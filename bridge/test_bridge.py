import asyncio
import json
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time
import types
import unittest
from pathlib import Path
from unittest import mock

import bikebridge
import ftms


class FakeClient:
    """Stands in for bleak's BleakClient, answering like an FTMS bike.

    refuse: opcode -> how many times to refuse it, and with what result
    (like a bike that refuses control until it's started). silent: never
    answers at all, like some bikes. echo_start: reports "started" before
    answering a start, as the Domyos does."""

    def __init__(self, target_features, refuse=None, silent=False, echo_start=False):
        self.feature = struct.pack("<II", 0x4000, target_features)
        self.is_connected = True
        self.handlers = {}
        self.writes = []
        self.refuse = dict(refuse or {})
        self.silent = silent
        self.echo_start = echo_start

    async def read_gatt_char(self, uuid):
        assert uuid == ftms.FEATURE
        return bytearray(self.feature)

    async def start_notify(self, uuid, callback):
        self.handlers[uuid] = callback

    async def write_gatt_char(self, uuid, data, response=False):
        assert uuid == ftms.CONTROL_POINT
        assert ftms.CONTROL_POINT in self.handlers, "indications not on yet"
        self.writes.append(bytes(data))
        if self.silent:
            return
        result = 0x01
        times, code = self.refuse.get(data[0], (0, 0x01))
        if times > 0:
            self.refuse[data[0]] = (times - 1, code)
            result = code
        if self.echo_start and data[0] == ftms.OP_START_OR_RESUME and result == 0x01:
            self.status(ftms.STATUS_STARTED_BY_USER)
        self.handlers[uuid](None, bytearray([0x80, data[0], result]))

    def notify(self, hexdata):
        self.handlers[ftms.INDOOR_BIKE_DATA](None, bytearray.fromhex(hexdata))

    def status(self, code):
        self.handlers[ftms.STATUS](None, bytearray([code]))


async def until(check, timeout=2.0):
    loop = asyncio.get_running_loop()
    end = loop.time() + timeout
    while not check():
        if loop.time() > end:
            raise AssertionError("timed out")
        await asyncio.sleep(0.01)


class Ride(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self._saved = (bikebridge.MIN_WRITE_GAP, bikebridge.CONTROL_RETRY,
                       bikebridge.ANSWER_WAIT)
        bikebridge.MIN_WRITE_GAP = 0
        bikebridge.CONTROL_RETRY = 0.05
        bikebridge.ANSWER_WAIT = 0.1

    def tearDown(self):
        (bikebridge.MIN_WRITE_GAP, bikebridge.CONTROL_RETRY,
         bikebridge.ANSWER_WAIT) = self._saved

    async def start(self, target_features, **fake):
        self.link = bikebridge.Link()
        self.sent = []
        self.link.send = lambda **msg: self.sent.append(msg)
        self.state = {}
        self.client = FakeClient(target_features, **fake)
        self.task = asyncio.create_task(
            bikebridge.ride(self.client, self.link, self.state))
        self.addAsyncCleanup(self.stop)

    async def stop(self):
        self.client.is_connected = False
        await asyncio.wait_for(self.task, 3)

    async def test_takes_control_then_starts_then_rides_the_hill(self):
        await self.start(1 << 13)
        self.link.datagram_received(b'{"grade": 5.5}', None)
        await until(lambda: len(self.client.writes) >= 3)
        self.assertEqual(self.client.writes[0], ftms.request_control())
        self.assertEqual(self.client.writes[1], ftms.start_or_resume())
        self.assertEqual(self.client.writes[-1], ftms.set_simulation(5.5))
        self.assertTrue(self.state["simulation"])
        self.assertFalse(self.state["erg"])

    async def test_readings_are_merged_across_split_notifications(self):
        await self.start(1 << 13)
        await until(lambda: len(self.client.writes) >= 2)
        self.client.notify("4400f609aa00c800")   # speed, cadence, power
        self.client.notify("41002c01")           # power only, "more data"
        self.assertEqual(self.sent[-1], {"type": "ride", "power": 300,
                                         "cadence": 85, "speed": 25.5})

    async def test_grade_is_not_sent_to_a_bike_that_cannot_ride_hills(self):
        await self.start(1 << 3)
        self.link.datagram_received(b'{"grade": 4}', None)
        await asyncio.sleep(0.1)
        self.assertEqual(len(self.client.writes), 2)
        self.link.datagram_received(b'{"power": 220}', None)
        await until(lambda: len(self.client.writes) == 3)
        self.assertEqual(self.client.writes[-1], ftms.set_target_power(220))
        self.assertTrue(self.state["erg"])

    async def test_keeps_asking_until_a_just_switched_on_bike_agrees(self):
        # Straight after power-on the bike refuses control, then refuses to
        # start: the bridge asks again until it agrees, then sends the hill.
        await self.start(1 << 13, refuse={
            ftms.OP_REQUEST_CONTROL: (2, 0x05),   # control not permitted
            ftms.OP_START_OR_RESUME: (1, 0x04),   # operation failed
        })
        self.link.datagram_received(b'{"grade": 3}', None)
        await until(lambda: self.client.writes[-1:] == [ftms.set_simulation(3)])
        control = ftms.request_control()
        go = ftms.start_or_resume()
        self.assertEqual(self.client.writes[:6], [control, control, control, go,
                                                  control, go])
        self.assertTrue(self.state["controlled"])

    async def test_no_commands_until_the_bike_agrees(self):
        await self.start(1 << 13, refuse={ftms.OP_REQUEST_CONTROL: (1000, 0x05)})
        self.link.datagram_received(b'{"grade": 3}', None)
        await asyncio.sleep(0.3)
        self.assertGreater(len(self.client.writes), 2)
        self.assertEqual(set(self.client.writes), {ftms.request_control()})
        self.assertFalse(self.state["controlled"])

    async def test_takes_control_again_when_the_bike_loses_it(self):
        await self.start(1 << 13)
        self.link.datagram_received(b'{"grade": 2}', None)
        await until(lambda: self.client.writes[-1:] == [ftms.set_simulation(2)])
        before = len(self.client.writes)
        for code in (ftms.STATUS_CONTROL_LOST, ftms.STATUS_RESET,
                     ftms.STATUS_STOPPED_BY_USER):
            self.client.status(code)
            await until(lambda: len(self.client.writes) >= before + 3)
            self.assertEqual(self.client.writes[before:before + 3], [
                ftms.request_control(), ftms.start_or_resume(), ftms.set_simulation(2)])
            self.assertTrue(self.state["controlled"])
            self.assertGreater(len(self.client.writes), before)
            before = len(self.client.writes)

    async def test_play_on_the_bike_is_answered_at_once(self):
        await self.start(1 << 13, refuse={ftms.OP_REQUEST_CONTROL: (1, 0x05)})
        bikebridge.CONTROL_RETRY = 60  # would wait a minute, but play is pressed
        await until(lambda: len(self.client.writes) == 1)
        self.client.status(ftms.STATUS_STARTED_BY_USER)
        await until(lambda: self.state.get("controlled"), timeout=1.0)

    async def test_the_bikes_report_of_our_own_start_is_not_play_pressed(self):
        # The Domyos reports "started" before it answers our start: that's
        # our start, not play pressed, so control isn't asked for twice.
        await self.start(1 << 13, echo_start=True)
        self.link.datagram_received(b'{"grade": 2}', None)
        await until(lambda: self.client.writes[-1:] == [ftms.set_simulation(2)])
        await asyncio.sleep(0.1)
        self.assertEqual(self.client.writes, [ftms.request_control(),
                                              ftms.start_or_resume(), ftms.set_simulation(2)])

    async def test_a_refused_command_retakes_control(self):
        await self.start(1 << 3)
        await until(lambda: self.state.get("controlled"))
        self.client.refuse[ftms.OP_SET_TARGET_POWER] = (1, 0x05)
        before = len(self.client.writes)
        self.link.datagram_received(b'{"power": 180}', None)
        await until(lambda: len(self.client.writes) >= before + 4)
        self.assertEqual(self.client.writes[before:before + 4], [
            ftms.set_target_power(180), ftms.request_control(),
            ftms.start_or_resume(), ftms.set_target_power(180)])

    async def test_a_bike_that_never_answers_still_gets_commands(self):
        await self.start(1 << 13, silent=True)
        self.link.datagram_received(b'{"grade": 4}', None)
        await until(lambda: self.client.writes[-1:] == [ftms.set_simulation(4)])
        self.assertEqual(self.client.writes[:2], [ftms.request_control(),
                                                  ftms.start_or_resume()])

    async def test_returns_when_the_bike_disconnects(self):
        await self.start(1 << 13)
        await until(lambda: len(self.client.writes) >= 2)
        self.client.is_connected = False
        await asyncio.wait_for(self.task, 2)


class LinkInput(unittest.TestCase):
    def test_ignores_junk_and_only_flags_real_changes(self):
        link = bikebridge.Link()
        for junk in (b"nope", b"[1]", b'{"grade": true}', b'{"grade": "3"}'):
            link.datagram_received(junk, None)
        self.assertEqual(link.target, {"grade": 0.0})
        self.assertFalse(link.changed.is_set())
        link.datagram_received(b'{"grade": 0}', None)
        self.assertFalse(link.changed.is_set())
        link.datagram_received(b'{"grade": 2}', None)
        self.assertTrue(link.changed.is_set())


class NoAdapter(unittest.IsolatedAsyncioTestCase):
    async def test_waits_instead_of_crashing_without_an_adapter(self):
        # With no adapter, BlueZ never starts and every scan fails. The bridge
        # used to crash on the first one and be restarted in a loop.
        scans = []

        class Scanner:
            @staticmethod
            async def find_device_by_filter(filterfunc, timeout):
                scans.append(timeout)
                raise RuntimeError("Failed to activate service 'org.bluez'")

        fake = types.ModuleType("bleak")
        fake.BleakScanner = Scanner
        fake.BleakClient = object
        state = {}
        with mock.patch.dict(sys.modules, {"bleak": fake}), \
                mock.patch.object(bikebridge, "ADAPTER_RETRY", 0.01):
            task = asyncio.create_task(bikebridge.run_bike(bikebridge.Link(), state, None))
            await until(lambda: len(scans) >= 3)
            self.assertFalse(task.done(), "still running")
            task.cancel()
        self.assertEqual(state["state"], "no_adapter")


class Reconnecting(unittest.IsolatedAsyncioTestCase):
    """A bike left connected to the computer's Bluetooth by a bridge that
    ended without disconnecting doesn't advertise, so a search can't find it:
    the bridge lets go of it, and then finds it."""

    def setUp(self):
        self.tmp = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.enterContext(mock.patch.object(bikebridge, "STATE_FILE", self.tmp / "bike"))
        self.events = []
        self.stale = False  # BlueZ holds a connection to the bike
        events = self.events
        test = self

        class Device:
            address = "AA:BB"
            name = "Domyos-Biking-1"

        class Client:
            def __init__(self, device, **kwargs):
                self.device = device

            async def __aenter__(self):
                events.append("connect")
                return self

            async def __aexit__(self, *exc):
                events.append("disconnect")

        class Scanner:
            @staticmethod
            async def find_device_by_filter(filterfunc, timeout):
                events.append("scan")
                await asyncio.sleep(0.01)
                return None if test.stale else Device()

        async def let_go_of(address):
            events.append("let go of " + address)
            was, test.stale = test.stale, False
            return was

        self.fake = types.ModuleType("bleak")
        self.fake.BleakClient = Client
        self.fake.BleakScanner = Scanner
        self.let_go_of = let_go_of

    async def run_until(self, check):
        async def ride(client, link, state):
            self.events.append("ride")
            await asyncio.sleep(3600)

        with mock.patch.dict(sys.modules, {"bleak": self.fake}), \
                mock.patch.object(bikebridge, "ride", ride), \
                mock.patch.object(bikebridge, "let_go_of", self.let_go_of):
            task = asyncio.create_task(bikebridge.run_bike(bikebridge.Link(), {}, None))
            await until(check)
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task

    async def test_a_bike_left_connected_is_let_go_of_and_found(self):
        bikebridge.remember("AA:BB")
        self.stale = True
        await self.run_until(lambda: "ride" in self.events)
        self.assertEqual(self.events[:4], ["scan", "let go of AA:BB", "scan", "connect"])

    async def test_nothing_is_disconnected_for_a_bike_never_seen(self):
        self.stale = True
        await self.run_until(lambda: self.events.count("scan") >= 3)
        self.assertEqual(set(self.events), {"scan"})

    async def test_trouble_with_bluez_doesnt_stop_the_search(self):
        bikebridge.remember("AA:BB")
        self.stale = True

        async def broken(address):
            raise RuntimeError("no system bus")

        self.let_go_of = broken
        await self.run_until(lambda: self.events.count("scan") >= 3)

    async def test_stopping_mid_ride_disconnects_the_bike(self):
        await self.run_until(lambda: "ride" in self.events)
        self.assertEqual(self.events[-1], "disconnect")


class LetGoOf(unittest.IsolatedAsyncioTestCase):
    """let_go_of() against a made-up BlueZ on D-Bus."""

    def setUp(self):
        self.calls = []
        calls = self.calls
        test = self
        self.connected = True

        class Variant:
            def __init__(self, value):
                self.value = value

        class Message:
            def __init__(self, **kw):
                self.__dict__.update(kw)

        class Reply:
            def __init__(self, body, error=False):
                self.body = body
                self.message_type = "error" if error else "return"

        class Bus:
            def __init__(self, bus_type):
                pass

            async def connect(self):
                return self

            async def call(self, msg):
                calls.append((msg.path, msg.member))
                if msg.member == "GetManagedObjects":
                    return Reply([{
                        "/org/bluez/hci0": {"org.bluez.Adapter1": {}},
                        "/org/bluez/hci0/dev_11_22": {"org.bluez.Device1": {
                            "Address": Variant("11:22"), "Connected": Variant(True)}},
                        "/org/bluez/hci0/dev_AA_BB": {"org.bluez.Device1": {
                            "Address": Variant("AA:BB"),
                            "Connected": Variant(test.connected)}},
                    }])
                return Reply([])

            def disconnect(self):
                calls.append("closed")

        dbus = types.ModuleType("dbus_fast")
        dbus.BusType = types.SimpleNamespace(SYSTEM="system")
        dbus.Message = Message
        dbus.MessageType = types.SimpleNamespace(ERROR="error")
        aio = types.ModuleType("dbus_fast.aio")
        aio.MessageBus = Bus
        self.enterContext(mock.patch.dict(sys.modules, {"dbus_fast": dbus, "dbus_fast.aio": aio}))

    async def test_disconnects_that_bike_only(self):
        self.assertTrue(await bikebridge.let_go_of("aa:bb"))
        self.assertEqual(self.calls, [("/", "GetManagedObjects"),
                                      ("/org/bluez/hci0/dev_AA_BB", "Disconnect"), "closed"])

    async def test_leaves_a_bike_that_isnt_connected(self):
        self.connected = False
        self.assertFalse(await bikebridge.let_go_of("AA:BB"))
        self.assertEqual(self.calls, [("/", "GetManagedObjects"), "closed"])


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class FakeModeOverUdp(unittest.IsolatedAsyncioTestCase):
    async def test_game_sees_a_rider_who_works_harder_uphill(self):
        game = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        game.bind(("127.0.0.1", 0))
        game.setblocking(False)
        self.addCleanup(game.close)
        bridge_port = free_port()
        args = bikebridge.parse_args([
            "--fake", "--fake-watts", "200",
            "--game-port", str(game.getsockname()[1]),
            "--bridge-port", str(bridge_port)])
        task = asyncio.create_task(bikebridge.main(args))
        await asyncio.sleep(0.1)
        game.sendto(b'{"grade": 10}', ("127.0.0.1", bridge_port))

        loop = asyncio.get_running_loop()
        messages = []
        end = loop.time() + 2.2
        while loop.time() < end:
            try:
                messages.append(json.loads(await asyncio.wait_for(
                    loop.sock_recv(game, 4096), end - loop.time())))
            except TimeoutError:
                break
        task.cancel()

        status = [m for m in messages if m["type"] == "status"]
        rides = [m for m in messages if m["type"] == "ride"][2:]
        self.assertTrue(status)
        self.assertEqual(status[-1]["state"], "connected")
        self.assertGreater(len(rides), 4)
        self.assertGreater(sum(m["power"] for m in rides) / len(rides), 300)


class Stopping(unittest.TestCase):
    def test_sigterm_ends_it_cleanly(self):
        # Docker stops it with SIGTERM, and it runs as process 1 there, which
        # the kernel sends no signal it has no handler for.
        proc = subprocess.Popen(
            [sys.executable, str(Path(bikebridge.__file__)), "--fake",
             "--game-port", str(free_port()), "--bridge-port", str(free_port())],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        time.sleep(1.0)
        proc.send_signal(signal.SIGTERM)
        out, _ = proc.communicate(timeout=5)
        self.assertEqual(proc.returncode, 0, out)
        self.assertNotIn("Traceback", out)


if __name__ == "__main__":
    unittest.main()
