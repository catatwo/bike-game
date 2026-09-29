#!/usr/bin/env python3
"""Relay an FTMS bike to the game over UDP on localhost.

bike -> game, JSON datagrams to 127.0.0.1:47810
    {"type": "status", "state": "searching" | "connected" | "no_adapter",
     "bike": name, "simulation": bool, "erg": bool,
     "controlled": bool}                                   every second
        (controlled: the bike has accepted control and started, so it
        takes the gradient and wattage; until then it's only read)
    {"type": "ride", "power": W, "cadence": rpm, "speed": km/h}  per reading
game -> bike, JSON datagrams to 127.0.0.1:47811
    {"grade": percent}   ride a hill (the bike sets its own resistance)
    {"power": watts}     hold a fixed wattage, for workouts

It never exits by itself: it searches until the bike is switched on, rides,
and goes back to searching when the bike goes away, so it can start with the
machine and simply wait. --fake stands in for the bike and a rider, so the
game can be worked on away from the bike.
"""

import argparse
import asyncio
import itertools
import json
import logging
import os
import random
import signal
import struct
from pathlib import Path

import ftms

GAME_PORT = 47810
BRIDGE_PORT = 47811
STATE_FILE = (Path(os.environ.get("XDG_STATE_HOME",
                                  Path.home() / ".local/state"))
              / "bike-game/bike-address")
MIN_WRITE_GAP = 0.5  # seconds between commands to the bike
CONTROL_RETRY = 3.0  # seconds between asks when the bike refuses control
ANSWER_WAIT = 3.0  # seconds to wait for the bike to answer a command
ADAPTER_RETRY = 15.0  # seconds between looks for a Bluetooth adapter
SHORT_LINK = 30.0  # a connection that ends sooner than this counts as dropped...
DROPS_BEFORE_RESTART = 3  # ...and this many in a row restart the computer's Bluetooth,
RESTART_GAP = 300.0  # at most this often (seconds)
RECONNECT_GAP = 2.0  # seconds between one connection ending and the next search

log = logging.getLogger("bikebridge")


class Link(asyncio.DatagramProtocol):
    """The game's side: sends it readings, keeps its latest request."""

    def __init__(self, game_port: int = GAME_PORT):
        self.game = ("127.0.0.1", game_port)
        self.transport = None
        self.target = {"grade": 0.0}
        self.changed = asyncio.Event()

    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data, addr):
        try:
            msg = json.loads(data)
        except ValueError:
            return
        if not isinstance(msg, dict):
            return
        for key in ("grade", "power"):
            value = msg.get(key)
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                if self.target != {key: float(value)}:
                    self.target = {key: float(value)}
                    self.changed.set()

    def error_received(self, exc):
        pass  # the game isn't listening yet; readings are simply dropped

    def send(self, **msg):
        if self.transport:
            self.transport.sendto(json.dumps(msg).encode(), self.game)


async def heartbeat(link: Link, state: dict):
    while True:
        link.send(type="status", **state)
        await asyncio.sleep(1)


def command_for(target: dict, features: ftms.Features) -> bytes | None:
    if "grade" in target and features.simulation:
        return ftms.set_simulation(target["grade"])
    if "power" in target and features.target_power:
        return ftms.set_target_power(target["power"])
    return None


async def ride(client, link: Link, state: dict):
    """One connected session, until the bike disconnects. `client` is a
    bleak BleakClient, or anything with the same four members.

    The bike only takes commands once it has granted control and started
    (the same as pressing play on its console). Straight after power-on it
    may refuse both, so the bridge keeps asking until it agrees, and asks
    again whenever the bike reports it was reset, stopped or lost control,
    or refuses a command."""
    features = ftms.parse_features(await client.read_gatt_char(ftms.FEATURE))
    state["simulation"] = features.simulation
    state["erg"] = features.target_power
    state["controlled"] = False
    log.info("bike can ride hills: %s, hold a wattage: %s",
             features.simulation, features.target_power)

    reading = {"power": None, "cadence": None, "speed": None}
    answers: dict[int, asyncio.Future] = {}
    lost = asyncio.Event()  # the bike needs taking control of again
    asking = False  # a request for control or to start is on its way

    def on_data(_, data):
        try:
            d = ftms.parse_bike_data(bytes(data))
        except struct.error:
            log.warning("short bike data packet: %s", bytes(data).hex())
            return
        for key, value in (("power", d.power_w), ("cadence", d.cadence_rpm),
                           ("speed", d.speed_kmh)):
            if value is not None:
                reading[key] = value
        log.debug("reading %s", reading)
        link.send(type="ride", **reading)

    def on_control(_, data):
        response = ftms.parse_response(bytes(data))
        if response is None:
            return
        op, result = response
        waiting = answers.pop(op, None)
        if waiting and not waiting.done():
            waiting.set_result(result)
        if result == "control not permitted" and state["controlled"]:
            log.warning("bike stopped taking commands (0x%02x refused)", op)
            state["controlled"] = False
            lost.set()

    def on_status(_, data):
        status = ftms.parse_status(bytes(data))
        if status is None:
            return
        code, meaning = status
        log.info("bike: %s (%s)", meaning, bytes(data).hex())
        if code in (ftms.STATUS_RESET, ftms.STATUS_STOPPED_BY_USER,
                    ftms.STATUS_STOPPED_BY_SAFETY_KEY, ftms.STATUS_CONTROL_LOST):
            state["controlled"] = False
            lost.set()
        elif (code == ftms.STATUS_STARTED_BY_USER and not state["controlled"]
                and not asking):
            # Play was pressed while it was refusing: ask again now. (While
            # asking, it's the bike reporting our own start.)
            lost.set()

    last_training = [""]

    def on_training(_, data):
        state_now = ftms.parse_training_status(bytes(data))
        if state_now and state_now != last_training[0]:
            last_training[0] = state_now
            log.info("bike's training state: %s (%s)", state_now, bytes(data).hex())

    async def command(data: bytes) -> str:
        """Writes a command and waits for the bike's answer: its result,
        or "no answer" from a bike that doesn't reply."""
        waiting = asyncio.get_running_loop().create_future()
        answers[data[0]] = waiting
        try:
            await client.write_gatt_char(ftms.CONTROL_POINT, data, response=True)
            return await asyncio.wait_for(waiting, ANSWER_WAIT)
        except TimeoutError:
            return "no answer"
        except Exception as exc:  # bleak raises many kinds
            return f"write failed: {exc}"
        finally:
            answers.pop(data[0], None)

    async def take_control():
        """Asks for control, then to start, until the bike agrees (or doesn't
        answer at all, which some bikes don't: then carry on as if it did)."""
        nonlocal asking
        told = ""
        while client.is_connected:
            lost.clear()
            asking = True
            try:
                got = await command(ftms.request_control())
                log.info("asked the bike for control: %s", got)
                if got in ("success", "no answer"):
                    got = await command(ftms.start_or_resume())
                    log.info("asked the bike to start: %s", got)
            finally:
                asking = False
            if got in ("success", "no answer"):
                state["controlled"] = True
                log.info("bike accepted control%s", "" if got == "success" else " (it doesn't answer)")
                link.changed.set()  # send whatever the game already asked for
                return
            if got != told:
                told = got
                log.warning("bike refused control (%s); asking again every %gs, "
                            "or press play on the bike", got, CONTROL_RETRY)
            try:
                await asyncio.wait_for(lost.wait(), CONTROL_RETRY)
            except TimeoutError:
                pass

    # Indications must be on before the first write, or the bike can't answer.
    await client.start_notify(ftms.CONTROL_POINT, on_control)
    await client.start_notify(ftms.INDOOR_BIKE_DATA, on_data)
    for uuid, handler, what in ((ftms.STATUS, on_status, "fitness machine status"),
                                (ftms.TRAINING_STATUS, on_training, "training status")):
        try:
            await client.start_notify(uuid, handler)
        except Exception as exc:  # a bike without that characteristic
            log.info("no %s from this bike: %s", what, exc)

    await take_control()
    unsupported = set()
    while client.is_connected:
        if lost.is_set():
            await take_control()
            continue
        try:
            await asyncio.wait_for(link.changed.wait(), 1.0)
        except TimeoutError:
            continue
        link.changed.clear()
        command_bytes = command_for(link.target, features)
        if command_bytes is None:
            kind = next(iter(link.target))
            if kind not in unsupported:
                unsupported.add(kind)
                log.warning("bike doesn't support %s commands", kind)
            continue
        got = await command(command_bytes)
        if got not in ("success", "no answer", "control not permitted"):
            log.warning("bike refused command 0x%02x: %s", command_bytes[0], got)
        await asyncio.sleep(MIN_WRITE_GAP)


def remembered_address() -> str | None:
    try:
        return STATE_FILE.read_text().strip() or None
    except OSError:
        return None


def remember(address: str):
    try:
        STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        STATE_FILE.write_text(address + "\n")
    except OSError as exc:
        log.warning("can't remember the bike's address: %s", exc)


async def let_go_of(address: str) -> bool:
    """Disconnects the bike at `address` if the computer's Bluetooth (BlueZ)
    still holds a connection to it. True when it did.

    A bridge that ended without disconnecting (killed, or crashed) leaves
    the bike connected to BlueZ with nothing using it. A connected bike
    doesn't advertise, so a search never finds it, and neither does
    connecting by address: bleak searches for the address first."""
    from dbus_fast import BusType, Message, MessageType
    from dbus_fast.aio import MessageBus

    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    try:
        reply = await bus.call(Message(
            destination="org.bluez", path="/",
            interface="org.freedesktop.DBus.ObjectManager",
            member="GetManagedObjects"))
        if reply.message_type == MessageType.ERROR:
            return False
        for path, interfaces in reply.body[0].items():
            device = interfaces.get("org.bluez.Device1")
            if (not device or device["Address"].value.upper() != address.upper()
                    or not device["Connected"].value):
                continue
            reply = await bus.call(Message(
                destination="org.bluez", path=path,
                interface="org.bluez.Device1", member="Disconnect"))
            if reply.message_type == MessageType.ERROR:
                log.warning("couldn't disconnect %s: %s", address, reply.body)
                return False
            return True
        return False
    finally:
        bus.disconnect()


async def restart_bluetooth(bike: str) -> str:
    """Switches the computer's Bluetooth adapter off and on. A controller can
    come up (from a cold start, seen on an Intel 7265) in a state where every
    link drops within seconds of connecting, whatever is sent over it, and
    that clears it. Never while anything but the bike is connected to it
    (headphones, a keyboard): returns why not, or "" when it's done."""
    from dbus_fast import BusType, Message, MessageType, Variant
    from dbus_fast.aio import MessageBus

    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    try:
        reply = await bus.call(Message(
            destination="org.bluez", path="/",
            interface="org.freedesktop.DBus.ObjectManager",
            member="GetManagedObjects"))
        if reply.message_type == MessageType.ERROR:
            return f"BlueZ didn't answer: {reply.body}"
        objects = reply.body[0]
        adapter = ""
        for path, interfaces in objects.items():
            device = interfaces.get("org.bluez.Device1")
            if device and device["Address"].value.upper() == bike.upper():
                adapter = device["Adapter"].value
        if not adapter:
            return "the bike isn't known to BlueZ"
        others = [interfaces["org.bluez.Device1"]["Name"].value
                  if "Name" in interfaces["org.bluez.Device1"] else path
                  for path, interfaces in objects.items()
                  if "org.bluez.Device1" in interfaces
                  and interfaces["org.bluez.Device1"]["Adapter"].value == adapter
                  and interfaces["org.bluez.Device1"]["Connected"].value
                  and interfaces["org.bluez.Device1"]["Address"].value.upper() != bike.upper()]
        if others:
            return "other devices are connected to it: " + ", ".join(others)
        for on in (False, True):
            reply = await bus.call(Message(
                destination="org.bluez", path=adapter,
                interface="org.freedesktop.DBus.Properties", member="Set",
                signature="ssv", body=["org.bluez.Adapter1", "Powered", Variant("b", on)]))
            if reply.message_type == MessageType.ERROR:
                return f"couldn't switch it {'on' if on else 'off'}: {reply.body}"
            await asyncio.sleep(2)
        return ""
    finally:
        bus.disconnect()


async def run_bike(link: Link, state: dict, name: str | None):
    from bleak import BleakClient, BleakScanner

    loop = asyncio.get_running_loop()
    problem = ""
    drops = 0
    restarted = -RESTART_GAP
    while True:
        state.update(state="searching", bike=None, simulation=False,
                     erg=False, controlled=False)
        known = remembered_address()

        def is_bike(device, adv):
            if known and device.address == known:
                return True
            if name:
                return name.lower() in (device.name or "").lower()
            return ftms.SERVICE in adv.service_uuids

        try:
            device = await BleakScanner.find_device_by_filter(is_bike, timeout=10)
        except Exception as exc:  # no adapter, or BlueZ isn't running (yet)
            if str(exc) != problem:
                problem = str(exc)
                log.warning("can't scan for the bike (no Bluetooth adapter?): %s", exc)
            state.update(state="no_adapter")
            await asyncio.sleep(ADAPTER_RETRY)
            continue
        if problem:
            log.info("Bluetooth works again")
            problem = ""
        if device is None:
            if known:
                try:
                    if await let_go_of(known):
                        log.info("the bike was still connected to this computer, "
                                 "with nothing using it: disconnected it, so it "
                                 "can be found")
                except Exception as exc:  # D-Bus trouble: keep searching
                    log.debug("can't check BlueZ for %s: %s", known, exc)
            continue
        log.info("found %s (%s)", device.name, device.address)
        began = loop.time()
        try:
            async with BleakClient(device) as client:
                remember(device.address)
                state.update(state="connected",
                             bike=device.name or device.address)
                await ride(client, link, state)
            log.info("the bike disconnected, after %.0f s", loop.time() - began)
        except Exception as exc:  # bleak and D-Bus raise many kinds
            log.warning("bike connection ended: %s", exc)
        drops = drops + 1 if loop.time() - began < SHORT_LINK else 0
        if drops >= DROPS_BEFORE_RESTART and loop.time() - restarted >= RESTART_GAP:
            drops = 0
            restarted = loop.time()
            try:
                why = await restart_bluetooth(device.address)
            except Exception as exc:  # D-Bus trouble: keep going as we are
                why = str(exc)
            if why:
                log.warning("the bike keeps dropping the connection, but this "
                            "computer's Bluetooth can't be restarted: %s", why)
            else:
                log.warning("the bike kept dropping the connection within "
                            "seconds: switched this computer's Bluetooth off "
                            "and on")
        await asyncio.sleep(RECONNECT_GAP)


async def run_fake(link: Link, state: dict, watts: float):
    """A steady rider who pushes harder uphill and holds any ERG target."""
    state.update(state="connected", bike="fake bike", simulation=True,
                 erg=True, controlled=True)
    while True:
        grade = link.target.get("grade", 0.0)
        power = link.target.get("power", watts + 15 * grade)
        link.send(type="ride",
                  power=max(0, round(power + random.gauss(0, 8))),
                  cadence=max(0.0, round(88 - 1.5 * grade
                                         + random.gauss(0, 2), 1)),
                  speed=None)
        await asyncio.sleep(0.25)


async def hill_test(link: Link):
    """Step through a few gradients, so the resistance can be felt changing
    without the game."""
    for grade in itertools.cycle((0, 4, 8, 4)):
        log.info("hill test: %s%% gradient for 20 seconds", grade)
        link.target = {"grade": float(grade)}
        link.changed.set()
        await asyncio.sleep(20)


async def main(args):
    link = Link(args.game_port)
    loop = asyncio.get_running_loop()
    # Docker stops the bridge with SIGTERM. The bridge is process 1 in its
    # container, which the kernel sends no signal it has no handler for, so
    # without this it was killed 10 s later instead, leaving the bike
    # connected to the computer's Bluetooth with nothing using it (and not
    # advertising, so not found again). Ending cleanly disconnects it.
    loop.add_signal_handler(signal.SIGTERM, asyncio.current_task().cancel)
    transport, _ = await loop.create_datagram_endpoint(
        lambda: link, local_addr=("127.0.0.1", args.bridge_port))
    state = {"state": "searching", "bike": None, "simulation": False,
             "erg": False}
    beat = asyncio.create_task(heartbeat(link, state))
    hills = asyncio.create_task(hill_test(link)) if args.hill_test else None
    try:
        if args.fake:
            await run_fake(link, state, args.fake_watts)
        else:
            await run_bike(link, state, args.name)
    finally:
        loop.remove_signal_handler(signal.SIGTERM)
        beat.cancel()
        if hills:
            hills.cancel()
        transport.close()


def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="Relay an FTMS bike to the game over UDP on localhost.")
    p.add_argument("--fake", action="store_true",
                   help="simulate a bike and rider instead of using Bluetooth")
    p.add_argument("--fake-watts", type=float, default=180,
                   help="the fake rider's power on the flat (default 180)")
    p.add_argument("--name", help="match the bike by name instead of by the "
                   "FTMS service it advertises")
    p.add_argument("--game-port", type=int, default=GAME_PORT)
    p.add_argument("--bridge-port", type=int, default=BRIDGE_PORT)
    p.add_argument("--hill-test", action="store_true",
                   help="without the game: change the gradient every 20 "
                   "seconds (0, 4, 8, 4%%) to feel the resistance change")
    p.add_argument("-v", "--verbose", action="store_true",
                   help="also print every reading from the bike")
    return p.parse_args(argv)


if __name__ == "__main__":
    args = parse_args()
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    if args.verbose:
        log.setLevel(logging.DEBUG)  # ours only; bleak's debug is a flood
    try:
        asyncio.run(main(args))
    except (KeyboardInterrupt, asyncio.CancelledError):
        pass
