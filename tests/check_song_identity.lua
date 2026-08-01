package.path = "./?.lua;./lib/?.lua;" .. package.path

local identity = require("song_identity")
local profiles = require("genre_profiles")
local genres = {
  "HOUSE", "FUNKY", "DIRTY", "TECHNO", "GARAGE4", "TWO_STEP",
  "BREAKS", "DUBSTEP", "DEEP", "ACID", "TRANCE", "PROG", "JUNGLE",
  "DNB", "LIQUID", "HARDTECHNO", "ELECTRO", "JUKE", "AFRO",
  "MINIMAL", "MELODIC", "SPEED", "BASSLINE", "HARDSTYLE",
}

for _, genre in ipairs(genres) do
  assert(#identity.archetypes_for_genre(genre) >= 4, genre .. " needs four archetypes")
end

for _, genre in ipairs(genres) do
  for seed = 1, 96 do
    local song = identity.new{seed=seed, deck="A", genre=genre}
    assert(profiles.supports(genre,song.archetype,"kits",song.kit),
      genre .. " selected incompatible kit " .. tostring(song.kit))
  end
end

local first = identity.new{seed=42042, deck="A", genre="TWO_STEP"}
local replay = identity.new{seed=42042, deck="A", genre="TWO_STEP"}
assert(identity.serialize(first) == identity.serialize(replay), "same seed must replay")

local deck_b = identity.new{seed=42042, deck="B", genre="TWO_STEP"}
assert(identity.serialize(first) ~= identity.serialize(deck_b), "deck streams must be independent")

local patch_rng = identity.stream(first, "patches")
local patch_values = {patch_rng:float(), patch_rng:int(1, 16), patch_rng:chance(0.5)}
identity.stream(first, "unrelated"):next()
local patch_replay = identity.stream(first, "patches")
assert(patch_values[1] == patch_replay:float(), "named streams must be isolated")
assert(patch_values[2] == patch_replay:int(1, 16), "integer replay failed")
assert(patch_values[3] == patch_replay:chance(0.5), "chance replay failed")

local changed_dimensions = 0
local second = identity.new{seed=42043, deck="A", genre="TWO_STEP"}
for _, key in ipairs({"archetype", "groove_family", "kit", "bass_family", "chord_model",
    "secondary_bass_family", "mono_model", "harmony_family", "arrangement_family", "hook_role"}) do
  if first[key] ~= second[key] then changed_dimensions = changed_dimensions + 1 end
end
assert(changed_dimensions >= 2, "nearby seeds should change multiple identity dimensions")

local valid, reason = identity.validate(first)
assert(valid, reason)
for _,genre in ipairs({"TWO_STEP","DUBSTEP","DNB","BASSLINE"}) do
  for seed=1,256 do
    local song=identity.new{seed=seed,deck="A",genre=genre}
    if song.secondary_bass_family then
      assert(song.chord_role=="off","secondary bass must replace chords")
      assert(song.secondary_bass_family~="sub","secondary bass must not be a sub")
      assert(song.secondary_bass_family~=song.bass_family,"bass roles must use different voices")
    end
  end
end
print("All song identity checks passed")
