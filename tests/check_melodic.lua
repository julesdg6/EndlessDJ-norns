-- Melodic genre regression suite.
-- Acceptance criteria: golden seeds for all four archetypes, structural
-- assertions (no 303, melodic breakdown, open harmonic space, staged builds),
-- archetype-specific arrangement checks, and 1 000-seed diversity scan.
package.path = "./?.lua;./lib/?.lua;" .. package.path

local identity = require("song_identity")
local groove_eng = require("groove_engine")
local bass_eng = require("bass_engine")
local arr_eng = require("arrangement_engine")

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
  {archetype = "melodic_techno", seed = 6},
  {archetype = "melodic_house",  seed = 8},
  {archetype = "cinematic_prog", seed = 1},
  {archetype = "vocal_melodic",  seed = 4},
}

for _, g in ipairs(GOLDEN) do
  local song = identity.new{genre = "MELODIC", seed = g.seed, deck = "A"}

  -- Correct archetype selected
  if song.archetype ~= g.archetype then
    fail(string.format("MELODIC golden seed=%d: expected %s got %s",
      g.seed, g.archetype, tostring(song.archetype)))
  end

  -- Identity validates
  local ok, reason = identity.validate(song)
  if not ok then
    fail("MELODIC/" .. g.archetype .. " identity invalid: " .. tostring(reason))
  end

  -- No 303 bass
  if song.bass_family == "303" then
    fail("MELODIC/" .. g.archetype .. " must not select a 303 bass voice")
  end

  -- Replay is deterministic
  local replay = identity.new{genre = "MELODIC", seed = g.seed, deck = "A"}
  if identity.serialize(song) ~= identity.serialize(replay) then
    fail("MELODIC/" .. g.archetype .. " identity replay changed")
  end

  -- Deck A and B are independent
  local deck_b = identity.new{genre = "MELODIC", seed = g.seed, deck = "B"}
  if identity.serialize(song) == identity.serialize(deck_b) then
    fail("MELODIC/" .. g.archetype .. " deck A and B identities are identical")
  end

  -- Named streams are isolated
  local before = identity.stream(song, "bass"):next()
  identity.stream(song, "melodic_test_stream"):next()
  local after = identity.stream(song, "bass"):next()
  if before ~= after then
    fail("MELODIC/" .. g.archetype .. " random stream isolation failed")
  end

  -- ---------------------------------------------------------------------------
  -- Groove assertions
  -- ---------------------------------------------------------------------------
  local groove = groove_eng.new(song)
  ok, reason = groove_eng.validate(groove)
  if not ok then
    fail("MELODIC/" .. g.archetype .. " groove invalid: " .. tostring(reason))
  end

  -- Must have drum events
  local drum_events = count_voice(groove.bars, "kick") +
    count_voice(groove.bars, "snare") + count_voice(groove.bars, "hats")
  if drum_events == 0 then
    fail("MELODIC/" .. g.archetype .. " has empty drum phrase")
  end

  -- Open hats provide space between chord hits; all archetypes require them
  if count_voice(groove.bars, "ohats") == 0 then
    fail("MELODIC/" .. g.archetype .. " has no open hats (melodic space missing)")
  end

  -- Phrase length must be 8 or 16 bars (long phrases for harmonic arcs)
  if groove.phrase_bars ~= 8 and groove.phrase_bars ~= 16 then
    fail("MELODIC/" .. g.archetype .. " unexpected phrase_bars=" .. tostring(groove.phrase_bars))
  end

  -- ---------------------------------------------------------------------------
  -- Bass assertions
  -- ---------------------------------------------------------------------------
  local bass = bass_eng.new(song, groove)
  ok, reason = bass_eng.validate(bass)
  if not ok then
    fail("MELODIC/" .. g.archetype .. " bass invalid: " .. tostring(reason))
  end

  -- Never a 303 voice
  if bass.voice_family == "303" then
    fail("MELODIC/" .. g.archetype .. " bass voice_family must not be 303")
  end

  -- Must have bass events (MELODIC is never a pitched-kick genre)
  if count_bass_events(bass.bars) == 0 then
    fail("MELODIC/" .. g.archetype .. " has empty bass phrase")
  end

  -- Bass density must stay within safe limit
  if count_bass_events(bass.bars) > bass.phrase_bars * 12 then
    fail("MELODIC/" .. g.archetype .. " unsafe bass density")
  end

  -- ---------------------------------------------------------------------------
  -- Arrangement assertions
  -- ---------------------------------------------------------------------------
  local arrangement = arr_eng.new(song)
  ok, reason = arr_eng.validate(arrangement)
  if not ok then
    fail("MELODIC/" .. g.archetype .. " arrangement invalid: " .. tostring(reason))
  end

  -- MIX section must begin exactly at bar 97 (DJ-friendly handover)
  local mix_phrase = arr_eng.phrase(arrangement, 97)
  if not mix_phrase or mix_phrase.section ~= "MIX" or mix_phrase.bar ~= 1 then
    fail("MELODIC/" .. g.archetype .. " MIX section is not phrase aligned at bar 97")
  end

  -- INTRO must be bass-free (DJ-friendly start)
  local intro = section_by_name(arrangement, "INTRO")
  if not intro then
    fail("MELODIC/" .. g.archetype .. " has no INTRO section")
  elseif intro.energy.bass ~= 0 then
    fail(string.format("MELODIC/%s INTRO bass=%.2f must be 0 (DJ-friendly intro)",
      g.archetype, intro.energy.bass))
  end

  -- BREAK must strip the kick and spotlight the melodic lead
  local brk = section_by_name(arrangement, "BREAK")
  if not brk then
    fail("MELODIC/" .. g.archetype .. " has no BREAK section")
  elseif brk.energy.mono < 0.80 then
    fail(string.format("MELODIC/%s BREAK mono=%.2f must be >= 0.80 (melodic breakdown)",
      g.archetype, brk.energy.mono))
  elseif brk.energy.kick > 0.20 then
    fail(string.format("MELODIC/%s BREAK kick=%.2f must be <= 0.20 (stripped breakdown)",
      g.archetype, brk.energy.kick))
  end

  -- BUILD must peak the FX riser for the harmonic build
  local build = section_by_name(arrangement, "BUILD")
  if not build then
    fail("MELODIC/" .. g.archetype .. " has no BUILD section")
  elseif build.energy.fx < 0.90 then
    fail(string.format("MELODIC/%s BUILD fx=%.2f must be >= 0.90 (harmonic build)",
      g.archetype, build.energy.fx))
  end

  -- DROP must be a full-energy release
  local drop = section_by_name(arrangement, "DROP")
  if not drop then
    fail("MELODIC/" .. g.archetype .. " has no DROP section")
  elseif drop.energy.kick ~= 1 then
    fail(string.format("MELODIC/%s DROP kick=%.2f must be 1 (full-energy drop)",
      g.archetype, drop.energy.kick))
  end
end

-- ---------------------------------------------------------------------------
-- Archetype-specific structural checks
-- ---------------------------------------------------------------------------

-- melodic_techno: extended DROP (>= 16 bars) carries the full melodic arc
do
  local song = identity.new{genre = "MELODIC", seed = 6, deck = "A"}
  local arr  = arr_eng.new(song)
  local drop = section_by_name(arr, "DROP")
  if not drop or drop.length < 16 then
    fail("MELODIC/melodic_techno DROP must be >= 16 bars for extended melodic arc")
  end
end

-- melodic_house: OUTRO present for DJ-friendly mixing out
do
  local song = identity.new{genre = "MELODIC", seed = 8, deck = "A"}
  local arr  = arr_eng.new(song)
  local outro = section_by_name(arr, "OUTRO")
  if not outro then
    fail("MELODIC/melodic_house must have an OUTRO section (DJ-friendly mixing out)")
  end
end

-- cinematic_prog: long GROOVE (>= 20 bars) and emotional BREAK (>= 12 bars)
do
  local song = identity.new{genre = "MELODIC", seed = 1, deck = "A"}
  local arr  = arr_eng.new(song)
  local groove_sec = section_by_name(arr, "GROOVE")
  if not groove_sec or groove_sec.length < 20 then
    fail("MELODIC/cinematic_prog GROOVE must be >= 20 bars for cinematic atmosphere")
  end
  local brk = section_by_name(arr, "BREAK")
  if not brk or brk.length < 12 then
    fail("MELODIC/cinematic_prog BREAK must be >= 12 bars for emotional breakdown")
  end
end

-- vocal_melodic: OUTRO present and vocal samples elevated in BREAK
do
  local song = identity.new{genre = "MELODIC", seed = 4, deck = "A"}
  local arr  = arr_eng.new(song)
  local outro = section_by_name(arr, "OUTRO")
  if not outro then
    fail("MELODIC/vocal_melodic must have an OUTRO section (DJ-friendly)")
  end
  local brk = section_by_name(arr, "BREAK")
  if brk and brk.energy.samples < 0.55 then
    fail(string.format("MELODIC/vocal_melodic BREAK samples=%.2f must be >= 0.55 (vocal spotlight)",
      brk.energy.samples))
  end
end

-- ---------------------------------------------------------------------------
-- Statistical diversity over 1 000 seeds
-- ---------------------------------------------------------------------------
local archetype_count = {}
local fingerprints    = {}
local banned_303      = 0

for seed = 1, 1000 do
  local song   = identity.new{genre = "MELODIC", seed = seed, deck = "A"}
  local groove = groove_eng.new(song)
  local bass   = bass_eng.new(song, groove)
  local arr    = arr_eng.new(song)

  if bass.voice_family == "303" then
    banned_303 = banned_303 + 1
  end

  archetype_count[song.archetype] = (archetype_count[song.archetype] or 0) + 1

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
  fail(string.format("MELODIC must never use 303 bass; found %d seeds with 303", banned_303))
end

-- All four archetypes must appear
local n_archetypes = 0
for _ in pairs(archetype_count) do n_archetypes = n_archetypes + 1 end
if n_archetypes < 4 then
  fail(string.format("MELODIC archetype collapse: %d/4 archetypes seen over 1000 seeds",
    n_archetypes))
end

-- No archetype must dominate (each should appear at least 15% of the time)
for archetype, count in pairs(archetype_count) do
  if count < 150 then
    fail(string.format("MELODIC/%s appears only %d/1000 times (< 15%% threshold)",
      archetype, count))
  end
end

-- Minimum fingerprint diversity (bass pattern variation ensures this is achievable)
local n_fps = 0
for _ in pairs(fingerprints) do n_fps = n_fps + 1 end
if n_fps < 350 then
  fail(string.format("MELODIC identity diversity too low: %d unique fingerprints over 1000 seeds",
    n_fps))
end

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
if #failures > 0 then
  for _, msg in ipairs(failures) do
    io.stderr:write("MELODIC FAIL: " .. msg .. "\n")
  end
  error(string.format("Melodic genre regression suite failed (%d failures)", #failures))
end

print(string.format(
  "All Melodic genre regression tests passed: 4 archetypes, %d fingerprints/1000 seeds",
  n_fps))
