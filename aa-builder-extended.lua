-- Five editable states, native body desync, packet jitter and per-state overrides.
-- Load, enable "Extended AA builder", then edit each state in the selector.
local enabled=ui.new_checkbox('Extended AA builder')
local selected=ui.new_combobox('Edit condition',{'Shared','Standing','Moving','Air','Duck'})
local names={'Shared','Standing','Moving','Air','Duck'}
local controls={}
for i,name in ipairs(names) do
    controls[i]={
        override=ui.new_checkbox(name..' override'),
        yaw=ui.new_slider(name..' yaw',-180,180,180),
        jitter=ui.new_slider(name..' jitter',0,180,40),
        pitch=ui.new_combobox(name..' pitch',{'Off','Down','Up','Zero','Jitter'}),
        body=ui.new_slider(name..' body',0,58,58),
        side=ui.new_combobox(name..' side',{'Left','Right','Jitter','Random'}),
    }
end
-- The builder takes over the AA tab while loaded (built-in AA settings stay as they are; unload brings the tab back).
ui.override_tab('AA')
ui.set_group(enabled,'Builder');ui.set_group(selected,'Builder')
for _,c in ipairs(controls) do for _,id in pairs(c) do ui.set_group(id,'Condition') end end
local function refresh()
    local choice=ui.get(selected)
    for i,c in ipairs(controls) do
        for field,id in pairs(c) do ui.set_visible(id,i==choice and (field~='override' or i~=1)) end
    end
end
ui.set_callback(selected,refresh);refresh()
local previousPacket=-1;local randomSide=1
client.set_event_callback('anti_aim',function(cmd)
    if not ui.get(enabled) then return end
    local state=entity.get_local_state();if not state then return end
    local index=if not state.move.onGround then 4 elseif state.move.duckAmount>.5 then 5 elseif state.move.velocity.Magnitude>5 then 3 else 2
    if not ui.get(controls[index].override) then index=1 end
    local c=controls[index];local phase=if cmd.packet%2==0 then 1 else -1
    if cmd.packet~=previousPacket then previousPacket=cmd.packet;randomSide=if math.random(0,1)==0 then -1 else 1 end
    cmd.yaw=cmd.view_yaw+ui.get(c.yaw)+phase*ui.get(c.jitter)/2
    local pitch=ui.get(c.pitch)
    if pitch==2 then cmd.pitch=89 elseif pitch==3 then cmd.pitch=-89 elseif pitch==4 then cmd.pitch=0 elseif pitch==5 then cmd.pitch=89*phase end
    cmd.desync_amount=ui.get(c.body)
    local side=ui.get(c.side)
    cmd.desync_side=if side==1 then 1 elseif side==2 then -1 elseif side==3 then phase else randomSide
end)
