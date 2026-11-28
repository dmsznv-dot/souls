#!/usr/bin/env python3
"""Synthesizes every sound and music stem in assets/audio from code.

All material is original and procedural: no samples are used. Run from the project root:

    pip install numpy scipy soundfile
    python3 tools/audio/generate_audio.py

Music stems share tempo and length per area so Godot's AudioStreamSynchronized can fade
layers in and out without losing sync. A fixed random seed keeps the output reproducible.
"""
from __future__ import annotations

import os
import numpy as np
import soundfile as sf
from scipy import signal

SR = 44100
ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
rng = np.random.default_rng(1337)


# ---------------------------------------------------------------- primitives

def t_axis(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * SR)) / SR


def midi(note: float) -> float:
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


NOTE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6,
        "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def n(name: str) -> int:
    """'D4' -> MIDI number."""
    pitch, octave = name[:-1], int(name[-1])
    return 12 * (octave + 1) + NOTE[pitch]


def env_adsr(length: int, a: float, d: float, s: float, r: float) -> np.ndarray:
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    sustain_n = max(0, length - a_n - d_n - r_n)
    parts = [np.linspace(0, 1, max(a_n, 1), endpoint=False),
             np.linspace(1, s, max(d_n, 1), endpoint=False),
             np.full(sustain_n, s),
             np.linspace(s, 0, max(r_n, 1))]
    e = np.concatenate(parts)
    return np.pad(e, (0, max(0, length - len(e))))[:length]


def exp_decay(length: int, seconds: float) -> np.ndarray:
    return np.exp(-np.arange(length) / (seconds * SR))


def noise(length: int) -> np.ndarray:
    return rng.standard_normal(length)


def sos(kind: str, freq, order: int = 2):
    nyq = SR / 2
    if isinstance(freq, (tuple, list)):
        wn = [min(max(f / nyq, 1e-4), 0.999) for f in freq]
    else:
        wn = min(max(freq / nyq, 1e-4), 0.999)
    return signal.butter(order, wn, btype=kind, output="sos")


def lp(x, f, order=2):
    return signal.sosfilt(sos("lowpass", f, order), x)


def hp(x, f, order=2):
    return signal.sosfilt(sos("highpass", f, order), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(sos("bandpass", (lo, hi), order), x)


def saw(freq: float, seconds: float, phase: float = 0.0) -> np.ndarray:
    t = t_axis(seconds)
    return 2.0 * ((freq * t + phase) % 1.0) - 1.0


def sine_sweep(f0: float, f1: float, seconds: float) -> np.ndarray:
    length = int(seconds * SR)
    freq = np.geomspace(f0, f1, length)
    return np.sin(2 * np.pi * np.cumsum(freq) / SR)


def karplus(freq: float, seconds: float, damping: float = 0.996, bright: float = 0.6) -> np.ndarray:
    """Plucked string: a noise burst through a damped comb (Karplus-Strong) via lfilter."""
    length = int(seconds * SR)
    period = max(2, int(SR / freq))
    burst = np.zeros(length)
    excite = noise(period)
    excite = lp(excite, 1500 + bright * 6000)
    burst[:period] = excite
    a = np.zeros(period + 2)
    a[0] = 1.0
    a[period] = -damping * 0.5
    a[period + 1] = -damping * 0.5
    return signal.lfilter([1.0], a, burst)


def reverb(x: np.ndarray, seconds: float = 2.6, wet: float = 0.35, tone: float = 5000,
           stereo: bool = True) -> np.ndarray:
    """Convolution with a synthetic exponentially decaying noise tail."""
    length = int(seconds * SR)
    channels = []
    for _ in range(2 if stereo else 1):
        ir = noise(length) * exp_decay(length, seconds / 6.9)
        ir = lp(ir, tone)
        ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
        ir /= np.sqrt(np.sum(ir ** 2))
        source = x if x.ndim == 1 else x[:, len(channels) % x.shape[1]]
        channels.append(signal.fftconvolve(source, ir)[: len(source)])
    tail = np.stack(channels, axis=1)
    dry = x if x.ndim == 2 else np.stack([x, x], axis=1)
    return dry * (1 - wet) + tail * wet * 1.6


def loop_reverb(x: np.ndarray, **kwargs) -> np.ndarray:
    """Reverb on a loop: the tail of the end wraps into the start, so the loop point is seamless."""
    tripled = np.concatenate([x, x, x]) if x.ndim == 1 else np.concatenate([x, x, x], axis=0)
    wet = reverb(tripled, **kwargs)
    return wet[len(x): 2 * len(x)]


def fade(x: np.ndarray, fade_in: float = 0.003, fade_out: float = 0.01) -> np.ndarray:
    x = x.copy()
    i, o = int(fade_in * SR), int(fade_out * SR)
    if i:
        x[:i] *= np.linspace(0, 1, i)[:, None] if x.ndim == 2 else np.linspace(0, 1, i)
    if o:
        x[-o:] *= np.linspace(1, 0, o)[:, None] if x.ndim == 2 else np.linspace(1, 0, o)
    return x


def normalize(x: np.ndarray, peak_db: float = -3.0) -> np.ndarray:
    peak = np.max(np.abs(x)) + 1e-9
    return x / peak * 10 ** (peak_db / 20)


def rms_normalize(x: np.ndarray, rms_db: float) -> np.ndarray:
    rms = np.sqrt(np.mean(x ** 2)) + 1e-9
    y = x / rms * 10 ** (rms_db / 20)
    peak = np.max(np.abs(y))
    return y / peak * 0.89 if peak > 0.89 else y


def write(name: str, x: np.ndarray, ogg: bool = False) -> None:
    path = os.path.join(ROOT, name + (".ogg" if ogg else ".wav"))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if ogg:
        # libsndfile's Vorbis encoder can crash on one very large write; feed it in blocks.
        data = x.astype(np.float32)
        channels = 1 if data.ndim == 1 else data.shape[1]
        with sf.SoundFile(path, "w", SR, channels, format="OGG", subtype="VORBIS") as out:
            for start in range(0, len(data), 4096):
                out.write(data[start:start + 4096])
    else:
        sf.write(path, x.astype(np.float32), SR, subtype="PCM_16")
    print("wrote", os.path.relpath(path, os.path.join(ROOT, "..", "..")))


def place(buffer: np.ndarray, sound: np.ndarray, at: float, gain: float = 1.0) -> None:
    start = int(at * SR)
    if start >= len(buffer):
        return
    end = min(len(buffer), start + len(sound))
    if buffer.ndim == 2 and sound.ndim == 1:
        buffer[start:end] += (sound[: end - start] * gain)[:, None]
    else:
        buffer[start:end] += sound[: end - start] * gain


def place_wrapped(buffer: np.ndarray, sound: np.ndarray, at: float, gain: float = 1.0) -> None:
    """Place on a loop buffer; anything past the end wraps to the start."""
    start = int(at * SR) % len(buffer)
    first = min(len(sound), len(buffer) - start)
    buffer[start:start + first] += sound[:first] * gain
    if first < len(sound):
        rest = sound[first:]
        buffer[: len(rest)] += rest * gain


# ---------------------------------------------------------------- sound effects

def whoosh(seconds: float, low: float, high: float, peak_at: float, rumble: float = 0.0) -> np.ndarray:
    length = int(seconds * SR)
    raw = noise(length)
    bands = [bp(raw, low, low * 2.2), bp(raw, low * 2.2, high * 0.6), bp(raw, high * 0.6, high)]
    t = np.linspace(0, 1, length)
    sweep = np.clip(t / peak_at, 0, 1)
    gains = [1 - sweep, 1 - np.abs(sweep - 0.5) * 2, sweep]
    mix = sum(b * g for b, g in zip(bands, gains))
    shape = np.where(t < peak_at, (t / peak_at) ** 2, np.exp(-(t - peak_at) / (1 - peak_at) * 4))
    out = mix * shape
    if rumble:
        out += np.sin(2 * np.pi * np.cumsum(np.linspace(70, 40, length)) / SR) * shape * rumble
    return fade(out)


def thump(seconds: float, f0: float, f1: float, decay: float) -> np.ndarray:
    length = int(seconds * SR)
    return sine_sweep(f0, f1, seconds) * exp_decay(length, decay)


def clang(f0: float, seconds: float, brightness: float = 1.0, decay: float = 0.35) -> np.ndarray:
    """Modal metal: inharmonic partials with independent decays."""
    length = int(seconds * SR)
    t = t_axis(seconds)
    ratios = [1.0, 2.32, 3.86, 5.41, 6.92, 8.63]
    out = np.zeros(length)
    for i, r in enumerate(ratios):
        detune = 1 + rng.uniform(-0.01, 0.01)
        amp = (0.9 ** i) * (brightness if i > 1 else 1.0)
        out += np.sin(2 * np.pi * f0 * r * detune * t + rng.uniform(0, 6)) * amp * exp_decay(length, decay / (1 + i * 0.45))
    strike = hp(noise(length), 2500) * exp_decay(length, 0.008)
    return out + strike * 0.6


def bone_clicks(seconds: float, count: int, spread: float, pitch: float = 1.0) -> np.ndarray:
    out = np.zeros(int(seconds * SR))
    for _ in range(count):
        tick_len = int(0.018 * SR)
        tick = bp(noise(tick_len), 1200 * pitch, 3800 * pitch) * exp_decay(tick_len, 0.004)
        tick += np.sin(2 * np.pi * rng.uniform(700, 1300) * pitch * t_axis(0.018)) * exp_decay(tick_len, 0.005) * 0.5
        place(out, tick, rng.uniform(0, spread), rng.uniform(0.4, 1.0))
    return out


def make_sfx() -> None:
    for i in range(3):
        write(f"sfx/swing_light_{i}", normalize(whoosh(0.2 + 0.03 * i, 500, 7000, 0.42), -5))
        write(f"sfx/swing_medium_{i}", normalize(whoosh(0.3 + 0.03 * i, 300, 5200, 0.45, 0.12), -4))
        write(f"sfx/swing_heavy_{i}", normalize(whoosh(0.5 + 0.05 * i, 140, 3200, 0.5, 0.45), -3))

        # Blade into armour and body: slice, low thump, crunch and an armour tick.
        length = int(0.45 * SR)
        hit = np.zeros(length)
        place(hit, hp(noise(int(0.05 * SR)), 5000) * exp_decay(int(0.05 * SR), 0.012), 0.0, 0.6)
        place(hit, thump(0.3, 120 - 10 * i, 46, 0.08), 0.004, 1.0)
        crunch_len = int(0.12 * SR)
        place(hit, bp(noise(crunch_len), 900, 3600) * exp_decay(crunch_len, 0.03), 0.002, 0.8)
        place(hit, clang(rng.uniform(900, 1300), 0.3, 0.6, 0.08), 0.0, 0.18)
        write(f"sfx/hit_{i}", normalize(fade(hit), -2))

        block = clang(rng.uniform(380, 470), 0.9, 0.9, 0.45)
        block[: int(0.004 * SR)] += noise(int(0.004 * SR)) * 0.8
        write(f"sfx/block_{i}", normalize(fade(reverb(block, 1.2, 0.18, 7000)), -3))

    parry = clang(880, 1.6, 1.2, 0.9) + clang(1320, 1.6, 0.8, 0.7) * 0.5
    parry = parry + np.concatenate([np.zeros(0), whoosh(1.6, 2000, 9000, 0.02) * 0.08])
    write("sfx/parry", normalize(fade(reverb(parry, 2.0, 0.3, 8000)), -2))

    length = int(1.3 * SR)
    breaker = np.zeros(length)
    place(breaker, clang(310, 1.2, 1.0, 0.5), 0.0, 1.0)
    place(breaker, thump(0.8, 90, 32, 0.25), 0.0, 1.2)
    place(breaker, bp(noise(int(0.4 * SR)), 300, 2000) * exp_decay(int(0.4 * SR), 0.1), 0.01, 0.6)
    place(breaker, bone_clicks(0.6, 9, 0.5), 0.05, 0.5)
    write("sfx/guard_break", normalize(fade(reverb(breaker, 1.6, 0.22)), -1.5))

    for i in range(2):
        length = int(0.62 * SR)
        roll = np.zeros(length)
        rustle = lp(noise(length), 1800) * env_adsr(length, 0.05, 0.25, 0.3, 0.25)
        place(roll, rustle, 0.0, 0.45)
        place(roll, bone_clicks(0.5, 10, 0.42, 0.9), 0.04, 0.6)
        place(roll, thump(0.2, 110, 50, 0.05), 0.08 + 0.02 * i, 0.7)
        place(roll, thump(0.2, 90, 45, 0.06), 0.42, 0.6)
        write(f"sfx/roll_{i}", normalize(fade(roll), -4))

    for i in range(5):
        # Sabaton on flagstone: grit, a low heel thud, a faint bone/metal clink.
        length = int(0.22 * SR)
        step = np.zeros(length)
        place(step, bp(noise(length), 600, 3500) * exp_decay(length, 0.018), 0.0, 0.7)
        place(step, thump(0.12, 95 + 6 * i, 55, 0.03), 0.0, 0.9)
        place(step, clang(rng.uniform(1600, 2600), 0.15, 0.4, 0.04), rng.uniform(0.005, 0.03), 0.12)
        place(step, bone_clicks(0.05, 2, 0.03, 1.1), 0.01, 0.25)
        write(f"sfx/step_{i}", normalize(fade(step), -8))

    for i in range(3):
        length = int(0.5 * SR)
        jingle = np.zeros(length)
        for _ in range(7):
            place(jingle, clang(rng.uniform(2400, 4200), 0.2, 0.3, 0.05), rng.uniform(0, 0.3), rng.uniform(0.1, 0.35))
        write(f"sfx/armor_{i}", normalize(fade(jingle), -12))

    length = int(0.55 * SR)
    windup = whoosh(0.55, 120, 1400, 0.85, 0.2)
    place(windup, bone_clicks(0.3, 5, 0.25, 0.8), 0.1, 0.3)
    jingle = np.zeros(length)
    for _ in range(5):
        place(jingle, clang(rng.uniform(2000, 3500), 0.2, 0.3, 0.05), rng.uniform(0.05, 0.35), 0.2)
    write("sfx/windup", normalize(fade(windup + jingle), -5))

    length = int(0.4 * SR)
    land = np.zeros(length)
    place(land, thump(0.3, 100, 40, 0.07), 0.0, 1.0)
    place(land, bone_clicks(0.3, 8, 0.2), 0.01, 0.5)
    place(land, bp(noise(length), 400, 2500) * exp_decay(length, 0.03), 0.0, 0.4)
    write("sfx/land", normalize(fade(land), -5))

    length = int(1.6 * SR)
    death = np.zeros(length)
    for k, at in enumerate([0.0, 0.18, 0.31, 0.55, 0.62, 0.9]):
        place(death, thump(0.3, 110 - k * 8, 40, 0.06), at, 0.8 - k * 0.08)
        place(death, clang(rng.uniform(500, 1500), 0.4, 0.6, 0.12), at + 0.01, 0.25)
    place(death, bone_clicks(1.2, 26, 1.1), 0.05, 0.7)
    write("sfx/death", normalize(fade(reverb(death, 1.5, 0.2)), -2.5))

    length = int(0.55 * SR)
    breath = bp(noise(length), 250, 1100) * env_adsr(length, 0.08, 0.1, 0.6, 0.3)
    write("sfx/tired", normalize(fade(breath), -12))

    # Seal of the gate burning away: grinding stone, chains, a deep boom and rising embers.
    length = int(5.0 * SR)
    gate = np.zeros(length)
    grind = lp(noise(length), 420) * (0.6 + 0.4 * np.abs(signal.sosfilt(sos("lowpass", 6), noise(length))) * 8)
    gate += grind * env_adsr(length, 0.6, 0.5, 0.7, 1.6) * 0.8
    place(gate, thump(2.5, 60, 26, 0.8), 0.0, 1.4)
    for k in range(18):
        place(gate, clang(rng.uniform(700, 1900), 0.4, 0.5, 0.1), 0.4 + k * 0.17 + rng.uniform(0, 0.08), 0.22)
    place(gate, whoosh(3.0, 600, 9000, 0.7) * 0.5, 1.4, 0.6)
    write("sfx/gate_open", normalize(fade(reverb(gate, 3.2, 0.35, 4000), 0.01, 0.5), -1.5))


# ---------------------------------------------------------------- instruments

def pad_voice(note: int, seconds: float, cutoff: float = 1400, detune_cents: float = 9) -> np.ndarray:
    f = midi(note)
    out = sum(saw(f * 2 ** (c / 1200), seconds, rng.uniform()) for c in (-detune_cents, 0, detune_cents))
    out = lp(out / 3, cutoff, 2)
    return out * env_adsr(len(out), 0.9, 0.6, 0.8, 1.2)


def choir_voice(note: int, seconds: float) -> np.ndarray:
    """Formant-filtered saw: a dark 'ah'."""
    f = midi(note)
    t = t_axis(seconds)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.1 * t)
    src = 2.0 * ((np.cumsum(f * vib) / SR) % 1.0) - 1.0
    formants = bp(src, 650, 1000) * 1.0 + bp(src, 1050, 1300) * 0.6 + bp(src, 2600, 3000) * 0.18
    return formants * env_adsr(len(src), 1.2, 0.4, 0.85, 1.4)


def organ_lead(note: int, seconds: float) -> np.ndarray:
    f = midi(note)
    t = t_axis(seconds)
    vib = 1 + 0.005 * np.sin(2 * np.pi * 4.8 * t) * np.clip(t / 0.6, 0, 1)
    phase = np.cumsum(f * vib) / SR
    tone = np.sin(2 * np.pi * phase) + 0.45 * np.sin(4 * np.pi * phase) + 0.25 * np.sin(6 * np.pi * phase) \
        + 0.12 * np.sign(np.sin(2 * np.pi * phase))
    return lp(tone, 2600) * env_adsr(len(t), 0.12, 0.3, 0.75, 0.35)


def recorder(note: int, seconds: float) -> np.ndarray:
    f = midi(note)
    t = t_axis(seconds)
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.6 * t) * np.clip((t - 0.15) / 0.3, 0, 1)
    phase = np.cumsum(f * vib) / SR
    tone = np.sin(2 * np.pi * phase) + 0.18 * np.sin(4 * np.pi * phase) + 0.06 * np.sin(6 * np.pi * phase)
    breath = bp(noise(len(t)), f * 1.5, min(f * 6, 15000)) * 0.05
    chiff = bp(noise(len(t)), 2000, 6000) * exp_decay(len(t), 0.02) * 0.25
    return (tone + breath + chiff) * env_adsr(len(t), 0.035, 0.1, 0.85, 0.08)


def lute(note: int, seconds: float) -> np.ndarray:
    pluck = karplus(midi(note), seconds, 0.994, 0.45)
    body = lp(pluck, 3200)
    return fade(body, 0.001, 0.05)


def timpani(note: int, seconds: float = 1.6) -> np.ndarray:
    length = int(seconds * SR)
    f = midi(note)
    t = t_axis(seconds)
    pitch = f * (1 + 0.06 * np.exp(-t / 0.05))
    body = np.sin(2 * np.pi * np.cumsum(pitch) / SR) + 0.4 * np.sin(2 * np.pi * np.cumsum(pitch * 1.5) / SR)
    head = lp(noise(length), 900) * exp_decay(length, 0.03)
    return (body * exp_decay(length, 0.5) + head * 0.6)


def frame_drum(low: bool) -> np.ndarray:
    seconds = 0.6 if low else 0.18
    length = int(seconds * SR)
    if low:
        return thump(seconds, 110, 62, 0.16) + lp(noise(length), 500) * exp_decay(length, 0.02) * 0.4
    tek = bp(noise(length), 900, 4500) * exp_decay(length, 0.025)
    return tek + np.sin(2 * np.pi * 420 * t_axis(seconds)) * exp_decay(length, 0.02) * 0.3


def jingle() -> np.ndarray:
    out = np.zeros(int(0.25 * SR))
    for _ in range(5):
        place(out, clang(rng.uniform(4500, 7500), 0.15, 0.2, 0.04), rng.uniform(0, 0.03), 0.2)
    return out


def hurdy_drone(notes: list[int], seconds: float, buzz_beats: list[float] | None = None) -> np.ndarray:
    """Sustained drone rendered 1.5 s past the loop and crossfaded into its start: no seam click."""
    overlap = 1.5
    body = _drone(notes, seconds + overlap, buzz_beats)
    length, span = int(seconds * SR), int(overlap * SR)
    out = body[:length].copy()
    ramp = np.linspace(0, 1, span)
    out[:span] = out[:span] * ramp + body[length:length + span] * (1 - ramp)
    return out


def _drone(notes: list[int], seconds: float, buzz_beats: list[float] | None) -> np.ndarray:
    t = t_axis(seconds)
    out = np.zeros(len(t))
    for note in notes:
        f = midi(note)
        wobble = 1 + 0.0025 * np.sin(2 * np.pi * 0.7 * t + rng.uniform(0, 6))
        out += 2.0 * ((np.cumsum(f * wobble) / SR) % 1.0) - 1.0
    out = lp(out / len(notes), 1700) + bp(out, 2200, 3400) * 0.15
    if buzz_beats:
        gate = np.zeros(len(t))
        for b in buzz_beats:
            start = int(b * SR)
            span = int(0.12 * SR)
            gate[start:start + span] += np.linspace(1, 0, min(span, len(gate) - start))
        buzz = bp(np.sign(np.sin(2 * np.pi * midi(notes[0]) * 2 * t)), 700, 2600)
        out += buzz * gate * 0.35
    return out


def tape(x: np.ndarray, depth: float = 0.004, rate: float = 0.31) -> np.ndarray:
    """Cassette wow and soft saturation: a slow wandering pitch and rounded peaks."""
    length = len(x)
    seconds = length / SR
    t = np.arange(length) / SR
    # Whole cycles per loop so the warp, like the music, ends where it began.
    slow = max(1, round(rate * seconds)) / seconds
    fast = max(2, round(rate * 2.7 * seconds)) / seconds
    wander = depth * SR * (np.sin(2 * np.pi * slow * t) + 0.35 * np.sin(2 * np.pi * fast * t + 1.3))
    index = np.arange(length) + wander
    channels = [x] if x.ndim == 1 else [x[:, c] for c in range(x.shape[1])]
    warped = [np.interp(index, np.arange(length), ch, period=length) for ch in channels]
    y = warped[0] if x.ndim == 1 else np.stack(warped, axis=1)
    peak = np.max(np.abs(y)) + 1e-9
    return np.tanh(y / peak * 1.4) * peak / np.tanh(1.4)


def harpsichord(note: int, seconds: float) -> np.ndarray:
    pluck = karplus(midi(note), seconds, 0.992, 0.95) + karplus(midi(note) * 2.003, seconds, 0.985, 1.0) * 0.3
    return fade(hp(pluck, 180), 0.001, 0.05)


def brass(note: int, seconds: float, bright: float = 1.0) -> np.ndarray:
    """Synth brass: stacked saws through a lowpass that opens on the attack."""
    f = midi(note)
    t = t_axis(seconds)
    raw = sum(saw(f * 2 ** (c / 1200), seconds, rng.uniform()) for c in (-7, 0, 6)) / 3
    sweep = 500 + 2600 * bright * np.exp(-t / 0.18) + 900 * bright
    out = np.zeros(len(t))
    block = 1024
    for start in range(0, len(t), block):
        cutoff = float(sweep[min(start + block // 2, len(t) - 1)])
        out[start:start + block] = lp(raw[max(0, start - 2048):start + block], cutoff)[-len(raw[start:start + block]):]
    return out * env_adsr(len(t), 0.03, 0.15, 0.75, 0.12)


def war_snare(seconds: float = 0.3) -> np.ndarray:
    length = int(seconds * SR)
    return bp(noise(length), 900, 5000) * exp_decay(length, 0.06) + \
        np.sin(2 * np.pi * 190 * t_axis(seconds)) * exp_decay(length, 0.04) * 0.5


def arp_pluck(note: int, seconds: float) -> np.ndarray:
    f = midi(note)
    raw = saw(f, seconds) + 0.5 * saw(f * 1.004, seconds)
    t = t_axis(seconds)
    return lp(raw, 2400) * np.exp(-t / 0.09)


def court_combat() -> None:
    """The Gatekeeper's theme: D minor with Phrygian E flat, a 16th-note ostinato, timpani and
    war snare under a synth-brass melody; phase two adds a chanting choir and bells."""
    bpm, bars = 126, 16
    beat = 60 / bpm
    length_s = bars * 4 * beat
    length = int(length_s * SR)
    harmony = ["Dm", "Dm", "Eb", "Eb", "Dm", "C", "Bb", "Eb", "Dm", "Dm", "Gm", "Gm", "Eb", "Eb", "A", "A"]
    chords = {"Dm": ["D3", "F3", "A3"], "Eb": ["Eb3", "G3", "Bb3"], "C": ["C3", "E3", "G3"],
              "Bb": ["Bb2", "D3", "F3"], "Gm": ["G2", "Bb2", "D3"], "A": ["A2", "C#3", "E3"]}
    rhythm = np.zeros(length)
    extra = np.zeros(length)
    for bar, chord in enumerate(harmony):
        at = bar * 4 * beat
        root = n(chords[chord][0]) - 12
        for k in range(16):
            step = [0, 0, 0, 1, 0, 0, -2, 0][k % 8]
            note = root + {1: 1, -2: -2}.get(step, 0)
            place_wrapped(rhythm, arp_pluck(note, beat * 0.3), at + k * beat / 4, 0.32 if k % 4 == 0 else 0.2)
        place_wrapped(rhythm, timpani(root + 12, 1.2), at, 0.9)
        place_wrapped(rhythm, timpani(root + 12, 0.8), at + 2 * beat, 0.6)
        for hit in (1, 3):
            place_wrapped(rhythm, war_snare(), at + hit * beat, 0.45)
        place_wrapped(rhythm, war_snare(0.15), at + 3.75 * beat, 0.2)
        if bar % 2 == 0:
            for v in chords[chord]:
                place_wrapped(rhythm, pad_voice(n(v), 8 * beat + 0.6, 1500, 10), at, 0.12)
                place_wrapped(extra, choir_voice(n(v) + 12, 8 * beat + 0.8), at, 0.2)
            place_wrapped(extra, clang(midi(root + 24), 2.5, 0.6, 1.2), at, 0.25)
    tune = [("A4", 2), ("D5", 1), ("F5", 1), ("E5", 1.5), ("D5", .5), ("C5", 1), ("D5", 1),
            ("Eb5", 2), ("G5", 1), ("Bb5", 1), ("G5", 1), ("F5", 1), ("Eb5", 1), ("D5", 1),
            ("D5", 2), ("A4", 1), ("D5", 1), ("E5", 1.5), ("D5", .5), ("C5", 2),
            ("D5", 2), ("F5", 1), ("Bb5", 1), ("G5", 2), ("F5", 1), ("Eb5", 1),
            ("A5", 2), ("G5", .5), ("F5", .5), ("E5", 1), ("F5", 1), ("E5", 1), ("D5", 2),
            ("G5", 1.5), ("A5", .5), ("Bb5", 1), ("A5", 1), ("G5", 2), ("D5", 2),
            ("Eb5", 1), ("F5", 1), ("G5", 1), ("Bb5", 1), ("Bb5", 2), ("G5", 2),
            ("C#5", 1), ("E5", 1), ("A5", 1), ("G5", 1), ("F5", 1), ("E5", 1), ("D5", 1), ("C#5", 1)]
    lead = np.zeros(length)
    at = 0.0
    for name, beats in tune:
        place_wrapped(lead, brass(n(name) - 12, beats * beat * 0.92), at, 0.36)
        at += beats * beat
    assert abs(at - length_s) < 1e-6, (at, length_s)
    write("music/court_combat_rhythm", rms_normalize(loop_reverb(rhythm, seconds=1.8, wet=0.25, tone=4000), -20), True)
    write("music/court_combat_lead", rms_normalize(tape(loop_reverb(lead, seconds=2.4, wet=0.35, tone=5000), 0.0015), -22), True)
    write("music/court_combat_phase", rms_normalize(loop_reverb(extra, seconds=3.5, wet=0.5, tone=4000), -23), True)


def ruins_combat() -> None:
    """Ruins fight: D Dorian dungeon synth at 132 BPM, a 16th-note arpeggiator, frame drum and
    taiko under a buzzing hurdy-gurdy, and a new organ melody; a choir layer for the brute."""
    bpm, bars = 132, 16
    beat = 60 / bpm
    length_s = bars * 4 * beat
    length = int(length_s * SR)
    harmony = ["Dm", "Dm", "C", "C", "Dm", "Dm", "G", "G", "F", "F", "C", "C", "Am", "Am", "Dm", "Dm"]
    shapes = {"Dm": ["D3", "F3", "A3", "D4"], "C": ["C3", "E3", "G3", "C4"], "G": ["G2", "B2", "D3", "G3"],
              "F": ["F2", "A2", "C3", "F3"], "Am": ["A2", "C3", "E3", "A3"]}
    rhythm = np.zeros(length)
    extra = np.zeros(length)
    buzz = []
    for bar, chord in enumerate(harmony):
        at = bar * 4 * beat
        tones = [n(v) + 12 for v in shapes[chord]]
        for k in range(16):
            place_wrapped(rhythm, arp_pluck(tones[[0, 1, 2, 3, 2, 1, 2, 3][k % 8]], beat * 0.28), at + k * beat / 4, 0.17)
        place_wrapped(rhythm, timpani(n(shapes[chord][0]) - 12, 0.9), at, 0.8)
        for hit, low in ((0, True), (1.5, True), (2, False), (3, False), (3.5, False)):
            place_wrapped(rhythm, frame_drum(low), at + hit * beat, 0.7 if low else 0.45)
        for e in range(8):
            place_wrapped(rhythm, jingle(), at + e * beat / 2 + beat / 4, 0.25)
        buzz += [at + b * beat for b in range(4)]
        if bar % 2 == 0:
            for v in shapes[chord][1:]:
                place_wrapped(extra, choir_voice(n(v) + 12, 8 * beat + 0.6), at, 0.2)
    rhythm += hurdy_drone([n("D2"), n("A2")], length_s, buzz) * 0.2
    tune = [("D5", .5), ("F5", .5), ("A5", 1), ("G5", .5), ("F5", .5), ("E5", 1), ("D5", 1.5), ("E5", .5), ("F5", 2),
            ("E5", .5), ("G5", .5), ("C6", 1), ("B5", .5), ("A5", .5), ("G5", 1), ("E5", 2), ("G5", 2),
            ("A5", 1), ("G5", .5), ("F5", .5), ("E5", 1), ("D5", 1), ("F5", 1), ("E5", 1), ("D5", 2),
            ("B4", 1), ("D5", 1), ("G5", 1), ("B5", 1), ("A5", 2), ("G5", 2),
            ("A5", 1), ("C6", 1), ("A5", 1), ("F5", 1), ("G5", 1.5), ("F5", .5), ("E5", 2),
            ("G5", 1), ("E5", 1), ("C5", 1), ("E5", 1), ("D5", 2), ("E5", 2),
            ("C5", 1), ("E5", 1), ("A5", 1), ("G5", 1), ("F5", 1), ("E5", 1), ("D5", 1), ("C5", 1),
            ("D5", 1), ("F5", 1), ("A5", 1), ("F5", 1), ("D5", 4)]
    lead = np.zeros(length)
    at = 0.0
    for name, beats in tune:
        place_wrapped(lead, organ_lead(n(name), beats * beat * 0.9 + 0.1), at, 0.3)
        place_wrapped(lead, brass(n(name) - 12, beats * beat * 0.9, 0.6), at, 0.14)
        at += beats * beat
    assert abs(at - length_s) < 1e-6, (at, length_s)
    write("music/ruins_combat_rhythm", rms_normalize(loop_reverb(rhythm, seconds=1.6, wet=0.22, tone=5000), -20), True)
    write("music/ruins_combat_lead", rms_normalize(tape(loop_reverb(lead, seconds=2.2, wet=0.35, tone=5500), 0.0015), -22), True)
    write("music/ruins_combat_phase", rms_normalize(loop_reverb(extra, seconds=3.0, wet=0.5, tone=4000), -23), True)


def notice_stinger() -> None:
    """A foe has seen you: low boom, a dissonant brass cluster swelling open, a choir breath."""
    seconds = 2.2
    out = np.zeros(int(seconds * SR))
    place(out, thump(1.6, 70, 30, 0.45), 0.0, 1.0)
    for note in ("D3", "Eb3", "A3", "D4"):
        place(out, brass(n(note), 1.6, 1.3), 0.02, 0.22)
    for note in ("D4", "Eb4", "A4"):
        place(out, choir_voice(n(note), 1.8), 0.05, 0.12)
    place(out, hp(noise(int(0.5 * SR)), 3000) * np.linspace(0, 1, int(0.5 * SR)) ** 2 * 0.1, 0.0, 1.0)
    write("music/notice", normalize(fade(reverb(out, 2.8, 0.4, 4000), 0.002, 0.5), -3), True)


def special_sfx() -> None:
    length = int(0.7 * SR)
    cast = whoosh(0.7, 1500, 9000, 0.25) * 0.6
    for k in range(5):
        place(cast, clang(rng.uniform(1600, 3200), 0.6, 0.5, 0.25) * 0.2, 0.02 + k * 0.03)
    write("sfx/cast", normalize(fade(reverb(cast, 1.4, 0.35, 8000)), -4))
    nova = np.zeros(int(1.6 * SR))
    place(nova, thump(1.2, 90, 28, 0.35), 0.0, 1.0)
    place(nova, whoosh(1.2, 400, 8000, 0.08) * 0.6, 0.0)
    for k in range(8):
        place(nova, clang(rng.uniform(900, 2600), 0.9, 0.5, 0.4) * 0.15, rng.uniform(0, 0.2))
    write("sfx/nova", normalize(fade(reverb(nova, 2.2, 0.4, 6000)), -2))
    slam = np.zeros(int(1.4 * SR))
    place(slam, thump(1.0, 75, 24, 0.3), 0.0, 1.3)
    place(slam, lp(noise(int(0.6 * SR)), 700) * exp_decay(int(0.6 * SR), 0.15), 0.0, 0.9)
    for k in range(10):
        place(slam, thump(0.12, rng.uniform(180, 320), 90, 0.02), rng.uniform(0.04, 0.5), rng.uniform(0.15, 0.35))
    write("sfx/shockwave", normalize(fade(reverb(slam, 1.6, 0.25, 3000)), -1.5))
    charged = np.zeros(int(0.8 * SR))
    place(charged, clang(midi(n("A5")), 0.8, 0.8, 0.5), 0.0, 0.6)
    place(charged, whoosh(0.4, 2000, 9000, 0.9) * 0.3, 0.0)
    write("sfx/charged", normalize(fade(charged), -6))
    skid = lp(noise(int(0.45 * SR)), 2600) * env_adsr(int(0.45 * SR), 0.01, 0.1, 0.6, 0.25)
    skid = skid + bp(noise(len(skid)), 300, 900) * 0.5 * np.linspace(1, 0, len(skid))
    write("sfx/skid", normalize(fade(skid), -8))
    crit = np.zeros(int(0.9 * SR))
    place(crit, hp(noise(int(0.06 * SR)), 4000) * exp_decay(int(0.06 * SR), 0.01), 0.0, 0.8)
    place(crit, thump(0.4, 160, 50, 0.1), 0.0, 1.0)
    place(crit, clang(1480, 0.8, 1.0, 0.35), 0.01, 0.4)
    write("sfx/critical", normalize(fade(reverb(crit, 1.2, 0.25)), -2))
    fizzle = bp(noise(int(0.4 * SR)), 300, 1200) * exp_decay(int(0.4 * SR), 0.1)
    write("sfx/no_focus", normalize(fade(fizzle), -10))


def impact_sfx() -> None:
    """Material layers played on top of the base hit, plus stun and knockdown cues."""
    local = np.random.default_rng(4242)
    for i in range(3):
        # Plate: bright inharmonic ring and a scrape of grit.
        length = int(0.7 * SR)
        plate = np.zeros(length)
        place(plate, clang(local.uniform(620, 980), 0.65, 1.1, 0.22), 0.0, 1.0)
        place(plate, hp(noise(int(0.03 * SR)), 3000) * exp_decay(int(0.03 * SR), 0.006), 0.0, 0.9)
        place(plate, bp(noise(int(0.15 * SR)), 2500, 7000) * exp_decay(int(0.15 * SR), 0.04), 0.01, 0.25)
        write(f"sfx/impact_plate_{i}", normalize(fade(reverb(plate, 0.8, 0.12, 9000)), -4))
        # Bone: dry splintering cracks over a hollow knock.
        length = int(0.35 * SR)
        bone = np.zeros(length)
        place(bone, bone_clicks(0.25, 7 + i * 2, 0.06, 0.8), 0.0, 1.0)
        knock = np.sin(2 * np.pi * local.uniform(380, 520) * t_axis(0.12)) * exp_decay(int(0.12 * SR), 0.02)
        place(bone, knock, 0.0, 0.7)
        place(bone, bp(noise(int(0.08 * SR)), 1800, 6000) * exp_decay(int(0.08 * SR), 0.012), 0.004, 0.6)
        write(f"sfx/impact_bone_{i}", normalize(fade(bone), -4))
        # Flesh and cloth: wet low thud, a short squelch.
        length = int(0.4 * SR)
        flesh = np.zeros(length)
        place(flesh, thump(0.3, 95 - 8 * i, 38, 0.07), 0.0, 1.0)
        squelch = lp(noise(int(0.12 * SR)), 900) * exp_decay(int(0.12 * SR), 0.035)
        place(flesh, squelch, 0.006, 0.9)
        place(flesh, bp(noise(int(0.05 * SR)), 300, 1200) * exp_decay(int(0.05 * SR), 0.015), 0.0, 0.5)
        write(f"sfx/impact_flesh_{i}", normalize(fade(flesh), -4))
        # Hide: dull leathery slap with a heavy body behind it.
        length = int(0.45 * SR)
        hide = np.zeros(length)
        place(hide, thump(0.35, 70, 30, 0.1), 0.0, 1.0)
        slap = bp(noise(int(0.05 * SR)), 500, 2200) * exp_decay(int(0.05 * SR), 0.01)
        place(hide, slap, 0.0, 0.8)
        write(f"sfx/impact_hide_{i}", normalize(fade(hide), -4))
    # Posture broken: a ringing daze, a sinking tone and a jolt.
    length = int(1.6 * SR)
    daze = np.zeros(length)
    place(daze, thump(0.5, 140, 45, 0.15), 0.0, 1.0)
    ring = np.sin(2 * np.pi * 2900 * t_axis(1.5)) * exp_decay(int(1.5 * SR), 0.6) * 0.18
    ring += np.sin(2 * np.pi * 3170 * t_axis(1.5)) * exp_decay(int(1.5 * SR), 0.5) * 0.12
    place(daze, ring, 0.04, 1.0)
    place(daze, clang(260, 1.2, 0.8, 0.5), 0.0, 0.5)
    write("sfx/posture_break", normalize(fade(reverb(daze, 1.6, 0.25), 0.003, 0.3), -2))
    # Knocked off one's feet: the body hits the flagstones and slides.
    length = int(0.9 * SR)
    fall = np.zeros(length)
    place(fall, thump(0.5, 85, 28, 0.14), 0.0, 1.2)
    place(fall, thump(0.3, 110, 40, 0.06), 0.12, 0.6)
    place(fall, lp(noise(int(0.45 * SR)), 1500) * env_adsr(int(0.45 * SR), 0.02, 0.1, 0.5, 0.3), 0.08, 0.35)
    place(fall, bone_clicks(0.4, 10, 0.3), 0.02, 0.45)
    write("sfx/knockdown", normalize(fade(fall), -2.5))
    # Out of breath: a ragged gasp, longer than the plain "tired" huff.
    length = int(1.1 * SR)
    gasp = np.zeros(length)
    for k, at in enumerate([0.0, 0.42]):
        g = int(0.5 * SR)
        place(gasp, bp(noise(g), 350, 1600) * env_adsr(g, 0.06, 0.12, 0.5, 0.25), at, 1.0 - k * 0.3)
    write("sfx/exhausted", normalize(fade(gasp), -10))


def forest_audio() -> None:
    """The Thornwood: night ambience, a sparse exploration score, portal, ambush and bonfire."""
    local = np.random.default_rng(777)
    # Night ambience: crickets in pulsing choruses, a far owl, leaves stirring. Stereo loop.
    seconds = 20.0
    length = int(seconds * SR)
    night = np.zeros((length, 2))
    leaves = bp(noise(length), 900, 4000) * (0.4 + 0.6 * np.abs(lp(noise(length), 0.6, 1)) * 40)
    leaves = np.clip(leaves, -1, 1) * 0.12
    night[:, 0] += leaves
    night[:, 1] += np.roll(leaves, int(0.21 * SR))
    for voice in range(5):
        pitch = local.uniform(4200, 5600)
        rate = local.uniform(14, 22)
        pan = local.uniform(0.15, 0.85)
        chirp_len = int(0.035 * SR)
        chirp = np.sin(2 * np.pi * pitch * t_axis(0.035)) * np.hanning(chirp_len)
        at = local.uniform(0, 1.0)
        while at < seconds - 0.1:
            burst = local.integers(3, 7)
            for b in range(burst):
                pos = int((at + b / rate) * SR) % length
                end = min(pos + chirp_len, length)
                night[pos:end, 0] += chirp[:end - pos] * (1 - pan) * 0.05
                night[pos:end, 1] += chirp[:end - pos] * pan * 0.05
            at += local.uniform(0.6, 1.6)
    for at in [3.0, 3.55, 13.0]:
        hoot_len = int(0.45 * SR)
        hoot = np.sin(2 * np.pi * np.cumsum(np.linspace(420, 370, hoot_len)) / SR) * env_adsr(hoot_len, 0.08, 0.1, 0.7, 0.2)
        hoot = reverb(hoot, 2.4, 0.5, 3000)[:hoot_len * 3]
        if hoot.ndim == 2:
            hoot = hoot.mean(axis=1)
        pos = int(at * SR)
        night[pos:pos + len(hoot), 0] += hoot[:length - pos] * 0.05
        night[pos:pos + len(hoot), 1] += hoot[:length - pos] * 0.08
    write("ambience/forest_night", rms_normalize(night, -27), True)

    # Exploration score: slow D minor, a low string drone, a heartbeat drum, a lonely recorder.
    bpm, bars = 66, 16
    beat = 60 / bpm
    bar_s = 4 * beat
    length_s = bars * bar_s
    length = int(length_s * SR)
    base = np.zeros(length)
    base += hurdy_drone([n("D2"), n("A2")], length_s) * 0.16
    chords = ["Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "A", "A", "Dm", "Dm", "F", "F", "Gm", "Bb", "A", "A"]
    shapes = {"Dm": ["D3", "F3", "A3"], "Bb": ["Bb2", "D3", "F3"], "Gm": ["G2", "Bb2", "D3"],
              "A": ["A2", "C#3", "E3"], "F": ["F2", "A2", "C3"]}
    for i, chord in enumerate(chords):
        if i % 2 == 0:
            for v in shapes[chord]:
                place_wrapped(base, pad_voice(n(v), 2 * bar_s + 1.5, 800, 14), i * bar_s, 0.08)
        for k in [0, 2]:
            place_wrapped(base, frame_drum(True), i * bar_s + k * beat, 0.22 if k == 0 else 0.12)
    tune = [("A4", 3), ("F4", 1), ("E4", 2), ("D4", 2), ("C4", 4), ("D4", 4),
            ("F4", 2), ("G4", 2), ("A4", 3), ("C5", 1), ("Bb4", 4), ("A4", 4),
            ("D5", 3), ("C5", 1), ("A4", 2), ("F4", 2), ("G4", 4), ("E4", 4),
            ("F4", 2), ("E4", 2), ("D4", 2), ("C#4", 2), ("D4", 8)]
    melody = np.zeros(length)
    at = 0.0
    for name, beats in tune:
        place_wrapped(melody, recorder(n(name), beats * beat * 0.95), at, 0.3)
        at += beats * beat
    assert abs(at - length_s) < 1e-6, (at, length_s)
    write("music/forest_base", rms_normalize(loop_reverb(base, seconds=3.0, wet=0.4, tone=3500), -22), True)
    write("music/forest_melody", rms_normalize(loop_reverb(melody, seconds=3.2, wet=0.45, tone=5000), -24), True)

    # Portal opening: a rising shimmer over a low swell. Stepping through: a rush and a boom.
    length = int(3.6 * SR)
    shimmer = np.zeros(length)
    for k in range(6):
        f = midi(n("D5")) * [1, 1.5, 2, 2.5, 3, 4][k]
        tone = np.sin(2 * np.pi * f * t_axis(3.6) + local.uniform(0, 6)) * env_adsr(length, 1.6, 0.3, 0.8, 1.2)
        shimmer += tone * (0.3 / (k + 1)) * (1 + 0.3 * np.sin(2 * np.pi * (3 + k) * t_axis(3.6)))
    place(shimmer, thump(3.0, 50, 70, 1.6), 0.0, 0.6)
    shimmer += whoosh(3.6, 300, 6000, 0.8) * 0.25
    write("sfx/portal_open", normalize(fade(reverb(shimmer, 2.6, 0.45, 7000), 0.01, 0.6), -3))
    length = int(2.2 * SR)
    rush = whoosh(2.2, 120, 8000, 0.35, 0.4) * 0.9
    place(rush, thump(1.4, 70, 25, 0.5), 0.3, 1.2)
    write("sfx/portal_enter", normalize(fade(reverb(rush, 2.0, 0.35, 5000), 0.005, 0.5), -2))

    # Ambush: branches snapping and leaves thrashing, then a low snarl.
    length = int(1.4 * SR)
    burst = np.zeros(length)
    place(burst, bp(noise(int(0.6 * SR)), 700, 5000) * env_adsr(int(0.6 * SR), 0.01, 0.15, 0.4, 0.3), 0.0, 0.8)
    for k in range(6):
        snap_len = int(0.03 * SR)
        place(burst, hp(noise(snap_len), 1200) * exp_decay(snap_len, 0.006), local.uniform(0, 0.35), local.uniform(0.5, 1.0))
    growl_len = int(0.9 * SR)
    growl = saw(55, 0.9) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t_axis(0.9))) * env_adsr(growl_len, 0.1, 0.2, 0.6, 0.4)
    place(burst, lp(growl, 600), 0.25, 0.5)
    write("sfx/ambush", normalize(fade(burst), -3))

    # Bonfire kindling: a whoomp of catching flame and a low warm chord.
    length = int(3.0 * SR)
    kindle = np.zeros(length)
    place(kindle, lp(noise(int(1.2 * SR)), 900) * env_adsr(int(1.2 * SR), 0.15, 0.3, 0.4, 0.6), 0.0, 0.9)
    place(kindle, thump(0.8, 90, 40, 0.3), 0.05, 0.8)
    for note in ["D3", "A3", "F4"]:
        place(kindle, pad_voice(n(note), 2.6, 1200, 6), 0.2, 0.12)
    write("sfx/bonfire", normalize(fade(reverb(kindle, 2.2, 0.35, 4000), 0.01, 0.8), -3))


def thornwood_sfx() -> None:
    """Breaking wood and the drip of a wet canopy."""
    local = np.random.default_rng(31337)
    length = int(0.9 * SR)
    crack = np.zeros(length)
    for k in range(5):
        snap_len = int(local.uniform(0.02, 0.05) * SR)
        snap = bp(noise(snap_len), 700, 4200) * exp_decay(snap_len, local.uniform(0.006, 0.015))
        place(crack, snap, local.uniform(0.0, 0.12), local.uniform(0.5, 1.0))
    place(crack, thump(0.35, 140, 60, 0.07), 0.0, 0.7)
    for k in range(7):
        clatter_len = int(0.06 * SR)
        knock = np.sin(2 * np.pi * local.uniform(300, 700) * t_axis(0.06)) * exp_decay(clatter_len, 0.012)
        place(crack, knock, 0.18 + local.uniform(0, 0.55), local.uniform(0.15, 0.4))
    write("sfx/wood_break", normalize(fade(crack), -3))
    seconds = 12.0
    length = int(seconds * SR)
    drips = np.zeros((length, 2))
    for k in range(70):
        drop_len = int(0.05 * SR)
        f = local.uniform(900, 2200)
        drop = np.sin(2 * np.pi * np.cumsum(np.linspace(f, f * 1.6, drop_len)) / SR) * exp_decay(drop_len, 0.01)
        pos = int(local.uniform(0, seconds - 0.1) * SR)
        pan = local.uniform(0.1, 0.9)
        gain = local.uniform(0.2, 0.7)
        drips[pos:pos + drop_len, 0] += drop * (1 - pan) * gain
        drips[pos:pos + drop_len, 1] += drop * pan * gain
    hiss = bp(noise(length), 2000, 7000) * 0.015
    drips[:, 0] += hiss
    drips[:, 1] += np.roll(hiss, 977)
    write("ambience/drips", rms_normalize(drips, -30), True)


def zones_audio() -> None:
    """Water lapping under the crossing's walks; the belfry's bell and its answer below."""
    local = np.random.default_rng(424242)
    seconds = 14.0
    length = int(seconds * SR)
    water = np.zeros((length, 2))
    body = lp(noise(length), 420) * (0.5 + 0.5 * np.sin(2 * np.pi * t_axis(seconds) * 0.35))
    water[:, 0] += body * 0.6
    water[:, 1] += np.roll(body, 1301) * 0.6
    for k in range(60):
        lap_len = int(local.uniform(0.15, 0.4) * SR)
        lap = bp(noise(lap_len), local.uniform(250, 500), local.uniform(900, 1600)) * env_adsr(lap_len, 0.05, 0.2, 0.3, 0.4)
        pos = int(local.uniform(0, seconds - 0.5) * SR)
        pan = local.uniform(0.1, 0.9)
        water[pos:pos + lap_len, 0] += lap * (1 - pan) * 0.5
        water[pos:pos + lap_len, 1] += lap * pan * 0.5
    write("ambience/water", rms_normalize(water, -28), True)
    # The bell: a low bronze strike with long inharmonic partials.
    seconds = 6.0
    length = int(seconds * SR)
    t = t_axis(seconds)
    f0 = midi(n("D2"))
    bell = np.zeros(length)
    for ratio, amp, decay in [(0.5, 0.5, 3.5), (1.0, 1.0, 2.8), (1.19, 0.6, 2.2), (1.5, 0.45, 1.8), (2.0, 0.5, 1.5), (2.52, 0.3, 1.1), (3.0, 0.25, 0.8), (4.07, 0.15, 0.5)]:
        bell += np.sin(2 * np.pi * f0 * ratio * t + local.uniform(0, 6)) * amp * exp_decay(length, decay)
    bell[: int(0.01 * SR)] += noise(int(0.01 * SR)) * 0.6
    write("sfx/bell_toll", normalize(fade(reverb(bell, 3.0, 0.4, 3000), 0.002, 1.0), -2))
    echo = lp(bell, 500) * 0.5
    write("sfx/bell_echo", normalize(fade(reverb(echo, 3.5, 0.7, 1200), 0.05, 1.5), -9))


# ---------------------------------------------------------------- music

def court_music() -> None:
    bpm, bars = 66, 16
    beat = 60 / bpm
    length_s = bars * 4 * beat
    length = int(length_s * SR)
    chords = [("D2", ["D3", "F3", "A3"]), ("Bb1", ["Bb2", "D3", "F3"]), ("G1", ["G2", "Bb2", "D3"]),
              ("A1", ["A2", "C#3", "E3"]), ("D2", ["D3", "F3", "A3"]), ("F1", ["F2", "A2", "C3"]),
              ("Eb2", ["Eb3", "G3", "Bb3"]), ("A1", ["A2", "C#3", "E3"])]
    pad = np.zeros(length)
    arp = np.zeros(length)
    for i, (bass, voices) in enumerate(chords):
        at = i * 8 * beat
        span = 8 * beat + 1.2
        for v in voices:
            place_wrapped(pad, pad_voice(n(v), span, 1200), at, 0.32)
            place_wrapped(pad, choir_voice(n(v) + 12, span), at, 0.11)
        place_wrapped(pad, pad_voice(n(bass), span, 380, 4), at, 0.5)
        tones = [n(v) + 12 for v in voices] + [n(voices[0]) + 24]
        for e in range(16):
            order = [0, 1, 2, 3, 2, 1, 0, 2][e % 8]
            place_wrapped(arp, harpsichord(tones[order], 1.2), at + e * beat / 2, 0.2 if e % 2 == 0 else 0.13)
    melody_notes = [("A4", 2), ("F4", 1), ("E4", 1), ("D4", 3), (None, 1),
                    ("F4", 2), ("G4", 1), ("A4", 1), ("Bb4", 2), ("A4", 2),
                    ("G4", 2), ("Bb4", 1), ("A4", 1), ("G4", 2), ("D4", 2),
                    ("E4", 1), ("F4", 1), ("E4", 1), ("D4", 1), ("C#4", 3), (None, 1),
                    ("D5", 2), ("C5", 1), ("A4", 1), ("F4", 2), ("A4", 2),
                    ("C5", 2), ("A4", 1), ("F4", 1), ("G4", 2), ("A4", 2),
                    ("Bb4", 2), ("G4", 1), ("Eb4", 1), ("G4", 2), ("F4", 1), ("Eb4", 1),
                    ("D4", 2), ("E4", 1), ("F4", 1), ("E4", 3), (None, 1)]
    melody = np.zeros(length)
    at = 0.0
    for name, beats in melody_notes:
        if name:
            voice = organ_lead(n(name), beats * beat * 0.95 + 0.3)
            place_wrapped(melody, voice, at, 0.3)
            place_wrapped(melody, organ_lead(n(name) - 12, beats * beat * 0.95 + 0.3), at, 0.1)
        at += beats * beat
    assert abs(at - length_s) < 1e-6, at
    # Dungeon synth: warped tape and soft saturation on the pads, a plucked arpeggio under the organ.
    write("music/court_pad", rms_normalize(tape(loop_reverb(pad, seconds=4.5, wet=0.45, tone=3500)), -21), True)
    melody = melody + arp
    write("music/court_melody", rms_normalize(tape(loop_reverb(melody, seconds=4.0, wet=0.5, tone=4500), 0.0025), -23), True)


def ruins_music() -> None:
    bpm, bars = 92, 24
    beat = 60 / bpm
    bar_s = 3 * beat
    length_s = bars * bar_s
    length = int(length_s * SR)
    progression = ["Dm", "Dm", "C", "C", "Dm", "Dm", "Am", "Am",
                   "F", "F", "C", "C", "G", "G", "Dm", "Dm",
                   "Dm", "C", "Dm", "Am", "F", "G", "Am", "Dm"]
    shapes = {"Dm": ["D3", "A3", "D4", "F4"], "C": ["C3", "G3", "C4", "E4"], "Am": ["A2", "E3", "A3", "C4"],
              "F": ["F2", "C3", "F3", "A3"], "G": ["G2", "D3", "G3", "B3"]}
    base = np.zeros(length)
    base += hurdy_drone([n("D2"), n("A2")], length_s) * 0.22
    for i, chord in enumerate(progression):
        if i % 2 == 0:
            for v in shapes[chord][1:]:
                place_wrapped(base, pad_voice(n(v), 2 * bar_s + 1.0, 1100, 12), i * bar_s, 0.07)
    for i, chord in enumerate(progression):
        at = i * bar_s
        tones = shapes[chord]
        pattern = [tones[0], tones[1], tones[2], tones[3], tones[2], tones[1]]
        for k, tone in enumerate(pattern):
            place_wrapped(base, lute(n(tone), 1.6), at + k * beat / 2, 0.42 if k == 0 else 0.28)
    tune = [("D5", 1), ("E5", .5), ("F5", .5), ("G5", 1), ("A5", 2), ("F5", 1),
            ("E5", 1), ("D5", .5), ("C5", .5), ("E5", 1), ("G5", 2), ("E5", 1),
            ("F5", 1), ("E5", .5), ("D5", .5), ("A4", 1), ("D5", 2), ("E5", 1),
            ("C5", 1), ("A4", .5), ("B4", .5), ("C5", 1), ("A4", 3),
            ("F5", 1), ("A5", 1), ("C6", 1), ("A5", 1.5), ("G5", .5), ("F5", 1),
            ("E5", 1), ("G5", 1), ("C6", 1), ("G5", 3),
            ("B5", 1), ("A5", .5), ("G5", .5), ("D5", 1), ("G5", 1.5), ("A5", .5), ("B5", 1),
            ("A5", 1), ("F5", 1), ("E5", 1), ("D5", 3),
            ("A5", 1), ("G5", .5), ("F5", .5), ("E5", 1), ("G5", 1), ("E5", .5), ("D5", .5), ("C5", 1),
            ("D5", 1), ("F5", 1), ("A5", 1), ("E5", 2), ("C5", 1),
            ("F5", 1), ("A5", .5), ("G5", .5), ("F5", 1), ("D5", 1), ("B4", 1), ("D5", 1),
            ("E5", 1), ("C5", .5), ("D5", .5), ("E5", 1), ("D5", 3)]
    melody = np.zeros(length)
    at = 0.0
    for name, beats in tune:
        place_wrapped(melody, recorder(n(name) - 12, beats * beat * 0.92), at, 0.36)
        at += beats * beat
    assert abs(at - length_s) < 1e-6, (at, length_s)
    write("music/ruins_base", rms_normalize(loop_reverb(base, seconds=2.4, wet=0.32, tone=5000), -21), True)
    write("music/ruins_melody", rms_normalize(loop_reverb(melody, seconds=2.6, wet=0.35, tone=6000), -23), True)



def stingers() -> None:
    # Victory: D minor swells into D major under a tolling bell.
    seconds = 5.5
    out = np.zeros(int(seconds * SR))
    for v in ["D3", "F3", "A3", "D4"]:
        place(out, pad_voice(n(v), 2.2, 1800), 0.0, 0.25)
        place(out, choir_voice(n(v) + 12, 2.2), 0.0, 0.08)
    for v in ["D3", "F#3", "A3", "D4"]:
        place(out, pad_voice(n(v), 3.2, 2200), 1.8, 0.28)
        place(out, choir_voice(n(v) + 12, 3.2), 1.8, 0.1)
    place(out, clang(midi(n("D4")), 4.0, 0.7, 1.6), 1.8, 0.35)
    write("music/victory", normalize(fade(reverb(out, 4.0, 0.45, 4000), 0.01, 0.8), -3), True)
    # Defeat: two low bell tolls over a falling drone.
    out = np.zeros(int(seconds * SR))
    place(out, clang(midi(n("A2")), 4.0, 0.6, 1.8), 0.0, 0.5)
    place(out, clang(midi(n("D2")), 4.0, 0.6, 2.0), 1.5, 0.55)
    drone = pad_voice(n("D2"), 5.0, 500, 6) * np.linspace(1, 0.4, int(5.0 * SR))
    place(out, drone, 0.2, 0.35)
    write("music/defeat", normalize(fade(reverb(out, 4.0, 0.45, 3000), 0.01, 0.8), -3), True)


def ambience() -> None:
    # Wind: noise through a slowly wandering band, crossfaded so the loop has no seam.
    seconds = 24.0
    length = int(seconds * SR)
    raw = noise(length + SR * 2)
    low = lp(raw, 380, 2)
    mid = bp(raw, 380, 1400)
    t = np.linspace(0, 1, len(raw))
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * (t * 3 + 0.2 * np.sin(2 * np.pi * t * 2)))
    wind = low * 0.9 + mid * gust * 0.5
    stereo = np.stack([wind, np.roll(wind, int(0.37 * SR))], axis=1)
    head, tail = stereo[:SR * 2], stereo[length:length + SR * 2]
    loop = stereo[:length].copy()
    ramp = np.linspace(0, 1, SR * 2)[:, None]
    loop[:SR * 2] = head * ramp + tail * (1 - ramp)
    write("ambience/wind", rms_normalize(loop, -26), True)
    # Torch: crackles and a soft roar, mono for 3D placement.
    seconds = 8.0
    length = int(seconds * SR)
    fire = lp(noise(length), 300) * 0.5
    for _ in range(140):
        pop_len = int(rng.uniform(0.003, 0.012) * SR)
        pop = hp(noise(pop_len), 1500) * exp_decay(pop_len, 0.003)
        place_wrapped(fire, pop, rng.uniform(0, seconds), rng.uniform(0.2, 1.0))
    write("ambience/torch", rms_normalize(fire, -24), True)


def weather_audio() -> None:
    """Rain bed with discrete drops, a wind gust swell, two thunder rolls. Loops crossfade."""
    seconds = 12.0
    length = int(seconds * SR)
    extra = SR * 2
    hiss = hp(noise(length + extra), 1800) * 0.25 + bp(noise(length + extra), 500, 1800) * 0.35
    drops = np.zeros(length + extra)
    for _ in range(2600):
        drop_len = int(rng.uniform(0.004, 0.012) * SR)
        drop = bp(noise(drop_len), rng.uniform(1500, 4000), 7000) * exp_decay(drop_len, 0.003)
        place(drops, drop, rng.uniform(0, (length + extra) / SR - 0.02), rng.uniform(0.1, 0.6))
    bed = np.stack([hiss + drops, np.roll(hiss, SR // 3) + np.roll(drops, SR // 5)], axis=1)
    loop = bed[:length].copy()
    ramp = np.linspace(0, 1, extra)[:, None]
    loop[:extra] = bed[:extra] * ramp + bed[length:length + extra] * (1 - ramp)
    write("ambience/rain", rms_normalize(loop, -24), True)
    seconds = 8.0
    length = int(seconds * SR)
    t = np.linspace(0, 1, length)
    swell = np.sin(np.pi * t) ** 1.5
    raw = noise(length)
    gust = (lp(raw, 500) * 0.8 + bp(raw, 500, 2000) * 0.5 * swell) * (0.25 + 0.75 * swell)
    write("ambience/gust", rms_normalize(np.stack([gust, np.roll(gust, int(0.4 * SR))], axis=1), -24), True)
    for k in range(2):
        seconds = 6.0
        length = int(seconds * SR)
        roll = np.zeros(length)
        place(roll, lp(noise(int(0.25 * SR)), 2500) * exp_decay(int(0.25 * SR), 0.05), 0.0, 0.7 if k == 0 else 0.3)
        rumble = lp(noise(length), 140, 2) * exp_decay(length, 1.6 + k * 0.6)
        crackle = np.zeros(length)
        for _ in range(30):
            place(crackle, thump(0.4, rng.uniform(60, 120), 30, 0.12), rng.uniform(0.05, 2.5), rng.uniform(0.1, 0.4))
        roll += rumble * 3.0 + crackle
        write(f"ambience/thunder_{k}", normalize(fade(reverb(roll, 3.0, 0.45, 2500), 0.002, 1.0), -2), True)


if __name__ == "__main__":
    make_sfx()
    court_music()
    ruins_music()
    stingers()
    ambience()
    special_sfx()
    court_combat()
    ruins_combat()
    notice_stinger()
    weather_audio()
    impact_sfx()
    forest_audio()
    thornwood_sfx()
    zones_audio()
