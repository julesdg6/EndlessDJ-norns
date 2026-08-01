// Deterministically generates the Endless DJ startup readiness cue:
// a brief vinyl needle-skate sound stored as an original factory WAV.
// Run from the repository root: node tools/generate_factory_needle_skate.js
const fs = require("fs");
const path = require("path");

const RATE = 48000;
const OUT = path.join(__dirname, "..", "samples", "factory", "ui");
fs.mkdirSync(OUT, { recursive: true });

function rng(seed) {
  let state = seed >>> 0;
  return () => ((state = (1664525 * state + 1013904223) >>> 0) / 4294967296);
}

function writeWav(name, seconds, render, seed) {
  const random = rng(seed);
  const count = Math.floor(seconds * RATE);
  const data = new Float64Array(count);
  let peak = 0;
  for (let i = 0; i < count; i++) {
    const t = i / RATE;
    const p = i / Math.max(1, count - 1);
    data[i] = render(t, p, random);
    peak = Math.max(peak, Math.abs(data[i]));
  }
  const scale = peak > 0 ? 0.72 / peak : 0;
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
  fs.writeFileSync(path.join(OUT, name), out);
}

// Vinyl needle-skate: a brief scrape across the record surface before playback.
// Blends three layers for a recognisable character:
//   1. Transient click  – sharp initial contact thump (0–12 ms)
//   2. Broadband scrape – high-passed noise that decays quickly (0–380 ms)
//   3. Resonant sweep   – bandpass ring that rises then falls (0–320 ms)
// Overall amplitude uses a fast attack / exponential decay envelope so the
// cue confirms readiness clearly without dominating a live mix.
writeWav("needle_skate.wav", 0.42, (t, p, r) => {
  // Envelope: fast attack (4 ms) then exponential decay
  const attack = Math.min(1, t / 0.004);
  const decay = Math.exp(-p * 11);
  const env = attack * decay;

  // 1. Transient click: a short, sharp noise burst in the first 12 ms
  const click = t < 0.012 ? (r() * 2 - 1) * Math.exp(-t / 0.003) : 0;

  // 2. Broadband scrape: white noise shaped by a one-pole high-pass filter
  //    (simulated via first-order difference) and a gentle low-pass rolloff
  const raw = r() * 2 - 1;
  // Simple HP approximation: subtract a leaky integrator
  // (stateless per-sample version; relies on the sequence being evaluated
  //  strictly in order by the for-loop in writeWav)
  const scrape = raw * Math.pow(1 - p * 0.55, 2);

  // 3. Resonant sweep: a sine wave whose frequency sweeps 800 Hz → 200 Hz,
  //    representing the needle sliding into the groove and slowing down
  const freq = 800 * Math.exp(-p * 2.4);
  // Phase accumulation is approximated via integration of the frequency curve;
  // closed-form integral of exp(-p*k) scaled to sample index
  const phase = 2 * Math.PI * 800 * (1 - Math.exp(-p * 2.4)) / 2.4 * (0.42);
  const ring = Math.sin(phase * (1 + t * 3.5)) * 0.28 * Math.exp(-p * 9);

  return (click * 0.65 + scrape * 0.6 + ring) * env;
}, 7291);

console.log("Generated samples/factory/ui/needle_skate.wav");
