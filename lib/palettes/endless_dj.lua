-- EndlessDJ RGB colour palette for Launchpad Gen 3 devices via midigrid.
--
-- Maps midigrid brightness levels 0–15 to {r, g, b} (0–127 each).
-- Levels correspond to the LEVEL table in EndlessDJ.lua:
--
--   0  OFF       — off
--   1  INACTIVE  — inactive step (dim grey)
--   2  (unused)  — dim grey
--   3  PLAYHEAD  — playhead cursor on an inactive step (medium grey)
--   4  (unused)  — medium grey
--   5  KICK      — kick drum lane (red)
--   6  SNARE     — snare lane (yellow)
--   7  OHAT      — open hi-hat lane (green)
--   8  CHAT      — closed hi-hat lane (blue)
--   9  NTS1      — NTS-1 enabled step (cyan)
--  10  J6        — J-6 enabled step (violet)
--  11  ROOT      — root note on keyboard (amber)
--  12  SCALE     — in-scale note on keyboard (lime)
--  13  CHROMA    — chromatic / out-of-scale note (dim purple)
--  14  PRESSED   — pressed note or active trigger (warm white)
--  15  HOT       — active step under playhead (bright white)

return {
  {  0,   0,   0},   --  0: off
  {  8,   8,   8},   --  1: inactive step (dim grey)
  { 14,  14,  14},   --  2: (unused) dim grey
  { 22,  22,  22},   --  3: playhead cursor (medium grey)
  { 30,  30,  30},   --  4: (unused) medium grey
  {100,   8,   0},   --  5: kick (red)
  { 90,  72,   0},   --  6: snare (yellow)
  {  0,  90,   0},   --  7: open hi-hat (green)
  {  0,  25, 100},   --  8: closed hi-hat (blue)
  {  0,  90,  80},   --  9: NTS-1 (cyan)
  { 65,   0, 100},   -- 10: J-6 (violet)
  {100,  50,   0},   -- 11: root note (amber)
  { 30, 105,  10},   -- 12: in-scale note (lime green)
  { 28,   0,  60},   -- 13: chromatic note (dim purple)
  {115, 110,  85},   -- 14: pressed / active trigger (warm white)
  {127, 127, 127},   -- 15: hot — active step under playhead (max white)
}
