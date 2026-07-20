You are helping develop a Monome Norns script called Endless DJ.

PROJECT GOAL

Endless DJ is a generative electronic music DJ system for Norns.

The goal is NOT to make a simple 16-step random sequencer.

The script should continuously generate complete, DJ-structured electronic tracks and automatically mix them together using two virtual decks.

Think of it as an endless AI/procedural DJ using external Roland AIRA hardware.

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
5. Palette: for distinct instrument colours select:
     SYSTEM → MODS → MIDIGRID → palette → endless_dj
   Any other midigrid palette still works; brightness differences remain legible.

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

Required NTS-1 settings
1. On the NTS-1, hold SHIFT and press OSC to enter the MIDI settings screen.
2. Set the receive channel to match the "nts1 channel" param (default Ch 1).
3. Enable "MIDI RX SHORT MESSAGE" so the NTS-1 processes incoming Note On/Off.
   (This setting may be labelled "MIDI RX MSG" in some firmware revisions.)
   Without it the NTS-1 will ignore incoming MIDI notes.
4. The NTS-1 does not respond to MIDI Program Change; sound design is done
   directly on the device.

How it plays
- Silent during INTRO and BREAK sections; sparse (every second bar) during GROOVE
  and MAIN; full in BUILD and DROP.
- Motifs are generated from the active deck's root note, genre, and chord
  progression, so every note is key-safe.
- Each 8-bar phrase gets its own motif; the motif changes at phrase boundaries
  rather than every note, giving the melody a recognisable character.
- During a mix the NTS-1 follows the melody group (phase 4, bars 25-32 of the
  32-bar crossfade) and fades in/out with the chords.

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

Pad note numbers
The eight MPX8 pads trigger samples by MIDI note number.  The defaults are:

  Pad  Role                  Default note
  ───  ────────────────────  ────────────
  1    Percussion accent     36
  2    Alternate percussion  38
  3    Short fill            42
  4    Long fill             46
  5    Impact                48
  6    Riser                 50
  7    Vocal / FX stab       60
  8    Drop accent           62

To match Norns to your MPX8 kit:
1. In the MPX8 editor (or on-device), note which MIDI note each pad is assigned.
2. Set the corresponding "mpx8 padN …" params in the Norns params menu to match.
   Alternatively, reassign the pads on the MPX8 to match the Norns defaults above.

Required MPX8 settings
- Set the MPX8 MIDI receive channel to match the "mpx8 channel" param (default 10).
- Ensure pads are in "one-shot" / "momentary" trigger mode so a short note-on
  fires the complete sample.
- Load the desired samples onto each pad slot via the MPX8 SD card / editor.

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
2. Open the params menu and press "mpx8 test pads" to fire all 8 pads in
   sequence (4-tick gap between each).  You should hear each sample trigger.
3. Start playback; confirm samples fire at the appropriate section boundaries.

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
