-- Deterministic, deck-independent song identity foundation.
-- Musical generators consume named child streams so adding a new choice to one
-- subsystem cannot perturb unrelated parts of the record.

local M = {}

local profiles = rawget(_G, "genre_profiles")
if not profiles then
  local ok, result = pcall(require, "genre_profiles")
  profiles = ok and result or dofile("lib/genre_profiles.lua")
end

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
  local archetype = selection:pick(choices)
  local profile = assert(profiles.profile(options.genre, archetype), "missing genre profile")
  local identity = {
    schema_version=2,
    seed=seed,
    deck=deck_key,
    genre=options.genre,
    archetype=archetype,
    groove_family=selection:pick(profile.grooves),
    kit=selection:pick(profile.kits),
    bass_family=selection:pick(profile.bass),
    chord_model=selection:pick(profile.chords),
    chord_role=profile.chord_role,
    mono_model=selection:pick(profile.mono),
    harmony_family=selection:pick(profile.harmony),
    arrangement_family=selection:pick(profile.arrangements),
    sample_tags=profile.sample_tags,
    hook_role=profile.hook,
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
  if type(identity) ~= "table" or identity.schema_version ~= 2 then
    return false, "unsupported identity schema"
  end
  local choices = archetypes[identity.genre]
  if not choices then return false, "unknown genre" end
  local known = false
  for _, name in ipairs(choices) do
    if name == identity.archetype then known = true break end
  end
  if not known then return false, "incompatible archetype" end
  for dimension, key in pairs({kits="kit", grooves="groove_family", bass="bass_family",
      chords="chord_model", mono="mono_model", harmony="harmony_family",
      arrangements="arrangement_family"}) do
    if not profiles.supports(identity.genre, identity.archetype, dimension, identity[key]) then
      return false, "incompatible " .. key
    end
  end
  if identity.chord_role~="off" and identity.chord_role~="support" and identity.chord_role~="featured" then
    return false,"invalid chord role"
  end
  if type(identity.seed) ~= "number" or type(identity.stream_seeds) ~= "table" then
    return false, "missing seed lineage"
  end
  return true
end

function M.profile_for(identity)
  return identity and profiles.profile(identity.genre, identity.archetype) or nil
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
