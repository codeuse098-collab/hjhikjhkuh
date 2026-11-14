-- One transparent PNG embedded as Base64. Load once; draw each frame.
local enabled=ui.new_checkbox('Custom image')
local logo=renderer.load_png_base64('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAF0lEQVR4nGP4/////5QTAQ0MYIKBgQEAYbAH9SFplrAAAAAASUVORK5CYII=')
-- Raw RGBA alternative: a half-transparent red pixel next to a transparent green pixel.
local pixels=renderer.load_rgba(string.char(255,0,0,128,0,255,0,0),2,1)
client.set_event_callback('paint',function()
    if not ui.get(enabled) then return end
    renderer.texture(logo,30,100,64,64,255,255,255,255)
    renderer.texture(pixels,110,100,128,64,255,255,255,255)
end)
