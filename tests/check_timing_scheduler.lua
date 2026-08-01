local scheduler=dofile("lib/timing_scheduler.lua")
local fired={}
local function add(name) return function() fired[#fired+1]=name end end

scheduler.clear()
scheduler.schedule(100,0.25,6,add("bass"),"bass")
scheduler.schedule(100,0,6,add("kick"),"kick")
scheduler.schedule(100,0.25,6,add("chord"),"chord")
assert(scheduler.pending_count()==3)
local count,errors=scheduler.service(100)
assert(count==1 and #errors==0 and fired[1]=="kick")
count,errors=scheduler.service(102)
assert(count==2 and #errors==0)
assert(fired[2]=="bass" and fired[3]=="chord","same-pulse ordering changed")
assert(scheduler.pending_count()==0)

scheduler.schedule(200,-1,6,add("clamped"),"clamped")
assert(scheduler.service(200)==1,"negative timing must clamp safely")
scheduler.schedule(300,0.49,6,add("late"),"late")
scheduler.clear()
assert(scheduler.pending_count()==0,"clear left stale events")

print("All timing scheduler checks passed")
