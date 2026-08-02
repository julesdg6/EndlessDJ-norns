-- Deterministic multi-bar groove plans derived from a song identity.
-- Timing offsets are fractions of a 16th note for a shared scheduler to use.
local M = {}

local FEELS = {
  HOUSE={"straight","swung"}, FUNKY={"swung","syncopated"}, DIRTY={"straight","syncopated"},
  TECHNO={"straight","polymetric"}, GARAGE4={"swung","syncopated"}, TWO_STEP={"swung","broken"},
  BREAKS={"broken","syncopated"}, DUBSTEP={"halftime","broken"}, DEEP={"swung","straight"},
  ACID={"straight","syncopated"}, TRANCE={"straight","double_time"}, PROG={"straight","polymetric"},
  JUNGLE={"broken","double_time"}, DNB={"broken","double_time"}, LIQUID={"broken","swung"},
  HARDTECHNO={"straight","double_time"}, ELECTRO={"broken","syncopated"}, JUKE={"syncopated","double_time"},
  AFRO={"polymetric","syncopated"}, MINIMAL={"straight","polymetric"},   MELODIC={"straight","polymetric","swung"},
  SPEED={"swung","broken"}, BASSLINE={"swung","syncopated"}, HARDSTYLE={"straight","double_time"},
}

local PATTERNS = {
  straight={kick={1,5,9,13},snare={5,13},clap={5,13},hats={3,7,11,15},ohats={7,15},tom={}},
  swung={kick={1,5,9,13},snare={5,13},clap={5,13},hats={3,4,7,10,12,15},ohats={4,12},tom={}},
  syncopated={kick={1,4,7,11,13},snare={5,13},clap={5,13},hats={2,4,7,10,12,15},ohats={4,11},tom={8,16}},
  broken={kick={1,4,11,15},snare={5,13},clap={},hats={3,6,8,11,14,16},ohats={6,14},tom={}},
  halftime={kick={1,11},snare={9},clap={9},hats={3,7,11,15},ohats={9},tom={}},
  double_time={kick={1,5,9,13},snare={5,13},clap={},hats={2,4,6,8,10,12,14,16},ohats={3,11},tom={}},
  polymetric={kick={1,5,9,13},snare={7,15},clap={5,13},hats={2,4,7,10,12,15},ohats={4,9,13},tom={3,8,12}},
}

local PHRASE_LENGTHS = {
  HOUSE={4,8}, FUNKY={4,8}, DIRTY={4,8}, TECHNO={8,16}, GARAGE4={4,8},
  TWO_STEP={2,4,8}, BREAKS={4,8}, DUBSTEP={4,8,16}, DEEP={8,16}, ACID={4,8},
  TRANCE={8,16}, PROG={8,16}, JUNGLE={4,8}, DNB={4,8}, LIQUID={8,16},
  HARDTECHNO={4,8}, ELECTRO={4,8}, JUKE={2,4}, AFRO={8,16}, MINIMAL={8,16},
  MELODIC={8,16}, SPEED={2,4,8}, BASSLINE={2,4,8}, HARDSTYLE={4,8},
}

local ACID_GROOVES = {
  classic_303={
    feel="straight", phrase_bars=8,
    pattern={kick={1,5,9,13},snare={5,13},clap={5,13},hats={3,7,11,15},ohats={7,15},tom={8,16}},
    fill={{12,"hats"},{15,"tom"},{16,"snare"}},
  },
  jack_acid={
    feel="syncopated", phrase_bars=8,
    pattern={kick={1,5,9,13},snare={5,13},clap={5,13},hats={2,4,7,10,12,15},ohats={4,11,15},tom={8,16}},
    fill={{11,"tom"},{14,"snare"},{15,"tom"},{16,"clap"}},
  },
  deep_acid={
    feel="straight", phrase_bars=16,
    pattern={kick={1,5,9,13},snare={13},clap={5,13},hats={7,11,15},ohats={15},tom={}},
    fill={{14,"hats"},{16,"clap"}},
  },
  rave_acid={
    feel="straight", phrase_bars=8,
    pattern={kick={1,5,9,13},snare={5,13},clap={5,13},hats={2,3,6,7,10,11,14,15},ohats={7,11,15},tom={8,12,16}},
    fill={{13,"snare"},{14,"tom"},{15,"snare"},{16,"clap"}},
  },
}

-- Per-archetype groove plans for Funky House.  The step positions capture
-- disco open-hat offbeats, ghost snares between beats 2/4, conga-style tom
-- accents, and kick pickups that distinguish each archetype, while the feel
-- (timing swing/offset) still comes from the song identity so consecutive
-- seeds produce perceptibly different grooves within the same archetype.
local FUNKY_GROOVES = {
  filtered_disco = {
    -- Disco shuffle: 8th-note hats on all offbeats, open hats every quarter,
    -- syncopated kick pickups at 3 and 11, conga accents at 10/14.
    phrase_bars = 8,
    pattern = {
      kick  = {1,3,5,9,11,13},
      snare = {3,5,7,11,13,15},
      clap  = {5,13},
      hats  = {2,4,6,8,10,12,14,16},
      ohats = {4,8,12,16},
      tom   = {10,14},
    },
    fill = {{12,"ohats"},{14,"tom"},{15,"snare"},{16,"clap"}},
  },
  live_clavinet = {
    -- Syncopated funk: sparse offbeat hats with selective opens, clavinet
    -- call-response tom accents at 6/14, syncopated kick.
    phrase_bars = 8,
    pattern = {
      kick  = {1,4,7,11,13},
      snare = {3,5,9,13,15},
      clap  = {5,13},
      hats  = {2,4,6,8,10,12,14,16},
      ohats = {4,12},
      tom   = {6,14},
    },
    fill = {{11,"tom"},{13,"snare"},{15,"tom"},{16,"clap"}},
  },
  brass_vocal = {
    -- Punchy 4/4 with space for brass stabs: sparse hats, open hats on
    -- off-beats 7/15, kick pickup at 11, phrase punctuation toms at 8/16.
    phrase_bars = 4,
    pattern = {
      kick  = {1,5,9,11,13},
      snare = {3,5,7,13,15},
      clap  = {5,13},
      hats  = {3,5,7,9,11,13,15},
      ohats = {7,15},
      tom   = {8,16},
    },
    fill = {{12,"snare"},{14,"tom"},{16,"clap"}},
  },
  french_touch = {
    -- Pumping 4-on-the-floor with ghost snares, offbeat quarter open hats
    -- and a single mid-phrase tom accent for the French-touch filter feel.
    phrase_bars = 4,
    pattern = {
      kick  = {1,5,9,13},
      snare = {5,7,11,13,15},
      clap  = {5,13},
      hats  = {3,7,11,15},
      ohats = {4,12},
      tom   = {8},
    },
    fill = {{14,"tom"},{15,"snare"},{16,"clap"}},
  },
}

-- Per-archetype groove plans for Melodic genres.  Patterns open space for
-- the harmonic lead and pads: controlled kick, restrained toms, and open hats
-- that breathe between chord hits.  The feel (timing) is fixed per archetype
-- so the groove character is deterministic regardless of the groove_family
-- selected in the song identity.
local MELODIC_GROOVES = {
  melodic_techno = {
    -- Controlled four-floor techno: precise kick, restrained open hats on
    -- off-beats 7/15, no toms so the harmonic lead has space to breathe.
    feel = "straight", phrase_bars = 8,
    pattern = {
      kick  = {1,5,9,13},
      snare = {9,13},
      clap  = {5,13},
      hats  = {3,7,11,15},
      ohats = {7,15},
      tom   = {},
    },
    fill = {{14,"hats"},{15,"snare"},{16,"clap"}},
  },
  melodic_house = {
    -- House four-floor with swung offbeat hats and space for chord pads.
    -- Ghost snares on 3/11 keep the groove warm without burying the melody.
    feel = "swung", phrase_bars = 8,
    pattern = {
      kick  = {1,5,9,13},
      snare = {5,13},
      clap  = {5,13},
      hats  = {3,4,7,10,12,15},
      ohats = {4,12},
      tom   = {},
    },
    fill = {{12,"ohats"},{14,"snare"},{16,"clap"}},
  },
  cinematic_prog = {
    -- Spacious 16-bar phrase: minimal snare and toms let strings and pads
    -- dominate; single open hat on 7/15 marks the half-bar with restraint.
    feel = "straight", phrase_bars = 16,
    pattern = {
      kick  = {1,5,9,13},
      snare = {9},
      clap  = {5,13},
      hats  = {3,7,11,15},
      ohats = {7,15},
      tom   = {11},
    },
    fill = {{13,"tom"},{15,"snare"},{16,"clap"}},
  },
  vocal_melodic = {
    -- Open straight groove with a single mid-phrase tom accent to punctuate
    -- vocal phrases; open hats on 7/15 keep energy without crowding vocals.
    feel = "straight", phrase_bars = 8,
    pattern = {
      kick  = {1,5,9,13},
      snare = {5,13},
      clap  = {5,13},
      hats  = {3,7,11,15},
      ohats = {7,15},
      tom   = {8},
    },
    fill = {{12,"hats"},{15,"tom"},{16,"clap"}},
  },
}

local FILL_RECIPES = {
  straight={{14,"tom"},{15,"snare"},{16,"clap"}},
  swung={{12,"hats"},{15,"tom"},{16,"clap"}},
  syncopated={{11,"tom"},{14,"snare"},{16,"clap"}},
  broken={{12,"snare"},{14,"snare"},{15,"tom"},{16,"snare"}},
  halftime={{15,"snare"},{16,"clap"}},
  double_time={{13,"snare"},{14,"snare"},{15,"tom"},{16,"snare"}},
  polymetric={{11,"tom"},{14,"tom"},{16,"clap"}},
}

local BASE_VELOCITY={kick=110,snare=100,clap=104,hats=70,ohats=74,tom=88}
local function contains(values,wanted)
  for _,value in ipairs(values or {}) do if value==wanted then return true end end
  return false
end
local function copy(values) local result={} for i,v in ipairs(values or {}) do result[i]=v end return result end
local function add_unique(values,step)
  if not contains(values,step) then values[#values+1]=step end
  table.sort(values)
end
local function rotate_steps(values, amount)
  local result={}
  for _,step in ipairs(values or {}) do result[#result+1]=((step-1+amount)%16)+1 end
  table.sort(result)
  return result
end
local function timing_for(feel,step,swing)
  if feel=="swung" and step%2==0 then return swing end
  if feel=="broken" and (step==4 or step==12) then return 0.06 end
  if feel=="polymetric" and step%3==0 then return 0.04 end
  return 0
end
local function rng_new(seed)
  local rng={state=math.max(1,seed%2147483647)}
  function rng:next() self.state=(self.state*48271)%2147483647 return self.state end
  function rng:float() return (self:next()-1)/2147483646 end
  function rng:int(first,last) return first+math.floor(self:float()*(last-first+1)) end
  function rng:chance(p) return self:float()<p end
  function rng:pick(values) return values[self:int(1,#values)] end
  return rng
end
local function make_bar(pattern,bar_number,phrase_bars,rng,feel,swing)
  local bar={}
  for _,voice in ipairs({"kick","snare","clap","hats","ohats","tom"}) do
    local steps=copy(pattern[voice])
    local phrase_position=((bar_number-1)%4)+1
    if feel=="polymetric" and voice=="hats" then steps=rotate_steps(steps,(bar_number-1)*3)
    elseif feel=="polymetric" and voice=="tom" then steps=rotate_steps(steps,(bar_number-1)*5) end
    if phrase_position==2 and (voice=="hats" or voice=="tom") and rng:chance(0.55) then
      add_unique(steps,rng:pick({8,12,16}))
    elseif phrase_position==3 and voice=="kick" and rng:chance(0.6) then add_unique(steps,rng:pick({4,12,16}))
    elseif bar_number==phrase_bars and voice=="snare" then add_unique(steps,16) end
    if bar_number>4 and bar_number%8==0 and voice=="ohats" then add_unique(steps,16) end
    bar[voice]={}
    for index,step in ipairs(steps) do
      local velocity=BASE_VELOCITY[voice]+((index-1)%4)*2+rng:int(-5,5)
      local event={
        velocity=math.max(30,math.min(127,velocity)),
        offset=timing_for(feel,step,swing),
      }
      event.ghost=(voice=="snare" and step~=5 and step~=9 and step~=13)
      if event.ghost then event.velocity=rng:int(48,70) end
      bar[voice][step]=event
    end
  end
  return bar
end

local function make_fill(feel,phrase_bars,rng,recipe,style)
  local events={}
  for index,item in ipairs(recipe or FILL_RECIPES[feel] or FILL_RECIPES.straight) do
    local step,voice=item[1],item[2]
    events[step]={voice=voice,velocity=math.min(127,
      (BASE_VELOCITY[voice] or 88)+index*3+rng:int(-3,3))}
  end
  return {bar=phrase_bars,style=style or (feel.."_turnaround"),events=events}
end

function M.new(identity)
  assert(identity and identity.genre,"song identity required")
  local rng=rng_new(assert(identity.stream_seeds and identity.stream_seeds.groove,"groove seed required"))
  local compatible=FEELS[identity.genre] or {"straight"}
  local acid_spec=identity.genre=="ACID" and ACID_GROOVES[identity.archetype] or nil
  local funky_spec=identity.genre=="FUNKY" and FUNKY_GROOVES[identity.archetype] or nil
  local melodic_spec=identity.genre=="MELODIC" and MELODIC_GROOVES[identity.archetype] or nil
  local feel=(acid_spec and acid_spec.feel) or (melodic_spec and melodic_spec.feel)
    or identity.groove_family or rng:pick(compatible)
  local pattern=(acid_spec and acid_spec.pattern) or (funky_spec and funky_spec.pattern)
    or (melodic_spec and melodic_spec.pattern) or PATTERNS[feel]
  assert(pattern,"identity selected unknown groove")
  local swing=(feel=="swung") and (0.12+rng:float()*0.16) or 0
  local phrase_bars=rng:pick(PHRASE_LENGTHS[identity.genre] or {4})
  if acid_spec then phrase_bars=acid_spec.phrase_bars end
  if funky_spec then phrase_bars=funky_spec.phrase_bars end
  if melodic_spec then phrase_bars=melodic_spec.phrase_bars end
  local bars={}
  for bar_number=1,phrase_bars do
    bars[bar_number]=make_bar(pattern,bar_number,phrase_bars,rng,feel,swing)
  end
  local fill_recipe=(acid_spec and acid_spec.fill) or (funky_spec and funky_spec.fill)
    or (melodic_spec and melodic_spec.fill)
  local fill_style=acid_spec and (identity.archetype.."_fill") or
    (funky_spec and (identity.archetype.."_funky")) or
    (melodic_spec and (identity.archetype.."_melodic")) or nil
  return {
    schema_version=1, genre=identity.genre, archetype=identity.archetype,
    family=feel, swing=swing, phrase_bars=phrase_bars, bars=bars,
    cycles=(feel=="polymetric") and {hats=3,tom=5} or nil,
    fill=make_fill(feel,phrase_bars,rng,fill_recipe,fill_style),
  }
end
function M.event(plan,absolute_bar,voice,step)
  if not plan or not plan.bars then return nil end
  local bar=((absolute_bar-1)%plan.phrase_bars)+1
  return plan.bars[bar] and plan.bars[bar][voice] and plan.bars[bar][voice][step] or nil
end
function M.is_fill_step(plan,absolute_bar,step)
  if not plan or ((absolute_bar-1)%plan.phrase_bars)+1~=plan.fill.bar then return false end
  return plan.fill.events[step]~=nil
end
function M.fill_event(plan,absolute_bar,step)
  if not M.is_fill_step(plan,absolute_bar,step) then return nil end
  return plan.fill.events[step]
end
function M.role_offset(plan,_absolute_bar,step,role)
  if not plan then return 0 end
  local base=timing_for(plan.family,step,plan.swing or 0)
  local scale={drums=1,bass=0.75,chords=1,mono=0.5,samples=1}
  return base*(scale[role] or 1)
end
function M.validate(plan)
  if type(plan)~="table" or plan.schema_version~=1 then return false,"unsupported groove schema" end
  if not PATTERNS[plan.family] then return false,"unknown groove family" end
  if type(plan.bars)~="table" or #plan.bars~=plan.phrase_bars then return false,"invalid phrase length" end
  if not contains({2,4,8,16},plan.phrase_bars) then return false,"unsupported phrase length" end
  if type(plan.fill)~="table" or plan.fill.bar~=plan.phrase_bars or type(plan.fill.events)~="table" then
    return false,"invalid phrase fill"
  end
  if plan.family=="polymetric" and (not plan.cycles or plan.cycles.hats~=3 or plan.cycles.tom~=5) then
    return false,"invalid polymetric cycles"
  end
  return true
end
return M
