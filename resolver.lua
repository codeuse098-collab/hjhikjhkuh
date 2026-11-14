-- Demonstrates the override API, NOT a recommended resolving algorithm.
local enabled=ui.new_checkbox('Custom resolver')
local side=ui.new_combobox('Hypothesis',{'Public feet','Left','Right','Center'})
client.set_event_callback('resolve',function(target)
    if not ui.get(enabled) then return nil end -- keep the built-in result
    local mode=ui.get(side)
    if mode==1 then return target.foot_yaw end
    if mode==2 then return target.yaw+target.max_desync end
    if mode==3 then return target.yaw-target.max_desync end
    return target.yaw
end)
client.set_event_callback('shot',function(event)
    if ui.get(enabled) and event.shooter==entity.get_local_player() then
        client.log('Shot',event.cmdNumber,'damage',event.damage or 0)
    end
end)
