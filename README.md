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
- Because all devices share the same USB MIDI interface, the default MIDI device for T-8, J-6, and MX-1 FX control is all device 1
- If the T-8/J-6 enumerate as separate USB MIDI devices through the hub, adjust the "t8 midi device" and "j6 midi device" params accordingly
- Beat FX depth is automated via MIDI CC during mix transitions (sinusoidal ramp: zero → peak at mid-mix → zero)
- Default Beat FX CC: 12 (Roland MX-1 Beat FX depth); default system channel: 1

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

The incoming deck currently begins 8 bars before handover.

During those 8 bars:

- outgoing track continues
- incoming track starts at bar 1
- crossfader moves gradually
- incoming musical elements should be introduced progressively

At handover the incoming track MUST NOT restart at bar 1.

If it has already played bars 1-8 during the mix, it should continue from bar 9.

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
The second launchpad is reserved for future functionality.

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

The launchpad MIDI device number is configurable via Norns params
(default device 3).  If the device is absent the script falls back to
fully generative drums.

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
