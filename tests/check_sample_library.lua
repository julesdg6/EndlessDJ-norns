_path={code=""}
util={}
function util.scandir(path)
  local result={}
  path=path:gsub("^EndlessDJ/","")
  local pipe=assert(io.popen("ls -1 '"..path.."' | sort"))
  for name in pipe:lines() do result[#result+1]=name end
  pipe:close()
  return result
end

local identity=dofile("lib/song_identity.lua")
local library=dofile("lib/sample_library.lua")
library.scan()
assert(#library.catalog==92,"sample catalog must describe all 92 factory WAVs")
assert(#library.factory_risers==64,"factory riser catalog is incomplete")

local provenance={}
for _,entry in ipairs(library.catalog) do
  assert(entry.id and entry.role and entry.slot and entry.path,"incomplete sample metadata")
  assert(entry.energy>=0 and entry.energy<=1,"invalid sample energy")
  assert(type(entry.tags)=="table" and #entry.tags>0,"sample lacks affinity tags")
  assert(entry.origin and entry.license,"sample lacks licensing provenance")
  assert(entry.duration and entry.duration>0,"sample lacks WAV duration metadata")
  provenance[entry.origin..":"..entry.license]=true
end

assert(next(provenance),"sample provenance metadata is empty")

local function make(seed,genre,root)
  local song=identity.new{seed=seed,deck="A",genre=genre}
  song.root_pitch_class=root or 0
  return library.plan_for_identity(song)
end
local timed=library.sync_settings(make(21,"HOUSE",0).roles.riser.primary,120,4)
assert(math.abs((timed.duration/math.abs(timed.rate))-2)<0.0001,
  "riser does not span exactly one 120 BPM bar")
local short=library.sync_settings(make(21,"HOUSE",0).roles.short_fill.primary,120,1)
assert(math.abs((short.duration/math.abs(short.rate))-0.5)<0.0001,
  "short fill does not span exactly one beat")
local function signature(plan)
  local parts={plan.genre,plan.archetype}
  for _,role in ipairs(library.ROLES) do
    local choices=plan.roles[role]
    parts[#parts+1]=role..":"..choices.primary.id..":"..choices.alternate.id
  end
  return table.concat(parts,"|")
end

for _,genre in ipairs({"HOUSE","TWO_STEP","TECHNO","AFRO","HARDSTYLE"}) do
  local a=make(42042,genre,7)
  local b=make(42042,genre,7)
  assert(library.validate_plan(a))
  assert(signature(a)==signature(b),genre.." sample plan is not deterministic")
  for _,role in ipairs(library.ROLES) do
    local choices=a.roles[role]
    assert(choices.primary.slot~=choices.alternate.slot,"A/B sample choices collapsed")
    for _,variant in ipairs({"primary","alternate"}) do
      local selection=choices[variant]
      assert(selection.rate>=0.7 and selection.rate<=1.42,"unsafe tonal pitch rate")
    end
  end
end

local distinct={}
for seed=1,128 do distinct[signature(make(seed,"HOUSE",seed%12))]=true end
local count=0
for _ in pairs(distinct) do count=count+1 end
assert(count>=24,"sample identities lack seed diversity")
assert(signature(make(9,"AFRO",0))~=signature(make(9,"HARDSTYLE",0)),
  "genre affinity did not affect the sample palette")

assert(library.selection_for({roles={}},"riser","primary")==nil,
  "missing sample roles must fail safely")
print("All sample library checks passed")
