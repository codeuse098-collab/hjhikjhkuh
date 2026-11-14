-- Expanded API demo. Shows immediately; open the menu to drag the panel with Mouse1.
local enabled=ui.new_checkbox('Custom dashboard');ui.set(enabled,true)
local features=ui.new_multiselect('Dashboard features',{'Arc','Triangle','Enemy names'});ui.set(features,{true,true,true})
local title=ui.new_textbox('Panel title','my lua')
local accent=ui.new_color_picker('Accent',160,205,80,255)
local hotkey=ui.new_hotkey('Dashboard hotkey','None','Always')
local status=ui.new_label('Ready')
local x=storage.get('x');local y=storage.get('y') or 80
local dragging=false;local dx,dy=0,0;local packets=0
ui.new_button('Reset panel position',function() x=nil;y=80;storage.set('x',nil);storage.set('y',nil) end)
ui.set_callback(enabled,function() ui.set_visible(features,ui.get(enabled));ui.set_visible(accent,ui.get(enabled)) end)
client.set_event_callback('net_update_end',function() packets+=1 end)
client.every(.5,function() ui.set(status,'Snapshots: '..packets) end)
client.set_event_callback('paint',function()
    if not ui.get(enabled) or not ui.get(hotkey) then return end
    local sw,sh=client.screen_size();x=x or math.max(0,sw-310)
    local mx,my=client.mouse_position()
    local down=client.key_state('Mouse1')
    if ui.is_menu_open() and down and not dragging and mx>=x and mx<=x+280 and my>=y and my<=y+32 then dragging=true;dx=mx-x;dy=my-y end
    if not down then
        if dragging then storage.set('x',x);storage.set('y',y) end
        dragging=false
    end
    if dragging then x=math.clamp(mx-dx,0,math.max(0,sw-280));y=math.clamp(my-dy,0,math.max(0,sh-150)) end
    local r,g,b,a=ui.get(accent);local show=ui.get(features)
    renderer.rounded_rectangle(x,y,280,150,18,18,22,235,8)
    renderer.rectangle(x+8,y,264,2,r,g,b,a)
    renderer.text_ex(x+14,y+10,ui.get(title),{font='ui_bold',size=18,color={r,g,b,a},outline=true})
    renderer.text(x+14,y+38,190,190,200,255,'Drag with menu open | '..packets..' snaps',12)
    if show[1] then renderer.arc(x+240,y+92,25,-90,270*(math.sin(globals.realtime())*.5+.5),r,g,b,a,3,24) end
    if show[2] then renderer.triangle(x+234,y+84,x+250,y+104,x+218,y+104,r,g,b,a,true) end
    renderer.push_clip(x+12,y+62,190,76)
    if show[3] then
        local line=0
        for _,slot in ipairs(entity.get_players(true)) do
            if entity.is_alive(slot) then
                renderer.text(x+14,y+64+line*17,235,235,240,255,(entity.get_name(slot) or tostring(slot))..' | '..entity.get_prop(slot,'health')..' HP',13)
                line+=1
            end
        end
    end
    renderer.pop_clip()
end)
