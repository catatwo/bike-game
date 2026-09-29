import asyncio
import json
import socket
import struct
import sys
import types
import unittest
from unittest import mock

import bikebridge
import ftms


class FakeClient:
    """Stands in for bleak's BleakClient, answering like an FTMS bike.

    refuse: opcode -> how many times to refuse it, and with what result
    (like a bike that refuses control until it's started). silent: never
    answers at all, like some bikes."""

    def __init__(self, target_features, refuse=None, silent=False):
        self.feature = struct.pack("<II", 0x4000, target_features)
        self.is_connected = True
        self.handlers = {}
        self.writes = []
        self.refuse = dict(refuse or {})
        self.silent = silent

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


if __name__ == "__main__":
    unittest.main()
