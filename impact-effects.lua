local enabled=ui.new_checkbox('Custom 3D impacts');ui.set(enabled,true)
local sparks=ui.new_checkbox('Impact particles');ui.set(sparks,true)
local tint=ui.new_color_picker('Impact color',125,209,255,255)
client.set_event_callback('bullet_impact',function(e)
 if not ui.get(enabled) or e.shooter~=entity.get_local_player() then return end
 local r,g,b,a=ui.get(tint);local color={r,g,b,a}
 renderer.effect('sphere',e.impact,{radius=1.5,color=color,life=.8,fade=.5})
 renderer.effect('ring',e.impact,{radius=5,width=.5,color=color,life=.8,fade=.5})
 if ui.get(sparks) then renderer.effect('particles',e.impact,{radius=.6,color=color,count=12,speed=60,life=.5}) end
end)
client.set_event_callback('player_hurt',function(e)
 if not ui.get(enabled) or e.shooter~=entity.get_local_player() then return end
 renderer.effect('text',e.impact+vector.new(0,8,0),{text='-'..e.damage,color={255,100,100,255},life=1,fade=.5,text_size=18})
end)
