local enabled=ui.new_checkbox('Custom visuals')
local accent=ui.new_color_picker('Accent',150,205,80,255)
client.set_event_callback('paint',function()
    if not ui.get(enabled) then return end
    local r,g,b,a=ui.get(accent)
    local width,height=client.screen_size()
    local wave=(math.sin(globals.realtime()*2)+1)/2
    renderer.gradient(width-270,30,250,34,18,18,18,245,45,45,45,220,true)
    renderer.rectangle(width-270,30,250,2,r,g,b,a)
    renderer.text(width-260,40,235,235,235,255,'my hvh | '..globals.tickcount(),14)
    renderer.circle(width/2,height/2,12+wave*8,r,g,b,180,false)
    for _,slot in ipairs(entity.get_players(true)) do
        local target=entity.get(slot)
        if target and target.origin and target.health>0 then
            local p=target.origin
            local x,y=renderer.world_to_screen(p.X,p.Y+80,p.Z)
            if x then
                renderer.text(x,y,r,g,b,a,'HP '..target.health,13)
            end
        end
    end
end)
