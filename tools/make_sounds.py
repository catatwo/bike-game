#!/usr/bin/env python3
"""Make every sound the game uses, from nothing but code: two synthwave music
loops, wind and tyre noise, and the blips, beeps and chimes.

    python3 tools/make_sounds.py game/sounds

Standard library only, and seeded, so every run gives the same files. The
game image runs it at build time; the WAVs aren't kept in git.
"""

import array
import math
import os
import random
import sys
import wave

RATE = 32000
TABLE = 2048
random.seed(1)


# --- building blocks ---------------------------------------------------------

def _table(harmonics):
    """One band-limited cycle: harmonics is [(k, amplitude), ...]."""
    t = [0.0] * TABLE
    for k, a in harmonics:
        for i in range(TABLE):
            t[i] += a * math.sin(2 * math.pi * k * i / TABLE)
    peak = max(abs(x) for x in t) or 1.0
    return [x / peak for x in t]


SAW_LOW = _table([(k, 1 / k) for k in range(1, 25)])  # bass and pads
SAW_HIGH = _table([(k, 1 / k) for k in range(1, 9)])
SQUARE = _table([(k, 1 / k) for k in range(1, 14, 2)])  # the arpeggio
SINE = _table([(1, 1.0)])


def note_hz(name):
    """'A2' -> 110.0. Sharps as 'C#4'."""
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4,
             "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[pitch] + 12 * (octave - 4)) / 12)


def tone(buf, start, length, hz, table, amp, attack=0.005, decay=None,
         release=0.02, detune=1.0):
    """Add one note to buf: attack, then either an exponential decay (time
    constant `decay`, seconds) or a hold, then a release."""
    i0 = int(start * RATE)
    n = int((length + release) * RATE)
    step = hz * detune * TABLE / RATE
    phase = random.random() * TABLE
    a_n = max(1, int(attack * RATE))
    r_start = int(length * RATE)
    r_n = max(1, int(release * RATE))
    k_decay = math.exp(-1.0 / (decay * RATE)) if decay else 1.0
    env_d = 1.0
    end = min(len(buf), i0 + n)
    for i in range(max(0, i0), end):
        j = i - i0
        env = j / a_n if j < a_n else 1.0
        env *= env_d
        env_d *= k_decay
        if j >= r_start:
            env *= max(0.0, 1.0 - (j - r_start) / r_n)
        buf[i] += amp * env * table[int(phase) & (TABLE - 1)]
        phase += step


def lowpass(buf, cutoff):
    a = 1.0 - math.exp(-2 * math.pi * cutoff / RATE)
    y = 0.0
    for i in range(len(buf)):
        y += a * (buf[i] - y)
        buf[i] = y


def highpass(buf, cutoff):
    a = 1.0 - math.exp(-2 * math.pi * cutoff / RATE)
    low = 0.0
    for i in range(len(buf)):
        low += a * (buf[i] - low)
        buf[i] -= low


def echo(buf, seconds, feedback):
    d = int(seconds * RATE)
    for i in range(d, len(buf)):
        buf[i] += buf[i - d] * feedback


def mix(into, other, gain=1.0):
    for i in range(min(len(into), len(other))):
        into[i] += other[i] * gain


def kick(buf, start, amp=0.9):
    i0 = int(start * RATE)
    phase = 0.0
    for j in range(int(0.28 * RATE)):
        if i0 + j >= len(buf):
            break
        t = j / RATE
        hz = 45 + 110 * math.exp(-t * 28)
        phase += hz / RATE
        buf[i0 + j] += amp * math.exp(-t * 9) * math.sin(2 * math.pi * phase)


def noise_hit(buf, start, length, amp, decay):
    i0 = int(start * RATE)
    for j in range(int(length * RATE)):
        if i0 + j >= len(buf):
            break
        buf[i0 + j] += amp * math.exp(-j / RATE / decay) * (random.random() * 2 - 1)


def snare(buf, start):
    part = [0.0] * int(0.4 * RATE)
    noise_hit(part, 0.0, 0.4, 0.5, 0.11)
    highpass(part, 900)
    tone(part, 0.0, 0.08, 185, SINE, 0.35, decay=0.05)
    i0 = int(start * RATE)
    for j, x in enumerate(part):
        if i0 + j < len(buf):
            buf[i0 + j] += x


def hat(buf, start, amp=0.12):
    part = [0.0] * int(0.06 * RATE)
    noise_hit(part, 0.0, 0.06, amp, 0.018)
    highpass(part, 6000)
    i0 = int(start * RATE)
    for j, x in enumerate(part):
        if i0 + j < len(buf):
            buf[i0 + j] += x


def finish(buf, peak=0.8):
    for i in range(len(buf)):
        buf[i] = math.tanh(buf[i] * 1.2)
    top = max(abs(x) for x in buf) or 1.0
    return [x * peak / top for x in buf]


def write(path, buf):
    data = array.array("h", (int(max(-1.0, min(1.0, x)) * 32767) for x in buf))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def loop(render, seconds, fade=0.03):
    """A seamless loop. Render three and keep the middle one, so echoes and
    releases from the loop before are already in its start. What really
    follows its end is the third loop's start, which differs slightly (notes
    start at random phases), so the first few milliseconds are faded in from
    that: the wrap-around is then exactly continuous."""
    buf = render(3 * seconds)
    n = int(seconds * RATE)
    out = buf[n:2 * n]
    f = int(fade * RATE)
    for i in range(f):
        k = i / f
        out[i] = buf[2 * n + i] * (1 - k) + out[i] * k
    return out


# --- music -------------------------------------------------------------------

RIDE_CHORDS = [["A2", "A3", "C4", "E4"], ["F2", "F3", "A3", "C4"],
               ["C3", "G3", "C4", "E4"], ["G2", "G3", "B3", "D4"]]


def ride_music(total):
    bpm = 110
    beat = 60 / bpm
    bar = 4 * beat
    n = int(total * RATE)
    out, pad, arp = [0.0] * n, [0.0] * n, [0.0] * n
    t = 0.0
    while t < total:
        for c, chord in enumerate(RIDE_CHORDS):
            start = t + c * 2 * bar
            if start >= total:
                break
            root = note_hz(chord[0])
            # Bass: eighth notes, jumping the octave on the off-beats.
            for e in range(16):
                hz = root * (2 if e % 4 == 3 else 1)
                tone(out, start + e * beat / 2, beat / 2 * 0.8, hz, SAW_LOW, 0.32,
                     decay=0.18, release=0.03)
            # Pad: the chord held for two bars, two detuned voices a note.
            for name in chord[1:]:
                for det in (0.997, 1.003):
                    tone(pad, start, 2 * bar - 0.1, note_hz(name), SAW_LOW, 0.07,
                         attack=0.4, release=0.5, detune=det)
            # Arpeggio: sixteenths up and down the chord, an octave up.
            notes = [note_hz(x) * 2 for x in chord[1:]] + [note_hz(chord[1]) * 4]
            order = [0, 1, 2, 3, 2, 1]
            for s in range(32):
                hz = notes[order[s % len(order)]]
                tone(arp, start + s * beat / 4, beat / 4 * 0.6, hz, SQUARE, 0.11,
                     decay=0.09, release=0.02)
        t += 8 * bar
    lowpass(pad, 1400)
    lowpass(arp, 3500)
    echo(arp, 3 * beat / 4, 0.35)
    mix(out, pad)
    mix(out, arp)
    b = 0.0
    while b < total:
        kick(out, b)
        if int(round(b / beat)) % 2 == 1:
            snare(out, b)
        hat(out, b + beat / 2)
        b += beat
    return finish(out, 0.75)


MENU_CHORDS = [["A2", "C4", "E4", "A4"], ["E2", "B3", "E4", "G4"],
               ["F2", "A3", "C4", "F4"], ["G2", "B3", "D4", "G4"]]


def menu_music(total):
    bpm = 84
    beat = 60 / bpm
    bar = 4 * beat
    n = int(total * RATE)
    out, pad, arp = [0.0] * n, [0.0] * n, [0.0] * n
    t = 0.0
    while t < total:
        for c, chord in enumerate(MENU_CHORDS):
            start = t + c * 2 * bar
            if start >= total:
                break
            tone(out, start, 2 * bar - 0.2, note_hz(chord[0]), SINE, 0.35,
                 attack=0.3, release=0.6)
            for name in chord[1:]:
                for det in (0.996, 1.004):
                    tone(pad, start, 2 * bar - 0.1, note_hz(name), SAW_LOW, 0.06,
                         attack=1.2, release=1.2, detune=det)
            notes = [note_hz(x) * 2 for x in chord[1:]]
            for s in range(16):
                hz = notes[(s * 2 + s // 4) % len(notes)]
                tone(arp, start + s * beat / 2, beat / 2 * 0.5, hz, SINE, 0.12,
                     decay=0.25, release=0.05)
        t += 8 * bar
    lowpass(pad, 900)
    echo(arp, 3 * beat / 4, 0.45)
    mix(out, pad)
    mix(out, arp)
    return finish(out, 0.6)


# --- road noise --------------------------------------------------------------

def crossfade_loop(buf, fade):
    """Make buf loop without a click: blend its end into its start."""
    n = int(fade * RATE)
    body = buf[:len(buf) - n]
    for i in range(n):
        k = i / n
        body[i] = body[i] * math.sqrt(k) + buf[len(buf) - n + i] * math.sqrt(1 - k)
    return body


def wind(seconds=6.0):
    n = int((seconds + 1.0) * RATE)
    buf = [random.random() * 2 - 1 for _ in range(n)]
    lowpass(buf, 700)
    lowpass(buf, 900)
    for i in range(n):
        t = i / RATE
        buf[i] *= 0.75 + 0.25 * math.sin(2 * math.pi * t / 3.5) * math.sin(2 * math.pi * t / 1.3)
    return finish(crossfade_loop(buf, 1.0), 0.7)


def tyres(seconds=3.0):
    n = int((seconds + 0.5) * RATE)
    buf = [0.0] * n
    brown = 0.0
    for i in range(n):
        brown = 0.995 * brown + 0.05 * (random.random() * 2 - 1)
        buf[i] = brown + 0.15 * math.sin(2 * math.pi * 62 * i / RATE)
    lowpass(buf, 400)
    return finish(crossfade_loop(buf, 0.5), 0.6)


# --- effects -----------------------------------------------------------------

def effect(seconds, notes):
    """notes: [(start, length, hz, table, amp, decay), ...]"""
    buf = [0.0] * int(seconds * RATE)
    for start, length, hz, table, amp, dec in notes:
        tone(buf, start, length, hz, table, amp, decay=dec, release=0.02)
    return finish(buf, 0.7)


def effects():
    c5, e5, g5, c6 = (note_hz(x) for x in ("C5", "E5", "G5", "C6"))
    fanfare = [(i * 0.11, 0.12, hz, SQUARE, 0.4, 0.12) for i, hz in enumerate((c5, e5, g5))]
    fanfare += [(0.33, 1.1, hz, SAW_HIGH, 0.25, 0.6) for hz in (c5, e5, g5, c6)]
    # Two octaves of the C major chord, fast, an octave up: C6 E6 G6 C7 E7 G7.
    sparkle = [(i * 0.06, 0.08, hz * 2, SQUARE, 0.3, 0.08)
               for i, hz in enumerate((c5, e5, g5, c6, e5 * 2, g5 * 2))]
    sparkle += [(0.4, 1.2, hz * 2, SINE, 0.3, 0.7) for hz in (c5, e5, g5)]
    # Up a level: a climbing run G4 to C6, landing on a bright held chord.
    g4 = note_hz("G4")
    climb = [(i * 0.09, 0.1, hz, SQUARE, 0.35, 0.1) for i, hz in enumerate((g4, c5, e5, g5, c6))]
    climb += [(0.5, 1.4, hz, SAW_HIGH, 0.22, 0.8) for hz in (c5, g5, c6, e5 * 2)]
    climb += [(0.5 + i * 0.07, 0.1, hz * 2, SINE, 0.25, 0.12) for i, hz in enumerate((g5, c6, e5 * 2))]
    return {
        "move": effect(0.06, [(0, 0.03, 1320, SINE, 0.5, 0.015)]),
        "select": effect(0.2, [(0, 0.06, 880, SQUARE, 0.4, 0.05), (0.07, 0.08, 1320, SQUARE, 0.4, 0.06)]),
        "back": effect(0.2, [(0, 0.06, 1320, SQUARE, 0.35, 0.05), (0.07, 0.08, 880, SQUARE, 0.35, 0.06)]),
        "beep": effect(0.2, [(0, 0.15, 1000, SINE, 0.7, 0.2)]),
        "go": effect(0.6, [(0, 0.4, hz, SINE, 0.45, 0.25) for hz in (1320, 1760, 2640)]),
        "km": effect(1.2, [(0, 1.0, 1568, SINE, 0.5, 0.35), (0, 1.0, 2352, SINE, 0.25, 0.25),
                           (0, 0.6, 3136, SINE, 0.12, 0.15)]),
        "finish": effect(1.8, fanfare),
        "connect": effect(0.3, [(0, 0.09, 660, SINE, 0.5, 0.1), (0.1, 0.12, 990, SINE, 0.5, 0.12)]),
        "pb": effect(2.0, sparkle),
        "levelup": effect(2.2, climb),
    }


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "game/sounds"
    os.makedirs(out, exist_ok=True)
    jobs = {
        "music_ride": lambda: loop(ride_music, 16 * 4 * 60 / 110),
        "music_menu": lambda: loop(menu_music, 16 * 4 * 60 / 84),
        "wind": wind,
        "tyres": tyres,
    }
    for name, make in jobs.items():
        write(os.path.join(out, name + ".wav"), make())
        print("made", name)
    made = effects()
    for name, buf in made.items():
        write(os.path.join(out, name + ".wav"), buf)
    print("made", ", ".join(made))


if __name__ == "__main__":
    main()
