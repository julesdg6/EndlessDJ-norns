// Deterministically regenerates Endless DJ's original factory riser library.
const fs = require("fs");
const path = require("path");

const RATE = 48000;
const OUT = path.join(__dirname, "..", "samples", "factory", "risers");
fs.mkdirSync(OUT, { recursive: true });

function rng(seed) {
  let state = seed >>> 0;
  return () => ((state = (1664525 * state + 1013904223) >>> 0) / 4294967296);
}

function wav(name, seconds, render, seed) {
  const random = rng(seed);
  const count = Math.floor(seconds * RATE);
  const data = new Float64Array(count);
  let peak = 0;
  for (let i = 0; i < count; i++) {
    const t = i / RATE;
    const p = i / (count - 1);
    const fade = Math.min(1, i / 240) * Math.min(1, (count - 1 - i) / 480);
    data[i] = render(t, p, random) * fade;
    peak = Math.max(peak, Math.abs(data[i]));
  }
  const scale = peak > 0 ? 0.78 / peak : 0;
  const out = Buffer.alloc(44 + count * 2);
  out.write("RIFF", 0); out.writeUInt32LE(36 + count * 2, 4);
  out.write("WAVEfmt ", 8); out.writeUInt32LE(16, 16);
  out.writeUInt16LE(1, 20); out.writeUInt16LE(1, 22);
  out.writeUInt32LE(RATE, 24); out.writeUInt32LE(RATE * 2, 28);
  out.writeUInt16LE(2, 32); out.writeUInt16LE(16, 34);
  out.write("data", 36); out.writeUInt32LE(count * 2, 40);
  for (let i = 0; i < count; i++) {
    out.writeInt16LE(Math.round(Math.max(-1, Math.min(1, data[i] * scale)) * 32767), 44 + i * 2);
  }
  fs.writeFileSync(path.join(OUT, name), out);
}

for (let n = 1; n <= 8; n++) {
  let low = 0;
  wav(`${String(n).padStart(2, "0")}_noise_air_${String(n).padStart(2, "0")}.wav`,
    2.4 + n * 0.19, (t, p, r) => {
      const noise = r() * 2 - 1;
      low += (noise - low) * (0.015 + p * 0.32);
      const pulse = Math.sin(2 * Math.PI * (3 + n * 0.3) * t) * 0.12;
      return (noise - low * 0.65 + pulse) * Math.pow(p, 1.4);
    }, 1000 + n);
}

for (let n = 1; n <= 8; n++) {
  let phase = 0;
  wav(`${String(n + 8).padStart(2, "0")}_tonal_lift_${String(n).padStart(2, "0")}.wav`,
    2.7 + n * 0.17, (t, p, r) => {
      const freq = (55 + n * 7) * Math.pow(8 + n * 0.7, p);
      phase += 2 * Math.PI * freq / RATE;
      return (Math.sin(phase) + 0.32 * Math.sin(phase * 2.01) +
        0.12 * (r() * 2 - 1)) * Math.pow(p, 1.25);
    }, 2000 + n);
}

for (let n = 1; n <= 8; n++) {
  let carrier = 0;
  let mod = 0;
  wav(`${String(n + 16).padStart(2, "0")}_digital_metal_${String(n).padStart(2, "0")}.wav`,
    2.2 + n * 0.21, (t, p, r) => {
      const base = (90 + n * 13) * Math.pow(5.5, p);
      carrier += 2 * Math.PI * base / RATE;
      mod += 2 * Math.PI * base * (1.7 + n * 0.11) / RATE;
      return (Math.sin(carrier + Math.sin(mod) * (2 + p * 7)) +
        0.18 * (r() * 2 - 1)) * Math.pow(p, 1.5);
    }, 3000 + n);
}

for (let n = 1; n <= 8; n++) {
  let phase = 0;
  wav(`${String(n + 24).padStart(2, "0")}_hybrid_impact_${String(n).padStart(2, "0")}.wav`,
    3.0 + n * 0.18, (t, p, r) => {
      phase += 2 * Math.PI * (48 + n * 5) * Math.pow(11, p) / RATE;
      const rise = (Math.sin(phase) * 0.55 + (r() * 2 - 1) * 0.38) * Math.pow(p, 1.35);
      const endBurst = Math.exp(-Math.pow((p - 0.965) * (42 + n), 2)) *
        ((r() * 2 - 1) + Math.sin(phase * 0.25));
      return rise + endBurst * 0.8;
    }, 4000 + n);
}

console.log(`Generated 32 mono 48 kHz risers in ${OUT}`);
