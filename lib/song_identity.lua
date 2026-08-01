-- Deterministic, deck-independent song identity foundation.
-- Musical generators consume named child streams so adding a new choice to one
-- subsystem cannot perturb unrelated parts of the record.

local M = {}

local MODULUS = 2147483647
local MULTIPLIER = 48271

local function hash_text(text, seed)
  local value = math.max(1, math.floor(seed or 1) % MODULUS)
  for index = 1, #text do
    value = (value * 131 + text:byte(index) + index) % MODULUS
  end
  return math.max(1, value)
end

local Rng = {}
Rng.__index = Rng

function Rng:new(seed)
  return setmetatable({state=math.max(1, math.floor(seed or 1) % MODULUS)}, self)
end

function Rng:next()
  self.state = (self.state * MULTIPLIER) % MODULUS
  return self.state
end

function Rng:float()
  return (self:next() - 1) / (MODULUS - 1)
end

function Rng:int(first, last)
  if last == nil then last, first = first, 1 end
  return first + math.floor(self:float() * (last - first + 1))
end

function Rng:chance(probability)
  return self:float() < probability
end

function Rng:pick(values)
  assert(type(values) == "table" and #values > 0, "cannot pick from an empty list")
  return values[self:int(1, #values)]
end

function Rng:fork(label)
  return Rng:new(hash_text(tostring(label), self.state))
end

M.Rng = Rng

local archetypes = {
  HOUSE={"classic_organ", "disco_sample", "deep_rolling", "vocal_stab"},
  FUNKY={"filtered_disco", "live_clavinet", "brass_vocal", "french_touch"},
  DIRTY={"electro_riff", "fidget_bass", "rave_stab", "minimal_growl"},
  TECHNO={"hypnotic", "dub_tool", "warehouse", "industrial"},
  GARAGE4={"organ_4x4", "soulful_vocal", "dark_sub", "ravey_speed"},
  TWO_STEP={"deep_sub", "reese_shuffle", "organ_skip", "fm_future"},
  BREAKS={"funky_break", "progressive_break", "electro_break", "big_beat"},
  DUBSTEP={"deep_140", "wobble", "halfstep_reese", "dubwise"},
  DEEP={"warm_organ", "dub_chord", "soulful_pad", "minimal_deep"},
  ACID={"classic_303", "jack_acid", "deep_acid", "rave_acid"},
  TRANCE={"uplifting", "progressive_trance", "acid_trance", "classic_euphoric"},
  PROG={"progressive_house", "tribal_progressive", "melodic_drive", "deep_progressive"},
  JUNGLE={"amen_pressure", "ragga_jungle", "darkside", "jazz_jungle"},
  DNB={"techstep", "dancefloor", "rollers", "neuro"},
  LIQUID={"soulful_liquid", "jazz_liquid", "vocal_liquid", "deep_roller"},
  HARDTECHNO={"warehouse_hard", "schranz", "industrial_rumble", "acid_hard"},
  ELECTRO={"robot_funk", "detroit_electro", "breakdance", "dark_electro"},
  JUKE={"classic_juke", "footwork", "soul_chop", "experimental_160"},
  AFRO={"organic_percussion", "deep_afro", "vocal_afro", "melodic_afro"},
  MINIMAL={"microhouse", "minimal_tech", "dub_minimal", "clicky_tool"},
  MELODIC={"melodic_techno", "deep_melodic", "arpeggiated", "cinematic"},
  SPEED={"speed_garage", "bassline_speed", "rave_speed", "dark_speed"},
  BASSLINE={"organ_bassline", "donk_bassline", "reese_bassline", "wobble_bassline"},
  HARDSTYLE={"reverse_bass", "euphoric", "rawstyle", "classic_hardstyle"},
}

local kit_families = {
  HOUSE={"909","808","hybrid"}, FUNKY={"linn","909","hybrid"},
  DIRTY={"909","industrial","hybrid"}, TECHNO={"909","industrial"},
  GARAGE4={"909","linn","hybrid"}, TWO_STEP={"linn","909","hybrid"},
  BREAKS={"linn","909","hybrid"}, DUBSTEP={"808","linn","industrial"},
  DEEP={"808","909"}, ACID={"808","909"}, TRANCE={"909","hybrid"},
  PROG={"909","hybrid"}, JUNGLE={"linn","909","hybrid"},
  DNB={"linn","909","industrial"}, LIQUID={"linn","909"},
  HARDTECHNO={"industrial","909"}, ELECTRO={"808","linn"},
  JUKE={"808","linn"}, AFRO={"808","linn","hybrid"},
  MINIMAL={"808","909"}, MELODIC={"909","hybrid"},
  SPEED={"909","linn","industrial"}, BASSLINE={"909","linn","hybrid"},
  HARDSTYLE={"industrial","909","hybrid"},
}
local groove_families = {"straight", "swung", "broken", "syncopated"}
local harmony_families = {"minor_modal", "seventh_ninth", "pedal_tone", "borrowed_motion"}
local arrangement_families = {
  HOUSE={"club_linear","hook_ab","slow_burn"},
  FUNKY={"hook_ab","club_linear","double_drop"}, DIRTY={"double_drop","club_linear"},
  TECHNO={"slow_burn","double_drop","club_linear"}, GARAGE4={"hook_ab","club_linear"},
  TWO_STEP={"hook_ab","double_drop"}, BREAKS={"double_drop","hook_ab"},
  DUBSTEP={"double_drop","slow_burn"}, DEEP={"slow_burn","club_linear"},
  ACID={"club_linear","double_drop"}, TRANCE={"double_drop","slow_burn"},
  PROG={"slow_burn","hook_ab"}, JUNGLE={"double_drop","hook_ab"},
  DNB={"double_drop","club_linear"}, LIQUID={"hook_ab","slow_burn"},
  HARDTECHNO={"double_drop","club_linear"}, ELECTRO={"hook_ab","double_drop"},
  JUKE={"hook_ab","double_drop"}, AFRO={"slow_burn","club_linear"},
  MINIMAL={"slow_burn","club_linear"}, MELODIC={"slow_burn","double_drop"},
  SPEED={"double_drop","hook_ab"}, BASSLINE={"double_drop","hook_ab"},
  HARDSTYLE={"double_drop","club_linear"},
}

function M.archetypes_for_genre(genre)
  return archetypes[genre]
end

function M.stream(identity, label)
  assert(identity and identity.stream_seeds, "song identity required")
  local seed = identity.stream_seeds[label]
  if not seed then
    seed = hash_text(label, identity.seed)
    identity.stream_seeds[label] = seed
  end
  return Rng:new(seed)
end

function M.new(options)
  assert(type(options) == "table", "identity options required")
  assert(type(options.genre) == "string", "identity genre required")
  local choices = archetypes[options.genre]
  assert(choices and #choices >= 4, "genre must register at least four archetypes")

  local seed = math.max(1, math.floor(options.seed or 1) % MODULUS)
  local deck_key = tostring(options.deck or "?")
  local selection = Rng:new(hash_text("identity:" .. deck_key, seed))
  local identity = {
    schema_version=1,
    seed=seed,
    deck=deck_key,
    genre=options.genre,
    archetype=selection:pick(choices),
    groove_family=selection:pick(groove_families),
    kit=selection:pick(kit_families[options.genre]),
    harmony_family=selection:pick(harmony_families),
    arrangement_family=selection:pick(arrangement_families[options.genre]),
    stream_seeds={},
    stems={
      kick={role="rhythm", low_end_owner=true},
      percussion={role="rhythm"},
      bass={role="low_end", low_end_owner=true},
      chords={role="harmony"},
      mono={role="lead"},
      samples={role="sample"},
      fx={role="transition"},
    },
  }
  for _, label in ipairs({
    "patches", "groove", "bass", "harmony", "motif", "samples",
    "fills", "arrangement"
  }) do
    identity.stream_seeds[label] = hash_text(label, seed)
  end
  return identity
end

function M.validate(identity)
  if type(identity) ~= "table" or identity.schema_version ~= 1 then
    return false, "unsupported identity schema"
  end
  local choices = archetypes[identity.genre]
  if not choices then return false, "unknown genre" end
  local known = false
  for _, name in ipairs(choices) do
    if name == identity.archetype then known = true break end
  end
  if not known then return false, "incompatible archetype" end
  if type(identity.seed) ~= "number" or type(identity.stream_seeds) ~= "table" then
    return false, "missing seed lineage"
  end
  return true
end

local function encode(value)
  if type(value) ~= "table" then return tostring(value) end
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, key in ipairs(keys) do
    parts[#parts + 1] = tostring(key) .. "=" .. encode(value[key])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function M.serialize(identity)
  local valid, reason = M.validate(identity)
  assert(valid, reason)
  return encode(identity)
end

return M
