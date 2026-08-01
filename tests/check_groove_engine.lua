local identity=dofile("lib/song_identity.lua")
local groove=dofile("lib/groove_engine.lua")
local function signature(plan)
  local parts={plan.genre,plan.archetype,plan.family,string.format("%.4f",plan.swing)}
  for bar=1,plan.phrase_bars do for _,voice in ipairs({"kick","snare","clap","hats","ohats","tom"}) do for step=1,16 do
    local event=groove.event(plan,bar,voice,step)
    if event then
      local values={bar,voice,step,event.velocity,string.format("%.3f",event.offset)}
      parts[#parts+1]=table.concat(values,":")
    end
  end end end
  return table.concat(parts,"|")
end
for _,genre in ipairs({"HOUSE","TWO_STEP","BREAKS","DUBSTEP","DNB","AFRO","HARDSTYLE"}) do
  local a=groove.new(identity.new{seed=42042,deck="A",genre=genre})
  local b=groove.new(identity.new{seed=42042,deck="A",genre=genre})
  assert(groove.validate(a))
  assert(signature(a)==signature(b),genre.." groove is not deterministic")
  assert(a.phrase_bars==2 or a.phrase_bars==4 or a.phrase_bars==8 or a.phrase_bars==16)
  assert(#a.bars==a.phrase_bars)
end
local house=groove.new(identity.new{seed=1,deck="A",genre="HOUSE"})
local two_step=groove.new(identity.new{seed=1,deck="A",genre="TWO_STEP"})
assert(signature(house)~=signature(two_step),"contrasting genres collapsed to one groove")
local lengths={}
for seed=1,512 do
  for _,genre in ipairs({"TWO_STEP","HOUSE","TECHNO"}) do
    local plan=groove.new(identity.new{seed=seed,deck="A",genre=genre})
    lengths[plan.phrase_bars]=true
  end
end
for _,length in ipairs({2,4,8,16}) do assert(lengths[length],"phrase length "..length.." was never selected") end

local fill_count=0
for step=1,16 do
  local event=groove.fill_event(house,house.phrase_bars,step)
  if event then
    fill_count=fill_count+1
    assert(event.voice and event.velocity,"fill event lacks musical role data")
    assert(not groove.fill_event(house,house.phrase_bars-1,step),"fill leaked before phrase boundary")
  end
end
assert(fill_count>=2,"phrase fill is empty")

local poly
for seed=1,256 do
  local candidate=groove.new(identity.new{seed=seed,deck="A",genre="AFRO"})
  if candidate.family=="polymetric" then poly=candidate break end
end
assert(poly and poly.cycles.hats==3 and poly.cycles.tom==5,"polymetric cycles missing")
assert(signature(poly)~=signature(groove.new(identity.new{seed=1,deck="A",genre="HOUSE"})),
  "polymetric groove collapsed to straight 4x4")
print("All groove engine checks passed")
