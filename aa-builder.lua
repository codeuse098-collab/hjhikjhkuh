-- Paste into Config > Lua. All controls appear below the editor; enable after loading.
local enabled=ui.new_checkbox('Custom anti-aim')
local mode=ui.new_combobox('Condition',{'All','Standing','Moving','In air'})
local yaw=ui.new_slider('Yaw offset',-180,180,180)
local jitter=ui.new_slider('Jitter range',0,180,40)
local body=ui.new_slider('Body yaw',0,58,58)
local side=ui.new_combobox('Body side',{'Left','Right','Jitter'})
client.set_event_callback('anti_aim',function(cmd)
    if not ui.get(enabled) then return end
    local cond=antiaim.get_condition()
    local selected=ui.get(mode)
    if selected==2 and cond~='standing' then return end
    if selected==3 and cond~='moving' then return end
    if selected==4 and cond~='in air' then return end
    local phase=if cmd.packet%2==0 then 1 else -1
    cmd.yaw=cmd.view_yaw+ui.get(yaw)+phase*ui.get(jitter)/2
    cmd.pitch=89
    cmd.desync_amount=ui.get(body)
    cmd.desync_side=if ui.get(side)==3 then phase elseif ui.get(side)==1 then 1 else -1
end)
