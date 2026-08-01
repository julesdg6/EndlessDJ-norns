local identity=dofile("lib/song_identity.lua")
local groove=dofile("lib/groove_engine.lua")
local function signature(plan)
  local parts={plan.genre,plan.archetype,plan.family,string.format("%.4f",plan.swing)}
  for bar=1,plan.phrase_bars do for _,voice in ipairs({"kick","snare","clap","hats","ohats","tom"}) do for step=1,16 do
    local event=groove.event(plan,bar,voice,step)
    if event then parts[#parts+1]=table.concat({bar,voice,step,event.velocity,string.format("%.3f",event.offset)},":") end
  end end end
  return table.concat(parts,"|")
end
for _,genre in ipairs({"HOUSE","TWO_STEP","BREAKS","DUBSTEP","DNB","AFRO","HARDSTYLE"}) do
  local a=groove.new(identity.new{seed=42042,deck="A",genre=genre})
  local b=groove.new(identity.new{seed=42042,deck="A",genre=genre})
  assert(groove.validate(a)); assert(signature(a)==signature(b),genre.." groove is not deterministic"); assert(#a.bars==4)
end
local house=groove.new(identity.new{seed=1,deck="A",genre="HOUSE"})
local two_step=groove.new(identity.new{seed=1,deck="A",genre="TWO_STEP"})
assert(signature(house)~=signature(two_step),"contrasting genres collapsed to one groove")
assert(groove.is_fill_step(house,4,16)); assert(not groove.is_fill_step(house,3,16))
print("All groove engine checks passed")
