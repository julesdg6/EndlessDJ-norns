-- Deterministic phrase-level arrangement plans and stem energy envelopes.
local M={}

local GRAMMARS={
  club_linear={
    {"INTRO",16},{"GROOVE",16},{"MAIN",16},{"BREAK",8},
    {"BUILD",8},{"DROP",24},{"DEVELOP",8},
  },
  hook_ab={
    {"INTRO",8},{"GROOVE",16},{"MAIN",16},{"BREAK",8},
    {"BUILD",8},{"DROP",16},{"DEVELOP",16},{"OUTRO",8},
  },
  double_drop={
    {"INTRO",8},{"GROOVE",16},{"MAIN",8},{"BUILD",8},
    {"DROP",16},{"BREAK",8},{"BUILD",8},{"DROP",16},{"DEVELOP",8},
  },
  slow_burn={
    {"INTRO",16},{"GROOVE",24},{"MAIN",16},{"BREAK",16},
    {"BUILD",8},{"DROP",16},
  },
}

local ENVELOPES={
  INTRO={kick=0.72,percussion=0.45,bass=0,chords=0.18,mono=0,samples=0.18,fx=0.15},
  GROOVE={kick=1,percussion=0.72,bass=0.78,chords=0.35,mono=0.18,samples=0.28,fx=0.12},
  MAIN={kick=1,percussion=0.9,bass=0.92,chords=0.78,mono=0.62,samples=0.55,fx=0.2},
  BREAK={kick=0.12,percussion=0.28,bass=0.2,chords=0.82,mono=0.7,samples=0.65,fx=0.55},
  BUILD={kick=0.7,percussion=0.9,bass=0.48,chords=0.62,mono=0.8,samples=0.72,fx=0.9},
  DROP={kick=1,percussion=1,bass=1,chords=0.82,mono=0.9,samples=0.78,fx=0.42},
  DEVELOP={kick=1,percussion=0.82,bass=0.9,chords=0.58,mono=0.5,samples=0.42,fx=0.2},
  OUTRO={kick=1,percussion=0.68,bass=0.35,chords=0.15,mono=0,samples=0.12,fx=0.15},
  MIX={kick=1,percussion=0.7,bass=0.65,chords=0.35,mono=0.25,samples=0.25,fx=0.35},
}

local function copy_envelope(name)
  local result={}
  for role,value in pairs(ENVELOPES[name] or ENVELOPES.GROOVE) do result[role]=value end
  return result
end

local function rng_new(seed)
  local rng={state=math.max(1,seed%2147483647)}
  function rng:next() self.state=(self.state*48271)%2147483647 return self.state end
  function rng:float() return (self:next()-1)/2147483646 end
  function rng:int(first,last) return first+math.floor(self:float()*(last-first+1)) end
  return rng
end

local function section_event(name,occurrence)
  if name=="BUILD" then return occurrence==1 and "riser" or "riser_b" end
  if name=="DROP" then return occurrence==1 and "impact" or "impact_b" end
  if name=="BREAK" then return "breakdown" end
  if name=="OUTRO" then return "outro" end
end

function M.new(identity)
  assert(identity and identity.stream_seeds and identity.stream_seeds.arrangement,
    "arrangement seed required")
  local family=identity.arrangement_family or "club_linear"
  local grammar=assert(GRAMMARS[family],"unknown arrangement family")
  local rng=rng_new(identity.stream_seeds.arrangement)
  local sections={}
  local events={}
  local occurrences={}
  local first=1
  for index,item in ipairs(grammar) do
    local name,length=item[1],item[2]
    occurrences[name]=(occurrences[name] or 0)+1
    local section={
      name=name, first=first, last=first+length-1, length=length,
      phrase_bars=(length>=16 and rng:float()>0.48) and 8 or 4,
      energy=copy_envelope(name), index=index, occurrence=occurrences[name],
    }
    sections[#sections+1]=section
    local event=section_event(name,occurrences[name])
    if event then events[first]=event end
    first=section.last+1
  end
  assert(first==97,"arrangement grammar must fill 96 performance bars")
  sections[#sections+1]={
    name="MIX",first=97,last=128,length=32,phrase_bars=8,
    energy=copy_envelope("MIX"),index=#sections+1,occurrence=1,
  }
  return {
    schema_version=1,genre=identity.genre,archetype=identity.archetype,
    family=family,total_bars=128,performance_bars=96,
    sections=sections,events=events,
  }
end

function M.section(plan,bar)
  if not plan then return nil end
  for _,section in ipairs(plan.sections or {}) do
    if bar>=section.first and bar<=section.last then return section end
  end
end

function M.section_name(plan,bar)
  local section=M.section(plan,bar)
  return section and section.name or "PLAY"
end

function M.role_level(plan,bar,role)
  local section=M.section(plan,bar)
  return section and (section.energy[role] or 0) or 0
end

function M.event_at(plan,bar)
  return plan and plan.events and plan.events[bar] or nil
end

function M.phrase(plan,bar)
  local section=M.section(plan,bar)
  if not section then return nil end
  local offset=bar-section.first
  local phrase=math.floor(offset/section.phrase_bars)+1
  return {
    section=section.name,index=phrase,
    bar=(offset%section.phrase_bars)+1,
    length=math.min(section.phrase_bars,section.length-(phrase-1)*section.phrase_bars),
  }
end

function M.gate(plan,bar,step,role,amount)
  if amount>=0.999 then return true end
  if amount<=0 then return false end
  local seed=(bar*977+step*131+#role*53+(plan and plan.schema_version or 1)*17)%1000
  return seed/1000<amount
end

function M.validate(plan)
  if type(plan)~="table" or plan.schema_version~=1 then return false,"unsupported arrangement schema" end
  if not GRAMMARS[plan.family] then return false,"unknown arrangement family" end
  if type(plan.sections)~="table" or #plan.sections<2 then return false,"missing arrangement sections" end
  local next_bar=1
  for _,section in ipairs(plan.sections) do
    if section.first~=next_bar or section.last<section.first then return false,"non-contiguous arrangement" end
    if type(section.energy)~="table" or not section.energy.kick then return false,"missing stem envelope" end
    next_bar=section.last+1
  end
  if next_bar~=129 then return false,"arrangement must cover 128 bars" end
  return true
end

return M
