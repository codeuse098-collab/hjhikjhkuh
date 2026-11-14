-- Demonstrates scan control; not an accuracy improvement claim.
local enabled=ui.new_checkbox('Lua rage rules')
local damage=ui.new_slider('Lua minimum damage',1,130,35)
local chance=ui.new_slider('Lua hitchance',0,100,60)
local airborne=ui.new_checkbox('Skip airborne targets')
local center=ui.new_checkbox('Prefer center points')
local hold=ui.new_hotkey('Hold fire', 'H', 'Hold')
client.set_event_callback('rage_config',function(c)
 if not ui.get(enabled) then return end
 c.minDamage=ui.get(damage);c.hitchance=ui.get(chance)
end)
client.set_event_callback('rage_target',function(t)
 if not ui.get(enabled) or not ui.get(airborne) then return end
 local e=entity.get(t.slot);if e and bit.band(e.flags,1)==0 then t.skip=true end
end)
client.set_event_callback('rage_point',function(p)
 if ui.get(enabled) and ui.get(center) and p.center then p.score=1000 end
end)
client.set_event_callback('rage_fire',function(s)
 if ui.get(enabled) and ui.get(hold) then s.skip=true end
end)
