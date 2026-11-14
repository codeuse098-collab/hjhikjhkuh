-- Original Hysteria logo from Hysteria Debug.lua, not the butterfly.
-- Paste into Config > Lua and press Load / reload. Enabled immediately.
local left=renderer.load_png_base64('iVBORw0KGgoAAAANSUhEUgAAABoAAAAPCAYAAAD6Ud/mAAAABHNCSVQICAgIfAhkiAAAAmlJREFUOE+9VD2IknEY/79XBMcJuljh4js15RdYTg2hNFTQIAkiTTqYo8Op4Dk0CBp3QyEuCpIldCB0WIv40uKQYClOdzqkgxG2qNxxm/Z7Xv9/uyQy4rgHHny+3t/v+XhfJXZBIl0QD1OJRqPRe71e/4Dser1+dAcC88d5NkFEW36//9jr9TKn08kCgQDL5/PnMalvPB6/bjabzOVymQjQAf3U7/eZ0WhkkiTtw39Gg65MpYd/FXoC7a9MexP+nMcpLw+HwyODwXAlnU6zSCQiEREB7M7n8yeDwYDpdDqm1WpVHPhKuVw+DYfDDwUwGmGtVotZrVYWj8e/RKNRi0ajuSTynU7nm9lsNpxtpN1uL26UzWa/B4PBa2RTB91ul+VyObrXaaFQ2KQ4+Yqi0Bpa0+nUMpvNNmq12onb7d4qlUrM5/MtsXEKtZ4IbDabGiciGQ98pftwoGXH6P4Q+Q7yHnE/u91OTV0XtbjDcgOTyYQ20ka9ler52rYTiYSbiJy4T43fhyWTSSUWizk50CvkywA7IEBZlpkAbjQazOFwMDENwNWXKZVKVdHIPZqCztDr9abFYvFQymQy+6FQ6DEf8yXym7hXQOxhZ2fns8fjsZhMpssUo67phpj2GA1qqEEhvLkySN1ESkK41WpVXd1bqIcXP8LvLWhcPIx7zCqVygbdQOyeA35Ezd0lyy/jKczsSvwNEb04E9yDTR9qFEqtGjDdojUu4jZwb0NvQOnzEHIAQ+Ex8XY04KtEf5MPSN7/Q8E2Ys/XPPtbeh0RTUOAi3eUsRZ0F/oOSh/mP8s6IgEkc+D//v/7CRz7BXkxEuNsAAAAAElFTkSuQmCC')
local right=renderer.load_png_base64('iVBORw0KGgoAAAANSUhEUgAAABgAAAAPCAYAAAD+pA/bAAAABHNCSVQICAgIfAhkiAAAAghJREFUOE/VUz1oWlEUPs9glyQoEYe4+Ai1YJIWJYW6iT8lY6GjxoDoUAJdMuhUNKNCO7QOGdRNCUFok6lQlWIHySAVkkGcdJBShGALpVhoX79zcx88KaQgZMiFj3Pueeec77sfPIVu+Cg3vJ/mIVicTqdjk8n0x2w2L/1P4DwErzVNez4cDklV1ScgOL2OxEiwiEYV+AEMDEObyDV55/onwCvvO4gVmdsReYdxVlj0tN1uH/h8Pl4kTq1W6wQCgXs2m23ZqG48Hv+22+0LXJMvCCP9OhqNOg6H4w7Xu90ueTweqlarFI1GFaXf7393uVzL+XyekFOxWBRNXq+XJpMJWSwWUpSrhyYSCQoGgxSJRIj70+n0Fno63JNMJqlUKtFgMCCr1cp4y+IV+Kk/XyzRl/MyJpNKPktbvmDhKvdhQatSqdhAttFoNCgcDh+Xy+WH8Xh8Td6FfYJAX2qw41W9Xt8PhUK6svv4dtFsNt/Duu1Wq/XL7/cf5XK53VQqpYt4BvJDw4t9mDlToELjJxtPoVC4jMViK1LpOeIDzjOZTDubzfKgOGwdW+J0OsWdlbMoPr1e76fb7V5nc2cskrMfEB8D34A3wAtZf4m4bxDTQb41o272ssMEj4CorPPCj8BdYEPWTliczFXEBGABzoB3wB7AFg5ZOLANTAAxN8+Pdo3gfz/dfoK/KS67ix7SE9MAAAAASUVORK5CYII=')
local enabled=ui.new_checkbox('Hysteria logo')
local scale=ui.new_slider('Logo scale',1,8,4)
local opacity=ui.new_slider('Logo opacity',0,255,255)
local accent=ui.new_color_picker('Logo accent',160,205,80,255)
ui.set(enabled,true)
client.set_event_callback('paint',function()
    if not ui.get(enabled) then return end
    local sw,sh=client.screen_size()
    local k=ui.get(scale)
    local x,y=math.floor((sw-50*k)/2),math.floor(sh/2-15*k/2)
    local r,g,b,a=ui.get(accent)
    local alpha=ui.get(opacity)*a/255
    -- Original render.logo layout: left 26x15, right 24x15, directly adjacent.
    renderer.texture(left,x,y,26*k,15*k,r,g,b,alpha)
    renderer.texture(right,x+26*k,y,24*k,15*k,255,255,255,alpha)
end)
client.log('Hysteria logo loaded. Close the menu: logo is in the screen center.')
