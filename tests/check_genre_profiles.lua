package.path = "./?.lua;./lib/?.lua;" .. package.path

local profiles = require("genre_profiles")
local identity = require("song_identity")
local rows = profiles.each()
assert(#rows == 96, "expected 96 genre/archetype profiles, got " .. #rows)

local counts = {}
for _, row in ipairs(rows) do
  local valid, reason = profiles.validate(row.genre, row.archetype)
  assert(valid, row.genre .. "/" .. row.archetype .. ": " .. tostring(reason))
  counts[row.genre] = (counts[row.genre] or 0) + 1
  assert(row.profile.chord_role=="off" or row.profile.chord_role=="support" or row.profile.chord_role=="featured",
    row.genre .. "/" .. row.archetype .. ": invalid chord role")
  if row.profile.secondary_bass then
    assert(row.profile.chord_role=="off",row.genre.."/"..row.archetype..
      ": secondary bass must replace chords")
    for _,voice in ipairs(row.profile.secondary_bass) do
      assert(voice~="sub" and voice~="303",row.genre.."/"..row.archetype..
        ": secondary bass must not own the sub register")
    end
  end
end
for genre, count in pairs(counts) do assert(count == 4, genre .. " must have four profiles") end
assert(#profiles.archetypes("TWO_STEP") == 4)
for _, archetype in ipairs(profiles.archetypes("TWO_STEP")) do
  assert(not profiles.supports("TWO_STEP", archetype, "bass", "303"),
    "2-Step must not default to 303")
end
for _, archetype in ipairs(profiles.archetypes("ACID")) do
  assert(profiles.supports("ACID", archetype, "bass", "303"),
    "Acid archetypes must use expressive 303")
end
for _, archetype in ipairs(profiles.archetypes("ELECTRO")) do
  if archetype == "acid_electro" then
    assert(profiles.supports("ELECTRO", archetype, "bass", "303"),
      "Acid Electro must opt into 303")
    assert(profiles.supports("ELECTRO", archetype, "kits", "909"),
      "Acid Electro crossover must allow a four-floor compatible kit")
  else
    assert(not profiles.supports("ELECTRO", archetype, "bass", "303"),
      "Default Electro archetypes must not route through 303")
    assert(profiles.supports("ELECTRO", archetype, "kits", "808"),
      "Default Electro archetypes must be anchored by 808-style drums")
  end
end

for _, row in ipairs(rows) do
  local found = false
  for seed = 1, 20000 do
    local song = identity.new{genre=row.genre,seed=seed,deck="A"}
    if song.archetype == row.archetype then
      local valid, reason = identity.validate(song)
      assert(valid, reason)
      found = true
      break
    end
  end
  assert(found, "no deterministic seed found for " .. row.genre .. "/" .. row.archetype)
end

print("All 96 genre/archetype compatibility profiles passed")
