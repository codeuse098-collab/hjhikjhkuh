-- gui.* showcase: a full script menu on the built-in widget library. RightShift opens / closes it.
-- Every element type, theme switching, elements linked to the game's own settings, own keybinds, notifications,
-- saving the menu's values in session storage.

local win = gui.window({ title = 'showcase', subtitle = 'gui.* demo', width = 680, height = 500, theme = 'default' })

-- a game setting may not exist yet (its menu section was never opened): link only when it does
local function linked(key)
	local ok = pcall(ui.get_setting_info, key)
	return ok and key or nil
end

-- Rage tab ------------------------------------------------------------------------------------------------------
local rage = win:tab('Rage')
local aim = rage:group('Aimbot', 'left')
local enabled = aim:toggle('Enabled', { default = true, bind = 'None', mode = 'Toggle', flag = 'enabled',
	tooltip = 'Bind it: click the box on the right, right-click for the mode' })
local fov = aim:slider('Field of view', 0, 180, 90, { step = 1, suffix = '°', flag = 'fov' })
local hitbox = aim:dropdown('Target hitbox', { 'Head', 'Chest', 'Stomach', 'Legs' }, 1, { flag = 'hitbox' })
local points = aim:multiselect('Multi-point', { 'Head', 'Chest', 'Stomach', 'Arms', 'Legs' }, { true, true }, { flag = 'points' })
local chance = aim:slider('Hit chance', 0, 100, 60, { step = 1, suffix = '%', flag = 'hc' })

local other = rage:group('Other', 'right')
other:label('Elements can edit the game\'s own settings: they then work like the built-in menu.')
local dtKey = linked('Rage.doubleTap')
if dtKey then other:toggle('Double tap (game)', { link = dtKey }) end
local hcKey = linked('Rage.hitchance')
if hcKey then other:slider('Hit chance (game)', 0, 100, 0, { link = hcKey }) end
local peek = other:keybind('Peek key', 'X', 'Hold', { flag = 'peek' })
other:button('Say hi', function() gui.notify('Hello from ' .. (win:is_open() and 'an open menu' or 'a closed menu'), { title = 'showcase' }) end)

-- Visuals tab ---------------------------------------------------------------------------------------------------
local visuals = win:tab('Visuals')
local esp = visuals:group('ESP')
local boxes = esp:toggle('Boxes', { default = true, flag = 'boxes' })
local boxColor = esp:color('Box color', 120, 200, 255, 255, { flag = 'boxColor' })
local names = esp:toggle('Names', { flag = 'names' })
local style = esp:dropdown('Box style', { 'Full', 'Corners' }, 1, { flag = 'boxStyle' })

local world = visuals:group('World')
local smoke = world:toggle('Remove smoke', { flag = 'smoke' })
smoke:on_change(function(on) client.set_smoke_hidden(on) end)
local caption = world:textbox('Watermark text', 'showcase', { placeholder = 'type something', flag = 'caption' })

-- Settings tab: themes + config ---------------------------------------------------------------------------------
local settings = win:tab('Settings')
local look = settings:group('Look')
local themes = gui.themes()
local theme = look:dropdown('Theme', themes, table.find(themes, 'default'))
theme:on_change(function() win:set_theme(theme:get_option()) end)
local accent = look:color('Accent', 108, 138, 255, 255)
accent:on_change(function(c)
	local r, g, b = c.Color.R * 255, c.Color.G * 255, c.Color.B * 255
	win:set_theme({ preset = theme:get_option(), accent = { r, g, b } })
end)

local config = settings:group('Config')
config:label('Values of flagged elements: kept in session storage (until you leave the game).')
config:button('Save', function() storage.set('menu', win:export()); gui.notify('Saved', { title = 'config' }) end)
config:button('Load', function()
	local data = storage.get('menu')
	if data then win:import(data); gui.notify('Loaded', { title = 'config' }) else gui.notify('Nothing saved yet', { title = 'config', color = { 255, 120, 90 } }) end
end)

-- what the elements drive: a small watermark and the ESP boxes ---------------------------------------------------
client.set_event_callback('paint', function()
	renderer.text_ex(20, 20, caption:get() .. (enabled:is_active() and '  [rage]' or ''), { size = 14, font = 'ui_bold', outline = true })
	if not boxes:get() then return end
	local r, g, b, a = boxColor:get().Color.R * 255, boxColor:get().Color.G * 255, boxColor:get().Color.B * 255, (boxColor:get().Alpha or 1) * 255
	for _, slot in entity.get_players(true) do
		if entity.is_alive(slot) then
			local x, y, z = entity.get_origin(slot)
			local foot = { renderer.world_to_screen(x, y, z) }
			local head = { renderer.world_to_screen(x, y + 72, z) }
			if foot[1] and head[1] then
				local h = foot[2] - head[2]
				local w = h * 0.45
				if style:get() == 1 then
					renderer.rectangle_outline(head[1] - w / 2, head[2], w, h, r, g, b, a, 1)
				else
					local c = w / 4
					for _, p in { { head[1] - w / 2, head[2], 1, 1 }, { head[1] + w / 2, head[2], -1, 1 }, { head[1] - w / 2, foot[2], 1, -1 }, { head[1] + w / 2, foot[2], -1, -1 } } do
						renderer.line(p[1], p[2], p[1] + c * p[3], p[2], r, g, b, a, 1)
						renderer.line(p[1], p[2], p[1], p[2] + c * p[4], r, g, b, a, 1)
					end
				end
				if names:get() then renderer.text_ex(head[1], head[2] - 16, entity.get_name(slot) or '', { align = 'center', size = 13, outline = true }) end
			end
		end
	end
end)

gui.notify('RightShift opens / closes the menu', { title = 'showcase', duration = 5 })
