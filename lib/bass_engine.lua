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
  ELECTRO={"fm","analog","303"}, JUKE={"sub","fm"},
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
local ACID_SPECS = {
  classic_303={
    steps={{1,4,7,11,13},{1,3,7,9,12,15},{1,4,7,10,13,15},{1,3,7,11,14,16}},
    degrees={0,0,3,7,10,12},
    accents={1,7,13,15},
    slides={3,10,11,14},
    endings={7,12},
    octave_chance=0.14,
  },
  jack_acid={
    steps={{1,4,7,10,13,16},{1,3,6,9,12,15},{1,4,8,11,13,15},{1,3,7,10,12,16}},
    degrees={0,3,5,7,10,12},
    accents={1,4,10,13,16},
    slides={3,6,10,12,15},
    endings={10,12},
    octave_chance=0.18,
  },
  deep_acid={
    steps={{1,7,11,15},{1,8,11,14},{1,7,10,15},{1,8,12,16}},
    degrees={0,0,3,7,10},
    accents={1,11,15},
    slides={7,11},
    endings={3,7},
    octave_chance=0.06,
  },
  rave_acid={
    steps={{1,3,6,7,10,11,14,15},{1,4,7,9,12,13,15},{1,3,7,10,11,14,16},{1,4,7,10,12,15,16}},
    degrees={0,3,7,10,12,15},
    accents={1,3,7,11,15},
    slides={3,6,10,14,15},
    endings={12,15},
    octave_chance=0.24,
  },
}

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

local function acid_bar(archetype,bar,rng)
  local spec=ACID_SPECS[archetype] or ACID_SPECS.classic_303
  local events={}
  local steps=spec.steps[((bar-1)%#spec.steps)+1]
  for index,step in ipairs(steps) do
    local degree=spec.degrees[((index+bar-2)%#spec.degrees)+1]
    if index==1 then degree=0 end
    if bar==4 and step==steps[#steps] then degree=spec.endings[rng:int(1,#spec.endings)] end
    if step~=1 and rng:chance(spec.octave_chance or 0) then degree=degree+12 end
    local slide=contains(spec.slides,step) and index<#steps and rng:chance(0.72)
    local accent=(step==1 or contains(spec.accents,step)) and rng:chance(0.88)
    add_event(events,step,degree,slide and 2 or 1,rng:int(88,114),accent,slide)
  end
  return events
end

-- Funky House bass: each archetype has four per-bar step patterns and a
-- degree pool that encodes octave jumps (+12), chromatic approaches (-1, 1)
-- and chord tones (3, 5, 7, 10).  Bass notes avoid the kick wherever possible
-- so kick and bass share the low end without collision.
local FUNKY_SPECS = {
  filtered_disco = {
    -- Electric / slap bass: busy 8th-note feel, frequent octave jumps.
    steps = {
      {1,3,5,7,9,11,13,15},
      {1,3,5,9,11,13},
      {1,3,7,9,13,15},
      {1,5,9,11,13,15},
    },
    degrees  = {0,0,12,5,7,3,0,12},
    accents  = {1,9,13},
    endings  = {7,12},
    octave_chance = 0.28,
  },
  live_clavinet = {
    -- Funk synth / Moog bass: syncopated with chromatic approaches.
    steps = {
      {1,4,7,9,13},
      {1,3,7,11,13,16},
      {1,4,9,11,15},
      {1,3,7,9,12,15},
    },
    degrees  = {0,0,7,3,5,12,-1,0},
    accents  = {1,7,9},
    endings  = {5,12},
    octave_chance = 0.22,
  },
  brass_vocal = {
    -- Organ bass: chord-tone walk-ups with space for brass stabs.
    steps = {
      {1,3,7,9,13},
      {1,5,9,11,13},
      {1,3,7,13,15},
      {1,7,9,13,15},
    },
    degrees  = {0,7,0,5,3,12},
    accents  = {1,9},
    endings  = {5,12},
    octave_chance = 0.18,
  },
  french_touch = {
    -- Filtered analog bass: 4-on-floor anchored with pickup 16ths.
    steps = {
      {1,5,9,11,13},
      {1,3,9,13,15},
      {1,5,9,13},
      {1,3,7,11,13},
    },
    degrees  = {0,0,7,5,12},
    accents  = {1,5,9,13},
    endings  = {7,12},
    octave_chance = 0.20,
  },
}

local ELECTRO_SPECS = {
  classic_808 = {
    steps = {
      {1,7,11,15},
      {1,4,9,11,15},
      {1,7,10,13},
      {1,4,11,15,16},
    },
    degrees = {0,12,7,0,3,10},
    accents = {1,11,15},
    endings = {7,12},
    octave_chance = 0.28,
  },
  detroit_electro = {
    steps = {
      {1,6,11,15},
      {1,4,8,12,15},
      {1,6,10,13},
      {1,4,11,15},
    },
    degrees = {0,0,3,7,10,12},
    accents = {1,6,11},
    endings = {5,10},
    octave_chance = 0.18,
  },
  vocoder_robot = {
    steps = {
      {1,4,7,11,14},
      {1,6,9,12,15},
      {1,4,8,11,15},
      {1,6,10,13,16},
    },
    degrees = {0,12,0,7,3,10},
    accents = {1,7,11,15},
    endings = {7,12},
    octave_chance = 0.24,
  },
  acid_electro = {
    steps = {
      {1,4,7,10,12,15},
      {1,3,6,9,11,14},
      {1,4,7,10,13,15},
      {1,3,7,10,12,16},
    },
    degrees = {0,0,3,7,10,12},
    accents = {1,7,10,15},
    slides = {3,6,10,14},
    endings = {7,12},
    octave_chance = 0.10,
  },
}

-- UK Garage 4x4 bass: syncopated answers around the four-floor kicks with
-- octave flips, late-16th pickups, and chord-tone walks.  Notes on the kick
-- beats (step 1, 5, 9, 13) are limited to root/fifth to avoid masking the
-- drum; syncopated off-steps carry melody and interest.
local GARAGE4_SPECS = {
  organ_4x4 = {
    -- Organ bass: chord-tone stabs between kicks, decisive octave jumps.
    steps = {
      {1, 3, 7, 9, 13},
      {1, 5, 9, 11, 13},
      {1, 3, 7, 13, 15},
      {1, 7, 9, 13, 16},
    },
    degrees      = {0, 7, 0, 5, 3, 12},
    accents      = {1, 9, 13},
    endings      = {5, 12},
    octave_chance = 0.22,
  },
  soulful_vocal = {
    -- Soulful sub-bass: long anchors on beats 1/3, late pickup answers.
    steps = {
      {1, 5, 9, 13},
      {1, 4, 9, 11, 15},
      {1, 5, 9, 12, 13},
      {1, 7, 9, 13, 16},
    },
    degrees      = {0, 0, 7, 3, 5, 12},
    accents      = {1, 9},
    endings      = {7, 12},
    octave_chance = 0.16,
  },
  dark_sub = {
    -- Reese/sub bass: follows the displaced kick at step 4, dark sparse motion.
    steps = {
      {1, 4, 7, 11, 13},
      {1, 3, 7, 9, 12},
      {1, 4, 9, 11, 15},
      {1, 3, 7, 11, 13, 16},
    },
    degrees      = {0, 0, 3, 7, 10, 12},
    accents      = {1, 7, 13},
    endings      = {7, 12},
    octave_chance = 0.12,
  },
  ravey_speed = {
    -- FM/organ bass: rapid 16th pickups and octave flips for rave energy.
    steps = {
      {1, 3, 7, 9, 13},
      {1, 4, 7, 10, 13, 16},
      {1, 3, 7, 9, 12, 15},
      {1, 4, 9, 11, 13, 16},
    },
    degrees      = {0, 12, 7, 0, 3, 5},
    accents      = {1, 7, 9, 13},
    endings      = {5, 12},
    octave_chance = 0.24,
  },
}

local function garage4_bar(archetype, bar, rng, groove)
  local spec = GARAGE4_SPECS[archetype] or GARAGE4_SPECS.organ_4x4
  local events = {}
  local steps = spec.steps[((bar - 1) % #spec.steps) + 1]
  for index, step in ipairs(steps) do
    local avoid_kick = kick_at(groove, bar, step) and step ~= 1
    if not avoid_kick or rng:chance(0.15) then
      local degree = spec.degrees[((index + bar - 2) % #spec.degrees) + 1]
      if index == 1 then degree = 0 end
      if bar == 4 and step == steps[#steps] then
        degree = spec.endings[rng:int(1, #spec.endings)]
      end
      if step ~= 1 and rng:chance(spec.octave_chance) then degree = degree + 12 end
      local accent = contains(spec.accents, step) and rng:chance(0.82)
      local length = (step % 4 == 1) and rng:int(2, 3) or 1
      add_event(events, step, degree, length, rng:int(82, 110), accent, false)
    end
  end
  if next(events) == nil then
    add_event(events, 1, 0, 2, rng:int(92, 108), true, false)
  end
  return events
end

local function electro_bar(archetype, voice_family, bar, rng, groove)
  local spec = ELECTRO_SPECS[archetype] or ELECTRO_SPECS.classic_808
  local events = {}
  local steps = spec.steps[((bar - 1) % #spec.steps) + 1]
  for index, step in ipairs(steps) do
    local avoid_kick = kick_at(groove, bar, step) and step ~= 1
    local allow_overlap = (voice_family == "303") and rng:chance(0.22)
    if not avoid_kick or allow_overlap then
      local degree = spec.degrees[((index + bar - 2) % #spec.degrees) + 1]
      if index == 1 then degree = 0 end
      if bar == 4 and step == steps[#steps] then
        degree = spec.endings[rng:int(1, #spec.endings)]
      end
      if step ~= 1 and rng:chance(spec.octave_chance or 0) then degree = degree + 12 end
      local accent = contains(spec.accents, step) and rng:chance(0.84)
      local slide = voice_family == "303" and contains(spec.slides, step) and
        index < #steps and rng:chance(0.68)
      local length = (step % 4 == 1) and rng:int(2, 3) or 1
      add_event(events, step, degree, slide and 2 or length, rng:int(84, 112), accent, slide)
    end
  end
  if next(events) == nil then
    add_event(events, 1, 0, 2, rng:int(92, 108), true, false)
  end
  return events
end

local function funky_bar(archetype, bar, rng, groove)
  local spec = FUNKY_SPECS[archetype] or FUNKY_SPECS.filtered_disco
  local events = {}
  local steps = spec.steps[((bar - 1) % #spec.steps) + 1]
  for index, step in ipairs(steps) do
    local avoid_kick = kick_at(groove, bar, step) and step ~= 1
    if not avoid_kick or rng:chance(0.15) then
      local degree = spec.degrees[((index + bar - 2) % #spec.degrees) + 1]
      if index == 1 then degree = 0 end
      if bar == 4 and step == steps[#steps] then
        degree = spec.endings[rng:int(1, #spec.endings)]
      end
      if step ~= 1 and rng:chance(spec.octave_chance) then degree = degree + 12 end
      local accent = contains(spec.accents, step) and rng:chance(0.82)
      -- Beat-downbeat notes are held longer; pickups and syncopations are short.
      local length = (step % 4 == 1) and rng:int(2, 3) or 1
      add_event(events, step, degree, length, rng:int(82, 110), accent, false)
    end
  end
  if next(events) == nil then
    add_event(events, 1, 0, 2, rng:int(92, 108), true, false)
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
  for bar = 1, 4 do
    if identity.genre == "ACID" and voice_family == "303" then
      bars[bar] = acid_bar(identity.archetype, bar, rng)
    elseif identity.genre == "FUNKY" then
      bars[bar] = funky_bar(identity.archetype, bar, rng, groove)
    elseif identity.genre == "ELECTRO" then
      bars[bar] = electro_bar(identity.archetype, voice_family, bar, rng, groove)
    elseif identity.genre == "GARAGE4" then
      bars[bar] = garage4_bar(identity.archetype, bar, rng, groove)
    else
      bars[bar] = make_bar(identity.genre, voice_family, bar, rng, groove)
    end
  end
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
    base=((identity.genre=="ACID") and 0.82 or 0.78) + rng:float() * 0.12,
    drop=((identity.genre=="ACID") and 1.12 or 1.05) + rng:float() * 0.12,
    second_drop=((identity.genre=="ACID") and 1.28 or 1.18) + rng:float() * 0.18,
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
