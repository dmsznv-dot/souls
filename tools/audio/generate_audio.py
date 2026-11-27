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
    battle = np.zeros(length)
    for i, (bass, voices) in enumerate(chords):
        at = i * 8 * beat
        span = 8 * beat + 1.2
        for v in voices:
            place_wrapped(pad, pad_voice(n(v), span, 1200), at, 0.32)
            place_wrapped(pad, choir_voice(n(v) + 12, span), at, 0.11)
        place_wrapped(pad, pad_voice(n(bass), span, 380, 4), at, 0.5)
        # Battle: timpani on the root, low string ostinato in eighths.
        root = n(bass) + (12 if n(bass) < n("C2") else 0)
        for bar in range(2):
            bar_at = at + bar * 4 * beat
            place_wrapped(battle, timpani(root + 12, 1.4), bar_at, 0.9)
            place_wrapped(battle, timpani(root + 12, 1.0), bar_at + 2 * beat, 0.55)
            place_wrapped(battle, timpani(root + 19, 0.6), bar_at + 3.5 * beat, 0.4)
            for e in range(8):
                note = root + 12 + (7 if e % 4 == 2 else 0) + (12 if e == 7 else 0)
                stab = lp(saw(midi(note), beat * 0.45) + saw(midi(note) * 1.005, beat * 0.45), 900)
                stab *= env_adsr(len(stab), 0.005, 0.08, 0.5, 0.1)
                place_wrapped(battle, stab, bar_at + e * beat / 2, 0.16 if e % 2 else 0.22)
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
    write("music/court_pad", rms_normalize(loop_reverb(pad, seconds=4.5, wet=0.45, tone=3500), -21), True)
    write("music/court_melody", rms_normalize(loop_reverb(melody, seconds=4.0, wet=0.5, tone=4500), -23), True)
    write("music/court_battle", rms_normalize(loop_reverb(battle, seconds=2.2, wet=0.28, tone=3000), -22), True)


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
    battle = np.zeros(length)
    base += hurdy_drone([n("D2"), n("A2")], length_s) * 0.22
    buzz = []
    for i, chord in enumerate(progression):
        at = i * bar_s
        tones = shapes[chord]
        pattern = [tones[0], tones[1], tones[2], tones[3], tones[2], tones[1]]
        for k, tone in enumerate(pattern):
            place_wrapped(base, lute(n(tone), 1.6), at + k * beat / 2, 0.42 if k == 0 else 0.28)
        place_wrapped(battle, frame_drum(True), at, 0.9)
        place_wrapped(battle, frame_drum(False), at + beat, 0.5)
        place_wrapped(battle, frame_drum(False), at + 2 * beat, 0.5)
        place_wrapped(battle, frame_drum(False), at + 2.5 * beat, 0.35)
        place_wrapped(battle, jingle(), at + 1.5 * beat, 0.5)
        buzz += [at, at + beat, at + 2 * beat]
        for k in range(6):
            strum = lute(n(tones[k % 2 + 1]) + 12, 0.5)
            place_wrapped(battle, strum, at + k * beat / 2 + beat / 4, 0.12)
    battle += hurdy_drone([n("D3"), n("A3")], length_s, buzz) * 0.25
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
    write("music/ruins_battle", rms_normalize(loop_reverb(battle, seconds=1.6, wet=0.2, tone=5000), -22), True)


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


if __name__ == "__main__":
    make_sfx()
    court_music()
    ruins_music()
    stingers()
    ambience()
