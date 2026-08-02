-- UK Garage 4x4 genre regression suite.
-- Acceptance criteria: golden seeds for all four archetypes, structural
-- assertions (no 303, UKG shuffle hats, open hats, syncopated bass,
-- DJ-friendly intros/outros), archetype-specific arrangement checks,
-- and a 1 000-seed diversity / degenerate-pattern scan.
package.path = "./?.lua;./lib/?.lua;" .. package.path

local identity   = require("song_identity")
local groove_eng = require("groove_engine")
local bass_eng   = require("bass_engine")
local arr_eng    = require("arrangement_engine")

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
  {archetype = "organ_4x4",    seed = 6},
  {archetype = "soulful_vocal", seed = 8},
  {archetype = "dark_sub",      seed = 1},
  {archetype = "ravey_speed",   seed = 4},
}

for _, g in ipairs(GOLDEN) do
  local song = identity.new{genre = "GARAGE4", seed = g.seed, deck = "A"}

  -- Correct archetype selected
  if song.archetype ~= g.archetype then
    fail(string.format("GARAGE4 golden seed=%d: expected %s got %s",
      g.seed, g.archetype, tostring(song.archetype)))
  end

  -- Identity validates
  local ok, reason = identity.validate(song)
  if not ok then
    fail("GARAGE4/" .. g.archetype .. " identity invalid: " .. tostring(reason))
  end

  -- No 303 bass: UK Garage 4x4 uses organ/sub/reese/fm voices, not acid 303
  if song.bass_family == "303" then
    fail("GARAGE4/" .. g.archetype .. " must not select a 303 bass voice")
  end

  -- Replay is deterministic
  local replay = identity.new{genre = "GARAGE4", seed = g.seed, deck = "A"}
  if identity.serialize(song) ~= identity.serialize(replay) then
    fail("GARAGE4/" .. g.archetype .. " identity replay changed")
  end

  -- Deck A and B are independent
  local deck_b = identity.new{genre = "GARAGE4", seed = g.seed, deck = "B"}
  if identity.serialize(song) == identity.serialize(deck_b) then
    fail("GARAGE4/" .. g.archetype .. " deck A and B identities are identical")
  end

  -- Named streams are isolated
  local before = identity.stream(song, "bass"):next()
  identity.stream(song, "garage4_test_stream"):next()
  local after = identity.stream(song, "bass"):next()
  if before ~= after then
    fail("GARAGE4/" .. g.archetype .. " random stream isolation failed")
  end

  -- -------------------------------------------------------------------------
  -- Groove assertions
  -- -------------------------------------------------------------------------
  local groove = groove_eng.new(song)
  ok, reason = groove_eng.validate(groove)
  if not ok then
    fail("GARAGE4/" .. g.archetype .. " groove invalid: " .. tostring(reason))
  end

  -- Must have drum events
  local drum_events = count_voice(groove.bars, "kick") +
    count_voice(groove.bars, "snare") + count_voice(groove.bars, "hats")
  if drum_events == 0 then
    fail("GARAGE4/" .. g.archetype .. " has empty drum phrase")
  end

  -- UKG shuffle: open hats required to mark the syncopated offbeats
  if count_voice(groove.bars, "ohats") == 0 then
    fail("GARAGE4/" .. g.archetype .. " has no open hats (UKG shuffle missing)")
  end

  -- Ghost snares required for UKG syncopation between the backbeat
  if count_ghost_snares(groove.bars) == 0 then
    fail("GARAGE4/" .. g.archetype .. " has no ghost snares (UKG syncopation missing)")
  end

  -- Phrase length must be 4 or 8 bars (two-bar phrases within the four-floor frame)
  if groove.phrase_bars ~= 4 and groove.phrase_bars ~= 8 then
    fail("GARAGE4/" .. g.archetype .. " unexpected phrase_bars=" .. tostring(groove.phrase_bars))
  end

  -- -------------------------------------------------------------------------
  -- Bass assertions
  -- -------------------------------------------------------------------------
  local bass = bass_eng.new(song, groove)
  ok, reason = bass_eng.validate(bass)
  if not ok then
    fail("GARAGE4/" .. g.archetype .. " bass invalid: " .. tostring(reason))
  end

  -- Never a 303 voice (explicit eligibility contract)
  if bass.voice_family == "303" then
    fail("GARAGE4/" .. g.archetype .. " bass voice_family must not be 303")
  end

  -- Must have bass events
  if count_bass_events(bass.bars) == 0 then
    fail("GARAGE4/" .. g.archetype .. " has empty bass phrase")
  end

  -- Bass density must stay within safe limit
  if count_bass_events(bass.bars) > bass.phrase_bars * 12 then
    fail("GARAGE4/" .. g.archetype .. " unsafe bass density")
  end

  -- -------------------------------------------------------------------------
  -- Arrangement assertions
  -- -------------------------------------------------------------------------
  local arrangement = arr_eng.new(song)
  ok, reason = arr_eng.validate(arrangement)
  if not ok then
    fail("GARAGE4/" .. g.archetype .. " arrangement invalid: " .. tostring(reason))
  end

  -- MIX section must begin exactly at bar 97 (DJ-friendly handover)
  local mix_phrase = arr_eng.phrase(arrangement, 97)
  if not mix_phrase or mix_phrase.section ~= "MIX" or mix_phrase.bar ~= 1 then
    fail("GARAGE4/" .. g.archetype .. " MIX section is not phrase aligned at bar 97")
  end

  -- INTRO must be bass-free (DJ-friendly, bass enters in GROOVE)
  local intro = section_by_name(arrangement, "INTRO")
  if not intro then
    fail("GARAGE4/" .. g.archetype .. " has no INTRO section")
  elseif intro.energy.bass ~= 0 then
    fail(string.format("GARAGE4/%s INTRO bass=%.2f must be 0 (bass enters in GROOVE)",
      g.archetype, intro.energy.bass))
  end

  -- INTRO must carry percussion/samples for the DJ-friendly vocal open
  if intro.energy.samples < 0.40 then
    fail(string.format("GARAGE4/%s INTRO samples=%.2f must be >= 0.40 (vocal/sample open)",
      g.archetype, intro.energy.samples))
  end

  -- BREAK must expose vocal samples
  local brk = section_by_name(arrangement, "BREAK")
  if not brk then
    fail("GARAGE4/" .. g.archetype .. " has no BREAK section")
  elseif brk.energy.samples < 0.70 then
    fail(string.format("GARAGE4/%s BREAK samples=%.2f must be >= 0.70 (vocal exposure)",
      g.archetype, brk.energy.samples))
  end

  -- BUILD must use filter FX riser
  local build = section_by_name(arrangement, "BUILD")
  if not build then
    fail("GARAGE4/" .. g.archetype .. " has no BUILD section")
  elseif build.energy.fx < 0.88 then
    fail(string.format("GARAGE4/%s BUILD fx=%.2f must be >= 0.88 (filter/riser build)",
      g.archetype, build.energy.fx))
  end

  -- DROP must be a full-band drop
  local drop = section_by_name(arrangement, "DROP")
  if not drop then
    fail("GARAGE4/" .. g.archetype .. " has no DROP section")
  elseif drop.energy.kick ~= 1 or drop.energy.bass ~= 1 or drop.energy.percussion ~= 1 then
    fail(string.format("GARAGE4/%s DROP must be full-band (kick/bass/perc=1), got %.2f/%.2f/%.2f",
      g.archetype, drop.energy.kick, drop.energy.bass, drop.energy.percussion))
  end
end

-- ---------------------------------------------------------------------------
-- Archetype-specific structural checks
-- ---------------------------------------------------------------------------

-- organ_4x4: extended DROP (>= 16 bars) for maximum dancefloor impact
do
  local song = identity.new{genre = "GARAGE4", seed = 6, deck = "A"}
  local arr  = arr_eng.new(song)
  local drop = section_by_name(arr, "DROP")
  if not drop or drop.length < 16 then
    fail("GARAGE4/organ_4x4 DROP must be >= 16 bars for dancefloor impact")
  end
  -- No OUTRO: classic organ 4x4 ends hard on the drop
  local outro = section_by_name(arr, "OUTRO")
  if outro then
    fail("GARAGE4/organ_4x4 must not have an OUTRO (ends on DEVELOP)")
  end
end

-- soulful_vocal: OUTRO present for DJ-friendly mixing out
do
  local song  = identity.new{genre = "GARAGE4", seed = 8, deck = "A"}
  local arr   = arr_eng.new(song)
  local outro = section_by_name(arr, "OUTRO")
  if not outro then
    fail("GARAGE4/soulful_vocal must have an OUTRO section (DJ-friendly mixing out)")
  end
  -- Vocal samples elevated in BREAK for this archetype
  local brk = section_by_name(arr, "BREAK")
  if brk and brk.energy.samples < 0.88 then
    fail(string.format("GARAGE4/soulful_vocal BREAK samples=%.2f must be >= 0.88 (vocal spotlight)",
      brk.energy.samples))
  end
end

-- dark_sub: extended GROOVE (>= 20 bars) for slow bass reveal
do
  local song     = identity.new{genre = "GARAGE4", seed = 1, deck = "A"}
  local arr      = arr_eng.new(song)
  local groove_s = section_by_name(arr, "GROOVE")
  if not groove_s or groove_s.length < 20 then
    fail("GARAGE4/dark_sub GROOVE must be >= 20 bars for extended sub bass reveal")
  end
end

-- ravey_speed: two DROP sections (double-drop structure)
do
  local song      = identity.new{genre = "GARAGE4", seed = 4, deck = "A"}
  local arr       = arr_eng.new(song)
  local drop_count = 0
  for _, s in ipairs(arr.sections) do
    if s.name == "DROP" then drop_count = drop_count + 1 end
  end
  if drop_count < 2 then
    fail("GARAGE4/ravey_speed must have >= 2 DROP sections (double-drop structure)")
  end
end

-- ---------------------------------------------------------------------------
-- Four-floor kick check: organ_4x4 and soulful_vocal must preserve the pure
-- four-floor pattern (kick on steps 1, 5, 9, 13 in every bar).
-- ---------------------------------------------------------------------------
for _, archetype_seed in ipairs({{6, "organ_4x4"}, {8, "soulful_vocal"}}) do
  local seed, archetype = archetype_seed[1], archetype_seed[2]
  local song   = identity.new{genre = "GARAGE4", seed = seed, deck = "A"}
  local groove = groove_eng.new(song)
  for bar = 1, groove.phrase_bars do
    for _, step in ipairs({1, 5, 9, 13}) do
      if not groove_eng.event(groove, bar, "kick", step) then
        fail(string.format("GARAGE4/%s bar %d must have a four-floor kick at step %d",
          archetype, bar, step))
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Statistical diversity over 1 000 seeds
-- ---------------------------------------------------------------------------
local archetype_count = {}
local fingerprints    = {}
local banned_303      = 0

for seed = 1, 1000 do
  local song   = identity.new{genre = "GARAGE4", seed = seed, deck = "A"}
  local groove = groove_eng.new(song)
  local bass   = bass_eng.new(song, groove)
  local arr    = arr_eng.new(song)

  -- No 303 under any seed
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
  fail(string.format("GARAGE4 must never use 303 bass; found %d seeds with 303", banned_303))
end

-- All four archetypes must appear
local n_archetypes = 0
for _ in pairs(archetype_count) do n_archetypes = n_archetypes + 1 end
if n_archetypes < 4 then
  fail(string.format("GARAGE4 archetype collapse: %d/4 archetypes seen over 1000 seeds",
    n_archetypes))
end

-- No archetype must dominate (each should appear at least 15% of the time)
for archetype, count in pairs(archetype_count) do
  if count < 150 then
    fail(string.format("GARAGE4/%s appears only %d/1000 times (< 15%% threshold)",
      archetype, count))
  end
end

-- Minimum fingerprint diversity
local n_fps = 0
for _ in pairs(fingerprints) do n_fps = n_fps + 1 end
if n_fps < 350 then
  fail(string.format("GARAGE4 identity diversity too low: %d unique fingerprints over 1000 seeds",
    n_fps))
end

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
if #failures > 0 then
  for _, msg in ipairs(failures) do
    io.stderr:write("GARAGE4 FAIL: " .. msg .. "\n")
  end
  error(string.format("UK Garage 4x4 regression suite failed (%d failures)", #failures))
end

print(string.format(
  "All UK Garage 4x4 regression tests passed: 4 archetypes, %d fingerprints/1000 seeds",
  n_fps))
