package.path = "./?.lua;./lib/?.lua;" .. package.path

local registry = require("engine_registry")
local profiles = require("genre_profiles")

-- All registered model names must produce valid SC integers.
for _, name in ipairs({"808","909","linn","industrial","hybrid"}) do
  assert(registry.KIT[name] ~= nil, "kit not in registry: " .. name)
end
for _, name in ipairs({"analog","fm","organ","pad","rave"}) do
  assert(registry.CHORD[name] ~= nil, "chord not in registry: " .. name)
end
for _, name in ipairs({"analog","sub","reese","organ","fm","wobble"}) do
  assert(registry.MONO[name] ~= nil, "mono not in registry: " .. name)
end

-- Integers must form a zero-based contiguous range (no gaps, no duplicates).
local function check_range(tbl, label, expected_count)
  local seen = {}
  for _, id in pairs(tbl) do
    assert(id >= 0, label .. " id must be >= 0: " .. id)
    assert(not seen[id], label .. " duplicate id " .. id)
    seen[id] = true
  end
  for i = 0, expected_count - 1 do
    assert(seen[i], label .. " gap at integer " .. i)
  end
end
check_range(registry.KIT,   "kit",   5)
check_range(registry.CHORD, "chord", 5)
check_range(registry.MONO,  "mono",  6)

-- Display name arrays must match model count.
assert(#registry.KIT_NAMES   == 5, "KIT_NAMES length must be 5")
assert(#registry.CHORD_NAMES == 5, "CHORD_NAMES length must be 5")
assert(#registry.MONO_NAMES  == 6, "MONO_NAMES length must be 6")

-- Gain coefficients must exist for every registered model name.
for name in pairs(registry.CHORD) do
  assert(registry.CHORD_GAIN[name],
    "missing CHORD_GAIN entry for " .. name)
end
for name in pairs(registry.MONO) do
  assert(registry.MONO_GAIN[name],
    "missing MONO_GAIN entry for " .. name)
end
for name in pairs(registry.KIT) do
  assert(registry.KIT_GAIN[name],
    "missing KIT_GAIN entry for " .. name)
end

-- Gain values must match Engine_Endless.sc modelGain arrays exactly.
-- Chord: #[0.92, 0.78, 0.48, 0.86, 0.70] (analog, fm, organ, pad, rave)
assert(registry.CHORD_GAIN.analog == 0.92, "chord analog gain must be 0.92")
assert(registry.CHORD_GAIN.fm     == 0.78, "chord fm gain must be 0.78")
assert(registry.CHORD_GAIN.organ  == 0.48, "chord organ gain must be 0.48")
assert(registry.CHORD_GAIN.pad    == 0.86, "chord pad gain must be 0.86")
assert(registry.CHORD_GAIN.rave   == 0.70, "chord rave gain must be 0.70")
-- Mono/bass: 1.15, 1.20, 1.10, 0.58, 1.10, 0.95 (analog, sub, reese, organ, fm, wobble)
assert(registry.MONO_GAIN.analog  == 1.15, "mono analog gain must be 1.15")
assert(registry.MONO_GAIN.sub     == 1.20, "mono sub gain must be 1.20")
assert(registry.MONO_GAIN.reese   == 1.10, "mono reese gain must be 1.10")
assert(registry.MONO_GAIN.organ   == 0.58, "mono organ gain must be 0.58")
assert(registry.MONO_GAIN.fm      == 1.10, "mono fm gain must be 1.10")
assert(registry.MONO_GAIN.wobble  == 0.95, "mono wobble gain must be 0.95")

-- validate_* helpers must return false+reason for unknown names.
local ok, reason = registry.validate_kit("unknown_kit")
assert(not ok and reason, "validate_kit must reject unknown names")
ok, reason = registry.validate_chord("unknown_chord")
assert(not ok and reason, "validate_chord must reject unknown names")
ok, reason = registry.validate_mono("unknown_mono")
assert(not ok and reason, "validate_mono must reject unknown names")
-- And pass for all known names.
for name in pairs(registry.KIT)   do assert(registry.validate_kit(name))   end
for name in pairs(registry.CHORD) do assert(registry.validate_chord(name)) end
for name in pairs(registry.MONO)  do assert(registry.validate_mono(name))  end

-- Every profile in genre_profiles must use only registered model names,
-- ensuring unsupported genre/engine combinations fail at validation time.
for _, row in ipairs(profiles.each()) do
  local g, a = row.genre, row.archetype
  for _, kit in ipairs(row.profile.kits) do
    local v, r = registry.validate_kit(kit)
    assert(v, g .. "/" .. a .. ": " .. tostring(r))
  end
  for _, chord in ipairs(row.profile.chords) do
    local v, r = registry.validate_chord(chord)
    assert(v, g .. "/" .. a .. ": " .. tostring(r))
  end
  for _, mono in ipairs(row.profile.mono) do
    local v, r = registry.validate_mono(mono)
    assert(v, g .. "/" .. a .. ": " .. tostring(r))
  end
end

print("All engine registry checks passed")
