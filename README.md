You are helping develop a Monome Norns script called Endless DJ.

FINAL PHYSICAL ACCEPTANCE

After installing v1.147, stop normal playback and run this once in Maiden:

```lua
run_norns_test_harness("acceptance")
```

The acceptance run covers every registered engine command, all 96 deterministic
genre/archetype fixtures, factory samples, persistent first hits, resampling,
CPU/XRuns, and sequential bass/chord model loudness checks. Listen for each
model label and confirm that model changes alter colour without a large jump in
perceived level. The harness restores saved routing and mixer state afterward.

PROJECT GOAL

Endless DJ is a generative electronic music DJ system for Norns.

The goal is NOT to make a simple 16-step random sequencer.

The script should continuously generate complete, DJ-structured electronic tracks and automatically mix them together using two virtual decks.

Think of it as an endless AI/procedural DJ using external Roland AIRA hardware.

On every script launch, both virtual decks are generated through the normal
song-creation path. Deck A starts active, Deck B is queued, and their initial
genres are selected randomly without duplicating one another.

INSTALLING AND UPDATING ON NORNS

Install the complete repository, not only `EndlessDJ.lua` or the files in
`lib`. N-SAMPLER's factory sounds live under
`samples/factory/risers`, so partial updates will leave the sampler silent.

From Maiden's command line, this command downloads merged `main`, including all
32 riser WAV files, and copies it over the installed script:

```lua
os.execute("cd /tmp && curl -fL https://github.com/julesdg6/EndlessDJ-norns/archive/refs/heads/main.tar.gz -o EndlessDJ-main.tar.gz && tar -xzf EndlessDJ-main.tar.gz && mkdir -p /home/we/dust/code/EndlessDJ && rm -f /home/we/dust/code/EndlessDJ/endless_dj.lua && cp -R EndlessDJ-norns-main/. /home/we/dust/code/EndlessDJ/")
```

After installing or updating `Engine_Endless.sc`, restart Norns from
`SYSTEM → RESET → restart`. This lets SuperCollider recompile the custom
engine. Script parameter sets remain in `/home/we/dust/data/EndlessDJ` and are
not replaced by the command above.

`EndlessDJ.lua` is the canonical Norns entrypoint. The update command removes
the obsolete lowercase `endless_dj.lua` left by v1.65, preventing duplicate
scripts in Maiden and ensuring Norns launches the updated version.

Verify that the complete factory library arrived:

```lua
os.execute("find /home/we/dust/code/EndlessDJ/samples/factory/risers -maxdepth 1 -type f -name '*.wav' | wc -l")
```

The result must be `32`. After loading Endless DJ, Maiden should also print:

```text
Endless DJ: loaded 32 factory risers
```

For an immediate sound test, set `samples output` to `internal`, then enter:

```lua
engine.deck_level(1, 1)
engine.nsampler_hit(1, 17, 0.8, 1, 0, 0, 1, 1, 0)
```

This triggers the first factory riser without waiting for a generated song to
reach its BUILD section.

INTERNAL INSTRUMENTS / TRAVEL MODE

Endless DJ includes one custom SuperCollider engine named `Endless`. It provides
six Norns-native instrument roles:

- `n-808`: six synthesized drum voices with per-voice levels, shared tone,
  decay, drive, and variation controls, plus per-deck open/closed-hat choking
- `n-303`: persistent monophonic acid/bass voice with accent, legato slide,
  saw/square waveform, filter, envelope, decay, drive, and slide-time controls
- `n-bass`: an independent per-deck bass voice using analog, sub, Reese, organ,
  FM or wobble models selected only where they suit the generated genre
- `n-chord`: gated polyphonic chord voice with eight sound models, generated
  voicings and patches, and the Norns keyboard target
- `n-mono`: persistent monophonic lead/bass/pluck/FX voice with generated
  per-song patches and six interchangeable sound models: analog, sub, Reese,
  organ, FM and wobble/growl
- `n-sampler`: 16 user pads plus 32 bundled original risers with flexible
  playback controls, selected independently per generated song

The engine mixes internal Deck A and Deck B through separate stereo buses. The
existing Endless DJ crossfader drives those buses with an equal-power curve.

Bass parts are deterministic four-bar riffs rather than isolated random notes.
They leave deliberate gaps around kick hits, add a phrase-end turnaround and
retain the same riff identity through sections and transitions. Acid House uses
the n-303 with phrase-level accents and slides. UK Garage 2-Step explicitly
chooses deep sub, Reese, organ or FM bass and never defaults to acid; 303 is
eligible only for styles where it is musically intentional. External T-8 bass
receives the same generated notes, so existing MIDI behaviour is preserved.

Each bass family also has its own synthesis profile rather than sharing one
generic filter and envelope setting. Reese bass uses wider detuning and darker
movement, organ bass emphasizes bright stable harmonics, FM bass exposes a
stronger modulation index, and wobble bass uses deep resonant filter movement.
Small seeded patch variation remains, but cannot erase those audible family
differences.

Bass plans also declare low-end ownership explicitly. Reverse bass owns the
offbeats, industrial rumble owns the kick tail, and pitched-kick Hardstyle
suppresses the separate bass voice so the two layers cannot fight. Drop and
second-drop modulation are stored in the song plan and replay deterministically.

Groove plans now span deterministic 2, 4, 8 or 16-bar phrases according to
genre. Polymetric families rotate hat and percussion cycles across bar lines,
and each feel supplies its own phrase-ending fill roles, steps and velocities.
The same stored microtiming continues to drive internal and external parts.

INTERNAL MIXER

Every internal instrument now feeds its own stereo channel before reaching its
Deck A/B bus. The five channels are drums, bass, chords, mono, and samples.
Each channel has level, pan, low-pass filter, saturation, delay-send, and
reverb-send controls. The same performance settings are applied to the
corresponding channel on both decks, while their audio and effects remain
independent through transitions.

Two shared FX buses exist per deck. Every channel can send independently to
the tempo-neutral stereo delay or reverb bus, and the delay and reverb return
levels are adjustable. This bus layout is also the foundation for later live
resampling, because a future recorder can capture the complete post-channel,
post-effects deck signal.

The master stage applies adjustable stereo compression followed by a
look-ahead limiter. Master level, compressor amount, compressor threshold, and
limiter ceiling are exposed in parameters. Conservative defaults preserve the
existing mix while preventing simultaneous internal instruments or two-deck
overlap from exceeding the configured ceiling.

The auto mixer adds a musical starting balance to every generated song rather
than imposing one fixed mix on every genre. It gives drums, bass, chords, mono,
and samples deterministic per-song trims, with quieter chord and mono defaults
for bass- or percussion-heavy styles. `gentle`, `balanced`, and `assertive`
modes add progressively stronger kick/bass-aware ducking; `off` bypasses all
automatic trims and keeps the manual channel levels unchanged. Melody priority,
kick-to-bass ducking, target headroom, and two-deck transition compensation are
adjustable in the `INTERNAL MIXER` parameter group.

The kick and bass are measured once per deck on lightweight control buses.
Every channel reads those shared measurements, avoiding duplicate envelope
followers and preserving CPU headroom. Deck A and Deck B remain independent,
and transition compensation reduces only the summed overlap while both decks
are audible.

To preserve Norns CPU headroom, silent instrument channels, idle persistent
voices, unused effect returns, deck buses, and the master processor suspend
their audio calculations automatically. They wake before the next note,
sample, loop, granular voice, effect send, or crossfade-level change, so this
power saving does not alter sequencing or mixer controls.

The internal drum engine provides 808, 909, LinnDrum, industrial and hybrid
kits. Every generated record stores one genre-compatible kit in its song
identity; the choice remains stable for the record and is independent between
decks. Each kit/voice pair has a separate synthesis graph, so a hat hit
calculates only that selected hat rather than every voice and kit alternative.

The five n-chord synthesis engines and eight musical envelope roles are compiled
as separate graphs. Each note calculates only its song's selected engine/role
pair instead of every alternative, keeping polyphonic entrances within the
Norns audio budget.

In the `OUTPUT ROUTING` parameter group, drums, bass, chords, mono, and samples
can each be set manually to `off`, `external`, `internal`, or `both`. Every route
defaults to `external`, preserving the existing T-8, J-6, NTS-1, and MPX8 MIDI
behaviour after upgrading. Use `internal` for a Norns-only travel rig, or `both`
to layer the internal voice with the connected hardware.

The `N-808` parameter group shapes only the internal drum engine. Its six level
controls range from 0–150% for balancing voices, while tone, decay, drive, and
variation affect the whole kit. These settings do not alter external T-8 MIDI
notes or velocities.

Each generated song receives a stable, genre-shaped N-303 patch with bounded
random variation. The two decks retain independent patches, allowing distinct
outgoing and incoming bass timbres to overlap during a mix. The `N-303`
parameter group displays and edits the current deck's patch. A slide on one
pattern step glides into the following note without retriggering the amplitude
or filter envelopes. Accent raises amplitude, cutoff, and filter-envelope depth
together. A limiter bounds resonant and driven settings before the signal
reaches the deck mixer.

Each song also receives an independent, genre-shaped N-CHORD patch. It selects
one compatible synthesis engine—analog, FM, organ/piano, supersaw/pad, or
rave/hoover—plus one of eight envelope roles (house stab, deep chord, rave
chord, soft pad, organ, strings, detuned saw, or digital pluck). It then
generates inversion, octave spread, strum, brightness, filter-envelope, and
chorus settings. Engine choice is deterministic and remains fixed for the
record. These settings affect only the internal voice; external J-6 notes and
timing remain unchanged. The `N-CHORD` parameter group follows and edits the
current deck.
Grid keyboard notes targeting Norns now remain gated until their pads are
released.

Each song receives an independent N-MONO role and patch. Genre families favour
lead, bass, pluck, or FX settings, with saw/square/triangle oscillator choice,
sub level, resonant filter, attack/release, glide, LFO rate/depth, and stereo
delay send. A genre-compatible analog, sub, Reese, organ, FM or wobble/growl
model is selected once during song generation and stored with the deck; it
never changes randomly per note. UK Garage palettes exclude acid-only behavior
and favour sub, Reese, organ and FM models. One persistent voice is allocated
to each deck, so melodic notes
retrigger safely while pitch glide and effects remain continuous. External and
layered NTS-1 routing is unchanged.

N-SAMPLER includes 32 original mono factory risers in noise, tonal,
metallic/digital, and hybrid impact-rise families. The library loads
automatically, and each generated song selects one stable riser from the full
set. A further 28 original factory one-shots provide four stable variants for
each percussion accent, alternate percussion, short fill, long fill, impact,
vocal/FX stab, and drop-accent role. Every generated song chooses its own
repeatable role set from its variation seed. Each factory sound now has role,
genre/archetype affinity, energy, tonal-key capability, compatible processing,
vocal occupancy, origin and licensing metadata. Selection ranks compatible
sounds for the record instead of merely taking the seed modulo the file count.

Every role stores distinct primary and alternate choices. Hook A/B phrases and
second drops can therefore change vocal stabs, risers, impacts and drop accents
without changing the record's identity. Tonal risers are transposed within a
safe six-semitone range toward the generated root; atonal sounds remain at their
original rate. The phrase arrangement chooses when these roles occur, and
missing metadata or assets simply skip that trigger without altering other
random streams or external MPX8 behavior.

Sixteen persistent file parameters remain reserved for personal samples and do
not overwrite the factory performance banks. Select `n-sampler edit pad` to
change the chosen pad's level, pitch, reverse, pan, start/end position,
low-pass filter, choke group, and one-shot/gated mode. The test and release
parameters make every user pad immediately playable; eight factory-role test
parameters audition the automatically selected sounds without waiting for a
song section. Missing user files are reported and skipped safely.

The existing MPX8 events now map to matching internal factory roles when
samples output is `internal` or `both`. External MPX8 notes, configuration, and
the default external route remain unchanged.

ADVANCED N-SAMPLER — LOOPS AND SLICES

Each user pad can act as a tempo-synchronized loop or an 8/16-slice source.
Set the pad's source BPM to the tempo at which its file was recorded. Endless
DJ repitches playback by `current BPM / source BPM`, so it stays aligned when
the master tempo changes. This phase uses classic sampler repitching rather
than independent time-stretching; changing speed also changes pitch.

Loop sync starts persistent nodes on bar boundaries and keeps Deck A/B nodes
independent through the crossfader. A BPM change restarts the loop smoothly at
the next bar. Switching samples output away from internal, stopping transport,
cleaning up, or reloading the script releases every loop node.

Slice mode divides the selected start/end range into 8 or 16 equal pieces.
Controls provide forward, reverse, or deterministic random rearrangement,
per-slice reverse probability, repeat/stutter probability, trigger
probability, and Deck A/Deck B/both targeting. Choices derive from the
generated deck's variation seed, bar, step, and pad, making them varied but
repeatable for that song. Loop and slice modes are mutually exclusive.

Suggested setup:

1. Assign a rhythmic WAV to one of the 16 user pads.
2. Set its source BPM.
3. Choose loop sync, or choose 8/16 slices.
4. For slices, set order, reverse, repeat, and probability amounts.
5. Choose Deck A, Deck B, or both.
6. Set samples output to `internal` or `both`, then start transport.

GRANULAR N-SAMPLER

Each user pad can also become a persistent granular texture. Granular mode is
mutually exclusive with loop and slice modes. Its controls set the centre
position, grain size, density, playback rate, stereo spread, and freeze state.
With freeze off, the read position scans through the sample; freeze holds the
selected position while grains continue to play.

Every generated song receives a stable genre-shaped granular patch. Ambient,
dub, and melodic styles favour longer, airier grains; harder and faster styles
favour shorter, denser textures; broken-beat styles use tighter rhythmic
settings. The user pad controls remain the base settings, while the song patch
adds bounded variation that remains stable for the life of that deck.

Only one granular node can run per deck, with a maximum of 24 overlapping
grains per node and density capped at 32 grains per second. This keeps Deck A
and Deck B independent during a transition while bounding Norns CPU use.
Starting another granular pad on the same deck replaces the previous texture.
Stopping transport, changing the sample route away from internal, cleanup, and
engine all-off release both granular nodes.

To try it:

1. Assign a WAV to a user pad and select that pad for editing.
2. Enable granular mode and choose Deck A, Deck B, or both.
3. Adjust position, size, density, rate, spread, and freeze.
4. Set samples output to `internal` or `both` and start transport.
5. Use `start granular texture` and `stop granular texture` for immediate
   auditioning without waiting for the sequencer.

LIVE RESAMPLING

Two dedicated stereo capture slots can record Deck A post-FX, Deck B post-FX,
or the combined master mix. Recording is armed from parameters and begins on
the next bar boundary, with selectable lengths of 1, 2, 4, or 8 bars. Each
slot is capped at 32 seconds, keeping total buffer memory predictable on Norns.
The capture slots are separate from the 16 user pads and 60 factory samples,
so recording never overwrites the installed sample library.

Captured audio can be sent to Deck A, Deck B, or both as a one-shot, persistent
loop, selected 8/16 slice, or CPU-bounded granular texture. Playback level and
rate are shared controls; slice number and the granular position, size,
density, spread, and freeze controls shape the selected replay mode. Resampled
audio enters the destination deck bus directly, so deck crossfading and
mastering remain active without depending on the one-shot sampler channel.

To capture a transition or phrase:

1. Start Endless DJ playback.
2. Choose the source, capture slot, and bar length.
3. Trigger `arm quantized recording`; Maiden reports when the slot starts and
   when it is ready.
4. Choose the destination and replay mode.
5. Trigger `play captured audio`; use `stop resampling` to stop record arming,
   active recording, loops, or granular playback.

Recording the master while a captured loop is already playing will
intentionally capture that loop again. Lower the resample level or stop existing
resample playback first when you do not want layered generations.

PHYSICAL NORNS TEST HARNESS

Endless DJ includes a single repeatable Maiden test entry point. It temporarily
routes all parts internally, never sends test MIDI to external hardware, and
restores the saved output routes after cleanup.

For a fast engine, asset, instrument, and cleanup smoke test:

```lua
run_norns_test_harness("quick")
```

Before merging a substantial Lua or SuperCollider change, run:

```lua
run_norns_test_harness("full")
```

For the same complete test with explicit listening reminders:

```lua
run_norns_test_harness("interactive")
```

The harness reports the script version and registered engine commands, confirms
the 32 factory risers and 28 role one-shots, exercises n-808, n-303, n-chord,
n-mono, n-sampler, both decks, mixer, FX, mastering, sampler modes and live
resampling, records maximum CPU average/peak, and scans only the fresh test
window for XRuns, overruns, or underruns. Every run stops its polls, notes,
loops, grains, resampling and temporary voices even when a stage fails.

The final summary uses `ENDLESS HARNESS PASS` or identifies the exact failing
stage. `ENDLESS_HARNESS_XRUN_COUNT 0` is required for a clean full run.

The previous command remains as a compatibility alias for a full run:

```lua
run_resample_test_harness()
```

## Deterministic generation regression suite

The musical generators have a separate off-device regression suite. It checks
all 24 genres, all four archetypes per genre, deterministic replay, independent
Deck A/B identities, named random-stream isolation, groove and bass safety,
phrase-aligned arrangements, stylistic 303 eligibility, and record diversity.

Run the bounded CI suite with:

```sh
lua tests/check_generation.lua quick
```

Before merging major generator changes, run the statistical suite. It generates
1,000 independent records per genre (24,000 total):

```sh
lua tests/check_generation.lua full
```

Failures name the genre, archetype, and seed so the exact record can be replayed.
The shared `lib/generation_fixtures.lua` manifest supplies one golden listening
fixture for every genre/archetype pair (96 records) to both this suite and the
physical Norns harness.

Human listening is still required to confirm that each voice is audible,
balanced and free from clicks or distortion; automated checks cannot judge
musical quality.

The internal architecture also leaves room for genre-selected 808, 909,
LinnDrum, or mixed drum kits, FM-based chord voices, and alternate mono-synth
models in future milestones.

HARDWARE

Norns is the sequencer and conductor.

Roland T-8:
- MIDI channel 10: drums
- MIDI channel 8: acid bass

Roland J-6:
- MIDI channel 6: chords/synth
- Connected through the Roland AIRA MX-1 USB hub
- Program Change should optionally randomise J-6 sounds/pattern programs
- Program Change channel must be configurable

Roland AIRA MX-1:
- Physical audio mixer and USB MIDI hub
- All MIDI from Norns is routed via the MX-1 (Norns connects to MX-1; T-8 and J-6 plug into the MX-1 USB hub)
- The MX-1 presents TWO USB MIDI ports to the host (Norns):
    Port 1 ("Roland MX-1"): the MX-1's own control/FX channel — use this for mx1 device (Beat FX CC, transport)
    Port 2 ("Roland MX-1 MIDI"): pass-through to the T-8/J-6 connected to the MX-1 hub — use this for t8 device and j6 device
  Select each by name in the Norns params menu.
- Because all devices share the same USB MIDI interface, the default MIDI device for T-8, J-6, and MX-1 FX control is all device 1
- If the T-8/J-6 enumerate as separate USB MIDI devices through the hub, adjust the "t8 device" and "j6 device" params accordingly
- Beat FX depth is automated via MIDI CC during mix transitions (sinusoidal ramp: zero → peak at mid-mix → zero)
- Default Beat FX CC: 12 (Roland MX-1 Beat FX depth); default system channel: 1
- MX-1 transport is supported: START/PLAY and CONTINUE start Norns playback, STOP halts playback

GRID CONTROLLER (OPTIONAL)

Endless DJ supports a 16×8 grid controller for live performance.  The recommended
setup uses two Launchpad Mini MK3 controllers connected through the midigrid mod,
which exposes them as a single 16×8 virtual grid.  A real monome 128 also works.

midigrid setup (two Launchpad Mini MK3)
1. Install the midigrid mod:
     SYSTEM → MODS → install midigrid  (https://github.com/jaggednz/midigrid)
2. In midigrid settings:
     SYSTEM → MODS → MIDIGRID → layout → 128
3. Physical orientation: place both controllers flat with the logo at the bottom.
   The left controller (x = 1–8) handles the drum sequencer; the right controller
   (x = 9–16) handles the synth lanes and keyboard.
4. Rotation: leave "rotate second device" DISABLED.  Both controllers should be
   in the same physical orientation.  Do not enable rotation inside midigrid for
   this setup.
5. Colours: distinct instrument colours (kick=red, snare=yellow, open hat=green,
   closed hat=blue, etc.) are applied automatically when the script connects to
   the grid. No manual palette selection is required. Maiden reports how many
   attached devices accepted the palette; warnings identify a missing palette,
   unavailable virtual-grid devices, or a driver without an RGB lookup table.

The Launchpad driver must expose an `rgb_lut` table. The current SysEx RGB
driver is recommended. If the pads remain a single colour, paste
`tools/grid_diagnostics.lua` into Maiden. It reports driver/RGB capability,
injects the Endless DJ palette, forces a complete refresh, and displays levels
0–15 across the first two rows. Check that midigrid is active, layout is 128,
and rotation is disabled before running the diagnostic.

16×8 control map
  The left half (x = 1–8) and right half (x = 9–16) are independent sections.
  y = 1 is the top row; y = 8 is the bottom row.

LEFT HALF – four-lane drum sequencer (x = 1–8)

  y 1–2  Kick:        row 1 = steps 1–8,  row 2 = steps 9–16
  y 3–4  Snare:       row 3 = steps 1–8,  row 4 = steps 9–16
  y 5–6  Open hi-hat: row 5 = steps 1–8,  row 6 = steps 9–16
  y 7–8  Closed hat:  row 7 = steps 1–8,  row 8 = steps 9–16

  Press any pad to toggle that step on/off.
  The playhead cursor moves across both rows of each pair; active steps under
  the cursor are shown brighter (LEVEL_HOT = 15).

RIGHT HALF – synth lanes and keyboard (x = 9–16)

  y 1–2  NTS-1 melody trigger pattern (16 steps)
  y 3–4  J-6 chord trigger pattern (16 steps)

  Press any pad in y 1–4 to toggle whether the instrument fires on that step.
  The pattern is pre-loaded with the genre's default timing when the deck changes.
  Pitch and chord content always comes from the active deck's musical identity.

  y 5–8  Chromatic keyboard (32 pads, 4 rows × 8 columns)

  Row y = 8 (bottom): kb_base + kb_octave×12 to +7
  Row y = 7:          +8 to +15
  Row y = 6:          +16 to +23
  Row y = 5 (top):    +24 to +31

  Default kb_base = 48 (C3); adjust "keyboard octave" in params (GRID section).
  Root note pads are highlighted (LEVEL_ROOT = 11); in-scale pads use
  LEVEL_SCALE = 12; all other chromatic pads use LEVEL_CHROMA = 13.
  Pressed pads show LEVEL_PRESSED = 14.

  Keyboard MIDI target: set "keyboard target" param to nts1, j6, or norns.
  Changing target sends note-off for any held notes before switching.
  All held notes are also released on script cleanup and grid disconnect.

Fallback behaviour
  Endless DJ continues generating music when no grid is connected.
  The drum patterns revert to the genre defaults when no grid is active.
  Grid disconnection does not interrupt playback.

MX-1 MIDI THRU

To pass MIDI from Norns through the MX-1 to the T-8 and J-6:
1. On the MX-1, ensure USB MIDI mode is enabled (check MX-1 system settings / USB MIDI switch).
2. Norns sends to Port 2 of the MX-1 (the pass-through port).  In the script params, set "t8 device" and "j6 device" to the port named "Roland MX-1 MIDI" (or whichever name shows the pass-through port on your system).
3. The T-8 and J-6 must be connected to the MX-1's USB hub ports, not directly to Norns.

LIVE SET PREP (CLEAR DEVICE PATTERNS)

To avoid onboard sequencer patterns from fighting the generated MIDI:

1. On the J-6, clear the currently selected pattern.
2. On the T-8, clear the currently selected pattern.
3. Save/write those cleared patterns on both devices so they persist after reboot/power-cycle.
4. Confirm Endless DJ is driving notes from Norns and hardware patterns are silent.

This gives Norns clean control when playing over MIDI.

Exact clear/write button steps can vary by firmware, so follow the current pattern clear + write procedure in each device manual:
- Roland J-6 (Chord Synthesizer) manual/reference
- Roland T-8 (Beat Machine) manual/reference

T-8 DRUM MIDI MAP

Bass Drum:
Tx 36
Rx 35, 36

Snare:
Tx 38
Rx 38, 40

Hand Clap:
Tx 50
Rx 48, 50

Tom:
Tx 47
Rx 45, 47

Closed Hi-Hat:
Tx 42
Rx 42, 44

Open Hi-Hat:
Tx 46
Rx 46

Use the correct T-8 notes. In particular, HAND CLAP IS MIDI NOTE 50, NOT GENERAL MIDI NOTE 39.

KORG NTS-1 (OPTIONAL MELODIC VOICE)

The NTS-1 acts as a restrained monophonic lead/melody voice layered on top of the J-6 chords.
It is disabled by default and has no effect when disabled or disconnected.

MIDI routing
- Connect the NTS-1 directly to a USB host port on Norns (or via a USB hub).
  Keep its USB MIDI connection separate from the T-8, J-6, and MX-1 chain.
- In the Norns params menu (KORG NTS-1 section):
    nts1 device  – select the USB MIDI port that corresponds to the NTS-1 ("NTS-1 digital kit" or similar)
    nts1 channel – default 1.  Must match the NTS-1's MIDI channel setting (see below).
    nts1 enabled – set to "on" to activate.
    nts1 variation – controls phrase-boundary motif mutation amount.
    nts1 motif density – controls rhythmic hit density.
    nts1 register – shifts melodic register up/down.
    nts1 cc automation – enables/disables timbre CC scene automation.

Required NTS-1 settings
1. On the NTS-1, hold SHIFT and press OSC to enter the MIDI settings screen.
2. Set the receive channel to match the "nts1 channel" param (default Ch 1).
3. Enable "MIDI RX SHORT MESSAGE" so the NTS-1 processes incoming Note On/Off.
   (This setting may be labelled "MIDI RX MSG" in some firmware revisions.)
   Without it the NTS-1 will ignore incoming MIDI notes.
4. The NTS-1 does not respond to MIDI Program Change; sound design is done
   directly on the device.

How it plays
- Each deck gets a stable NTS-1 identity: scale-safe base motif, rhythm pattern,
  note lengths, density, register, timbre scene, and variation seed.
- Motifs are monophonic and chord-compatible; mutations are controlled and only
  applied on 4/8/16-bar phrase boundaries (never mid-phrase).
- INTRO/BREAK stay sparse; GROOVE/MAIN establish motif; BUILD increases density,
  register, and timbral movement; DROP returns a strong motif variant.
- During MIX/OUTRO the outgoing deck simplifies while the incoming deck starts to
  introduce its motif in the melody transition phase.
- The NTS-1 does not use Program Change. Timbre evolution uses bounded MIDI CC
  scene automation with change-threshold caching and CC rate limiting.

Test procedure
1. Enable "nts1 enabled" and confirm the device is selected.
2. Open the params menu and press "nts1 test note" to fire a single middle-C.
   You should hear the NTS-1 sound for a short note.
3. Start playback; the NTS-1 should remain silent during INTRO and start
   playing from GROOVE onward.

AKAI MPX8 (OPTIONAL SAMPLE LAYER)

The MPX8 is a supplementary one-shot sample layer for percussion accents,
fills, impacts, risers, and vocal/FX stabs.  It is not a replacement for the T-8.
It is disabled by default and has no effect when disabled or disconnected.

MIDI routing
- Connect the MPX8 directly to a USB host port on Norns (separate from the
  T-8/J-6/MX-1 chain).
- In the Norns params menu (AKAI MPX8 section):
    mpx8 device  – select the USB MIDI port that corresponds to the MPX8
    mpx8 channel – default 10.  Must match the MPX8's MIDI receive channel.
    mpx8 enabled – set to "on" to activate.

Factory kit defaults (Internal Kit i01)
Use the MPX8's first factory Internal Kit (`i01`) for plug-and-play defaults.
Endless DJ does not select kits over MIDI; select `i01` on the MPX8 itself.

The eight MPX8 pads trigger samples by MIDI note number. Endless DJ defaults
to the `i01` factory pad notes:

 Pad  i01 sample (factory)  Default note  Endless DJ role
 ───  ────────────────────  ────────────  ────────────────────
 1    Kick                  36            Percussion accent
 2    Snare                 38            Alternate percussion
 3    Closed hi-hat         42            Short fill
 4    Open hi-hat           46            Long fill
 5    Low tom               43            Impact
 6    Mid tom               47            Riser
 7    Crash                 49            Vocal / FX stab
 8    Ride                  51            Drop accent

You can still customize all eight pad notes with the `mpx8 padN ...` params.
This keeps custom/user kits fully supported.

Required MPX8 settings
- Set the MPX8 MIDI receive channel to match the "mpx8 channel" param (default 10).
- Select Internal Kit `i01` on the MPX8 hardware.
- Tuning, reverb, trigger mode, level, panning, and sample assignment remain
 under MPX8 control.

How it plays
- Riser (pad 6) fires once at the first bar of the BUILD section.
- Impact (pad 5) and drop accent (pad 8) fire once at the first bar of DROP.
- Short fill (pad 3) triggers at every 4-bar boundary in MAIN/BUILD/DROP.
- Long fill (pad 4) triggers at every 8-bar boundary.
- Vocal/FX stab (pad 7) fires at the start of every 8-bar phrase in MAIN/DROP.
- Percussion accents (pads 1-2) fire at regular intervals derived from the
  deck's variation seed to keep them consistent throughout the track.
- During a mix the recurring samples follow the "other drums" phase (phase 3,
  bars 17-24 of the 32-bar crossfade).
- One-shot transition samples (riser, impact, drop accent) are tracked per deck,
  so they fire exactly once even when both virtual decks are playing simultaneously.

Test procedure
1. Enable "mpx8 enabled" and confirm the device is selected.
2. In params, press each "mpx8 test padN" trigger and verify the corresponding
   `i01` pad plays.
3. Optionally press "mpx8 test all pads" to fire all 8 pads in sequence
   (4-tick gap between each).
4. Start playback; confirm samples fire at the appropriate section boundaries.

CORE CONCEPT

There are two virtual DJ decks:

DECK A
DECK B

Each deck represents a generated track.

A generated track should have:

- genre
- root/key
- chord progression
- drum identity
- bass pattern
- chord playing style
- J-6 program
- arrangement
- musical variations

Tracks must feel like complete dance records rather than repeating 16-bar loops.

SUPPORTED GENRES

Initially support:

- House
- Funky House
- Dirty House
- Techno
- UK Garage 4x4
- UK Garage 2-Step
- Nu-Skool Breaks
- Dubstep

The genre must affect ALL musical generation.

Do not simply change a genre label.

Each genre needs its own:

- kick placement
- snare/clap placement
- hi-hat language
- fills
- rhythmic density
- bass rhythm
- bass note choices
- bass note lengths
- chord progressions
- chord rhythm
- chord voicing
- chord performance styles
- arrangement tendencies
- breakdown behaviour
- build behaviour
- drop behaviour

For example:

House:
4x4 kick, claps on 2/4, offbeat hats, rolling acid bass.

Funky House:
syncopated bass, brighter major/seventh chords, chord stabs, busier percussion.

Dirty House:
4x4 but heavier, darker minor chords, aggressive bass and short stabs.

Techno:
relentless kick, sparse chords, repetitive/hypnotic bass motifs, tom percussion.

UK Garage 4x4:
4x4 foundation with shuffled hats, syncopated bass and offbeat chords.

UK Garage 2-Step:
broken kick pattern, strong snare/clap backbeat, shuffled hats, highly syncopated bass and chord stabs.

Nu-Skool Breaks:
broken kick/snare patterns, energetic fills, syncopated bass and darker chord movement.

Dubstep:
half-time drum feel, heavy low bass, sparse chords and long note space.

TRACK STRUCTURE

Tracks should follow DJ-friendly phrase structure.

Current conceptual arrangement is approximately:

Bars 1-16: INTRO
Bars 17-32: GROOVE
Bars 33-64: MAIN
Bars 65-80: BREAK
Bars 81-96: BUILD
Bars 97-120: DROP
Bars 121-128: MIX/OUTRO

However, genre-specific arrangements are encouraged.

All major changes should happen on predictable phrase boundaries:

- 4 bars
- 8 bars
- 16 bars
- 32 bars

A DJ should be able to understand where the track is going.

Avoid random changes in musically inappropriate places.

ENDLESS DJ MIXING

The next deck must start BEFORE the current track finishes.

The incoming deck begins 32 bars before handover, split into four 8-bar phases.

During those 32 bars each group of elements is swapped one phase at a time:

- Phase 1 (bars 1-8 of mix):  kick drum fades out on outgoing deck, fades in on incoming deck
- Phase 2 (bars 9-16 of mix): bass fades out on outgoing deck, fades in on incoming deck
- Phase 3 (bars 17-24 of mix): remaining drums (snare, hats, clap, tom) swap between decks
- Phase 4 (bars 25-32 of mix): chords and melody swap between decks

At handover the incoming track MUST NOT restart at bar 1.

It has already played 32 bars during the mix, so it continues from bar 33.

This is essential.

The system should behave like two real DJ decks playing simultaneously.

Eventually transitions should become genre-aware.

Examples:

House -> Techno:
long percussion blend.

2-Step -> Breaks:
rhythmic blend.

Dubstep -> House:
breakdown or reset transition rather than blindly overlaying incompatible rhythms.

MUSICAL GENERATION

Do not generate every note independently with math.random().

Generate a track identity when a deck is created.

For example a deck could contain:

deck.genre
deck.root
deck.scale
deck.chord_progression
deck.bass_pattern
deck.drum_pattern
deck.chord_style
deck.program
deck.variation_seed

Patterns should then evolve from this identity.

The listener should recognise a track for several minutes.

Variation should occur at phrase boundaries.

Examples:

- remove kick for one bar
- open hi-hat variation
- snare fill
- tom fill
- bass mutation
- octave bass variation
- chord inversion
- chord rhythm variation
- breakdown
- build
- drop

The system should balance repetition and variation.

J-6 CHORDS

Norns generates the MIDI notes sent to the J-6.

Chord performance styles should include things such as:

- block chords
- short stabs
- offbeat stabs
- upward arpeggio
- downward arpeggio
- up/down arpeggio
- strum

Styles should be genre appropriate.

Do not randomly select a completely different chord style for every chord.

A generated track should normally choose one or two chord performance identities and retain them, with controlled variation.

J-6 sound/program randomisation should occur when generating/loading a new deck, not constantly during a track.

USER INTERFACE

The Norns screen represents a minimal DJ setup.

Keep the UI simple.

It should show:

- two animated turntables
- Deck A
- Deck B
- one crossfader
- BPM
- current section/bar
- genre information

Do not turn the screen into a complex mixer UI.

The visual reference is the Norns script:

https://github.com/adamstaff/turntable

Study its turntable drawing and animation implementation.

Our decks should visually feel similar:

- convincing spinning record/platter
- animated centre label or record marker
- tonearm/needle
- needle gradually moves inward as the generated track progresses

There must be TWO compact decks on the 128x64 Norns screen.

The crossfader should visually move between them during an automatic mix.

CONTROLS

K2:
Play/stop.

K3 while playing:
Skip/force towards the next mix for testing.

K3 while stopped:
Send a J-6 MIDI chord/program test.

K1 must not be hijacked in a way that prevents normal Norns navigation/exit behaviour.

E2:
BPM.

E3:
Manual crossfader control when enabled.

PARAMS

Norns params should expose at least:

- T-8 MIDI device
- J-6 MIDI device
- MX-1 MIDI device
- MX-1 Beat FX enabled
- MX-1 system channel
- MX-1 Beat FX depth CC
- BPM
- drum MIDI channel
- bass MIDI channel
- chord MIDI channel
- J-6 Program Change enabled
- J-6 Program Change channel
- J-6 minimum program
- J-6 maximum program
- automatic/manual crossfader mode
- Launchpad MIDI device

LAUNCHPAD / GRID

Two Launchpad Mini MK3s are connected to the Norns.

The first launchpad functions as a live drum step sequencer.
The second launchpad is a real-time instrument activity monitor.

Layout of the first launchpad (8×8 grid, top row = row 8):

  Row 8-7: Kick       (red)
  Row 6-5: Snare      (yellow)
  Row 4-3: Open Hat   (green)
  Row 2-1: Closed Hat (blue)

Each pair of rows covers 16 steps: the upper row holds steps 1-8, the lower
row holds steps 9-16.

Pressing a pad toggles that step on or off.

A moving playhead cursor (brighter shade of the lane colour) shows the
currently playing step.

When a Launchpad is connected:
- Kick, snare, open hat and closed hat are driven by the pad pattern.
- Clap, tom and bar fills remain generative as before.

On deck handover the launchpad pattern is reinitialised from the incoming
deck's genre base pattern so the grid immediately reflects the new track.

Layout of the second launchpad (8×8 grid, programmer mode):

  Top 4-row block (rows 8-5): BASS
    Rows 8-7: bass 16-step display (row 8 = steps 1-8, row 7 = steps 9-16)
    Rows 6-5: bass activity on the current step

  Bottom 4-row block (rows 4-1): CHORDS
    Rows 4-3: chord trigger-step display (row 4 = steps 1-8, row 3 = steps 9-16)
    Rows 2-1: chord/norns activity on the current step

Current step uses brighter colours (amber for bass, purple for chords).

Both Launchpads must be in programmer mode (sent automatically on connect via
SysEx).  The LAUNCHPAD section in PARAMS lets you choose which MIDI device
number is assigned to each pad ("launchpad device" for LP1, "lp2 device" for
LP2).

LAUNCHPAD CONNECTION (MIDI vs HID)

The script supports two ways to connect a Launchpad Mini MK3:

1. Direct MIDI (default): The Launchpad appears as a MIDI device in Norns.
   Select it by name using the "launchpad device" param.

2. midigrid (HID or multi-device): If the Launchpad appears as an HID device
   or you use the midigrid library, install midigrid first:
     https://github.com/jaggednz/midigrid
   When midigrid is installed, the script automatically uses it and the
   "launchpad device" param is ignored (midigrid finds the device by name).

If the launchpad is absent the script falls back to fully generative drums.

CODE QUALITY

This is becoming a real GitHub project.

Do not rewrite the entire script into a shorter simplified example.

Preserve working functionality.

Prefer a data-driven architecture.

Genre definitions should ideally be structured data rather than hundreds of scattered:

if genre == "HOUSE"

conditions.

For example:

genres = {
  HOUSE = {
    drums = {...},
    bass = {...},
    chords = {...},
    arrangement = {...},
    transition = {...}
  }
}

Separate:

- transport
- deck generation
- genre definitions
- drum generation
- bass generation
- chord generation
- MIDI output
- DJ mixing
- UI drawing

where practical.

IMPORTANT DEVELOPMENT RULE

Before changing code:

1. Read the existing implementation.
2. Understand the current transport and two-deck state.
3. Preserve known working behaviour.
4. Make focused changes.
5. Check Lua syntax.
6. Consider Norns API compatibility.
7. Do not silently remove features.

The immediate objective is to turn the current prototype into a genuinely endless, genre-aware generative DJ that produces recognisable electronic tracks with proper DJ phrase structure and mixes them continuously using the T-8 and J-6.

SONG IDENTITY FOUNDATION

Every newly generated deck owns a deterministic `identity` record. It stores
the deck seed lineage, genre archetype, groove family, drum-kit family,
harmony family, arrangement family and stem-role metadata. Named child random
streams isolate patches, groove, bass, harmony, motifs, samples, fills and
arrangement so adding a choice to one subsystem cannot silently rewrite the
rest of a tune.

The same seed, deck label and genre reproduce the same serialized identity;
Deck A and Deck B use separate streams. In Maiden, inspect the active record
with:

    print_song_identity()

or preview an identity without changing playback:

    tab.print(generate_song_identity(42042, "A", "TWO_STEP"))

GROOVE PLANS

Every generated deck also owns a deterministic 2, 4, 8 or 16-bar groove plan. The plan
selects a genre-compatible feel, stable velocity arcs, ghost-note roles,
microtiming offsets and a phrase-boundary turnaround. With no grid connected it
drives generated drums directly; a connected grid keeps its editable pattern
while inheriting the plan's velocity and phrase metadata. Timing offsets are
stored for the shared scheduler rather than approximated with random per-hit
delays.

PHRASE ARRANGEMENT AND ENERGY CURVES

Each record now stores a deterministic 128-bar arrangement selected from
genre-compatible club-linear, hook A/B, double-drop and slow-burn grammars.
The first 96 bars contain purposeful intro, groove, main, breakdown, build,
drop, development and optional outro roles; the final 32 bars remain the DJ
transition window. Every section exposes phrase position plus independent kick,
percussion, bass, chord, mono, sample and FX envelopes. These stored envelopes
replace the universal section template and make energy changes repeatable rather
than depending on unrelated per-note randomness.

Risers and impacts are emitted by section-boundary events in the arrangement
plan. A double-drop record can therefore have distinct first and second build/drop
cues. The Norns display shows the active section and phrase position, while the
same metadata drives the stem-aware transition system.

STEM-AWARE DJ TRANSITIONS

The final 32 bars are planned as four deterministic eight-bar phrases across
kick, percussion, bass, chords, lead, samples/vocals and FX. Each transition
stores its outgoing and incoming song seeds, mode, strategy, harmonic warning,
stem envelopes and low-end ownership. Automatic Stem DJ and Producer DJ plans
never create an accidental double kick or double bass; Classic DJ retains a
bounded conventional blend and the manual crossfader fallback.

Available strategies are bass swap, percussion overlay, vocal tease, clean cut,
FX exit and classic blend. Selection considers the genre pair, energy seed and
harmonic distance, with explicit plans for representative contrasting pairs and
a safe clean-cut/FX fallback when compatibility is poor. Encoder 1 selects a
stem during a transition, Encoder 2 assigns it to the outgoing deck, incoming
deck or off, Encoder 3 retains manual crossfading, and Key 3 cancels safely.
The screen shows both genres, mode, strategy, phrase progress, kick/bass owner,
selected stem, warnings and next-phrase entries/exits. Deck A/B low, mid and
high EQ remain available in parameters for manual and Classic DJ operation.

SHARED MICROTIMING SCHEDULER

Groove offsets are delivered by one bounded six-pulse-per-step queue shared by
internal instruments and external MIDI. Drums, bass, chords, mono parts and
samples are scheduled from the same deck plan, so they cannot drift onto
different swing grids. The scheduler never sleeps inside the transport callback,
preserves insertion order for simultaneous events, catches callback errors and
is cleared whenever playback stops.
