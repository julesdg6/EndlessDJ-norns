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
