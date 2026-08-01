local SampleLibrary={}

SampleLibrary.factory_risers={}
SampleLibrary.factory_roles={}
SampleLibrary.catalog={}

SampleLibrary.ROLES={
  "perc_accent","alt_perc","short_fill","long_fill",
  "impact","riser","vocal_stab","drop_accent",
}

local GENRE_TAGS={
  HOUSE={"club","classic","soulful"}, FUNKY={"organic","soulful","classic"},
  DIRTY={"aggressive","digital","rave"}, TECHNO={"dark","digital","club"},
  GARAGE4={"soulful","club","rave"}, TWO_STEP={"broken","dark","soulful"},
  BREAKS={"broken","organic","rave"}, DUBSTEP={"dark","digital","heavy"},
  DEEP={"soulful","organic","clean"}, ACID={"rave","digital","classic"},
  TRANCE={"rave","clean","tonal"}, PROG={"tonal","clean","organic"},
  JUNGLE={"broken","rave","organic"}, DNB={"broken","dark","digital"},
  LIQUID={"soulful","clean","tonal"}, HARDTECHNO={"aggressive","dark","digital"},
  ELECTRO={"digital","broken","classic"}, JUKE={"broken","soulful","digital"},
  AFRO={"organic","soulful","clean"}, MINIMAL={"clean","dark","club"},
  MELODIC={"tonal","clean","soulful"}, SPEED={"rave","broken","aggressive"},
  BASSLINE={"rave","dark","club"}, HARDSTYLE={"aggressive","rave","tonal"},
}

local VARIANTS={
  {tags={"classic","club","clean"},energy=0.45},
  {tags={"organic","soulful","clean"},energy=0.55},
  {tags={"dark","digital","broken"},energy=0.72},
  {tags={"rave","aggressive","heavy"},energy=0.9},
}

local RISER_FAMILIES={
  {first=1,last=8,tags={"clean","club","air"},energy=0.55,tonal=false},
  {first=9,last=16,tags={"tonal","soulful","clean"},energy=0.68,tonal=true,key=0},
  {first=17,last=24,tags={"digital","dark","rave"},energy=0.8,tonal=false},
  {first=25,last=32,tags={"heavy","aggressive","rave"},energy=0.95,tonal=true,key=0},
}

local function scan(path)
  local files={}
  if not util or not util.scandir then return files end
  for _,name in ipairs(util.scandir(path) or {}) do
    if type(name)=="string" and name:lower():match("%.wav$") then files[#files+1]=path..name end
  end
  table.sort(files)
  return files
end

local function copy(values)
  local result={}
  for _,value in ipairs(values or {}) do result[#result+1]=value end
  return result
end

local function has(values,wanted)
  for _,value in ipairs(values or {}) do if value==wanted then return true end end
  return false
end

local function riser_family(index)
  for _,family in ipairs(RISER_FAMILIES) do
    if index>=family.first and index<=family.last then return family end
  end
  return RISER_FAMILIES[1]
end

local function add_entry(entry)
  entry.origin="Endless DJ procedural factory generator"
  entry.license="repository license"
  entry.bpm=entry.bpm or nil
  entry.length=entry.length or "one_shot"
  SampleLibrary.catalog[#SampleLibrary.catalog+1]=entry
  return entry
end

function SampleLibrary.scan()
  SampleLibrary.factory_risers=scan(_path.code.."EndlessDJ/samples/factory/risers/")
  SampleLibrary.factory_roles={}
  SampleLibrary.catalog={}
  for index,path in ipairs(SampleLibrary.factory_risers) do
    local family=riser_family(index)
    add_entry({
      id="riser_"..string.format("%02d",index),role="riser",slot=index+16,path=path,
      tags=copy(family.tags),energy=family.energy,tonal=family.tonal,key=family.key,
      processing={"filter","pitch","reverse"},
    })
  end
  local next_slot=49
  for _,role in ipairs(SampleLibrary.ROLES) do
    if role~="riser" then
      local paths=scan(_path.code.."EndlessDJ/samples/factory/oneshots/"..role.."/")
      SampleLibrary.factory_roles[role]={}
      for index,path in ipairs(paths) do
        local variant=VARIANTS[((index-1)%#VARIANTS)+1]
        local entry=add_entry({
          id=role.."_"..string.format("%02d",index),role=role,slot=next_slot,path=path,
          tags=copy(variant.tags),energy=variant.energy,tonal=false,
          vocal_occupancy=(role=="vocal_stab") and "hook" or "none",
          processing={"filter","pitch","reverse","choke"},
        })
        SampleLibrary.factory_roles[role][#SampleLibrary.factory_roles[role]+1]=entry
        next_slot=next_slot+1
      end
    end
  end
  return SampleLibrary.factory_risers
end

function SampleLibrary.load_factory(internal_engine)
  local files=SampleLibrary.scan()
  for index,path in ipairs(files) do
    local slot=index+16
    if slot>48 then break end
    internal_engine.load_sample(slot,path)
  end
  local one_shots=0
  for _,role in ipairs(SampleLibrary.ROLES) do
    for _,sample in ipairs(SampleLibrary.factory_roles[role] or {}) do
      internal_engine.load_sample(sample.slot,sample.path)
      one_shots=one_shots+1
    end
  end
  print("Endless DJ: loaded "..#files.." factory risers and "..one_shots.." role one-shots")
  return #files,one_shots
end

local function candidates(role)
  local result={}
  for _,entry in ipairs(SampleLibrary.catalog) do
    if entry.role==role then result[#result+1]=entry end
  end
  return result
end

local function compatibility_score(entry,identity,target_energy)
  local value=0
  for _,tag in ipairs(GENRE_TAGS[identity.genre] or {"club"}) do
    if has(entry.tags,tag) then value=value+4 end
  end
  value=value-math.abs((entry.energy or 0.5)-target_energy)*3
  return value
end

local function select_entry(role,identity,target_energy,offset,excluded_slot)
  local ranked={}
  for _,entry in ipairs(candidates(role)) do
    if entry.slot~=excluded_slot then ranked[#ranked+1]={entry=entry,score=compatibility_score(entry,identity,target_energy)} end
  end
  table.sort(ranked,function(a,b)
    if a.score==b.score then return a.entry.slot<b.entry.slot end
    return a.score>b.score
  end)
  if #ranked==0 then return nil end
  local pool=math.min(3,#ranked)
  local seed=(identity.stream_seeds.samples or identity.seed or 1)+(offset or 0)*97
  return ranked[((seed-1)%pool)+1].entry
end

local function playback(entry,identity,variant)
  if not entry then return nil end
  local rate=1
  if entry.tonal and entry.key~=nil then
    local root=(identity.root_pitch_class or 0)%12
    local semitones=((root-entry.key+6)%12)-6
    rate=2^(semitones/12)
  end
  return {
    slot=entry.slot,id=entry.id,role=entry.role,tags=copy(entry.tags),
    energy=entry.energy,tonal=entry.tonal,key=entry.key,rate=rate,
    level=(variant=="alternate") and 0.86 or 0.92,
    pan=(variant=="alternate") and 0.12 or -0.08,
    origin=entry.origin,license=entry.license,vocal_occupancy=entry.vocal_occupancy,
  }
end

function SampleLibrary.plan_for_identity(identity)
  assert(identity and identity.genre and identity.stream_seeds,"song identity required")
  if #SampleLibrary.catalog==0 then SampleLibrary.scan() end
  local plan={schema_version=1,genre=identity.genre,archetype=identity.archetype,roles={}}
  for index,role in ipairs(SampleLibrary.ROLES) do
    local target=0.38+((identity.stream_seeds.samples+index*31)%55)/100
    local primary=select_entry(role,identity,target,index)
    local alternate=select_entry(role,identity,math.min(1,target+0.16),index+17,primary and primary.slot)
    plan.roles[role]={
      primary=playback(primary,identity,"primary"),
      alternate=playback(alternate or primary,identity,"alternate"),
    }
  end
  return plan
end

function SampleLibrary.selection_for(plan,role,variant)
  local choices=plan and plan.roles and plan.roles[role]
  if not choices then return nil end
  return choices[variant=="alternate" and "alternate" or "primary"]
end

function SampleLibrary.riser_for_seed(seed)
  local count=#SampleLibrary.factory_risers
  if count==0 then return nil end
  return ((math.max(1,seed or 1)-1)%count)+17
end

function SampleLibrary.role_for_seed(role,seed)
  if role=="riser" then return SampleLibrary.riser_for_seed(seed) end
  local choices=SampleLibrary.factory_roles[role] or {}
  if #choices==0 then return nil end
  return choices[((math.max(1,seed or 1)-1)%#choices)+1].slot
end

function SampleLibrary.validate_plan(plan)
  if type(plan)~="table" or plan.schema_version~=1 then return false,"unsupported sample plan" end
  for _,role in ipairs(SampleLibrary.ROLES) do
    local choices=plan.roles and plan.roles[role]
    if not choices or not choices.primary then return false,"missing sample role "..role end
    for _,variant in ipairs({"primary","alternate"}) do
      local selection=choices[variant]
      if not selection or type(selection.slot)~="number" then return false,"invalid sample selection" end
      if not selection.origin or not selection.license then return false,"missing sample provenance" end
    end
  end
  return true
end

return SampleLibrary
