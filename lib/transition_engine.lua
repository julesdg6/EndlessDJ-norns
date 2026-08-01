-- Deterministic phrase-aligned stem transition planning.
local M = {}

M.STEMS = {"kick", "percussion", "bass", "chords", "lead", "samples", "fx"}
M.MODES = {"classic", "stem", "producer"}

local STRATEGIES = {
  classic_blend=true, bass_swap=true, percussion_overlay=true,
  vocal_tease=true, clean_cut=true, fx_exit=true,
}

local PAIR_MATRIX = {
  ["HOUSE>TECHNO"]="percussion_overlay",
  ["TWO_STEP>DNB"]="bass_swap",
  ["DEEP>HARDTECHNO"]="clean_cut",
  ["TRANCE>DUBSTEP"]="fx_exit",
  ["JUNGLE>LIQUID"]="bass_swap",
  ["AFRO>ELECTRO"]="percussion_overlay",
  ["HARDSTYLE>MINIMAL"]="clean_cut",
}

local MODE_STRATEGIES = {
  classic={"classic_blend"},
  stem={"bass_swap", "percussion_overlay", "vocal_tease", "clean_cut", "fx_exit"},
  producer={"bass_swap", "percussion_overlay", "vocal_tease", "fx_exit", "clean_cut"},
}

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function hash(text, seed)
  local value=math.max(1,math.floor(seed or 1)%2147483647)
  for index=1,#text do value=(value*131+text:byte(index)+index)%2147483647 end
  return math.max(1,value)
end

local function copy(values)
  local result={}
  for key,value in pairs(values or {}) do
    result[key]=type(value)=="table" and copy(value) or value
  end
  return result
end

local function levels(outgoing, incoming)
  local result={outgoing={},incoming={}}
  for _,stem in ipairs(M.STEMS) do
    result.outgoing[stem]=(outgoing and outgoing[stem]) or 0
    result.incoming[stem]=(incoming and incoming[stem]) or 0
  end
  return result
end

local FULL={kick=1,percussion=1,bass=1,chords=1,lead=1,samples=1,fx=1}

local function stage_levels(strategy, stage)
  if strategy=="classic_blend" then
    local incoming=(stage-1)/3
    local outgoing=1-incoming
    local out,incoming_levels={},{}
    for _,stem in ipairs(M.STEMS) do out[stem]=outgoing incoming_levels[stem]=incoming end
    return levels(out,incoming_levels), true
  end
  if strategy=="clean_cut" then
    local data={
      levels(FULL,{fx=0.15}),
      levels({kick=1,percussion=0.7,bass=1,chords=0.35,fx=0.8},{samples=0.2,fx=0.35}),
      levels({fx=0.7},{kick=1,percussion=0.8,bass=1,chords=0.65,lead=0.4,samples=0.4,fx=0.5}),
      levels({},FULL),
    }
    return data[stage], false
  end
  if strategy=="bass_swap" then
    local data={
      levels(FULL,{percussion=0.45,samples=0.2,fx=0.2}),
      levels({kick=1,percussion=0.8,chords=0.55,lead=0.25,samples=0.25,fx=0.35},{bass=1,percussion=0.55,fx=0.2}),
      levels({percussion=0.45,chords=0.3,samples=0.2,fx=0.55},{kick=1,percussion=0.85,bass=1,chords=0.45,lead=0.3,samples=0.35,fx=0.35}),
      levels({},FULL),
    }
    return data[stage], false
  end
  if strategy=="percussion_overlay" then
    local data={
      levels(FULL,{percussion=0.65,fx=0.18}),
      levels({kick=1,bass=1,chords=0.75,lead=0.45,samples=0.3,fx=0.35},{percussion=1,samples=0.25,fx=0.3}),
      levels({percussion=0.3,chords=0.35,lead=0.2,samples=0.2,fx=0.5},{kick=1,percussion=1,bass=1,chords=0.5,lead=0.35,samples=0.4,fx=0.35}),
      levels({},FULL),
    }
    return data[stage], false
  end
  if strategy=="vocal_tease" then
    local data={
      levels(FULL,{samples=0.5,fx=0.25}),
      levels({kick=1,percussion=0.8,bass=1,chords=0.65,lead=0.25,fx=0.4},{samples=0.8,percussion=0.3,fx=0.35}),
      levels({percussion=0.4,chords=0.25,samples=0.15,fx=0.55},{kick=1,percussion=0.85,bass=1,chords=0.55,lead=0.45,samples=0.75,fx=0.4}),
      levels({},FULL),
    }
    return data[stage], false
  end
  local data={
    levels(FULL,{fx=0.25}),
    levels({kick=1,percussion=0.7,bass=1,chords=0.45,lead=0.2,samples=0.3,fx=1},{samples=0.2,fx=0.4}),
    levels({percussion=0.25,chords=0.2,samples=0.15,fx=1},{kick=1,percussion=0.8,bass=1,chords=0.55,lead=0.35,samples=0.4,fx=0.55}),
    levels({},FULL),
  }
  return data[stage], false
end

local function root_distance(a,b)
  local distance=math.abs((a or 0)-(b or 0))%12
  return math.min(distance,12-distance)
end

local function strategy_for(outgoing,incoming,mode,options)
  if mode=="classic" then return "classic_blend" end
  local pair=tostring(outgoing.genre)..">"..tostring(incoming.genre)
  local selected=PAIR_MATRIX[pair]
  local distance=root_distance(outgoing.root_pitch_class,incoming.root_pitch_class)
  if distance>5 then selected=(mode=="producer") and "fx_exit" or "clean_cut" end
  if selected then return selected end
  local candidates=MODE_STRATEGIES[mode]
  local seed=hash(pair,(outgoing.seed or 1)+(incoming.seed or 1)+(options.energy or 0)*97)
  return candidates[(seed%#candidates)+1]
end

local function enforce_low_end(stage,intentional)
  for _,stem in ipairs({"kick","bass"}) do
    local out=stage.levels.outgoing[stem]
    local incoming=stage.levels.incoming[stem]
    if intentional then
      local total=out+incoming
      if total>1 then
        stage.levels.outgoing[stem]=out/total
        stage.levels.incoming[stem]=incoming/total
      end
    elseif out>0 and incoming>0 then
      if incoming>=out then stage.levels.outgoing[stem]=0
      else stage.levels.incoming[stem]=0 end
    end
  end
end

function M.new(outgoing,incoming,options)
  options=options or {}
  assert(outgoing and incoming,"two song identities required")
  assert(outgoing.seed~=incoming.seed or outgoing.deck~=incoming.deck,
    "transition decks must remain independent")
  local mode=options.mode or "stem"
  assert(MODE_STRATEGIES[mode],"unknown transition mode")
  local strategy=strategy_for(outgoing,incoming,mode,options)
  local plan={
    schema_version=1, mode=mode, strategy=strategy, total_bars=32,
    phrase_bars=8, outgoing_seed=outgoing.seed, incoming_seed=incoming.seed,
    outgoing_genre=outgoing.genre, incoming_genre=incoming.genre,
    harmonic_distance=root_distance(outgoing.root_pitch_class,incoming.root_pitch_class),
    stages={}, overrides={}, cancelled=false,
  }
  for index=1,4 do
    local envelope,intentional=stage_levels(strategy,index)
    local stage={
      levels=envelope,index=index,first=(index-1)*8+1,last=index*8,
      intentional_low_end_overlap=intentional,
    }
    enforce_low_end(stage,intentional)
    plan.stages[index]=stage
  end
  if plan.harmonic_distance>5 then plan.warning="HARM" end
  return plan
end

function M.stage(plan,bar)
  if not plan or plan.cancelled then return nil end
  local index=clamp(math.floor((clamp(bar,1,32)-1)/plan.phrase_bars)+1,1,#plan.stages)
  return plan.stages[index]
end

function M.levels(plan,bar)
  local stage=M.stage(plan,bar)
  if not stage then return levels(FULL,{}) end
  local result=copy(stage.levels)
  for stem,owner in pairs(plan.overrides or {}) do
    if owner=="outgoing" then result.outgoing[stem]=1 result.incoming[stem]=0
    elseif owner=="incoming" then result.outgoing[stem]=0 result.incoming[stem]=1
    elseif owner=="both" then result.outgoing[stem]=0.5 result.incoming[stem]=0.5
    elseif owner=="off" then result.outgoing[stem]=0 result.incoming[stem]=0 end
  end
  return result
end

function M.ownership(plan,bar,stem)
  local state=M.levels(plan,bar)
  local out,incoming=state.outgoing[stem] or 0,state.incoming[stem] or 0
  if out>0 and incoming>0 then return "both" end
  if incoming>0 then return "incoming" end
  if out>0 then return "outgoing" end
  return "off"
end

function M.preview(plan,bar)
  local stage=M.stage(plan,bar)
  if not stage or stage.index>=#plan.stages then return {} end
  local now=M.levels(plan,bar)
  local future=M.levels(plan,stage.last+1)
  local changes={}
  for _,stem in ipairs(M.STEMS) do
    local before=(now.incoming[stem] or 0)-(now.outgoing[stem] or 0)
    local after=(future.incoming[stem] or 0)-(future.outgoing[stem] or 0)
    if after>before then changes[#changes+1]="+"..stem
    elseif after<before then changes[#changes+1]="-"..stem end
  end
  return changes
end

function M.override(plan,stem,owner)
  local known=false
  for _,name in ipairs(M.STEMS) do if name==stem then known=true end end
  assert(known,"unknown transition stem")
  assert(owner=="outgoing" or owner=="incoming" or owner=="both" or owner=="off",
    "unknown stem owner")
  if (stem=="kick" or stem=="bass") and owner=="both" then
    return false,"low-end overlap must come from an explicit bounded strategy"
  end
  plan.overrides[stem]=owner
  return true
end

function M.clear_override(plan,stem) plan.overrides[stem]=nil end
function M.cancel(plan) plan.cancelled=true end

function M.validate(plan)
  if type(plan)~="table" or plan.schema_version~=1 then return false,"unsupported transition schema" end
  if not MODE_STRATEGIES[plan.mode] or not STRATEGIES[plan.strategy] then return false,"unknown transition type" end
  if #plan.stages~=4 or plan.total_bars~=32 then return false,"transition must contain four phrases" end
  for index,stage in ipairs(plan.stages) do
    if stage.first~=(index-1)*8+1 or stage.last~=index*8 then return false,"transition is not phrase aligned" end
    for _,stem in ipairs(M.STEMS) do
      local out=stage.levels.outgoing[stem]
      local incoming=stage.levels.incoming[stem]
      if type(out)~="number" or type(incoming)~="number" then return false,"missing stem envelope" end
      if (stem=="kick" or stem=="bass") and not stage.intentional_low_end_overlap and out>0 and incoming>0 then
        return false,"unintended low-end overlap"
      end
      if stage.intentional_low_end_overlap and out+incoming>1.0001 then return false,"unbounded low-end overlap" end
    end
  end
  return true
end

return M
