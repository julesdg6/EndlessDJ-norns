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
 classic_organ=p("909","swung|straight","organ|analog","organ","analog|organ","seventh_ninth","club_linear","classic|soulful","organ_chord"),
 disco_sample=p("linn|hybrid","swung","analog|organ","organ|pad","analog","seventh_ninth|borrowed_motion","hook_ab","soulful|organic","sample_hook"),
 deep_rolling=p("808|909","swung","sub|analog","pad|organ","sub|analog","minor_modal|pedal_tone","slow_burn","clean|club","bass_hook"),
 vocal_stab=p("909|hybrid","straight|swung","organ|fm","organ|rave","analog|fm","seventh_ninth","hook_ab","soulful|club","vocal_answer"),},
FUNKY={
 filtered_disco=p("linn|hybrid","swung","analog|organ","organ|pad","analog","seventh_ninth|borrowed_motion","hook_ab","organic|soulful","filtered_loop"),
 live_clavinet=p("linn","syncopated|swung","fm|analog","organ","fm|organ","seventh_ninth","club_linear","organic|classic","clavinet_answer"),
 brass_vocal=p("linn|909","syncopated","organ|fm","organ|rave","analog|fm","borrowed_motion","hook_ab","soulful|rave","brass_vocal"),
 french_touch=p("909|hybrid","swung|straight","analog|organ","pad|organ","analog","seventh_ninth","double_drop","classic|club","filter_pump"),},
DIRTY={
 electro_riff=p("909|industrial","straight|syncopated","reese|fm","analog|rave","reese|fm","pedal_tone","double_drop","digital|aggressive","bass_riff"),
 fidget_bass=p("hybrid|909","syncopated","wobble|fm","rave|fm","wobble|fm","minor_modal","double_drop","digital|rave","talking_bass"),
 rave_stab=p("909|industrial","straight","reese|analog","rave","analog|reese","minor_modal","hook_ab","rave|aggressive","rave_stab"),
 minimal_growl=p("industrial","straight|polymetric","reese|wobble","analog","reese|wobble","pedal_tone","slow_burn","dark|digital","growl_tool"),},
TECHNO={
 hypnotic=p("909","straight|polymetric","sub|analog","analog","analog|fm","pedal_tone","slow_burn","dark|club","ostinato"),
