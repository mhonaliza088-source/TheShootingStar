--[[
	STELLAR REMOTE v3  ·  SS-01 RAILGUN + SS-03 GUNGNIR
	LocalScript for Delta. 100% client-side: only YOU see anything.

	  1. Execute. You get a "Stellar Remote" tool (+ a small "SR" button on screen).
	  2. Tap the tool (equip, then tap again) or the SR button -> menu opens.
	  3. CUTSCENE: ON  = ~10 s cinematic (Earth > Saturn > Solar System > Milky Way > railgun > impact)
	     CUTSCENE: OFF = no camera movement, you watch the red beam charge live (~10 s) and then hit.
	  4. Aim the centre of your screen at the ground and press SS-01 · RAILGUN or SS-03 · GUNGNIR.
]]

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting     = game:GetService("Lighting")
local Debris       = game:GetService("Debris")

local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
if env.__StellarRemoteCleanup then pcall(env.__StellarRemoteCleanup) end
if env.__StellarCutsceneOn == nil then env.__StellarCutsceneOn = true end

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
local CONFIG = {
	QUALITY       = 1,      -- 1 = full | 0.6 = lighter for weak phones | 0.35 = minimum
	TIME_SCALE    = 1,      -- cutscene speed: 1 = ~10 s | 1.4 = slower | 0.8 = faster
	LIVE_CHARGE   = 6.0,    -- seconds the red beam charges when the cutscene is OFF
	CARVE_LAND    = true,   -- beam + blast erase small parts / terrain in its path (YOUR screen only)
	CARVE_RADIUS  = 55,     -- crater radius
	PATH_RADIUS   = 34,     -- how wide the beam's destruction path is
	HEX_RADIUS    = 900,    -- SS-03: how far the orange hexagons spread across the ground
	HEX_CELL      = 26,     -- SS-03: hexagon size (bigger = fewer parts)
	SPEAR_STAYS   = 90,     -- SS-03: seconds the collidable spear stays standing in the ground
	SOUNDS        = true,
	LASER_COLOR   = Color3.fromRGB(255, 25, 25),
	BEAM_CORE     = Color3.fromRGB(255, 255, 255),
	BEAM_MID      = Color3.fromRGB(130, 205, 255),
	BEAM_OUTER    = Color3.fromRGB(70, 140, 255),
	BLACK_TEXTURE = "rbxasset://textures/blackBkg_square.png", -- turns the sky black in space
}

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
local conns, objs = {}, {}
local function track(i) objs[#objs + 1] = i return i end
local function getCam() return workspace.CurrentCamera end
local function rnd() return math.random() * 2 - 1 end
local function smooth(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end
local function V(s) return Vector3.new(s, s, s) end
local function shakeRot(a) return CFrame.Angles(rnd() * a, rnd() * a, rnd() * a * 0.6) end
local function TS(x) return x * CONFIG.TIME_SCALE end

local function fmt(n)
	local s = tostring(math.floor(n))
	local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (r:gsub("^,", ""))
end

local function protect(g)
	local ok, hui = pcall(function() return gethui and gethui() end)
	g.Parent = (ok and hui) or player:WaitForChild("PlayerGui")
	return g
end

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then p.Shape = props.Shape end
	for k, v in pairs(props) do
		if k ~= "Shape" then p[k] = v end
	end
	p.Parent = parent
	return p
end

local function runFor(duration, fn)
	local t0 = os.clock()
	while true do
		local dt = RunService.RenderStepped:Wait()
		local e = os.clock() - t0
		local a = math.min(e / duration, 1)
		fn(a, dt, e)
		if a >= 1 then break end
	end
end

local function flatCF(pos, n)
	n = n.Unit
	local ref = math.abs(n.Y) > 0.99 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	local y = (ref - n * ref:Dot(n)).Unit
	return CFrame.fromMatrix(pos, n, y) -- local X axis = normal (cylinders lie flat)
end

local function randUnit(rng)
	local v
	repeat
		v = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
	until v.Magnitude > 0.1 and v.Magnitude <= 1
	return v.Unit
end

local SND = {
	click  = "rbxasset://sounds/switch.mp3",
	launch = "rbxasset://sounds/Launching rocket.wav",
	whoosh = "rbxasset://sounds/Rocket whoosh 01.wav",
	shot   = "rbxasset://sounds/Rocket shot.wav",
	boom   = "rbxasset://sounds/impact_explosion_03.mp3",
}
local function sfx(id, vol, speed, life)
	if not CONFIG.SOUNDS then return end
	pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = vol or 1
		s.PlaybackSpeed = speed or 1
		s.Parent = workspace
		s:Play()
		Debris:AddItem(s, life or 8)
	end)
end

local function setControls(on)
	pcall(function()
		local pm = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		local c = pm:GetControls()
		if on then c:Enable() else c:Disable() end
	end)
end

------------------------------------------------------------------------
-- LIGHTING (space look + restore)
------------------------------------------------------------------------
local LIGHT_PROPS = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "FogEnd", "FogStart", "FogColor", "ExposureCompensation", "GlobalShadows" }
local SKY_FACES = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" }
local L0 = {}

local function saveLighting()
	L0 = { props = {} }
	for _, k in ipairs(LIGHT_PROPS) do L0.props[k] = Lighting[k] end
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then L0.atmo = { inst = atmo, Density = atmo.Density, Offset = atmo.Offset, Glare = atmo.Glare, Haze = atmo.Haze } end
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		L0.sky = { inst = sky, StarCount = sky.StarCount, Bodies = sky.CelestialBodiesShown, faces = {} }
		for _, f in ipairs(SKY_FACES) do L0.sky.faces[f] = sky[f] end
	end
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then L0.clouds = { inst = clouds, Enabled = clouds.Enabled } end
end

local function spaceLighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(100, 105, 135)
	Lighting.OutdoorAmbient = Color3.fromRGB(125, 130, 165)
	Lighting.FogEnd = 1e9
	Lighting.FogStart = 1e8
	Lighting.GlobalShadows = false
	Lighting.ExposureCompensation = 0
	if L0.atmo then
		local a = L0.atmo.inst
		a.Density = 0; a.Haze = 0; a.Glare = 0; a.Offset = 0
	end
	local sky = L0.sky and L0.sky.inst
	if not sky then
		sky = Instance.new("Sky")
		sky.Parent = Lighting
		L0.createdSky = sky
	end
	for _, f in ipairs(SKY_FACES) do sky[f] = CONFIG.BLACK_TEXTURE end
	sky.StarCount = 6000
	sky.CelestialBodiesShown = false
	if L0.clouds then L0.clouds.inst.Enabled = false end
end

local function restoreLighting()
	for k, v in pairs(L0.props or {}) do pcall(function() Lighting[k] = v end) end
	if L0.atmo and L0.atmo.inst.Parent then
		local a = L0.atmo
		a.inst.Density = a.Density; a.inst.Offset = a.Offset; a.inst.Glare = a.Glare; a.inst.Haze = a.Haze
	end
	if L0.sky and L0.sky.inst.Parent then
		local s = L0.sky
		for f, v in pairs(s.faces) do s.inst[f] = v end
		s.inst.StarCount = s.StarCount
		s.inst.CelestialBodiesShown = s.Bodies
	end
	if L0.createdSky then L0.createdSky:Destroy(); L0.createdSky = nil end
	if L0.clouds and L0.clouds.inst.Parent then L0.clouds.inst.Enabled = L0.clouds.Enabled end
end

------------------------------------------------------------------------
-- BEAM / LASER RIGS  (chains of <=2048-stud cylinders)
------------------------------------------------------------------------
local SEG = 2000

local function makeRig(parent, n, layers)
	local rig = {}
	for i = 1, n do
		local group = {}
		for li, spec in ipairs(layers) do
			local p = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 1, 1), Color = spec.color, Material = Enum.Material.Neon, Transparency = 1 }, parent)
			p:SetAttribute("a", spec.alpha)
			group[li] = p
		end
		rig[i] = group
	end
	return rig
end

local function updateRig(rig, a, b, thFn)
	local vec = b - a
	local len = vec.Magnitude
	if len < 1 then
		for _, group in ipairs(rig) do for _, p in ipairs(group) do p.Transparency = 1 end end
		return
	end
	local dir = vec.Unit
	local n = math.min(#rig, math.ceil(len / SEG))
	local segLen = len / n
	for i, group in ipairs(rig) do
		if i <= n then
			local mid = a + dir * (segLen * (i - 0.5))
			local th = thFn(i, mid)
			local up = (math.abs(dir.Y) > 0.98) and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
			local base = CFrame.lookAt(mid, mid + dir, up) * CFrame.Angles(0, math.rad(90), 0) -- cylinder axis -> dir
			for li, p in ipairs(group) do
				local t = math.max(th[li], 0.05)
				p.Size = Vector3.new(math.min(segLen + 2, 2040), t, t)
				p.CFrame = base
				p.Transparency = p:GetAttribute("a")
			end
		else
			for _, p in ipairs(group) do p.Transparency = 1 end
		end
	end
end

local function beamLayers()
	return {
		{ color = CONFIG.BEAM_CORE,  alpha = 0 },
		{ color = CONFIG.BEAM_MID,   alpha = 0.35 },
		{ color = CONFIG.BEAM_OUTER, alpha = 0.82 },
	}
end
local function laserLayers()
	return { { color = CONFIG.LASER_COLOR, alpha = 0 }, { color = CONFIG.LASER_COLOR, alpha = 0.6 } }
end

------------------------------------------------------------------------
-- COSMIC LAYOUT + CAMERA SHOTS
-- Every shot LOCKS onto an object and pulls straight back from it.
------------------------------------------------------------------------
local STAGE    = Vector3.new(0, 30000, 0)      -- the space scene lives high above the map
local E0       = STAGE                         -- top of the Earth model (beam target)
local SATURN_C = Vector3.new(2400, 3500, 900)
local SUN_C    = Vector3.new(-4200, 7500, 2400)
local GAL_C    = Vector3.new(0, 18000, 1282)

local SHOTS = {
	{ name = "EARTH",            c = STAGE + Vector3.new(0, -250, 0), dir = Vector3.new(-0.8, 0.45, -0.4).Unit,  d0 = 1500,  d1 = 9500,  t = 1.10 },
	{ name = "SATURN",           c = STAGE + SATURN_C,                dir = Vector3.new(-0.5, 0.35, -0.8).Unit,  d0 = 3600,  d1 = 18000, t = 0.85 },
	{ name = "THE SOLAR SYSTEM", c = STAGE + SUN_C,                   dir = Vector3.new(0.2, 0.75, -0.62).Unit,  d0 = 8000,  d1 = 24000, t = 0.90 },
	{ name = "THE MILKY WAY",    c = STAGE + GAL_C,                   dir = Vector3.new(0.15, 0.6, -0.78).Unit,  d0 = 16000, d1 = 30000, t = 1.00 },
}
local function shotPos(sh, a)
	local d = sh.d0 * (sh.d1 / sh.d0) ^ (a ^ 1.35) -- constant-rate zoom-out
	return sh.c + sh.dir * d
end

-- the railgun ends up beside the camera at the end of the galaxy shot
local P_END    = shotPos(SHOTS[4], 1)
local CAM_END  = CFrame.lookAt(P_END, SHOTS[4].c)
local GFIN     = (CAM_END * CFrame.new(700, -120, -1100)).Position
local GSTART   = GFIN + CAM_END.LookVector * 7000 - CAM_END.RightVector * 2500 -- "it's there", far near the galaxy
local DIR_RAW  = GFIN - E0
local DIR      = DIR_RAW.Unit                  -- beam direction (Earth top -> railgun), also used in the real world
local PERP     = DIR:Cross(Vector3.new(1, 0, 0)).Unit
local PERP2    = DIR:Cross(PERP)
local GUNCF    = CFrame.lookAt(GFIN, E0) * CFrame.new(0, 0, 440)
local function L(u) return E0 + DIR_RAW * u end
local function GL(x, y, z) return (GUNCF * CFrame.new(x, y, z)).Position end

------------------------------------------------------------------------
-- STAGE BUILDER (deleted after the cutscene)
------------------------------------------------------------------------
local function buildStage()
	local Q = CONFIG.QUALITY
	local folder = Instance.new("Folder")
	folder.Name = "StellarStage"
	folder.Parent = workspace

	local made = 0
	local function P(props, parent)
		made += 1
		if made % 140 == 0 then task.wait() end
		return part(props, parent or folder)
	end
	local NEON, METALM = Enum.Material.Neon, Enum.Material.Metal
	local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder
	local rng = Random.new(1337)

	local function ringBand(cf, rIn, rOut, segs, thick, color, transp, mat)
		segs = math.max(24, math.floor(segs * Q))
		local mid, width = (rIn + rOut) / 2, rOut - rIn
		local arc = (2 * math.pi * mid / segs) * 1.06
		for i = 1, segs do
			local a = (i / segs) * math.pi * 2
			P({
				Size = Vector3.new(width, thick, arc),
				CFrame = cf * CFrame.new(math.cos(a) * mid, 0, math.sin(a) * mid) * CFrame.Angles(0, -a, 0),
				Color = color, Transparency = transp, Material = mat or Enum.Material.SmoothPlastic,
			})
		end
	end

	-- ============ EARTH ============
	do
		local c = STAGE + Vector3.new(0, -1000, 0)
		P({ Shape = BALL, Size = V(2000), Position = c, Color = Color3.fromRGB(10, 45, 115), Reflectance = 0.08 })
		local function disc(dir, radius, d, thick, props)
			props.Shape = CYL
			props.Size = Vector3.new(thick, d, d)
			props.CFrame = flatCF(c + dir * radius, dir)
			return P(props)
		end
		local lands = { Color3.fromRGB(46, 110, 52), Color3.fromRGB(70, 128, 58), Color3.fromRGB(104, 134, 70), Color3.fromRGB(160, 138, 84), Color3.fromRGB(190, 165, 100) }
		for _ = 1, 8 do
			local cen = randUnit(rng)
			local spread = rng:NextNumber(0.12, 0.26)
			for _ = 1, math.max(6, math.floor(16 * Q)) do
				local d = (cen + randUnit(rng) * spread).Unit
				disc(d, 999.2, rng:NextNumber(70, 190), 7, { Color = lands[rng:NextInteger(1, #lands)] })
			end
		end
		disc(Vector3.new(0, 1, 0), 999.2, 340, 7, { Color = Color3.fromRGB(240, 245, 250) })
		disc(Vector3.new(0, -1, 0), 999.2, 300, 7, { Color = Color3.fromRGB(240, 245, 250) })
		for _ = 1, math.floor(70 * Q) do -- clouds
			disc(randUnit(rng), 1008, rng:NextNumber(60, 200), 3, { Color = Color3.new(1, 1, 1), Transparency = 0.3 })
		end
		P({ Shape = BALL, Size = V(2044), Position = c, Color = Color3.fromRGB(90, 160, 255), Material = NEON, Transparency = 0.9 })
	end

	-- ============ SATURN ============
	do
		local r = 700
		local tilt = CFrame.new(STAGE + SATURN_C) * CFrame.Angles(math.rad(12), 0, math.rad(22))
		P({ Shape = BALL, Size = V(r * 2), Position = STAGE + SATURN_C, Color = Color3.fromRGB(214, 190, 140) })
		local bands = {
			{ -330, 70, Color3.fromRGB(176, 150, 106) }, { -230, 70, Color3.fromRGB(228, 207, 162) },
			{ -120, 70, Color3.fromRGB(190, 160, 112) }, { -10, 80, Color3.fromRGB(238, 218, 172) },
			{ 105, 70, Color3.fromRGB(184, 154, 108) }, { 205, 70, Color3.fromRGB(230, 210, 166) },
			{ 305, 60, Color3.fromRGB(172, 146, 102) },
		}
		for _, b in ipairs(bands) do
			local h, th, col = b[1], b[2], b[3]
			local dia = 2 * math.sqrt((r + 0.6) ^ 2 - (math.abs(h) + th / 2) ^ 2)
			P({ Shape = CYL, Size = Vector3.new(th, dia, dia), CFrame = tilt * CFrame.new(0, h, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = col })
		end
		ringBand(tilt, r * 1.28, r * 1.46, 70, 3, Color3.fromRGB(150, 128, 92), 0.25)
		ringBand(tilt, r * 1.50, r * 1.78, 86, 3, Color3.fromRGB(226, 208, 166), 0.18)
		ringBand(tilt, r * 1.82, r * 2.02, 100, 3, Color3.fromRGB(190, 170, 130), 0.3)
		ringBand(tilt, r * 2.05, r * 2.12, 110, 3, Color3.fromRGB(170, 150, 115), 0.5)
	end

	-- ============ SOLAR SYSTEM ============
	do
		local c = STAGE + SUN_C
		P({ Shape = BALL, Size = V(520), Position = c, Color = Color3.fromRGB(255, 205, 90), Material = NEON })
		P({ Shape = BALL, Size = V(900), Position = c, Color = Color3.fromRGB(255, 150, 40), Material = NEON, Transparency = 0.85 })
		local planets = {
			{ 450, 38, Color3.fromRGB(150, 150, 150) }, { 780, 58, Color3.fromRGB(230, 200, 140) },
			{ 1100, 62, Color3.fromRGB(60, 120, 220) }, { 1450, 48, Color3.fromRGB(200, 90, 60) },
			{ 1950, 150, Color3.fromRGB(210, 170, 130) }, { 2350, 130, Color3.fromRGB(232, 212, 162) },
			{ 2700, 90, Color3.fromRGB(150, 220, 230) }, { 3050, 88, Color3.fromRGB(70, 100, 230) },
		}
		local pr = Random.new(5)
		for _, pl in ipairs(planets) do
			ringBand(CFrame.new(c), pl[1] - 10, pl[1] + 10, math.floor(pl[1] / 20), 4, Color3.fromRGB(110, 150, 210), 0.3, NEON)
			local a = pr:NextNumber(0, math.pi * 2)
			P({ Shape = BALL, Size = V(pl[2] * 2), Position = c + Vector3.new(math.cos(a) * pl[1], 0, math.sin(a) * pl[1]), Color = pl[3] })
		end
	end

	-- ============ MILKY WAY ============
	do
		local c = STAGE + GAL_C
		local R = 9000
		for _ = 1, math.floor(1500 * Q) do
			local t = rng:NextNumber() ^ 0.65
			local rr = t * R
			local arm = rng:NextInteger(0, 3)
			local ang = arm * (math.pi / 2) + t * math.pi * 3.4 + rng:NextNumber(-1, 1) * (0.16 + 0.32 * (1 - t))
			local y = rng:NextNumber(-1, 1) * (30 + 360 * (1 - t) ^ 2)
			local col = Color3.fromRGB(255, 225, 170):Lerp(Color3.fromRGB(150, 185, 255), math.clamp(t * 1.2, 0, 1))
			if rng:NextNumber() < 0.06 then col = Color3.fromRGB(255, 140, 200) end
			local s = rng:NextNumber(70, 230) * (1 - 0.4 * t)
			P({ Shape = BALL, Size = V(s), Position = c + Vector3.new(math.cos(ang) * rr, y, math.sin(ang) * rr), Color = col, Material = NEON, Transparency = rng:NextNumber(0, 0.3) })
		end
		for _ = 1, math.floor(220 * Q) do
			local v = randUnit(rng) * (rng:NextNumber() ^ 1.6) * 1500
			P({ Shape = BALL, Size = V(rng:NextNumber(120, 320)), Position = c + Vector3.new(v.X, v.Y * 0.35, v.Z), Color = Color3.fromRGB(255, 215, 150), Material = NEON, Transparency = rng:NextNumber(0.1, 0.4) })
		end
		P({ Shape = BALL, Size = V(1800), Position = c, Color = Color3.fromRGB(255, 230, 170), Material = NEON, Transparency = 0.55 })
		P({ Shape = BALL, Size = V(3600), Position = c, Color = Color3.fromRGB(255, 220, 160), Material = NEON, Transparency = 0.86 })
	end

	-- ============ SPACE DUST along the beam line (speed during the ride) ============
	for _ = 1, math.floor(240 * Q) do
		local u = rng:NextNumber(0.02, 0.92)
		local ang = rng:NextNumber(0, math.pi * 2)
		local rad = rng:NextNumber(80, 800)
		local pos = L(u) + (PERP * math.cos(ang) + PERP2 * math.sin(ang)) * rad
		P({ Size = Vector3.new(2.5, 2.5, 36), CFrame = CFrame.lookAt(pos, pos + DIR), Color = Color3.fromRGB(200, 225, 255), Material = NEON, Transparency = rng:NextNumber(0, 0.4) })
	end

	-- ============ THE RAILGUN (a Model so it can glide in with PivotTo) ============
	local gunModel = Instance.new("Model")
	gunModel.Name = "Railgun"
	gunModel.Parent = folder
	local gun = { coils = {}, strips = {}, blink = {} }
	do
		local METAL = Color3.fromRGB(46, 50, 62)
		local DARK = Color3.fromRGB(26, 28, 36)
		local CDIM = Color3.fromRGB(20, 85, 125)
		local function GP(cf, props)
			props.CFrame = GUNCF * cf
			return P(props, gunModel)
		end
		for _, sx in ipairs({ -46, 46 }) do -- twin rails + glowing inner strips
			GP(CFrame.new(sx, 0, -450), { Size = Vector3.new(30, 30, 900), Color = METAL, Material = METALM })
			gun.strips[#gun.strips + 1] = GP(CFrame.new(sx * 0.65, 0, -450), { Size = Vector3.new(4, 20, 880), Color = CDIM, Material = NEON })
		end
		for i = 0, 15 do -- accelerator coils
			local z = -140 - i * 52
			local frame = {}
			local function bar(x, y, w, h)
				GP(CFrame.new(x, y, z), { Size = Vector3.new(w, h, 22), Color = DARK, Material = METALM })
			end
			bar(0, 84, 204, 16); bar(0, -84, 204, 16); bar(-94, 0, 16, 172); bar(94, 0, 16, 172)
			local function glow(x, y, w, h)
				frame[#frame + 1] = GP(CFrame.new(x, y, z), { Size = Vector3.new(w, h, 27), Color = CDIM, Material = NEON })
			end
			glow(0, 84, 180, 6); glow(0, -84, 180, 6); glow(-94, 0, 6, 150); glow(94, 0, 6, 150)
			gun.coils[i + 1] = frame
		end
		GP(CFrame.new(0, 0, 40), { Size = Vector3.new(210, 210, 170), Color = DARK, Material = METALM }) -- breech
		GP(CFrame.new(0, 0, -62), { Size = Vector3.new(150, 150, 40), Color = METAL, Material = METALM })
		for _, o in ipairs({ { -135, 70 }, { 135, 70 }, { -135, -70 }, { 135, -70 } }) do -- capacitors
			GP(CFrame.new(o[1], o[2], 70) * CFrame.Angles(0, math.rad(90), 0), { Shape = CYL, Size = Vector3.new(190, 60, 60), Color = METAL, Material = METALM })
			for k = 0, 2 do
				gun.strips[#gun.strips + 1] = GP(CFrame.new(o[1], o[2], 20 + k * 50) * CFrame.Angles(0, math.rad(90), 0), { Shape = CYL, Size = Vector3.new(8, 64, 64), Color = CDIM, Material = NEON })
			end
		end
		gun.core = GP(CFrame.new(0, 0, -98), { Shape = BALL, Size = V(46), Color = Color3.fromRGB(40, 180, 255), Material = NEON, Transparency = 0.15 })
		local sparks = Instance.new("ParticleEmitter")
		sparks.Rate = 0
		sparks.Color = ColorSequence.new(Color3.fromRGB(200, 240, 255), Color3.fromRGB(60, 160, 255))
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 18), NumberSequenceKeypoint.new(1, 0) })
		sparks.Lifetime = NumberRange.new(0.5, 1.1)
		sparks.Speed = NumberRange.new(120, 320)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Parent = gun.core
		gun.sparks = sparks
		for _, o in ipairs({ { 0, 96, 220, 24 }, { 0, -96, 220, 24 }, { -98, 0, 24, 170 }, { 98, 0, 24, 170 } }) do -- muzzle brake
			GP(CFrame.new(o[1], o[2], -905), { Size = Vector3.new(o[3], o[4], 36), Color = METAL, Material = METALM })
		end
		gun.flash = GP(CFrame.new(0, 0, -905), { Shape = BALL, Size = V(10), Color = Color3.new(1, 1, 1), Material = NEON, Transparency = 1 })
		for _, sx in ipairs({ -1, 1 }) do -- solar wings + arms
			GP(CFrame.new(sx * 330, 0, 60), { Size = Vector3.new(380, 3, 210), Color = Color3.fromRGB(25, 45, 95), Material = METALM, Reflectance = 0.2 })
			GP(CFrame.new(sx * 330, 2, 60), { Size = Vector3.new(384, 1, 6), Color = CDIM, Material = NEON })
			GP(CFrame.new(sx * 140, 0, 60), { Size = Vector3.new(120, 10, 10), Color = METAL, Material = METALM })
		end
		GP(CFrame.new(0, -190, -300), { Size = Vector3.new(24, 260, 24), Color = METAL, Material = METALM }) -- pylon + antenna
		GP(CFrame.new(0, -330, -300), { Size = Vector3.new(220, 16, 16), Color = DARK, Material = METALM })
		GP(CFrame.new(0, 150, 60), { Size = Vector3.new(10, 190, 10), Color = METAL, Material = METALM })
		for _, o in ipairs({ { 98, 96, -905 }, { -98, -96, -905 }, { 105, 105, 120 }, { -105, -105, 120 }, { 0, 190, 60 } }) do
			gun.blink[#gun.blink + 1] = GP(CFrame.new(o[1], o[2], o[3]), { Shape = BALL, Size = V(16), Color = Color3.fromRGB(255, 40, 40), Material = NEON })
		end
	end
	gunModel.WorldPivot = GUNCF
	gunModel:PivotTo(CFrame.new(GSTART - GFIN) * GUNCF) -- starts far away, near the galaxy

	return {
		folder = folder,
		gun = gun,
		gunModel = gunModel,
		laser = makeRig(folder, 24, laserLayers()),
		beam = makeRig(folder, 24, beamLayers()),
	}
end

------------------------------------------------------------------------
-- DESTRUCTION: erase small parts / terrain in the beam's path (client-side)
------------------------------------------------------------------------
local function makeEraser(T, pathR, craterR, udir)
	local list = {}
	local pr, cr, dv = pathR or CONFIG.PATH_RADIUS, craterR or CONFIG.CARVE_RADIUS, udir or DIR
	if CONFIG.CARVE_LAND then
		pcall(function()
			local char = player.Character
			local rp = char and char:FindFirstChild("HumanoidRootPart")
			local ex = {}
			for _, pl in ipairs(Players:GetPlayers()) do
				if pl.Character then ex[#ex + 1] = pl.Character end
			end
			local op = OverlapParams.new()
			op.FilterType = Enum.RaycastFilterType.Exclude
			op.FilterDescendantsInstances = ex
			local seen = {}
			local function consider(p, s)
				if seen[p] or p == workspace.Terrain or #list >= 1500 then return end
				seen[p] = true
				if p.Size.Magnitude > 420 then return end                                     -- keep huge floors/baseplates
				if rp and (p.Position - rp.Position).Magnitude < 32 then return end            -- never remove what's under you
				local m = p:FindFirstAncestorWhichIsA("Model")
				if m and m:FindFirstChildOfClass("Humanoid") then return end                   -- never remove characters
				list[#list + 1] = { p, s }
			end
			for s = 0, 700, 26 do
				for _, p in ipairs(workspace:GetPartBoundsInRadius(T + dv * s, pr, op)) do consider(p, s) end
			end
			for _, p in ipairs(workspace:GetPartBoundsInRadius(T, cr, op)) do consider(p, 0) end
			table.sort(list, function(a, b) return a[2] > b[2] end)
		end)
	end
	local idx = 1
	-- call with the beam head's height along the path; erases everything the head has passed
	return function(headS)
		while list[idx] and list[idx][2] >= headS do
			local p = list[idx][1]
			idx += 1
			if p.Parent then p.Parent = nil end
		end
	end
end

------------------------------------------------------------------------
-- IMPACT (the boom, in the real world)
------------------------------------------------------------------------
local function impact(hud, T, N, beamRig, eraser, doShake)
	local R = CONFIG.CARVE_RADIUS
	local fold = Instance.new("Folder")
	fold.Name = "StellarImpact"
	fold.Parent = workspace
	task.delay(50, function() fold:Destroy() end)

	sfx(SND.boom, 2.5, 0.7, 10)
	sfx(SND.shot, 2, 0.35, 10)
	sfx(SND.whoosh, 1.5, 0.5, 8)
	TweenService:Create(hud.flash, TweenInfo.new(1.3), { BackgroundTransparency = 1 }):Play()

	eraser(-1) -- anything left in the path goes now
	if CONFIG.CARVE_LAND then
		pcall(function() workspace.Terrain:FillBall(T, R, Enum.Material.Air) end)
		pcall(function()
			local mid = T + DIR * 350
			workspace.Terrain:FillCylinder(CFrame.lookAt(mid, mid + DIR) * CFrame.Angles(math.rad(-90), 0, 0), 700, CONFIG.PATH_RADIUS * 0.8, Enum.Material.Air)
		end)
	end

	-- scorched crater
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, R * 2.15, R * 2.15), CFrame = flatCF(T + N * 0.15, N), Color = Color3.fromRGB(255, 110, 20), Material = Enum.Material.Neon, Transparency = 0.35 }, fold)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, R * 2.0, R * 2.0), CFrame = flatCF(T + N * 0.3, N), Color = Color3.fromRGB(14, 12, 12) }, fold)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, R * 0.9, R * 0.9), CFrame = flatCF(T + N * 0.45, N), Color = Color3.fromRGB(255, 80, 10), Material = Enum.Material.Neon, Transparency = 0.15 }, fold)

	-- fireball
	local fb = part({ Shape = Enum.PartType.Ball, Size = V(4), Position = T + Vector3.new(0, 4, 0), Color = Color3.fromRGB(255, 190, 90), Material = Enum.Material.Neon }, fold)
	local fb2 = part({ Shape = Enum.PartType.Ball, Size = V(3), Position = T + Vector3.new(0, 4, 0), Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon }, fold)
	TweenService:Create(fb, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V(R * 2.6), Position = T + Vector3.new(0, R * 0.7, 0), Transparency = 1 }):Play()
	TweenService:Create(fb2, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V(R * 1.6), Position = T + Vector3.new(0, R * 0.5, 0), Transparency = 1 }):Play()

	-- embers + smoke
	local emP = part({ Size = Vector3.new(R, 1, R), Position = T + Vector3.new(0, 1, 0), Transparency = 1 }, fold)
	local em = Instance.new("ParticleEmitter")
	em.Rate = 0
	em.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 80, 20))
	em.LightEmission = 1
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 0) })
	em.Lifetime = NumberRange.new(1.2, 2.8)
	em.Speed = NumberRange.new(60, 200)
	em.SpreadAngle = Vector2.new(65, 65)
	em.Acceleration = Vector3.new(0, -75, 0)
	em.EmissionDirection = Enum.NormalId.Top
	em.Parent = emP
	em:Emit(280)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Rate = 0
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(60, 55, 52))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 20), NumberSequenceKeypoint.new(1, 75) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(3, 5.5)
	smoke.Speed = NumberRange.new(12, 45)
	smoke.SpreadAngle = Vector2.new(50, 50)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = emP
	smoke:Emit(70)
	em.Rate = 18
	task.delay(6, function() em.Rate = 0 end)

	-- shockwave ring
	task.spawn(function()
		local SEGS = 56
		local ring = {}
		for i = 1, SEGS do
			ring[i] = part({ Size = Vector3.new(6, 3, 6), Color = Color3.fromRGB(255, 235, 200), Material = Enum.Material.Neon }, fold)
		end
		runFor(1.8, function(a)
			local rad = 6 + (a ^ 0.6) * R * 5
			local width = 10 * (1 - a) + 2
			local arc = 2 * math.pi * rad / SEGS * 1.1
			for i, p in ipairs(ring) do
				local ang = (i / SEGS) * math.pi * 2
				p.Size = Vector3.new(width, 3 * (1 - a) + 0.5, arc)
				p.CFrame = CFrame.new(T + Vector3.new(0, 1.5, 0)) * CFrame.new(math.cos(ang) * rad, 0, math.sin(ang) * rad) * CFrame.Angles(0, -ang, 0)
				p.Transparency = 0.15 + 0.85 * a
			end
		end)
		for _, p in ipairs(ring) do p:Destroy() end
	end)

	if doShake then
		local t0 = os.clock()
		local dist = (getCam().CFrame.Position - T).Magnitude
		local intensity = math.clamp(1 - dist / 600, 0.2, 1)
		RunService:BindToRenderStep("StellarShake", Enum.RenderPriority.Camera.Value + 1, function()
			local e = os.clock() - t0
			local k = (math.max(0, 1 - e / 3.2) ^ 2) * intensity
			local c = getCam()
			c.CFrame = c.CFrame * CFrame.Angles(rnd() * 0.02 * k, rnd() * 0.02 * k, rnd() * 0.01 * k)
			if e > 3.3 then RunService:UnbindFromRenderStep("StellarShake") end
		end)
	end

	-- the beam fades out
	runFor(2.6, function(a)
		local k = (1 - a) ^ 0.6
		updateRig(beamRig, T + DIR * 2700, T, function() return { 30 * k, 70 * k, 130 * k } end)
	end)
	updateRig(beamRig, T, T, function() return { 1, 1, 1 } end)
end

------------------------------------------------------------------------
-- CUTSCENE HUD
------------------------------------------------------------------------
local function newHUD()
	local g = Instance.new("ScreenGui")
	g.Name = "StellarCutscene"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 1000
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local function fr(props)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		for k, v in pairs(props) do f[k] = v end
		f.Parent = g
		return f
	end
	local function tx(props)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.Code
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextStrokeTransparency = 0.6
		t.TextTransparency = 1
		for k, v in pairs(props) do t[k] = v end
		t.Parent = g
		return t
	end
	local hud = { gui = g }
	hud.top = fr({ BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.new(1, 0, 0, 0), ZIndex = 5 })
	hud.bot = fr({ BackgroundColor3 = Color3.new(0, 0, 0), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 0), ZIndex = 5 })
	hud.title = tx({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.80, 0), Size = UDim2.new(0.9, 0, 0, 34), TextSize = 26, ZIndex = 8 })
	hud.sub = tx({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.855, 0), Size = UDim2.new(0.9, 0, 0, 22), TextSize = 15, TextColor3 = Color3.fromRGB(255, 120, 120), ZIndex = 8 })
	hud.flash = fr({ BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), ZIndex = 20 })
	protect(g)
	function hud.bars(open)
		local s = open and UDim2.new(1, 0, 0.11, 0) or UDim2.new(1, 0, 0, 0)
		TweenService:Create(hud.top, TweenInfo.new(0.5), { Size = s }):Play()
		TweenService:Create(hud.bot, TweenInfo.new(0.5), { Size = s }):Play()
	end
	function hud.setLabel(text)
		hud.title.Text = text
		hud.title.TextTransparency = 1
		TweenService:Create(hud.title, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
	end
	function hud.setSub(text)
		hud.sub.Text = text
		hud.sub.TextTransparency = 0
	end
	return hud
end

------------------------------------------------------------------------
-- THE SS-01 SEQUENCE
------------------------------------------------------------------------
local busy = false
local menu

local function runSS01()
	if busy then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then return end
	busy = true
	if menu then menu.close() end
	local useCut = env.__StellarCutsceneOn ~= false

	local cam = getCam()
	local saved = {
		type = cam.CameraType, subject = cam.CameraSubject, fov = cam.FieldOfView,
		ws = hum.WalkSpeed, jp = hum.JumpPower, jh = hum.JumpHeight,
	}
	local hud = newHUD()
	local stage, stageReady = nil, false
	local hidden, live = {}, {}
	local lightingActive = false
	local playerRestored = not useCut -- live mode never touches the player or camera
	local realFolder = Instance.new("Folder")
	realFolder.Name = "StellarReal"
	realFolder.Parent = workspace

	local fx
	if useCut then
		fx = { blur = Instance.new("BlurEffect"), cc = Instance.new("ColorCorrectionEffect"), bloom = Instance.new("BloomEffect") }
		fx.blur.Size = 0
		fx.bloom.Intensity = 0.8; fx.bloom.Size = 36; fx.bloom.Threshold = 0.9
		for _, e in pairs(fx) do e.Parent = Lighting end
	end
	local function resetFx()
		if not fx then return end
		fx.blur.Size = 0
		fx.cc.Brightness = 0; fx.cc.Contrast = 0; fx.cc.Saturation = 0
		fx.cc.TintColor = Color3.new(1, 1, 1)
	end

	local function hideWorld()
		local n = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") and d ~= workspace.Terrain then
				if not (stage and d:IsDescendantOf(stage.folder)) then
					local v = d.LocalTransparencyModifier
					if v < 1 then
						hidden[#hidden + 1] = { d, v }
						d.LocalTransparencyModifier = 1
					end
				end
			end
			n += 1
			if n % 3000 == 0 then task.wait() end
		end
	end

	local function leaveSpace()
		if not lightingActive then return end
		lightingActive = false
		restoreLighting()
		for _, rec in ipairs(hidden) do
			if rec[1].Parent then rec[1].LocalTransparencyModifier = rec[2] end
		end
		hidden = {}
	end

	local function restorePlayer()
		if playerRestored then return end
		playerRestored = true
		local c = getCam()
		c.CameraType = (saved.type ~= Enum.CameraType.Scriptable) and saved.type or Enum.CameraType.Custom
		if saved.subject then c.CameraSubject = saved.subject end
		c.FieldOfView = saved.fov
		if hum and hum.Parent then
			hum.WalkSpeed = saved.ws; hum.JumpPower = saved.jp; hum.JumpHeight = saved.jh
		end
		setControls(true)
	end

	local function restoreAll()
		for _, cn in ipairs(live) do pcall(function() cn:Disconnect() end) end
		leaveSpace()
		restorePlayer()
		pcall(function() RunService:UnbindFromRenderStep("StellarShake") end)
		if fx then for _, e in pairs(fx) do pcall(function() e:Destroy() end) end end
		if stage and stage.folder then pcall(function() stage.folder:Destroy() end) end
		pcall(function() realFolder:Destroy() end)
		pcall(function() hud.gui:Destroy() end)
	end

	local ok, err = pcall(function()
		sfx(SND.click, 1.2, 1, 3)

		-- ---------- aim: the centre of your screen ----------
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char }
		local vs = cam.ViewportSize
		local ray = cam:ViewportPointToRay(vs.X / 2, vs.Y / 2)
		local res = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
		local T, N
		if res then
			T, N = res.Position, res.Normal
		else
			local p = ray.Origin + ray.Direction * 150
			local down = workspace:Raycast(p + Vector3.new(0, 200, 0), Vector3.new(0, -800, 0), params)
			if down then T, N = down.Position, down.Normal else T, N = p, Vector3.new(0, 1, 0) end
		end
		if N.Y < 0.3 then N = Vector3.new(0, 1, 0) end

		-- ground marker + red laser (shared by both modes)
		local laserR = makeRig(realFolder, 3, laserLayers())
		local mk1 = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 18, 18), CFrame = flatCF(T + N * 0.1, N), Color = CONFIG.LASER_COLOR, Material = Enum.Material.Neon }, realFolder)
		part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 16, 16), CFrame = flatCF(T + N * 0.16, N), Color = Color3.fromRGB(20, 0, 0) }, realFolder)
		local mk3 = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 5, 5), CFrame = flatCF(T + N * 0.22, N), Color = CONFIG.LASER_COLOR, Material = Enum.Material.Neon }, realFolder)
		local beamR = makeRig(realFolder, 3, beamLayers())
		local eraser

		if useCut then
			----------------------------------------------------------------
			-- CUTSCENE ON  (~10 s)
			----------------------------------------------------------------
			setControls(false)
			hum.WalkSpeed = 0; hum.JumpPower = 0; hum.JumpHeight = 0
			cam.CameraType = Enum.CameraType.Scriptable
			saveLighting()
			task.spawn(function()
				local okb, res2 = pcall(buildStage)
				if okb then stage = res2 else warn("[StellarRemote] stage build failed: " .. tostring(res2)) end
				stageReady = true
			end)
			hud.bars(true)
			hud.setLabel("SS-01  ·  RAILGUN")
			hud.setSub("TARGET LOCKED")

			live[#live + 1] = RunService.RenderStepped:Connect(function()
				local k = 1 + 0.12 * math.sin(os.clock() * 11)
				mk1.Size = Vector3.new(0.2, 18 * k, 18 * k)
				mk3.Size = Vector3.new(0.3, 5 * k, 5 * k)
			end)
			task.spawn(function()
				runFor(0.4, function(a)
					updateRig(laserR, T, T + DIR * 2600, function() return { 0.5 * a, 2.4 * a } end)
				end)
			end)

			-- lock-on (0.7 s)
			local startCF = cam.CFrame
			local toPlayer = Vector3.new(root.Position.X - T.X, 0, root.Position.Z - T.Z)
			if toPlayer.Magnitude < 5 then toPlayer = Vector3.new(0, 0, 1) end
			local lockPos = T + toPlayer.Unit * math.clamp(toPlayer.Magnitude, 26, 60) + Vector3.new(0, 10, 0)
			local lockLook = T + Vector3.new(0, 30, 0)
			local lockCF = CFrame.lookAt(lockPos, lockLook)
			runFor(TS(0.7), function(a) cam.CFrame = startCF:Lerp(lockCF, smooth(a)) end)

			-- up the laser + whiteout (0.9 s)
			sfx(SND.launch, 1.5, 1.0, 6)
			runFor(TS(0.9), function(a)
				local s = 6 + 2500 * (a ^ 2.2)
				local blend = smooth(a / 0.3)
				local ang = a * 2.0 + 0.8
				local off = (PERP * math.cos(ang) + PERP2 * math.sin(ang)) * 12
				local pos = lockPos:Lerp(T + DIR * s + off, blend)
				local look = lockLook:Lerp(T + DIR * (s + 500), blend)
				cam.CFrame = CFrame.lookAt(pos, look)
				cam.FieldOfView = 70 + 35 * (a ^ 1.5)
				fx.blur.Size = 16 * a * a
				local dd = smooth((a - 0.45) / 0.55)
				fx.cc.Brightness = -0.3 * dd
				fx.cc.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(160, 190, 255), dd)
				if a > 0.72 then hud.flash.BackgroundTransparency = 1 - smooth((a - 0.72) / 0.28) end
			end)
			hud.flash.BackgroundTransparency = 0

			while not stageReady do RunService.RenderStepped:Wait() end
			if not stage then error("stage not built") end
			resetFx()
			spaceLighting(); lightingActive = true
			hideWorld()

			local gun = stage.gun
			local function blink(rate)
				local on = (math.floor(os.clock() * rate) % 2 == 0)
				for _, b in ipairs(gun.blink) do b.Transparency = on and 0 or 0.85 end
			end
			local function laserUpdate()
				local cp = cam.CFrame.Position
				updateRig(stage.laser, E0, GFIN, function(_, mid)
					local d = (mid - cp).Magnitude
					local t = math.clamp(d * 0.006 + 0.8, 0.8, 160)
					return { t, t * 3.2 }
				end)
			end
			sfx(SND.whoosh, 1.2, 0.6, 10)

			-- ---------- lock + pull back: Earth > Saturn > Solar System > Milky Way ----------
			local prevEnd, prevLook
			for i, sh in ipairs(SHOTS) do
				local startPos = shotPos(sh, 0)
				if i > 1 then -- whip to the next object
					runFor(TS(0.22), function(a)
						local k = smooth(a)
						cam.CFrame = CFrame.lookAt(prevEnd:Lerp(startPos, k), prevLook:Lerp(sh.c, k))
						cam.FieldOfView = 70 + 25 * math.sin(a * math.pi)
						fx.blur.Size = 26 * math.sin(a * math.pi)
						laserUpdate()
					end)
				end
				hud.setLabel(sh.name)
				runFor(TS(sh.t), function(a, dt, e)
					local pos = shotPos(sh, a)
					cam.CFrame = CFrame.lookAt(pos, sh.c) * CFrame.Angles(0, 0, math.sin(a * 5 + i) * 0.025)
					cam.FieldOfView = 70 + 14 * smooth(a)
					fx.blur.Size = 6 * smooth(a)
					if i == 1 then hud.flash.BackgroundTransparency = smooth(e / 0.5) end
					laserUpdate()
					hud.setSub("DISTANCE FROM TARGET   " .. fmt((pos - E0).Magnitude * 4200) .. " KM")
					if i == 4 then -- the railgun is there: it glides in beside the camera
						local g = smooth((a - 0.2) / 0.8)
						local ease = 1 - (1 - g) ^ 2
						stage.gunModel:PivotTo(CFrame.new((GSTART - GFIN) * (1 - ease)) * GUNCF)
						blink(4)
					end
				end)
				prevEnd, prevLook = shotPos(sh, 1), sh.c
			end
			stage.gunModel:PivotTo(GUNCF)
			fx.blur.Size = 0

			-- ---------- charge (camera swings round to the gun's side) ----------
			hud.setLabel("RAILGUN  //  CHARGING")
			hud.setSub("")
			sfx(SND.launch, 1.6, 0.5, 8)
			local gunMid = GL(0, 0, -420)
			local relL = GUNCF:VectorToObjectSpace(P_END - gunMid)
			local sign = relL.X >= 0 and 1 or -1
			local CDIM, HOT = Color3.fromRGB(20, 85, 125), Color3.fromRGB(235, 250, 255)
			local lastPos = P_END
			runFor(TS(1.4), function(a)
				local th = sign * 0.95 * smooth(a)
				local rl = (CFrame.Angles(0, th, 0) * relL) * (1 - 0.22 * smooth(a))
				lastPos = gunMid + GUNCF:VectorToWorldSpace(rl)
				cam.CFrame = CFrame.lookAt(lastPos, gunMid) * shakeRot(0.001 + 0.012 * a * a)
				cam.FieldOfView = 62 - 10 * smooth(a)
				local prog = a * (#gun.coils + 3)
				for i2, frame in ipairs(gun.coils) do
					local col = CDIM:Lerp(HOT, math.clamp(prog - i2 + 1, 0, 1))
					for _, p in ipairs(frame) do p.Color = col end
				end
				for _, s2 in ipairs(gun.strips) do s2.Color = CDIM:Lerp(HOT, a) end
				gun.core.Size = V(46 + 70 * a * a)
				gun.core.Color = Color3.fromRGB(40, 180, 255):Lerp(Color3.new(1, 1, 1), a)
				gun.sparks.Rate = 160 * a
				blink(2 + 6 * a)
				laserUpdate()
			end)
			gun.sparks.Rate = 0

			-- ---------- fire, ride the beam to the Earth model ----------
			hud.setLabel("FIRE")
			sfx(SND.shot, 3, 0.5, 10)
			sfx(SND.boom, 2, 0.5, 10)
			updateRig(stage.laser, E0, E0, function() return { 1, 1 } end) -- targeting laser off
			gun.flash.Transparency = 0
			TweenService:Create(gun.flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V(420), Transparency = 1 }):Play()
			local muzzle = GL(0, 0, -905)
			local fwd = (E0 - muzzle).Unit
			local total = (E0 - muzzle).Magnitude
			local HEND = total - 700
			local function thick(grow) return function() return { 90 * grow, 210 * grow, 380 * grow } end end

			runFor(TS(0.85), function(a, dt, e)
				local H = HEND * (a ^ 2.0)
				local head = muzzle + fwd * H
				updateRig(stage.beam, muzzle, head, thick(math.clamp(e / 0.3, 0, 1)))
				local blend = smooth(e / 0.4)
				local pos = lastPos:Lerp(muzzle + fwd * math.max(H - 120, 0), blend)
				local look = muzzle:Lerp(head + fwd * 600, blend)
				cam.CFrame = CFrame.lookAt(pos, look) * shakeRot(0.012 * (1 - blend) + 0.004)
				cam.FieldOfView = 55 + 60 * smooth(e / 0.8)
				fx.blur.Size = 22 * blend
			end)

			local endPos1 = muzzle + fwd * (HEND - 120)
			local lat = fwd:Cross(Vector3.new(0, 1, 0)).Unit
			local earthFlashDone = false
			runFor(TS(0.45), function(a)
				local H = HEND + 700 * (a ^ 1.6)
				updateRig(stage.beam, muzzle, muzzle + fwd * H, thick(1))
				local k = smooth(a)
				local pos = endPos1:Lerp(muzzle + fwd * (HEND - 100) + lat * 650, k)
				local look = (muzzle + fwd * (HEND + 600)):Lerp(E0, k)
				cam.CFrame = CFrame.lookAt(pos, look) * shakeRot(0.004 + 0.01 * a)
				cam.FieldOfView = 115 - 40 * k
				fx.blur.Size = 22 * (1 - k)
				if a > 0.85 and not earthFlashDone then
					earthFlashDone = true
					local ef = part({ Shape = Enum.PartType.Ball, Size = V(40), Position = E0, Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon }, stage.folder)
					TweenService:Create(ef, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V(900), Transparency = 1 }):Play()
				end
				if a > 0.75 then hud.flash.BackgroundTransparency = 1 - smooth((a - 0.75) / 0.25) end
			end)
			hud.flash.BackgroundTransparency = 0

			-- ---------- down to where you are: re-entry, the beam strikes ----------
			stage.folder:Destroy()
			leaveSpace()
			resetFx()
			hud.setLabel("RE-ENTRY")
			hud.setSub("")
			eraser = makeEraser(T)
			local fp = part({ Size = Vector3.new(60, 60, 6), Transparency = 1 }, realFolder)
			local fire = Instance.new("ParticleEmitter")
			fire.Rate = 260
			fire.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 60, 10))
			fire.LightEmission = 1
			fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 10), NumberSequenceKeypoint.new(1, 2) })
			fire.Lifetime = NumberRange.new(0.3, 0.6)
			fire.Speed = NumberRange.new(0, 0)
			fire.Parent = fp
			sfx(SND.whoosh, 2, 0.8, 6)
			runFor(TS(0.8), function(a, dt, e)
				local s = 2500 - 2440 * a * a
				local pos = T + DIR * s
				cam.CFrame = CFrame.lookAt(pos, T) * CFrame.Angles(0, 0, math.sin(a * 9) * 0.04) * shakeRot(0.006 * a)
				cam.FieldOfView = 105 - 20 * a
				fx.blur.Size = 20
				local heat = smooth(a * 1.4)
				fx.cc.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 170, 110), heat)
				fx.cc.Contrast = 0.2 * heat
				fp.CFrame = CFrame.lookAt(pos + (T - pos).Unit * 14, T)
				local headS = math.max(s - 160, 0)
				updateRig(beamR, T + DIR * 2700, T + DIR * headS, function() return { 30, 70, 130 } end)
				eraser(headS)
				if e < 0.2 then hud.flash.BackgroundTransparency = smooth(e / 0.2) end
				if a > 0.8 then hud.flash.BackgroundTransparency = 1 - smooth((a - 0.8) / 0.2) end
			end)
			hud.flash.BackgroundTransparency = 0
			fire.Rate = 0
			fp:Destroy()

			for _, cn in ipairs(live) do cn:Disconnect() end
			live = {}
			restorePlayer()
			resetFx()
			hud.setLabel("")
			hud.setSub("")
			hud.bars(false)
			impact(hud, T, N, beamR, eraser, true)
		else
			----------------------------------------------------------------
			-- CUTSCENE OFF: red beam live, no camera movement (~10 s total)
			----------------------------------------------------------------
			hud.setLabel("SS-01  ·  RAILGUN")
			sfx(SND.launch, 1.3, 0.45, 9)
			local flare = part({ Shape = Enum.PartType.Ball, Size = V(20), Position = T + DIR * 2600, Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon, Transparency = 0.2 }, realFolder)
			local cp = part({ Size = Vector3.new(14, 1, 14), Position = T + N * 0.5, Transparency = 1 }, realFolder)
			local em = Instance.new("ParticleEmitter")
			em.Rate = 0
			em.Color = ColorSequence.new(Color3.fromRGB(255, 120, 90), Color3.fromRGB(255, 30, 20))
			em.LightEmission = 1
			em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
			em.Lifetime = NumberRange.new(1, 2)
			em.Speed = NumberRange.new(12, 40)
			em.SpreadAngle = Vector2.new(12, 12)
			em.EmissionDirection = Enum.NormalId.Top
			em.Parent = cp
			local CH = CONFIG.LIVE_CHARGE
			runFor(CH, function(a, dt, e)
				local pulse = 1 + (0.2 + 0.5 * a) * math.sin(e * (8 + 24 * a))
				local core, glow = (1.3 + 1.9 * a) * pulse, (5 + 10 * a) * pulse
				updateRig(laserR, T, T + DIR * 2600, function() return { core, glow } end)
				local d = (18 - 6 * a) * (1 + 0.08 * math.sin(e * 12))
				mk1.Size = Vector3.new(0.2, d, d)
				mk3.Size = Vector3.new(0.3, 5 + 5 * a, 5 + 5 * a)
				flare.Size = V(20 + 150 * a * a)
				em.Rate = 8 + 90 * a
				hud.setSub(("FIRING IN  %.1f"):format(math.max(CH - e, 0)))
			end)
			em.Rate = 0
			hud.setSub("")
			hud.setLabel("FIRE")
			sfx(SND.shot, 3, 0.5, 10)
			eraser = makeEraser(T)
			updateRig(laserR, T, T, function() return { 1, 1 } end)
			runFor(0.4, function(a)
				local headS = 2700 * (1 - a ^ 1.8)
				updateRig(beamR, T + DIR * 2700, T + DIR * headS, function() return { 30, 70, 130 } end)
				eraser(headS)
			end)
			flare:Destroy()
			hud.flash.BackgroundTransparency = 0.15
			impact(hud, T, N, beamR, eraser, false)
		end
		task.wait(0.4)
	end)

	if not ok then warn("[StellarRemote] " .. tostring(err)) end
	restoreAll()
	busy = false
end

------------------------------------------------------------------------
-- SS-03 · GUNGNIR
-- Orange beam points UP. Camera follows it to space: Earth > Jupiter (forms) > accelerator ring (forms),
-- the spear loads, does 7 laps (faster each lap), RELEASE, rockets into Earth, falls through the sky as a
-- star, slams into the ground: huge blast, collidable spear, hexagons across the ground.
------------------------------------------------------------------------
local UP        = Vector3.new(0, 1, 0)
local NEONM, METALMAT = Enum.Material.Neon, Enum.Material.Metal
local CYLS, BALLS = Enum.PartType.Cylinder, Enum.PartType.Ball

local GS        = Vector3.new(0, 30000, 0)                -- Earth top in the Gungnir space scene
local G_JUP     = GS + Vector3.new(0, 15000, 0)           -- Jupiter sits straight above Earth, on the beam
local G_RING_R  = 2500
local G_P0      = G_JUP + Vector3.new(G_RING_R, 0, 0)    -- spear start + release point (ring's right side)
local G_CTRL    = G_P0 + Vector3.new(0, -8000, 0)
local G_LAPS    = { 1.0, 0.8, 0.62, 0.5, 0.4, 0.32, 0.26 } -- seconds per lap: faster every lap
local G_EARTH   = { c = GS + Vector3.new(0, -250, 0), dir = Vector3.new(0.78, 0.42, 0.46).Unit, d0 = 1500, d1 = 9000 }
local function gEarthPos(a) return G_EARTH.c + G_EARTH.dir * (G_EARTH.d0 * (G_EARTH.d1 / G_EARTH.d0) ^ (a ^ 1.35)) end
local G_PE1     = gEarthPos(1)
local G_PJ1     = G_JUP + Vector3.new(1300, 450, 5500)
local G_LOADCAM = G_P0 + Vector3.new(650, 140, 950)
local G_WIDECAM = G_JUP + Vector3.new(0, 200, 9200)
local SPEAR_STAGE_SCALE, SPEAR_REAL_SCALE = 2.2, 1.5

local function gBez(u)
	local a, b, c = (1 - u) ^ 2, 2 * (1 - u) * u, u * u
	return G_P0 * a + G_CTRL * b + GS * c
end
local function gBezDir(u)
	return ((G_CTRL - G_P0) * (2 * (1 - u)) + (GS - G_CTRL) * (2 * u)).Unit
end
local function poseCF(pos, dir)
	local up = math.abs(dir.Y) > 0.98 and Vector3.new(1, 0, 0) or UP
	return CFrame.lookAt(pos, pos + dir, up)
end
local function gLayers()
	return {
		{ color = Color3.fromRGB(255, 240, 150), alpha = 0 },
		{ color = Color3.fromRGB(255, 160, 40),  alpha = 0.3 },
		{ color = Color3.fromRGB(255, 100, 10),  alpha = 0.75 },
	}
end

-- ---------------------------------------------------------------- the spear (rocket-spear)
local function buildSpear(parent, sc, solidCollide)
	local m = Instance.new("Model")
	m.Name = "Gungnir"
	local spear = { model = m, items = {}, glow = {}, flames = {} }
	local ORANGE = Color3.fromRGB(255, 120, 20)
	local GOLD = Color3.fromRGB(232, 182, 72)
	local DARK = Color3.fromRGB(46, 38, 34)
	local WHITE = Color3.fromRGB(255, 244, 214)

	local function add(kind, z, cf, size, color, mat, shape, transp)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = (kind == "solid") and solidCollide or false
		p.CanQuery = (kind == "solid") and solidCollide or false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.Material = mat
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if shape then p.Shape = shape end
		p.Size = size * sc
		p.Color = color
		p.Transparency = transp or 0
		p.CFrame = cf
		p.Parent = m
		local e = { p = p, base = p.Transparency, kind = kind, z = z }
		spear.items[#spear.items + 1] = e
		if kind == "glow" then spear.glow[#spear.glow + 1] = e
		elseif kind == "flame" then spear.flames[#spear.flames + 1] = e end
		return e
	end
	local function cyl(kind, z, len, dia, color, mat, transp)
		add(kind, z, CFrame.new(0, 0, z * sc) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(len, dia, dia), color, mat, CYLS, transp)
	end
	local function blk(kind, z, sx, sy, sz, color, mat, transp)
		add(kind, z, CFrame.new(0, 0, z * sc), Vector3.new(sx, sy, sz), color, mat, nil, transp)
	end

	-- shaft, collars, gold bands
	cyl("solid", -15, 90, 5, DARK, METALMAT)
	cyl("solid", -58, 3, 11, ORANGE, NEONM)
	cyl("solid", -38, 2, 8, ORANGE, NEONM)
	cyl("solid", -8, 2, 8, ORANGE, NEONM)
	cyl("solid", 14, 2, 8, ORANGE, NEONM)
	cyl("solid", -48, 6, 6.6, GOLD, METALMAT)
	-- tapered spearhead + blades
	cyl("solid", -66, 12, 9, GOLD, METALMAT)
	cyl("solid", -78, 12, 7, GOLD, METALMAT)
	cyl("solid", -88, 10, 5, GOLD, METALMAT)
	cyl("solid", -96, 8, 3.2, GOLD, METALMAT)
	cyl("solid", -102, 6, 1.6, WHITE, NEONM)
	blk("solid", -82, 16, 1.2, 40, GOLD, METALMAT)
	blk("solid", -82, 1.2, 16, 40, GOLD, METALMAT)
	-- rocket tail: fins + nozzle + flame
	blk("solid", 30, 1.2, 26, 22, DARK, METALMAT)
	blk("solid", 30, 26, 1.2, 22, DARK, METALMAT)
	cyl("solid", 40, 12, 9, DARK, METALMAT)
	cyl("flame", 58, 34, 6.5, ORANGE, NEONM, 0.25)
	cyl("flame", 52, 24, 3.2, WHITE, NEONM, 0.1)
	-- star look: glow balls + spikes
	add("glow", 0, CFrame.new(), Vector3.new(70, 70, 70), Color3.fromRGB(255, 140, 30), NEONM, BALLS, 0.35)
	add("glow", 0, CFrame.new(), Vector3.new(32, 32, 32), WHITE, NEONM, BALLS, 0.05)
	add("glow", 0, CFrame.new(), Vector3.new(170, 170, 170), Color3.fromRGB(255, 120, 20), NEONM, BALLS, 0.82)
	add("glow", 0, CFrame.new(), Vector3.new(520, 5, 5), ORANGE, NEONM, nil, 0.1)
	add("glow", 0, CFrame.new(), Vector3.new(5, 520, 5), ORANGE, NEONM, nil, 0.1)
	add("glow", 0, CFrame.Angles(0, 0, math.rad(45)), Vector3.new(340, 4, 4), WHITE, NEONM, nil, 0.25)
	add("glow", 0, CFrame.Angles(0, 0, math.rad(-45)), Vector3.new(340, 4, 4), WHITE, NEONM, nil, 0.25)

	-- loading order: tail -> tip
	local zmin, zmax = math.huge, -math.huge
	for _, e in ipairs(spear.items) do
		if e.kind == "solid" then zmin = math.min(zmin, e.z); zmax = math.max(zmax, e.z) end
	end
	for _, e in ipairs(spear.items) do e.order = (zmax - e.z) / (zmax - zmin) end

	-- trail + exhaust at the tail
	local anchor = Instance.new("Part")
	anchor.Anchored = true; anchor.CanCollide = false; anchor.CanQuery = false; anchor.CanTouch = false
	anchor.Transparency = 1; anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(0, 0, 62 * sc)
	anchor.Parent = m
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(-14 * sc, 0, 0); a0.Parent = anchor
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(14 * sc, 0, 0); a1.Parent = anchor
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0; trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 130), Color3.fromRGB(255, 70, 10))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.7
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = anchor
	local exhaust = Instance.new("ParticleEmitter")
	exhaust.Rate = 0
	exhaust.Color = ColorSequence.new(Color3.fromRGB(255, 210, 120), Color3.fromRGB(255, 60, 10))
	exhaust.LightEmission = 1
	exhaust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 16 * sc), NumberSequenceKeypoint.new(1, 0) })
	exhaust.Lifetime = NumberRange.new(0.4, 0.7)
	exhaust.Speed = NumberRange.new(0, 0)
	exhaust.Parent = anchor

	function spear.reveal(k)
		for _, e in ipairs(spear.items) do
			if e.kind == "solid" then e.p.Transparency = (k > 0 and k >= e.order) and e.base or 1 end
		end
	end
	function spear.setGlow(k)
		for _, e in ipairs(spear.glow) do e.p.Transparency = 1 - k * (1 - e.base) end
	end
	function spear.setFlame(k)
		for _, e in ipairs(spear.flames) do e.p.Transparency = 1 - k * (1 - e.base) end
		exhaust.Rate = 260 * k
	end
	function spear.setTrail(on) trail.Enabled = on end

	m.WorldPivot = CFrame.new()
	m.Parent = parent
	spear.reveal(0); spear.setGlow(0); spear.setFlame(0)
	return spear
end

-- ---------------------------------------------------------------- the space scene
local function buildGungnirStage()
	local Q = CONFIG.QUALITY
	local folder = Instance.new("Folder")
	folder.Name = "StellarGungnirStage"
	folder.Parent = workspace

	local made = 0
	local function P(props, parent)
		made += 1
		if made % 140 == 0 then task.wait() end
		return part(props, parent or folder)
	end
	local rng = Random.new(2024)

	-- EARTH (same model as SS-01)
	do
		local c = GS + Vector3.new(0, -1000, 0)
		P({ Shape = BALLS, Size = V(2000), Position = c, Color = Color3.fromRGB(10, 45, 115), Reflectance = 0.08 })
		local function disc(dir, radius, d, thick, props)
			props.Shape = CYLS
			props.Size = Vector3.new(thick, d, d)
			props.CFrame = flatCF(c + dir * radius, dir)
			return P(props)
		end
		local lands = { Color3.fromRGB(46, 110, 52), Color3.fromRGB(70, 128, 58), Color3.fromRGB(104, 134, 70), Color3.fromRGB(160, 138, 84), Color3.fromRGB(190, 165, 100) }
		for _ = 1, 8 do
			local cen = randUnit(rng)
			local spread = rng:NextNumber(0.12, 0.26)
			for _ = 1, math.max(6, math.floor(16 * Q)) do
				local d = (cen + randUnit(rng) * spread).Unit
				disc(d, 999.2, rng:NextNumber(70, 190), 7, { Color = lands[rng:NextInteger(1, #lands)] })
			end
		end
		disc(Vector3.new(0, 1, 0), 999.2, 340, 7, { Color = Color3.fromRGB(240, 245, 250) })
		disc(Vector3.new(0, -1, 0), 999.2, 300, 7, { Color = Color3.fromRGB(240, 245, 250) })
		for _ = 1, math.floor(70 * Q) do
			disc(randUnit(rng), 1008, rng:NextNumber(60, 200), 3, { Color = Color3.new(1, 1, 1), Transparency = 0.3 })
		end
		P({ Shape = BALLS, Size = V(2044), Position = c, Color = Color3.fromRGB(90, 160, 255), Material = NEONM, Transparency = 0.9 })
	end

	-- JUPITER (a Model so it can "form" with ScaleTo)
	local jup = Instance.new("Model")
	jup.Name = "Jupiter"
	jup.Parent = folder
	local jupParts = {}
	do
		local c = G_JUP
		local function JP(props)
			local p = P(props, jup)
			jupParts[#jupParts + 1] = { p = p, base = p.Transparency }
			return p
		end
		JP({ Shape = BALLS, Size = V(1960), Position = c, Color = Color3.fromRGB(206, 160, 116) })
		local bands = {
			{ -640, 80, Color3.fromRGB(226, 196, 150) }, { -520, 90, Color3.fromRGB(150, 98, 66) },
			{ -380, 110, Color3.fromRGB(232, 205, 160) }, { -230, 100, Color3.fromRGB(176, 108, 72) },
			{ -90, 120, Color3.fromRGB(236, 212, 170) }, { 40, 110, Color3.fromRGB(158, 100, 68) },
			{ 170, 100, Color3.fromRGB(230, 202, 156) }, { 300, 110, Color3.fromRGB(180, 112, 74) },
			{ 450, 90, Color3.fromRGB(228, 198, 152) }, { 580, 80, Color3.fromRGB(150, 98, 66) },
		}
		local R = 980
		for _, b in ipairs(bands) do
			local h, th, col = b[1], b[2], b[3]
			local dia = 2 * math.sqrt((R + 0.8) ^ 2 - (math.abs(h) + th / 2) ^ 2)
			JP({ Shape = CYLS, Size = Vector3.new(th, dia, dia), CFrame = CFrame.new(c + Vector3.new(0, h, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = col })
		end
		local d = Vector3.new(0.28, -0.3, 0.91).Unit -- Great Red Spot, facing the camera side
		JP({ Shape = CYLS, Size = Vector3.new(24, 300, 300), CFrame = flatCF(c + d * (R - 12), d), Color = Color3.fromRGB(176, 76, 48) })
		JP({ Shape = CYLS, Size = Vector3.new(20, 190, 190), CFrame = flatCF(c + d * (R - 9), d), Color = Color3.fromRGB(205, 108, 72) })
		JP({ Shape = BALLS, Size = V(2040), Position = c, Color = Color3.fromRGB(255, 160, 80), Material = NEONM, Transparency = 0.93 })
	end
	jup.WorldPivot = CFrame.new(G_JUP)
	jup:ScaleTo(0.03)
	for _, jp in ipairs(jupParts) do jp.p.Transparency = 1 end

	-- ACCELERATOR RING (vertical ring, seen face-on from +Z)
	local ring = { parts = {}, strips = {} }
	do
		local N = math.max(36, math.floor(72 * Q))
		local arc = 2 * math.pi * G_RING_R / N
		local METAL = Color3.fromRGB(52, 54, 66)
		local DARK = Color3.fromRGB(30, 31, 40)
		local ORG = Color3.fromRGB(255, 120, 20)
		for i = 1, N do
			local ang = (i - 0.5) / N * 2 * math.pi
			local radial = Vector3.new(math.cos(ang), math.sin(ang), 0)
			local tangent = Vector3.new(-math.sin(ang), math.cos(ang), 0)
			local base = CFrame.fromMatrix(G_JUP + radial * G_RING_R, tangent, Vector3.new(0, 0, 1), radial)
			local f = (i - 1) / N
			local function RP(cf, size, color, mat, isStrip)
				local p = P({ Size = size, Color = color, Material = mat, Transparency = 1, CFrame = base * cf })
				ring.parts[#ring.parts + 1] = { p = p, cf = base * cf, f = f }
				if isStrip then ring.strips[#ring.strips + 1] = p end
			end
			RP(CFrame.new(0, 0, 0), Vector3.new(arc * 1.04, 60, 150), METAL, METALMAT)
			RP(CFrame.new(0, 34, 62), Vector3.new(arc * 1.04, 8, 14), ORG, NEONM, true)
			RP(CFrame.new(0, 34, -62), Vector3.new(arc * 1.04, 8, 14), ORG, NEONM, true)
			RP(CFrame.new(0, 0, 90), Vector3.new(arc * 1.04, 80, 22), DARK, METALMAT)
			RP(CFrame.new(0, 0, -90), Vector3.new(arc * 1.04, 80, 22), DARK, METALMAT)
			if i % 3 == 0 then
				RP(CFrame.new(0, 0, 0), Vector3.new(arc * 0.5, 120, 210), METAL, METALMAT)
				RP(CFrame.new(0, 64, 0), Vector3.new(arc * 0.52, 6, 190), Color3.fromRGB(255, 190, 90), NEONM, true)
			end
		end
	end
	-- forming animation: segments fly in around the ring one after another
	local function formRing(tau)
		for _, e in ipairs(ring.parts) do
			local p = math.clamp((tau - e.f * 0.55) / 0.45, 0, 1)
			local ease = 1 - (1 - p) ^ 3
			e.p.Transparency = 1 - ease
			if ease >= 1 then
				e.p.CFrame = e.cf
			else
				e.p.CFrame = e.cf * CFrame.new(0, (1 - ease) * 700, (1 - ease) * 2400)
			end
		end
	end
	formRing(0)

	local spear = buildSpear(folder, SPEAR_STAGE_SCALE, false)
	spear.model:PivotTo(poseCF(G_P0, Vector3.new(0, -1, 0)))

	return {
		folder = folder, jup = jup, jupParts = jupParts, ring = ring, formRing = formRing, spear = spear,
		beam = makeRig(folder, 10, gLayers()),
	}
end

-- ---------------------------------------------------------------- hexagons across the ground
local function hexWave(T)
	if env.__StellarHex then pcall(function() env.__StellarHex:Destroy() end) end
	local folder = Instance.new("Folder")
	folder.Name = "StellarHex"
	folder.Parent = workspace
	env.__StellarHex = folder
	task.spawn(function()
		local Rh = CONFIG.HEX_CELL / math.sqrt(math.max(CONFIG.QUALITY, 0.25))
		local rad = CONFIG.HEX_RADIUS
		local d = math.sqrt(3) * Rh
		local a1 = Vector3.new(d, 0, 0)
		local a2 = Vector3.new(d * 0.5, 0, d * math.sqrt(3) / 2)
		local dirs = { Vector3.new(1, 0, 0), Vector3.new(0.5, 0, math.sqrt(3) / 2), Vector3.new(-0.5, 0, math.sqrt(3) / 2) }
		local edges = {}
		local qm = math.ceil(rad / d) + 2
		for q = -qm, qm do
			for r = -qm, qm do
				local c = a1 * q + a2 * r
				if c.Magnitude <= rad + d then
					for k = 1, 3 do -- 3 edges per cell = every honeycomb edge exactly once
						local mid = c + dirs[k] * (d / 2)
						if mid.Magnitude <= rad then
							edges[#edges + 1] = { mid, Vector3.new(-dirs[k].Z, 0, dirs[k].X), mid.Magnitude }
						end
					end
				end
			end
		end
		table.sort(edges, function(x, y) return x[3] < y[3] end)

		local ex = {}
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl.Character then ex[#ex + 1] = pl.Character end
		end
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = ex

		local bars, idx, last = {}, 1, os.clock()
		local rate = #edges / 1.4 -- the wave sweeps out in ~1.4 s
		while idx <= #edges and folder.Parent do
			RunService.Heartbeat:Wait()
			local now = os.clock()
			local n = math.max(1, math.floor(rate * (now - last)))
			last = now
			for _ = 1, n do
				local e = edges[idx]
				if not e then break end
				idx += 1
				local hit = workspace:Raycast(Vector3.new(T.X + e[1].X, T.Y + 250, T.Z + e[1].Z), Vector3.new(0, -600, 0), rp)
				if hit then
					local f = e[3] / rad
					local pos = hit.Position + Vector3.new(0, 0.45, 0)
					bars[#bars + 1] = part({
						Size = Vector3.new(2.4, 0.6, Rh * 1.02),
						CFrame = CFrame.lookAt(pos, pos + e[2]),
						Color = Color3.fromRGB(255, 240, 180):Lerp(Color3.fromRGB(255, 105, 15), math.clamp(f * 1.7, 0, 1)),
						Material = Enum.Material.Neon,
					}, folder)
				end
			end
		end
		local t0 = os.clock()
		while folder.Parent and os.clock() - t0 < 36 do -- pulse
			local k = 0.5 + 0.5 * math.sin((os.clock() - t0) * 4)
			for _, b in ipairs(bars) do b.Transparency = 0.05 + 0.3 * k end
			task.wait(0.1)
		end
		local t1 = os.clock() -- fade out
		while folder.Parent and os.clock() - t1 < 3 do
			local a = (os.clock() - t1) / 3
			for _, b in ipairs(bars) do b.Transparency = 0.2 + 0.8 * a end
			task.wait(0.1)
		end
		if folder.Parent then folder:Destroy() end
	end)
end

-- ---------------------------------------------------------------- the big boom
local function impactG(S, T, N, beamRig, eraser)
	local hud = S.hud
	local R = 150
	local fold = Instance.new("Folder")
	fold.Name = "StellarImpact"
	fold.Parent = workspace
	task.delay(60, function() fold:Destroy() end)

	sfx(SND.boom, 3, 0.55, 12)
	sfx(SND.shot, 2.5, 0.3, 12)
	sfx(SND.boom, 2, 0.9, 10)
	TweenService:Create(hud.flash, TweenInfo.new(1.4), { BackgroundTransparency = 1 }):Play()

	eraser(-1)
	if CONFIG.CARVE_LAND then
		pcall(function() workspace.Terrain:FillBall(T, R * 0.8, Enum.Material.Air) end)
		pcall(function() workspace.Terrain:FillCylinder(CFrame.new(T + UP * 350), 700, 45, Enum.Material.Air) end)
	end

	-- crater
	part({ Shape = CYLS, Size = Vector3.new(0.1, R * 2.2, R * 2.2), CFrame = flatCF(T + N * 0.15, N), Color = Color3.fromRGB(255, 110, 20), Material = NEONM, Transparency = 0.35 }, fold)
	part({ Shape = CYLS, Size = Vector3.new(0.1, R * 2.0, R * 2.0), CFrame = flatCF(T + N * 0.3, N), Color = Color3.fromRGB(14, 12, 12) }, fold)
	part({ Shape = CYLS, Size = Vector3.new(0.1, R * 0.9, R * 0.9), CFrame = flatCF(T + N * 0.45, N), Color = Color3.fromRGB(255, 80, 10), Material = NEONM, Transparency = 0.15 }, fold)

	-- fireball, dome, pillar of fire
	local fb = part({ Shape = BALLS, Size = V(6), Position = T + Vector3.new(0, 6, 0), Color = Color3.fromRGB(255, 190, 90), Material = NEONM }, fold)
	local fb2 = part({ Shape = BALLS, Size = V(4), Position = T + Vector3.new(0, 6, 0), Color = Color3.new(1, 1, 1), Material = NEONM }, fold)
	TweenService:Create(fb, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V(R * 3.4), Position = T + Vector3.new(0, R * 0.9, 0), Transparency = 1 }):Play()
	TweenService:Create(fb2, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V(R * 2), Position = T + Vector3.new(0, R * 0.6, 0), Transparency = 1 }):Play()
	local dome = part({ Shape = BALLS, Size = V(30), Position = T, Color = Color3.fromRGB(255, 140, 30), Material = NEONM, Transparency = 0.55 }, fold)
	TweenService:Create(dome, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V(1400), Transparency = 1 }):Play()
	local pillar = part({ Shape = CYLS, Size = Vector3.new(900, 40, 40), CFrame = CFrame.new(T + UP * 450) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 150, 40), Material = NEONM }, fold)
	TweenService:Create(pillar, TweenInfo.new(1.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(900, 260, 260), Transparency = 1 }):Play()

	-- shockwave rings
	local function ringWave(delay, maxR, dur, col)
		task.spawn(function()
			task.wait(delay)
			local SEGS = 90
			local ring = {}
			for i = 1, SEGS do ring[i] = part({ Size = Vector3.new(8, 4, 8), Color = col, Material = NEONM }, fold) end
			runFor(dur, function(a)
				local rad = 8 + (a ^ 0.55) * maxR
				local width = 16 * (1 - a) + 3
				local arc = 2 * math.pi * rad / SEGS * 1.1
				for i, p in ipairs(ring) do
					local ang = (i / SEGS) * math.pi * 2
					p.Size = Vector3.new(width, 5 * (1 - a) + 0.6, arc)
					p.CFrame = CFrame.new(T + Vector3.new(0, 2, 0)) * CFrame.new(math.cos(ang) * rad, 0, math.sin(ang) * rad) * CFrame.Angles(0, -ang, 0)
					p.Transparency = 0.1 + 0.9 * a
				end
			end)
			for _, p in ipairs(ring) do p:Destroy() end
		end)
	end
	ringWave(0, 1700, 2.0, Color3.fromRGB(255, 235, 190))
	ringWave(0.25, 1300, 2.0, Color3.fromRGB(255, 140, 30))

	-- embers + smoke
	local emP = part({ Size = Vector3.new(R, 1, R), Position = T + Vector3.new(0, 1, 0), Transparency = 1 }, fold)
	local em = Instance.new("ParticleEmitter")
	em.Rate = 0
	em.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 80, 20))
	em.LightEmission = 1
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3.2), NumberSequenceKeypoint.new(1, 0) })
	em.Lifetime = NumberRange.new(1.4, 3.2)
	em.Speed = NumberRange.new(90, 280)
	em.SpreadAngle = Vector2.new(70, 70)
	em.Acceleration = Vector3.new(0, -80, 0)
	em.EmissionDirection = Enum.NormalId.Top
	em.Parent = emP
	em:Emit(520)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Rate = 0
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 50, 40))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 40), NumberSequenceKeypoint.new(1, 170) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(3.5, 6)
	smoke.Speed = NumberRange.new(20, 80)
	smoke.SpreadAngle = Vector2.new(60, 60)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = emP
	smoke:Emit(150)
	em.Rate = 30
	task.delay(8, function() em.Rate = 0 end)

	-- orange tint over the whole screen, fading out
	local tint = Instance.new("ColorCorrectionEffect")
	tint.TintColor = Color3.fromRGB(255, 170, 110)
	tint.Brightness = 0.12
	tint.Contrast = 0.15
	tint.Parent = Lighting
	TweenService:Create(tint, TweenInfo.new(5, Enum.EasingStyle.Quad), { TintColor = Color3.new(1, 1, 1), Brightness = 0, Contrast = 0 }):Play()
	Debris:AddItem(tint, 6)

	hexWave(T)

	-- the beam flares and fades
	task.spawn(function()
		runFor(2.0, function(a)
			local k = (1 - a) ^ 0.6
			updateRig(beamRig, T, T + UP * 2600, function() return { 20 * k, 48 * k, 90 * k } end)
		end)
		updateRig(beamRig, T, T, function() return { 1, 1, 1 } end)
	end)
end

-- ---------------------------------------------------------------- session helper (camera/lighting/cleanup)
local function newSession(useCut, hum)
	local S = {}
	S.cam = getCam()
	S.saved = {
		type = S.cam.CameraType, subject = S.cam.CameraSubject, fov = S.cam.FieldOfView,
		ws = hum.WalkSpeed, jp = hum.JumpPower, jh = hum.JumpHeight,
	}
	S.hud = newHUD()
	S.hidden, S.live = {}, {}
	S.lightingActive = false
	S.playerRestored = not useCut
	S.realFolder = Instance.new("Folder")
	S.realFolder.Name = "StellarReal"
	S.realFolder.Parent = workspace
	if useCut then
		S.fx = { blur = Instance.new("BlurEffect"), cc = Instance.new("ColorCorrectionEffect"), bloom = Instance.new("BloomEffect") }
		S.fx.blur.Size = 0
		S.fx.bloom.Intensity = 0.8; S.fx.bloom.Size = 36; S.fx.bloom.Threshold = 0.9
		for _, e in pairs(S.fx) do e.Parent = Lighting end
	end

	function S.resetFx()
		if not S.fx then return end
		S.fx.blur.Size = 0
		S.fx.cc.Brightness = 0; S.fx.cc.Contrast = 0; S.fx.cc.Saturation = 0
		S.fx.cc.TintColor = Color3.new(1, 1, 1)
	end
	function S.enterSpace()
		spaceLighting()
		S.lightingActive = true
	end
	function S.hideWorld()
		local n = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") and d ~= workspace.Terrain then
				if not (S.stage and d:IsDescendantOf(S.stage.folder)) then
					local v = d.LocalTransparencyModifier
					if v < 1 then
						S.hidden[#S.hidden + 1] = { d, v }
						d.LocalTransparencyModifier = 1
					end
				end
			end
			n += 1
			if n % 3000 == 0 then task.wait() end
		end
	end
	function S.leaveSpace()
		if not S.lightingActive then return end
		S.lightingActive = false
		restoreLighting()
		for _, rec in ipairs(S.hidden) do
			if rec[1].Parent then rec[1].LocalTransparencyModifier = rec[2] end
		end
		S.hidden = {}
	end
	function S.restorePlayer()
		if S.playerRestored then return end
		S.playerRestored = true
		local c = getCam()
		c.CameraType = (S.saved.type ~= Enum.CameraType.Scriptable) and S.saved.type or Enum.CameraType.Custom
		if S.saved.subject then c.CameraSubject = S.saved.subject end
		c.FieldOfView = S.saved.fov
		if hum and hum.Parent then
			hum.WalkSpeed = S.saved.ws; hum.JumpPower = S.saved.jp; hum.JumpHeight = S.saved.jh
		end
		setControls(true)
	end
	function S.restoreAll()
		for _, cn in ipairs(S.live) do pcall(function() cn:Disconnect() end) end
		S.leaveSpace()
		S.restorePlayer()
		if S.fx then for _, e in pairs(S.fx) do pcall(function() e:Destroy() end) end end
		if S.stage and S.stage.folder then pcall(function() S.stage.folder:Destroy() end) end
		pcall(function() S.realFolder:Destroy() end)
		pcall(function() S.hud.gui:Destroy() end)
	end
	return S
end

-- ---------------------------------------------------------------- THE SS-03 SEQUENCE
local function runSS03()
	if busy then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then return end
	busy = true
	if menu then menu.close() end
	local useCut = env.__StellarCutsceneOn ~= false
	local S = newSession(useCut, hum)
	local hud, cam, fx = S.hud, S.cam, S.fx

	local ok, err = pcall(function()
		sfx(SND.click, 1.2, 1, 3)
		if env.__StellarSpear then pcall(function() env.__StellarSpear:Destroy() end) end
		local spearFolder = Instance.new("Folder")
		spearFolder.Name = "StellarSpear"
		spearFolder.Parent = workspace
		env.__StellarSpear = spearFolder
		task.delay(CONFIG.SPEAR_STAYS, function() if spearFolder.Parent then spearFolder:Destroy() end end)

		-- ---------- aim: the centre of your screen (same as the railgun) ----------
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char }
		local vs = cam.ViewportSize
		local ray = cam:ViewportPointToRay(vs.X / 2, vs.Y / 2)
		local res = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
		local T, N
		if res then
			T, N = res.Position, res.Normal
		else
			local p = ray.Origin + ray.Direction * 150
			local down = workspace:Raycast(p + Vector3.new(0, 200, 0), Vector3.new(0, -800, 0), params)
			if down then T, N = down.Position, down.Normal else T, N = p, Vector3.new(0, 1, 0) end
		end
		if N.Y < 0.3 then N = Vector3.new(0, 1, 0) end

		local toPlayer = Vector3.new(root.Position.X - T.X, 0, root.Position.Z - T.Z)
		if toPlayer.Magnitude < 5 then toPlayer = Vector3.new(0, 0, 1) end
		local farPos = T + toPlayer.Unit * 260 + Vector3.new(0, 18, 0)

		-- ---------- orange pulsing circle on the ground + orange beam pointing UP ----------
		local core = part({ Shape = CYLS, Size = Vector3.new(0.2, 16, 16), CFrame = flatCF(T + N * 0.1, N), Color = Color3.fromRGB(255, 130, 20), Material = NEONM, Transparency = 0.15 }, S.realFolder)
		local pulses = {}
		for i = 1, 3 do
			pulses[i] = part({ Shape = CYLS, Size = Vector3.new(0.15, 4, 4), CFrame = flatCF(T + N * (0.14 + i * 0.03), N), Color = Color3.fromRGB(255, 190, 90), Material = NEONM, Transparency = 1 }, S.realFolder)
		end
		local pulseSpeed, phase = 0.9, 0
		S.live[#S.live + 1] = RunService.RenderStepped:Connect(function(dt)
			phase += dt * pulseSpeed
			core.Size = Vector3.new(0.2, 16 * (1 + 0.1 * math.sin(os.clock() * 9)), 16 * (1 + 0.1 * math.sin(os.clock() * 9)))
			for i, p in ipairs(pulses) do
				local ph = (phase + i / 3) % 1
				local d = 8 + 46 * ph
				p.Size = Vector3.new(0.15, d, d)
				p.Transparency = 0.25 + 0.75 * ph
			end
		end)
		local beamUp = makeRig(S.realFolder, 3, gLayers())
		local eraser = makeEraser(T, 60, 150, UP)
		local RS = SPEAR_REAL_SCALE
		local FINAL_C = 102 * RS - 12 * RS -- spear centre height when its tip is buried in the ground

		-- the spear falls down the beam as a star and becomes a collidable spear
		local function descend(spear, dur, camFn)
			runFor(dur, function(a, dt, e)
				local s = FINAL_C + (2600 - FINAL_C) * (1 - a * a)
				spear.model:PivotTo(poseCF(T + UP * s, -UP))
				updateRig(beamUp, T, T + UP * 2600, function() return { 2.2 + 3 * a, 6 + 8 * a, 12 + 18 * a } end)
				eraser(s - 102 * RS)
				if camFn then camFn(s, a, e) end
			end)
			spear.model:PivotTo(poseCF(T + UP * FINAL_C, -UP))
		end
		local function landed(spear)
			spear.setGlow(0); spear.setFlame(0); spear.setTrail(false)
		end

		if useCut then
			----------------------------------------------------------------
			-- CUTSCENE ON  (~15 s)
			----------------------------------------------------------------
			setControls(false)
			hum.WalkSpeed = 0; hum.JumpPower = 0; hum.JumpHeight = 0
			cam.CameraType = Enum.CameraType.Scriptable
			saveLighting()
			local stageReady = false
			task.spawn(function()
				local okb, res2 = pcall(buildGungnirStage)
				if okb then S.stage = res2 else warn("[StellarRemote] stage build failed: " .. tostring(res2)) end
				stageReady = true
			end)
			hud.bars(true)
			hud.setLabel("SS-03  ·  GUNGNIR")
			hud.setSub("TARGET LOCKED")
			task.spawn(function()
				runFor(0.4, function(a)
					updateRig(beamUp, T, T + UP * 2600, function() return { 2.2 * a, 6 * a, 12 * a } end)
				end)
			end)

			-- camera goes to the laser (0.6 s)
			local startCF = cam.CFrame
			local lockPos = T + toPlayer.Unit * math.clamp(toPlayer.Magnitude, 26, 60) + Vector3.new(0, 10, 0)
			local lockLook = T + Vector3.new(0, 30, 0)
			local lockCF = CFrame.lookAt(lockPos, lockLook)
			runFor(TS(0.6), function(a) cam.CFrame = startCF:Lerp(lockCF, smooth(a)) end)

			-- ...then rises up the beam into the sky (0.8 s)
			sfx(SND.launch, 1.5, 1.0, 6)
			runFor(TS(0.8), function(a)
				local s = 6 + 2500 * (a ^ 2.2)
				local blend = smooth(a / 0.3)
				local ang = a * 2.0 + 0.8
				local off = Vector3.new(math.cos(ang), 0, math.sin(ang)) * 12
				local pos = lockPos:Lerp(T + UP * s + off, blend)
				local look = lockLook:Lerp(T + UP * (s + 500), blend)
				cam.CFrame = CFrame.lookAt(pos, look)
				cam.FieldOfView = 70 + 35 * (a ^ 1.5)
				fx.blur.Size = 16 * a * a
				local dd = smooth((a - 0.45) / 0.55)
				fx.cc.Brightness = -0.2 * dd
				fx.cc.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 205, 150), dd)
				if a > 0.72 then hud.flash.BackgroundTransparency = 1 - smooth((a - 0.72) / 0.28) end
			end)
			hud.flash.BackgroundTransparency = 0

			while not stageReady do RunService.RenderStepped:Wait() end
			if not S.stage then error("stage not built") end
			S.resetFx()
			S.enterSpace()
			S.hideWorld()
			local gst = S.stage
			local spear = gst.spear
			local function beamLOD()
				local cp = cam.CFrame.Position
				updateRig(gst.beam, GS, G_JUP, function(_, mid)
					local d = (mid - cp).Magnitude
					local t = math.clamp(d * 0.004 + 1.5, 1.5, 120)
					return { t, t * 2.4, t * 4.5 }
				end)
			end
			sfx(SND.whoosh, 1.2, 0.6, 10)

			-- ---------- lock on Earth, zoom out ----------
			hud.setLabel("EARTH")
			runFor(TS(1.1), function(a, dt, e)
				cam.CFrame = CFrame.lookAt(gEarthPos(a), G_EARTH.c) * CFrame.Angles(0, 0, math.sin(a * 5) * 0.025)
				cam.FieldOfView = 70 + 14 * smooth(a)
				fx.blur.Size = 6 * smooth(a)
				hud.flash.BackgroundTransparency = smooth(e / 0.5)
				beamLOD()
				hud.setSub("DISTANCE FROM TARGET   " .. fmt((gEarthPos(a) - GS).Magnitude * 4200) .. " KM")
			end)

			-- ---------- lock on Jupiter while flying to it; Jupiter + the ring FORM ----------
			hud.setLabel("JUPITER")
			local tJ = TS(1.5)
			runFor(tJ, function(a, dt, e)
				local k = smooth(a)
				local look = G_EARTH.c:Lerp(G_JUP, smooth(a / 0.35))
				cam.CFrame = CFrame.lookAt(G_PE1:Lerp(G_PJ1, k), look) * CFrame.Angles(0, 0, math.sin(a * 4) * 0.02)
				cam.FieldOfView = 84 - 20 * k
				fx.blur.Size = 6 * (1 - k)
				local jf = math.clamp(e / (tJ * 0.65), 0, 1)
				local ease = 1 - (1 - jf) ^ 2
				gst.jup:ScaleTo(0.03 + 0.97 * ease)
				for _, jp in ipairs(gst.jupParts) do jp.p.Transparency = 1 - ease * (1 - jp.base) end
				gst.formRing(math.clamp((e - tJ * 0.08) / (tJ * 0.85), 0, 1))
				beamLOD()
				hud.setSub("ACCELERATOR RING  FORMING")
				if a > 0.9 then hud.flash.BackgroundTransparency = 1 - smooth((a - 0.9) / 0.1) end
			end)
			gst.jup:ScaleTo(1)
			gst.formRing(1)
			hud.flash.BackgroundTransparency = 0

			-- ---------- teleport to the accelerator: the spear loads in ----------
			hud.setLabel("SS-03  ·  ACCELERATOR")
			S.resetFx()
			sfx(SND.launch, 1.4, 0.7, 8)
			local ORG, HOT = Color3.fromRGB(255, 120, 20), Color3.fromRGB(255, 250, 230)
			runFor(TS(1.1), function(a, dt, e)
				if e < 0.3 then hud.flash.BackgroundTransparency = smooth(e / 0.3) end
				local pos = G_LOADCAM:Lerp(G_P0 + Vector3.new(380, 90, 560), smooth(a))
				cam.CFrame = CFrame.lookAt(pos, G_P0)
				cam.FieldOfView = 66
				local load = math.clamp(a / 0.85, 0, 1)
				spear.reveal(load)
				spear.setGlow(smooth((a - 0.55) / 0.45) * 0.6)
				hud.setSub(("SPEAR LOADING   %d%%"):format(math.floor(load * 100)))
				for _, s2 in ipairs(gst.ring.strips) do s2.Color = ORG:Lerp(HOT, 0.25 * math.sin(e * 14) ^ 2) end
			end)
			spear.reveal(1)
			hud.setSub("")

			-- ---------- 7 laps around Jupiter, faster every lap ----------
			spear.setGlow(1)
			spear.setTrail(true)
			local lapDur, lapStart, total = {}, {}, 0
			for i, d0 in ipairs(G_LAPS) do
				lapDur[i] = TS(d0); lapStart[i] = total; total = total + lapDur[i]
			end
			local curLap = 0
			runFor(total, function(a, dt, e)
				local lap = #G_LAPS
				for i = 1, #G_LAPS do
					if e < lapStart[i] + lapDur[i] then lap = i break end
				end
				local u = math.clamp((e - lapStart[lap]) / lapDur[lap], 0, 1)
				local th = (lap - 1 + u) * 2 * math.pi
				local radial = Vector3.new(math.cos(th), -math.sin(th), 0)
				local tang = Vector3.new(-math.sin(th), -math.cos(th), 0) -- clockwise
				local pos = G_JUP + radial * G_RING_R
				spear.model:PivotTo(poseCF(pos, tang))
				if lap ~= curLap then
					curLap = lap
					hud.setLabel(("LAP  %d / %d"):format(lap, #G_LAPS))
					sfx(SND.whoosh, 1.2, 0.8 + 0.12 * lap, 3)
				end
				local sp = (lap - 1 + u) / #G_LAPS
				for _, s2 in ipairs(gst.ring.strips) do s2.Color = ORG:Lerp(HOT, sp) end
				-- wide view of Jupiter (laps 1-4), then the camera rides with the spear (laps 5-7)
				local wide = G_WIDECAM + Vector3.new(0, 0, 500 * a)
				local chasePos = pos + radial * 380 + Vector3.new(0, 0, 520) - tang * 700
				local chaseLook = pos + tang * 300 - radial * 120
				local ck = (lap >= 5) and smooth((e - lapStart[5]) / TS(0.15)) or 0
				cam.CFrame = CFrame.lookAt(wide:Lerp(chasePos, ck), G_JUP:Lerp(chaseLook, ck)) * shakeRot(0.001 + 0.006 * sp)
				cam.FieldOfView = 70 + 20 * sp
				fx.blur.Size = 14 * ck
			end)

			-- ---------- RELEASE ----------
			hud.title.TextSize = 56
			hud.title.TextColor3 = Color3.fromRGB(255, 170, 60)
			hud.setLabel("RELEASE")
			hud.setSub("")
			sfx(SND.shot, 3, 0.6, 8)
			sfx(SND.boom, 1.5, 0.8, 6)
			local holdCF = cam.CFrame
			runFor(TS(0.28), function(a)
				cam.CFrame = holdCF * shakeRot(0.004 + 0.01 * a)
				cam.FieldOfView = 90 - 12 * a
			end)

			-- the rocket-spear launches into the Earth model, camera at its side
			spear.setFlame(1)
			spear.setGlow(0.5)
			local fromCF = cam.CFrame
			local frozen
			local earthFlashDone = false
			runFor(TS(1.3), function(a, dt, e)
				local u = a ^ 2.3
				local pos = gBez(u)
				local dir = gBezDir(u)
				spear.model:PivotTo(poseCF(pos, dir))
				local sidePos = pos + Vector3.new(0, 40, 330) - dir * 160
				local look = pos + dir * 260
				if u > 0.93 then
					frozen = frozen or sidePos
					sidePos = frozen
					look = GS
				end
				local k = smooth(e / 0.35)
				local camPos = fromCF.Position:Lerp(sidePos, k)
				local camLook = (fromCF * CFrame.new(0, 0, -400)).Position:Lerp(look, k)
				cam.CFrame = CFrame.lookAt(camPos, camLook) * shakeRot(0.004)
				cam.FieldOfView = 70 + 35 * smooth(a)
				fx.blur.Size = 6 + 16 * a
				beamLOD()
				if a > 0.93 and not earthFlashDone then
					earthFlashDone = true
					local ef = part({ Shape = BALLS, Size = V(40), Position = GS, Color = Color3.new(1, 1, 1), Material = NEONM }, gst.folder)
					TweenService:Create(ef, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V(1100), Transparency = 1 }):Play()
				end
				if a > 0.82 then hud.flash.BackgroundTransparency = 1 - smooth((a - 0.82) / 0.18) end
			end)
			hud.flash.BackgroundTransparency = 0
			hud.title.TextSize = 26
			hud.title.TextColor3 = Color3.new(1, 1, 1)

			-- ---------- back in the game: a star comes down the sky ----------
			gst.folder:Destroy()
			S.leaveSpace()
			S.resetFx()
			hud.setLabel("")
			hud.setSub("")
			local rs = buildSpear(spearFolder, RS, true)
			rs.reveal(1); rs.setGlow(1); rs.setFlame(1); rs.setTrail(true)
			rs.model:PivotTo(poseCF(T + UP * 2600, -UP))
			sfx(SND.whoosh, 2, 0.8, 6)
			descend(rs, TS(1.2), function(s, a, e)
				local look = T + UP * math.max(s * 0.55, 80)
				cam.CFrame = CFrame.lookAt(farPos, look) * shakeRot(0.004 * a)
				cam.FieldOfView = 68 + 14 * a
				fx.blur.Size = 6 * a
				if e < 0.25 then hud.flash.BackgroundTransparency = smooth(e / 0.25) end
				if a > 0.9 then hud.flash.BackgroundTransparency = 1 - smooth((a - 0.9) / 0.1) end
			end)
			hud.flash.BackgroundTransparency = 0
			landed(rs)
			hud.bars(false)
			impactG(S, T, N, beamUp, eraser)
			-- hold the camera on the blast with a heavy shake, then give control back
			local baseCF = CFrame.lookAt(farPos, T + UP * 120)
			runFor(1.6, function(a)
				local k = (1 - a) ^ 2
				cam.CFrame = baseCF * shakeRot(0.03 * k)
				cam.FieldOfView = 70 + 18 * k
				fx.blur.Size = 12 * k
			end)
			S.resetFx()
			S.restorePlayer()
			task.wait(2.3)
		else
			----------------------------------------------------------------
			-- CUTSCENE OFF: orange beam live, no camera movement (~10 s)
			----------------------------------------------------------------
			hud.setLabel("SS-03  ·  GUNGNIR")
			local spear = buildSpear(spearFolder, RS, true)
			spear.model:PivotTo(poseCF(T + UP * 2600, -UP))
			local CH = CONFIG.LIVE_CHARGE
			sfx(SND.launch, 1.3, 0.45, 9)
			runFor(CH, function(a, dt, e)
				pulseSpeed = 0.9 + 2.6 * a
				local pulse = 1 + (0.2 + 0.5 * a) * math.sin(e * (8 + 24 * a))
				updateRig(beamUp, T, T + UP * 2600, function() return { (2.2 + 2.5 * a) * pulse, (6 + 8 * a) * pulse, (12 + 20 * a) * pulse } end)
				local load = math.clamp(a / 0.85, 0, 1)
				spear.reveal(load)
				spear.setGlow(0.2 + 0.8 * a * a)
				hud.setSub(("SPEAR LOADING  %d%%   ·   RELEASE IN %.1f"):format(math.floor(load * 100), math.max(CH - e, 0)))
			end)
			spear.reveal(1)
			hud.title.TextSize = 56
			hud.title.TextColor3 = Color3.fromRGB(255, 170, 60)
			hud.setLabel("RELEASE")
			hud.setSub("")
			sfx(SND.shot, 3, 0.6, 8)
			spear.setGlow(1); spear.setFlame(1); spear.setTrail(true)
			descend(spear, 1.0, nil)
			hud.title.TextSize = 26
			hud.title.TextColor3 = Color3.new(1, 1, 1)
			landed(spear)
			hud.flash.BackgroundTransparency = 0.15
			impactG(S, T, N, beamUp, eraser)
			task.wait(2.6)
		end
	end)

	if not ok then warn("[StellarRemote] " .. tostring(err)) end
	S.restoreAll()
	busy = false
end

------------------------------------------------------------------------
-- MENU (opens when you click/tap the remote)
------------------------------------------------------------------------
local function buildMenu()
	local g = Instance.new("ScreenGui")
	g.Name = "StellarRemoteUI"
	g.ResetOnSpawn = false
	g.DisplayOrder = 500
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local m = {}

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.Size = UDim2.fromOffset(300, 374)
	frame.BackgroundColor3 = Color3.fromRGB(12, 14, 22)
	frame.BackgroundTransparency = 0.04
	frame.BorderSizePixel = 0
	frame.Visible = false
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = frame
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(255, 50, 50); stroke.Thickness = 1.6
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; stroke.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Scale = math.clamp(getCam().ViewportSize.Y / 700, 0.8, 1.25)
	scale.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 14); pad.PaddingBottom = UDim.new(0, 14)
	pad.PaddingLeft = UDim.new(0, 14); pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = frame
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8); list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = frame

	local function label(text, size, color, order, h)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1; t.Font = Enum.Font.Code; t.Text = text; t.TextSize = size
		t.TextColor3 = color; t.Size = UDim2.new(1, 0, 0, h); t.LayoutOrder = order
		t.Parent = frame
		return t
	end
	local function button(text, order, active, h)
		local b = Instance.new("TextButton")
		b.AutoButtonColor = active
		b.Font = Enum.Font.Code; b.Text = text; b.TextSize = 20; b.TextColor3 = Color3.new(1, 1, 1)
		b.Size = UDim2.new(1, 0, 0, h or 54); b.LayoutOrder = order
		b.BackgroundColor3 = active and Color3.fromRGB(120, 10, 20) or Color3.fromRGB(30, 32, 42)
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = b
		local s = Instance.new("UIStroke"); s.Color = active and Color3.fromRGB(255, 70, 70) or Color3.fromRGB(70, 74, 90)
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Thickness = 1.2; s.Parent = b
		if not active then b.TextColor3 = Color3.fromRGB(120, 124, 140) end
		b.Parent = frame
		return b, s
	end

	label("STELLAR REMOTE", 24, Color3.new(1, 1, 1), 1, 30)
	label("THE SHOOTING STAR", 13, Color3.fromRGB(255, 110, 110), 2, 16)
	local ss01 = button("SS-01  ·  RAILGUN", 3, true)
	local ss03, ss03Stroke = button("SS-03  ·  GUNGNIR", 4, true)
	ss03.BackgroundColor3 = Color3.fromRGB(150, 72, 8)
	ss03Stroke.Color = Color3.fromRGB(255, 165, 45)
	local cutBtn, cutStroke = button("", 5, true, 44)
	local locked = button("SS-04  ·  SEVEN STARS  (LOCKED)", 6, false)
	locked.TextSize = 14
	local close = Instance.new("TextButton")
	close.Font = Enum.Font.Code; close.Text = "CLOSE"; close.TextSize = 16
	close.TextColor3 = Color3.fromRGB(200, 204, 220); close.BackgroundTransparency = 1
	close.Size = UDim2.new(1, 0, 0, 30); close.LayoutOrder = 7; close.Parent = frame

	local function refreshCut()
		local on = env.__StellarCutsceneOn ~= false
		cutBtn.Text = on and "CUTSCENE:  ON" or "CUTSCENE:  OFF"
		cutBtn.BackgroundColor3 = on and Color3.fromRGB(14, 90, 48) or Color3.fromRGB(58, 60, 74)
		cutStroke.Color = on and Color3.fromRGB(60, 220, 120) or Color3.fromRGB(120, 124, 140)
	end
	refreshCut()

	frame.Parent = g

	-- small always-available button (in case the game hides the hotbar)
	local fab = Instance.new("TextButton")
	fab.Size = UDim2.fromOffset(46, 46)
	fab.Position = UDim2.new(1, -60, 0.38, 0)
	fab.BackgroundColor3 = Color3.fromRGB(120, 10, 20)
	fab.Font = Enum.Font.Code; fab.Text = "SR"; fab.TextSize = 18; fab.TextColor3 = Color3.new(1, 1, 1)
	local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(1, 0); fc.Parent = fab
	local fs = Instance.new("UIStroke"); fs.Color = Color3.fromRGB(255, 70, 70); fs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; fs.Parent = fab
	fab.Parent = g

	function m.open() frame.Visible = true end
	function m.close() frame.Visible = false end
	function m.toggle() frame.Visible = not frame.Visible end

	conns[#conns + 1] = ss01.Activated:Connect(function() task.spawn(runSS01) end)
	conns[#conns + 1] = ss03.Activated:Connect(function() task.spawn(runSS03) end)
	conns[#conns + 1] = cutBtn.Activated:Connect(function()
		env.__StellarCutsceneOn = not (env.__StellarCutsceneOn ~= false)
		refreshCut()
	end)
	conns[#conns + 1] = close.Activated:Connect(m.close)
	conns[#conns + 1] = fab.Activated:Connect(m.toggle)

	protect(g)
	m.gui = g
	return m
end

------------------------------------------------------------------------
-- THE REMOTE (Tool)
------------------------------------------------------------------------
local function buildTool()
	local t = Instance.new("Tool")
	t.Name = "Stellar Remote"
	t.ToolTip = "Stellar Remote"
	t.CanBeDropped = false
	t.RequiresHandle = true

	local function bp(name, size, color, mat, shape, transp)
		local p = Instance.new("Part")
		p.Name = name; p.Size = size; p.Color = color; p.Material = mat or Enum.Material.SmoothPlastic
		p.CanCollide = false; p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
		if shape then p.Shape = shape end
		if transp then p.Transparency = transp end
		return p
	end
	local handle = bp("Handle", Vector3.new(0.7, 0.26, 1.9), Color3.fromRGB(24, 26, 34))
	handle.Parent = t
	local function attach(p, cf)
		local w = Instance.new("Weld")
		w.Part0 = handle; w.Part1 = p; w.C0 = cf
		w.Parent = p
		p.Parent = t
	end
	for r = 0, 2 do -- keypad
		for c = -1, 1 do
			attach(bp("Key", Vector3.new(0.14, 0.04, 0.14), Color3.fromRGB(90, 94, 108)), CFrame.new(c * 0.2, 0.15, 0.1 + r * 0.28))
		end
	end
	attach(bp("Cover", Vector3.new(0.6, 0.07, 0.5), Color3.fromRGB(150, 160, 180), Enum.Material.Glass, nil, 0.5), CFrame.new(0, 0.21, -0.6))
	attach(bp("RedButton", Vector3.new(0.06, 0.22, 0.22), Color3.fromRGB(255, 30, 30), Enum.Material.Neon, Enum.PartType.Cylinder), CFrame.new(0, 0.16, -0.6) * CFrame.Angles(0, 0, math.rad(90)))
	attach(bp("Led", Vector3.new(0.06, 0.06, 0.06), Color3.fromRGB(255, 40, 40), Enum.Material.Neon, Enum.PartType.Ball), CFrame.new(0, 0.16, -0.88))

	conns[#conns + 1] = t.Activated:Connect(function() if menu then menu.toggle() end end)
	return t
end

local function giveTool()
	local bp = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not bp then return end
	if bp:FindFirstChild("Stellar Remote") or (player.Character and player.Character:FindFirstChild("Stellar Remote")) then return end
	local tool = buildTool()
	tool.Parent = bp
	track(tool)
end

------------------------------------------------------------------------
-- START
------------------------------------------------------------------------
menu = buildMenu()
track(menu.gui)
giveTool()
conns[#conns + 1] = player.CharacterAdded:Connect(function()
	task.wait(1)
	giveTool()
end)

env.__StellarRemoteCleanup = function()
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	for _, o in ipairs(objs) do pcall(function() o:Destroy() end) end
	pcall(function() RunService:UnbindFromRenderStep("StellarShake") end)
end

print("[Stellar Remote v3] ready - equip the remote (or tap SR), set CUTSCENE ON/OFF, press SS-01 or SS-03.")
