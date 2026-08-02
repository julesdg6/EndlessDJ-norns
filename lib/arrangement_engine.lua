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

-- Per-archetype arrangement grammars for Funky House.  Each section plan is
-- tailored to its archetype's character while still resolving to exactly 96
-- performance bars so the shared MIX section always begins at bar 97.
local FUNKY_GRAMMARS = {
  filtered_disco = {
    -- Extended sample-led intro (16 bars), short groove reveal, then standard
    -- hook A/B structure with disco-loop breakdown and percussion outro.
    {"INTRO",16},{"GROOVE",8},{"MAIN",16},{"BREAK",8},
    {"BUILD",8},{"DROP",16},{"DEVELOP",16},{"OUTRO",8},
  },
  live_clavinet = {
    -- Short intro then a long groove-reveal section (24 bars) so the clavinet
    -- bass and groove establish their identity before the full arrangement.
    {"INTRO",8},{"GROOVE",24},{"MAIN",8},{"BREAK",8},
    {"BUILD",8},{"DROP",24},{"DEVELOP",16},
  },
  brass_vocal = {
    -- Quick intro and groove, long breakdown (16 bars) that exposes vocal
    -- and brass material, then full-band drop.
    {"INTRO",8},{"GROOVE",8},{"MAIN",16},{"BREAK",16},
    {"BUILD",8},{"DROP",16},{"DEVELOP",16},{"OUTRO",8},
  },
  french_touch = {
    -- Double-drop filter-pump structure: build, drop, break, build, drop.
    {"INTRO",8},{"GROOVE",16},{"MAIN",8},{"BUILD",8},
    {"DROP",16},{"BREAK",8},{"BUILD",8},{"DROP",16},{"DEVELOP",8},
  },
}

local ELECTRO_GRAMMARS = {
  classic_808 = {
    {"INTRO",16},{"GROOVE",16},{"MAIN",8},{"BREAK",8},
    {"BUILD",8},{"DROP",16},{"DEVELOP",16},{"OUTRO",8},
  },
  detroit_electro = {
    {"INTRO",16},{"GROOVE",24},{"MAIN",16},{"BREAK",8},
    {"BUILD",8},{"DROP",16},{"DEVELOP",8},
  },
  vocoder_robot = {
    {"INTRO",8},{"GROOVE",16},{"MAIN",16},{"BREAK",16},
    {"BUILD",8},{"DROP",16},{"DEVELOP",8},{"OUTRO",8},
  },
  acid_electro = {
    {"INTRO",8},{"GROOVE",16},{"MAIN",8},{"BUILD",8},
    {"DROP",16},{"BREAK",8},{"BUILD",8},{"DROP",16},{"OUTRO",8},
  },
}

local ACID_GRAMMARS={
  classic_303={
    {"INTRO",16},{"GROOVE",16},{"MAIN",16},{"BREAK",8},
    {"BUILD",8},{"DROP",16},{"DEVELOP",8},{"OUTRO",8},
  },
  jack_acid={
    {"INTRO",8},{"GROOVE",16},{"MAIN",16},{"BREAK",8},
    {"BUILD",8},{"DROP",16},{"DEVELOP",8},{"OUTRO",16},
  },
  deep_acid={
    {"INTRO",16},{"GROOVE",24},{"MAIN",16},{"BREAK",16},
    {"BUILD",8},{"DROP",8},{"DEVELOP",8},
  },
  rave_acid={
    {"INTRO",8},{"GROOVE",16},{"MAIN",8},{"BREAK",8},
    {"BUILD",8},{"DROP",16},{"BREAK",8},{"DROP",16},{"DEVELOP",8},
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

local function acid_envelope(archetype,name)
  local envelope={
    INTRO={kick=0.86,percussion=0.26,bass=0.22,chords=0.06,mono=0.32,samples=0.08,fx=0.10},
    GROOVE={kick=1,percussion=0.66,bass=0.78,chords=0.12,mono=0.48,samples=0.18,fx=0.10},
    MAIN={kick=1,percussion=0.84,bass=0.90,chords=0.18,mono=0.64,samples=0.24,fx=0.16},
    BREAK={kick=0.08,percussion=0.20,bass=0.24,chords=0.10,mono=0.56,samples=0.22,fx=0.50},
    BUILD={kick=0.62,percussion=0.72,bass=0.68,chords=0.14,mono=0.82,samples=0.38,fx=0.92},
    DROP={kick=1,percussion=1,bass=1,chords=0.20,mono=0.94,samples=0.34,fx=0.28},
    DEVELOP={kick=0.96,percussion=0.76,bass=0.82,chords=0.12,mono=0.58,samples=0.18,fx=0.16},
    OUTRO={kick=1,percussion=0.52,bass=0.42,chords=0.06,mono=0.16,samples=0.08,fx=0.12},
    MIX={kick=1,percussion=0.58,bass=0.38,chords=0.10,mono=0.18,samples=0.10,fx=0.20},
  }
  local result={}
  for role,value in pairs(envelope[name] or envelope.GROOVE) do result[role]=value end
  if archetype=="deep_acid" then
    result.percussion=math.max(0.12,result.percussion-0.10)
    result.samples=math.max(0.06,result.samples-0.08)
    result.fx=math.min(1,result.fx+0.08)
  elseif archetype=="rave_acid" then
    result.chords=math.min(0.42,result.chords+0.12)
    result.samples=math.min(0.46,result.samples+0.10)
  elseif archetype=="jack_acid" then
    result.percussion=math.min(1,result.percussion+0.06)
  end
  return result
end

-- Funky House stem energy envelopes.  Samples (disco loops, guitar chops,
-- vocal hooks) are deliberately higher than in the generic template throughout,
-- the INTRO is sample-led (very low bass / no mono), the BREAK exposes vocal
-- and instrumental material, the BUILD emphasises filter FX, and the OUTRO
-- thins to kick + percussion only.
local function funky_envelope(archetype, name)
  local envelope = {
    INTRO   = {kick=0.65,percussion=0.42,bass=0,    chords=0.10,mono=0,    samples=0.52,fx=0.18},
    GROOVE  = {kick=1,   percussion=0.72,bass=0.82, chords=0.28,mono=0.15, samples=0.45,fx=0.10},
    MAIN    = {kick=1,   percussion=0.90,bass=0.92, chords=0.72,mono=0.58, samples=0.68,fx=0.18},
    BREAK   = {kick=0.08,percussion=0.35,bass=0.15, chords=0.75,mono=0.72, samples=0.88,fx=0.52},
    BUILD   = {kick=0.72,percussion=0.92,bass=0.48, chords=0.55,mono=0.75, samples=0.65,fx=0.94},
    DROP    = {kick=1,   percussion=1,   bass=1,    chords=0.78,mono=0.88, samples=0.78,fx=0.38},
    DEVELOP = {kick=1,   percussion=0.82,bass=0.88, chords=0.52,mono=0.42, samples=0.55,fx=0.18},
    OUTRO   = {kick=0.92,percussion=0.78,bass=0.18, chords=0.06,mono=0,    samples=0.22,fx=0.10},
    MIX     = {kick=1,   percussion=0.72,bass=0.58, chords=0.28,mono=0.20, samples=0.38,fx=0.30},
  }
  local result = {}
  for role, value in pairs(envelope[name] or envelope.GROOVE) do result[role] = value end
  -- Archetype-specific emphasis on top of the shared base.
  if archetype == "filtered_disco" then
    -- Sample-led throughout; extra filter loop presence in INTRO and BREAK.
    if name == "INTRO"  then result.samples = math.min(1, result.samples + 0.10) end
    if name == "BREAK"  then result.samples = math.min(1, result.samples + 0.08) end
  elseif archetype == "live_clavinet" then
    -- Clavinet mono lead is prominent in MAIN and DEVELOP sections.
    if name == "MAIN"   then result.mono = math.min(1, result.mono + 0.15) end
    if name == "DEVELOP" then result.mono = math.min(1, result.mono + 0.10) end
  elseif archetype == "brass_vocal" then
    -- Brass stabs and vocal chops are featured in MAIN and BREAK.
    if name == "MAIN"   then result.samples = math.min(1, result.samples + 0.08) end
    if name == "BREAK"  then result.samples = math.min(1, result.samples + 0.10) end
  elseif archetype == "french_touch" then
    -- Filter FX are exaggerated in BUILD sections; chords pumped in DROP.
    if name == "BUILD"  then result.fx = math.min(1, result.fx + 0.06) end
    if name == "DROP"   then result.chords = math.min(1, result.chords + 0.10) end
  end
  return result
end

local function electro_envelope(archetype, name)
  local envelope = {
    INTRO   = {kick=0.86,percussion=0.42,bass=0,    chords=0.08,mono=0.10,samples=0.12,fx=0.12},
    GROOVE  = {kick=1,   percussion=0.76,bass=0.84, chords=0.18,mono=0.22,samples=0.22,fx=0.10},
    MAIN    = {kick=1,   percussion=0.92,bass=0.94, chords=0.38,mono=0.56,samples=0.34,fx=0.16},
    BREAK   = {kick=0.10,percussion=0.26,bass=0.18, chords=0.54,mono=0.76,samples=0.62,fx=0.52},
    BUILD   = {kick=0.68,percussion=0.86,bass=0.52, chords=0.28,mono=0.80,samples=0.56,fx=0.92},
    DROP    = {kick=1,   percussion=1,   bass=1,    chords=0.34,mono=0.82,samples=0.46,fx=0.32},
    DEVELOP = {kick=1,   percussion=0.82,bass=0.90, chords=0.26,mono=0.48,samples=0.30,fx=0.18},
    OUTRO   = {kick=1,   percussion=0.72,bass=0.32, chords=0.06,mono=0.12,samples=0.10,fx=0.10},
    MIX     = {kick=1,   percussion=0.68,bass=0.58, chords=0.14,mono=0.22,samples=0.16,fx=0.24},
  }
  local result = {}
  for role, value in pairs(envelope[name] or envelope.GROOVE) do result[role] = value end
  if archetype == "classic_808" then
    if name == "GROOVE" then result.percussion = math.min(1, result.percussion + 0.08) end
    if name == "BREAK" then result.samples = math.max(0.20, result.samples - 0.14) end
  elseif archetype == "detroit_electro" then
    if name == "MAIN" or name == "BREAK" then
      result.chords = math.min(0.68, result.chords + 0.14)
    end
    if name == "BREAK" then result.fx = math.min(1, result.fx + 0.10) end
  elseif archetype == "vocoder_robot" then
    if name == "BREAK" or name == "BUILD" then
      result.samples = math.min(1, result.samples + 0.14)
      result.mono = math.min(1, result.mono + 0.10)
    end
  elseif archetype == "acid_electro" then
    result.chords = math.max(0, result.chords - 0.12)
    if name == "DROP" or name == "BUILD" then result.fx = math.min(1, result.fx + 0.08) end
  end
  return result
end

local MELODIC_GRAMMARS = {
  melodic_techno = {
    -- Deep evolving techno: long intro and groove establish the hypnotic
    -- identity; an extended drop carries the full melodic arc.
    {"INTRO",16},{"GROOVE",16},{"MAIN",16},{"BREAK",8},
    {"BUILD",8},{"DROP",24},{"DEVELOP",8},
  },
  melodic_house = {
    -- House hook structure: DJ-friendly intro, hook A/B alternation,
    -- chord breakdown, and an atmospheric outro for mixing out.
    {"INTRO",8},{"GROOVE",16},{"MAIN",16},{"BREAK",8},
    {"BUILD",8},{"DROP",16},{"DEVELOP",16},{"OUTRO",8},
  },
  cinematic_prog = {
    -- Cinematic slow-burn: extended groove and emotional breakdown let
    -- strings and pads breathe before the single full-energy climax.
    {"INTRO",16},{"GROOVE",24},{"MAIN",16},{"BREAK",16},
    {"BUILD",8},{"DROP",16},
  },
  vocal_melodic = {
    -- Vocal hook structure: hook reveal in MAIN, vocal spotlight in BREAK,
    -- re-drop, development, and DJ-friendly outro.
    {"INTRO",8},{"GROOVE",16},{"MAIN",16},{"BREAK",8},
    {"BUILD",8},{"DROP",16},{"DEVELOP",16},{"OUTRO",8},
  },
}

-- Melodic stem energy envelopes.  The lead melody (mono) is the primary
-- hook so it sits higher than in the generic template throughout; chords
-- (pads/strings) support without overpowering; the break spotlights the
-- melodic lead; the build peaks the FX riser; the intro has no bass so
-- it is DJ-friendly.
local function melodic_envelope(archetype, name)
  local envelope = {
    INTRO  = {kick=0.65,percussion=0.32,bass=0,    chords=0.22,mono=0.12,samples=0.10,fx=0.22},
    GROOVE = {kick=1,   percussion=0.65,bass=0.72, chords=0.38,mono=0.32,samples=0.18,fx=0.12},
    MAIN   = {kick=1,   percussion=0.82,bass=0.88, chords=0.60,mono=0.78,samples=0.42,fx=0.18},
    BREAK  = {kick=0.06,percussion=0.15,bass=0.10, chords=0.75,mono=0.90,samples=0.52,fx=0.68},
    BUILD  = {kick=0.62,percussion=0.80,bass=0.38, chords=0.52,mono=0.92,samples=0.55,fx=0.96},
    DROP   = {kick=1,   percussion=0.95,bass=0.95, chords=0.65,mono=0.95,samples=0.62,fx=0.36},
    DEVELOP= {kick=1,   percussion=0.70,bass=0.80, chords=0.42,mono=0.60,samples=0.32,fx=0.16},
    OUTRO  = {kick=0.88,percussion=0.52,bass=0.25, chords=0.15,mono=0.06,samples=0.10,fx=0.10},
    MIX    = {kick=1,   percussion=0.62,bass=0.55, chords=0.30,mono=0.25,samples=0.20,fx=0.30},
  }
  local result = {}
  for role, value in pairs(envelope[name] or envelope.GROOVE) do result[role] = value end
  if archetype == "melodic_techno" then
    -- Techno: suppress chords in MAIN, amplify mono in BREAK, peak FX in BUILD.
    if name == "MAIN"  then result.chords = math.max(0.38, result.chords - 0.14) end
    if name == "BREAK" then result.mono   = math.min(1,    result.mono   + 0.06) end
    if name == "BUILD" then result.fx     = math.min(1,    result.fx     + 0.04) end
  elseif archetype == "melodic_house" then
    -- House: chords more prominent in MAIN and DROP; groove samples up.
    if name == "MAIN"   then result.chords  = math.min(1, result.chords  + 0.10) end
    if name == "BREAK"  then result.samples = math.min(1, result.samples + 0.08) end
    if name == "DROP"   then result.chords  = math.min(1, result.chords  + 0.10) end
  elseif archetype == "cinematic_prog" then
    -- Cinematic: strings/pads prominent in BREAK; extra mono depth in DROP.
    if name == "BREAK" then result.chords = math.min(1, result.chords + 0.10) end
    if name == "BREAK" then result.mono   = math.min(1, result.mono   + 0.05) end
    if name == "DROP"  then result.mono   = math.min(1, result.mono   + 0.05) end
  elseif archetype == "vocal_melodic" then
    -- Vocal: sample (vocal) energy elevated throughout; BREAK exposes vocal.
    if name == "GROOVE" then result.samples = math.min(1, result.samples + 0.10) end
    if name == "MAIN"   then result.samples = math.min(1, result.samples + 0.12) end
    if name == "BREAK"  then result.samples = math.min(1, result.samples + 0.18) end
  end
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
  local is_melodic=identity.genre=="MELODIC"
  local grammar=(identity.genre=="ACID" and ACID_GRAMMARS[identity.archetype]) or
    (identity.genre=="FUNKY" and FUNKY_GRAMMARS[identity.archetype]) or
    (identity.genre=="ELECTRO" and ELECTRO_GRAMMARS[identity.archetype]) or
    (is_melodic and MELODIC_GRAMMARS[identity.archetype]) or
    assert(GRAMMARS[family],"unknown arrangement family")
  local rng=rng_new(identity.stream_seeds.arrangement)
  local sections={}
  local events={}
  local occurrences={}
  local first=1
  for index,item in ipairs(grammar) do
    local name,length=item[1],item[2]
    occurrences[name]=(occurrences[name] or 0)+1
    local is_funky=identity.genre=="FUNKY"
    local is_electro=identity.genre=="ELECTRO"
    local section={
      name=name, first=first, last=first+length-1, length=length,
      phrase_bars=(identity.genre=="ACID" and ((name=="BREAK" or name=="BUILD") and 4 or 8)) or
        (is_funky and ((name=="BREAK" or name=="BUILD") and 4 or 8)) or
        (is_electro and ((name=="BREAK" or name=="BUILD") and 4 or 8)) or
        (is_melodic and ((name=="BREAK" or name=="BUILD") and 4 or 8)) or
        ((length>=16 and rng:float()>0.48) and 8 or 4),
      energy=(identity.genre=="ACID" and acid_envelope(identity.archetype,name)) or
        (is_funky and funky_envelope(identity.archetype,name)) or
        (is_electro and electro_envelope(identity.archetype,name)) or
        (is_melodic and melodic_envelope(identity.archetype,name)) or
        copy_envelope(name), index=index, occurrence=occurrences[name],
    }
    sections[#sections+1]=section
    local event=section_event(name,occurrences[name])
    if event then events[first]=event end
    first=section.last+1
  end
  assert(first==97,"arrangement grammar must fill 96 performance bars")
  sections[#sections+1]={
    name="MIX",first=97,last=128,length=32,phrase_bars=8,
    energy=(identity.genre=="ACID" and acid_envelope(identity.archetype,"MIX")) or
      (identity.genre=="FUNKY" and funky_envelope(identity.archetype,"MIX")) or
      (identity.genre=="ELECTRO" and electro_envelope(identity.archetype,"MIX")) or
      (identity.genre=="MELODIC" and melodic_envelope(identity.archetype,"MIX")) or
      copy_envelope("MIX"),index=#sections+1,occurrence=1,
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
