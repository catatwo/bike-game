"""Bluetooth FTMS (Fitness Machine Service) encoding and decoding.

Pure byte handling with no Bluetooth in it, so it can be tested without a
bike. Layouts follow the FTMS 1.0 specification; every multi-byte field is
little-endian.
"""

import struct
from dataclasses import dataclass


def _uuid(short: int) -> str:
    return f"0000{short:04x}-0000-1000-8000-00805f9b34fb"


SERVICE = _uuid(0x1826)
FEATURE = _uuid(0x2ACC)
INDOOR_BIKE_DATA = _uuid(0x2AD2)
CONTROL_POINT = _uuid(0x2AD9)

OP_REQUEST_CONTROL = 0x00
OP_SET_TARGET_POWER = 0x05
OP_START_OR_RESUME = 0x07
OP_SET_SIMULATION = 0x11
OP_RESPONSE = 0x80

RESULTS = {
    0x01: "success",
    0x02: "not supported",
    0x03: "invalid parameter",
    0x04: "operation failed",
    0x05: "control not permitted",
}


@dataclass
class BikeData:
    """One Indoor Bike Data notification. None: the bike didn't send it."""

    speed_kmh: float | None = None
    cadence_rpm: float | None = None
    distance_m: int | None = None
    resistance: int | None = None
    power_w: int | None = None
    heart_rate: int | None = None
    elapsed_s: int | None = None


def parse_bike_data(data: bytes) -> BikeData:
    (flags,) = struct.unpack_from("<H", data, 0)
    pos = 2
    out = BikeData()

    def take(fmt: str) -> tuple:
        nonlocal pos
        values = struct.unpack_from("<" + fmt, data, pos)
        pos += struct.calcsize("<" + fmt)
        return values

    # Bit 0 is "More Data", and it is inverted: when it is SET, speed is
    # absent. Bikes that split one reading over two notifications do that.
    if not flags & 0x0001:
        out.speed_kmh = take("H")[0] / 100
    if flags & 0x0002:
        take("H")  # average speed
    if flags & 0x0004:
        out.cadence_rpm = take("H")[0] / 2
    if flags & 0x0008:
        take("H")  # average cadence
    if flags & 0x0010:
        low, high = take("HB")
        out.distance_m = low | high << 16
    if flags & 0x0020:
        out.resistance = take("h")[0]
    if flags & 0x0040:
        out.power_w = take("h")[0]
    if flags & 0x0080:
        take("h")  # average power
    if flags & 0x0100:
        take("HHB")  # energy: total, per hour, per minute
    if flags & 0x0200:
        out.heart_rate = take("B")[0]
    if flags & 0x0400:
        take("B")  # metabolic equivalent
    if flags & 0x0800:
        out.elapsed_s = take("H")[0]
    return out


@dataclass
class Features:
    machine: int
    target: int

    @property
    def simulation(self) -> bool:
        """Can ride a hill: takes a grade and sets the resistance itself."""
        return bool(self.target & 1 << 13)

    @property
    def target_power(self) -> bool:
        """Can hold a fixed wattage (ERG mode)."""
        return bool(self.target & 1 << 3)


def parse_features(data: bytes) -> Features:
    return Features(*struct.unpack_from("<II", data, 0))


def _clamp(value: int, low: int, high: int) -> int:
    return max(low, min(high, value))


def request_control() -> bytes:
    return bytes([OP_REQUEST_CONTROL])


def start_or_resume() -> bytes:
    return bytes([OP_START_OR_RESUME])


def set_simulation(grade_pct: float, wind_mps: float = 0.0,
                   crr: float = 0.004, cw: float = 0.51) -> bytes:
    """Ride a hill. grade_pct is signed (-5.5 is 5.5% downhill); crr and cw
    are the rolling and wind resistance the bike should assume."""
    return struct.pack(
        "<BhhBB",
        OP_SET_SIMULATION,
        _clamp(round(wind_mps * 1000), -32768, 32767),
        _clamp(round(grade_pct * 100), -32768, 32767),
        _clamp(round(crr * 10000), 0, 255),
        _clamp(round(cw * 100), 0, 255),
    )


def set_target_power(watts: float) -> bytes:
    return struct.pack("<Bh", OP_SET_TARGET_POWER,
                       _clamp(round(watts), -32768, 32767))


def parse_response(data: bytes) -> tuple[int, str] | None:
    """(request opcode, result) from a control point indication, or None
    when it isn't a response."""
    if len(data) < 3 or data[0] != OP_RESPONSE:
        return None
    return data[1], RESULTS.get(data[2], f"unknown result 0x{data[2]:02x}")
