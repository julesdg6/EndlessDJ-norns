package.path="./?.lua;./lib/?.lua;"..package.path

local identity=require("song_identity")
local transition=require("transition_engine")

local genre_pairs={
  {"HOUSE","TECHNO","percussion_overlay"},
  {"TWO_STEP","DNB","bass_swap"},
  {"DEEP","HARDTECHNO","clean_cut"},
  {"TRANCE","DUBSTEP","fx_exit"},
  {"JUNGLE","LIQUID","bass_swap"},
  {"AFRO","ELECTRO","percussion_overlay"},
  {"HARDSTYLE","MINIMAL","clean_cut"},
}

local function make(seed,deck,genre,root)
  local song=identity.new{seed=seed,deck=deck,genre=genre}
  song.root_pitch_class=root or seed%12
  return song
end

local function encode(value)
  if type(value)~="table" then return tostring(value) end
  local keys={}
  for key in pairs(value) do keys[#keys+1]=key end
  table.sort(keys,function(a,b)return tostring(a)<tostring(b) end)
  local result={}
  for _,key in ipairs(keys) do result[#result+1]=tostring(key).."="..encode(value[key]) end
  return "{"..table.concat(result,",").."}"
end

for index,pair in ipairs(genre_pairs) do
  local outgoing=make(1000+index,"A",pair[1],index%12)
  local incoming=make(8000+index,"B",pair[2],(index+2)%12)
  local plan=transition.new(outgoing,incoming,{mode="stem",energy=0.7})
  local replay=transition.new(outgoing,incoming,{mode="stem",energy=0.7})
  assert(plan.strategy==pair[3],pair[1]..">"..pair[2].." chose "..plan.strategy)
  assert(encode(plan)==encode(replay),"transition plan must replay deterministically")
  local valid,reason=transition.validate(plan)
  assert(valid,reason)
  assert(plan.outgoing_seed==outgoing.seed and plan.incoming_seed==incoming.seed,
    "transition must preserve independent deck identities")
  for bar=1,32 do
    local state=transition.levels(plan,bar)
    for _,stem in ipairs({"kick","bass"}) do
      assert(not (state.outgoing[stem]>0 and state.incoming[stem]>0),
        "unintended "..stem.." overlap at bar "..bar)
    end
  end
end

for _,mode in ipairs(transition.MODES) do
  local outgoing=make(41,"A","HOUSE",0)
  local incoming=make(99,"B","TECHNO",2)
  local plan=transition.new(outgoing,incoming,{mode=mode})
  assert(plan.mode==mode,"mode not stored")
  local valid,reason=transition.validate(plan)
  assert(valid,reason)
  for _,bar in ipairs({1,8,9,16,17,24,25,32}) do
    assert(transition.stage(plan,bar),"missing phrase stage")
  end
  if mode=="classic" then
    for bar=1,32 do
      local state=transition.levels(plan,bar)
      assert(state.outgoing.kick+state.incoming.kick<=1.0001,
        "classic low end must remain bounded")
      assert(state.outgoing.bass+state.incoming.bass<=1.0001,
        "classic bass must remain bounded")
    end
  end
end

do
  local outgoing=make(111,"A","HOUSE",0)
  local incoming=make(222,"B","TECHNO",1)
  local plan=transition.new(outgoing,incoming,{mode="producer"})
  local before=transition.preview(plan,1)
  assert(#before>0,"next phrase preview must describe stem changes")
  assert(transition.override(plan,"chords","incoming"),"manual stem override failed")
  assert(transition.ownership(plan,1,"chords")=="incoming","override not applied")
  local ok=transition.override(plan,"kick","both")
  assert(not ok,"manual double-kick override must be rejected")
  transition.clear_override(plan,"chords")
  transition.cancel(plan)
  assert(transition.stage(plan,1)==nil,"cancelled transition remained active")
  local state=transition.levels(plan,1)
  assert(state.outgoing.kick==1 and state.incoming.kick==0,"cancel fallback unsafe")
end

do
  local outgoing=make(551,"A","HOUSE",0)
  local incoming=make(552,"B","TECHNO",6)
  local plan=transition.new(outgoing,incoming,{mode="stem"})
  assert(plan.warning=="HARM","harmonic warning missing")
  assert(plan.strategy=="clean_cut","unsafe harmonic pair must simplify")
end

print("All transition engine checks passed")
