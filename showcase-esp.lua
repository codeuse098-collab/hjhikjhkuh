-- Public snapshots only; this script changes no aiming or server state.
local enabled=ui.new_checkbox('Custom Lua ESP');ui.set(enabled,true)
local head=ui.new_checkbox('Public head marker');ui.set(head,true)
client.set_event_callback('paint',function()
    if not ui.get(enabled) then return end
    local drawn=0
    for _,slot in ipairs(entity.get_players(true)) do
        if not entity.is_alive(slot) then continue end
        local target=entity.get(slot);local p=target.origin
        local x,y=renderer.world_to_screen(p.X,p.Y+76,p.Z)
        local fx,fy=renderer.world_to_screen(p.X,p.Y,p.Z)
        if not x or not fx then continue end
        drawn+=1;if drawn>3 then break end
        local h=math.max(24,fy-y);local w=h*.46;local left=x-w/2
        renderer.rectangle_outline(left-1,y-1,w+2,h+2,0,0,0,230,3)
        renderer.rectangle_outline(left,y,w,h,125,209,167,245,1)
        renderer.text_ex(x,y-23,entity.get_name(slot) or ('Player '..slot),{font='ui_bold',size=16,align='center',color={240,245,247,255},outline=true})
        renderer.rectangle(left-7,y,3,h,15,20,24,240)
        local hp=math.clamp(target.health/100,0,1)
        renderer.rectangle(left-7,y+h*(1-hp),3,h*hp,125,209,167,255)
        local weapon=entity.get_weapon(slot)
        renderer.text_ex(x,fy+7,(weapon and weapon.model or 'weapon')..' / '..target.clip,{font='code',size=12,align='center',color={180,200,215,255},outline=true})
        renderer.text_ex(left+w+7,y+8,'PUBLIC',{font='code',size=11,color={125,209,167,255},outline=true})
        renderer.text_ex(left+w+7,y+25,target.health..' HP',{font='code',size=11,color={215,225,232,255},outline=true})
        if ui.get(head) then
            local boxes=entity.get_hitboxes(slot)
            if boxes[1] then
                local hpos=boxes[1].origin;local hx,hy=renderer.world_to_screen(hpos.X,hpos.Y,hpos.Z)
                if hx then renderer.circle(hx,hy,4,245,194,110,255,false) end
            end
        end
    end
    renderer.rounded_rectangle(24,76,292,62,17,23,28,235,10)
    renderer.text_ex(40,88,'CUSTOM LUA ESP',{font='ui_bold',size=18,color={125,209,167,255}})
    renderer.text_ex(40,113,'Boxes, HP, names and public hitbox marker',{font='ui',size=13,color={173,190,202,255}})
end)
