# Endless DJ factory risers

These 32 mono, 48 kHz WAV files are original procedural sounds generated for
Endless DJ. They use conservative peak headroom and four families:

- 01–08: filtered noise / air
- 09–16: tonal oscillator lifts
- 17–24: metallic and FM-style digital lifts
- 25–32: hybrid noise/tonal rises with end impacts

Run `node tools/generate_factory_risers.js` from the repository root to
reproduce the exact files. Their use and distribution follows the repository's
license.

Every WAV here is original project material with origin `Endless DJ procedural
factory generator` and license `repository license`. `lib/sample_library.lua`
provides the authoritative per-file catalog: stable ID, role, energy,
genre-affinity tags, compatible processing and tonal-key metadata. Tonal lifts
09–16 and hybrid lifts 25–32 are catalogued at pitch class C for bounded
root-matching; the noise and metallic families remain explicitly atonal.
