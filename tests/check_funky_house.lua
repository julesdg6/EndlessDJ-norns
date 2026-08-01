-- Funky House genre regression suite.
-- Acceptance criteria: golden seeds for all four archetypes, structural
-- assertions (no 303, ghost snares, open hats, funk bass), archetype-specific
-- arrangement checks, and a 1 000-seed diversity / degenerate-pattern scan.
package.path = "./?.lua;./lib/?.lua;" .. package.path

local identity    = require("song_identity")
local groove_eng  = require("groove_engine")
local bass_eng    = require("bass_engine")
local arr_eng     = require("arrangement_engine")

local failures = {}
local function fail(msg)
  failures[#failures + 1] = msg
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function count_voice(bars, voice)
  local n = 0
  for _, bar in ipairs(bars or {}) do
    for _ in pairs(bar[voice] or {}) do n = n + 1 end
  end
  return n
end

local function count_ghost_snares(bars)
  local n = 0
  for _, bar in ipairs(bars or {}) do
    for _, ev in pairs(bar.snare or {}) do
      if ev.ghost then n = n + 1 end
    end
  end
  return n
end

local function count_bass_events(bars)
  local n = 0
  for _, bar in ipairs(bars or {}) do
    for _ in pairs(bar) do n = n + 1 end
  end
  return n
end

local function section_by_name(arrangement, name)
  for _, s in ipairs(arrangement.sections) do
    if s.name == name then return s end
  end
end

-- ---------------------------------------------------------------------------
-- Golden fixtures (seeds that deterministically select each archetype).
-- These mirror the generation_fixtures archetype_seeds = {6, 8, 1, 4}.
-- ---------------------------------------------------------------------------
local GOLDEN = {
  {archetype = "filtered_disco", seed = 6},
  {archetype = "live_clavinet",  seed = 8},
  {archetype = "brass_vocal",    seed = 1},
  {archetype = "french_touch",   seed = 4},
}

for _, g in ipairs(GOLDEN) do
  local song = identity.new{genre = "FUNKY", seed = g.seed, deck = "A"}

  -- Correct archetype selected
  if song.archetype ~= g.archetype then
    fail(string.format("FUNKY golden seed=%d: expected %s got %s",
      g.seed, g.archetype, tostring(song.archetype)))
  end

  -- Identity validates
  local ok, reason = identity.validate(song)
  if not ok then
    fail("FUNKY/" .. g.archetype .. " identity invalid: " .. tostring(reason))
  end

  -- No 303 bass
  if song.bass_family == "303" then
    fail("FUNKY/" .. g.archetype .. " must not select a 303 bass voice")
  end

  -- Replay is deterministic
  local replay = identity.new{genre = "FUNKY", seed = g.seed, deck = "A"}
  if identity.serialize(song) ~= identity.serialize(replay) then
    fail("FUNKY/" .. g.archetype .. " identity replay changed")
  end

  -- Deck A and B are independent
  local deck_b = identity.new{genre = "FUNKY", seed = g.seed, deck = "B"}
  if identity.serialize(song) == identity.serialize(deck_b) then
    fail("FUNKY/" .. g.archetype .. " deck A and B identities are identical")
  end

  -- Named streams are isolated
  local before = identity.stream(song, "bass"):next()
  identity.stream(song, "funky_test_stream"):next()
  local after = identity.stream(song, "bass"):next()
  if before ~= after then
    fail("FUNKY/" .. g.archetype .. " random stream isolation failed")
  end

  -- ---------------------------------------------------------------------------
  -- Groove assertions
  -- ---------------------------------------------------------------------------
  local groove = groove_eng.new(song)
  ok, reason = groove_eng.validate(groove)
  if not ok then
    fail("FUNKY/" .. g.archetype .. " groove invalid: " .. tostring(reason))
  end

  -- Must have drum events
  local drum_events = count_voice(groove.bars, "kick") +
    count_voice(groove.bars, "snare") + count_voice(groove.bars, "hats")
  if drum_events == 0 then
    fail("FUNKY/" .. g.archetype .. " has empty drum phrase")
  end

  -- Open hats are required for the disco / funk groove feel
  if count_voice(groove.bars, "ohats") == 0 then
    fail("FUNKY/" .. g.archetype .. " has no open hats (disco feel missing)")
  end

  -- Ghost snares are required for syncopation
  if count_ghost_snares(groove.bars) == 0 then
    fail("FUNKY/" .. g.archetype .. " has no ghost snares (syncopation missing)")
  end

  -- Phrase length must be 4 or 8 bars
  if groove.phrase_bars ~= 4 and groove.phrase_bars ~= 8 then
    fail("FUNKY/" .. g.archetype .. " unexpected phrase_bars=" .. tostring(groove.phrase_bars))
  end

  -- ---------------------------------------------------------------------------
  -- Bass assertions
  -- ---------------------------------------------------------------------------
  local bass = bass_eng.new(song, groove)
  ok, reason = bass_eng.validate(bass)
  if not ok then
    fail("FUNKY/" .. g.archetype .. " bass invalid: " .. tostring(reason))
  end

  -- Never a 303 voice
  if bass.voice_family == "303" then
    fail("FUNKY/" .. g.archetype .. " bass voice_family must not be 303")
  end

  -- Must have bass events (FUNKY is never a pitched-kick genre)
  if count_bass_events(bass.bars) == 0 then
    fail("FUNKY/" .. g.archetype .. " has empty bass phrase")
  end

  -- Bass density must stay within the shared safe limit
  if count_bass_events(bass.bars) > bass.phrase_bars * 12 then
    fail("FUNKY/" .. g.archetype .. " unsafe bass density")
  end

  -- ---------------------------------------------------------------------------
  -- Arrangement assertions
  -- ---------------------------------------------------------------------------
  local arrangement = arr_eng.new(song)
  ok, reason = arr_eng.validate(arrangement)
  if not ok then
    fail("FUNKY/" .. g.archetype .. " arrangement invalid: " .. tostring(reason))
  end

  -- MIX section must begin exactly at bar 97
  local mix_phrase = arr_eng.phrase(arrangement, 97)
  if not mix_phrase or mix_phrase.section ~= "MIX" or mix_phrase.bar ~= 1 then
    fail("FUNKY/" .. g.archetype .. " MIX section is not phrase aligned at bar 97")
  end

  -- INTRO must be sample-led: samples energy >= 0.50 and bass energy == 0
  local intro = section_by_name(arrangement, "INTRO")
  if not intro then
    fail("FUNKY/" .. g.archetype .. " has no INTRO section")
  elseif intro.energy.samples < 0.50 then
    fail(string.format("FUNKY/%s INTRO samples=%.2f must be >= 0.50 (sample-led intro)",
      g.archetype, intro.energy.samples))
  elseif intro.energy.bass ~= 0 then
    fail(string.format("FUNKY/%s INTRO bass=%.2f must be 0 (bass enters in GROOVE)",
      g.archetype, intro.energy.bass))
  end

  -- BREAK must expose vocal / sample material: samples energy >= 0.80
  local brk = section_by_name(arrangement, "BREAK")
  if not brk then
    fail("FUNKY/" .. g.archetype .. " has no BREAK section")
  elseif brk.energy.samples < 0.80 then
    fail(string.format("FUNKY/%s BREAK samples=%.2f must be >= 0.80 (expose vocal/guitar)",
      g.archetype, brk.energy.samples))
  end

  -- BUILD must use filter FX: fx energy >= 0.90
  local build = section_by_name(arrangement, "BUILD")
  if not build then
    fail("FUNKY/" .. g.archetype .. " has no BUILD section")
  elseif build.energy.fx < 0.90 then
    fail(string.format("FUNKY/%s BUILD fx=%.2f must be >= 0.90 (filter build)",
      g.archetype, build.energy.fx))
  end

  -- DROP must be a full-band drop: kick = 1, bass = 1, percussion = 1
  local drop = section_by_name(arrangement, "DROP")
  if not drop then
    fail("FUNKY/" .. g.archetype .. " has no DROP section")
  elseif drop.energy.kick ~= 1 or drop.energy.bass ~= 1 or drop.energy.percussion ~= 1 then
    fail(string.format("FUNKY/%s DROP must be full-band (kick/bass/perc=1), got %.2f/%.2f/%.2f",
      g.archetype, drop.energy.kick, drop.energy.bass, drop.energy.percussion))
  end
end

-- Archetype-specific structural checks
-- filtered_disco: INTRO >= 16 bars (extended sample-led intro)
do
  local song = identity.new{genre = "FUNKY", seed = 6, deck = "A"}
  local arr  = arr_eng.new(song)
  local intro = section_by_name(arr, "INTRO")
  if not intro or intro.length < 16 then
    fail("FUNKY/filtered_disco INTRO must be >= 16 bars for sample-led opening")
  end
end

-- live_clavinet: GROOVE >= 16 bars (groove reveal)
do
  local song = identity.new{genre = "FUNKY", seed = 8, deck = "A"}
  local arr  = arr_eng.new(song)
  local groove_sec = section_by_name(arr, "GROOVE")
  if not groove_sec or groove_sec.length < 16 then
    fail("FUNKY/live_clavinet GROOVE must be >= 16 bars for groove reveal")
  end
end

-- brass_vocal: BREAK >= 12 bars (extended vocal/brass breakdown)
do
  local song = identity.new{genre = "FUNKY", seed = 1, deck = "A"}
  local arr  = arr_eng.new(song)
  local brk  = section_by_name(arr, "BREAK")
  if not brk or brk.length < 12 then
    fail("FUNKY/brass_vocal BREAK must be >= 12 bars for vocal/brass exposure")
  end
end

-- french_touch: two DROP sections (double-drop structure)
do
  local song = identity.new{genre = "FUNKY", seed = 4, deck = "A"}
  local arr  = arr_eng.new(song)
  local drop_count = 0
  for _, s in ipairs(arr.sections) do
    if s.name == "DROP" then drop_count = drop_count + 1 end
  end
  if drop_count < 2 then
    fail("FUNKY/french_touch must have >= 2 DROP sections (double-drop)")
  end
end

-- ---------------------------------------------------------------------------
-- Statistical diversity over 1 000 seeds
-- ---------------------------------------------------------------------------
local archetype_count = {}
local fingerprints    = {}
local banned_303      = 0

for seed = 1, 1000 do
  local song   = identity.new{genre = "FUNKY", seed = seed, deck = "A"}
  local groove = groove_eng.new(song)
  local bass   = bass_eng.new(song, groove)
  local arr    = arr_eng.new(song)

  if bass.voice_family == "303" then
    banned_303 = banned_303 + 1
  end

  archetype_count[song.archetype] = (archetype_count[song.archetype] or 0) + 1

  -- Compute a simple fingerprint: archetype + groove + bass pattern + arrangement
  local bass_sig = {}
  for bi, bar in ipairs(bass.bars) do
    for step, ev in pairs(bar) do
      bass_sig[#bass_sig + 1] = bi .. ":" .. step .. ":" .. ev.degree
    end
  end
  table.sort(bass_sig)
  local fp = table.concat({
    song.archetype, song.kit, song.harmony_family,
    groove.family, groove.phrase_bars, bass.voice_family,
    table.concat(bass_sig, "/"), arr.family,
  }, "|")
  fingerprints[fp] = true
end

-- No 303 across all seeds
if banned_303 > 0 then
  fail(string.format("FUNKY must never use 303 bass; found %d seeds with 303", banned_303))
end

-- All four archetypes must appear
local n_archetypes = 0
for _ in pairs(archetype_count) do n_archetypes = n_archetypes + 1 end
if n_archetypes < 4 then
  fail(string.format("FUNKY archetype collapse: %d/4 archetypes seen over 1000 seeds",
    n_archetypes))
end

-- No archetype must dominate (each should appear at least 15% of the time)
for archetype, count in pairs(archetype_count) do
  if count < 150 then
    fail(string.format("FUNKY/%s appears only %d/1000 times (< 15%% threshold)",
      archetype, count))
  end
end

-- Minimum fingerprint diversity
local n_fps = 0
for _ in pairs(fingerprints) do n_fps = n_fps + 1 end
if n_fps < 350 then
  fail(string.format("FUNKY identity diversity too low: %d unique fingerprints over 1000 seeds",
    n_fps))
end

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
if #failures > 0 then
  for _, msg in ipairs(failures) do
    io.stderr:write("FUNKY FAIL: " .. msg .. "\n")
  end
  error(string.format("Funky House regression suite failed (%d failures)", #failures))
end

print(string.format(
  "All Funky House regression tests passed: 4 archetypes, %d fingerprints/1000 seeds",
  n_fps))
