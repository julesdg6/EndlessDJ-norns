# Endless DJ factory UI sounds

This folder contains original, redistributable factory WAV files used for
user-interface feedback inside Endless DJ.

## needle_skate.wav

A brief vinyl needle-skate sound played once after the `Endless` SuperCollider
engine initialises successfully on script load. It confirms readiness
immediately and reinforces the turntable identity of Endless DJ.

- Format: 16-bit PCM, 48 kHz, mono
- Duration: ~0.42 s
- Normalised peak: –2.9 dBFS

Regenerate with:

```sh
node tools/generate_factory_needle_skate.js
```

Every file in this folder is original project material with origin
`Endless DJ procedural factory generator` and license `repository license`.
