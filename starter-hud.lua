-- Load in Config > Lua. Enabled immediately; change Element to preview each item separately.
local enabled=ui.new_checkbox('Starter HUD');ui.set(enabled,true)
local element=ui.new_combobox('Element',{'FPS counter','Frame graph','Drawing primitives'})
local tint=ui.new_color_picker('Accent',125,209,167,255)
local samples=table.create(48,0)
client.every(.1,function()
 table.remove(samples,1);table.insert(samples,globals.frametime()*1000)
end)
client.set_event_callback('paint',function()
 if not ui.get(enabled) then return end
 local sw,sh=client.screen_size();local x,y=math.floor(sw/2-190),math.floor(sh/2-100)
 local r,g,b,a=ui.get(tint);local choice=ui.get(element)
 renderer.rounded_rectangle(x,y,380,200,17,23,28,240,10)
 if choice==1 then
  renderer.text_ex(x+24,y+20,'FPS',{font='ui_bold',size=26,color={r,g,b,a}})
  renderer.text_ex(x+24,y+68,string.format('%.0f',1/math.max(globals.frametime(),.001)),{font='gotham',size=48,color={240,245,247,255}})
  renderer.text_ex(x+24,y+145,string.format('%.1f ms',globals.frametime()*1000),{font='code',size=20,color={180,200,210,255}})
 elseif choice==2 then
  renderer.text_ex(x+24,y+20,'FRAME / MS',{font='ui_bold',size=24,color={r,g,b,a}})
  renderer.push_clip(x+24,y+65,332,110)
  for i=0,3 do renderer.line(x+24,y+70+i*30,x+356,y+70+i*30,255,255,255,24,1) end
  local points={}
  for i,value in ipairs(samples) do points[i]={x+24+(i-1)*332/47,y+170-math.min(value,80)/80*100} end
  renderer.polyline(points,r,g,b,a,2,false)
  renderer.pop_clip()
 else
  renderer.text_ex(x+24,y+20,'DRAW',{font='ui_bold',size=24,color={r,g,b,a}})
  renderer.arc(x+78,y+120,30,-90,270,r,g,b,a,3,32)
  renderer.triangle(x+170,y+88,x+200,y+148,x+140,y+148,r,g,b,a,true)
  renderer.rounded_rectangle(x+238,y+92,48,54,197,151,236,255,9)
  renderer.rectangle_outline(x+307,y+92,45,54,r,g,b,a,2)
 end
end)
