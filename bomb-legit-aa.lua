-- Own anti-aim for the two special states the anti_aim command reports:
--   cmd.bomb_action  'plant' / 'defuse' while you are frozen by a real plant / defuse
--                    (needs AA > Other "Anti-aim on bomb actions": without it anti_aim is not called there)
--   cmd.legit_aa     AA > Other "Legit anti-aim" is held (E by default): the built-in pitch / yaw stayed on your view
-- Outside these two states the script leaves the built-in anti-aim alone.
local enabled=ui.new_checkbox('Bomb / legit anti-aim');ui.set(enabled,true)
local bombYaw=ui.new_combobox('Bomb yaw',{'Backward','Spin','Jitter'})
local bombPitch=ui.new_combobox('Bomb pitch',{'Down','Up','View'})
local spinSpeed=ui.new_slider('Spin / deg per packet',5,90,30)
local jitter=ui.new_slider('Jitter range',0,180,60)
local bombBody=ui.new_slider('Bomb body yaw',0,58,58)
local legitBody=ui.new_slider('Legit body yaw',0,58,58)
local legitSide=ui.new_combobox('Legit body side',{'Left','Right','Jitter'})
local indicator=ui.new_checkbox('Indicator');ui.set(indicator,true)

local status,statusAt=nil,0
client.set_event_callback('anti_aim',function(cmd)
    if not ui.get(enabled) then return end
    local phase=if cmd.packet%2==0 then 1 else -1 -- flips once per sent packet: choked commands never show
    if cmd.bomb_action then
        local mode=ui.get(bombYaw)
        if mode==1 then cmd.yaw=cmd.view_yaw+180
        elseif mode==2 then cmd.yaw=cmd.view_yaw+cmd.packet*ui.get(spinSpeed)
        else cmd.yaw=cmd.view_yaw+180+phase*ui.get(jitter)/2 end
        local pitch=ui.get(bombPitch)
        if pitch==1 then cmd.pitch=89 elseif pitch==2 then cmd.pitch=-89 else cmd.pitch=cmd.view_pitch end
        cmd.desync_amount=ui.get(bombBody)
        cmd.desync_side=phase
        status=if cmd.bomb_action=='plant' then 'PLANT AA' else 'DEFUSE AA'
        statusAt=globals.realtime()
    elseif cmd.legit_aa then
        -- angles stay on the view (what a legit player looks like); only the body side is ours
        local side=ui.get(legitSide)
        cmd.desync_amount=ui.get(legitBody)
        cmd.desync_side=if side==3 then phase elseif side==1 then 1 else -1
        status='LEGIT AA';statusAt=globals.realtime()
    end
end)
client.set_event_callback('paint',function()
    if not ui.get(indicator) or not status or globals.realtime()-statusAt>0.2 then return end
    local sw,sh=client.screen_size()
    renderer.text(sw/2-36,sh/2+60,125,209,255,255,status,14)
end)
