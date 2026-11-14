-- Grenades in flight: the predicted rest of each path, where it goes off, the time left, a warning when it lands
-- near you. entity.get_grenades() + renderer.effect through_walls. Grenade mode only (the list is empty elsewhere).
local enabled=ui.new_checkbox('Grenade warning');ui.set(enabled,true)
local enemyOnly=ui.new_checkbox('Enemy grenades only')
local showPath=ui.new_checkbox('Draw path');ui.set(showPath,true)
local marker=ui.new_checkbox('Landing marker through walls');ui.set(marker,true)
local danger=ui.new_slider('Warning radius / hu',100,600,350)
local tint=ui.new_color_picker('Enemy color',255,90,90,255)
local friendTint=ui.new_color_picker('Friendly color',120,180,255,255)

local NAMES={he='HE',smoke='SMOKE',molotov='MOLOTOV',incendiary='INCENDIARY',flash='FLASH',decoy='DECOY'}
local markers={} -- grenade id -> {effect, at}

local function drop(id)
    if markers[id] then renderer.remove_effect(markers[id].effect);markers[id]=nil end
end

client.set_event_callback('paint',function()
    local seen={}
    if ui.get(enabled) then
        local me=entity.get_local_player()
        local state=entity.get_local_state()
        local origin=state and state.move and state.move.origin
        local sw,sh=client.screen_size()
        local warn=nil
        for _,g in entity.get_grenades() do
            local enemy=g.thrower~=me and entity.is_enemy(g.thrower)
            if g.path and (enemy or not ui.get(enemyOnly)) then
                local r,gr,b,a
                if enemy then r,gr,b,a=ui.get(tint) else r,gr,b,a=ui.get(friendTint) end
                -- the rest of the flight as a screen polyline (drawn over everything, shorter every frame)
                if ui.get(showPath) then
                    local px,py=renderer.world_to_screen(g.origin.X,g.origin.Y,g.origin.Z)
                    for _,p in g.path do
                        local x,y=renderer.world_to_screen(p.X,p.Y,p.Z)
                        if px and x then renderer.line(px,py,x,y,r,gr,b,a,2) end
                        px,py=x,y
                    end
                end
                -- one world marker per grenade where it detonates; moved when a bounce changes the prediction
                local land=g.landing
                if ui.get(marker) then
                    local m=markers[g.id]
                    if not m then
                        markers[g.id]={at=land,effect=renderer.effect('sphere',land,
                            {radius=4,color={r,gr,b,200},life=10,fade=0,through_walls=true})}
                    elseif (m.at-land).Magnitude>4 then
                        renderer.update_effect(m.effect,{position=land});m.at=land
                    end
                    seen[g.id]=true
                end
                local x,y=renderer.world_to_screen(land.X,land.Y+10,land.Z)
                if x then
                    renderer.text(x-30,y-8,r,gr,b,255,string.format('%s %.1fs',NAMES[g.type] or g.type,g.time_left),14)
                end
                -- the closest dangerous one for the screen warning (smokes are harmless)
                if enemy and origin and g.type~='smoke' then
                    local dist=(land-origin).Magnitude
                    if dist<=ui.get(danger) and (not warn or dist<warn.dist) then
                        warn={dist=dist,name=NAMES[g.type] or g.type,time=g.time_left}
                    end
                end
            end
        end
        if warn then
            local text=string.format('! %s lands %d hu away in %.1fs',warn.name,warn.dist,warn.time)
            renderer.rectangle(sw/2-150,sh*0.25-4,300,24,0,0,0,150)
            renderer.text(sw/2-140,sh*0.25,255,80,80,255,text,16)
        end
    end
    for id in markers do if not seen[id] then drop(id) end end
end)
client.set_event_callback('shutdown',function() for id in markers do drop(id) end end)
