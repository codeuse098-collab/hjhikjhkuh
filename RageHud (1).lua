--[[
RAGEHUD // READ-ONLY LAB BUILD
Version: 0.5.1

Built from the supplied Lua examples plus selected Illusion architecture patterns:
GUI showcase, both AA builders, bomb/legit AA state example, resolver and rage
hooks, HUD examples, public-snapshot ESP, extended visuals, hitlog, tracers,
impact effects, grenade warning, custom camera, and image/logo tests.

SAFETY / SCOPE:
- This build is a diagnostics + UI prototype.
- It DOES NOT write cmd.yaw / cmd.pitch / cmd.desync_*.
- It DOES NOT override the resolve callback or alter rage target/point/fire.
- It uses public snapshots and confirmed shot events for display/analysis.
- The "AA Lab" is a profile preview/simulator, not an anti-aim actuator.
- The built-in "Perfect" config sets only AA preview + resolver diagnostic settings; it does not configure live LBY packet/angle manipulation.
- Performance mode adds a frame-local entity cache and a script-side draw budget.
- Resolver Lab adds per-target yaw history, circular means, jitter signatures, five reference hypotheses,
  and per-target hit/miss totals; no candidate is selected or forced into the game's resolver.

Runtime expected: the custom Lua client API shown in the uploaded examples.
Some optional callbacks/data fields vary by client build; guarded where practical.
]]

local VERSION = "0.5.1"
local ACCENT = {125, 209, 167, 255}
local WHITE  = {235, 242, 247, 255}
local MUTED  = {155, 169, 180, 255}
local PANEL  = {17, 23, 28, 238}

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
    return nil
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function now()
    return safe(globals.realtime) or 0
end

local function local_player()
    return safe(entity.get_local_player)
end

local function color_picker(label, default)
    local id = ui.new_color_picker(label, default[1], default[2], default[3], default[4])
    return id
end

-- Forward declarations: the Resolver Lab controls are built before the data stores below.
local targetSnapshots, resolverRecords, record_target_shot

-- GUI: gui-showcase.lua pattern, with Rage / Resolver / AA Lab / Visuals / Settings.
local win = gui.window({
    title = "RageHud",
    width = 720,
    height = 540,
    theme = "default"
})

local rageTab = win:tab("Overview")
local overview = rageTab:group("Session", "left")
local hudEnabled = overview:toggle("Telemetry HUD", {default = true, flag = "hud"})
local hitlogEnabled = overview:toggle("Confirmed hitlog", {default = true, flag = "hitlog"})
local tracersEnabled = overview:toggle("Confirmed bullet tracers", {default = true, flag = "tracers"})
local impactsEnabled = overview:toggle("Impact effects", {default = true, flag = "impacts"})
local rightOverview = rageTab:group("Status", "right")
rightOverview:label("READ-ONLY BUILD")
rightOverview:label("No aim, resolver override, or anti-aim command writes.")
rightOverview:label("RightShift opens / closes the menu.")

-- Resolver lab: hypothesis display only; no resolve callback is registered.
local resolverTab = win:tab("Resolver Lab")
local resolverGroup = resolverTab:group("Analysis", "left")
local resolverEnabled = resolverGroup:toggle("Resolver telemetry", {default = true, flag = "resolver"})
local showAngles = resolverGroup:toggle("Show public yaw hypotheses", {default = true, flag = "resolver_angles"})
local showHistory = resolverGroup:toggle("Show per-target yaw history", {default = true, flag = "resolver_history"})
local showCandidates = resolverGroup:toggle("Compare reference hypotheses", {default = true, flag = "resolver_candidates"})
local historyLength = resolverGroup:slider("History samples / target", 4, 32, 16, {flag = "resolver_history_len"})
local maxTargets = resolverGroup:slider("Tracked targets", 1, 16, 8, {flag = "resolver_max"})
local resolverInfo = resolverTab:group("Method", "right")
resolverInfo:label("Per-target yaw history + circular mean + jitter signature.")
resolverInfo:label("Compares low / half / full-range references to public feet.")
resolverInfo:label("Hit / miss totals are per target, never assigned to a candidate.")
resolverInfo:label("Read-only: no resolve callback or aim-angle overrides.")
resolverGroup:button("Clear resolver observations", function()
    targetSnapshots = {}
    resolverRecords = {}
    safe(gui.notify, "Resolver observations cleared", {title = "RageHud"})
end)

-- AA Lab: profile controls are only used for a visual preview.
local aaTab = win:tab("AA Lab")
local aaLeft = aaTab:group("Profile preview", "left")
local aaState = aaLeft:dropdown("Preview state", {"Shared", "Standing", "Moving", "Air", "Duck", "Bomb", "Legit"}, 1, {flag = "aa_state"})
local aaYaw = aaLeft:slider("Preview yaw offset", -180, 180, 180, {flag = "aa_yaw"})
local aaJitter = aaLeft:slider("Preview jitter range", 0, 180, 40, {flag = "aa_jitter"})
local aaPitch = aaLeft:dropdown("Preview pitch", {"Off", "Down", "Up", "Zero", "Jitter"}, 1, {flag = "aa_pitch"})
local aaBody = aaLeft:slider("Preview body amount", 0, 58, 58, {flag = "aa_body"})
local aaSide = aaLeft:dropdown("Preview body side", {"Left", "Right", "Jitter", "Random"}, 3, {flag = "aa_side"})
local aaRight = aaTab:group("Important", "right")
aaRight:label("These values are a sandbox preview only.")
aaRight:label("They are not written to anti_aim commands.")
aaRight:label("The five movement states mirror aa-builder-extended.lua.")

-- Visuals: public snapshots only.
local visualsTab = win:tab("Visuals")
local visualsGroup = visualsTab:group("Public snapshot ESP", "left")
local espEnabled = visualsGroup:toggle("Public player labels", {default = true, flag = "esp"})
local espHealth = visualsGroup:toggle("Health text", {default = true, flag = "esp_hp"})
local espHead = visualsGroup:toggle("Public head marker", {default = false, flag = "esp_head"})
local espColor = visualsGroup:color("ESP accent", 125, 209, 167, 255, {flag = "esp_color"})
local worldGroup = visualsTab:group("World / utility", "right")
local grenadeEnabled = worldGroup:toggle("Grenade path warnings", {default = true, flag = "grenades"})
local grenadeEnemyOnly = worldGroup:toggle("Enemy grenades only", {default = false, flag = "grenades_enemy"})
local grenadeRadius = worldGroup:slider("Warning radius", 100, 600, 350, {flag = "grenade_radius"})
local cameraEnabled = worldGroup:toggle("Camera override", {default = false, flag = "camera"})
local cameraThird = worldGroup:toggle("Third person", {default = true, flag = "camera_third"})
local cameraDistance = worldGroup:slider("Camera distance", 0, 240, 100, {flag = "camera_dist"})
local cameraFov = worldGroup:slider("Camera FOV", 40, 140, 100, {flag = "camera_fov"})

-- Settings and config persistence.
local settingsTab = win:tab("Settings")
local settingsLook = settingsTab:group("Look", "left")
local themes = safe(gui.themes) or {"default"}
local theme = settingsLook:dropdown("Theme", themes, 1, {flag = "theme"})
local caption = settingsLook:textbox("Watermark", "RageHud", {flag = "caption"})
local accentPicker = settingsLook:color("Accent", 125, 209, 167, 255, {flag = "accent"})
local settingsPerf = settingsTab:group("Performance / HUD", "left")
local debugOverlay = settingsPerf:toggle("Performance debug overlay", {default = false, flag = "debug_overlay"})
local performanceMode = settingsPerf:toggle("Performance mode", {default = true, flag = "performance_mode"})
local drawBudget = settingsPerf:slider("Draw budget / frame", 80, 360, 300, {flag = "draw_budget"})
local hotkeysEnabled = settingsPerf:toggle("Active hotkey panel", {default = true, flag = "hotkeys"})
local hotkeysDraggable = settingsPerf:toggle("Allow dragging hotkey panel", {default = true, flag = "hotkeys_drag"})
local killFeedEnabled = settingsPerf:toggle("Recent kill feed", {default = true, flag = "kill_feed"})
local sessionStatsEnabled = settingsPerf:toggle("Expanded session stats", {default = true, flag = "session_stats"})
settingsPerf:label("Hotkeys use ui.get_binds() when your client exposes it.")

-- Dedicated config tab. "Perfect" is a recommended diagnostic + preview profile.
-- It configures the Resolver Lab and AA Lab display only; it does not actuate anti-aim
-- commands, choke packets, or override the game's resolver.
local configTab = win:tab("Config")
local profileGroup = configTab:group("Built-in profiles", "left")
local configActionGroup = configTab:group("Config management", "right")
local configLbyGroup = configTab:group("Perfect / LBY reference", "left")
local configResolverGroup = configTab:group("Perfect / resolver", "right")
profileGroup:label("PERFECT  —  recommended lab profile")
profileGroup:label("Balances readable telemetry, full history, and a clear AA preview.")
profileGroup:label("Apply it to set the Resolver Lab and AA Lab controls below.")
configLbyGroup:label("AA LAB PREVIEW VALUES")
configLbyGroup:label("State: Standing  |  Yaw: 180  |  Jitter: 40")
configLbyGroup:label("Pitch: Down  |  Body: 58  |  Side: Jitter")
configLbyGroup:label("LBY REFERENCE (display only; not applied to a live controller)")
configLbyGroup:label("Yaw additive: 0  |  Desync reference: 58  |  Max choke reference: 14")
configLbyGroup:label("Left: flick 32 / real -180  |  Right: flick -11 / real -166")
configResolverGroup:label("Resolver telemetry: ON  |  Public yaw: ON")
configResolverGroup:label("History: 32 samples per target  |  Tracked targets: 8")
configResolverGroup:label("History analysis and candidate gaps are observational only.")

local function apply_perfect_profile()
    local values = {
        {resolverEnabled, true}, {showAngles, true}, {showHistory, true},
        {showCandidates, true}, {historyLength, 32}, {maxTargets, 8},
        {aaState, 2}, {aaYaw, 180}, {aaJitter, 40}, {aaPitch, 2},
        {aaBody, 58}, {aaSide, 3},
        {hudEnabled, true}, {hitlogEnabled, true}, {tracersEnabled, true},
        {impactsEnabled, true}, {espEnabled, true}, {espHealth, true},
        {espHead, false}, {grenadeEnabled, true}, {grenadeEnemyOnly, false},
        {grenadeRadius, 350}, {cameraEnabled, false}, {cameraThird, true},
        {cameraDistance, 100}, {cameraFov, 100},
        {debugOverlay, false}, {performanceMode, true}, {drawBudget, 300},
        {hotkeysEnabled, true}, {hotkeysDraggable, true},
        {killFeedEnabled, true}, {sessionStatsEnabled, true}
    }
    for _, item in ipairs(values) do
        safe(item[1].set, item[1], item[2])
    end
    safe(storage.set, "ragehud_active_profile", "Perfect")
    safe(gui.notify, "Perfect profile applied — lab / preview settings only", {title = "RageHud"})
end

profileGroup:button("Apply Perfect", apply_perfect_profile)
profileGroup:button("Reset to Perfect", apply_perfect_profile)
configActionGroup:label("Saved configs are kept in this client session storage.")
configActionGroup:button("Save current config", function()
    safe(storage.set, "ragehud_config", win:export())
    safe(storage.set, "ragehud_config_version", 5)
    safe(gui.notify, "RageHud config saved (v5)", {title = "RageHud"})
end)
configActionGroup:button("Load saved config", function()
    local data = safe(storage.get, "ragehud_config")
    if data then
        safe(win.import, win, data)
        local savedVersion = safe(storage.get, "ragehud_config_version") or 1
        if savedVersion < 5 then
            safe(storage.set, "ragehud_config_version", 5)
            safe(gui.notify, "Older config loaded; new profile fields use defaults", {title = "RageHud"})
        else
            safe(gui.notify, "RageHud config loaded", {title = "RageHud"})
        end
    else
        safe(gui.notify, "No saved config in this session", {title = "RageHud"})
    end
end)
configActionGroup:button("Clear resolver observations", function()
    targetSnapshots = {}
    resolverRecords = {}
    safe(gui.notify, "Resolver observations cleared", {title = "RageHud"})
end)
theme:on_change(function()
    local choice = theme:get_option()
    if choice then safe(win.set_theme, win, choice) end
end)

-- Small image test asset from images.lua: two RGBA pixels, intentionally subtle.
local pixelTexture = safe(renderer.load_rgba, string.char(
    125, 209, 167, 255,
    17, 23, 28, 0
), 2, 1)

-- Performance architecture inspired by Illusion: one frame snapshot, cached entity reads,
-- and a local draw-operation budget. This guard is a script-side limit, not an engine guarantee.
local FRAME = {id = 0, sw = 1920, sh = 1080, ft = 0.016, cache = {}}
local function begin_frame()
    FRAME.id = FRAME.id + 1
    FRAME.cache = {}
    local sw, sh = safe(client.screen_size)
    if type(sw) == "number" and type(sh) == "number" then FRAME.sw, FRAME.sh = sw, sh end
    FRAME.ft = tonumber(safe(globals.frametime)) or 0.016
end
local function cached_entity(slot)
    local key = "ent:" .. tostring(slot)
    if FRAME.cache[key] == nil then FRAME.cache[key] = safe(entity.get, slot) or false end
    return FRAME.cache[key] or nil
end
local function cached_alive(slot)
    local key = "alive:" .. tostring(slot)
    if FRAME.cache[key] == nil then FRAME.cache[key] = safe(entity.is_alive, slot) == true end
    return FRAME.cache[key]
end
local function cached_name(slot)
    local key = "name:" .. tostring(slot)
    if FRAME.cache[key] == nil then FRAME.cache[key] = safe(entity.get_name, slot) or ("Player " .. tostring(slot)) end
    return FRAME.cache[key]
end

local DRAW = {count = 0, limit = 300, dropped = 0}
local R = {}
local function take_draw(n)
    n = n or 1
    if DRAW.count + n > DRAW.limit then DRAW.dropped = DRAW.dropped + n; return false end
    DRAW.count = DRAW.count + n
    return true
end
function R.begin(limit)
    DRAW.count, DRAW.dropped = 0, 0
    DRAW.limit = math.max(40, tonumber(limit) or 300)
end
function R.text(...) if take_draw(1) then return renderer.text(...) end end
function R.text_ex(...) if take_draw(1) then return renderer.text_ex(...) end end
function R.rectangle(...) if take_draw(1) then return renderer.rectangle(...) end end
function R.rounded_rectangle(...) if take_draw(1) then return renderer.rounded_rectangle(...) end end
function R.line(...) if take_draw(1) then return renderer.line(...) end end
function R.circle(...) if take_draw(1) then return renderer.circle(...) end end
function R.polyline(points, ...) if take_draw(math.max(1, #(points or {}))) then return renderer.polyline(points, ...) end end
function R.rectangle_outline(...) if take_draw(4) then return renderer.rectangle_outline(...) end end
function R.arc(x, y, radius, start, sweep, r, g, b, a, thickness, segments)
    if take_draw(segments or math.max(4, math.floor(math.abs(sweep or 0) / 12))) then
        return renderer.arc(x, y, radius, start, sweep, r, g, b, a, thickness, segments)
    end
end
function R.gradient(...) if take_draw(1) then return renderer.gradient(...) end end
function R.triangle(...) if take_draw(2) then return renderer.triangle(...) end end
function R.texture(...) if take_draw(1) then return renderer.texture(...) end end

local DEBUG = {clock = nil, paintMs = 0, maxMs = 0, paints = 0, at = 0, perSecond = 0}
do
    local ok, c = pcall(function() return os.clock end)
    DEBUG.clock = (ok and type(c) == "function") and c or now
end
local function debug_overlay()
    if safe(debugOverlay.get, debugOverlay) ~= true then return end
    local fps = 1 / math.max(FRAME.ft, 0.001)
    local text = string.format("RAGEHUD PERF  %d FPS  /  %.2f ms  /  max %.2f ms", fps, DEBUG.paintMs, DEBUG.maxMs)
    R.rounded_rectangle(18, 62, 350, 48, 17, 23, 28, 220, 7)
    R.text_ex(30, 70, text, {font = "code", size = 11, color = WHITE, outline = true})
    R.text_ex(30, 87, string.format("draw %d/%d  /  skipped %d  /  paint %.0f Hz  /  targets %d",
        DRAW.count, DRAW.limit, DRAW.dropped, DEBUG.perSecond, #targetSnapshots),
        {font = "code", size = 11, color = MUTED, outline = true})
end

-- Data stores.
local frameSamples = {}
local shotRows = {}
local shotStats = {hits = 0, misses = 0, shots = 0, damage = 0, kills = 0}
local killRows = {}
local activeBinds = {}
targetSnapshots = {}
-- Resolver Lab records are session-local diagnostics. They never feed a live resolve callback.
resolverRecords = {}
local grenadeMarkers = {}
local lastShotAt = 0

local function push_shot(text, hit)
    table.insert(shotRows, 1, {text = text, hit = hit, at = now()})
    if #shotRows > 6 then table.remove(shotRows) end
    if hit then shotStats.hits = shotStats.hits + 1
    else shotStats.misses = shotStats.misses + 1 end
    lastShotAt = now()
end

local hitGroups = {"head", "chest", "stomach", "arm", "leg", "neck"}
local missReasons = {"spread", "resolver", "occlusion", "death", "prediction error"}

-- Confirmed shot event: hitlog + tracer pattern from starter-hitlog / bullet-tracers.
client.set_event_callback("shot", function(e)
    local me = local_player()
    if not e or e.shooter ~= me then return end

    local melee = bit and bit.band and bit.band(e.flags or 0, 8) ~= 0
    local extra = bit and bit.band and bit.band(e.flags or 0, 32) ~= 0
    if not melee and not extra then
        shotStats.shots = shotStats.shots + 1
        if (e.victim or 0) > 0 and (e.damage or 0) > 0 then
            shotStats.damage = shotStats.damage + (tonumber(e.damage) or 0)
            if e.killed then shotStats.kills = shotStats.kills + 1 end
        end
    end

    if safe(hitlogEnabled.get, hitlogEnabled) ~= false then
        if (e.victim or 0) > 0 and (e.damage or 0) > 0 then
            local group = hitGroups[e.group] or "body"
            local victim = safe(entity.get_name, e.victim) or ("#" .. tostring(e.victim))
            push_shot(string.format("%s / %s / %d dmg / %d hp%s",
                victim, group, e.damage, e.remainingHealth or 0,
                e.killed and " / KO" or ""), true)
        elseif not extra and (e.aimTarget or 0) > 0 then
            push_shot("Miss / " .. (missReasons[(e.missReason or 0) + 1] or "unclassified"), false)
        end
    end

    -- Aggregate outcomes by target only. The event does not identify a candidate hypothesis,
    -- so the data is deliberately not credited to any left/right/center reference.
    if (e.victim or 0) > 0 and (e.damage or 0) > 0 then
        record_target_shot(e.victim, true, e.damage, nil)
    elseif not extra and (e.aimTarget or 0) > 0 then
        record_target_shot(e.aimTarget, false, 0, missReasons[(e.missReason or 0) + 1] or "unclassified")
    end

    if safe(tracersEnabled.get, tracersEnabled) ~= false and not melee and not extra
        and e.start and e.impact and (e.impact - e.start).Magnitude > 0.001 then
        renderer.tracer(e.start, e.impact, {
            color = ACCENT, width = 2, end_width = 0.5, life = 0.8, fade = 0.3, glow = 1
        })
    end
end)

-- Recent local kills / deaths from the standard player_death event.
client.set_event_callback("player_death", function(e)
    if not e then return end
    local me = local_player()
    local attacker = e.attacker or e.shooter
    local victim = e.slot
    if attacker ~= me and victim ~= me then return end
    local attackerName = attacker and safe(entity.get_name, attacker) or "?"
    local victimName = victim and safe(entity.get_name, victim) or "?"
    local row = {
        text = (attacker == me and "YOU  >  " or "") .. tostring(attackerName) .. "  /  " .. tostring(victimName),
        mine = attacker == me,
        at = now()
    }
    table.insert(killRows, 1, row)
    if #killRows > 4 then table.remove(killRows) end
end)

-- Impact particles / rings from impact-effects.lua.
client.set_event_callback("bullet_impact", function(e)
    if safe(impactsEnabled.get, impactsEnabled) == false then return end
    if not e or e.shooter ~= local_player() or not e.impact then return end
    renderer.effect("sphere", e.impact, {radius = 1.5, color = ACCENT, life = 0.8, fade = 0.5})
    renderer.effect("ring", e.impact, {radius = 5, width = 0.5, color = ACCENT, life = 0.8, fade = 0.5})
    renderer.effect("particles", e.impact, {radius = 0.6, color = ACCENT, count = 12, speed = 60, life = 0.5})
end)

client.set_event_callback("player_hurt", function(e)
    if safe(impactsEnabled.get, impactsEnabled) == false then return end
    if not e or e.shooter ~= local_player() or not e.impact then return end
    renderer.effect("text", e.impact + vector.new(0, 8, 0), {
        text = "-" .. tostring(e.damage or 0), color = {255, 100, 100, 255},
        life = 1, fade = 0.5, text_size = 18
    })
end)

-- Resolver lab: per-target read-only history, circular averaging, jitter signatures,
-- reference hypotheses, and target-level shot observations. Nothing here writes aim angles.
local function wrap_angle(angle)
    if type(angle) ~= "number" or angle ~= angle then return nil end
    return ((angle + 180) % 360) - 180
end

local function angle_delta(a, b)
    if type(a) ~= "number" or type(b) ~= "number" then return nil end
    return wrap_angle(a - b)
end

local function resolver_record(slot)
    local rec = resolverRecords[slot]
    if not rec then
        rec = {
            yawHistory = {}, footHistory = {},
            stats = {shots = 0, hits = 0, misses = 0, damage = 0},
            lastOutcome = "—", lastReason = nil, lastSeen = now(),
            meanYaw = nil, meanFootYaw = nil, concentration = 0,
            jitter = "collecting", flips = 0, deltaAverage = 0
        }
        resolverRecords[slot] = rec
    end
    return rec
end

local function circular_mean(values)
    local sx, sy, n = 0, 0, 0
    for _, value in ipairs(values) do
        if type(value) == "number" then
            local rad = math.rad(value)
            sx, sy, n = sx + math.cos(rad), sy + math.sin(rad), n + 1
        end
    end
    if n == 0 then return nil, 0 end
    local concentration = math.sqrt(sx * sx + sy * sy) / n
    return wrap_angle(math.deg(math.atan2(sy, sx))), concentration
end

local function analyse_yaw_history(history)
    local values, deltas = {}, {}
    for i, sample in ipairs(history) do
        if sample.yaw ~= nil then values[#values + 1] = sample.yaw end
        if i > 1 and sample.yaw ~= nil and history[i - 1].yaw ~= nil then
            local d = angle_delta(sample.yaw, history[i - 1].yaw)
            if d then deltas[#deltas + 1] = d end
        end
    end

    local mean, concentration = circular_mean(values)
    local flips, significant, magnitude = 0, 0, 0
    local previousSign = nil
    for _, d in ipairs(deltas) do
        magnitude = magnitude + math.abs(d)
        if math.abs(d) >= 8 then
            significant = significant + 1
            local sign = d > 0 and 1 or -1
            if previousSign ~= nil and sign ~= previousSign then flips = flips + 1 end
            previousSign = sign
        end
    end

    local averageDelta = #deltas > 0 and magnitude / #deltas or 0
    local pattern = "stable"
    if #values < 5 then
        pattern = "collecting"
    elseif significant >= 4 and flips >= 2 and concentration < 0.82 then
        pattern = "alternating"
    elseif averageDelta >= 18 and flips <= 1 then
        pattern = "drifting"
    elseif concentration < 0.55 then
        pattern = "variable"
    end
    return mean, concentration, pattern, flips, averageDelta
end

local function make_reference_candidates(yaw, range, footYaw)
    if type(yaw) ~= "number" then return {} end
    range = clamp(tonumber(range) or 0, 0, 58)
    local offsets = {
        {name = "Center", offset = 0},
        {name = "Low left", offset = range * 0.25},
        {name = "Low right", offset = -range * 0.25},
        {name = "Half left", offset = range * 0.5},
        {name = "Half right", offset = -range * 0.5},
        {name = "Full left", offset = range},
        {name = "Full right", offset = -range}
    }
    local out = {}
    for _, candidate in ipairs(offsets) do
        local angle = wrap_angle(yaw + candidate.offset)
        local gap = type(footYaw) == "number" and math.abs(angle_delta(angle, footYaw)) or nil
        out[#out + 1] = {
            name = candidate.name,
            offset = candidate.offset,
            angle = angle,
            publicFootGap = gap
        }
    end
    return out
end

local function refresh_targets()
    targetSnapshots = {}
    if safe(resolverEnabled.get, resolverEnabled) == false then return end
    local players = safe(entity.get_players, true) or {}
    local limit = safe(maxTargets.get, maxTargets) or 8
    local maxHistory = safe(historyLength.get, historyLength) or 16
    local stamp = now()

    for _, slot in ipairs(players) do
        if #targetSnapshots >= limit then break end
        if safe(entity.is_alive, slot) then
            local obj = safe(entity.get, slot)
            if obj then
                local yaw = wrap_angle(tonumber(obj.yaw))
                local footYaw = wrap_angle(tonumber(obj.foot_yaw))
                local maxDesync = clamp(tonumber(obj.max_desync) or 0, 0, 58)
                local rec = resolver_record(slot)
                rec.lastSeen = stamp

                if yaw ~= nil or footYaw ~= nil then
                    table.insert(rec.yawHistory, {at = stamp, yaw = yaw, footYaw = footYaw})
                    while #rec.yawHistory > maxHistory do table.remove(rec.yawHistory, 1) end
                end

                local yawValues, footValues = {}, {}
                for _, sample in ipairs(rec.yawHistory) do
                    if sample.yaw ~= nil then yawValues[#yawValues + 1] = sample.yaw end
                    if sample.footYaw ~= nil then footValues[#footValues + 1] = sample.footYaw end
                end
                rec.meanYaw, rec.concentration, rec.jitter, rec.flips, rec.deltaAverage = analyse_yaw_history(rec.yawHistory)
                rec.meanFootYaw = circular_mean(footValues)

                table.insert(targetSnapshots, {
                    slot = slot,
                    name = safe(entity.get_name, slot) or ("Player " .. tostring(slot)),
                    yaw = yaw,
                    footYaw = footYaw,
                    maxDesync = maxDesync,
                    health = tonumber(obj.health),
                    meanYaw = rec.meanYaw,
                    meanFootYaw = rec.meanFootYaw,
                    concentration = rec.concentration,
                    jitter = rec.jitter,
                    flips = rec.flips,
                    deltaAverage = rec.deltaAverage,
                    samples = #rec.yawHistory,
                    stats = rec.stats,
                    lastOutcome = rec.lastOutcome,
                    lastReason = rec.lastReason,
                    history = rec.yawHistory,
                    candidates = make_reference_candidates(yaw or rec.meanYaw, maxDesync, footYaw)
                })
            end
        end
    end

    -- Drop records for targets that have been absent for a while; keep recent history through brief visibility gaps.
    for slot, rec in pairs(resolverRecords) do
        if stamp - (rec.lastSeen or stamp) > 12 then resolverRecords[slot] = nil end
    end
end

record_target_shot = function(slot, hit, damage, reason)
    if type(slot) ~= "number" or slot <= 0 then return end
    local rec = resolver_record(slot)
    rec.stats.shots = rec.stats.shots + 1
    if hit then
        rec.stats.hits = rec.stats.hits + 1
        rec.stats.damage = rec.stats.damage + (tonumber(damage) or 0)
        rec.lastOutcome = "HIT"
        rec.lastReason = nil
    else
        rec.stats.misses = rec.stats.misses + 1
        rec.lastOutcome = "MISS"
        rec.lastReason = reason or "unclassified"
    end
end

client.every(0.25, refresh_targets)

-- HUD frame-time samples are collected once in the consolidated paint callback below.

-- Grenade path and landing warning from grenade-warning.lua.
local grenadeNames = {he = "HE", smoke = "SMOKE", molotov = "MOLOTOV",
    incendiary = "INCENDIARY", flash = "FLASH", decoy = "DECOY"}

local function draw_grenades()
    if safe(grenadeEnabled.get, grenadeEnabled) == false then return end
    local me = local_player()
    local state = safe(entity.get_local_state)
    local origin = state and state.move and state.move.origin
    local seen = {}
    local list = safe(entity.get_grenades) or {}
    local closest = nil

    for _, g in ipairs(list) do
        local enemy = g.thrower ~= me and safe(entity.is_enemy, g.thrower)
        local allowed = safe(grenadeEnemyOnly.get, grenadeEnemyOnly) ~= true or enemy
        if allowed and g.path then
            local px, py = renderer.world_to_screen(g.origin.X, g.origin.Y, g.origin.Z)
            for _, p in ipairs(g.path) do
                local x, y = renderer.world_to_screen(p.X, p.Y, p.Z)
                if px and x then R.line(px, py, x, y, 125, 209, 167, 210, 2) end
                px, py = x, y
            end

            local land = g.landing
            if land then
                local x, y = renderer.world_to_screen(land.X, land.Y + 10, land.Z)
                if x then
                    R.text(x - 30, y - 8, 125, 209, 167, 255,
                        string.format("%s %.1fs", grenadeNames[g.type] or tostring(g.type), g.time_left or 0), 14)
                end
                if enemy and origin and g.type ~= "smoke" then
                    local dist = (land - origin).Magnitude
                    if dist <= (safe(grenadeRadius.get, grenadeRadius) or 350)
                        and (not closest or dist < closest.dist) then
                        closest = {dist = dist, time = g.time_left or 0, name = grenadeNames[g.type] or tostring(g.type)}
                    end
                end
            end
            seen[g.id] = true
        end
    end
    for id, marker in pairs(grenadeMarkers) do
        if not seen[id] then
            if marker and marker.effect then safe(renderer.remove_effect, marker.effect) end
            grenadeMarkers[id] = nil
        end
    end
    if closest then
        local sw, sh = client.screen_size()
        R.rounded_rectangle(sw/2 - 160, sh*0.24 - 5, 320, 30, 20, 22, 27, 190, 6)
        R.text(sw/2 - 148, sh*0.24 + 2, 255, 100, 100, 255,
            string.format("! %s landing %.0f units away / %.1fs", closest.name, closest.dist, closest.time), 14)
    end
end

-- Public ESP: based on showcase-esp / visuals / extended-visuals.
local function draw_public_esp()
    if safe(espEnabled.get, espEnabled) == false then return end
    local r, g, b, a = 125, 209, 167, 255
    local c = safe(espColor.get, espColor)
    if type(c) == "table" then r, g, b, a = c[1] or r, c[2] or g, c[3] or b, c[4] or a end

    local drawn = 0
    for _, slot in ipairs(safe(entity.get_players, true) or {}) do
        if cached_alive(slot) then
            local target = cached_entity(slot)
            local p = target and target.origin
            if p then
                local x, y = renderer.world_to_screen(p.X, p.Y + 76, p.Z)
                local fx, fy = renderer.world_to_screen(p.X, p.Y, p.Z)
                if x and fx then
                    drawn = drawn + 1
                    if drawn > 8 then break end
                    local h = math.max(24, fy - y)
                    local w = h * 0.46
                    R.rectangle_outline(x - w/2, y, w, h, r, g, b, a, 1)
                    R.text_ex(x, y - 20, cached_name(slot), {
                        font = "ui_bold", size = 14, align = "center",
                        color = WHITE, outline = true
                    })
                    if safe(espHealth.get, espHealth) ~= false then
                        R.text_ex(x + w/2 + 7, y + 3, tostring(target.health or "?") .. " HP", {
                            font = "code", size = 11, color = MUTED, outline = true
                        })
                    end
                    if safe(espHead.get, espHead) == true then
                        local boxes = safe(entity.get_hitboxes, slot) or {}
                        if boxes[1] and boxes[1].origin then
                            local hp = boxes[1].origin
                            local hx, hy = renderer.world_to_screen(hp.X, hp.Y, hp.Z)
                            if hx then R.circle(hx, hy, 4, 245, 194, 110, 255, false) end
                        end
                    end
                end
            end
        end
    end
end

-- AA profile preview only. Mirrors the profile states and controls in both AA builders.
local function draw_aa_preview(sw, sh)
    local stateNames = {"SHARED", "STANDING", "MOVING", "AIR", "DUCK", "BOMB", "LEGIT"}
    local state = safe(aaState.get, aaState) or 1
    local yaw = safe(aaYaw.get, aaYaw) or 0
    local jitter = safe(aaJitter.get, aaJitter) or 0
    local pitch = safe(aaPitch.get, aaPitch) or 1
    local body = safe(aaBody.get, aaBody) or 0
    local side = safe(aaSide.get, aaSide) or 1
    local x, y = 24, sh - 128
    R.rounded_rectangle(x, y, 300, 98, 17, 23, 28, 220, 9)
    R.text_ex(x + 14, y + 10, "AA LAB / PREVIEW ONLY", {
        font = "ui_bold", size = 15, color = ACCENT
    })
    R.text_ex(x + 14, y + 34, string.format("%s  |  yaw %+d  |  jitter %d",
        stateNames[state] or "SHARED", yaw, jitter), {font = "code", size = 12, color = WHITE})
    R.text_ex(x + 14, y + 56, string.format("pitch %d  |  body %d  |  side %d",
        pitch, body, side), {font = "code", size = 12, color = MUTED})
end

-- Resolver display: per-target history, candidate comparisons and outcome aggregates.
-- Candidate gaps are geometric comparisons to the exposed public foot-yaw, not hit predictions.
local function draw_resolver_panel(sw, sh)
    if safe(resolverEnabled.get, resolverEnabled) == false then return end
    local x, y, width = sw - 382, 74, 358
    local count = math.min(#targetSnapshots, 3)
    local showHist = safe(showHistory.get, showHistory) ~= false and count > 0
    local showCand = safe(showCandidates.get, showCandidates) ~= false and count > 0
    local height = 48 + count * 42 + (showHist and 54 or 0) + (showCand and 124 or 0)
    R.rounded_rectangle(x, y, width, height, 17, 23, 28, 232, 10)
    R.text_ex(x + 14, y + 10, "RESOLVER LAB / ADAPTIVE OBSERVATIONS", {
        font = "ui_bold", size = 13, color = ACCENT
    })
    R.text_ex(x + 14, y + 29, "history • circular mean • jitter • target outcomes", {
        font = "code", size = 9, color = MUTED
    })

    local cursorY = y + 49
    if count == 0 then
        R.text_ex(x + 14, cursorY, "Waiting for public target snapshots...", {
            font = "ui", size = 11, color = MUTED
        })
        return
    end

    for i = 1, count do
        local t = targetSnapshots[i]
        local stats = t.stats or {shots = 0, hits = 0, misses = 0}
        local accuracy = stats.shots > 0 and stats.hits / stats.shots * 100 or 0
        if safe(showAngles.get, showAngles) ~= false then
            R.text_ex(x + 14, cursorY, string.format("#%s %s  HP %s", tostring(t.slot), t.name,
                t.health and tostring(math.floor(t.health)) or "?"), {
                font = "ui_bold", size = 10, color = WHITE
            })
            R.text_ex(x + 14, cursorY + 15, string.format("yaw %s  feet %s  mean %s  range %.0f",
                t.yaw and string.format("%+.0f", t.yaw) or "—",
                t.footYaw and string.format("%+.0f", t.footYaw) or "—",
                t.meanYaw and string.format("%+.0f", t.meanYaw) or "—",
                t.maxDesync or 0), {
                font = "code", size = 9, color = MUTED
            })
            R.text_ex(x + width - 14, cursorY + 15, string.format("H%d/M%d %.0f%%", stats.hits, stats.misses, accuracy), {
                font = "code", size = 9, align = "right", color = stats.misses > stats.hits and {255, 170, 130, 255} or ACCENT
            })
        else
            R.text_ex(x + 14, cursorY, string.format("#%s %s  |  %d samples  |  H%d/M%d",
                tostring(t.slot), t.name, t.samples or 0, stats.hits, stats.misses), {
                font = "code", size = 10, color = WHITE
            })
        end
        local lastText = t.lastOutcome or "—"
        if t.lastOutcome == "MISS" and t.lastReason then lastText = lastText .. "/" .. tostring(t.lastReason) end
        R.text_ex(x + 14, cursorY + 28, string.format("pattern: %s | flips %d | Δ %.1f° | n %d | last %s",
            string.upper(t.jitter or "collecting"), t.flips or 0, t.deltaAverage or 0, t.samples or 0, lastText), {
            font = "code", size = 8, color = MUTED
        })
        cursorY = cursorY + 42
    end

    local selected = targetSnapshots[1]
    if showHist and selected and selected.history and #selected.history >= 2 then
        R.text_ex(x + 14, cursorY, "YAW HISTORY  /  oldest → newest", {
            font = "code", size = 9, color = ACCENT
        })
        local points = {}
        local gx, gy, gw, gh = x + 14, cursorY + 15, width - 28, 25
        for i, sample in ipairs(selected.history) do
            if sample.yaw ~= nil then
                local px = gx + (i - 1) * gw / math.max(#selected.history - 1, 1)
                local py = gy + (180 - sample.yaw) / 360 * gh
                points[#points + 1] = {px, py}
            end
        end
        R.line(gx, gy + gh / 2, gx + gw, gy + gh / 2, 155, 169, 180, 55, 1)
        if #points >= 2 then R.polyline(points, ACCENT[1], ACCENT[2], ACCENT[3], 235, 2, false) end
        cursorY = cursorY + 48
    end

    if showCand and selected and selected.candidates then
        R.text_ex(x + 14, cursorY, string.format("REFERENCE HYPOTHESES  /  target #%s", tostring(selected.slot)), {
            font = "code", size = 9, color = ACCENT
        })
        cursorY = cursorY + 15
        for _, candidate in ipairs(selected.candidates) do
            local gapText = candidate.publicFootGap and string.format("feet gap %.0f°", candidate.publicFootGap) or "feet unavailable"
            R.text_ex(x + 14, cursorY, string.format("%-11s  %+.0f°  →  %+.0f°",
                candidate.name, candidate.offset, candidate.angle), {
                font = "code", size = 9, color = WHITE
            })
            R.text_ex(x + width - 14, cursorY, gapText, {
                font = "code", size = 8, align = "right", color = MUTED
            })
            cursorY = cursorY + 15
        end
        R.text_ex(x + 14, cursorY + 1, "Gap is a public-angle comparison, not resolver accuracy.", {
            font = "ui", size = 8, color = MUTED
        })
    end
end

local function draw_hitlog(sw, sh)
    if safe(hitlogEnabled.get, hitlogEnabled) == false then return end
    local life = 5
    local y = math.floor(sh * 0.70)
    for i = #shotRows, 1, -1 do
        if now() - shotRows[i].at > life then table.remove(shotRows, i) end
    end
    for i, row in ipairs(shotRows) do
        local alpha = math.floor(clamp((life - (now() - row.at)) / 0.4, 0, 1) * 255)
        R.rounded_rectangle(sw/2 - 270, y + (i-1)*34, 540, 30, 17, 23, 28, math.floor(alpha*0.88), 5)
        local c = row.hit and ACCENT or {245, 150, 110, alpha}
        R.text_ex(sw/2 - 258, y + 5 + (i-1)*34, row.text, {
            font = "ui", size = 16, color = {c[1], c[2], c[3], alpha}
        })
    end
end

local function draw_hud(sw, sh)
    if safe(hudEnabled.get, hudEnabled) == false then return end
    local ft = FRAME.ft
    local fps = 1 / math.max(ft, 0.001)
    local x, y = sw - 330, sh - 170
    R.rounded_rectangle(x, y, 306, 132, 17, 23, 28, 230, 10)
    R.text_ex(x + 14, y + 10, "RAGEHUD / LIVE TELEMETRY", {
        font = "ui_bold", size = 15, color = ACCENT
    })
    R.text_ex(x + 14, y + 36, string.format("%.0f", fps), {
        font = "gotham", size = 28, color = WHITE
    })
    R.text_ex(x + 14, y + 68, "FPS", {font = "ui", size = 11, color = MUTED})
    R.text_ex(x + 112, y + 36, string.format("%.1f ms", ft * 1000), {
        font = "gotham", size = 22, color = WHITE
    })
    R.text_ex(x + 112, y + 68, "FRAME TIME", {font = "ui", size = 11, color = MUTED})
    local accuracy = shotStats.shots > 0 and (shotStats.hits / shotStats.shots * 100) or 0
    R.text_ex(x + 14, y + 91, string.format("HIT %d  MISS %d  ACC %.0f%%", shotStats.hits, shotStats.misses, accuracy),
        {font = "code", size = 11, color = MUTED})
    R.text_ex(x + 14, y + 108, string.format("DMG %d  KILLS %d  PING %.0f ms", shotStats.damage, shotStats.kills,
        (tonumber(safe(client.latency)) or 0) * 1000), {font = "code", size = 11, color = MUTED})
    local points = {}
    for i, value in ipairs(frameSamples) do
        points[i] = {x + 14 + (i-1)*278/47, y + 156 - math.min(value, 50)/50*18}
    end
    if #points >= 2 then R.polyline(points, ACCENT[1], ACCENT[2], ACCENT[3], 220, 1, false) end
end

local watermarkCache = {at = 0, text = ""}
local function draw_watermark(sw)
    if now() >= watermarkCache.at then
        watermarkCache.at = now() + 1
        local captionText = safe(caption.get, caption) or "RageHud"
        local fps = 1 / math.max(FRAME.ft, 0.001)
        local ping = (tonumber(safe(client.latency)) or 0) * 1000
        watermarkCache.text = string.format("%s  /  %s  /  %.0f FPS  /  %.0f ms", captionText, VERSION, fps, ping)
    end
    local text = watermarkCache.text
    local width = (safe(renderer.measure_text, text, 13, "ui_bold") or (#text * 7)) + 24
    R.rounded_rectangle(20, 20, width, 34, 18, 22, 27, 210, 8)
    R.rectangle(28, 20, width - 16, 2, ACCENT[1], ACCENT[2], ACCENT[3], 255)
    R.text_ex(31, 29, text, {font = "ui_bold", size = 13, color = WHITE, outline = true})
    if pixelTexture then R.texture(pixelTexture, 0, 0, 1, 1, 255, 255, 255, 255) end
end

-- Optional active-bind panel. ui.get_binds is feature-detected; clients without it simply
-- show a small unavailable message rather than failing the HUD.
local hotkeyPos = safe(storage.get, "ragehud_hotkey_pos")
if type(hotkeyPos) ~= "table" or type(hotkeyPos[1]) ~= "number" or type(hotkeyPos[2]) ~= "number" then
    hotkeyPos = {20, 130}
end
local hotkeyDrag = {active = false, dx = 0, dy = 0}
local lastBindRefresh = 0
local function refresh_active_binds()
    if now() - lastBindRefresh < 0.1 then return end
    lastBindRefresh = now()
    activeBinds = {}
    if type(ui.get_binds) ~= "function" then return end
    local ok, binds = pcall(function() return ui.get_binds() end)
    if not ok or type(binds) ~= "table" then return end
    for _, bind in pairs(binds) do
        if type(bind) == "table" and bind.active == true and bind.enabled ~= false and bind.mode ~= "Always" then
            local name = tostring(bind.name or bind.key or "Active bind")
            table.insert(activeBinds, name)
            if #activeBinds >= 6 then break end
        end
    end
end
local function draw_hotkeys(sw, sh)
    if safe(hotkeysEnabled.get, hotkeysEnabled) == false then return end
    refresh_active_binds()
    local x, y = hotkeyPos[1], hotkeyPos[2]
    local width, header, rowH = 190, 25, 21
    local rows = math.max(1, #activeBinds)
    local height = header + rows * rowH + 8
    local menuOpen = safe(ui.is_menu_open) == true
    if safe(hotkeysDraggable.get, hotkeysDraggable) == true and menuOpen then
        local mx, my = safe(client.mouse_position)
        local down = safe(client.key_state, "Mouse1") == true
        if type(mx) == "number" and type(my) == "number" then
            if down and not hotkeyDrag.active and mx >= x and mx <= x + width and my >= y and my <= y + header then
                hotkeyDrag.active = true
                hotkeyDrag.dx, hotkeyDrag.dy = mx - x, my - y
            end
            if down and hotkeyDrag.active then
                x = clamp(mx - hotkeyDrag.dx, 0, math.max(0, sw - width))
                y = clamp(my - hotkeyDrag.dy, 0, math.max(0, sh - height))
                hotkeyPos = {x, y}
            elseif not down and hotkeyDrag.active then
                hotkeyDrag.active = false
                safe(storage.set, "ragehud_hotkey_pos", hotkeyPos)
            end
        end
    elseif not menuOpen then
        hotkeyDrag.active = false
    end
    R.rounded_rectangle(x, y, width, height, 17, 23, 28, 220, 8)
    R.rectangle(x + 7, y, width - 14, 2, ACCENT[1], ACCENT[2], ACCENT[3], 255)
    R.text_ex(x + 10, y + 6, "ACTIVE BINDS", {font = "ui_bold", size = 12, color = ACCENT})
    if #activeBinds == 0 then
        local msg = type(ui.get_binds) == "function" and "No active binds" or "Bind API unavailable"
        R.text_ex(x + 10, y + 30, msg, {font = "ui", size = 11, color = MUTED})
    else
        for i, name in ipairs(activeBinds) do
            R.text_ex(x + 10, y + 27 + (i - 1) * rowH, name, {font = "ui", size = 11, color = WHITE})
        end
    end
end

local function draw_killfeed(sw)
    if safe(killFeedEnabled.get, killFeedEnabled) == false then return end
    local y = 68
    for i = #killRows, 1, -1 do
        if now() - killRows[i].at > 5 then table.remove(killRows, i) end
    end
    for i, row in ipairs(killRows) do
        local alpha = math.floor(255 * clamp((5 - (now() - row.at)) / 0.5, 0, 1))
        local w = math.min(330, (safe(renderer.measure_text, row.text, 12, "ui") or (#row.text * 6)) + 24)
        local x = sw - w - 20
        R.rounded_rectangle(x, y + (i - 1) * 27, w, 22, 17, 23, 28, math.floor(alpha * 0.8), 5)
        R.text_ex(x + 10, y + 4 + (i - 1) * 27, row.text, {
            font = "ui", size = 12, color = row.mine and {125, 209, 167, alpha} or {235, 242, 247, alpha}
        })
    end
end

local function draw_session_stats(sw, sh)
    if safe(sessionStatsEnabled.get, sessionStatsEnabled) == false then return end
    local x, y = 20, sh - 74
    local accuracy = shotStats.shots > 0 and (shotStats.hits / shotStats.shots * 100) or 0
    local text = string.format("SESSION  |  %d shots  |  %d hits  |  %d misses  |  %.0f%%  |  %d dmg  |  %d kills",
        shotStats.shots, shotStats.hits, shotStats.misses, accuracy, shotStats.damage, shotStats.kills)
    R.rounded_rectangle(x, y, 470, 28, 17, 23, 28, 205, 6)
    R.text_ex(x + 10, y + 7, text, {font = "code", size = 10, color = WHITE})
end

-- Versioned HUD defaults: old exported configs still import unchanged; new toggles keep defaults.
local CONFIG_VERSION = 5
safe(storage.set, "ragehud_runtime_version", CONFIG_VERSION)

-- Camera customization from custom-camera.lua; optional, independent of aiming.
client.set_event_callback("override_view", function(v)
    if safe(cameraEnabled.get, cameraEnabled) == false then return end
    v.thirdperson = safe(cameraThird.get, cameraThird) == true
    v.distance = safe(cameraDistance.get, cameraDistance) or 100
    v.fov = safe(cameraFov.get, cameraFov) or 100
    v.collision = true
end)

-- One paint callback owns the frame snapshot, draw budget, and render order.
client.set_event_callback("paint", function()
    local started = DEBUG.clock()
    begin_frame()
    R.begin(safe(drawBudget.get, drawBudget) or 300)
    -- Frame-time history is sampled once per frame; no separate timer callback is needed.
    table.insert(frameSamples, FRAME.ft * 1000)
    if #frameSamples > 48 then table.remove(frameSamples, 1) end

    draw_watermark(FRAME.sw)
    draw_public_esp()
    draw_grenades()
    draw_resolver_panel(FRAME.sw, FRAME.sh)
    draw_aa_preview(FRAME.sw, FRAME.sh)
    draw_hitlog(FRAME.sw, FRAME.sh)
    draw_hud(FRAME.sw, FRAME.sh)
    draw_hotkeys(FRAME.sw, FRAME.sh)
    draw_killfeed(FRAME.sw)
    draw_session_stats(FRAME.sw, FRAME.sh)

    DEBUG.paintMs = math.max(0, (DEBUG.clock() - started) * 1000)
    DEBUG.maxMs = math.max(DEBUG.maxMs, DEBUG.paintMs)
    DEBUG.paints = DEBUG.paints + 1
    if now() >= DEBUG.at then
        DEBUG.perSecond = DEBUG.paints
        DEBUG.paints = 0
        DEBUG.at = now() + 1
    end
    debug_overlay()
end)

client.set_event_callback("round_start", function()
    shotRows = {}
    killRows = {}
    shotStats = {hits = 0, misses = 0, shots = 0, damage = 0, kills = 0}
    targetSnapshots = {}
    resolverRecords = {}
end)

client.set_event_callback("shutdown", function()
    for id, marker in pairs(grenadeMarkers) do
        if marker and marker.effect then safe(renderer.remove_effect, marker.effect) end
        grenadeMarkers[id] = nil
    end
end)

safe(gui.notify, "RageHud " .. VERSION .. " loaded — adaptive read-only resolver lab", {
    title = "RageHud", duration = 5
})
client.log("RageHud " .. VERSION .. " loaded. Read-only resolver diagnostics; no aim/AA overrides.")
