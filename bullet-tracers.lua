-- Real world-space beams, emitted once for each server-confirmed bullet.
local enabled=ui.new_checkbox('Custom 3D bullet tracers');ui.set(enabled,true)
local others=ui.new_checkbox('Other players tracers')
local tint=ui.new_color_picker('Tracer color',125,209,255,255)
local width=ui.new_slider('Tracer width / hu',1,12,2)
local life=ui.new_slider('Tracer life / tenths',1,50,10)
client.set_event_callback('shot',function(e)
    if not ui.get(enabled) or bit.band(e.flags or 0,8)~=0 then return end
    if not ui.get(others) and e.shooter~=entity.get_local_player() then return end
    -- Penetration may report more than one victim for a single bullet.
    if bit.band(e.flags or 0,32)~=0 then return end
    local r,g,b,a=ui.get(tint)
    if e.start and e.impact and (e.impact-e.start).Magnitude>.001 then
        renderer.tracer(e.start,e.impact,{color={r,g,b,a},width=ui.get(width),
            end_width=.5,life=ui.get(life)/10,fade=.35,glow=1})
    end
end)
