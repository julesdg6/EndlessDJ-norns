-- Bounded high-resolution event queue for deterministic musical microtiming.
-- One shared queue services internal-engine and external-MIDI callbacks.
local M = {queue={}, sequence=0}

local function clamp(value,minimum,maximum)
  return math.max(minimum,math.min(maximum,value))
end

function M.offset_to_pulses(offset,pulses_per_step)
  local safe=clamp(tonumber(offset) or 0,0,0.49)
  return math.floor(safe*pulses_per_step+0.5)
end

function M.schedule(current_pulse,offset,pulses_per_step,callback,label)
  assert(type(callback)=="function","scheduled event requires a callback")
  M.sequence=M.sequence+1
  local event={
    due=current_pulse+M.offset_to_pulses(offset,pulses_per_step),
    callback=callback, label=label or "event", sequence=M.sequence,
  }
  M.queue[#M.queue+1]=event
  return event.sequence
end

function M.service(current_pulse)
  local ready={}
  for index=#M.queue,1,-1 do
    if M.queue[index].due<=current_pulse then
      ready[#ready+1]=table.remove(M.queue,index)
    end
  end
  table.sort(ready,function(a,b)
    if a.due==b.due then return a.sequence<b.sequence end
    return a.due<b.due
  end)
  local errors={}
  for _,event in ipairs(ready) do
    local ok,reason=pcall(event.callback)
    if not ok then errors[#errors+1]=event.label..": "..tostring(reason) end
  end
  return #ready,errors
end

function M.clear()
  M.queue={}
end

function M.pending_count()
  return #M.queue
end

return M
