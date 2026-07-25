// Deterministically regenerates Endless DJ's original factory role one-shots.
const fs = require("fs");
const path = require("path");

const RATE = 48000;
const ROOT = path.join(__dirname, "..", "samples", "factory", "oneshots");

function rng(seed) {
  let state = seed >>> 0;
  return () => ((state = (1664525 * state + 1013904223) >>> 0) / 4294967296);
}

function writeWav(role, variant, seconds, render, seed) {
  const random = rng(seed);
  const count = Math.floor(seconds * RATE);
  const data = new Float64Array(count);
  let peak = 0;
  for (let i = 0; i < count; i++) {
    const t = i / RATE;
    const p = i / Math.max(1, count - 1);
    const fade = Math.min(1, i / 96) * Math.min(1, (count - 1 - i) / 240);
    data[i] = render(t, p, random) * fade;
    peak = Math.max(peak, Math.abs(data[i]));
  }
  const scale = peak > 0 ? 0.76 / peak : 0;
  const out = Buffer.alloc(44 + count * 2);
  out.write("RIFF", 0); out.writeUInt32LE(36 + count * 2, 4);
  out.write("WAVEfmt ", 8); out.writeUInt32LE(16, 16);
  out.writeUInt16LE(1, 20); out.writeUInt16LE(1, 22);
  out.writeUInt32LE(RATE, 24); out.writeUInt32LE(RATE * 2, 28);
  out.writeUInt16LE(2, 32); out.writeUInt16LE(16, 34);
  out.write("data", 36); out.writeUInt32LE(count * 2, 40);
  for (let i = 0; i < count; i++) {
    out.writeInt16LE(
      Math.round(Math.max(-1, Math.min(1, data[i] * scale)) * 32767),
      44 + i * 2
    );
  }
  const dir = path.join(ROOT, role);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, `${role}_${String(variant).padStart(2, "0")}.wav`),
    out
  );
}

for (let v = 1; v <= 4; v++) {
  let phaseA = 0;
  writeWav("perc_accent", v, 0.18 + v * 0.025, (t, p, r) => {
    phaseA += 2 * Math.PI * (240 + v * 55) * (1 - p * 0.65) / RATE;
    return (Math.sin(phaseA) * 0.7 + (r() * 2 - 1) * 0.3) * Math.exp(-p * 8);
  }, 5100 + v);

  let phaseB = 0;
  writeWav("alt_perc", v, 0.24 + v * 0.035, (t, p, r) => {
    phaseB += 2 * Math.PI * (520 + v * 90) * (1 + 0.08 * Math.sin(t * 40)) / RATE;
    return (Math.sin(phaseB) * 0.55 + (r() * 2 - 1) * 0.45) * Math.exp(-p * 6);
  }, 5200 + v);

  let phaseC = 0;
  writeWav("short_fill", v, 0.65 + v * 0.08, (t, p, r) => {
    const hit = (p * (5 + v)) % 1;
    phaseC += 2 * Math.PI * (150 + v * 28) * (1 - hit * 0.45) / RATE;
    return (Math.sin(phaseC) + (r() * 2 - 1) * 0.35) * Math.exp(-hit * 9) * 0.75;
  }, 5300 + v);

  let phaseD = 0;
  writeWav("long_fill", v, 1.25 + v * 0.13, (t, p, r) => {
    const hit = (p * (8 + v * 2)) % 1;
    phaseD += 2 * Math.PI * (105 + v * 22 + p * 180) / RATE;
    return (Math.sin(phaseD) + (r() * 2 - 1) * 0.42) * Math.exp(-hit * 8) * 0.72;
  }, 5400 + v);

  let phaseE = 0;
  writeWav("impact", v, 0.9 + v * 0.12, (t, p, r) => {
    phaseE += 2 * Math.PI * (75 + v * 6) * Math.pow(0.28, p) / RATE;
    return (Math.sin(phaseE) * 0.9 + (r() * 2 - 1) * 0.5) * Math.exp(-p * 4.5);
  }, 5500 + v);

  let phaseF = 0;
  writeWav("vocal_stab", v, 0.38 + v * 0.055, (t, p) => {
    const f0 = 105 + v * 17;
    phaseF += 2 * Math.PI * f0 / RATE;
    const vowel = Math.sin(phaseF) + 0.45 * Math.sin(phaseF * 2) +
      0.25 * Math.sin(phaseF * (3.1 + v * 0.08));
    return vowel * Math.exp(-p * (3.5 + v * 0.3));
  }, 5600 + v);

  let phaseG = 0;
  writeWav("drop_accent", v, 1.05 + v * 0.14, (t, p, r) => {
    const pitch = (48 + v * 5) * Math.pow(0.42, p);
    phaseG += 2 * Math.PI * pitch / RATE;
    const click = (r() * 2 - 1) * Math.exp(-p * 45);
    return (Math.sin(phaseG) * 0.85 + click + (r() * 2 - 1) * 0.18) *
      Math.exp(-p * 3.2);
  }, 5700 + v);
}

console.log(`Generated 28 mono 48 kHz factory role one-shots in ${ROOT}`);
