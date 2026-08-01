local identity=dofile("lib/song_identity.lua")
local arrangement=dofile("lib/arrangement_engine.lua")

local function signature(plan)
  local parts={plan.genre,plan.archetype,plan.family}
  for _,section in ipairs(plan.sections) do
    parts[#parts+1]=table.concat({section.name,section.first,section.last,section.phrase_bars},":")
    for _,role in ipairs({"kick","percussion","bass","chords","mono","samples","fx"}) do
      parts[#parts+1]=role..":"..string.format("%.2f",section.energy[role])
    end
  end
  for bar,event in pairs(plan.events) do parts[#parts+1]=bar..":"..event end
  table.sort(parts)
  return table.concat(parts,"|")
end

local families={}
for seed=1,512 do
  for _,genre in ipairs({"HOUSE","TWO_STEP","TECHNO","AFRO","HARDSTYLE"}) do
    local song=identity.new{seed=seed,deck="A",genre=genre}
    local a=arrangement.new(song)
    local b=arrangement.new(song)
    assert(arrangement.validate(a))
    assert(signature(a)==signature(b),genre.." arrangement is not deterministic")
    assert(a.performance_bars==96 and a.total_bars==128)
    assert(arrangement.section_name(a,97)=="MIX")
    families[a.family]=true
    for bar=1,128 do
      local section=arrangement.section(a,bar)
      local phrase=arrangement.phrase(a,bar)
      assert(section and phrase,"bar is not covered by phrase metadata")
      assert(phrase.bar>=1 and phrase.bar<=phrase.length)
      for _,role in ipairs({"kick","percussion","bass","chords","mono","samples","fx"}) do
        local level=arrangement.role_level(a,bar,role)
        assert(level>=0 and level<=1,"unsafe role envelope")
      end
    end
  end
end
for _,family in ipairs({"club_linear","hook_ab","double_drop","slow_burn"}) do
  assert(families[family],family.." arrangement was never selected")
end

local double
for seed=1,512 do
  local candidate=arrangement.new(identity.new{seed=seed,deck="A",genre="HARDSTYLE"})
  if candidate.family=="double_drop" then double=candidate break end
end
assert(double,"double-drop fixture missing")
local impacts={}
for bar,event in pairs(double.events) do
  if event:find("impact",1,true) then impacts[#impacts+1]=bar end
end
table.sort(impacts)
assert(#impacts==2 and impacts[1]~=impacts[2],"double drop lacks distinct impacts")
assert(arrangement.role_level(double,1,"bass")==0,"DJ intro should not begin with full bass")
assert(arrangement.role_level(double,impacts[1],"kick")==1,"drop must own the kick")
assert(arrangement.gate(double,4,3,"chords",0.5)==arrangement.gate(double,4,3,"chords",0.5),
  "stem gate is not deterministic")

local a=arrangement.new(identity.new{seed=42,deck="A",genre="HOUSE"})
local b=arrangement.new(identity.new{seed=43,deck="B",genre="HOUSE"})
assert(signature(a)~=signature(b),"different records collapsed to one arrangement")
print("All arrangement engine checks passed")
