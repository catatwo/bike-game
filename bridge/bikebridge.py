#!/usr/bin/env python3
"""Relay an FTMS bike to the game over UDP on localhost.

bike -> game, JSON datagrams to 127.0.0.1:47810
    {"type": "status", "state": "searching" | "connected" | "no_adapter",
     "bike": name, "simulation": bool, "erg": bool}         every second
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
import struct
from pathlib import Path

import ftms

GAME_PORT = 47810
BRIDGE_PORT = 47811
STATE_FILE = (Path(os.environ.get("XDG_STATE_HOME",
                                  Path.home() / ".local/state"))
              / "bike-game/bike-address")
MIN_WRITE_GAP = 0.5  # seconds between commands to the bike
ADAPTER_RETRY = 15.0  # seconds between looks for a Bluetooth adapter

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
    bleak BleakClient, or anything with the same four members."""
    features = ftms.parse_features(await client.read_gatt_char(ftms.FEATURE))
    state["simulation"] = features.simulation
    state["erg"] = features.target_power
    log.info("bike can ride hills: %s, hold a wattage: %s",
             features.simulation, features.target_power)

    reading = {"power": None, "cadence": None, "speed": None}

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
        if response and response[1] != "success":
            log.warning("bike refused command 0x%02x: %s", *response)

    # Indications must be on before the first write, or the bike can't answer.
    await client.start_notify(ftms.CONTROL_POINT, on_control)
    await client.start_notify(ftms.INDOOR_BIKE_DATA, on_data)
    await client.write_gatt_char(ftms.CONTROL_POINT, ftms.request_control(),
                                 response=True)
    await client.write_gatt_char(ftms.CONTROL_POINT, ftms.start_or_resume(),
                                 response=True)

    link.changed.set()  # send whatever the game already asked for
    unsupported = set()
    while client.is_connected:
        try:
            await asyncio.wait_for(link.changed.wait(), 1.0)
        except TimeoutError:
            continue
        link.changed.clear()
        command = command_for(link.target, features)
        if command is None:
            kind = next(iter(link.target))
            if kind not in unsupported:
                unsupported.add(kind)
                log.warning("bike doesn't support %s commands", kind)
            continue
        await client.write_gatt_char(ftms.CONTROL_POINT, command, response=True)
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


async def run_bike(link: Link, state: dict, name: str | None):
    from bleak import BleakClient, BleakScanner

    problem = ""
    while True:
        state.update(state="searching", bike=None, simulation=False,
                     erg=False)
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
            continue
        log.info("found %s (%s)", device.name, device.address)
        try:
            async with BleakClient(device) as client:
                remember(device.address)
                state.update(state="connected",
                             bike=device.name or device.address)
                await ride(client, link, state)
        except Exception as exc:  # bleak and D-Bus raise many kinds
            log.warning("bike connection ended: %s", exc)
        await asyncio.sleep(2)


async def run_fake(link: Link, state: dict, watts: float):
    """A steady rider who pushes harder uphill and holds any ERG target."""
    state.update(state="connected", bike="fake bike", simulation=True,
                 erg=True)
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
    except KeyboardInterrupt:
        pass
