local identity_engine = dofile("lib/song_identity.lua")
local groove_engine = dofile("lib/groove_engine.lua")
local bass_engine = dofile("lib/bass_engine.lua")

local function fail(message)
  io.stderr:write("FAIL: " .. message .. "\n")
  os.exit(1)
end

local function encode(value)
  if type(value) ~= "table" then return tostring(value) end
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
  local result = {}
  for _, key in ipairs(keys) do result[#result + 1] = key .. "=" .. encode(value[key]) end
  return "{" .. table.concat(result, ",") .. "}"
end

local genres = {
  "HOUSE","FUNKY","DIRTY","TECHNO","GARAGE4","TWO_STEP",
  "BREAKS","DUBSTEP","DEEP","ACID","TRANCE","PROG","JUNGLE",
  "DNB","LIQUID","HARDTECHNO","ELECTRO","JUKE","AFRO","MINIMAL",
  "MELODIC","SPEED","BASSLINE","HARDSTYLE",
}

for _, genre in ipairs(genres) do
  local identity = identity_engine.new{seed=12048,deck="A",genre=genre}
  local groove = groove_engine.new(identity)
  local first = bass_engine.new(identity, groove)
  local second = bass_engine.new(identity, groove)
  local valid, reason = bass_engine.validate(first)
  if not valid then fail(genre .. " bass plan is invalid: " .. tostring(reason)) end
  if encode(first) ~= encode(second) then fail(genre .. " bass plan is not deterministic") end
  if first.phrase_bars ~= 4 or #first.bars ~= 4 then fail(genre .. " must use a four-bar phrase") end
  if not first.low_end_owner or not first.kick_relationship or not first.modulation then
    fail(genre .. " lacks explicit low-end ownership and modulation")
  end
end

local secondary_count=0
for _,genre in ipairs({
  "TECHNO","GARAGE4","TWO_STEP","BREAKS","DUBSTEP","JUNGLE",
  "DNB","HARDTECHNO","SPEED","BASSLINE","HARDSTYLE",
}) do
  for seed=1,256 do
    local song=identity_engine.new{seed=seed,deck="A",genre=genre}
    local groove=groove_engine.new(song)
    local primary=bass_engine.new(song,groove)
    local secondary=bass_engine.new_secondary(song,groove,primary)
    if secondary then
      secondary_count=secondary_count+1
      local replay=bass_engine.new_secondary(song,groove,primary)
      if encode(secondary)~=encode(replay) then fail("secondary bass is not deterministic") end
      local valid,reason=bass_engine.validate(secondary)
      if not valid then fail("invalid secondary bass: "..tostring(reason)) end
      if secondary.low_end_owner~="primary_bass" or secondary.low_end_mode~="secondary" then
        fail("secondary bass must not claim low-end ownership")
      end
      if secondary.octave<(primary.octave+12) then fail("secondary bass register is too low") end
      for bar=1,4 do
        for step in pairs(secondary.bars[bar]) do
          if primary.bars[bar][step] then fail("primary and secondary bass duplicate a step") end
        end
      end
    end
  end
end
if secondary_count==0 then fail("no bass-led archetype selected a secondary bass") end

local secondary_patch=bass_engine.apply_voice_profile(
  {voice_family="reese",low_end_mode="secondary"},
  {sub=0.8,cutoff=0.2,delay_send=0.5}
)
if secondary_patch.sub~=0 or secondary_patch.cutoff<0.48 or secondary_patch.delay_send>0.08 then
  fail("secondary bass patch is not safely separated from the sub role")
end

local reverse_identity = identity_engine.new{seed=37,deck="A",genre="HARDSTYLE"}
reverse_identity.archetype = "reverse_bass"
local reverse_plan = bass_engine.new(reverse_identity, groove_engine.new(reverse_identity))
if reverse_plan.low_end_mode ~= "reverse_bass" or reverse_plan.low_end_owner ~= "bass" or
    reverse_plan.kick_relationship ~= "offbeat" then
  fail("reverse bass must explicitly own offbeat low end")
end
local pitched_identity = identity_engine.new{seed=38,deck="B",genre="HARDSTYLE"}
pitched_identity.archetype = "rawstyle"
local pitched_plan = bass_engine.new(pitched_identity, groove_engine.new(pitched_identity))
if pitched_plan.low_end_mode ~= "pitched_kick" or pitched_plan.low_end_owner ~= "kick" or
    next(pitched_plan.bars[1]) ~= nil then
  fail("pitched-kick mode must suppress the separate bass phrase")
end

local normal_event = bass_engine.event(reverse_plan, 1, 3, "MAIN")
local developed_event = bass_engine.event(reverse_plan, 9, 3, "DROP")
if not normal_event or not developed_event or
    developed_event.modulation <= normal_event.modulation or developed_event.velocity <= normal_event.velocity then
  fail("second drop must deterministically develop the bass phrase")
end

local two_step_voices = {}
for seed = 1, 512 do
  local identity = identity_engine.new{seed=seed,deck="B",genre="TWO_STEP"}
  local plan = bass_engine.new(identity, groove_engine.new(identity))
  if plan.voice_family == "303" then fail("2-Step selected a forbidden default 303") end
  two_step_voices[plan.voice_family] = true
end
for _, voice in ipairs({"sub","reese","organ","fm"}) do
  if not two_step_voices[voice] then fail("2-Step never selected " .. voice) end
end

for seed = 1, 64 do
  local identity = identity_engine.new{seed=seed,deck="A",genre="ACID"}
  local plan = bass_engine.new(identity, groove_engine.new(identity))
  if plan.voice_family ~= "303" then fail("Acid House must select the expressive 303 voice") end
  local expressive = false
  for bar = 1, 4 do
    for _, event in pairs(plan.bars[bar]) do
      expressive = expressive or event.accent or event.slide
    end
  end
  if not expressive then fail("Acid phrase lacks accents and slides") end
end
local acid_signatures={}
for archetype,seed in pairs({classic_303=6,jack_acid=8,deep_acid=1,rave_acid=4}) do
  local identity = identity_engine.new{seed=seed,deck="A",genre="ACID"}
  local plan = bass_engine.new(identity, groove_engine.new(identity))
  assert(identity.acid_identity and identity.acid_identity.style,"Acid archetype must store 303 identity data")
  acid_signatures[archetype]=encode(plan)
end
assert(acid_signatures.classic_303~=acid_signatures.deep_acid,"Acid archetypes collapsed to one 303 phrase")
assert(acid_signatures.jack_acid~=acid_signatures.rave_acid,"Acid archetypes need distinct 303 grammar")

for seed = 1, 512 do
  local identity = identity_engine.new{seed=seed,deck="A",genre="HOUSE"}
  local plan = bass_engine.new(identity, groove_engine.new(identity))
  if plan.voice_family == "303" then fail("House must not default to 303 bass voice") end
end

local distinct = {}
for seed = 1, 96 do
  local identity = identity_engine.new{seed=seed,deck="A",genre="HOUSE"}
  local plan = bass_engine.new(identity, groove_engine.new(identity))
  distinct[encode(plan)] = true
end
local count = 0
for _ in pairs(distinct) do count = count + 1 end
if count < 40 then fail("different seeds do not create sufficiently distinct bass records") end

local neutral = {
  preset=2,model=0,waveform=0,sub=0.5,cutoff=0.5,resonance=0.5,
  attack=0.5,release=0.5,glide=0.5,lfo_rate=0.5,lfo_depth=0.5,
  delay_send=0.5,
}
local reese = bass_engine.apply_voice_profile({voice_family="reese"}, neutral)
local organ = bass_engine.apply_voice_profile({voice_family="organ"}, neutral)
local wobble = bass_engine.apply_voice_profile({voice_family="wobble"}, neutral)
if organ.cutoff < 0.75 or organ.sub > 0.12 or organ.lfo_depth > 0.10 then
  fail("organ profile must remain bright, harmonic and stable")
end
if wobble.resonance < 0.45 or wobble.lfo_depth < 0.70 or wobble.lfo_rate < 0.35 then
  fail("wobble profile must have deep animated filtering")
end
if reese.cutoff > 0.55 or reese.lfo_depth < 0.15 or reese.glide < 0.12 then
  fail("Reese profile must remain dark, wide and mobile")
end
if reese.model == organ.model or organ.model == wobble.model or reese.model == wobble.model then
  fail("Reese, organ and wobble must use different synthesis models")
end
if neutral.cutoff ~= 0.5 or neutral.lfo_depth ~= 0.5 then
  fail("voice profiling must not mutate the source patch")
end

io.stdout:write("PASS: deterministic genre-aware bass architecture\n")
