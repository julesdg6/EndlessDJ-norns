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
  AFRO={"polymetric","syncopated"}, MINIMAL={"straight","polymetric"}, MELODIC={"straight","polymetric"},
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

local BASE_VELOCITY={kick=110,snare=100,clap=104,hats=70,ohats=74,tom=88}
local function contains(values,wanted) for _,value in ipairs(values or {}) do if value==wanted then return true end end return false end
local function copy(values) local result={} for i,v in ipairs(values or {}) do result[i]=v end return result end
local function add_unique(values,step) if not contains(values,step) then values[#values+1]=step end table.sort(values) end
local function timing_for(feel,step,swing)
  if feel=="swung" and step%2==0 then return swing end
  if feel=="broken" and (step==4 or step==12) then return -0.06 end
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
local function make_bar(pattern,bar_number,rng,feel,swing)
  local bar={}
  for _,voice in ipairs({"kick","snare","clap","hats","ohats","tom"}) do
    local steps=copy(pattern[voice])
    if bar_number==2 and (voice=="hats" or voice=="tom") and rng:chance(0.55) then add_unique(steps,rng:pick({8,12,16}))
    elseif bar_number==3 and voice=="kick" and rng:chance(0.6) then add_unique(steps,rng:pick({4,12,16}))
    elseif bar_number==4 and voice=="snare" then add_unique(steps,16) end
    bar[voice]={}
    for index,step in ipairs(steps) do
      local event={velocity=math.max(30,math.min(127,BASE_VELOCITY[voice]+((index-1)%4)*2+rng:int(-5,5))),offset=timing_for(feel,step,swing)}
      event.ghost=(voice=="snare" and step~=5 and step~=9 and step~=13)
      if event.ghost then event.velocity=rng:int(48,70) end
      bar[voice][step]=event
    end
  end
  return bar
end

function M.new(identity)
  assert(identity and identity.genre,"song identity required")
  local rng=rng_new(assert(identity.stream_seeds and identity.stream_seeds.groove,"groove seed required"))
  local compatible=FEELS[identity.genre] or {"straight"}
  local feel=rng:pick(compatible)
  local swing=(feel=="swung") and (0.12+rng:float()*0.16) or 0
  local bars={}
  for bar_number=1,4 do bars[bar_number]=make_bar(PATTERNS[feel],bar_number,rng,feel,swing) end
  return {schema_version=1,genre=identity.genre,archetype=identity.archetype,family=feel,swing=swing,phrase_bars=4,bars=bars,fill={bar=4,steps={13,14,15,16},style=(feel=="halftime") and "sparse" or "turnaround"}}
end
function M.event(plan,absolute_bar,voice,step)
  if not plan or not plan.bars then return nil end
  local bar=((absolute_bar-1)%plan.phrase_bars)+1
  return plan.bars[bar] and plan.bars[bar][voice] and plan.bars[bar][voice][step] or nil
end
function M.is_fill_step(plan,absolute_bar,step)
  if not plan or ((absolute_bar-1)%plan.phrase_bars)+1~=plan.fill.bar then return false end
  return contains(plan.fill.steps,step)
end
function M.validate(plan)
  if type(plan)~="table" or plan.schema_version~=1 then return false,"unsupported groove schema" end
  if not PATTERNS[plan.family] then return false,"unknown groove family" end
  if type(plan.bars)~="table" or #plan.bars~=plan.phrase_bars then return false,"invalid phrase length" end
  return true
end
return M
