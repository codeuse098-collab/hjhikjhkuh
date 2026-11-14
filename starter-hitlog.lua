-- Own server-confirmed hits/misses, optional real 3D beams. Does not enable or reconfigure rage.
local enabled=ui.new_checkbox('Starter hitlog');ui.set(enabled,true)
local tracers=ui.new_checkbox('3D tracers');ui.set(tracers,true)
local duration=ui.new_slider('Log lifetime / seconds',1,10,5)
local tint=ui.new_color_picker('Hit color',125,209,167,255)
local rows={}
local groups={'head','chest','stomach','arm','leg','neck'}
local reasons={'spread','resolver','occlusion','death','prediction error'}
local function add(text,hit)
 table.insert(rows,1,{text=text,hit=hit,at=globals.realtime()})
 if #rows>5 then table.remove(rows) end
end
client.set_event_callback('shot',function(e)
 if not ui.get(enabled) or e.shooter~=entity.get_local_player() then return end
 local melee=bit.band(e.flags or 0,8)~=0
 local extra=not melee and bit.band(e.flags or 0,32)~=0
 if ui.get(tracers) and not melee and not extra and e.start and e.impact and (e.impact-e.start).Magnitude>.001 then
  local r,g,b,a=ui.get(tint)
  renderer.tracer(e.start,e.impact,{color={r,g,b,a},width=2,end_width=.5,life=.8,fade=.3,glow=1})
 end
 if (e.victim or 0)>0 and (e.damage or 0)>0 then
  add(string.format('%s / %s / %d dmg / %d hp%s',
   entity.get_name(e.victim) or ('#'..e.victim),groups[e.group] or 'body',e.damage,e.remainingHealth or 0,if e.killed then ' / kill' else ''),true)
 elseif not extra and (e.aimTarget or 0)>0 then
  add('Miss / '..(reasons[e.missReason or 0] or 'unclassified'),false)
 end
end)
client.set_event_callback('paint',function()
 if not ui.get(enabled) then return end
 local now=globals.realtime();local life=ui.get(duration)
 for i=#rows,1,-1 do if now-rows[i].at>=life then table.remove(rows,i) end end
 if #rows==0 then return end
 local sw,sh=client.screen_size();local x,y=math.floor(sw/2-270),math.floor(sh*.7)
 local r,g,b,a=ui.get(tint)
 for i,row in ipairs(rows) do
  local opacity=math.floor(math.clamp((life-(now-row.at))/.4,0,1)*a)
  renderer.rounded_rectangle(x,y+(i-1)*34,540,30,17,23,28,math.floor(opacity*.9),5)
  renderer.text_ex(x+10,y+5+(i-1)*34,row.text,{font='ui',size=18,color={if row.hit then r else 245,if row.hit then g else 150,if row.hit then b else 110,opacity}})
 end
end)
client.set_event_callback('round_start',function() rows={} end)
