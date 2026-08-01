-- Central compatibility registry for every generated genre/archetype.
-- The compact declarations below are musical contracts, not patches: all
-- generators consume the same allowed kit, feel, bass, chord, mono, harmony,
-- arrangement and sample-tag choices for a complete record.
local M={}

local function split(value)
  local result={}
  for item in tostring(value):gmatch("[^|]+") do result[#result+1]=item end
  return result
end

local function p(kit,groove,bass,chord,mono,harmony,arrangement,tags,hook)
  return {kits=split(kit),grooves=split(groove),bass=split(bass),
    chords=split(chord),mono=split(mono),harmony=split(harmony),
    arrangements=split(arrangement),sample_tags=split(tags),hook=hook}
end

local P={
HOUSE={
 classic_organ=p(
    "909","swung|straight","organ|analog",
    "organ","analog|organ","seventh_ninth",
    "club_linear","classic|soulful","organ_chord"),
 disco_sample=p(
    "linn|hybrid","swung","analog|organ",
    "organ|pad","analog","seventh_ninth|borrowed_motion",
    "hook_ab","soulful|organic","sample_hook"),
 deep_rolling=p(
    "808|909","swung","sub|analog",
    "pad|organ","sub|analog","minor_modal|pedal_tone",
    "slow_burn","clean|club","bass_hook"),
 vocal_stab=p(
    "909|hybrid","straight|swung","organ|fm",
    "organ|rave","analog|fm","seventh_ninth",
    "hook_ab","soulful|club","vocal_answer"),},
FUNKY={
 filtered_disco=p(
    "linn|hybrid","swung","analog|organ",
    "organ|pad","analog","seventh_ninth|borrowed_motion",
    "hook_ab","organic|soulful","filtered_loop"),
 live_clavinet=p(
    "linn","syncopated|swung","fm|analog",
    "organ","fm|organ","seventh_ninth",
    "club_linear","organic|classic","clavinet_answer"),
 brass_vocal=p(
    "linn|909","syncopated","organ|fm",
    "organ|rave","analog|fm","borrowed_motion",
    "hook_ab","soulful|rave","brass_vocal"),
 french_touch=p(
    "909|hybrid","swung|straight","analog|organ",
    "pad|organ","analog","seventh_ninth",
    "double_drop","classic|club","filter_pump"),},
DIRTY={
 electro_riff=p(
    "909|industrial","straight|syncopated","reese|fm",
    "analog|rave","reese|fm","pedal_tone",
    "double_drop","digital|aggressive","bass_riff"),
 fidget_bass=p(
    "hybrid|909","syncopated","wobble|fm",
    "rave|fm","wobble|fm","minor_modal",
    "double_drop","digital|rave","talking_bass"),
 rave_stab=p(
    "909|industrial","straight","reese|analog",
    "rave","analog|reese","minor_modal",
    "hook_ab","rave|aggressive","rave_stab"),
 minimal_growl=p(
    "industrial","straight|polymetric","reese|wobble",
    "analog","reese|wobble","pedal_tone",
    "slow_burn","dark|digital","growl_tool"),},
TECHNO={
 hypnotic=p(
    "909","straight|polymetric","sub|analog",
    "analog","analog|fm","pedal_tone",
    "slow_burn","dark|club","ostinato"),
 dub_tool=p(
    "909|808","polymetric","sub",
    "pad|analog","analog","minor_modal|pedal_tone",
    "slow_burn","dark|clean","dub_chord"),
 warehouse=p(
    "industrial|909","straight","reese|analog",
    "analog|rave","reese|fm","pedal_tone",
    "club_linear","aggressive|dark","warehouse_stab"),
 industrial=p(
    "industrial","polymetric|straight","reese|fm",
    "fm|rave","fm|reese","minor_modal",
    "double_drop","digital|aggressive","metal_sequence"),},
GARAGE4={
 organ_4x4=p(
    "909|linn","swung","organ|sub",
    "organ","organ|analog","seventh_ninth",
    "club_linear","soulful|club","organ_skip"),
 soulful_vocal=p(
    "linn|hybrid","swung","sub|organ",
    "organ|pad","analog|organ","seventh_ninth|borrowed_motion",
    "hook_ab","soulful|clean","vocal_hook"),
 dark_sub=p(
    "909|hybrid","swung|syncopated","sub|reese",
    "fm|pad","sub|reese","minor_modal",
    "slow_burn","dark|club","sub_tease"),
 ravey_speed=p(
    "909|linn","swung|straight","reese|organ",
    "rave|organ","fm|reese","minor_modal",
    "double_drop","rave|club","rave_response"),},
TWO_STEP={
 deep_sub=p(
    "linn|909","broken|swung","sub",
    "pad|organ","sub|analog","minor_modal",
    "slow_burn","dark|clean","sub_space"),
 reese_shuffle=p(
    "linn|hybrid","broken","reese",
    "fm|pad","reese","minor_modal|pedal_tone",
    "double_drop","dark|broken","reese_answer"),
 organ_skip=p(
    "linn|909","swung|broken","organ",
    "organ","organ|fm","seventh_ninth",
    "hook_ab","soulful|broken","organ_skip"),
 fm_future=p(
    "hybrid|linn","broken|syncopated","fm|sub",
    "fm|pad","fm","borrowed_motion",
    "hook_ab","digital|clean","fm_call"),},
BREAKS={
 funky_break=p(
    "linn","broken|syncopated","analog|fm",
    "organ","analog|fm","seventh_ninth",
    "hook_ab","organic|broken","funk_break"),
 progressive_break=p(
    "hybrid|909","broken","analog|sub",
    "pad","analog","minor_modal|borrowed_motion",
    "slow_burn","tonal|clean","progression"),
 electro_break=p(
    "808|linn","broken|syncopated","reese|fm",
    "fm|rave","fm|reese","pedal_tone",
    "double_drop","digital|broken","electro_riff"),
 big_beat=p(
    "linn|industrial","broken","reese|analog",
    "rave","reese|analog","minor_modal",
    "double_drop","rave|aggressive","sample_riff"),},
DUBSTEP={
 deep_140=p(
    "808|linn","halftime","sub",
    "pad","sub|analog","minor_modal|pedal_tone",
    "slow_burn","dark|heavy","sub_space"),
 wobble=p(
    "industrial|linn","halftime|broken","wobble",
    "fm|rave","wobble","pedal_tone",
    "double_drop","digital|heavy","wobble_call"),
 halfstep_reese=p(
    "industrial|linn","halftime","reese",
    "fm|pad","reese","minor_modal",
    "double_drop","dark|heavy","reese_drop"),
 dubwise=p(
    "808|linn","halftime|broken","sub|reese",
    "pad|organ","analog","minor_modal",
    "hook_ab","organic|dark","dub_echo"),},
DEEP={
 warm_organ=p(
    "808|909","swung","organ|sub",
    "organ","organ|analog","seventh_ninth",
    "slow_burn","soulful|clean","warm_chord"),
 dub_chord=p(
    "808","polymetric|straight","sub|analog",
    "pad","analog","minor_modal|pedal_tone",
    "slow_burn","dark|clean","dub_chord"),
 soulful_pad=p(
    "909|808","swung","sub|organ",
    "pad|organ","analog|organ","seventh_ninth|borrowed_motion",
    "hook_ab","soulful|tonal","pad_hook"),
 minimal_deep=p(
    "808|909","straight|polymetric","sub",
    "analog|pad","sub|analog","pedal_tone",
    "club_linear","clean|club","micro_hook"),},
ACID={
 classic_303=p(
    "808|909","straight","303",
    "analog","analog","minor_modal",
    "club_linear","classic|rave","acid_line"),
 jack_acid=p(
    "909","syncopated|straight","303",
    "organ|rave","analog","minor_modal",
    "double_drop","classic|club","jack_phrase"),
 deep_acid=p(
    "808","swung|straight","303",
    "pad","analog|sub","minor_modal|pedal_tone",
    "slow_burn","dark|clean","acid_drift"),
 rave_acid=p(
    "909|industrial","straight","303",
    "rave","fm|analog","minor_modal",
    "double_drop","rave|aggressive","acid_rave"),},
TRANCE={
 uplifting=p(
    "909|hybrid","straight|double_time","analog",
    "pad","analog|fm","borrowed_motion",
    "double_drop","tonal|rave","supersaw_theme"),
 progressive_trance=p(
    "909|hybrid","straight|polymetric","sub|analog",
    "pad|analog","analog","minor_modal",
    "slow_burn","tonal|clean","progressive_theme"),
 acid_trance=p(
    "909","straight|double_time","303",
    "rave|pad","analog|fm","minor_modal",
    "double_drop","rave|tonal","acid_theme"),
 classic_euphoric=p(
    "909|hybrid","double_time|straight","reese|analog",
    "pad|rave","fm|analog","borrowed_motion",
    "double_drop","rave|tonal","euphoric_lead"),},
PROG={
 progressive_house=p(
    "909|hybrid","straight","analog|sub",
    "pad|analog","analog","borrowed_motion",
    "slow_burn","tonal|clean","long_theme"),
 tribal_progressive=p(
    "909|linn","polymetric|syncopated","sub|analog",
    "analog","analog|organ","minor_modal",
    "club_linear","organic|club","tribal_hook"),
 melodic_drive=p(
    "909|hybrid","straight|polymetric","reese|analog",
    "pad","analog|reese","borrowed_motion",
    "double_drop","tonal|clean","melodic_drive"),
 deep_progressive=p(
    "808|909","polymetric|straight","sub",
    "pad|analog","sub|analog","minor_modal|pedal_tone",
    "slow_burn","dark|tonal","deep_theme"),},
JUNGLE={
 amen_pressure=p(
    "linn|hybrid","broken|double_time","reese|sub",
    "rave|fm","reese|fm","minor_modal",
    "double_drop","broken|rave","break_chop"),
 ragga_jungle=p(
    "linn","broken","sub|reese",
    "organ|rave","organ|fm","minor_modal",
    "hook_ab","organic|rave","vocal_break"),
 darkside=p(
    "industrial|linn","broken|double_time","reese",
    "fm|rave","reese|fm","pedal_tone",
    "double_drop","dark|broken","dark_break"),
 jazz_jungle=p(
    "linn","broken|swung","sub|organ",
    "organ|pad","organ|analog","seventh_ninth",
    "hook_ab","organic|soulful","jazz_chop"),},
DNB={
 techstep=p(
    "industrial|linn","broken|double_time","reese|fm",
    "fm|rave","reese|fm","pedal_tone",
    "double_drop","dark|digital","tech_riff"),
 dancefloor=p(
    "linn|909","double_time|broken","reese|sub",
    "pad|rave","fm|reese","minor_modal|borrowed_motion",
    "double_drop","rave|tonal","anthem_hook"),
 rollers=p(
    "linn|909","broken","sub|reese",
    "pad|organ","reese|analog","minor_modal",
    "club_linear","dark|club","roller_riff"),
 neuro=p(
    "industrial|linn","broken|double_time","fm|reese",
    "fm|rave","wobble|fm","pedal_tone",
    "double_drop","digital|aggressive","neuro_call"),},
LIQUID={
 soulful_liquid=p(
    "linn|909","broken|swung","sub|organ",
    "organ|pad","organ|analog","seventh_ninth",
    "hook_ab","soulful|clean","soul_hook"),
 jazz_liquid=p(
    "linn","broken|swung","organ|sub",
    "organ","organ|fm","seventh_ninth|borrowed_motion",
    "hook_ab","organic|soulful","jazz_phrase"),
 vocal_liquid=p(
    "linn|909","broken","sub|reese",
    "pad|organ","analog","borrowed_motion",
    "hook_ab","soulful|tonal","vocal_theme"),
 deep_roller=p(
    "linn|909","broken","sub|reese",
    "pad","sub|reese","minor_modal",
    "slow_burn","dark|clean","deep_roll"),},
HARDTECHNO={
 warehouse_hard=p(
    "industrial|909","straight|double_time","reese|analog",
    "rave|analog","reese|fm","pedal_tone",
    "club_linear","aggressive|dark","hard_ostinato"),
 schranz=p(
    "industrial","double_time|straight","reese|fm",
    "fm|rave","fm|wobble","pedal_tone",
    "double_drop","aggressive|digital","schranz_loop"),
 industrial_rumble=p(
    "industrial","straight|polymetric","reese",
    "fm|analog","reese|fm","minor_modal",
    "slow_burn","dark|heavy","rumble_tail"),
 acid_hard=p(
    "industrial|909","straight|double_time","303",
    "rave","fm|analog","minor_modal",
    "double_drop","rave|aggressive","hard_acid"),},
ELECTRO={
 robot_funk=p(
    "808|linn","broken|syncopated","fm|analog",
    "fm|rave","fm","pedal_tone",
    "hook_ab","digital|classic","robot_call"),
 detroit_electro=p(
    "808","broken","analog|reese",
    "analog|pad","analog|reese","minor_modal",
    "slow_burn","classic|dark","detroit_theme"),
 breakdance=p(
    "linn|808","broken|syncopated","fm|reese",
    "rave|fm","fm|wobble","minor_modal",
    "double_drop","rave|broken","battle_hook"),
 dark_electro=p(
    "industrial|808","broken|polymetric","reese",
    "fm|analog","reese|fm","pedal_tone",
    "double_drop","dark|digital","dark_sequence"),},
JUKE={
 classic_juke=p(
    "808|linn","syncopated|double_time","sub|fm",
    "organ|fm","fm|sub","minor_modal",
    "hook_ab","broken|classic","footwork_call"),
 footwork=p(
    "808|linn","double_time|syncopated","sub",
    "fm|rave","fm|sub","pedal_tone",
    "double_drop","broken|digital","footwork_grid"),
 soul_chop=p(
    "linn","syncopated","organ|sub",
    "organ","organ|fm","seventh_ninth",
    "hook_ab","soulful|broken","soul_chop"),
 experimental_160=p(
    "industrial|808","polymetric|double_time","fm|sub",
    "fm|rave","fm|wobble","pedal_tone",
    "slow_burn","digital|broken","abstract_cut"),},
AFRO={
 organic_percussion=p(
    "linn|hybrid","polymetric|syncopated","sub|analog",
    "organ","organ|analog","seventh_ninth",
    "slow_burn","organic|soulful","percussion_hook"),
 deep_afro=p(
    "808|linn","polymetric","sub",
    "pad|organ","sub|analog","minor_modal",
    "slow_burn","organic|clean","deep_pulse"),
 vocal_afro=p(
    "linn|hybrid","syncopated|polymetric","organ|sub",
    "organ|pad","organ|analog","seventh_ninth|borrowed_motion",
    "hook_ab","organic|soulful","vocal_response"),
 melodic_afro=p(
    "hybrid|linn","polymetric","analog|organ",
    "pad|organ","analog|organ","borrowed_motion",
    "hook_ab","organic|tonal","mallet_theme"),},
MINIMAL={
 microhouse=p(
    "808|909","straight|swung","sub|analog",
    "analog|organ","analog","pedal_tone",
    "slow_burn","clean|club","micro_sample"),
 minimal_tech=p(
    "909","straight|polymetric","analog|sub",
    "analog","analog|fm","pedal_tone",
    "club_linear","clean|dark","click_sequence"),
 dub_minimal=p(
    "808|909","polymetric","sub",
    "pad|analog","analog","minor_modal",
    "slow_burn","dark|clean","dub_fragment"),
 clicky_tool=p(
    "808|909","polymetric|straight","sub|analog",
    "fm|analog","fm|analog","pedal_tone",
    "club_linear","digital|clean","click_hook"),},
MELODIC={
 melodic_techno=p(
    "909|hybrid","straight|polymetric","analog|reese",
    "pad","analog|reese","borrowed_motion",
    "double_drop","tonal|clean","melodic_theme"),
 deep_melodic=p(
    "808|909","polymetric|straight","sub|analog",
    "pad|organ","analog","minor_modal|borrowed_motion",
    "slow_burn","dark|tonal","deep_theme"),
 arpeggiated=p(
    "909|hybrid","straight","analog|sub",
    "pad|analog","fm|analog","borrowed_motion",
    "hook_ab","tonal|digital","arp_hook"),
 cinematic=p(
    "hybrid|industrial","straight|polymetric","reese|sub",
    "pad|rave","analog|reese","minor_modal|borrowed_motion",
    "slow_burn","tonal|rave","cinematic_arc"),},
SPEED={
 speed_garage=p(
    "909|linn","swung|broken","organ|reese",
    "organ|rave","organ|fm","minor_modal",
    "double_drop","rave|club","speed_hook"),
 bassline_speed=p(
    "linn|hybrid","swung|syncopated","fm|reese",
    "fm|organ","fm|wobble","minor_modal",
    "double_drop","rave|digital","bass_call"),
 rave_speed=p(
    "909|industrial","straight|double_time","reese|organ",
    "rave","fm|reese","minor_modal",
    "double_drop","rave|aggressive","rave_hook"),
 dark_speed=p(
    "industrial|linn","broken|double_time","reese|sub",
    "fm|rave","reese|wobble","pedal_tone",
    "slow_burn","dark|broken","dark_roll"),},
BASSLINE={
 organ_bassline=p(
    "909|linn","swung|syncopated","organ",
    "organ","organ|fm","minor_modal",
    "hook_ab","club|rave","organ_call"),
 donk_bassline=p(
    "linn|hybrid","syncopated|swung","fm",
    "fm|rave","fm","pedal_tone",
    "double_drop","digital|rave","donk_call"),
 reese_bassline=p(
    "909|hybrid","swung|broken","reese",
    "fm|rave","reese|wobble","minor_modal",
    "double_drop","dark|club","reese_call"),
 wobble_bassline=p(
    "industrial|hybrid","syncopated|swung","wobble|fm",
    "rave|fm","wobble","pedal_tone",
    "double_drop","digital|aggressive","wobble_answer"),},
HARDSTYLE={
 reverse_bass=p(
    "industrial|909","straight|double_time","analog|reese",
    "rave|pad","reese|fm","minor_modal",
    "club_linear","aggressive|rave","reverse_drive"),
 euphoric=p(
    "909|hybrid","double_time|straight","analog|reese",
    "pad","fm|analog","borrowed_motion",
    "double_drop","tonal|rave","euphoric_theme"),
 rawstyle=p(
    "industrial","straight|double_time","reese|fm",
    "rave|fm","wobble|fm","pedal_tone",
    "double_drop","aggressive|heavy","raw_screech"),
 classic_hardstyle=p(
    "industrial|909","straight","analog|reese",
    "rave|pad","analog|fm","minor_modal",
    "club_linear","classic|rave","classic_hook"),},
}

local allowed={
 kits={"808","909","linn","industrial","hybrid"},
 grooves={"straight","swung","syncopated","broken","halftime","double_time","polymetric"},
 bass={"analog","sub","reese","organ","fm","wobble","303"},
 chords={"analog","fm","organ","pad","rave"},
 mono={"analog","sub","reese","organ","fm","wobble"},
 harmony={"minor_modal","seventh_ninth","pedal_tone","borrowed_motion"},
 arrangements={"club_linear","hook_ab","double_drop","slow_burn"},
}
local function contains(values,wanted)
  for _,value in ipairs(values or {}) do if value==wanted then return true end end
  return false
end

local function chord_role_for(profile)
  local hook=profile.hook or ""
  if hook:find("bass") or hook:find("sub") or hook:find("reese") or
      hook:find("wobble") or hook:find("growl") or hook:find("acid") or
      hook:find("screech") or hook:find("kick") or hook:find("drum") or
      hook:find("percussion") or hook:find("rhythm") or hook:find("stomp") or
      hook:find("roller") or hook:find("neuro") then return "off" end
  if hook:find("chord") or hook:find("pad") or hook:find("organ") or
      hook:find("piano") or hook:find("theme") or hook:find("harmony") or
      hook:find("clavinet") then return "featured" end
  return "support"
end

for _,profiles in pairs(P) do
  for _,profile in pairs(profiles) do profile.chord_role=chord_role_for(profile) end
end

function M.profile(genre,archetype)
  return P[genre] and P[genre][archetype] or nil
end
function M.archetypes(genre)
  local result={}
  for name in pairs(P[genre] or {}) do result[#result+1]=name end
  table.sort(result)
  return result
end
function M.supports(genre,archetype,dimension,value)
  local profile=M.profile(genre,archetype)
  return profile and contains(profile[dimension],value) or false
end
function M.validate(genre,archetype)
  local profile=M.profile(genre,archetype)
  if not profile then return false,"missing archetype profile" end
  for dimension,values in pairs(allowed) do
    local choices=profile[dimension]
    if type(choices)~="table" or #choices==0 then return false,"missing "..dimension end
    for _,value in ipairs(choices) do
      if not contains(values,value) then return false,"invalid "..dimension.." "..tostring(value) end
    end
  end
  if genre=="TWO_STEP" and contains(profile.bass,"303") then return false,"2-Step profile allows 303" end
  if genre=="ACID" and not contains(profile.bass,"303") then return false,"Acid profile lacks 303" end
  if not contains({"off","support","featured"},profile.chord_role) then return false,"invalid chord role" end
  return true
end
function M.each()
  local result={}
  for genre,profiles in pairs(P) do
    for archetype,profile in pairs(profiles) do
      result[#result+1]={genre=genre,archetype=archetype,profile=profile}
    end
  end
  table.sort(result,function(a,b)
    return a.genre==b.genre and a.archetype<b.archetype or a.genre<b.genre
  end)
  return result
end

return M
