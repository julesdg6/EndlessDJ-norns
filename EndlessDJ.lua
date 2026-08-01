-- EndlessDJ.lua
-- Endless DJ v1.139
-- Turntable-style animated decks + Roland AIRA MX-1 integration
--
-- T-8 drum map used here:
--   kick  36
--   snare 38
--   clap  50
--   tom   47
--   chh   42
--   ohh   46
--
-- MIDI (all routed via Roland AIRA MX-1 as USB hub):
--   T-8 drums  ch9  on t8 midi device  (default device 1 via MX-1)
--   T-8 bass   ch8  on t8 midi device
--   J-6 chords ch6  on j6 midi device  (default device 1 via MX-1)
--   MX-1 Beat FX depth automated via CC during mix transitions


engine.name = "Endless"


output_router = include("EndlessDJ/lib/output_router")
internal_engine = include("EndlessDJ/lib/internal_engine")
local sample_library = include("EndlessDJ/lib/sample_library")
genre_profiles = include("EndlessDJ/lib/genre_profiles")
song_identity = include("EndlessDJ/lib/song_identity")
groove_engine = include("EndlessDJ/lib/groove_engine")
bass_engine = include("EndlessDJ/lib/bass_engine")
arrangement_engine = include("EndlessDJ/lib/arrangement_engine")
transition_engine = include("EndlessDJ/lib/transition_engine")
timing_scheduler = include("EndlessDJ/lib/timing_scheduler")
norns_harness = include("EndlessDJ/lib/norns_harness")
generation_fixtures = include("EndlessDJ/lib/generation_fixtures")


-- Virtual grid connection (monome or midigrid virtual device).
-- With the midigrid mod enabled (SYSTEM â MODS â MIDIGRID), two Launchpad
-- Mini MK3 controllers appear as one 16Ã8 virtual grid.  Physical-device
