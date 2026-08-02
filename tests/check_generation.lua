package.path = "./?.lua;./lib/?.lua;" .. package.path

local identity = require("song_identity")
local groove_engine = require("groove_engine")
local bass_engine = require("bass_engine")
local arrangement_engine = require("arrangement_engine")
local fixtures = require("generation_fixtures").build(identity)

local mode = arg[1] or "quick"
assert(mode == "quick" or mode == "full", "mode must be quick or full")
local seeds_per_genre = mode == "full" and 1000 or 64
local failures = {}

local function fail(genre, archetype, seed, message)
  failures[#failures + 1] = string.format("%s/%s seed=%d: %s",
    genre, archetype or "?", seed or -1, message)
end

local function count_events(bars, voices)
  local count = 0
  for _, bar in ipairs(bars or {}) do
    if voices then
      for _, voice in ipairs(voices) do
        for _ in pairs(bar[voice] or {}) do count = count + 1 end
      end
    else
      for _ in pairs(bar) do count = count + 1 end
    end
  end
  return count
end

local function fingerprint(song, groove, bass, arrangement)
  local bass_steps = {}
  for bar_index, bar in ipairs(bass.bars) do
    for step, event in pairs(bar) do
      bass_steps[#bass_steps + 1] = table.concat({bar_index, step, event.degree}, ":")
    end
  end
  table.sort(bass_steps)
  return table.concat({song.archetype, song.kit, song.harmony_family,
    groove.family, groove.phrase_bars, bass.voice_family,
    table.concat(bass_steps, "/"), arrangement.family}, "|")
end

-- Golden fixtures: every registered archetype is selected and reproducible.
for _, fixture in ipairs(fixtures.all(identity)) do
  local song = identity.new(fixture)
  if song.archetype ~= fixture.archetype then
    fail(fixture.genre, fixture.archetype, fixture.seed,
      "golden seed selected " .. tostring(song.archetype))
  end
  local replay = identity.new(fixture)
  if identity.serialize(song) ~= identity.serialize(replay) then
    fail(fixture.genre, fixture.archetype, fixture.seed, "identity replay changed")
  end
end

local report = {}
for _, genre in ipairs(fixtures.genres) do
  local archetypes, fingerprints, grooves, basses, arrangements = {}, {}, {}, {}, {}
  for seed = 1, seeds_per_genre do
    local song = identity.new{genre=genre, seed=seed, deck="A"}
    local groove = groove_engine.new(song)
    local bass = bass_engine.new(song, groove)
    local arrangement = arrangement_engine.new(song)
    local context = song.archetype

    local valid, reason = identity.validate(song)
    if not valid then fail(genre, context, seed, reason) end
    valid, reason = groove_engine.validate(groove)
    if not valid then fail(genre, context, seed, reason) end
    valid, reason = bass_engine.validate(bass)
    if not valid then fail(genre, context, seed, reason) end
    valid, reason = arrangement_engine.validate(arrangement)
    if not valid then fail(genre, context, seed, reason) end

    local drum_events = count_events(groove.bars,
      {"kick", "snare", "clap", "hats", "ohats", "tom"})
    local bass_events = count_events(bass.bars)
    if drum_events == 0 then fail(genre, context, seed, "empty drum phrase") end
    if bass.low_end_mode ~= "pitched_kick" and bass_events == 0 then
      fail(genre, context, seed, "empty bass phrase")
    end
    if drum_events > groove.phrase_bars * 54 then
      fail(genre, context, seed, "unsafe drum density " .. drum_events)
    end
    if bass_events > bass.phrase_bars * 12 then
      fail(genre, context, seed, "unsafe bass density " .. bass_events)
    end
    if bass.voice_family == "303" and
        not ({ACID=true, TRANCE=true, HARDTECHNO=true})[genre] and
        not (genre == "ELECTRO" and song.archetype == "acid_electro") then
      fail(genre, context, seed, "stylistically invalid 303")
    end
    if genre == "TWO_STEP" and bass.voice_family == "303" then
      fail(genre, context, seed, "2-Step selected 303")
    end

    local phrase = arrangement_engine.phrase(arrangement, 97)
    if not phrase or phrase.section ~= "MIX" or phrase.bar ~= 1 then
      fail(genre, context, seed, "mix section is not phrase aligned")
    end

    archetypes[song.archetype] = true
    grooves[groove.family] = true
    basses[bass.voice_family] = true
    arrangements[arrangement.family] = true
    fingerprints[fingerprint(song, groove, bass, arrangement)] = true
  end

  local function size(values) local n=0 for _ in pairs(values) do n=n+1 end return n end
  local archetype_count = size(archetypes)
  local fingerprint_count = size(fingerprints)
  if archetype_count < 4 then fail(genre, "all", 0, "archetype collapse: " .. archetype_count .. "/4") end
  local minimum_fingerprints = math.max(8, math.floor(seeds_per_genre * 0.35))
  if fingerprint_count < minimum_fingerprints then
    fail(genre, "all", 0, "identity diversity collapsed: " .. fingerprint_count)
  end
  report[#report + 1] = string.format(
    "%s seeds=%d archetypes=%d grooves=%d basses=%d arrangements=%d records=%d",
    genre, seeds_per_genre, archetype_count, size(grooves), size(basses),
    size(arrangements), fingerprint_count)
end

-- Deck independence and named-stream isolation are direct invariants.
for _, genre in ipairs(fixtures.genres) do
  local seed = 42042
  local deck_a = identity.new{genre=genre, seed=seed, deck="A"}
  local deck_b = identity.new{genre=genre, seed=seed, deck="B"}
  if identity.serialize(deck_a) == identity.serialize(deck_b) then
    fail(genre, "deck", seed, "Deck A and B identities are identical")
  end
  local before = identity.stream(deck_a, "bass"):next()
  identity.stream(deck_a, "unrelated_regression_stream"):next()
  local after = identity.stream(deck_a, "bass"):next()
  if before ~= after then fail(genre, deck_a.archetype, seed, "random stream isolation failed") end
end

for _, line in ipairs(report) do print("GENERATION " .. line) end
if #failures > 0 then
  for _, message in ipairs(failures) do io.stderr:write("GENERATION FAIL: " .. message .. "\n") end
  error(string.format("generation %s suite failed (%d failures)", mode, #failures))
end
print(string.format("Generation %s suite passed: %d genres, %d records",
  mode, #fixtures.genres, #fixtures.genres * seeds_per_genre))
