-- Live showcase: every visible number comes from this client's actual state.
local enabled=ui.new_checkbox('Showcase HUD');ui.set(enabled,true)
local accent=ui.new_color_picker('HUD accent',125,209,167,255)
local samples={};local lastFrame=16
client.every(.1,function()
    table.insert(samples,lastFrame);if #samples>48 then table.remove(samples,1) end
end)
client.set_event_callback('paint',function()
    if not ui.get(enabled) then return end
    local sw,sh=client.screen_size();local r,g,b,a=ui.get(accent)
    lastFrame=globals.frametime()*1000
    local x=sw-354;local y=76
    renderer.rounded_rectangle(x+3,y+4,326,254,0,0,0,80,12)
    renderer.rounded_rectangle(x,y,326,254,17,23,28,240,12)
    renderer.gradient(x+14,y,298,2,r,g,b,255,75,140,200,255,true)
    renderer.text_ex(x+18,y+16,'LUA / LIVE TELEMETRY',{font='ui_bold',size=20,color={r,g,b,a}})
    renderer.text_ex(x+18,y+46,'Custom window, timers, clipped graph',{font='ui',size=15,color={155,169,180,255}})
    renderer.text_ex(x+18,y+80,string.format('%.0f',1/math.max(globals.frametime(),.001)),{font='gotham',size=32,color={235,242,247,255}})
    renderer.text_ex(x+18,y+119,'FPS',{font='ui',size=12,color={132,150,163,255}})
    renderer.text_ex(x+115,y+80,string.format('%.1f',lastFrame),{font='gotham',size=32,color={235,242,247,255}})
    renderer.text_ex(x+115,y+119,'FRAME / MS',{font='ui',size=12,color={132,150,163,255}})
    renderer.arc(x+270,y+106,27,-90,math.min(360,lastFrame/33*360),r,g,b,255,3,28)
    renderer.text_ex(x+270,y+98,'LIVE',{font='ui_bold',size=12,align='center',color={r,g,b,255}})
    renderer.push_clip(x+18,y+153,290,65)
    for i=0,3 do renderer.line(x+18,y+153+i*20,x+308,y+153+i*20,255,255,255,18,1) end
    local points={}
    for i,value in ipairs(samples) do points[i]={x+18+(i-1)*290/47,y+214-math.min(value,80)/80*56} end
    if #points>=2 then renderer.polyline(points,r,g,b,255,2,false) end
    renderer.pop_clip()
    renderer.text_ex(x+18,y+228,'PUBLIC SNAPSHOT  '..globals.server_tick(),{font='code',size=12,color={155,169,180,255}})
    local bx,by=sw-354,sh-194
    renderer.rounded_rectangle(bx,by,326,106,17,23,28,240,12)
    renderer.text_ex(bx+18,by+13,'CUSTOM DRAWING',{font='ui_bold',size=16,color={232,239,245,255}})
    renderer.triangle(bx+40,by+45,bx+64,by+81,bx+16,by+81,r,g,b,235,true)
    renderer.arc(bx+101,by+64,20,0,275,111,165,230,255,3,24)
    renderer.rounded_rectangle(bx+142,by+46,44,34,197,151,236,200,9)
    renderer.rectangle_outline(bx+207,by+46,41,34,r,g,b,230,2)
    renderer.text_ex(bx+268,by+51,'Aa',{font='gotham',size=25,color={240,240,245,255},outline=true})
end)
