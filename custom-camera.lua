local enabled=ui.new_checkbox('Lua camera') -- off until explicitly enabled
local third=ui.new_checkbox('Lua third person');ui.set(third,true)
local distance=ui.new_slider('Camera distance / hu',0,240,100)
local fov=ui.new_slider('Camera horizontal FOV',40,140,100)
local shoulder=ui.new_slider('Shoulder offset / hu',-40,40,12)
local roll=ui.new_slider('Camera roll',-20,20,0)
client.set_event_callback('override_view',function(v)
 if not ui.get(enabled) then return end
 v.thirdperson=ui.get(third);v.distance=ui.get(distance);v.fov=ui.get(fov);v.roll=ui.get(roll)
 local yaw=math.rad(v.yaw)
 v.position=v.position+vector.new(math.cos(yaw),0,-math.sin(yaw))*ui.get(shoulder)
 v.collision=true;v.viewmodel_fov=100;v.viewmodel_offset=vector.new(2,0,0)
end)
