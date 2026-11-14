-- Illusion for Sk1d HVH (written against the official hvh-lua-kit API)
-- Flick anti-aim with presets, Fake flick, manual anti-aim, thirdperson distance,
-- camera lag fix, weapon viewmodel, jumpscout, kill say, resolver, AI peek, edge stop,
-- watermark and hotkeys.
-- Config > Lua: paste, name it "Illusion", Load / reload.
--
-- Settings live in Illusion's own native menu (gui.*): it opens together with the cheat menu.
-- Every bind (manual AA, flick key, AI peek ...) is set right next to its feature there.
--
-- Performance: values are cached, hotkeys are read every frame, everything is drawn from
-- one paint callback, and the camera callback only copies cached numbers.

local function wrap(x) return (x+180)%360-180 end
local now=globals.realtime
local Z={} -- shared constants and state (keeps the main chunk under the local variable limit)

-- Debug overlay: counts how often every callback runs and how long it takes.
-- Turn it on in Settings -> Debug overlay; numbers are per second.
local DBG={on=false,c={},t={},mx={},sec={},at=0,draws=0,clock=nil,pn=nil,pt=0}
do
 local ok,oc=pcall(function() return os.clock end)
 DBG.clock=if ok and type(oc)=='function' then oc else globals.realtime
end
DBG.wrap={}
function DBG.cb(name,fn)
 local w=DBG.wrap[fn]
 if not w then
  w=function(a)
   local c=DBG.c
   c[name]=(c[name] or 0)+1
   if DBG.on then
    local t0=DBG.clock()
    local r=fn(a)
    local d=DBG.clock()-t0
    DBG.t[name]=(DBG.t[name] or 0)+d
    if d>(DBG.mx[name] or 0) then DBG.mx[name]=d end
    return r
   end
   return fn(a)
  end
  DBG.wrap[fn]=w
 end
 return w
end
local function on(name,fn) client.set_event_callback(name,DBG.cb(name,fn)) end
-- time spent in each part of the HUD drawing (only measured while the overlay is on)
function DBG.mark(name)
 if not DBG.on then return end
 local c=DBG.clock()
 if DBG.pn then DBG.sec[DBG.pn]=(DBG.sec[DBG.pn] or 0)+(c-DBG.pt) end
 DBG.pn=name;DBG.pt=c
end

-- entity.get / get_local_state return full COPIES (with animation layers), which is costly.
-- Every part of the script shares one copy per frame instead of making its own.
local FC={frame=nil,ls=nil,ent={}}
Z.HAS_FC=pcall(globals.framecount)
local frameId=if Z.HAS_FC then globals.framecount else now
local function fcCheck()
 local f=frameId()
 if FC.frame~=f then FC.frame=f;FC.ls=nil;FC.ent={} end
end
local function getLS()
 fcCheck()
 if FC.ls==nil then FC.ls=entity.get_local_state() or false end
 return FC.ls or nil
end
-- Draw budget: the game allows 384 primitives per frame per script; going over makes things
-- blink. All drawing goes through R, which counts and simply skips what would not fit.
local RR=renderer
local DRAW={n=0,limit=370,fresh=false}
local RF=0 -- render frame number, advanced once per drawn frame
local function drawFrame(limit)
 DRAW.limit=limit
end
local R={}
function R.text(x,y,r,g,b,a,t,sz) if DRAW.n>=DRAW.limit then return end DRAW.n=DRAW.n+1 RR.text(x,y,r,g,b,a,t,sz) end
function R.text_ex(x,y,t,o) if DRAW.n>=DRAW.limit then return end DRAW.n=DRAW.n+1 RR.text_ex(x,y,t,o) end
function R.rectangle(x,y,w,h,r,g,b,a) if DRAW.n>=DRAW.limit then return end DRAW.n=DRAW.n+1 RR.rectangle(x,y,w,h,r,g,b,a) end
function R.rounded_rectangle(x,y,w,h,r,g,b,a,rd) if DRAW.n>=DRAW.limit then return end DRAW.n=DRAW.n+1 RR.rounded_rectangle(x,y,w,h,r,g,b,a,rd) end
function R.gradient(x,y,w,h,r,g,b,a,r2,g2,b2,a2,hz) if DRAW.n>=DRAW.limit then return end DRAW.n=DRAW.n+1 RR.gradient(x,y,w,h,r,g,b,a,r2,g2,b2,a2,hz) end
function R.circle(x,y,rd,r,g,b,a,f) if DRAW.n>=DRAW.limit then return end DRAW.n=DRAW.n+1 RR.circle(x,y,rd,r,g,b,a,f) end
function R.triangle(x1,y1,x2,y2,x3,y3,r,g,b,a,f,th) if DRAW.n+2>DRAW.limit then return end DRAW.n=DRAW.n+2 RR.triangle(x1,y1,x2,y2,x3,y3,r,g,b,a,f,th) end
function R.line(x1,y1,x2,y2,r,g,b,a,th) if DRAW.n>=DRAW.limit then return end DRAW.n=DRAW.n+1 RR.line(x1,y1,x2,y2,r,g,b,a,th) end
function R.texture(id,x,y,w,h,r,g,b,a) if DRAW.n>=DRAW.limit then return end DRAW.n=DRAW.n+1 RR.texture(id,x,y,w,h,r,g,b,a) end
function R.rectangle_outline(x,y,w,h,r,g,b,a,th) if DRAW.n+4>DRAW.limit then return end DRAW.n=DRAW.n+4 RR.rectangle_outline(x,y,w,h,r,g,b,a,th) end
function R.world_line(p1,p2,r,g,b,a,th) if DRAW.n>=DRAW.limit then return end DRAW.n=DRAW.n+1 RR.world_line(p1,p2,r,g,b,a,th) end
function R.polyline(pts,r,g,b,a,th,cl)
 local c=#pts
 if DRAW.n+c>DRAW.limit then return end
 DRAW.n=DRAW.n+c
 RR.polyline(pts,r,g,b,a,th,cl)
end
function R.arc(x,y,rad,st,sw,r,g,b,a,th,seg)
 local c=seg or 24
 if DRAW.n+c>DRAW.limit then return end
 DRAW.n=DRAW.n+c
 RR.arc(x,y,rad,st,sw,r,g,b,a,th,seg)
end

-- Cheap reads: one number instead of a full player copy (with animation layers).
local function originOf(slot)
 local x,y,z=entity.get_origin(slot)
 if x then return vector.new(x,y,z) end
 return nil
end
local function aliveOf(slot)
 local ok,a=pcall(entity.is_alive,slot)
 return ok and a==true
end
local function propOf(slot,path)
 local ok,v=pcall(entity.get_prop,slot,path)
 if ok then return v end
 return nil
end
-- values read from the game once per drawn frame instead of many times
local FR={t=0,w=1920,h=1080,menu=false,ft=.016,sizeAt=0}
local function frameBegin()
 local t=now()
 FR.t=t
 FR.menu=ui.is_menu_open()==true
 FR.ft=globals.frametime()
 if t>=FR.sizeAt then FR.sizeAt=t+1;FR.w,FR.h=client.screen_size() end
end
local ME={air=false,hp=100} -- filled from cheap sources, see anti_aim and net_update_end
-- alive enemy slots, refreshed 5x a second
local EN={list={},at=0}
local function enemies()
 local t=now()
 if t>=EN.at then
  EN.at=t+.2
  local l={}
  for _,slot in ipairs(entity.get_players(true)) do if aliveOf(slot) then l[#l+1]=slot end end
  EN.list=l
 end
 return EN.list
end

local function getEnt(slot)
 if slot==nil then return nil end
 fcCheck()
 local e=FC.ent[slot]
 if e==nil then e=entity.get(slot) or false;FC.ent[slot]=e end
 return e or nil
end

Z.OWNER='tipcrt' -- shown in the Credits tab

---------------------------------------------------------------- presets
local PRESETS={
 {name='Classic flick',     pitch=2,yaw=0,jl=-20,jr=20,jd=2,body=58,bside=1,auto=true, when=1,fside=1,angle=90, fpitch=1,every=12,hold=1,rand=0},
 {name='Fast flick',        pitch=2,yaw=0,jl=-15,jr=15,jd=1,body=58,bside=1,auto=true, when=1,fside=4,angle=120,fpitch=1,every=6, hold=1,rand=2},
 {name='Heavy 180',         pitch=2,yaw=0,jl=-10,jr=10,jd=4,body=58,bside=4,auto=true, when=1,fside=5,angle=180,fpitch=2,every=20,hold=2,rand=0},
 {name='Air flick',         pitch=2,yaw=0,jl=-18,jr=18,jd=2,body=50,bside=1,auto=true, when=5,fside=1,angle=135,fpitch=2,every=6, hold=1,rand=1},
 {name='Chaos',             pitch=2,yaw=0,jl=-25,jr=25,jd=2,body=58,bside=1,auto=true, when=1,fside=4,angle=100,fpitch=1,every=8, hold=1,rand=6},
 {name='Static + key flick',pitch=2,yaw=0,jl=0,  jr=0, jd=1,body=58,bside=2,auto=false,when=1,fside=1,angle=90, fpitch=1,every=4, hold=2,rand=0},
}
local cur=PRESETS[1]
local presetNames={}
for i,p in ipairs(PRESETS) do presetNames[i]=p.name end

---------------------------------------------------------------- settings (edited in the Illusion panel)
local OPT={
 pitch={'Off','Down','Zero','Up'},
 bodySide={'Jitter','Left','Right','Opposite flick','Off'},
 fWhen={'Always','Standing','Moving','On ground','In air'},
 fSide={'Alternate','Left','Right','Random','Against jitter'},
 fPitch={'Same as normal','Up','Zero','Down'},
 jsWeapon={'Scout (SSG 08)','All snipers','Any weapon'},
 resMode={'Adaptive','Brute force','Low delta','Public feet','Smart (game data)'},
 presetSel=presetNames,
}
local S={} -- current values (declared early: the panel layout below refers to it)
local DEF={
 aaOn=true,pitch=2,yawAdd=0,jLeft=-20,jRight=20,jDelay=2,bodyAmt=58,bodySide=1,presetSel=1,
 fAuto=true,fWhen=1,fSide=1,fAngle=90,fPitch=1,fEvery=12,fHold=1,
 ffOn=false,ffDesync=3,ffRand=0,ffChoke=10,ffLFlick=111,ffLReal=105,ffRFlick=-139,ffRReal=-26,
 tpDist=47,lagOn=true,vmX=-3,vmY=1,vmZ=4,vmFov=108,
 jsOn=true,jsHC=59,jsWeapon=1,resOn=true,resMode=4,apDist=72,apDmg=25,
 wmOn=true,hkOn=true,ksText='',menuTheme='Crimson',hideBuiltin=false,
 -- rage rules
 rrHead=true,rrLethal=false,rrBodyHP=0,rrSafe=2,
 -- effects
 hlOn=true,hlTime=4,trOn=true,trStyle=1,trWidth=2,trLife=1,trColor=1,trMiss=true,
 fxOn=true,fxType=4,fxColor=1,fxDmg=true,fxLight=false,
 -- settings
 colSync=true,bgAlpha=92,theme=1,logoOn=true,perfMode=true,dbgOn=false,hkStyle=1,
 dmgInd=true,bombOn=true,streakOn=true,
 aaFree=false,aaAB=false,aaBackstab=true,aaUse=true,swSpeed=40,
 arrowsOn=true,hmOn=true,kfOn=true,toastOn=true,statsOn=false,
 chOn=false,chSize=6,chGap=3,chThick=2,chDot=true,
 impOn=true,impLife=2,tpSmooth=true,
 kfxOn=true,kfxType=1,lowHpOn=true,lowHpAt=35,spOn=false,spFight=2,spCalm=1,
}
for _,k in ipairs({'colMenu','colHk','colWm','colInd','colHl'}) do DEF[k]={120,200,255} end
DEF.colUI={255,34,75} -- menu accent (pink-red)
Z.ST_NAMES={'Standing','Moving','Air','Crouch'}
OPT.hkStyle={'Panel + squares','Panel only','Squares only'}
OPT.rrSafe={'Cheat setting','Off for head'}
OPT.kfxType={'Soul','Soul + rings','Light pillar','Ring blast'}
OPT.spFight=presetNames
OPT.spCalm=presetNames
OPT.theme={'Dark','Glass','Neon'}
OPT.menuTheme={'default','gamesense','neverlose'}
pcall(function()
 local list=gui.themes()
 if type(list)=='table' and #list>0 then OPT.menuTheme=list end
end)
do -- Illusion's own style first
 local list={'Crimson'}
 for _,n in ipairs(OPT.menuTheme) do if n~='Crimson' then list[#list+1]=n end end
 OPT.menuTheme=list
end
OPT.ffDesync={'Anti-brute','Jitter','Static'}
OPT.trColor={'Accent','White','Red','Green','Purple'}
OPT.fxType={'Shockwave','Sparks','Glow orb','Shockwave + sparks','Everything'}
OPT.trStyle={'Glow beam','Thin line','Laser'}
OPT.fxColor=OPT.trColor
for i=1,4 do
 DEF['st'..i..'_on']=false;DEF['st'..i..'_pitch']=2;DEF['st'..i..'_yaw']=0
 DEF['st'..i..'_jl']=-20;DEF['st'..i..'_jr']=20;DEF['st'..i..'_jd']=2
 DEF['st'..i..'_body']=58;DEF['st'..i..'_bside']=1
 OPT['st'..i..'_pitch']=OPT.pitch;OPT['st'..i..'_bside']=OPT.bodySide
end

-- Menu layout: tabs -> groups -> items. Items: {'check',key,label} {'slider',key,label,min,max,suffix}
-- {'combo',key,label} {'color',key,label} {'text',key,label} {'bind',key,label,defaultKey,mode}
-- {'button',action,label} {'label',text}
local function stGroup(i)
 local p='st'..i..'_'
 return {title=Z.ST_NAMES[i],side=if i%2==1 then 'left' else 'right',items={
  {'check',p..'on','Own settings'},{'combo',p..'pitch','Pitch'},{'slider',p..'yaw','Yaw offset',-180,180,''},
  {'slider',p..'jl','Jitter left',-90,90,''},{'slider',p..'jr','Jitter right',-90,90,''},
  {'slider',p..'jd','Jitter delay',1,32,' pk'},{'slider',p..'body','Body yaw',0,58,''},{'combo',p..'bside','Body side'}}}
end
local LAYOUT={
 {name='Anti-aim',groups={
  {title='Anti-aim',side='left',items={
   {'check','aaOn','Enable anti-aim'},{'combo','pitch','Pitch'},{'slider','yawAdd','Yaw offset',-180,180,''},
   {'slider','jLeft','Jitter left',-90,90,''},{'slider','jRight','Jitter right',-90,90,''},
   {'slider','jDelay','Jitter delay',1,32,' pk'},{'slider','bodyAmt','Body yaw',0,58,''},{'combo','bodySide','Body side'}}},
  {title='Manual',side='right',items={
   {'bind','mLeft','Manual left','Z','Toggle'},{'bind','mRight','Manual right','C','Toggle'},
   {'bind','mBack','Manual backward','None','Toggle'},{'bind','mFwd','Manual forward','None','Toggle'}}},
  {title='Smart AA',side='right',items={
   {'check','aaFree','Freestanding'},{'check','aaAB','Anti-brute'},{'check','aaBackstab','Anti-backstab'},
   {'check','aaUse','Disable on use (E)'}}},
  {title='Presets',side='left',items={
   {'combo','presetSel','Preset'},{'button','loadPreset','Load preset'},{'check','spOn','Smart presets'},
   {'combo','spFight','In a fight'},{'combo','spCalm','When calm'}}},
 }},
 {name='States',groups={stGroup(1),stGroup(2),stGroup(3),stGroup(4),
  {title='Info',side='left',items={{'label','States without "Own settings" use the Anti-aim tab.'}}}}},
 {name='Flicks',groups={
  {title='Flicks',side='left',items={
   {'check','fAuto','Auto flick'},{'bind','fKey','Flick','None','Hold'},{'combo','fWhen','Flick when'},
   {'combo','fSide','Flick side'},{'slider','fAngle','Flick angle',0,180,''},{'combo','fPitch','Flick pitch'},
   {'slider','fEvery','Flick every',2,64,' pk'},{'slider','fHold','Flick hold',1,8,' pk'}}},
  {title='Fake flick',side='right',items={
   {'check','ffOn','Fake flick'},{'bind','ffKey','Fake flick side','None','Toggle'},{'combo','ffDesync','Body side'},
   {'slider','ffRand','Flick randomness',0,30,''},{'slider','ffChoke','Max choke',1,14,''},
   {'slider','ffLFlick','Left angle',-180,180,''},{'slider','ffLReal','Left real',-180,180,''},
   {'slider','ffRFlick','Right angle',-180,180,''},{'slider','ffRReal','Right real',-180,180,''}}},
 }},
 {name='Rage',groups={
  {title='Resolver',side='left',items={{'check','resOn','Resolver'},{'combo','resMode','Resolver preset'}}},
  {title='Rage rules',side='left',items={
   {'check','rrHead','Head priority'},{'combo','rrSafe','Safe point'},{'check','rrLethal','Body if body kills'},
   {'slider','rrBodyHP','Body if HP below',0,100,''}}},
  {title='Jumpscout',side='right',items={
   {'check','jsOn','Jumpscout'},{'slider','jsHC','Hitchance in air',0,100,'%'},{'combo','jsWeapon','Weapons'}}},
  {title='AI peek',side='right',items={
   {'bind','apKey','AI peek','LeftAlt','Hold'},{'slider','apDist','Peek distance',24,120,' hu'},
   {'slider','apDmg','Min damage',1,100,''}}},
  {title='Movement',side='left',items={
   {'bind','esKey','Edge stop','LeftAlt','Hold'},{'bind','swKey','Slow walk','None','Hold'},
   {'slider','swSpeed','Slow walk speed',10,100,'%'}}},
 }},
 {name='Visuals',groups={
  {title='Indicators',side='left',items={
   {'check','wmOn','Watermark'},{'check','hkOn','Hotkeys'},{'combo','hkStyle','Hotkeys style'},
   {'check','dmgInd','Damage indicator'},{'check','bombOn','Bomb timer'},
   {'check','hideBuiltin','Hide cheat DT / duck text'}}},
  {title='Camera',side='right',items={
   {'slider','tpDist','Thirdperson distance',0,240,' hu'},{'check','lagOn','No camera lag'},
   {'check','tpSmooth','Smooth thirdperson'}}},
  {title='Weapon',side='right',items={
   {'slider','vmX','Weapon X',-48,48,''},{'slider','vmY','Weapon Y',-48,48,''},
   {'slider','vmZ','Weapon Z',-48,48,''},{'slider','vmFov','Weapon FOV',40,140,''}}},
 }},
 {name='HUD',groups={
  {title='HUD',side='left',items={
   {'check','arrowsOn','Off-screen arrows'},{'check','hmOn','Hit marker'},{'check','kfOn','Kill feed'},
   {'check','toastOn','Notifications'},{'check','statsOn','Stats panel'},{'check','lowHpOn','Low HP warning'},
   {'slider','lowHpAt','Warn below',10,80,' HP'}}},
  {title='Crosshair',side='right',items={
   {'check','chOn','Custom crosshair'},{'slider','chSize','Size',2,20,''},{'slider','chGap','Gap',0,12,''},
   {'slider','chThick','Thickness',1,4,''},{'check','chDot','Center dot'}}},
 }},
 {name='Effects',groups={
  {title='Hit log',side='left',items={
   {'check','hlOn','Hit log'},{'slider','hlTime','Log time',1,10,' s'},{'check','streakOn','Kill streak'}}},
  {title='Tracers',side='right',items={
   {'check','trOn','Tracers'},{'combo','trStyle','Tracer style'},{'combo','trColor','Tracer color'},
   {'slider','trWidth','Tracer width',1,8,' hu'},{'slider','trLife','Tracer life',1,10,' s'},{'check','trMiss','Red on miss'}}},
  {title='Hit effects',side='left',items={
   {'check','fxOn','Hit effect'},{'combo','fxType','Effect'},{'combo','fxColor','Effect color'},
   {'check','fxLight','Flash of light'},{'check','fxDmg','Damage numbers'}}},
  {title='Impacts & kills',side='right',items={
   {'check','impOn','Impact boxes'},{'slider','impLife','Impact time',1,5,' s'},
   {'check','kfxOn','Kill effect'},{'combo','kfxType','Kill effect style'}}},
  {title='Kill say',side='left',items={
   {'text','ksText','Text ({name} = player)'},{'label','Shown on your screen after a kill.'}}},
 }},
 {name='Settings',groups={
  {title='Colors',side='left',items={
   {'check','colSync','One color for all HUD'},{'color','colMenu','HUD accent'},{'color','colHk','Hotkeys'},
   {'color','colWm','Watermark'},{'color','colInd','Crosshair indicator'},{'color','colHl','Hit log'}}},
  {title='Look',side='right',items={
   {'tcombo','menuTheme','Menu style'},{'color','colUI','Menu accent'},{'combo','theme','HUD style'},{'slider','bgAlpha','HUD opacity',40,100,'%'},
   {'check','logoOn','Logo in watermark'},{'check','perfMode','Performance mode'},{'check','dbgOn','Debug overlay'}}},
 }},
 {name='Credits',groups={
  {title='Illusion',side='left',items={
   {'label','ILLUSION  -  Lua for Sk1d HVH'},{'label','Owner: '..Z.OWNER},
   {'label','Anti-aim, flicks, rage tools and visuals'},{'label','built on the official Sk1d HVH Lua API.'},
   {'label','Thanks for using Illusion!'}}},
 }},
}

for k,v in pairs(DEF) do S[k]=v end
local saved=storage.get('ui')
if type(saved)=='table' then
 for k,v in pairs(DEF) do
  if type(saved[k])==type(v) then S[k]=saved[k] end
 end
end
S.ffOn=false -- Fake flick always starts off, even if it was on before a reload
Z.VER=storage.get('ui_ver')
if type(Z.VER)~='number' then Z.VER=0 end
if Z.VER<2 then -- new rage defaults: head first
 S.rrHead=true;S.rrLethal=false;S.rrSafe=2
end
if Z.VER<3 then -- lighter defaults
 S.perfMode=true;S.statsOn=false
 storage.set('ui_ver',3)
end
if Z.VER<4 then -- the menu got a new look
 S.menuTheme='Crimson';S.colUI={255,34,75}
 storage.set('ui_ver',4)
end
local uiDirty=false

---------------------------------------------------------------- binds (created in the menu, see buildMenu)
local K={} -- gui keybind elements: fKey, ffKey, apKey, esKey, swKey
-- Press a key to turn the anti-aim that way, press it again to go back to normal.
local MANUAL={
 {name='LEFT',yaw=90,bind='mLeft'},{name='RIGHT',yaw=-90,bind='mRight'},
 {name='BACKWARD',yaw=180,bind='mBack'},{name='FORWARD',yaw=0,bind='mFwd'},
}

---------------------------------------------------------------- settings cache
local KS={}    -- cached hotkey states
local VM={x=nil,y=nil,z=nil,vec=nil} -- cached viewmodel vector
local RRON=false -- any rage rule active (set in refresh)
local ANYSTATE=false -- any per-state anti-aim enabled (set in refresh)
local function refresh()
 RRON=S.rrLethal or (S.rrBodyHP or 0)>0
 ANYSTATE=S.st1_on or S.st2_on or S.st3_on or S.st4_on
 if VM.x~=S.vmX or VM.y~=S.vmY or VM.z~=S.vmZ then
  VM.x,VM.y,VM.z=S.vmX,S.vmY,S.vmZ
  VM.vec=vector.new(S.vmX or 0,S.vmY or 0,S.vmZ or 0)
 end
end

local function applyPreset(i)
 local p=PRESETS[i]
 if not p then return end
 cur=p
 S.presetSel=i;S.aaOn=true
 S.pitch=p.pitch;S.yawAdd=p.yaw;S.jLeft=p.jl;S.jRight=p.jr;S.jDelay=p.jd
 S.bodyAmt=p.body;S.bodySide=p.bside
 S.fAuto=p.auto;S.fWhen=p.when;S.fSide=p.fside;S.fAngle=p.angle;S.fPitch=p.fpitch
 S.fEvery=p.every;S.fHold=p.hold
 uiDirty=true;Z.presetStale=true -- the menu shows the new values the next time it is open
end
Z.PKEYS={'presetSel','aaOn','pitch','yawAdd','jLeft','jRight','jDelay','bodyAmt','bodySide',
 'fAuto','fWhen','fSide','fAngle','fPitch','fEvery','fHold'}
cur=PRESETS[S.presetSel] or cur
refresh()

---------------------------------------------------------------- manual anti-aim state
local manual=nil
local manualPrev={}
local function readKeys()
 for k,el in pairs(K) do KS[k]=el:get()==true end
 for i,m in ipairs(MANUAL) do
  local on=m.key~=nil and m.key:get()==true
  if manualPrev[i]~=nil and on~=manualPrev[i] then
   -- Toggle binds: every key press (on or off) picks that side, or clears it when it is already
   -- the active one - so left / right / left works without pressing a key twice.
   -- Hold binds: active while held.
   local hold=false
   if not on then
    local ok,_,mode=pcall(m.key.get_key,m.key)
    hold=ok and string.find(tostring(mode or ''),'Hold',1,true)~=nil
   end
   if hold then
    if manual==m then manual=nil end
   elseif manual==m then manual=nil
   else manual=m end
  end
  manualPrev[i]=on
 end
end
-- SMART.abs: absolute yaw from freestanding / anti-backstab (filled 10x a second, see below)
local SMART={abs=nil,why=nil}
-- "Disable on use": while you hold the use key (E) the anti-aim steps aside, so you look
-- where you aim (doors, bomb, pick-ups). Detected from the use button in your command and
-- from the E key itself.
local USE={held=false,bit=nil}
pcall(function() USE.bit=buttons.use or buttons.Use or buttons.IN_USE or buttons.interact end)
Z.E_OK=pcall(client.key_state,'E')
local function useHeld()
 if USE.held then return true end
 return Z.E_OK and client.key_state('E')==true
end
local function baseYaw(cmd)
 if manual then return manual.yaw end
 if SMART.abs and cmd then return wrap(SMART.abs-cmd.view_yaw) end
 return 180
end
readKeys()

---------------------------------------------------------------- cheat camera lag
Z.LAG_KEY='Visuals.CameraMode.cameraLag'
local lagRef=nil
do
 local ok,ref=pcall(ui.reference,Z.LAG_KEY)
 if ok and ref then lagRef=ref end
end
local lagLast=nil
local function updateLag()
 if not lagRef or S.lagOn==lagLast then return end
 lagLast=S.lagOn
 if not S.lagOn then pcall(ui.reset_setting,Z.LAG_KEY);return end
 local ok,v=pcall(ui.get,lagRef)
 if not ok then return end
 if type(v)=='boolean' then pcall(ui.set,lagRef,false)
 elseif type(v)=='number' then
  if not pcall(ui.set,lagRef,0) then pcall(ui.set,lagRef,1) end
 end
end

---------------------------------------------------------------- anti-aim
local live={text='',mode='wait',amt=0,side=1,flick=false,err=nil}
local ff={choked=0,abSide=1,flips=0,flipAt=-10,lastPacket=nil,rnd=0}
local aa={packet=nil,count=0,side=1,fcount=999,fnext=12,fleft=0,fside=1}

local function fakeFlick(cmd)
 local phase=if cmd.packet%2==0 then 1 else -1
 local right=KS.ffKey
 -- a new random offset for every new packet, so the flick never repeats exactly
 if cmd.packet~=ff.lastPacket then ff.lastPacket=cmd.packet;ff.rnd=(math.random()*2-1)*(S.ffRand or 0) end
 local flick=(if right then S.ffRFlick else S.ffLFlick)+ff.rnd
 local real =if right then S.ffRReal else S.ffLReal
 local mult =if right then -1 else 1
 cmd.yaw=wrap(cmd.view_yaw+S.yawAdd+real*mult+phase*flick+(baseYaw(cmd)-180))
 cmd.pitch=89
 cmd.desync_amount=S.bodyAmt
 -- body side: anti-brute keeps one side and switches it every time an enemy shoots at you,
 -- so a resolver that just learned your side is wrong again on the next shot
 local dm=S.ffDesync
 local dside=if dm==1 then ff.abSide*mult elseif dm==2 then phase*mult else mult
 cmd.desync_side=dside
 local limit=S.ffChoke
 if phase>0 then
  cmd.send_packet=true;cmd.choke=0;ff.choked=0
 else
  ff.choked=ff.choked+1
  if ff.choked>=limit then cmd.send_packet=true;cmd.choke=0;ff.choked=0
  else cmd.send_packet=false;cmd.choke=limit end
 end
 live.mode='fake';live.amt=S.bodyAmt;live.side=dside;live.flick=false;live.ffRight=right;live.choke=ff.choked/math.max(limit,1)
end

-- Which state are we in, and does it have its own settings? (1 Standing, 2 Moving, 3 Air, 4 Crouch)
local AAV={}
Z.ST_K={}
for i=1,4 do
 local p='st'..i..'_'
 Z.ST_K[i]={on=p..'on',pitch=p..'pitch',yaw=p..'yaw',jl=p..'jl',jr=p..'jr',jd=p..'jd',body=p..'body',bside=p..'bside'}
end
local function aaValues(cond)
 local i=if cond=='in air' then 3 elseif cond=='moving' then 2 else 1
 if ANYSTATE then -- crouch needs the full state; only read it when a state has its own settings
  local st=getLS()
  local m=st and st.move
  if m and m.onGround~=false and (m.duckAmount or 0)>.5 then i=4 end
 end
 live.state=Z.ST_NAMES[i]
 local k=Z.ST_K[i]
 if S[k.on] then
  AAV.pitch,AAV.yaw,AAV.jl,AAV.jr=S[k.pitch],S[k.yaw],S[k.jl],S[k.jr]
  AAV.jd,AAV.body,AAV.bside=S[k.jd],S[k.body],S[k.bside]
  live.own=true
 else
  AAV.pitch,AAV.yaw,AAV.jl,AAV.jr=S.pitch,S.yawAdd,S.jLeft,S.jRight
  AAV.jd,AAV.body,AAV.bside=S.jDelay,S.bodyAmt,S.bodySide
  live.own=false
 end
 return AAV
end

on('anti_aim',function(cmd)
 local cond=antiaim.get_condition()
 ME.air=cond=='in air'
 if S.aaUse and useHeld() then
  cmd.yaw=cmd.view_yaw
  if cmd.view_pitch then cmd.pitch=cmd.view_pitch end
  cmd.desync_amount=0
  aa.fleft=0
  live.mode='use'
  return
 end
 if S.ffOn then aa.fleft=0;fakeFlick(cmd);return end
 if not S.aaOn then live.mode='off';aa.fleft=0;return end
 local A=aaValues(cond)

 local w=S.fWhen
 local allowed=w==1 or (w==2 and cond=='standing') or (w==3 and cond=='moving')
  or (w==4 and cond~='in air') or (w==5 and cond=='in air')
 local wantFlick=(S.fAuto or KS.fKey) and allowed
 local jl,jr=A.jl,A.jr

 if cmd.packet~=aa.packet then
  aa.packet=cmd.packet
  aa.count=aa.count+1
  if aa.count>=A.jd then aa.count=0;aa.side=-aa.side end
  if aa.fleft>0 then aa.fleft=aa.fleft-1 end
  if wantFlick then
   aa.fcount=aa.fcount+1
   if aa.fleft==0 and aa.fcount>=aa.fnext then
    aa.fcount=0
    aa.fnext=S.fEvery+math.random(0,cur.rand or 0)
    aa.fleft=math.max(1,math.min(S.fHold,aa.fnext-1))
    local fs=S.fSide
    if fs==1 then aa.fside=-aa.fside
    elseif fs==2 then aa.fside=-1
    elseif fs==3 then aa.fside=1
    elseif fs==4 then aa.fside=if math.random(0,1)==0 then -1 else 1
    else
     local j=if aa.side==1 then jl else jr
     aa.fside=if j>=0 then -1 else 1
    end
   end
  else
   aa.fleft=0;aa.fcount=999
  end
 end

 local offset=A.yaw+(if aa.side==1 then jl else jr)
 local flicking=aa.fleft>0
 local pm=A.pitch
 local p=if pm==2 then 89 elseif pm==3 then 0 elseif pm==4 then -89 else nil
 if flicking then
  offset=offset+aa.fside*S.fAngle
  local fp=S.fPitch
  if fp==2 then p=-89 elseif fp==3 then p=0 elseif fp==4 then p=89 end
 end
 if p~=nil then cmd.pitch=p end
 cmd.yaw=wrap(cmd.view_yaw+baseYaw(cmd)+offset)

 local bs=A.bside
 local amt=if bs==5 then 0 else A.body
 local side=if bs==2 then 1 elseif bs==3 then -1 elseif bs==4 then -aa.fside else aa.side
 if S.aaAB then side=ff.abSide end -- anti-brute: one side, switched by enemy shots
 cmd.desync_amount=amt
 cmd.desync_side=side

 live.mode='aa';live.amt=amt;live.side=side;live.flick=flicking
end)

---------------------------------------------------------------- camera & weapon (cached values only)
-- Smooth thirdperson: when the cheat switches thirdperson on, the camera slides out from
-- your head; when it switches off, the script keeps thirdperson a moment longer and slides
-- the camera back in, then hands over to first person.
local TPS={dist=0}
on('player_spawn',function(e)
 if e.slot==entity.get_local_player() then TPS.dist=0 end -- no slide from an old camera after respawn
end)
on('override_view',function(v)
 local want=v.thirdperson==true
 TPS.want=want;TPS.at=now()
 local target=if S.tpDist and S.tpDist>0 then S.tpDist else (v.distance or 100)
 if S.tpSmooth then
  local k=1-math.exp(-math.max(globals.frametime(),.001)*11)
  TPS.dist=TPS.dist+((if want then target else 0)-TPS.dist)*k
  if want or TPS.dist>3 then
   v.thirdperson=true
   v.distance=TPS.dist
   v.collision=true
  end
 else
  TPS.dist=if want then target else 0
  if want and S.tpDist and S.tpDist>0 then v.distance=S.tpDist;v.collision=true end
 end
 if VM.vec then v.viewmodel_offset=VM.vec end
 if S.vmFov then v.viewmodel_fov=S.vmFov end
end)

---------------------------------------------------------------- jumpscout
local js={active=false,weapon='?'}
local function weaponAllowed(name)
 local mode=S.jsWeapon
 if mode==3 or name=='' then return true end
 local scout=string.find(name,'ssg',1,true) or string.find(name,'scout',1,true)
 if mode==1 then return scout~=nil end
 return scout~=nil or string.find(name,'awp',1,true)~=nil or string.find(name,'scar',1,true)~=nil
  or string.find(name,'g3sg1',1,true)~=nil or string.find(name,'auto',1,true)~=nil
end
local function inAir() return ME.air end

---------------------------------------------------------------- kill say (on your screen; the API has no chat)
local ks={text='',till=0}
local function replaceName(t,name)
 local out,i='',1
 while true do
  local a,b=string.find(t,'{name}',i,true)
  if not a then return out..string.sub(t,i) end
  out=out..string.sub(t,i,a-1)..name;i=b+1
 end
end
on('player_hurt',function(e)
 local text=tostring(S.ksText or '')
 local me=entity.get_local_player()
 if text=='' or not e.killed or (e.attacker~=me and e.shooter~=me) then return end
 local msg=replaceName(text,entity.get_name(e.slot) or ('#'..tostring(e.slot)))
 if msg~='' then ks.text=msg;ks.till=now()+3 end
end)

---------------------------------------------------------------- resolver
-- The real enemy angle is server-only: this is a learning guess, graded by real miss reasons.
Z.SIDES={{k='left',f=1},{k='right',f=-1},{k='center',f=0},{k='half left',f=.5},{k='half right',f=-.5}}
Z.LOW={{k='half left',f=.5},{k='half right',f=-.5},{k='low left',f=.25},{k='low right',f=-.25},{k='center',f=0}}
Z.BRUTE={1,-1,0,.5,-.5}
Z.BRUTE_KEYS={'brute 1','brute 2','brute 3','brute 4','brute 5'}
local res={players={},pending={},hits=0,misses=0,last='waiting for a target'}

local function rec(slot)
 local r=res.players[slot]
 if not r then r={hist={},stats={},brute=1,cur=nil,tick=nil,jb=nil};res.players[slot]=r end
 return r
end
-- computed once per new snapshot, not on every resolve call
local function jitterBase(h)
 if #h<6 then return nil end
 local flips,prev,x,y=0,nil,0,0
 for i=1,#h do
  x=x+math.cos(math.rad(h[i]));y=y+math.sin(math.rad(h[i]))
  if i>1 then
   local d=wrap(h[i]-h[i-1])
   if math.abs(d)>12 then
    local sgn=if d>0 then 1 else -1
    if prev and sgn~=prev then flips=flips+1 end
    prev=sgn
   end
  end
 end
 if flips<3 or math.sqrt(x*x+y*y)/#h<.2 then return nil end
 return math.deg(math.atan2(y,x))
end
local function bestSide(r,list)
 local best,score=list[1],-math.huge
 for i,c in ipairs(list) do
  local st=r.stats[c.k]
  local v=if st then (st.h+1)/(st.h+st.m+2)-i*.001 else .5-i*.001
  if v>score then best,score=c,v end
 end
 return best
end

-- One net_update_end callback: resolver history (Adaptive / Low delta only), enemy HP for
-- rage rules, and your own HP. Single values are read, never whole player copies.
local HP={}
local NU={at=0}
on('net_update_end',function()
 local needHist=S.resOn and (S.resMode==1 or S.resMode==3)
 if needHist or RRON then
  for _,slot in ipairs(entity.get_players(true)) do
   local hp=propOf(slot,'health')
   if type(hp)=='number' then HP[slot]=hp end
   if needHist and type(hp)=='number' and hp>0 then
    local tk=propOf(slot,'tick')
    local r=rec(slot)
    if tk~=nil and r.tick~=tk then
     local yw=propOf(slot,'yaw')
     if type(yw)=='number' then
      r.tick=tk
      r.hist[#r.hist+1]=wrap(yw)
      if #r.hist>12 then table.remove(r.hist,1) end
      r.jb=jitterBase(r.hist)
     end
    end
   end
  end
 end
 local me=entity.get_local_player()
 if me then local h=propOf(me,'health');if type(h)=='number' then ME.hp=h end end
 local t=now()
 if t>=NU.at then
  NU.at=t+2
  for id,p in pairs(res.pending) do if t-p.at>8 then res.pending[id]=nil end end
 end
end)

local function onResolve(t)
 if not S.resOn or not t.yaw or not t.max_desync then return nil end
 local bound=math.clamp(t.max_desync,0,58)
 local r=rec(t.slot)
 local mode=S.resMode
 if mode==5 then
  -- Smart: uses what the game itself knows about the target.
  --  * a player who does not choke shows his real feet -> take them, and say we are sure
  --  * the tick he fired on his anti-aim was off -> leave it to the built-in resolver
  --  * otherwise the built-in guess first; after a resolver miss its mirror, then the middle
  local okT,trust=pcall(resolver.trusts_public,t.slot,t.tick)
  if okT and trust and t.foot_yaw then
   r.cur='public';res.lslot,res.llabel,res.lval=t.slot,'public',wrap(t.foot_yaw-t.yaw)
   return {foot=t.foot_yaw,confident=true}
  end
  local okF,fired=pcall(resolver.fired_at,t.slot,t.tick)
  if okF and fired then r.cur=nil;res.lslot,res.llabel,res.lval=t.slot,'shot',0;return nil end
  local step=(r.brute-1)%3
  if step==0 then
   r.cur='built-in';res.lslot,res.llabel,res.lval=t.slot,'built-in',0
   return nil
  end
  local okB,foot=pcall(resolver.get_builtin,t.slot,t.tick)
  if not okB or type(foot)~='number' then foot=t.foot_yaw or t.yaw end
  local d=math.clamp(wrap(foot-t.yaw),-bound,bound)
  if step==1 then
   if math.abs(d)<10 then d=bound end -- built-in said "middle": try a full side
   d=-d;r.cur='mirror'
  else
   d=d*.3;r.cur='middle'
  end
  res.lslot,res.llabel,res.lval=t.slot,r.cur,d
  return {foot=wrap(t.yaw+d),confident=false}
 end
 if mode==4 then
  if not t.foot_yaw then return nil end
  local d=math.clamp(wrap(t.foot_yaw-t.yaw),-bound,bound)
  r.cur='feet'
  res.lslot,res.llabel,res.lval=t.slot,'feet',d
  return wrap(t.yaw+d)
 end
 local base,f,key,label=t.yaw,0,'',''
 if mode==2 then
  local i=((r.brute-1)%#Z.BRUTE)+1
  f=Z.BRUTE[i];key=Z.BRUTE_KEYS[i];label=key
 else
  if r.jb then base=r.jb end
  local c=bestSide(r,if mode==3 then Z.LOW else Z.SIDES)
  f=c.f;key=c.k;label=c.k
 end
 r.cur=key
 res.lslot,res.llabel,res.lval=t.slot,label,f*bound
 return wrap(base+f*bound)
end

local function grade(e,hit)
 local p=e.cmdNumber and res.pending[e.cmdNumber]
 if not p then return end
 res.pending[e.cmdNumber]=nil
 local r=res.players[p.slot]
 if not r then return end
 if hit then res.hits=res.hits+1 else res.misses=res.misses+1 end
 local st=r.stats[p.k] or {h=0,m=0};r.stats[p.k]=st
 if hit then st.h=st.h+1 else st.m=st.m+1;r.brute=r.brute+1 end
 if st.h+st.m>12 then st.h=st.h*.5;st.m=st.m*.5 end
end
on('aim_hit',function(e) if S.resOn then grade(e,true) end end)
on('aim_miss',function(e)
 if not S.resOn then return end
 local reason=string.lower(tostring(e.reason or ''))
 if e.missReason==2 or string.find(reason,'resolver',1,true) then grade(e,false)
 elseif e.cmdNumber then res.pending[e.cmdNumber]=nil end
end)
on('player_disconnect',function(e) if e.slot then res.players[e.slot]=nil end end)

---------------------------------------------------------------- hit log, tracers, hit effects
Z.GROUPS={'head','chest','stomach','arm','leg','neck'}
Z.REASONS={'spread','resolver','occlusion','death','prediction error'}
local HL={} -- {text,hit,at}
local function addLog(text,hit)
 table.insert(HL,1,{text=text,hit=hit,at=now()})
 if #HL>6 then table.remove(HL) end
end
Z.TRC={{120,200,255},{240,240,245},{255,95,95},{120,230,140},{185,130,255}}
Z.MISS_C={255,90,90}

-- One real shot -> one tracer. Styles are built from layered beams:
--  Glow beam: wide soft colored beam + thin bright core
--  Thin line: one thin beam
--  Laser:     very thin bright core that stays sharp, plus a faint halo
local function tracer(a,b,c,hit)
 local life=S.trLife
 local w=S.trWidth
 local fade=math.min(.45,life)
 local st=S.trStyle
 if st==1 then
  renderer.tracer(a,b,{color={c[1],c[2],c[3],200},width=w*1.4,end_width=w*.5,life=life,fade=fade,glow=1})
 elseif st==2 then
  renderer.tracer(a,b,{color={c[1],c[2],c[3],255},width=math.max(.3,w*.5),end_width=math.max(.2,w*.25),life=life,fade=fade,glow=.6})
 else
  renderer.tracer(a,b,{color={c[1],c[2],c[3],70},width=w*1.6,end_width=w*1.6,life=life,fade=fade,glow=1})
  renderer.tracer(a,b,{color={255,255,255,255},width=.35,end_width=.35,life=life,fade=fade,glow=1})
 end
end

on('shot',function(e)
 if e.shooter~=entity.get_local_player() then return end
 local melee=bit.band(e.flags or 0,8)~=0
 local extra=not melee and bit.band(e.flags or 0,32)~=0 -- extra victims of one penetrating bullet
 local hit=(e.victim or 0)>0 and (e.damage or 0)>0
 if S.trOn and not melee and not extra and e.start and e.impact and (e.impact-e.start).Magnitude>.001 then
  local c=if (not hit and S.trMiss and (e.aimTarget or 0)>0) then Z.MISS_C else (Z.TRC[S.trColor] or Z.TRC[1])
  pcall(tracer,e.start,e.impact,c,hit)
 end
 if not S.hlOn then return end
 if hit then
  local name=entity.get_name(e.victim) or ('#'..e.victim)
  addLog('Hit '..name..' in the '..(Z.GROUPS[e.group] or 'body')..' for '..e.damage..
   (if e.killed then '  -  killed' else '  ('..(e.remainingHealth or 0)..' hp left)'),true)
 elseif not extra and (e.aimTarget or 0)>0 then
  local name=entity.get_name(e.aimTarget) or ('#'..e.aimTarget)
  addLog('Missed '..name..' due to '..(Z.REASONS[e.missReason or 0] or 'unknown'),false)
 end
end)

-- Floating damage numbers: created once, then moved up a little every frame.
local DMG={}
local function hitEffect(e)
 local pos=e.impact
 local head=e.group==1
 local c=Z.TRC[S.fxColor] or Z.TRC[1]
 if e.killed then c={255,95,95} elseif head then c={255,205,90} end -- kill red, headshot gold
 local col={c[1],c[2],c[3],255}
 local t=S.fxType
 if t==1 or t==4 or t==5 then
  -- shockwave: three rings that appear one after another and grow outward
  for i,rad in ipairs({7,15}) do
   pcall(renderer.effect,'ring',pos,{radius=rad,width=1.2-i*.25,normal=vector.new(0,1,0),
    color={c[1],c[2],c[3],255-i*50},life=.25+i*.15,fade=.25+i*.1})
  end
 end
 if t==2 or t==4 or t==5 then
  pcall(renderer.effect,'particles',pos,{count=if e.killed then 18 else 10,speed=if e.killed then 240 else 160,
   spread=180,radius=1.6,color=col,life=.8,acceleration=vector.new(0,-500,0)})
 end
 if t==3 or t==5 then
  pcall(renderer.effect,'sphere',pos,{radius=if head then 5 else 3.5,color={c[1],c[2],c[3],200},life=.5,fade=.4,material='neon'})
 end
 if S.fxLight then
  if e.killed then pcall(renderer.effect,'light',pos,{brightness=2,range=50,color=col,life=.3,fade=.25}) end
 end
 if S.fxDmg and e.damage then
  local txt=(if head then 'HS ' else '')..'-'..e.damage
  local ok,id=pcall(renderer.effect,'text',pos+vector.new(0,10,0),{text=txt,text_size=if e.killed then 26 else 22,
   color=col,life=1.1,fade=.5})
  if ok and id then DMG[#DMG+1]={id=id,pos=pos+vector.new(0,10,0),at=now()} end
  if #DMG>8 then table.remove(DMG,1) end
 end
end
on('player_hurt',function(e)
 local me=entity.get_local_player()
 if not S.fxOn or not e.impact or (e.attacker~=me and e.shooter~=me) then return end
 hitEffect(e)
end)
local function floatNumbers(t)
 for i=#DMG,1,-1 do
  local d=DMG[i]
  local age=t-d.at
  if age>1.1 then table.remove(DMG,i)
  else
   local ok,alive=pcall(renderer.update_effect,d.id,{position=d.pos+vector.new(0,age*28,0)})
   if not ok or alive==false then table.remove(DMG,i) end
  end
 end
end

---------------------------------------------------------------- rage rules
-- Adds score to the points rage already found valid; it never invents points or angles.
local function onRagePoint(p)
 local head=p.group==1 or p.hitbox==1
 if not head and (type(p.group)=='string' or type(p.hitbox)=='string') then -- named instead of numbered
  local hn=string.lower(tostring(p.hitbox or ''))..' '..string.lower(tostring(p.group or ''))
  head=string.find(hn,'head',1,true)~=nil
 end
 local hp=HP[p.slot] or 100
 local bodyMode=(S.rrBodyHP>0 and hp<S.rrBodyHP) or (S.rrLethal and (p.damage or 0)>=hp)
 if bodyMode then
  if not head then p.score=(p.score or 0)+2000 end
 elseif S.rrHead and head then
  p.score=(p.score or 0)+2000 -- head first whenever a head point is valid
 end
end

---------------------------------------------------------------- AI peek
local ap={state='off',start=nil,goal=nil,t=0,scanAt=0,enemyIdx=0,info='',lastGoal=nil,prevLen=0,bad=0,arrivedAt=nil}
local CAL={mode=1} -- movement axis self-calibration (8 combinations)

local function viewBasis()
 local _,yaw=client.camera_angles()
 local m=CAL.mode-1
 local ys=if bit.band(m,1)==0 then 1 else -1
 local rs=if bit.band(m,2)==0 then 1 else -1
 local fs=if bit.band(m,4)==0 then 1 else -1
 local r=math.rad((yaw or 0)*ys)
 return vector.new(-math.sin(r),0,-math.cos(r))*fs, vector.new(math.cos(r),0,-math.sin(r))*rs
end
local function asVector(v)
 if v==nil then return nil end
 local ok,x=pcall(function() return v.X end)
 if ok and type(x)=='number' then return v end
 return nil
end
local LO={frame=nil,v=nil,s=nil}
local function localOriginRaw()
 local s=getLS()
 if s then
  local m=s.move
  local v=asVector(m and (m.position or m.origin)) or asVector(s.origin) or asVector(s.position)
  if v then return v,s end
 end
 local me=entity.get_local_player()
 if me then
  local x,y,z=entity.get_origin(me)
  if x then return vector.new(x,y,z),s end
 end
 return nil,s
end
-- localOrigin(): cheap position (2 numbers from the game) for the HUD and other helpers.
-- localOrigin(true): exact predicted position plus the full local state (movement code).
local function localOrigin(wantState)
 if LO.frame~=RF then LO.frame=RF;LO.v=nil;LO.vs=nil;LO.s=nil;LO.done=false end
 if wantState then
  if not LO.done then LO.done=true;LO.vs,LO.s=localOriginRaw() end
  return LO.vs,LO.s
 end
 if not LO.v then
  if LO.done then LO.v=LO.vs
  else
   local me=entity.get_local_player()
   local x,y,z
   if me then x,y,z=entity.get_origin(me) end
   if x then LO.v=vector.new(x,y,z) else LO.done=true;LO.vs,LO.s=localOriginRaw();LO.v=LO.vs end
  end
 end
 return LO.v,nil
end
local function eyeOffset(s)
 return vector.new(0,64-18*((s and s.move and s.move.duckAmount) or 0),0)
end
local function headOf(e)
 local duck=e.duck or 0
 if type(duck)=='boolean' then duck=if duck then 1 else 0 end
 return e.origin+vector.new(0,64-18*duck,0)
end
local function moveTo(cmd,origin,goal)
 local dx,dz=goal.X-origin.X,goal.Z-origin.Z
 local len=math.sqrt(dx*dx+dz*dz)
 if ap.lastGoal~=goal then ap.lastGoal=goal;ap.prevLen=len;ap.bad=0
 else
  if len>ap.prevLen+.3 then ap.bad=ap.bad+1 elseif len<ap.prevLen-.3 then ap.bad=math.max(0,ap.bad-2) end
  ap.prevLen=len
  if ap.bad>=10 then CAL.mode=CAL.mode%8+1;ap.bad=0 end
 end
 if len<4 then cmd.forwardmove=0;cmd.sidemove=0;return true end
 local fwd,right=viewBasis()
 local ux,uz=dx/len,dz/len
 local speed=if len<20 then math.max(45,127*len/20) else 127
 cmd.forwardmove=math.clamp((ux*fwd.X+uz*fwd.Z)*speed,-127,127)
 cmd.sidemove=math.clamp((ux*right.X+uz*right.Z)*speed,-127,127)
 return false
end
local function scan(origin,s)
 local list={}
 for _,slot in ipairs(entity.get_players(true)) do
  local e=getEnt(slot)
  if e and (e.health or 0)>0 and e.origin then list[#list+1]={slot=slot,e=e,d=(e.origin-origin).Magnitude} end
 end
 if #list==0 then return nil,'no enemies' end
 table.sort(list,function(a,b) return a.d<b.d end)
 ap.enemyIdx=ap.enemyIdx%math.min(#list,2)+1
 local en=list[ap.enemyIdx]
 local eye=eyeOffset(s)
 local head=headOf(en.e)
 local minDmg=S.apDmg
 local here=client.trace_bullet(en.slot,origin+eye,head)
 if here and (here.damage or 0)>=minDmg then return nil,'enemy already hittable' end
 local _,right=viewBasis()
 local maxD=S.apDist
 local best=nil
 for _,side in ipairs({1,-1}) do
  local tr=client.trace_line(origin+eye,origin+right*(side*maxD)+eye)
  local free=maxD
  if tr and tr.hit then free=maxD*(tr.fraction or 0)-16 end
  for _,k in ipairs({.5,1}) do
   local dist=maxD*k
   if dist<=free then
    local p=origin+right*(side*dist)
    local r=client.trace_bullet(en.slot,p+eye,head)
    local dmg=(r and r.damage) or 0
    if dmg>=minDmg then
     local score=dmg*(if dmg>=(en.e.health or 100) then 2 else 1)-dist*.5
     if not best or score>best.score then
      best={goal=p,side=side,dist=dist,dmg=dmg,score=score,name=entity.get_name(en.slot) or ('#'..en.slot)}
     end
     break
    end
   end
  end
 end
 if not best then return nil,'no peek spot' end
 return best
end
local function apTick(cmd)
 if not KS.apKey then ap.state='off';ap.start=nil;ap.goal=nil;return end
 local origin,s=localOrigin(true)
 if not origin then ap.info='no position';return end
 if s and s.move and s.move.onGround==false then ap.info='in air';return end
 local t=now()
 local userMoving=math.abs(cmd.forwardmove or 0)>1 or math.abs(cmd.sidemove or 0)>1
 if ap.state=='off' then ap.state='scan';ap.start=origin;ap.scanAt=0 end
 if ap.state=='scan' then
  if userMoving then ap.start=origin;ap.info='you are moving' return end
  moveTo(cmd,origin,ap.start)
  if t>=ap.scanAt then
   ap.scanAt=t+.1
   local best,why=scan(origin,s)
   if best then
    ap.state='peek';ap.goal=best.goal;ap.t=t
    ap.info=(if best.side>0 then 'right ' else 'left ')..math.floor(best.dist)..' -> '..best.name..' '..math.floor(best.dmg)..' dmg'
   else ap.info=why end
  end
 elseif ap.state=='peek' then
  if moveTo(cmd,origin,ap.goal) and ap.arrivedAt==nil then ap.arrivedAt=t end
  if (ap.arrivedAt and t-ap.arrivedAt>.2) or t-ap.t>.7 then ap.state='return';ap.t=t;ap.arrivedAt=nil end
 elseif ap.state=='return' then
  if moveTo(cmd,origin,ap.start) or t-ap.t>2 then ap.state='scan';ap.scanAt=t+.15;ap.arrivedAt=nil end
 end
end
---------------------------------------------------------------- edge stop
-- Looks a little ahead of where you are going (by input and by current speed) and checks
-- with a downward trace whether there is still floor there. No floor within a step
-- height (18 hu) = ledge: movement input is cancelled so friction stops you at the edge.
local es={active=false,prev=nil,prevT=0,vx=0,vz=0}
Z.JUMP=nil
pcall(function() Z.JUMP=buttons.jump or buttons.Jump or buttons.IN_JUMP end)
Z.STEP=18
-- distance from p down to the floor (nil = no floor within 120 hu)
local function dropBelow(p)
 local tr=client.trace_line(p+vector.new(0,8,0),p-vector.new(0,120,0))
 if tr and tr.hit then return (tr.fraction or 0)*128-8 end
 return nil
end
local function edgeTick(cmd)
 es.active=false
 local fm,sm=cmd.forwardmove or 0,cmd.sidemove or 0
 if math.abs(fm)<1 and math.abs(sm)<1 then return end
 if Z.JUMP and cmd.buttons and bit.band(cmd.buttons,Z.JUMP)~=0 then return end -- jumping on purpose
 local origin,s=localOrigin(true)
 if not origin or not s or not s.move or s.move.onGround==false then return end
 -- own speed estimate in hu/s from position changes (does not depend on the game's velocity units)
 local t=now()
 if es.prev and t-es.prevT>.005 and t-es.prevT<.5 then
  local dt=t-es.prevT
  local vx,vz=(origin.X-es.prev.X)/dt,(origin.Z-es.prev.Z)/dt
  if math.abs(vx)<1500 and math.abs(vz)<1500 then
   es.vx=(es.vx or 0)+(vx-(es.vx or 0))*.35
   es.vz=(es.vz or 0)+(vz-(es.vz or 0))*.35
  end
 end
 if not es.prev or t-es.prevT>.005 then es.prev=origin;es.prevT=t end
 local vel=vector.new(es.vx or 0,0,es.vz or 0)
 local speed=math.sqrt(vel.X*vel.X+vel.Z*vel.Z)
 local reach=16+speed*.12 -- half the body + the distance needed to stop
 -- measure the floor under yourself first, so it works wherever the game puts the origin
 local here=dropBelow(origin)
 if not here then return end
 local function ledge(p) local d=dropBelow(p);return d==nil or d>here+Z.STEP end
 -- direction you want to go (from your keys)
 local fwd,right=viewBasis()
 local wx,wz=fwd.X*fm+right.X*sm,fwd.Z*fm+right.Z*sm
 local wl=math.sqrt(wx*wx+wz*wz)
 local over=false
 if wl>0 then
  over=ledge(origin+vector.new(wx/wl*reach,0,wz/wl*reach))
 end
 -- direction you are actually sliding
 if not over and speed>30 then
  over=ledge(origin+vector.new(vel.X/speed*reach,0,vel.Z/speed*reach))
 end
 if over then cmd.forwardmove=0;cmd.sidemove=0;es.active=true end
end

on('setup_command',function(cmd)
 USE.held=USE.bit~=nil and cmd.buttons~=nil and bit.band(cmd.buttons,USE.bit)~=0
 if KS.apKey or ap.state~='off' then
  local ok,err=pcall(apTick,cmd)
  if not ok then ap.state='off';ap.info='error: '..tostring(err) end
 end
 if KS.esKey then
  local ok=pcall(edgeTick,cmd)
  if not ok then es.active=false end
 end
 -- slow walk: scale your own movement (not while AI peek is moving you)
 if KS.swKey and ap.state~='peek' and ap.state~='return' then
  local f=S.swSpeed/100
  cmd.forwardmove=(cmd.forwardmove or 0)*f
  cmd.sidemove=(cmd.sidemove or 0)*f
 end
end)
on('aim_fire',function(e)
 if ap.state=='peek' then ap.state='return';ap.t=now();ap.arrivedAt=nil end
 if S.resOn and e.cmdNumber then
  local r=res.players[e.target]
  if r and r.cur then res.pending[e.cmdNumber]={slot=e.target,k=r.cur,at=now()} end
 end
end)

---------------------------------------------------------------- colors
local function hsv2rgb(h,sat,v)
 sat=(sat or 0)/100;v=(v or 0)/100
 local c=v*sat
 local hp=((h or 0)%360)/60
 local x=c*(1-math.abs(hp%2-1))
 local r,g,b=0,0,0
 if hp<1 then r,g,b=c,x,0 elseif hp<2 then r,g,b=x,c,0 elseif hp<3 then r,g,b=0,c,x
 elseif hp<4 then r,g,b=0,x,c elseif hp<5 then r,g,b=x,0,c else r,g,b=c,0,x end
 local m=v-c
 return math.floor((r+m)*255+.5),math.floor((g+m)*255+.5),math.floor((b+m)*255+.5)
end
-- colors are kept as {r,g,b}; older saves used hue/saturation/value numbers
for _,k in ipairs({'colMenu','colHk','colWm','colInd','colHl','colUI'}) do
 local c=S[k]
 if type(saved)=='table' and type(saved[k..'H'])=='number' and type(saved[k])~='table' then
  S[k]={hsv2rgb(saved[k..'H'],saved[k..'S'],saved[k..'V'])};uiDirty=true
 elseif type(c)~='table' or type(c[1])~='number' or type(c[2])~='number' or type(c[3])~='number' then
  S[k]={DEF[k][1],DEF[k][2],DEF[k][3]}
 end
end
local function colorOf(which)
 local c=if S.colSync then S.colMenu else S[which]
 return c[1],c[2],c[3]
end
-- the HUD colors, refreshed with the settings instead of converted several times per frame
local COL={ind={120,200,255},hk={120,200,255},wm={120,200,255},hl={120,200,255}}
local function refreshColors()
 COL.ind={colorOf('colInd')};COL.hk={colorOf('colHk')};COL.wm={colorOf('colWm')};COL.hl={colorOf('colHl')}
end
local function bgA(a) return math.floor(a*(S.bgAlpha or 100)/100) end

-- Built-in logo: a white PNG (64x64) embedded in the script, tinted with the accent color.
local LOGO=nil
pcall(function()
 LOGO=renderer.load_png_base64('iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAADP0lEQVR42uWbPW/UQBCGZ32nRHQ5iIREhQQNBULKR0OBkPgb0CUR/CZ+BwUFPQRQ6CipUpGQIBDSJc49NHswLF7b6/P5vOtt7DvfrPO8F8/OvKsTWeEAMiCTIQ7AaCGGBp/Z4y1gy56PhwY/AT4Bv4CdQYjgwB/yd3wDdpMWwQN/CVwlL0IJPMAsaREq4ElahBL4mYL+Yd+/SkqECvjcvn4K3AfOkhKhJvy++vyuBY5fhBB4YDwHS0KEUHgVF78ITeGTEGFR+IYiZNHDA8YFqSHCKfCkKDY6eF877BEhVwXUgUqiWYzwle2wI8Kpqhr37PujlfkJLcFXtsNKhG3gGHhuX6+tzE9oEb5WO6xibjiiTICjTv2EJcDXaodV7Mgmv03gXad+wpLgUVm+dJmzBurIJr439vPTTuqEJcOjsvx8mSsTwQCPgJNOiqWO4HGufQduWljjmXP5FWPH8NoUeWH/1UdFewedlM0rgHfnHBXN2YkIPYBft8cN4BXwsEax1I4IPYKfAG/tta8lS2R7IvQM/lAtdVV1wuIi9BT+0lkilyPCfKmxz5wPoLSrq4hdBD6kWNIinFVY7pnuyQ1wG/jo3PwK+Ak8K+nnfbFtwrsieD0BJcIW8MWx4P+LzURkXmhsisg9e56JCPbaVESOPGnDF1v4lInITERGInJgjHkJrBtjpsBERF6LyK6I5CIyLrlfLiLXReSOMQb1N8zHzB4/i8iJureOvftPrHqGt53nZ2bPz2s0Km5sm9+8O8eer1RWc35wOEpj/xQeTZKIJzZfEnxIIs6DfMlFMqknVre7XcMHm7Jti3BasIL0G75lEVwbKw74lkQos7H6D9+yCEU2Vv/h29itKbGx4oAP3K0JsbHyaOBriJAvYGPFAV9jrV/ExooD3gNy7tuuCrCxLqKBLwB5rDYq1xrYWK6A/Ycv+nYV1EagjaUFjAfeyfDjAk9gWrdOqNHV9RO+YJnbsRuVQcWSL29EAV/DEwhyZqOEb8NPiB5+0d4hCfimIiQF30SE5OADRXgAXAPeJwUfIMKxqh3ypOBrNkGENEWpipA2fBvtcOoiXAwCvkk7PAQRvO3wYH5CO8gfT5e1w12P3/ROsrzPgPilAAAAAElFTkSuQmCC')
end)

-- Panel background in the chosen theme. alpha already includes the opacity setting.
--  Dark : solid dark panel
--  Glass: lighter, see-through panel with a thin bright edge
--  Neon : dark panel with a glowing accent border
-- Text styles: one table per (template, color, alpha step) is created once and reused.
local STY={}
local function sty(size,font,align,outline,r,g,b,a)
 a=math.floor((a or 255)/8)*8+7
 if a>255 then a=255 end
 local key=size*16777216+(if font=='ui_bold' then 4 elseif font=='code' then 2 else 1)*4194304
  +(if align=='center' then 2 elseif align=='right' then 3 else 1)*1048576+(if outline then 524288 else 0)
 local k2=r*65536+g*256+b
 local t1=STY[key];if not t1 then t1={};STY[key]=t1 end
 local t2=t1[k2];if not t2 then t2={};t1[k2]=t2 end
 local st=t2[a]
 if not st then
  st={size=size,font=font,align=align,outline=outline or nil,color={r,g,b,a}}
  t2[a]=st
 end
 return st
end

local function themeBG(x,y,w,h,rad,alpha,r,g,b)
 local th=S.theme
 if th==2 then
  R.rounded_rectangle(x-1,y-1,w+2,h+2,255,255,255,math.floor(alpha*.18),rad+1)
  R.rounded_rectangle(x,y,w,h,36,38,50,math.floor(alpha*.55),rad)
 elseif th==3 then
  R.rounded_rectangle(x-3,y-3,w+6,h+6,r,g,b,math.floor(alpha*.12),rad+3)
  R.rounded_rectangle(x-1,y-1,w+2,h+2,r,g,b,math.floor(alpha*.6),rad+1)
  R.rounded_rectangle(x,y,w,h,9,9,13,alpha,rad)
 else
  R.rounded_rectangle(x,y,w,h,16,16,21,alpha,rad)
 end
end

---------------------------------------------------------------- the Illusion menu (native gui.* widgets)
-- The game draws these widgets itself, so the menu costs almost nothing and has no 48-control limit.
-- follow_menu: the window shows up together with the cheat menu and hides with it.
local MENU={win=nil,el={},ok=false,saveAt=0,syncAt=0}
local function c255(x) return math.floor((x or 0)*255+.5) end
-- reads an element's value in the form S keeps it
local function readEl(kind,el)
 local v=el:get()
 if kind=='color' then
  if type(v)=='table' and v.Color then return {c255(v.Color.R),c255(v.Color.G),c255(v.Color.B)} end
  return nil
 elseif kind=='slider' then
  if type(v)=='number' then return math.floor(v+.5) end
  return nil
 elseif kind=='combo' then
  if type(v)=='number' then return math.floor(v) end
  return nil
 elseif kind=='tcombo' then
  local ok,name=pcall(el.get_option,el)
  if ok and type(name)=='string' then return name end
  return nil
 elseif kind=='check' then return v==true
 elseif kind=='text' then return tostring(v or '')
 end
 return v
end
-- "Crimson": deep navy-violet panels, pink-red accent, tabs along the top, square checkboxes
Z.CRIMSON={preset='neverlose',background={12,10,26},panel={18,15,36},element={28,24,52},hover={38,33,68},
 border={44,38,80},text={236,233,246},subtext={136,130,166},rounding=4,font='gotham',title_font='gotham_bold',
 text_size=13,toggle='checkbox',tabs='top'}
local function menuTheme()
 local name=S.menuTheme
 local c=S.colUI
 if name=='Crimson' then
  local t={}
  for k,v in pairs(Z.CRIMSON) do t[k]=v end
  t.accent={c[1],c[2],c[3]}
  return t
 end
 if type(name)~='string' or name=='' then name='neverlose' end
 return {preset=name,accent={c[1],c[2],c[3]}}
end
local function applyTheme()
 if not MENU.win then return end
 local ok=pcall(function() MENU.win:set_theme(menuTheme()) end)
 if not ok then pcall(function() MENU.win:set_theme('neverlose') end) end
end
-- shows / hides elements that only matter with another option
local function menuVisibility()
 local el=MENU.el
 local function vis(key,on) local e=el[key];if e then pcall(e.set_visible,e,on==true) end end
 for _,k in ipairs({'colHk','colWm','colInd','colHl'}) do vis(k,not S.colSync) end
 vis('spFight',S.spOn);vis('spCalm',S.spOn)
 vis('lowHpAt',S.lowHpOn)
 vis('hkStyle',S.hkOn)
 vis('rrSafe',S.rrHead)
end
local function onMenuChange(key,kind,el)
 local v=readEl(kind,el)
 if v==nil then return end
 if kind=='color' then
  local o=S[key]
  if o[1]==v[1] and o[2]==v[2] and o[3]==v[3] then return end
 elseif S[key]==v then return end
 S[key]=v;uiDirty=true
 if key=='menuTheme' or key=='colUI' then applyTheme() end
 if key=='colSync' or key=='spOn' or key=='lowHpOn' or key=='hkOn' or key=='rrHead' then menuVisibility() end
 if key=='presetSel' then cur=PRESETS[v] or cur end
 if key=='hideBuiltin' then pcall(function() ui.set_builtin_indicators(not v) end) end
end
-- pushes S values into the widgets (after a preset was loaded)
local function menuPush(keys)
 for _,key in ipairs(keys) do
  local el,v=MENU.el[key],S[key]
  if el and v~=nil then
   if MENU.kind[key]=='color' then pcall(el.set,el,{v[1],v[2],v[3],255})
   else pcall(el.set,el,v) end
  end
 end
end
-- saved keys of the binds: {name={key,mode}}
local BINDS=storage.get('binds')
if type(BINDS)~='table' then BINDS={} end
-- checked once a second while the menu is open; written only when a key or mode changed
local function saveBinds()
 local out,sig={},''
 for name,el in pairs(MENU.binds) do
  local ok,key,mode=pcall(el.get_key,el)
  if ok and key~=nil then
   key=tostring(key);mode=tostring(mode or 'Hold')
   key=string.match(key,'([^%.]+)$') or key;mode=string.match(mode,'([^%.]+)$') or mode
   out[name]={key,mode};sig=sig..name..key..mode
  end
 end
 if sig~=MENU.bindSig then
  if MENU.bindSig~=nil then storage.set('binds',out) end
  MENU.bindSig=sig;BINDS=out
 end
end
local function buildMenu()
 MENU.kind={};MENU.binds={}
 local opt={title='ILLUSION',subtitle='Sk1d HVH',width=720,height=520,theme=menuTheme(),follow_menu=true}
 local okW,win=pcall(gui.window,opt)
 if not okW then opt.theme='neverlose';win=gui.window(opt) end
 MENU.win=win
 local pos=storage.get('menu_pos')
 if type(pos)=='table' and type(pos[1])=='number' and type(pos[2])=='number' then
  pcall(win.set_position,win,pos[1],pos[2]);MENU.pos=pos[1]..','..pos[2]
 end
 for _,tb in ipairs(LAYOUT) do
  local tab=win:tab(string.upper(tb.name))
  for _,gr in ipairs(tb.groups) do
   local g=tab:group(string.upper(gr.title),gr.side)
   for _,it in ipairs(gr.items) do
    local kind,key=it[1],it[2]
    local el=nil
    if kind=='check' then
     el=g:toggle(it[3],{default=S[key]==true})
    elseif kind=='slider' then
     local v=S[key];if type(v)~='number' then v=DEF[key] end
     el=g:slider(it[3],it[4],it[5],math.clamp(v,it[4],it[5]),{step=1,suffix=it[6] or ''})
    elseif kind=='combo' then
     local opts=OPT[key] or {'?'}
     local v=S[key];if type(v)~='number' or v<1 or v>#opts then v=1 end
     el=g:dropdown(it[3],opts,v)
    elseif kind=='tcombo' then
     local opts=OPT[key]
     local v=1
     for i,o in ipairs(opts) do if o==S[key] then v=i end end
     el=g:dropdown(it[3],opts,v)
    elseif kind=='color' then
     local c=S[key]
     el=g:color(it[3],c[1],c[2],c[3],255)
    elseif kind=='text' then
     el=g:textbox(it[3],tostring(S[key] or ''),{placeholder='nice shot, {name}'})
    elseif kind=='bind' then
     local sv=BINDS[key]
     local k,m=it[4],it[5]
     if type(sv)=='table' and type(sv[1])=='string' then k=sv[1];m=sv[2] or m end
     local ok,res=pcall(g.keybind,g,it[3],k,m)
     if not ok then ok,res=pcall(g.keybind,g,it[3],'None',it[5]) end
     if ok then el=res;MENU.binds[key]=el end
    elseif kind=='button' then
     if key=='loadPreset' then
      g:button(it[3],function()
       applyPreset(S.presetSel)
       pcall(gui.notify,'Preset loaded: '..tostring((PRESETS[S.presetSel] or {}).name or ''),{title='ILLUSION',duration=3})
      end)
     end
    elseif kind=='label' then
     g:label(key)
    end
    if el and kind~='bind' then
     MENU.el[key]=el;MENU.kind[key]=kind
     el:on_change(function() onMenuChange(key,kind,el) end)
    end
   end
  end
 end
 -- binds: manual AA lives in MANUAL, the rest in K
 for _,m in ipairs(MANUAL) do m.key=MENU.binds[m.bind] end
 for _,name in ipairs({'fKey','ffKey','apKey','esKey','swKey'}) do K[name]=MENU.binds[name] end
 menuVisibility()
 saveBinds()
 MENU.ok=true
end
do
 local ok,err=pcall(buildMenu)
 if not ok then client.log('[Illusion] menu error: '..tostring(err));live.err='menu error: '..tostring(err) end
 if S.hideBuiltin then pcall(function() ui.set_builtin_indicators(false) end) end
 pcall(function()
  local me=entity.get_local_player()
  local nm=if me then entity.get_name(me) else nil
  local c=S.colUI
  gui.notify('Hello, '..tostring(nm or 'player')..'! Welcome back.',{title='ILLUSION',duration=4,color={c[1],c[2],c[3]}})
 end)
end
-- the window remembers where you dragged it (checked once a second while it is open)
local function saveMenuPos()
 local ok,x,y=pcall(MENU.win.get_position,MENU.win)
 if not ok then return end
 if type(x)=='table' then x,y=x.x or x.X or x[1],x.y or x.Y or x[2] end
 if type(x)~='number' or type(y)~='number' then return end
 x,y=math.floor(x+.5),math.floor(y+.5)
 local sig=x..','..y
 if sig~=MENU.pos then MENU.pos=sig;storage.set('menu_pos',{x,y}) end
end
-- values saved for this session (once a second at most)
local function saveSettings(t)
 if not uiDirty or t<MENU.saveAt then return end
 MENU.saveAt=t+1;uiDirty=false
 local out={}
 for k in pairs(DEF) do out[k]=S[k] end
 storage.set('ui',out)
end

---------------------------------------------------------------- notifications (toasts)
local TOASTS={}
local function toast(text,col)
 if not S.toastOn then return end
 if Z.NOTIFY~=false then
  local c=col or COL.ind
  local ok=pcall(function() gui.notify(text,{title='ILLUSION',duration=3,color={c[1],c[2],c[3]}}) end)
  Z.NOTIFY=ok
  if ok then return end
 end
 table.insert(TOASTS,1,{text=text,col=col,at=now()})
 if #TOASTS>5 then table.remove(TOASTS) end
end

---------------------------------------------------------------- anti-brute (Fake flick and normal AA)
local function distToSegment(p,a,b)
 local ab=b-a
 local l2=ab.X*ab.X+ab.Y*ab.Y+ab.Z*ab.Z
 if l2<1e-6 then return (p-a).Magnitude end
 local ap=p-a
 local t=math.clamp((ap.X*ab.X+ap.Y*ab.Y+ap.Z*ab.Z)/l2,0,1)
 return (a+ab*t-p).Magnitude
end
local function flipSide()
 local t=now()
 if t-ff.flipAt<.15 then return end -- one flip per enemy shot
 ff.abSide=-ff.abSide;ff.flips=ff.flips+1;ff.flipAt=t
 toast('Anti-brute: switched side ('..ff.flips..')',nil)
end
on('shot',function(e)
 local abOn=(S.ffOn and S.ffDesync==1) or (S.aaAB and S.aaOn and not S.ffOn)
 if not abOn then return end
 local me=entity.get_local_player()
 if not me or e.shooter==me or not e.start or not e.impact then return end
 local okE,enemy=pcall(entity.is_enemy,e.shooter)
 if okE and enemy==false then return end
 if e.victim==me then flipSide();return end -- they hit you: change side right away
 local origin=localOrigin()
 if not origin then return end
 local head=origin+vector.new(0,64,0)
 if distToSegment(head,e.start,e.impact)<40 then flipSide() end -- the bullet was meant for you
end)

---------------------------------------------------------------- bomb timer
-- C4 timings: taken from the bomb data when the game sends them, otherwise CS:GO defaults.
Z.C4_TIME,Z.DEFUSE,Z.DEFUSE_KIT=40,10,5
local BOMB={}
local function bombReset() BOMB={planted=false,explodeAt=nil,site=nil,planter=nil,defuser=nil,defEnd=nil,kit=false} end
bombReset()
local function numField(t,names)
 if type(t)~='table' then return nil end
 for _,n in ipairs(names) do local v=t[n];if type(v)=='number' then return v end end
 return nil
end
on('bomb_beginplant',function(e) if not BOMB.planted then BOMB.planter=e.slot end end)
on('bomb_abortplant',function() BOMB.planter=nil end)
on('bomb_planted',function(e)
 local ct=globals.curtime()
 BOMB.planted=true;BOMB.planter=nil
 local abs=numField(e.bomb,{'explodeTime','explodeAt','blowTime','detonateTime'})
 local left=numField(e.bomb,{'timeLeft','timer','remaining'})
 BOMB.explodeAt=if abs and abs>ct then abs elseif left and left>0 and left<=90 then ct+left else ct+Z.C4_TIME
 BOMB.total=BOMB.explodeAt-ct
 if type(e.bomb)=='table' then BOMB.site=e.bomb.site or e.bomb.Site end
end)
on('bomb_begindefuse',function(e)
 local ent=getEnt(e.slot)
 local kit=false
 if type(ent)=='table' then kit=(ent.defuser or ent.hasDefuser or ent.kit or ent.defuseKit)==true end
 BOMB.defuser=e.slot;BOMB.kit=kit
 BOMB.defEnd=globals.curtime()+(if kit then Z.DEFUSE_KIT else Z.DEFUSE)
end)
on('bomb_abortdefuse',function() BOMB.defuser=nil;BOMB.defEnd=nil end)
on('bomb_defused',bombReset)
on('bomb_exploded',bombReset)
on('round_start',bombReset)
on('round_end',bombReset)

---------------------------------------------------------------- kill streak
-- Counts your kills in a row; dying resets it to 0.
local STREAK={n=0,showAt=-10,text=''}
Z.STREAK_NAMES={[2]='DOUBLE KILL',[3]='TRIPLE KILL',[4]='QUAD KILL',[5]='ACE',[6]='UNSTOPPABLE',[7]='UNSTOPPABLE'}
on('player_hurt',function(e)
 local me=entity.get_local_player()
 if not me or not e.killed then return end
 if e.slot==me then STREAK.n=0;return end
 if e.attacker==me or e.shooter==me then
  STREAK.n=STREAK.n+1
  if STREAK.n>=2 then
   STREAK.text=Z.STREAK_NAMES[STREAK.n] or 'GODLIKE'
   STREAK.showAt=now()
  end
 end
end)
on('player_death',function(e)
 if e.slot and e.slot==entity.get_local_player() then STREAK.n=0 end
end)

---------------------------------------------------------------- damage indicator
-- 10 times a second: the enemy closest to your crosshair, and how much an ideal bullet
-- from your eyes to his head would do (trace_bullet: walls and armor included, spread not).
local DI={slot=nil,dmg=0,hp=100,next=0,shown=0}
local function updateDamage(cx,cy)
 DI.slot=nil
 local me=entity.get_local_player()
 if not me then return end
 local okA,alive=pcall(entity.is_alive,me)
 if okA and alive==false then return end
 local origin,s=localOrigin()
 if not origin then return end
 local best,bd=nil,160
 for _,slot in ipairs(enemies()) do
  local x,y,z=entity.get_origin(slot)
  if x then
   local sx,sy=renderer.world_to_screen(x,y+60,z)
   if sx then
    local d=math.sqrt((sx-cx)^2+(sy-cy)^2)
    if d<bd then best,bd=slot,d end
   end
  end
 end
 if not best then return end
 local e=getEnt(best)
 if not e or not e.origin then return end
 local r=client.trace_bullet(best,origin+eyeOffset(s),headOf(e))
 DI.slot=best;DI.dmg=(r and r.damage) or 0;DI.hp=e.health or 100
end

---------------------------------------------------------------- view direction (self-calibrating)
-- The game's yaw convention is not documented, so the script tests 8 possible conventions:
-- the right one puts a point straight ahead of the camera in the middle of the screen.
local CB={mode=nil,rdeg=-90,next=0}
local function fwdFor(mode,deg)
 local r=math.rad(deg)
 local sn,cs=math.sin(r),math.cos(r)
 if mode==1 then return vector.new(-sn,0,-cs) elseif mode==2 then return vector.new(sn,0,-cs)
 elseif mode==3 then return vector.new(-sn,0,cs) elseif mode==4 then return vector.new(sn,0,cs)
 elseif mode==5 then return vector.new(cs,0,sn) elseif mode==6 then return vector.new(cs,0,-sn)
 elseif mode==7 then return vector.new(-cs,0,sn) end
 return vector.new(-cs,0,-sn)
end
local function camPos()
 local ok,c=pcall(camera.get)
 if ok and type(c)=='table' and c.position then return c.position end
 local x,y,z=client.camera_position()
 if x then return vector.new(x,y,z) end
 return nil
end
local function calibrate(cx)
 local _,yaw=client.camera_angles()
 local p=camPos()
 if not yaw or not p then return end
 local best,bs=nil,math.huge
 for m=1,8 do
  local q=p+fwdFor(m,yaw)*400
  local sx=renderer.world_to_screen(q.X,q.Y,q.Z)
  if sx and math.abs(sx-cx)<bs then best,bs=m,math.abs(sx-cx) end
 end
 if best and bs<cx*.2 then
  CB.mode=best
  local q=p+fwdFor(best,yaw)*400+fwdFor(best,yaw-90)*150
  local sx=renderer.world_to_screen(q.X,q.Y,q.Z)
  if sx then CB.rdeg=if sx>cx then -90 else 90 end
 end
end
-- yaw (in the game's own convention) of a world direction
local function yawOf(d)
 if not CB.mode then return nil end
 local f0,f90=fwdFor(CB.mode,0),fwdFor(CB.mode,90)
 return math.deg(math.atan2(d.X*f90.X+d.Z*f90.Z,d.X*f0.X+d.Z*f0.Z))
end
-- a world offset seen from the camera: forward and right components
local VB={frame=nil,fx=0,fz=1,rx=1,rz=0}
local function viewRel(d)
 if VB.frame~=RF then
  VB.frame=RF
  local _,yaw=client.camera_angles()
  local f=fwdFor(CB.mode,yaw or 0)
  local r=fwdFor(CB.mode,(yaw or 0)+CB.rdeg)
  VB.fx,VB.fz,VB.rx,VB.rz=f.X,f.Z,r.X,r.Z
 end
 return d.X*VB.fx+d.Z*VB.fz,d.X*VB.rx+d.Z*VB.rz
end

---------------------------------------------------------------- freestanding / anti-backstab
-- 10x a second. Anti-backstab: an enemy with a knife close by -> face him.
-- Freestanding: test two head spots to your left/right as seen from the nearest enemy;
-- if one is behind a wall and the other is not, turn the head to the hidden side.
local function isKnife(slot)
 local ok,w=pcall(entity.get_weapon,slot)
 if not ok or type(w)~='table' then return false end
 local n=string.lower(tostring(w.name or w.Name or w.type or w.class or ''))
 return string.find(n,'knife',1,true)~=nil or string.find(n,'melee',1,true)~=nil
end
local function updateSmart()
 SMART.abs=nil;SMART.why=nil
 if not CB.mode or not S.aaOn or manual then return end
 if not S.aaFree and not S.aaBackstab then return end
 local me,s=localOrigin()
 if not me then return end
 local near,nd,nearO=nil,math.huge,nil
 for _,slot in ipairs(enemies()) do
  local o=originOf(slot)
  if o then
   local d=(o-me).Magnitude
   if d<nd then near,nd,nearO=slot,d,o end
  end
 end
 if not near then return end
 local toEnemy=yawOf(nearO-me)
 if not toEnemy then return end
 if S.aaBackstab and nd<260 and isKnife(near) then
  SMART.abs=toEnemy;SMART.why='BACKSTAB';return
 end
 if S.aaFree then
  local eye=nearO+vector.new(0,64,0)
  local head=vector.new(0,64-18*((s and s.move and s.move.duckAmount) or 0),0)
  local pL=me+head+fwdFor(CB.mode,toEnemy+90)*22
  local pR=me+head+fwdFor(CB.mode,toEnemy-90)*22
  local tl=client.trace_line(eye,pL)
  local tr=client.trace_line(eye,pR)
  local hidL=tl and tl.hit==true
  local hidR=tr and tr.hit==true
  if hidL and not hidR then SMART.abs=toEnemy+90;SMART.why='FREESTAND'
  elseif hidR and not hidL then SMART.abs=toEnemy-90;SMART.why='FREESTAND' end
 end
end

---------------------------------------------------------------- hit marker, kill feed, stats
local HM={at=-10,head=false,kill=false}
local KF={}
local STATS={round={k=0,hs=0,shots=0,hits=0,dmg=0},match={k=0,hs=0,shots=0,hits=0,dmg=0},best=0}
local function statAdd(field,v) STATS.round[field]=STATS.round[field]+v;STATS.match[field]=STATS.match[field]+v end

on('shot',function(e)
 if e.shooter~=entity.get_local_player() then return end
 local melee=bit.band(e.flags or 0,8)~=0
 local extra=not melee and bit.band(e.flags or 0,32)~=0
 if extra then return end
 statAdd('shots',1)
 if (e.victim or 0)>0 and (e.damage or 0)>0 then
  statAdd('hits',1)
  HM.at=now();HM.head=e.group==1;HM.kill=e.killed==true
 end
end)
on('player_hurt',function(e)
 local me=entity.get_local_player()
 if not me or (e.attacker~=me and e.shooter~=me) or e.slot==me then return end
 statAdd('dmg',e.damage or 0)
 if e.killed then
  statAdd('k',1)
  if e.group==1 then statAdd('hs',1) end
  STATS.best=math.max(STATS.best,STREAK.n)
 else
  local left=e.health or e.remainingHealth
  if left and left>0 and left<=20 then
   toast((entity.get_name(e.slot) or ('#'..e.slot))..' is low: '..left..' HP',{255,170,80})
  end
 end
end)
on('player_death',function(e)
 if not e.slot then return end
 local att=e.attacker or e.shooter
 local wname=nil
 if att and att>0 then
  local ok,wd=pcall(entity.get_weapon,att)
  if ok and type(wd)=='table' then wname=wd.name or wd.Name end
 end
 table.insert(KF,1,{att=if att and att>0 then (entity.get_name(att) or ('#'..att)) else nil,
  vic=entity.get_name(e.slot) or ('#'..e.slot),hs=e.group==1,weapon=wname,
  mine=att==entity.get_local_player(),me=e.slot==entity.get_local_player(),at=now()})
 if #KF>5 then table.remove(KF) end
end)
on('round_start',function()
 STATS.round={k=0,hs=0,shots=0,hits=0,dmg=0}
 KF={}
 toast('Round started',nil)
end)
on('bomb_planted',function(e)
 local site=type(e.bomb)=='table' and (e.bomb.site or e.bomb.Site) or nil
 toast('Bomb planted'..(if site then ' on '..tostring(site) else ''),{255,170,80})
end)
on('bomb_defused',function() toast('Bomb defused',{120,230,140}) end)
on('bomb_exploded',function() toast('Bomb exploded',{255,95,95}) end)

---------------------------------------------------------------- bullet impacts
-- A small glowing box where each of your bullets ended (hits and misses).
on('bullet_impact',function(e)
 if not S.impOn or not e.impact then return end
 if e.shooter~=entity.get_local_player() and e.slot~=entity.get_local_player() then return end
 local c=Z.TRC[S.trColor] or Z.TRC[1]
 pcall(renderer.effect,'box',e.impact,{size=vector.new(3,3,3),color={c[1],c[2],c[3],230},
  life=S.impLife,fade=math.min(.6,S.impLife),material='neon'})
end)

---------------------------------------------------------------- kill effect
-- Soul: the killed player's body (taken from his hitboxes at the moment of death) rises
-- up as a glowing ghost in the theme color and fades away, with soft particles around it.
-- Light pillar / Ring blast: the simpler effects.
local SOULS={}
local function bodyPoints(slot,base)
 local pts={}
 local ok,boxes=pcall(entity.get_hitboxes,slot)
 if ok and type(boxes)=='table' and #boxes>0 then
  for _,hb in ipairs(boxes) do
   if hb.origin then
    local rad=hb.radius
    if type(rad)~='number' and hb.size then rad=(hb.size.X+hb.size.Y+hb.size.Z)/6 end
    pts[#pts+1]={pos=hb.origin,r=math.clamp(rad or 4,2.5,9)}
   end
  end
  -- keep at most 9 evenly spread points (enough for the silhouette, much cheaper)
  if #pts>9 then
   local keep={}
   for i=1,9 do keep[i]=pts[math.floor((i-1)*(#pts-1)/8)+1] end
   pts=keep
  end
 end
 if #pts==0 then -- fallback: a simple standing body
  for _,p in ipairs({{0,66,0,6},{0,56,0,6},{0,46,0,8},{0,36,0,7},{-9,48,0,3.5},{9,48,0,3.5},{-11,38,0,3},{11,38,0,3},
   {-4,24,0,4.5},{4,24,0,4.5},{-4,10,0,4},{4,10,0,4}}) do
   pts[#pts+1]={pos=base+vector.new(p[1],p[2],p[3]),r=p[4]}
  end
 end
 return pts
end
on('player_hurt',function(e)
 local me=entity.get_local_player()
 if not S.kfxOn or not e.killed or e.slot==me or (e.attacker~=me and e.shooter~=me) then return end
 local base=nil
 local ve=getEnt(e.slot)
 if type(ve)=='table' and ve.origin then base=ve.origin elseif e.impact then base=e.impact-vector.new(0,40,0) end
 if not base then return end
 local r,g,b=colorOf('colInd')
 local col={r,g,b,255}
 local st=S.kfxType
 if st==1 or st==2 then
  table.insert(SOULS,{pts=bodyPoints(e.slot,base),at=now(),col={r,g,b}})
  if #SOULS>(if S.perfMode then 1 else 2) then table.remove(SOULS,1) end -- keeps the draw budget safe
  pcall(renderer.effect,'particles',base+vector.new(0,40,0),{count=14,speed=40,spread=60,radius=1.4,color=col,
   life=1.4,acceleration=vector.new(0,90,0)})
 end
 if st==3 then
  pcall(renderer.effect,'box',base+vector.new(0,90,0),{size=vector.new(5,180,5),color={r,g,b,170},life=1.2,fade=.9,material='neon'})
  pcall(renderer.effect,'particles',base+vector.new(0,10,0),{count=40,speed=120,spread=25,radius=1.6,color=col,
   life=1.2,acceleration=vector.new(0,260,0)})
  pcall(renderer.effect,'light',base+vector.new(0,60,0),{brightness=3,range=120,color=col,life=.9,fade=.7})
 end
 if st==2 or st==4 then
  for i,rad in ipairs({18,34,52}) do
   pcall(renderer.effect,'ring',base+vector.new(0,3,0),{radius=rad,width=1.4-i*.3,normal=vector.new(0,1,0),
    color={r,g,b,255-i*45},life=.35+i*.18,fade=.3+i*.12})
  end
  pcall(renderer.effect,'particles',base+vector.new(0,8,0),{count=30,speed=280,spread=90,radius=1.4,color=col,
   life=.8,acceleration=vector.new(0,-600,0)})
 end
end)
-- drawn every frame from the paint callback
Z.SOUL_LIFE=1.8
local function drawSouls(t)
 for i=#SOULS,1,-1 do if t-SOULS[i].at>Z.SOUL_LIFE then table.remove(SOULS,i) end end
 for _,so in ipairs(SOULS) do
  local age=t-so.at
  local k=age/Z.SOUL_LIFE
  local fade=(1-k)^1.4
  local fin=math.clamp(age/.15,0,1)
  local rise=age*age*22+age*30  -- starts slow, then floats away faster
  local grow=1+k*.35
  local c=so.col
  -- screen size of one world unit at the soul's position, measured once per frame
  local p0=so.pts[1].pos
  local x0,y0=renderer.world_to_screen(p0.X,p0.Y+rise,p0.Z)
  local _,y1=renderer.world_to_screen(p0.X,p0.Y+rise+10,p0.Z)
  if x0 and y1 then
   local unit=math.abs(y1-y0)/10*grow
   local al=fin*fade
   local ga,ca2=math.floor(55*al),math.floor(150*al)
   local lr,lg,lb=math.min(255,c[1]+80),math.min(255,c[2]+80),math.min(255,c[3]+80)
   for j,pt in ipairs(so.pts) do
    local pp=pt.pos
    local x,y=renderer.world_to_screen(pp.X+math.sin(t*2.5+j*.7)*2*k,pp.Y+rise,pp.Z)
    if x then
     local rp=math.clamp(pt.r*unit,1.5,40)
     R.circle(x,y,rp*1.9,c[1],c[2],c[3],ga,true)   -- soft glow
     R.circle(x,y,rp*.9,lr,lg,lb,ca2,true)         -- bright core
    end
   end
  end
 end
end

---------------------------------------------------------------- smart presets
-- "In a fight" = an enemy on your screen within ~1800 hu, an enemy bullet passed near you,
-- or you shot in the last few seconds. The fight preset is kept 3 s after the last sign.
local SP={lastFight=-10,cur=nil,next=0}
on('shot',function(e)
 local me=entity.get_local_player()
 if not me or not e.start or not e.impact then return end
 if e.shooter==me then SP.lastFight=now();return end
 if e.victim==me then SP.lastFight=now();return end
 local o=localOrigin()
 if o and distToSegment(o+vector.new(0,64,0),e.start,e.impact)<120 then SP.lastFight=now() end
end)
local function smartPresetTick(w,h)
 if not S.spOn or S.ffOn then SP.cur=nil;return end
 local t=now()
 local me=localOrigin()
 if me then
  for _,slot in ipairs(enemies()) do
   local ox,oy,oz=entity.get_origin(slot)
   if ox and (vector.new(ox,oy,oz)-me).Magnitude<1800 then
    local sx,sy=renderer.world_to_screen(ox,oy+60,oz)
    if sx and sx>0 and sx<w and sy>0 and sy<h then SP.lastFight=t;break end
   end
  end
 end
 local want=if t-SP.lastFight<3 then S.spFight else S.spCalm
 if want~=SP.cur then
  SP.cur=want
  applyPreset(want)
  toast('Preset: '..(PRESETS[want] and PRESETS[want].name or '?')..(if t-SP.lastFight<3 then ' (fight)' else ' (calm)'),nil)
 end
end

---------------------------------------------------------------- hotkeys: every active bind (ui.get_binds)
Z.C_BG={16,16,21}
Z.C_TEXT={235,235,240}
Z.C_ACC={120,200,255}
-- short names and icons for the squares
Z.ABBR={doubletap={'DT','dt'},jumpbug={'JB','jump'},edgebug={'EB','jump'},edgejump={'EJ','jump'},
 minijump={'MJ','jump'},pixelsurf={'PS','jump'},thirdperson={'TP','peek'},hideshots={'HS','dt'},
 onshot={'OS','dt'},fakeduck={'FD','arrow'},slowwalk={'SW','arrow'},autopeek={'AP','peek'},
 quickpeek={'QP','peek'},freestanding={'FS','arrow'},mindamage={'MD','dt'},damageoverride={'MD','dt'},
 minimumdamage={'MD','dt'},forcebody={'FB','dot'},forcebodyaim={'FB','dot'},forcesafepoint={'SP','dot'},
 quickstop={'QS','dot'},edgeyaw={'EY','arrow'}}
-- Illusion's own binds (labels from the menu): how they look in the list
local OWNB={
 {label='Manual backward',manual=true},{label='Manual forward',manual=true},
 {label='Manual right',manual=true},{label='Manual left',manual=true},
 {label='Fake flick side',short='FF',icon='arrow',ff=true},
 {label='Edge stop',short='ES',icon='dot'},{label='Slow walk',short='SW',icon='arrow'},
 {label='AI peek',short='AP',icon='peek'},{label='Flick',short='FL',icon='flick'},
}
for _,o in ipairs(OWNB) do o.low=string.lower(o.label) end
local function initials(name)
 local s,prev='',' '
 for c=1,#name do
  local ch=string.sub(name,c,c)
  if prev==' ' and ch~=' ' then s=s..string.upper(ch) end
  prev=ch
 end
 return string.sub(s,1,2)
end
-- 'Rage.doubleTapKey' -> 'Double tap' (when a bind has no name)
local function prettyName(key)
 local last=key
 while true do
  local a=string.find(last,'.',1,true)
  if not a then break end
  last=string.sub(last,a+1)
 end
 for _,suffix in ipairs({'Hotkey','Key','Bind'}) do
  if #last>#suffix and string.sub(last,-#suffix)==suffix then last=string.sub(last,1,#last-#suffix);break end
 end
 local out=''
 for c=1,#last do
  local ch=string.sub(last,c,c)
  if c>1 and ch~=string.lower(ch) then out=out..' '..string.lower(ch) else out=out..ch end
 end
 return string.upper(string.sub(out,1,1))..string.sub(out,2)
end
local NAMEINFO={} -- name -> {short,icon,own,tw}, worked out once per name
local function infoOf(name)
 local inf=NAMEINFO[name]
 if inf then return inf end
 local low=string.lower(name)
 for _,o in ipairs(OWNB) do
  if low==o.low or string.sub(low,-#o.low)==o.low then inf={own=o,short=o.short,icon=o.icon};break end
 end
 if not inf then
  local compact=''
  for c=1,#low do local ch=string.sub(low,c,c);if ch~=' ' and ch~='_' and ch~='-' then compact=compact..ch end end
  local a=Z.ABBR[compact]
  inf={short=(a and a[1]) or initials(name),icon=(a and a[2]) or 'dot'}
 end
 inf.tw=renderer.measure_text(name,12,'ui') or #name*6
 NAMEINFO[name]=inf
 return inf
end
-- exploits (double tap / hide shots / fake duck) from the game, 10x a second
local EXS={dt=nil,charge=0,max=0,hs=false,fd=false}
local function pollExploits()
 local ok,st=pcall(function() return exploits.get_status() end)
 if not ok or type(st)~='table' then EXS.dt=nil;EXS.hs=false;EXS.fd=false;return end
 EXS.dt=st.double_tap;EXS.charge=tonumber(st.charge) or 0;EXS.max=tonumber(st.max_charge) or 0
 EXS.hs=st.hide_shots==true;EXS.fd=st.fake_duck==true
end
-- One rage_config callback for everything (each callback gets its own copy of the config).
-- Head priority: never "prefer body" from the cheat side, and optionally drop "prefer safe
-- point" (safe points are almost always body, so it blocks headshots). "Force" keys stay.
on('rage_config',function(c)
 local t=now()
 if S.rrHead then
  if c.body==2 then c.body=1 end
  if S.rrSafe==2 and c.safe==2 then c.safe=1 end
 end
 js.active=false
 if S.jsOn and ME.air then
  if t>=(js.wAt or 0) then
   js.wAt=t+.5
   local w=entity.get_local_weapon()
   js.weapon=if type(w)=='table' then string.lower(tostring(w.name or w.Name or w.displayName or w.id or '')) else ''
   js.allowed=weaponAllowed(js.weapon)
  end
  if js.allowed then c.hitchance=S.jsHC;c.autoStop=false;js.active=true end
 end
end)

local binds={} -- active binds, rebuilt 10x a second
Z.BINDS_API=nil -- does the game have ui.get_binds?
local function ownFallback(list)
 -- older game version: only Illusion's own binds
 if KS.fKey then list[#list+1]={name='Flick',short='FL',icon='flick'} end
 if S.ffOn and KS.ffKey then list[#list+1]={name='Fake flick side',short='FF',icon='arrow',dir='RIGHT'} end
 if KS.apKey then list[#list+1]={name='AI peek',short='AP',icon='peek'} end
 if KS.esKey then list[#list+1]={name='Edge stop',short='ES',icon='dot'} end
 if KS.swKey then list[#list+1]={name='Slow walk',short='SW',icon='arrow'} end
end
local function collectBinds()
 local list,shown={},{}
 -- manual anti-aim: one row for the side that is really used
 if manual then
  local nm='Manual '..string.lower(manual.name)
  list[1]={name=nm,short='M'..string.sub(manual.name,1,1),icon='arrow',dir=manual.name,tw=infoOf(nm).tw}
  shown[nm]=true
 end
 local all=nil
 if Z.BINDS_API~=false then
  local ok,res=pcall(function() return ui.get_binds() end)
  if ok and type(res)=='table' then all=res;Z.BINDS_API=true else Z.BINDS_API=false end
 end
 if not all then ownFallback(list);binds=list;return end
 for _,b in pairs(all) do
  if type(b)=='table' and b.active==true and b.enabled~=false and b.mode~='Always' then
   local name=b.name
   if type(name)~='string' or name=='' then name=prettyName(tostring(b.key or '?')) end
   if not shown[name] then
    shown[name]=true
    local inf=infoOf(name)
    local o=inf.own
    local skip=o and (o.manual or (o.ff and not S.ffOn))
    if not skip then
     local short,dir=inf.short,nil
     if o and o.ff then dir='RIGHT' end
     -- double tap: show the charge while it recharges
     if short=='DT' and EXS.dt=='charging' and EXS.max>0 then
      short=math.floor(EXS.charge/EXS.max*100)..'%'
     end
     list[#list+1]={name=name,short=short,icon=inf.icon,dir=dir,tw=inf.tw}
    end
   end
  end
 end
 binds=list
end

---------------------------------------------------------------- timers: everything that does not need every frame
local tick={settings=0,wm=0}
local wm={text='',w=0}
local fps=0

-- Heavy rage hooks are only registered while a feature needs them: the game builds a copy of
-- its data for every call (resolve: every pose, rage_point: every aim point), even if the
-- script would ignore it.
local HOOKS={}
local function hook(name,fn,on)
 if on and not HOOKS[name] then
  if pcall(client.set_event_callback,name,DBG.cb(name,fn)) then HOOKS[name]=true end
 elseif not on and HOOKS[name] then
  pcall(client.unset_event_callback,name,DBG.cb(name,fn));HOOKS[name]=false
 end
end
local function syncHooks()
 hook('resolve',onResolve,S.resOn==true)
 hook('rage_point',onRagePoint,RRON)
end
syncHooks()

local function update()
 local t=FR.t
 if t>=(tick.keys or 0) then tick.keys=t+.015;readKeys() end -- hotkeys: up to ~60x a second
 if t>=tick.settings then tick.settings=t+(if S.perfMode then .2 else .1);refresh();refreshColors();syncHooks();updateLag();pcall(updateSmart) end
 if t>=(tick.exp or 0) then tick.exp=t+.1;pollExploits() end
 if S.hkOn and t>=(tick.binds or 0) then tick.binds=t+.1;collectBinds() end
 saveSettings(t)
 if FR.menu and MENU.ok then
  if Z.presetStale then Z.presetStale=false;menuPush(Z.PKEYS) end
  if t>=(tick.bk or 0) then tick.bk=t+1;pcall(saveBinds);pcall(saveMenuPos) end
 end
end
on('paint_ui',function()
 if not DRAW.fresh then RF=RF+1;DRAW.n=0;frameBegin() end -- no paint this frame (menus / lobby)
 DRAW.fresh=false
 drawFrame(380)
 local ok,err=pcall(update)
 if not ok then live.err='update error: '..tostring(err) end
end)

---------------------------------------------------------------- drawing (one callback)
local function drawIcon(kind,cx,cy,dir)
 local r,g,b=Z.C_TEXT[1],Z.C_TEXT[2],Z.C_TEXT[3]
 if kind=='dt' then
  R.triangle(cx-5,cy-5,cx-5,cy+5,cx+4,cy,r,g,b,255,true)
 elseif kind=='jump' then
  R.triangle(cx,cy-6,cx-5,cy+4,cx+5,cy+4,r,g,b,255,true)
 elseif kind=='flick' then
  R.line(cx+3,cy-6,cx-3,cy+6,r,g,b,255,2)
 elseif kind=='peek' then
  R.circle(cx,cy,5,r,g,b,255,false)
 elseif kind=='arrow' then
  if dir=='LEFT' then R.triangle(cx-6,cy,cx+4,cy-6,cx+4,cy+6,r,g,b,255,true)
  elseif dir=='RIGHT' then R.triangle(cx+6,cy,cx-4,cy-6,cx-4,cy+6,r,g,b,255,true)
  elseif dir=='FORWARD' then R.triangle(cx,cy-6,cx-6,cy+4,cx+6,cy+4,r,g,b,255,true)
  else R.triangle(cx,cy+6,cx-6,cy-4,cx+6,cy-4,r,g,b,255,true) end
 else
  R.circle(cx,cy,3,r,g,b,255,true)
 end
end
-- glowing ring on the floor around p (projected to the screen each frame)
local function drawRing(p,rad,r,g,b)
 if not p then return end
 local pts={}
 for i=0,13 do
  local a=i/14*math.pi*2
  local q=p+vector.new(math.cos(a)*rad,2,math.sin(a)*rad)
  local x,y=renderer.world_to_screen(q.X,q.Y,q.Z)
  if not x then return end
  pts[#pts+1]={x,y}
 end
 R.polyline(pts,r,g,b,230,3,true)
end
local function drawPoint(p,r,g,b)
 if not p then return end
 local x,y=renderer.world_to_screen(p.X,p.Y,p.Z)
 if x then R.circle(x,y,5,r,g,b,255,true) end
end

local hk={x=storage.get('hk_x'),y=storage.get('hk_y'),drag=false,dx=0,dy=0}
local TXT={Z.C_TEXT[1],Z.C_TEXT[2],Z.C_TEXT[3],255}

local IND={bar=0,fade={},order={},width={}}
local ARW={at=0,list={}}
-- Debug overlay (Settings -> Debug overlay): calls per second and milliseconds per second
-- for every callback, plus the number of shapes drawn per frame.
local function drawDebug()
 local t=now()
 DBG.draws=math.max(DBG.draws,DRAW.n)
 if t>=DBG.at then
  local span=math.max(t-(DBG.last or t-1),.2)
  DBG.last=t;DBG.at=t+1
  local lines={}
  for name,c in pairs(DBG.c) do
   lines[#lines+1]={name=name,c=c/span,ms=(DBG.t[name] or 0)*1000/span,mx=(DBG.mx[name] or 0)*1000}
  end
  table.sort(lines,function(a,b) return a.ms>b.ms end)
  local out={'callback         calls   ms/s   max ms'}
  for i,l in ipairs(lines) do
   if i>12 then break end
   out[#out+1]=string.format('%-16s %5d %7.2f %7.2f',l.name,math.floor(l.c+.5),l.ms,l.mx)
  end
  local secs={}
  for name,v in pairs(DBG.sec) do secs[#secs+1]={name=name,ms=v*1000/span} end
  table.sort(secs,function(a,b) return a.ms>b.ms end)
  out[#out+1]='-- paint parts (ms/s) --'
  for i,l in ipairs(secs) do
   if i>10 then break end
   out[#out+1]=string.format('%-16s %7.2f',l.name,l.ms)
  end
  out[#out+1]='shapes per frame: '..DBG.draws..' (limit '..DRAW.limit..')'
  out[#out+1]='clock: '..(if DBG.clock==globals.realtime then 'frame time (ms may show 0)' else 'precise')
  DBG.text=out;DBG.c={};DBG.t={};DBG.mx={};DBG.sec={};DBG.draws=0
 end
 if DBG.text then
  local w,h=client.screen_size()
  local y=math.floor(h*.18)
  local st=sty(12,'code',nil,true,235,235,240,255)
  for i,l in ipairs(DBG.text) do RR.text_ex(16,y+(i-1)*14,l,st) end
 end
end
local function draw()
 local w,h=FR.w,FR.h
 local t=FR.t
 local ft=FR.ft
 if ft>0 then fps=fps+(1/ft-fps)*.05 end
 local r,g,b=COL.ind[1],COL.ind[2],COL.ind[3]
 local a=255
 local cx,cy=math.floor(w/2),math.floor(h/2)
 local x,y=cx-70,cy+35

 local menuOpenD=FR.menu
 DBG.mark('indicator')
 -- manual arrows
 if manual then
  if manual.name=='LEFT' then R.triangle(cx-60,cy,cx-45,cy-8,cx-45,cy+8,r,g,b,a,true)
  elseif manual.name=='RIGHT' then R.triangle(cx+60,cy,cx+45,cy-8,cx+45,cy+8,r,g,b,a,true)
  elseif manual.name=='FORWARD' then R.triangle(cx,cy-60,cx-8,cy-45,cx+8,cy-45,r,g,b,a,true)
  else R.triangle(cx,cy+28,cx-8,cy+16,cx+8,cy+16,r,g,b,a,true) end
 end

 -- While the cheat menu is open, only the watermark and Hotkeys are drawn: everything else
 -- is hidden behind the menu anyway, and skipping it keeps the menu smooth.
 if not menuOpenD then
 -- crosshair indicator (Illusion style)
 local k=1-math.exp(-math.max(ft,.001)*12) -- smooth animation step
 IND.bar=IND.bar+(((if live.mode=='fake' then (live.choke or 0) else (live.amt or 0)/58)*(live.side or 1))-IND.bar)*k
 local y0=cy+30
 -- title with a soft breathing glow
 local pulse=if S.perfMode then 255 else math.floor(205+50*math.sin(t*2.4))
 R.text_ex(cx,y0,'ILLUSION',sty(15,'ui_bold','center',true,r,g,b,pulse))
 -- body yaw bar: fills from the middle towards the desync side
 local bw2=36
 R.rounded_rectangle(cx-bw2-1,y0+19,bw2*2+2,5,Z.C_BG[1],Z.C_BG[2],Z.C_BG[3],200,2)
 local fill=math.floor(math.abs(IND.bar)*bw2+.5)
 if fill>0 then
  if IND.bar>0 then R.gradient(cx,y0+20,fill,3,r,g,b,120,r,g,b,255,true)
  else R.gradient(cx-fill,y0+20,fill,3,r,g,b,255,r,g,b,120,true) end
 end
 -- state badges (fade in / out)
 local want=IND.want
 if t>=(IND.next or 0) or not want then
 IND.next=t+.1
 want={}
 if live.mode=='off' then want[#want+1]='AA OFF' end
 if live.mode=='use' then want[#want+1]='USE' end
 if SMART.why and not manual then want[#want+1]=SMART.why end
 if S.spOn and SP.cur then want[#want+1]=if now()-SP.lastFight<3 then 'FIGHT' else 'CALM' end
 if KS.swKey then want[#want+1]='SLOW' end
 if S.streakOn and STREAK.n>=1 then want[#want+1]='STREAK '..STREAK.n end
 if live.mode=='aa' and live.own and live.state then want[#want+1]=string.upper(live.state) end
 if live.mode=='fake' then want[#want+1]=if live.ffRight then 'FAKE R' else 'FAKE L' end
 if live.mode=='fake' and S.ffDesync==1 and t-ff.flipAt<.8 then want[#want+1]='FLIP '..ff.flips end
 if live.flick then want[#want+1]='FLICK' end
 if manual then want[#want+1]=({LEFT='LEFT',RIGHT='RIGHT',FORWARD='FWD',BACKWARD='BACK'})[manual.name] end
 if S.jsOn and js.active then want[#want+1]='JUMP '..S.jsHC end
 if es.active then want[#want+1]='EDGE' end
 if EXS.dt=='ready' then want[#want+1]='DT'
 elseif EXS.dt=='charging' then
  want[#want+1]=if EXS.max>0 then 'DT '..(math.floor(EXS.charge/EXS.max*4)*25)..'%' else 'DT ...'
 end
 if EXS.hs then want[#want+1]='HS' end
 if EXS.fd then want[#want+1]='DUCK' end
 if KS.apKey then want[#want+1]=if ap.state=='peek' then 'PEEK >' else 'PEEK' end
 IND.want=want
 end
 local on={}
 for _,txt in ipairs(want) do on[txt]=true;if not IND.fade[txt] then IND.fade[txt]=0;IND.order[#IND.order+1]=txt end end
 local items,total={},0
 for i=#IND.order,1,-1 do
  local txt=IND.order[i]
  IND.fade[txt]=IND.fade[txt]+((if on[txt] then 1 else 0)-IND.fade[txt])*k
  if not on[txt] and IND.fade[txt]<.03 then IND.fade[txt]=nil;table.remove(IND.order,i) end
 end
 for _,txt in ipairs(IND.order) do
  local tw=IND.width[txt]
  if not tw then tw=renderer.measure_text(txt,11,'ui_bold') or #txt*6;IND.width[txt]=tw end
  items[#items+1]={txt=txt,w=tw+12,f=IND.fade[txt]}
  total=total+(tw+12)*IND.fade[txt]+4
 end
 if S.perfMode then
  -- one text line for all states (1 shape instead of 2 per badge)
  if want~=IND.lineFor then
   IND.lineFor=want
   IND.line=table.concat(want,'   ')
  end
  if IND.line and IND.line~='' then
   R.text_ex(cx,y0+31,IND.line,sty(11,'ui_bold','center',true,Z.C_TEXT[1],Z.C_TEXT[2],Z.C_TEXT[3],235))
  end
 else
  local bx=cx-math.floor((total-4)/2)
  for _,it in ipairs(items) do
   local al=math.floor(255*it.f)
   themeBG(bx,y0+30,it.w,16,4,math.floor(bgA(210)*it.f),r,g,b)
   R.text_ex(bx+8,y0+31,it.txt,sty(11,'ui_bold',nil,false,Z.C_TEXT[1],Z.C_TEXT[2],Z.C_TEXT[3],al))
   bx=bx+math.floor((it.w+4)*it.f)
  end
 end
 -- small info lines
 local ly=y0+52
 if S.resOn then
  if t>=(IND.resAt or 0) then
   IND.resAt=t+.25
   IND.resText=if res.lslot then 'resolver  #'..res.lslot..' '..res.llabel..' '..math.floor(res.lval or 0)..'   '..res.hits..' / '..res.misses
    else 'resolver  waiting for a target   '..res.hits..' / '..res.misses
  end
  R.text_ex(cx,ly,IND.resText,sty(11,'ui','center',false,170,170,180,200))
  ly=ly+14
 end
 if KS.apKey then
  drawRing(ap.start,18+math.sin(t*4)*2,r,g,b)
  if ap.state=='peek' and ap.goal then
   pcall(renderer.world_line,ap.start+vector.new(0,2,0),ap.goal+vector.new(0,2,0),r,g,b,200,2)
   drawRing(ap.goal,12,255,140,110)
  end
  R.text_ex(cx,ly,ap.info,sty(11,'ui','center',false,170,170,180,200))
  ly=ly+14
 end
 if S.jsOn and inAir() and not js.active and js.weapon~='?' then
  R.text_ex(cx,ly,'jumpscout: weapon not allowed ('..js.weapon..')',sty(11,'ui','center',false,230,150,120,220))
  ly=ly+14
 end
 if live.err then
  R.text_ex(cx,ly,live.err,sty(11,'ui','center',false,255,110,110,255))
 end

 if #DMG>0 then floatNumbers(t) end

 DBG.mark('misc')
 -- smart presets (4x a second)
 if t>=SP.next then SP.next=t+.25;pcall(smartPresetTick,w,h) end

 -- low HP: red edges that pulse faster the lower you are
 if S.lowHpOn then
  local hp=ME.hp
  if hp and hp>0 and hp<S.lowHpAt then
   local f=1-hp/S.lowHpAt
   local pulse3=if S.perfMode then .8 else .6+.4*math.sin(t*(3+f*5))
   local al=math.floor(150*f*pulse3+40)
   local ew=math.floor(math.min(w,h)*.16)
   R.gradient(0,0,w,ew,220,30,30,al,220,30,30,0,false)
   R.gradient(0,h-ew,w,ew,220,30,30,0,220,30,30,al,false)
   R.gradient(0,0,ew,h,220,30,30,al,220,30,30,0,true)
   R.gradient(w-ew,0,ew,h,220,30,30,0,220,30,30,al,true)
  end
 end

 -- keep the view direction calibrated (twice a second)
 if t>=CB.next then CB.next=t+.5;pcall(calibrate,cx) end

 DBG.mark('crosshair+marker')
 -- custom crosshair
 if S.chOn then
  local cs,gp,th=S.chSize,S.chGap,S.chThick
  local h2=math.floor(th/2)
  local function bar(x1,y1,w1,h1)
   R.rectangle(x1-1,y1-1,w1+2,h1+2,0,0,0,170)
   R.rectangle(x1,y1,w1,h1,r,g,b,255)
  end
  bar(cx-gp-cs,cy-h2,cs,th);bar(cx+gp+1,cy-h2,cs,th)
  bar(cx-h2,cy-gp-cs,th,cs);bar(cx-h2,cy+gp+1,th,cs)
  if S.chDot then bar(cx-h2,cy-h2,th,th) end
 end

 -- hit marker: four lines that fly apart and fade
 if S.hmOn and t-HM.at<.45 then
  local age=t-HM.at
  local al=math.floor(255*(1-age/.45))
  local sp=5+age*28
  local c=if HM.kill then {255,95,95} elseif HM.head then {255,205,90} else {255,255,255}
  for _,sg in ipairs({{1,1},{-1,1},{1,-1},{-1,-1}}) do
   R.line(cx+sg[1]*sp,cy+sg[2]*sp,cx+sg[1]*(sp+7),cy+sg[2]*(sp+7),c[1],c[2],c[3],al,2)
  end
 end

 DBG.mark('arrows')
 -- off-screen arrows towards enemies
 if S.arrowsOn and CB.mode and not menuOpenD then
  if t>=(ARW.at or 0) then
   ARW.at=t+.05
   local list={}
   local me2=localOrigin()
   if me2 then
    local rr=math.min(w,h)*.32
    for _,slot in ipairs(enemies()) do
     local ox,oy,oz=entity.get_origin(slot)
     if ox then
      local sx,sy=renderer.world_to_screen(ox,oy+40,oz)
      local onScreen=sx and sx>40 and sx<w-40 and sy>40 and sy<h-40
      if not onScreen then
       local fwdc,rgt=viewRel(vector.new(ox-me2.X,0,oz-me2.Z))
       local ang=math.atan2(rgt,fwdc)
       local sa,ca=math.sin(ang),math.cos(ang)
       local ax,ay=cx+sa*rr,cy-ca*rr
       list[#list+1]={ax+sa*12,ay-ca*12,ax+ca*7,ay+sa*7,ax-ca*7,ay-sa*7}
      end
     end
    end
   end
   ARW.list=list
  end
  local pulse2=if S.perfMode then 230 else math.floor(170+85*math.sin(t*5))
  for _,p in ipairs(ARW.list or {}) do
   R.triangle(p[1],p[2],p[3],p[4],p[5],p[6],r,g,b,pulse2,true)
  end
 end

 DBG.mark('killfeed')
 -- kill feed (top right, under the watermark)
 if S.kfOn and #KF>0 and not menuOpenD then
  for i=#KF,1,-1 do if t-KF[i].at>6 then table.remove(KF,i) end end
  local ky=46
  for _,row in ipairs(KF) do
   local al=math.floor(255*math.clamp((6-(t-row.at))/.5,0,1))
   local text=row.text
   if not text then
    text=(row.att or '')..(if row.weapon then ' ['..tostring(row.weapon)..'] ' else '  >  ')..(if row.hs then 'HS ' else '')..row.vic
    row.text=text
   end
   local tw=row.w
   if not tw then tw=(renderer.measure_text(text,12,'ui') or #text*6);row.w=tw end
   local bw5=tw+22
   local bx5=w-bw5-16
   local acc=if row.mine then {r,g,b} elseif row.me then {255,95,95} else {70,70,82}
   themeBG(bx5,ky,bw5,22,5,math.floor(bgA(225)*al/255),acc[1],acc[2],acc[3])
   if row.mine or row.me then R.rectangle(bx5+4,ky+5,2,12,acc[1],acc[2],acc[3],al) end
   R.text_ex(bx5+12,ky+4,text,sty(12,'ui',nil,false,235,235,240,al))
   ky=ky+26
  end
 end

 DBG.mark('toasts')
 -- notifications (right side, slide in)
 if #TOASTS>0 then
  for i=#TOASTS,1,-1 do if t-TOASTS[i].at>3.5 then table.remove(TOASTS,i) end end
  local ty0=math.floor(h*.42)
  for i,tt in ipairs(TOASTS) do
   local age=t-tt.at
   local fin=math.clamp(age/.2,0,1)
   local al=math.floor(255*math.min(fin,math.clamp((3.5-age)/.4,0,1)))
   local tw=tt.w
   if not tw then tw=(renderer.measure_text(tt.text,12,'ui') or #tt.text*6);tt.w=tw end
   local bw6=tw+26
   local bx6=if S.perfMode then w-16-bw6 else w-16-bw6+math.floor((1-fin)*(bw6+20))
   local by6=ty0+(i-1)*28
   local c=tt.col or {r,g,b}
   themeBG(bx6,by6,bw6,22,5,math.floor(bgA(230)*al/255),c[1],c[2],c[3])
   R.text_ex(bx6+14,by6+4,tt.text,sty(12,'ui',nil,false,235,235,240,al))
  end
 end

 DBG.mark('stats')
 -- stats panel (bottom right)
 if S.statsOn and not menuOpenD then
  if t>=(STATS.txtAt or 0) then
   STATS.txtAt=t+.5
   local function line(st)
    local acc=if st.shots>0 then math.floor(st.hits/st.shots*100+.5) else 0
    return 'K '..st.k..'   HS '..st.hs..'   ACC '..acc..'%   DMG '..math.floor(st.dmg)
   end
   STATS.tr='ROUND   '..line(STATS.round);STATS.tm='MATCH   '..line(STATS.match)
   STATS.tb='BEST STREAK   '..tostring(math.max(STATS.best,STREAK.n))
  end
  local sw2,sh2=230,64
  local sx2,sy2=w-sw2-16,h-sh2-16
  themeBG(sx2,sy2,sw2,sh2,7,bgA(225),r,g,b)
  local stS=sty(11,'ui',nil,false,Z.C_TEXT[1],Z.C_TEXT[2],Z.C_TEXT[3],255)
  R.rectangle(sx2+6,sy2,sw2-12,2,r,g,b,255)
  R.text_ex(sx2+10,sy2+6,STATS.tr or '',stS)
  R.text_ex(sx2+10,sy2+24,STATS.tm or '',stS)
  R.text_ex(sx2+10,sy2+42,STATS.tb or '',stS)
 end

 DBG.mark('dmg indicator')
 -- damage indicator around the crosshair
 if S.dmgInd then
  if t>=DI.next then DI.next=t+(if S.perfMode then .2 else .1);pcall(updateDamage,cx,cy) end
  if DI.slot then
   DI.shown=DI.shown+(DI.dmg-DI.shown)*k
   local lethal=DI.dmg>=DI.hp and DI.dmg>0
   local cr,cg,cb=r,g,b
   if lethal then cr,cg,cb=120,230,140 end
   local sweep=math.floor(360*math.clamp(DI.shown/math.max(DI.hp,1),0,1))
   if sweep>0 then R.arc(cx,cy,17,-90,sweep,cr,cg,cb,255,3,math.max(2,math.floor(sweep/360*8))) end
   if DI.dmg>0 then
    R.text_ex(cx+24,cy-8,if lethal then 'KILL' else tostring(math.floor(DI.dmg+.5)),
     sty(12,'ui_bold',nil,true,cr,cg,cb,255))
   end
  else
   DI.shown=0
  end
 end

 DBG.mark('bomb+streak')
 -- bomb timer (top center)
 if S.bombOn and (BOMB.planted or BOMB.planter) then
  local ct=globals.curtime()
  local bw4,bh4=240,if BOMB.defuser then 58 else 42
  local bx4,by4=cx-120,48
  themeBG(bx4,by4,bw4,bh4,7,bgA(230),r,g,b)
  if BOMB.planted and BOMB.explodeAt then
   local left=math.max(0,BOMB.explodeAt-ct)
   local f=math.clamp(left/math.max(BOMB.total or Z.C4_TIME,1),0,1)
   local br,bg2,bb=r,g,b
   if left<5 then br,bg2,bb=255,90,90 elseif left<10 then br,bg2,bb=255,170,80 end
   R.text_ex(bx4+12,by4+7,'BOMB'..(if BOMB.site then '  '..tostring(BOMB.site) else ''),
    sty(13,'ui_bold',nil,false,br,bg2,bb,255))
   R.text_ex(bx4+bw4-12,by4+7,string.format('%.1f s',left),sty(13,'ui_bold','right',false,Z.C_TEXT[1],Z.C_TEXT[2],Z.C_TEXT[3],255))
   R.rounded_rectangle(bx4+12,by4+28,bw4-24,5,40,40,50,255,2)
   R.rounded_rectangle(bx4+12,by4+28,math.floor((bw4-24)*f),5,br,bg2,bb,255,2)
   if BOMB.defuser and BOMB.defEnd then
    local dl=math.max(0,BOMB.defEnd-ct)
    local ok2=BOMB.defEnd<=BOMB.explodeAt
    local name=entity.get_name(BOMB.defuser) or ('#'..BOMB.defuser)
    R.text_ex(bx4+12,by4+38,'Defusing: '..name..(if BOMB.kit then ' (kit)' else ''),sty(12,'ui',nil,false,Z.C_TEXT[1],Z.C_TEXT[2],Z.C_TEXT[3],255))
    R.text_ex(bx4+bw4-12,by4+38,string.format('%.1f s',dl)..(if ok2 then '  OK' else '  LATE'),
     {size=12,font='ui_bold',align='right',color=if ok2 then {120,230,140,255} else {255,95,95,255}})
   end
  else
   local name=entity.get_name(BOMB.planter) or ('#'..tostring(BOMB.planter))
   R.text_ex(bx4+12,by4+7,'BOMB',sty(13,'ui_bold',nil,false,r,g,b,255))
   R.text_ex(bx4+12,by4+24,'Planting: '..name,sty(12,'ui',nil,false,Z.C_TEXT[1],Z.C_TEXT[2],Z.C_TEXT[3],255))
  end
 end

 -- kill streak announcement
 if S.streakOn and t-STREAK.showAt<2.2 then
  local age=t-STREAK.showAt
  local pop=1-math.clamp(age/.18,0,1)
  local al=math.floor(255*math.clamp((2.2-age)/.5,0,1))
  R.text_ex(cx,cy-210-math.floor(pop*8),STREAK.text,{size=30+math.floor(pop*12),font='ui_bold',align='center',
   outline=true,color={r,g,b,al}})
  R.text_ex(cx,cy-172,STREAK.n..' kills in a row',sty(13,'ui','center',true,235,235,240,al))
 end

 DBG.mark('hitlog+killsay')
 -- hit log (slides in, fades out)
 if S.hlOn and #HL>0 then
  local life=S.hlTime
  for i=#HL,1,-1 do if t-HL[i].at>=life then table.remove(HL,i) end end
  local ly2=math.floor(h*.68)
  for i,row in ipairs(HL) do
   local age=t-row.at
   local fin=math.clamp(age/.18,0,1)
   local fout=math.clamp((life-age)/.4,0,1)
   local al=math.min(fin,fout)
   local tw=row.w
   if not tw then tw=(renderer.measure_text(row.text,13,'ui') or #row.text*7);row.w=tw end
   local bw3=tw+30
   local bx3=if S.perfMode then cx-math.floor(bw3/2) else cx-math.floor(bw3/2)+math.floor((1-fin)*30)
   local by3=ly2+(i-1)*30
   local c=if row.hit then COL.hl else Z.MISS_C -- misses stay red
   themeBG(bx3,by3,bw3,24,6,math.floor(bgA(225)*al),c[1],c[2],c[3])
   R.rectangle(bx3+6,by3+6,2,12,c[1],c[2],c[3],math.floor(255*al))
   R.text_ex(bx3+16,by3+4,row.text,sty(13,'ui',nil,false,Z.C_TEXT[1],Z.C_TEXT[2],Z.C_TEXT[3],math.floor(255*al)))
  end
 end

 -- kill say
 if t<ks.till then
  R.text_ex(cx,cy-140,ks.text,sty(22,'ui_bold','center',true,255,255,255,255))
 end

 end -- of the part skipped while the menu is open

 DBG.mark('watermark')
 -- watermark (text rebuilt 4x a second)
 if S.wmOn then
  if t>=tick.wm then
   tick.wm=t+1
   local me=entity.get_local_player()
   local name=(me and entity.get_name(me)) or 'player'
   wm.text='Illusion  |  '..name..'  |  '..math.floor(fps)..' fps  |  '..math.floor((client.latency() or 0)*1000)..' ms'
   wm.w=renderer.measure_text(wm.text,13,'ui_bold') or (#wm.text*7)
  end
  local lw=if S.logoOn and LOGO then 20 else 0
  local ww=wm.w+20+lw
  local bx=math.floor(w-ww-16)
  local wr,wg,wb=COL.wm[1],COL.wm[2],COL.wm[3]
  themeBG(bx,12,ww,26,6,bgA(225),wr,wg,wb)
  R.rectangle(bx+6,12,ww-12,2,wr,wg,wb,255)
  if lw>0 then R.texture(LOGO,bx+8,17,16,16,wr,wg,wb,255) end
  R.text_ex(bx+10+lw,18,wm.text,sty(13,'ui_bold',nil,false,Z.C_TEXT[1],Z.C_TEXT[2],Z.C_TEXT[3],255))
 end

 if not S.hkOn then return end
 local hr,hg,hb=COL.hk[1],COL.hk[2],COL.hk[3]

 DBG.mark('hotkey squares')
 -- fixed squares: left side, centered
 if S.hkStyle~=2 then
 local bw,bh,gap=58,30,6
 local sy=math.floor(h/2-(#binds*(bh+gap)-gap)/2)
 for i,bnd in ipairs(binds) do
  local by=sy+(i-1)*(bh+gap)
  themeBG(16,by,bw,bh,6,bgA(225),hr,hg,hb)
  R.rectangle(21,by+6,2,bh-12,hr,hg,hb,255)
  drawIcon(bnd.icon,35,by+15,bnd.dir)
  R.text_ex(46,by+7,bnd.short,sty(14,'ui_bold',nil,false,Z.C_TEXT[1],Z.C_TEXT[2],Z.C_TEXT[3],255))
 end
 end
 if S.hkStyle==3 then return end

 DBG.mark('hotkey panel')
 -- draggable "Hotkeys" panel (drag the header with the menu open)
 local PW,HH,RH=150,26,22
 for _,bnd in ipairs(binds) do if bnd.tw and bnd.tw+52>PW then PW=math.floor(bnd.tw+52) end end
 local px=hk.x or 20
 local py=hk.y or math.floor(h*.22)
 if FR.menu then
  local mx,my=client.mouse_position()
  if client.key_state('Mouse1') then
   if not hk.drag and mx>=px and mx<=px+PW and my>=py and my<=py+HH then hk.drag=true;hk.dx=mx-px;hk.dy=my-py end
   if hk.drag then
    px=math.clamp(mx-hk.dx,0,w-PW);py=math.clamp(my-hk.dy,0,h-HH)
    hk.x,hk.y=px,py
   end
  elseif hk.drag then
   hk.drag=false;storage.set('hk_x',px);storage.set('hk_y',py)
  end
 else
  hk.drag=false
 end
 themeBG(px,py,PW,HH,7,bgA(230),hr,hg,hb)
 R.rectangle(px+6,py,PW-12,2,hr,hg,hb,255)
 R.text_ex(px+10,py+5,'Hotkeys',sty(14,'ui_bold',nil,false,Z.C_TEXT[1],Z.C_TEXT[2],Z.C_TEXT[3],255))
 if #binds>0 then
  -- one background behind all rows, then a name and a small switch per row
  themeBG(px,py+HH+4,PW,#binds*RH,5,bgA(170),hr,hg,hb)
  for i,bnd in ipairs(binds) do
   local ry=py+HH+4+(i-1)*RH
   R.text_ex(px+8,ry+3,bnd.name,sty(12,'ui',nil,false,Z.C_TEXT[1],Z.C_TEXT[2],Z.C_TEXT[3],255))
   R.rounded_rectangle(px+PW-30,ry+5,22,11,hr,hg,hb,255,5)
  end
 end
end

---------------------------------------------------------------- loading splash (first seconds only)
Z.LOAD_AT=now()
local function drawLoader(w,h)
 local age=now()-Z.LOAD_AT
 if age>3 then Z.LOADED=true;return end
 local a=math.clamp(math.min(age/.25,(3-age)/.4),0,1)
 local c=S.colUI
 local bw,bh=280,78
 local x,y=math.floor(w/2-bw/2),math.floor(h/2-bh/2)
 R.rounded_rectangle(x,y,bw,bh,12,10,26,math.floor(245*a),6)
 R.rectangle(x+6,y,bw-12,2,c[1],c[2],c[3],math.floor(255*a))
 R.text_ex(math.floor(w/2),y+14,'ILLUSION',sty(22,'ui_bold','center',false,c[1],c[2],c[3],math.floor(255*a)))
 R.text_ex(math.floor(w/2),y+40,'loading...',sty(11,'ui','center',false,136,130,166,math.floor(255*a)))
 local p=math.clamp(age/2.4,0,1)
 R.rounded_rectangle(x+24,y+60,bw-48,4,28,24,52,math.floor(255*a),2)
 R.rounded_rectangle(x+24,y+60,math.max(4,math.floor((bw-48)*p)),4,c[1],c[2],c[3],math.floor(255*a),2)
end

on('paint',function()
 RF=RF+1;DRAW.n=0;DRAW.fresh=true;FC.frame=nil
 frameBegin()
 drawFrame(if FR.menu then 190 elseif S.perfMode then 280 else 375)
 local ok,err=pcall(draw)
 DBG.mark(nil)
 if not ok then
  local _,h=client.screen_size()
  R.text(20,h-40,255,110,110,255,'Illusion draw error: '..tostring(err),12)
 end
 -- least important drawing last, so it only uses budget that is left over
 if #SOULS>0 and not FR.menu then pcall(drawSouls,FR.t) end
 if not Z.LOADED then pcall(drawLoader,FR.w,FR.h) end
 DBG.on=S.dbgOn==true
 if DBG.on then pcall(drawDebug) end
end)

client.log('[Illusion] loaded')
