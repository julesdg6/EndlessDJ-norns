-- Deterministic genre-aware bass plans. Bass phrases are generated once per
-- record, then replayed without per-note randomness so their identity survives
-- arrangement changes and DJ transitions.
local M = {}

local VOICES = {
  HOUSE={"organ","analog","sub"}, FUNKY={"organ","analog","fm"},
  DIRTY={"reese","fm","wobble"}, TECHNO={"analog","sub","reese"},
  GARAGE4={"organ","sub","reese"}, TWO_STEP={"sub","reese","organ","fm"},
  BREAKS={"reese","analog","fm"}, DUBSTEP={"sub","reese","wobble"},
  DEEP={"sub","organ","analog"}, ACID={"303"},
  TRANCE={"analog","reese","303"}, PROG={"analog","sub","reese"},
  JUNGLE={"sub","reese"}, DNB={"reese","sub","fm"},
  LIQUID={"sub","reese","organ"}, HARDTECHNO={"reese","analog","303"},
  ELECTRO={"fm","analog","reese"}, JUKE={"sub","fm"},
  AFRO={"sub","organ","analog"}, MINIMAL={"sub","analog"},
  MELODIC={"analog","sub","reese"}, SPEED={"reese","organ","sub"},
  BASSLINE={"organ","reese","wobble","fm"}, HARDSTYLE={"analog","reese"},
}

local MODEL = {analog=0,sub=1,reese=2,organ=3,fm=4,wobble=5}
local VOICE_PROFILES = {
  analog={sub=0.28,cutoff=0.62,resonance=0.24,attack=0.03,release=0.34,
    glide=0.12,lfo_rate=0.16,lfo_depth=0.09,delay_send=0.08},
  sub={sub=0.08,cutoff=0.38,resonance=0.12,attack=0.04,release=0.48,
    glide=0.08,lfo_rate=0.08,lfo_depth=0.03,delay_send=0.01},
  reese={sub=0.12,cutoff=0.46,resonance=0.34,attack=0.02,release=0.48,
    glide=0.18,lfo_rate=0.12,lfo_depth=0.22,delay_send=0.04},
  organ={sub=0.02,cutoff=0.88,resonance=0.08,attack=0.01,release=0.22,
    glide=0.01,lfo_rate=0.06,lfo_depth=0.01,delay_send=0.02},
  fm={sub=0.04,cutoff=0.74,resonance=0.18,attack=0.01,release=0.30,
    glide=0.04,lfo_rate=0.20,lfo_depth=0.58,delay_send=0.04},
  wobble={sub=0.32,cutoff=0.36,resonance=0.58,attack=0.02,release=0.52,
    glide=0.10,lfo_rate=0.42,lfo_depth=0.82,delay_send=0.05},
}
local LOW = {DUBSTEP=-12,JUNGLE=-12,DNB=-12,LIQUID=-12,JUKE=-12,HARDSTYLE=-12}
local DENSE = {TWO_STEP=true,BREAKS=true,JUNGLE=true,DNB=true,JUKE=true,SPEED=true,BASSLINE=true}
local LONG = {DUBSTEP=true,DEEP=true,LIQUID=true,MINIMAL=true,MELODIC=true,PROG=true}

local function low_end_mode(identity, voice_family)
  if identity.genre == "HARDSTYLE" then
    if identity.archetype == "rawstyle" then return "pitched_kick" end
    return "reverse_bass"
  end
  if identity.genre == "HARDTECHNO" and identity.archetype == "industrial_rumble" then
    return "rumble"
  end
  if voice_family == "sub" then return "sub_bass" end
  return "bass"
end

local function rng_new(seed)
  local rng = {state=math.max(1, seed % 2147483647)}
  function rng:next() self.state=(self.state*48271)%2147483647 return self.state end
  function rng:float() return (self:next()-1)/2147483646 end
  function rng:int(first,last) return first+math.floor(self:float()*(last-first+1)) end
  function rng:chance(probability) return self:float()<probability end
  function rng:pick(values) return values[self:int(1,#values)] end
  return rng
end

local function contains(values, wanted)
  for _, value in ipairs(values or {}) do if value == wanted then return true end end
  return false
end

local function kick_at(groove, bar, step)
  if not groove or not groove.bars then return false end
  local groove_bar = ((bar - 1) % (groove.phrase_bars or 4)) + 1
  local data = groove.bars[groove_bar]
  return data and data.kick and data.kick[step] ~= nil
end

local function add_event(events, step, degree, length, velocity, accent, slide)
  events[step] = {
    degree=degree, length=length, velocity=velocity,
    accent=accent or false, slide=slide or false,
  }
end

local function candidate_steps(genre, family)
  if family == "303" then return {1,3,4,7,9,11,12,15,16} end
  if genre == "DUBSTEP" then return {1,7,11,15} end
  if genre == "TWO_STEP" then return {1,3,6,8,11,14,16} end
  if DENSE[genre] then return {1,3,4,7,9,11,12,15,16} end
  return {1,4,7,9,11,13,15}
end

local function make_bar(genre, family, bar, rng, groove)
  local events = {}
  local steps = candidate_steps(genre, family)
  local target = DENSE[genre] and rng:int(4,6) or rng:int(3,5)
  if family == "303" then target = rng:int(5,7) end
  local degree_pool = {0,0,0,3,5,7,10,12}
  local selected = {}

  for _, step in ipairs(steps) do
    local avoid_kick = kick_at(groove, bar, step) and step ~= 1
    local keep = not avoid_kick or rng:chance(0.18)
    if keep and #selected < target and rng:chance(0.72) then selected[#selected + 1] = step end
  end
  if #selected == 0 then selected[1] = 1 end
  if bar == 4 and not contains(selected, 16) then selected[#selected + 1] = 16 end
  table.sort(selected)

  for index, step in ipairs(selected) do
    local degree = rng:pick(degree_pool)
    if index == 1 then degree = 0 end
    if bar == 4 and step == 16 then degree = rng:pick({-2,3,7,12}) end
    local length = LONG[genre] and rng:int(2,4) or rng:int(1,2)
    local accent = family == "303" and (step == 1 or rng:chance(0.32))
    local slide = family == "303" and index > 1 and rng:chance(0.28)
    add_event(events, step, degree, length, rng:int(82,108), accent, slide)
  end
  return events
end

local function secondary_bar(primary,genre,family,bar,rng,groove)
  local events=make_bar(genre,family,bar,rng,groove)
  local primary_bar=primary.bars[((bar-1)%primary.phrase_bars)+1] or {}
  for step in pairs(primary_bar) do events[step]=nil end
  if next(events)==nil then
    for _,step in ipairs({3,7,11,15}) do
      if not primary_bar[step] and not kick_at(groove,bar,step) then
        add_event(events,step,rng:pick({0,3,5,7,10}),1,rng:int(62,82),false,false)
        break
      end
    end
  end
  for _,event in pairs(events) do
    event.velocity=math.min(88,math.max(58,event.velocity-22))
    event.length=math.min(2,event.length)
  end
  return events
end

function M.new(identity, groove)
  assert(identity and identity.genre, "song identity required")
  local rng = rng_new(assert(identity.stream_seeds and identity.stream_seeds.bass,
    "bass seed required"))
  local palette = VOICES[identity.genre] or VOICES.HOUSE
  local voice_family = identity.bass_family or rng:pick(palette)
  assert(MODEL[voice_family] or voice_family == "303", "identity selected unknown bass")
  local mode = low_end_mode(identity, voice_family)
  local bars = {}
  for bar = 1, 4 do bars[bar] = make_bar(identity.genre, voice_family, bar, rng, groove) end
  if mode == "reverse_bass" then
    bars = {}
    for bar = 1, 4 do
      bars[bar] = {}
      for _, step in ipairs({3,7,11,15}) do
        add_event(bars[bar], step, (bar == 4 and step == 15) and 12 or 0,
          2, rng:int(92,110), step == 15, false)
      end
    end
  elseif mode == "pitched_kick" then
    bars = {{},{},{},{}}
  end
  local modulation = {
    base=0.78 + rng:float() * 0.12,
    drop=1.05 + rng:float() * 0.12,
    second_drop=1.18 + rng:float() * 0.18,
    transpose=rng:pick({0,0,0,5,7,12}),
  }
  return {
    schema_version=1, genre=identity.genre, archetype=identity.archetype,
    voice_family=voice_family, model=MODEL[voice_family], phrase_bars=4,
    octave=LOW[identity.genre] or 0, bars=bars, low_end_mode=mode,
    low_end_owner=(mode == "pitched_kick") and "kick" or "bass",
    kick_relationship=(mode == "reverse_bass" and "offbeat") or
      (mode == "rumble" and "tail") or (mode == "pitched_kick" and "owned") or "gapped",
    modulation=modulation,
  }
end

function M.new_secondary(identity,groove,primary)
  local family=identity and identity.secondary_bass_family
  if not family then return nil end
  assert(MODEL[family] and family~="sub","secondary bass must be a non-sub model")
  local seed=assert(identity.stream_seeds and identity.stream_seeds.bass,"bass seed required")
  local rng=rng_new(seed+104729)
  local bars={}
  for bar=1,4 do bars[bar]=secondary_bar(primary,identity.genre,family,bar,rng,groove) end
  return {
    schema_version=1,genre=identity.genre,archetype=identity.archetype,
    voice_family=family,model=MODEL[family],phrase_bars=4,
    octave=(primary.octave or 0)+12,bars=bars,low_end_mode="secondary",
    low_end_owner="primary_bass",kick_relationship="counter",
    modulation={base=0.62,drop=0.78,second_drop=0.88,transpose=rng:pick({0,5,7,12})},
  }
end

function M.event(plan, absolute_bar, step, section)
  if not plan or not plan.bars then return nil end
  local bar = ((absolute_bar - 1) % plan.phrase_bars) + 1
  local source = plan.bars[bar] and plan.bars[bar][step] or nil
  if not source then return nil end
  local event = {}
  for name, value in pairs(source) do event[name] = value end
  local second_drop = section == "DROP" and math.floor((absolute_bar - 1) / 8) % 2 == 1
  if second_drop then
    event.degree = event.degree + (plan.modulation and plan.modulation.transpose or 0)
    event.velocity = math.min(127, event.velocity + 8)
    event.modulation = plan.modulation and plan.modulation.second_drop or 1
  elseif section == "DROP" then
    event.modulation = plan.modulation and plan.modulation.drop or 1
  else
    event.modulation = plan.modulation and plan.modulation.base or 1
  end
  return event
end

function M.validate(plan)
  if type(plan) ~= "table" or plan.schema_version ~= 1 then
    return false, "unsupported bass schema"
  end
  if not MODEL[plan.voice_family] and plan.voice_family ~= "303" then
    return false, "unknown voice family"
  end
  if plan.genre == "TWO_STEP" and plan.voice_family == "303" then
    return false, "2-Step must not default to 303"
  end
  if type(plan.bars) ~= "table" or #plan.bars ~= plan.phrase_bars then
    return false, "invalid phrase length"
  end
  if not contains({"bass","sub_bass","rumble","reverse_bass","pitched_kick","secondary"},
      plan.low_end_mode) then
    return false, "invalid low-end mode"
  end
  local expected_owner=(plan.low_end_mode=="pitched_kick" and "kick") or
    (plan.low_end_mode=="secondary" and "primary_bass") or "bass"
  if plan.low_end_owner ~= expected_owner then return false, "invalid low-end ownership" end
  if type(plan.modulation) ~= "table" or not plan.modulation.second_drop then
    return false, "missing phrase modulation"
  end
  return true
end

function M.model_for_voice(voice_family)
  return MODEL[voice_family]
end

function M.apply_voice_profile(plan, patch)
  local result = {}
  for name, value in pairs(patch or {}) do result[name] = value end
  local profile = VOICE_PROFILES[plan and plan.voice_family]
  if not profile then return result end
  result.model = MODEL[plan.voice_family]
  for name, target in pairs(profile) do
    local original = result[name] or target
    result[name] = (target * 0.85) + (original * 0.15)
  end
  if plan.low_end_mode=="secondary" then
    result.sub=0
    result.cutoff=math.max(0.48,result.cutoff or 0.48)
    result.delay_send=math.min(0.08,result.delay_send or 0)
  end
  if plan.modulation then
    result.lfo_depth = math.min(1, result.lfo_depth * plan.modulation.base)
    result.resonance = math.min(1, result.resonance * (0.92 + plan.modulation.base * 0.08))
  end
  return result
end

function M.voices_for_genre(genre)
  local result = {}
  for index, voice in ipairs(VOICES[genre] or {}) do result[index] = voice end
  return result
end

return M
