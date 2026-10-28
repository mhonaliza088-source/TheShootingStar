--[[
	STELLAR REMOTE v5  ·  SS-01 RAILGUN + SS-03 GUNGNIR + SS-04 THE SHOOTING STAR + SS-05 TESSERACT
	LocalScript for Delta. 100% client-side: only YOU see anything.

	  1. Execute. You get a "Stellar Remote" tool (+ a small "SR" button on screen).
	  2. Tap the tool (equip, then tap again) or the SR button -> menu opens.
	  3. CUTSCENE: ON  = ~10 s cinematic (Earth > Saturn > Solar System > Milky Way > railgun > impact)
	     CUTSCENE: OFF = no camera movement, you watch the red beam charge live (~10 s) and then hit.
	  4. Aim the centre of your screen at the ground and press SS-01, SS-03, SS-04 or SS-05.
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
	DIPPER_SCALE  = 40,     -- SS-04: studs per degree of the Big Dipper (40 = about 930 studs wide)
	STAR_HEIGHT   = 1500,   -- SS-04: how high above the ground the 7 stars hang
	HOP_TIME      = 0.2,    -- SS-04: seconds the camera spends on each star
	SKY_STAY      = 15,     -- SS-04: seconds the glowing dipper + night sky stay after the finale
	LINES_STAY    = 30,     -- SS-04: seconds the burned holes + dipper lines stay on the ground
	TARGET_SIZE   = 260,    -- SS-05: width of the huge rainbow square target (about 5 houses)
	TESS_SIZE     = 1100,   -- SS-05: size of the giant tesseract (max 1400)
	STONE_VIEW    = 4,      -- SS-05: seconds the camera holds on the rainbow stone
	STONE_STAYS   = 30,     -- SS-05: seconds the stone + orbiting balls stay
	FLIP_STAY     = 20,     -- SS-05: seconds the folded half of the map stays flipped
	FOLD_MAX_PARTS = 40000, -- SS-05: safety cap on how many map parts get flipped
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
-- SS-04 · THE SHOOTING STAR  (the seven stars of the Big Dipper)
-- 7 lasers form the Big Dipper on the map > camera rises, sky goes black > camera hops to each star
-- (0.2 s each) and a white ritual ring forms > camera locks on the dipper > the stars fire purple lasers
-- one by one (name shown on screen at every hit) > the holes link into a dipper on the ground >
-- all 7 fire at once > { CONSTELLATION BURNED } > camera returns, night sky keeps the glowing dipper 15 s.
------------------------------------------------------------------------
SND.ping = "rbxasset://sounds/electronicpingshort.wav"

local DIPPER_RAW = {
	{ "DUBHE", 11.78, 5.75 }, { "MERAK", 12.05, 0.38 }, { "PHECDA", 4.78, -2.31 }, { "MEGREZ", 1.76, 1.03 },
	{ "ALIOTH", -3.63, -0.04 }, { "MIZAR", -7.81, -1.07 }, { "ALKAID", -11.11, -6.69 },
}
local DIPPER = {} -- centred star chart coordinates (degrees on the sky)
do
	local mx, my = 0, 0
	for _, d in ipairs(DIPPER_RAW) do mx += d[2]; my += d[3] end
	mx /= #DIPPER_RAW
	my /= #DIPPER_RAW
	for i, d in ipairs(DIPPER_RAW) do DIPPER[i] = { name = d[1], x = d[2] - mx, y = d[3] - my } end
end
local DIPPER_EDGES = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 }, { 4, 5 }, { 5, 6 }, { 6, 7 } }
local RING_WHITE = Color3.fromRGB(245, 240, 255)

local function purpleLayers()
	return {
		{ color = Color3.fromRGB(245, 228, 255), alpha = 0 },
		{ color = Color3.fromRGB(180, 90, 255),  alpha = 0.3 },
		{ color = Color3.fromRGB(120, 40, 230),  alpha = 0.75 },
	}
end
local function markerLayers()
	return {
		{ color = Color3.new(1, 1, 1),           alpha = 0 },
		{ color = Color3.fromRGB(205, 175, 255), alpha = 0.4 },
		{ color = Color3.fromRGB(150, 110, 255), alpha = 0.85 },
	}
end

local function easeOutBack(t)
	t = math.clamp(t, 0, 1)
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

-- night sky: black with stars, ground still visible
local function nightLighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 1.2
	Lighting.Ambient = Color3.fromRGB(58, 58, 96)
	Lighting.OutdoorAmbient = Color3.fromRGB(72, 74, 118)
	Lighting.FogEnd = 1e6
	Lighting.FogStart = 1e5
	Lighting.ExposureCompensation = 0
	if L0.atmo then
		local a = L0.atmo.inst
		a.Density = L0.atmo.Density * 0.25; a.Haze = 0; a.Glare = 0
	end
	local sky = L0.sky and L0.sky.inst
	if not sky then
		sky = Instance.new("Sky")
		sky.Parent = Lighting
		L0.createdSky = sky
	end
	for _, fc in ipairs(SKY_FACES) do sky[fc] = CONFIG.BLACK_TEXTURE end
	sky.StarCount = 6000
	sky.CelestialBodiesShown = false
	if L0.clouds then L0.clouds.inst.Enabled = false end
end

-- ---------------------------------------------------------------- star + ritual rings + ground marker
local function buildSevenStar(parent, st)
	local pos = st.spos
	local m = Instance.new("Model")
	m.Name = "Star_" .. st.name
	st.parts = {}
	local function add(shape, size, color, transp, cf)
		local p = part({ Shape = shape, Size = size, Color = color, Material = NEONM, Transparency = 1, CFrame = cf or CFrame.new(pos) }, m)
		st.parts[#st.parts + 1] = { p = p, base = transp }
		return p
	end
	local core = add(BALLS, V(12), Color3.new(1, 1, 1), 0)
	add(BALLS, V(40), Color3.fromRGB(200, 150, 255), 0.8)
	add(nil, Vector3.new(90, 1.2, 1.2), Color3.fromRGB(235, 215, 255), 0.1)
	add(nil, Vector3.new(1.2, 90, 1.2), Color3.fromRGB(235, 215, 255), 0.1)
	add(nil, Vector3.new(1.2, 1.2, 90), Color3.fromRGB(235, 215, 255), 0.1)
	add(nil, Vector3.new(56, 0.9, 0.9), RING_WHITE, 0.25, CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(45)))
	add(nil, Vector3.new(56, 0.9, 0.9), RING_WHITE, 0.25, CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(-45)))
	m.WorldPivot = CFrame.new(pos)
	m.Parent = parent
	m:ScaleTo(0.01)
	st.model = m
	local em = Instance.new("ParticleEmitter")
	em.Rate = 0
	em.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 120, 255))
	em.LightEmission = 1
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 0) })
	em.Lifetime = NumberRange.new(0.5, 1.0)
	em.Speed = NumberRange.new(14, 40)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Parent = core
	st.sparks = em

	-- white ritual circle: outer ring + runes, inner ring + hexagram (they spin in opposite directions)
	local ro, ri = Instance.new("Model"), Instance.new("Model")
	ro.Name, ri.Name = "RitualOuter", "RitualInner"
	st.ringParts = {}
	local function rp(model, cf, size)
		st.ringParts[#st.ringParts + 1] = part({ Size = size, Color = RING_WHITE, Material = NEONM, Transparency = 1, CFrame = CFrame.new(pos) * cf }, model)
	end
	local function band(model, R, width, segs)
		local arc = 2 * math.pi * R / segs * 1.08
		for i = 1, segs do
			local a = (i / segs) * math.pi * 2
			rp(model, CFrame.new(math.cos(a) * R, 0, math.sin(a) * R) * CFrame.Angles(0, -a, 0), Vector3.new(width, 0.5, arc))
		end
	end
	band(ro, 22, 1.4, 48)
	band(ri, 15.5, 0.8, 32)
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		rp(ro, CFrame.new(math.cos(a) * 18.5, 0, math.sin(a) * 18.5) * CFrame.Angles(0, -a, 0), Vector3.new(3.4, 0.5, 0.8))
	end
	for tri = 0, 1 do
		for j = 0, 2 do
			local a0 = math.rad(90 + tri * 60 + j * 120)
			local a1 = math.rad(90 + tri * 60 + (j + 1) * 120)
			local v0 = Vector3.new(math.cos(a0) * 15.5, 0, math.sin(a0) * 15.5)
			local v1 = Vector3.new(math.cos(a1) * 15.5, 0, math.sin(a1) * 15.5)
			local mid = (v0 + v1) / 2
			rp(ri, CFrame.lookAt(mid, mid + (v1 - v0)), Vector3.new(0.6, 0.4, (v1 - v0).Magnitude))
		end
	end
	for _, rm in ipairs({ ro, ri }) do
		rm.WorldPivot = CFrame.new(pos)
		rm.Parent = parent
		rm:ScaleTo(0.01)
	end
	st.ringO, st.ringI = ro, ri
end

-- spawn animation: star pops in, ritual circle opens up (runs on its own, ~0.55 s)
local function spawnSevenStar(st)
	task.spawn(function()
		if st.sparks then st.sparks:Emit(45) end
		local flash = part({ Shape = BALLS, Size = V(10), Position = st.spos, Color = Color3.new(1, 1, 1), Material = NEONM, Transparency = 0 }, st.model.Parent)
		TweenService:Create(flash, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V(90), Transparency = 1 }):Play()
		Debris:AddItem(flash, 1)
		runFor(0.55, function(a)
			local e = math.max(easeOutBack(a), 0.01)
			local alpha = math.clamp(a * 3, 0, 1)
			st.model:ScaleTo(e)
			if st.ringO and st.ringO.Parent then
				st.ringO:ScaleTo(e)
				st.ringI:ScaleTo(math.max(easeOutBack(math.clamp(a * 1.15 - 0.1, 0, 1)), 0.01))
				for _, p in ipairs(st.ringParts) do p.Transparency = 1 - alpha * 0.9 end
			end
			for _, e2 in ipairs(st.parts) do e2.p.Transparency = 1 - alpha * (1 - e2.base) end
		end)
	end)
end

local function buildMarker(parent, st)
	local g, n = st.gpos, st.gnorm
	st.core = part({ Shape = CYLS, Size = Vector3.new(0.2, 34, 34), CFrame = flatCF(g + n * 0.1, n), Color = Color3.fromRGB(190, 120, 255), Material = NEONM, Transparency = 0.15 }, parent)
	st.pulses = {}
	for i = 1, 3 do
		st.pulses[i] = part({ Shape = CYLS, Size = Vector3.new(0.15, 4, 4), CFrame = flatCF(g + n * (0.14 + i * 0.03), n), Color = Color3.fromRGB(235, 215, 255), Material = NEONM, Transparency = 1 }, parent)
	end
	st.marker = makeRig(parent, 1, markerLayers())
	st.fire = makeRig(parent, 1, purpleLayers())
end

-- one tick of everything a star does (rings spin, marker pulses, laser fires)
local function updateSevenStar(st, now)
	if st.ringO and st.ringO.Parent then
		local c = CFrame.new(st.spos)
		st.ringO:PivotTo(c * CFrame.Angles(0, now * 0.7, 0))
		st.ringI:PivotTo(c * CFrame.Angles(0, -now * 1.1, 0))
	end
	if st.moving and st.model then st.model:PivotTo(CFrame.new(st.spos)) end
	local s, g = st.spos, st.gpos
	local state = st.state
	local hideFn = function() return { 1, 1, 1 } end
	if state == "marker" then
		local rv = st.rv or 0
		if rv < 0.02 then
			updateRig(st.marker, g, g, hideFn)
		else
			local pl = 1 + 0.35 * math.sin(now * 8 + st.idx)
			updateRig(st.marker, g, s, function() return { 1.6 * pl * rv, 6 * pl * rv, 14 * pl * rv } end)
		end
		if st.core and st.core.Parent then
			local k = math.max(rv, 0.02)
			local d = 34 * (1 + 0.1 * math.sin(now * 9)) * k
			st.core.Size = Vector3.new(0.2, d, d)
			for i, p in ipairs(st.pulses) do
				local ph = (now * 0.9 + st.idx * 0.17 + i / 3) % 1
				local dd = (14 + 80 * ph) * k
				p.Size = Vector3.new(0.15, dd, dd)
				p.Transparency = 1 - rv * 0.75 * (1 - ph)
			end
		end
		return
	end
	-- fired: marker circle + thin marker laser are replaced by the purple laser
	if st.core and st.core.Parent then
		st.core.Transparency = 1
		for _, p in ipairs(st.pulses) do p.Transparency = 1 end
	end
	updateRig(st.marker, g, g, hideFn)
	if state == "firing" then
		local e = now - st.t0
		local head = math.clamp(e / 0.14, 0, 1)
		local th = 1 - math.clamp((e - 0.14) / 0.3, 0, 1)
		updateRig(st.fire, s, s:Lerp(g, head), function() return { 4 + 16 * th, 10 + 36 * th, 20 + 60 * th } end)
	elseif state == "finale" then
		local e = now - st.t0
		local k = 1 - smooth((e - 0.5) / 1.3)
		updateRig(st.fire, s, g, function() return { 3 + 31 * k, 8 + 82 * k, 16 + 154 * k } end)
	else -- "done": lasers gone, the stars just twinkle
		updateRig(st.fire, g, g, hideFn)
		if st.parts and st.parts[2] then st.parts[2].p.Transparency = 0.74 + 0.1 * math.sin(now * 3 + st.idx) end
	end
end

-- ---------------------------------------------------------------- hole where a laser lands
local function strikeHole(st, gfold, T, UPV)
	local g, n = st.gpos, st.gnorm
	local R0 = 45
	st.rim = part({ Shape = CYLS, Size = Vector3.new(0.1, R0 * 2.3, R0 * 2.3), CFrame = flatCF(g + n * 0.15, n), Color = Color3.fromRGB(180, 90, 255), Material = NEONM, Transparency = 0.2 }, gfold)
	st.pit = part({ Shape = CYLS, Size = Vector3.new(0.1, R0 * 2, R0 * 2), CFrame = flatCF(g + n * 0.3, n), Color = Color3.fromRGB(8, 0, 14) }, gfold)
	st.pitGlow = part({ Shape = CYLS, Size = Vector3.new(0.1, R0 * 0.7, R0 * 0.7), CFrame = flatCF(g + n * 0.45, n), Color = Color3.fromRGB(235, 210, 255), Material = NEONM, Transparency = 0.1 }, gfold)
	if CONFIG.CARVE_LAND then
		pcall(function() workspace.Terrain:FillBall(g, 38, Enum.Material.Air) end)
		local er = makeEraser(g, 20, 52, UPV)
		er(-1)
	end
	local bp = part({ Size = Vector3.new(10, 1, 10), Position = g + n * 1, Transparency = 1 }, gfold)
	local em = Instance.new("ParticleEmitter")
	em.Rate = 0
	em.Color = ColorSequence.new(Color3.fromRGB(245, 225, 255), Color3.fromRGB(150, 60, 255))
	em.LightEmission = 1
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
	em.Lifetime = NumberRange.new(0.8, 1.8)
	em.Speed = NumberRange.new(40, 140)
	em.SpreadAngle = Vector2.new(55, 55)
	em.Acceleration = Vector3.new(0, -60, 0)
	em.EmissionDirection = Enum.NormalId.Top
	em.Parent = bp
	em:Emit(70)
	Debris:AddItem(bp, 4)
	local fl = part({ Shape = CYLS, Size = Vector3.new(0.3, 6, 6), CFrame = flatCF(g + n * 0.6, n), Color = Color3.fromRGB(240, 225, 255), Material = NEONM, Transparency = 0.1 }, gfold)
	TweenService:Create(fl, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.3, 190, 190), Transparency = 1 }):Play()
	Debris:AddItem(fl, 1)
end

-- ---------------------------------------------------------------- glowing dipper lines on the ground
local function buildLines(gfold, stars, T, rp)
	local segs = {}
	local H = CONFIG.STAR_HEIGHT
	for _, e in ipairs(DIPPER_EDGES) do
		local a, b = stars[e[1]].gpos, stars[e[2]].gpos
		local dist = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
		local n = math.max(2, math.ceil(dist / 14))
		local pts, prevY = {}, a.Y
		for j = 0, n do
			local t = j / n
			local x, z = a.X + (b.X - a.X) * t, a.Z + (b.Z - a.Z) * t
			local hit = workspace:Raycast(Vector3.new(x, T.Y + H, z), Vector3.new(0, -(H + 900), 0), rp)
			local y = hit and hit.Position.Y or prevY
			prevY = y
			pts[j + 1] = Vector3.new(x, y, z)
		end
		for j = 1, n do
			local p0, p1 = pts[j], pts[j + 1]
			local m = (p0 + p1) / 2 + Vector3.new(0, 0.35, 0)
			local dir = p1 - p0
			local len = dir.Magnitude + 1.4
			local cf = CFrame.lookAt(m, m + dir)
			local dark = part({ Size = Vector3.new(22, 0.5, len), CFrame = cf, Color = Color3.fromRGB(8, 0, 14), Transparency = 1 }, gfold)
			local glow = part({ Size = Vector3.new(9, 0.6, len), CFrame = cf * CFrame.new(0, 0.12, 0), Color = Color3.fromRGB(190, 100, 255), Material = NEONM, Transparency = 1 }, gfold)
			segs[#segs + 1] = { dark = dark, glow = glow }
		end
	end
	return segs
end

-- ---------------------------------------------------------------- THE SS-04 SEQUENCE
local function runSS04()
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
	local rootPos = root.Position
	local rfold = S.realFolder

	local ok, err = pcall(function()
		sfx(SND.click, 1.2, 1, 3)
		if env.__StellarSevenGround then pcall(function() env.__StellarSevenGround:Destroy() end) end
		local gfold = Instance.new("Folder")
		gfold.Name = "StellarSevenGround"
		gfold.Parent = workspace
		env.__StellarSevenGround = gfold

		-- ---------- aim: centre of the screen ----------
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char }
		local vs = cam.ViewportSize
		local ray = cam:ViewportPointToRay(vs.X / 2, vs.Y / 2)
		local res = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
		local T
		if res then
			T = res.Position
		else
			local p = ray.Origin + ray.Direction * 150
			local down = workspace:Raycast(p + Vector3.new(0, 200, 0), Vector3.new(0, -800, 0), params)
			T = down and down.Position or p
		end

		-- dipper orientation: "up" on the chart points away from you
		local f = Vector3.new(T.X - rootPos.X, 0, T.Z - rootPos.Z)
		if f.Magnitude < 5 then
			local lv = cam.CFrame.LookVector
			f = Vector3.new(lv.X, 0, lv.Z)
		end
		if f.Magnitude < 0.1 then f = Vector3.new(0, 0, -1) end
		f = f.Unit
		local right = f:Cross(UP)

		-- ---------- the 7 stars: where they land, where they hang ----------
		local K, H = CONFIG.DIPPER_SCALE, CONFIG.STAR_HEIGHT
		local stars = {}
		for i, d in ipairs(DIPPER) do
			local x = T.X + right.X * d.x * K + f.X * d.y * K
			local z = T.Z + right.Z * d.x * K + f.Z * d.y * K
			local hit = workspace:Raycast(Vector3.new(x, T.Y + H, z), Vector3.new(0, -(H + 900), 0), params)
			local gn = hit and hit.Normal or UP
			if gn.Y < 0.3 then gn = UP end
			stars[i] = {
				idx = i, name = d.name, state = "marker", rv = 0,
				gpos = hit and hit.Position or Vector3.new(x, T.Y, z), gnorm = gn,
				spos = Vector3.new(x, T.Y + H, z),
			}
		end
		local Cs = Vector3.new(T.X, T.Y + H, T.Z)
		local Gc = Vector3.new(0, 0, 0)
		for _, st in ipairs(stars) do Gc += st.gpos end
		Gc /= #stars
		local W = Cs - f * (H * 1.27) + Vector3.new(0, H * 0.47, 0)          -- wide shot of the dipper in the sky
		local Clook = Cs - Vector3.new(0, H * 0.25, 0)
		local W2 = Gc - f * 1100 + Vector3.new(0, 900, 0)         -- high shot of the ground dipper
		local Mid = Gc + (Cs - Gc) * 0.3

		-- ---------- little helpers ----------
		local shakeAmp = 0
		local function camSet(cf, fov)
			if not useCut then return end
			cam.CFrame = cf * shakeRot(shakeAmp)
			cam.FieldOfView = fov
			shakeAmp = shakeAmp * 0.9
		end
		local function blur(v) if fx then fx.blur.Size = v end end
		local mid = Instance.new("TextLabel")
		mid.BackgroundTransparency = 1
		mid.Font = Enum.Font.Code
		mid.TextSize = 54
		mid.TextColor3 = Color3.fromRGB(232, 205, 255)
		mid.TextStrokeColor3 = Color3.fromRGB(80, 20, 140)
		mid.TextStrokeTransparency = 1
		mid.TextTransparency = 1
		mid.AnchorPoint = Vector2.new(0.5, 0.5)
		mid.Position = UDim2.new(0.5, 0, 0.5, 0)
		mid.Size = UDim2.new(0.9, 0, 0, 60)
		mid.ZIndex = 9
		mid.Parent = hud.gui
		local function say(text)
			mid.Text = text
			mid.TextTransparency = 0
			mid.TextStrokeTransparency = 0.5
			TweenService:Create(mid, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.12), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
		local function enterNight()
			nightLighting()
			S.lightingActive = true
		end

		-- ---------- setup ----------
		saveLighting()
		hud.flash.BackgroundColor3 = Color3.new(0, 0, 0)
		if useCut then
			setControls(false)
			hum.WalkSpeed = 0; hum.JumpPower = 0; hum.JumpHeight = 0
			cam.CameraType = Enum.CameraType.Scriptable
			hud.bars(true)
		end
		hud.setLabel("SS-04  ·  THE SHOOTING STAR")
		hud.setSub("SEVEN STARS")

		for _, st in ipairs(stars) do buildMarker(rfold, st) end
		local built = false
		task.spawn(function()
			for _, st in ipairs(stars) do
				local okb, e2 = pcall(buildSevenStar, rfold, st)
				if not okb then warn("[StellarRemote] star build failed: " .. tostring(e2)) end
				task.wait()
			end
			built = true
		end)
		S.live[#S.live + 1] = RunService.RenderStepped:Connect(function()
			local now = os.clock()
			for _, st in ipairs(stars) do updateSevenStar(st, now) end
		end)

		-- ---------- 7 lasers appear on the map, camera goes up the sky, the sky turns black ----------
		sfx(SND.launch, 1.4, 0.8, 6)
		local startCF = cam.CFrame
		runFor(TS(1.5), function(a, dt, e)
			if useCut then
				local k = smooth(a)
				local pos = startCF.Position:Lerp(W, k) + Vector3.new(0, 220 * math.sin(math.pi * k), 0)
				local look = (startCF * CFrame.new(0, 0, -300)).Position:Lerp(Cs - Vector3.new(0, 200, 0), k)
				cam.CFrame = CFrame.lookAt(pos, look)
				cam.FieldOfView = 70 + 12 * math.sin(math.pi * k)
				blur(10 * math.sin(math.pi * k))
			end
			for i, st in ipairs(stars) do st.rv = math.clamp((e - (i - 1) * 0.05) / 0.25, 0, 1) end
			if a > 0.78 then hud.flash.BackgroundTransparency = 1 - smooth((a - 0.78) / 0.22) end
		end)
		hud.flash.BackgroundTransparency = 0
		for _, st in ipairs(stars) do st.rv = 1 end
		enterNight()
		while not built do RunService.RenderStepped:Wait() end
		blur(0)

		-- ---------- camera hops star to star (0.2 s each); every star forms a white ritual ring ----------
		for i, st in ipairs(stars) do
			spawnSevenStar(st)
			sfx(SND.ping, 1.4, 0.8 + 0.1 * i, 2)
			hud.setSub(("RITUAL  %d / 7   ·   %s"):format(i, st.name))
			runFor(CONFIG.HOP_TIME, function(a, dt, e)
				local base = st.spos - f * 62 + Vector3.new(0, 36, 0)
				local pos = base:Lerp(st.spos - f * 50 + Vector3.new(0, 32, 0), a)
				camSet(CFrame.lookAt(pos, st.spos), 62)
				if i == 1 then hud.flash.BackgroundTransparency = smooth(e / 0.15) end
			end)
		end

		-- ---------- lock onto the dipper ----------
		hud.setLabel("")
		hud.setSub("")
		local lastCF = cam.CFrame
		runFor(TS(0.6), function(a)
			local k = smooth(a)
			camSet(CFrame.lookAt(lastCF.Position:Lerp(W, k), (lastCF * CFrame.new(0, 0, -300)).Position:Lerp(Clook, k)), 70 - 4 * a)
		end)

		-- ---------- the stars fire purple lasers one by one; each hit shows the star's name ----------
		local gap = TS(0.5)
		runFor(gap * 7 + 0.45, function(a, dt, e)
			for i, st in ipairs(stars) do
				if not st.fireStarted and e >= (i - 1) * gap then
					st.fireStarted = true
					st.state = "firing"
					st.t0 = os.clock()
					sfx(SND.shot, 1.6, 0.9 + 0.08 * i, 3)
				end
				if st.fireStarted and not st.hit and os.clock() - st.t0 >= 0.14 then
					st.hit = true
					strikeHole(st, gfold, T, UP)
					say(st.name)
					sfx(SND.boom, 1.3, 1.1 + 0.05 * i, 4)
					shakeAmp = 0.012
				end
			end
			local k = smooth(a)
			camSet(CFrame.lookAt(W:Lerp(W + f * 70 + Vector3.new(0, -25, 0), k), Clook), 66)
		end)

		-- ---------- the holes link into a dipper on the ground ----------
		hud.setSub("LINKING THE CONSTELLATION")
		local segs = buildLines(gfold, stars, T, params)
		sfx(SND.whoosh, 1.2, 1.2, 4)
		local fromCF = cam.CFrame
		runFor(TS(1.1), function(a)
			local k = smooth(a)
			camSet(CFrame.lookAt(fromCF.Position:Lerp(W2, k), (fromCF * CFrame.new(0, 0, -600)).Position:Lerp(Mid, k)), 66 + 4 * k)
			local count = math.floor(a * #segs * 1.05)
			for i = 1, math.min(count, #segs) do
				segs[i].dark.Transparency = 0.1
				segs[i].glow.Transparency = 0.05
			end
		end)
		for _, sg in ipairs(segs) do sg.dark.Transparency = 0.1; sg.glow.Transparency = 0.05 end
		hud.setSub("")

		-- ---------- ALL 7 FIRE AT ONCE ----------
		local now0 = os.clock()
		for _, st in ipairs(stars) do
			st.state = "finale"
			st.t0 = now0
			if CONFIG.CARVE_LAND then
				pcall(function() workspace.Terrain:FillBall(st.gpos, 85, Enum.Material.Air) end)
				local er = makeEraser(st.gpos, 32, 105, UP)
				er(-1)
			end
			for _, p in ipairs({ st.rim, st.pit, st.pitGlow }) do
				local sz = p.Size
				local ratio = 2
				TweenService:Create(p, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.1, sz.Y * ratio, sz.Z * ratio) }):Play()
			end
			st.sparks:Emit(60)
		end
		sfx(SND.boom, 3, 0.5, 10)
		sfx(SND.shot, 3, 0.4, 10)
		hud.flash.BackgroundColor3 = Color3.fromRGB(240, 225, 255)
		hud.flash.BackgroundTransparency = 0.2
		TweenService:Create(hud.flash, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
		shakeAmp = 0.035
		local textShown = false
		runFor(TS(1.7), function(a, dt, e)
			camSet(CFrame.lookAt(W2, Mid), 70 + 10 * math.sin(math.min(a * 3, 1) * math.pi * 0.5))
			blur(10 * (1 - a))
			local flare = 1 - smooth((e - 0.2) / 1.1)
			for _, sg in ipairs(segs) do
				sg.glow.Color = Color3.fromRGB(190, 100, 255):Lerp(Color3.new(1, 1, 1), flare)
			end
			if a > 0.25 and not textShown then
				textShown = true
				hud.title.TextSize = 40
				hud.title.TextColor3 = Color3.fromRGB(235, 210, 255)
				hud.setLabel("{ CONSTELLATION BURNED }")
			end
			if a > 0.88 then
				hud.flash.BackgroundColor3 = Color3.fromRGB(240, 225, 255)
				hud.flash.BackgroundTransparency = 1 - smooth((a - 0.88) / 0.12)
			end
		end)
		hud.flash.BackgroundTransparency = 0

		-- ritual circles + ground markers are gone, lasers off, stars stay
		for _, st in ipairs(stars) do
			st.state = "done"
			if st.ringO then st.ringO:Destroy(); st.ringI:Destroy(); st.ringO, st.ringI = nil, nil end
			if st.core then st.core:Destroy(); for _, p in ipairs(st.pulses) do p:Destroy() end; st.core = nil end
		end

		-- the holes and lines stay on the ground for a while, pulsing, then fade out
		task.spawn(function()
			local t0 = os.clock()
			while gfold.Parent and os.clock() - t0 < CONFIG.LINES_STAY do
				local k = 0.5 + 0.5 * math.sin((os.clock() - t0) * 3)
				for _, sg in ipairs(segs) do sg.glow.Color = Color3.fromRGB(150, 70, 235):Lerp(Color3.fromRGB(215, 150, 255), k) end
				task.wait(0.1)
			end
			local t1 = os.clock()
			while gfold.Parent and os.clock() - t1 < 3 do
				local x = (os.clock() - t1) / 3
				for _, sg in ipairs(segs) do
					sg.dark.Transparency = 0.1 + 0.9 * x
					sg.glow.Transparency = 0.05 + 0.95 * x
				end
				task.wait(0.1)
			end
			if gfold.Parent then gfold:Destroy() end
		end)

		-- ---------- camera back to normal; the night sky keeps the glowing dipper ----------
		S.restorePlayer()
		S.resetFx()
		hud.bars(false)
		TweenService:Create(hud.flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		hud.setSub("")
		task.delay(2.6, function() hud.setLabel("") end)

		-- the 7 stars glide into a Big Dipper hanging in the sky ahead of you
		local Cb = Vector3.new(rootPos.X, rootPos.Y, rootPos.Z) + f * 1300 + Vector3.new(0, 750, 0)
		for i, st in ipairs(stars) do
			st.sposStart = st.spos
			st.bpos = Cb + right * (DIPPER[i].x * 40) + UP * (DIPPER[i].y * 40)
			st.moving = true
		end
		local skyLines = {}
		for _, e in ipairs(DIPPER_EDGES) do
			skyLines[#skyLines + 1] = { e[1], e[2], part({ Size = Vector3.new(3, 3, 10), Color = Color3.fromRGB(215, 190, 255), Material = NEONM, Transparency = 1 }, rfold) }
		end
		local function placeSkyLines(tr)
			for _, l in ipairs(skyLines) do
				local a, b = stars[l[1]].spos, stars[l[2]].spos
				l[3].Size = Vector3.new(3, 3, math.max((b - a).Magnitude - 70, 1))
				l[3].CFrame = CFrame.lookAt((a + b) / 2, b)
				l[3].Transparency = tr
			end
		end
		runFor(1.2, function(a)
			local k = smooth(a)
			for _, st in ipairs(stars) do st.spos = st.sposStart:Lerp(st.bpos, k); st.model:ScaleTo(1 + 1.5 * k) end
			placeSkyLines(1 - 0.65 * k)
		end)
		for _, st in ipairs(stars) do st.moving = false end

		task.wait(CONFIG.SKY_STAY)

		-- ---------- the dipper disappears, the sky returns ----------
		runFor(1.5, function(a)
			for _, st in ipairs(stars) do st.model:ScaleTo(math.max(2.5 * (1 - a), 0.01)) end
			placeSkyLines(0.35 + 0.65 * a)
		end)
		hud.flash.BackgroundColor3 = Color3.new(0, 0, 0)
		hud.flash.BackgroundTransparency = 1
		TweenService:Create(hud.flash, TweenInfo.new(0.25), { BackgroundTransparency = 0 }):Play()
		task.wait(0.3)
		S.leaveSpace()
		TweenService:Create(hud.flash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		task.wait(0.45)
	end)

	if not ok then warn("[StellarRemote] " .. tostring(err)) end
	S.restoreAll()
	busy = false
end

------------------------------------------------------------------------
-- SS-05 · TESSERACT
-- huge rainbow square target (5x5 grid) > rewind Earth > solar system > space grid down to the Milky Way,
-- the rainbow 4D tesseract above it > it drops into the Milky Way and teleports to the Earth model >
-- back in the game a map-sized tesseract turns rainbow, stops spinning and crashes > ASCENSION x5 >
-- FOLDED (half the map flips upside down, +200 studs) > the tesseract becomes a rainbow stone.
------------------------------------------------------------------------
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 40, 40)),
	ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 160, 30)),
	ColorSequenceKeypoint.new(0.34, Color3.fromRGB(255, 240, 40)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 255, 90)),
	ColorSequenceKeypoint.new(0.67, Color3.fromRGB(40, 200, 255)),
	ColorSequenceKeypoint.new(0.84, Color3.fromRGB(120, 80, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 200)),
})
local TECH = Color3.fromRGB(120, 210, 255)

local function lookCF(pos, dir)
	local u = dir.Unit
	local up = (math.abs(u.Y) > 0.98) and Vector3.new(1, 0, 0) or UP
	return CFrame.lookAt(pos, pos + u, up)
end

-- ---------------------------------------------------------------- the 4D tesseract (wireframe)
local TxV, TxE = {}, {}
for i = 0, 15 do
	TxV[i + 1] = {
		(bit32.band(i, 1) == 0) and -1 or 1,
		(bit32.band(i, 2) == 0) and -1 or 1,
		(bit32.band(i, 4) == 0) and -1 or 1,
		(bit32.band(i, 8) == 0) and -1 or 1,
	}
end
for i = 0, 15 do
	for b = 0, 3 do
		local j = bit32.bxor(i, bit32.lshift(1, b))
		if j > i then TxE[#TxE + 1] = { i + 1, j + 1 } end
	end
end
local function wrapA(a) return a - 2 * math.pi * math.floor(a / (2 * math.pi) + 0.5) end
local function rot4(v, axw, ayw, azw, axy)
	local x, y, z, w = v[1], v[2], v[3], v[4]
	local c, s = math.cos(axw), math.sin(axw)
	x, w = x * c - w * s, x * s + w * c
	c, s = math.cos(ayw), math.sin(ayw)
	y, w = y * c - w * s, y * s + w * c
	c, s = math.cos(azw), math.sin(azw)
	z, w = z * c - w * s, z * s + w * c
	c, s = math.cos(axy), math.sin(axy)
	x, y = x * c - y * s, x * s + y * c
	return x, y, z, w
end

local function makeTess(parent)
	local folder = Instance.new("Folder")
	folder.Name = "Tesseract"
	local o = { folder = folder, parent = parent, edges = {}, nodes = {}, pts = {}, ws = {}, tt = 0 }
	for e = 1, #TxE do
		o.edges[e] = {
			outer = part({ Size = Vector3.new(1, 1, 1), Material = NEONM, Color = TECH }, folder),
			inner = part({ Size = Vector3.new(1, 1, 1), Material = NEONM, Color = Color3.new(1, 1, 1) }, folder),
		}
	end
	for i = 1, 16 do o.nodes[i] = part({ Size = Vector3.new(1, 1, 1), Material = NEONM, Color = Color3.new(1, 1, 1) }, folder) end
	o.core = part({ Size = Vector3.new(1, 1, 1), Material = NEONM, Color = Color3.new(1, 1, 1), Transparency = 0.2 }, folder)
	return o
end

-- spin: 0..1 speed, rainbow: 0 = tech cyan .. 1 = full rainbow, settle: 0..1 eases the 4D rotation to the classic cube-in-cube
local function updateTess(o, center, size, thick, dt, spin, rainbow, now, flash, settle)
	o.tt += dt * spin
	local t = o.tt
	local k0 = 1 - (settle or 0)
	local a1, a2, a3, a4 = wrapA(t * 0.7) * k0, wrapA(t * 0.45) * k0, wrapA(t * 0.31) * k0, wrapA(t * 0.18) * k0
	local u = size / 3
	local pts, ws = o.pts, o.ws
	for i = 1, 16 do
		local x, y, z, w = rot4(TxV[i], a1, a2, a3, a4)
		pts[i] = center + Vector3.new(x, y, z) * ((4.4 / (4.4 - w)) * u)
		ws[i] = w
	end
	local fl = math.min(flash, 1)
	local th = thick * (1 + 0.6 * flash)
	for e, ed in ipairs(TxE) do
		local a, b = pts[ed[1]], pts[ed[2]]
		local dir = b - a
		local len = math.min(dir.Magnitude, 2040)
		local cf = lookCF((a + b) / 2, dir)
		local rc = Color3.fromHSV((e / #TxE + now * 0.2 + (ws[ed[1]] + ws[ed[2]]) * 0.07) % 1, 0.9, 1)
		local col = TECH:Lerp(rc, rainbow):Lerp(Color3.new(1, 1, 1), fl * 0.7)
		local ed2 = o.edges[e]
		ed2.outer.Size = Vector3.new(th, th, len)
		ed2.outer.CFrame = cf
		ed2.outer.Color = col
		ed2.inner.Size = Vector3.new(th * 0.35, th * 0.35, len + 1)
		ed2.inner.CFrame = cf
	end
	local ns = th * 2.6
	for i = 1, 16 do
		local n = o.nodes[i]
		n.Size = Vector3.new(ns, ns, ns)
		n.CFrame = CFrame.new(pts[i]) * CFrame.Angles(t * 0.5, t * 0.8, 0)
		n.Color = Color3.new(1, 1, 1):Lerp(Color3.fromHSV((i / 16 + now * 0.2) % 1, 0.9, 1), rainbow * 0.8)
	end
	local cs = size * 0.14
	o.core.Size = Vector3.new(cs, cs, cs)
	o.core.CFrame = CFrame.new(center) * CFrame.Angles(t, t * 0.7, t * 1.3)
	o.core.Color = Color3.fromHSV((now * 0.3) % 1, 0.1 + 0.6 * rainbow, 1)
	if not o.folder.Parent then o.folder.Parent = o.parent end
end

-- ---------------------------------------------------------------- huge rainbow square target (5 x 5 grid)
local function buildTarget(parent, T, f, params, size)
	local right = f:Cross(UP)
	local half, step = size / 2, size / 5
	local segs, cells, corners = {}, {}, {}
	local function gpos(a, b)
		local x = T.X + right.X * a + f.X * b
		local z = T.Z + right.Z * a + f.Z * b
		local hit = workspace:Raycast(Vector3.new(x, T.Y + 400, z), Vector3.new(0, -900, 0), params)
		return Vector3.new(x, hit and hit.Position.Y or T.Y, z)
	end
	local function line(a0, b0, a1, b1, width)
		local dist = math.sqrt((a1 - a0) ^ 2 + (b1 - b0) ^ 2)
		local n = math.max(2, math.ceil(dist / 14))
		local prev = gpos(a0, b0)
		for j = 1, n do
			local t = j / n
			local a, b = a0 + (a1 - a0) * t, b0 + (b1 - b0) * t
			local p1 = gpos(a, b)
			local m = (prev + p1) / 2 + Vector3.new(0, 0.5, 0)
			local d = p1 - prev
			local seg = part({ Size = Vector3.new(width, 0.7, d.Magnitude + 1.4), CFrame = CFrame.lookAt(m, m + d), Material = NEONM, Color = Color3.new(1, 1, 1) }, parent)
			segs[#segs + 1] = { p = seg, u = ((a + b) / size) * 0.5 + 0.5 }
			prev = p1
		end
	end
	for i = 0, 5 do -- 6 + 6 lines = a 5 x 5 grid
		local c = -half + i * step
		local w = (i == 0 or i == 5) and 9 or 3.2
		line(c, -half, c, half, w)
		line(-half, c, half, c, w)
	end
	for ix = 0, 4 do
		for iy = 0, 4 do
			local a, b = -half + (ix + 0.5) * step, -half + (iy + 0.5) * step
			local gp = gpos(a, b)
			local p = part({ Size = Vector3.new(step - 8, 0.4, step - 8), CFrame = CFrame.fromMatrix(gp + Vector3.new(0, 0.35, 0), right, UP, -f), Material = NEONM, Color = Color3.new(1, 1, 1), Transparency = 0.8 }, parent)
			cells[#cells + 1] = { p = p, u = ((a + b) / size) * 0.5 + 0.5 }
		end
	end
	for _, sa in ipairs({ -1, 1 }) do
		for _, sb in ipairs({ -1, 1 }) do
			local gp = gpos(sa * half, sb * half)
			corners[#corners + 1] = part({ Size = Vector3.new(8, 1500, 8), Position = gp + Vector3.new(0, 750, 0), Material = NEONM, Color = Color3.new(1, 1, 1), Transparency = 0.15 }, parent)
		end
	end
	local obj = {}
	function obj.update(now, speed)
		local t = now * speed
		for _, s in ipairs(segs) do s.p.Color = Color3.fromHSV((s.u + t) % 1, 0.9, 1) end
		for _, c in ipairs(cells) do
			c.p.Color = Color3.fromHSV((c.u + t) % 1, 0.85, 1)
			c.p.Transparency = 0.78 + 0.12 * math.sin(now * 3 + c.u * 8)
		end
		for i, c in ipairs(corners) do c.Color = Color3.fromHSV((i / 4 + t) % 1, 0.9, 1) end
	end
	function obj.destroy()
		for _, s in ipairs(segs) do s.p:Destroy() end
		for _, c in ipairs(cells) do c.p:Destroy() end
		for _, c in ipairs(corners) do c:Destroy() end
		segs, cells, corners = {}, {}, {}
	end
	return obj
end

-- ---------------------------------------------------------------- wormhole / portal
local function buildPortal(parent, center, normal, radius)
	local base = poseCF(center, normal) -- ring plane = local XY, local -Z = normal
	local P = { rings = {} }
	local function ring(R, width, segs, speed, hue0)
		local m = Instance.new("Model")
		local arcs = {}
		for i = 1, segs do
			local a = (i / segs) * math.pi * 2
			arcs[i] = part({
				Size = Vector3.new(width, 2 * math.pi * R / segs * 1.12, radius * 0.05),
				CFrame = base * CFrame.new(math.cos(a) * R, math.sin(a) * R, 0) * CFrame.Angles(0, 0, a),
				Material = NEONM, Color = Color3.fromHSV((hue0 + i / segs) % 1, 0.9, 1), Transparency = 1,
			}, m)
		end
		m.WorldPivot = base
		m.Parent = parent
		m:ScaleTo(0.01)
		P.rings[#P.rings + 1] = { m = m, speed = speed, arcs = arcs, hue0 = hue0 }
	end
	ring(radius, radius * 0.07, 56, 1.2, 0)
	ring(radius * 0.76, radius * 0.06, 44, -1.7, 0.33)
	ring(radius * 0.54, radius * 0.05, 32, 2.4, 0.66)
	P.core = part({ Shape = CYLS, Size = Vector3.new(radius * 0.05, 1, 1), CFrame = base * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(10, 0, 30), Material = NEONM, Transparency = 1 }, parent)
	function P.update(now, k) -- k: 0 closed .. 1 open
		for _, r in ipairs(P.rings) do
			r.m:ScaleTo(math.max(k, 0.01))
			r.m:PivotTo(base * CFrame.Angles(0, 0, now * r.speed))
			local n = #r.arcs
			for i, p in ipairs(r.arcs) do
				p.Color = Color3.fromHSV((r.hue0 + i / n + now * 0.3) % 1, 0.9, 1)
				p.Transparency = 1 - 0.9 * k
			end
		end
		local d = math.max(radius * 0.9 * k, 0.1)
		P.core.Size = Vector3.new(radius * 0.05, d, d)
		P.core.Transparency = 1 - 0.85 * k
	end
	function P.destroy()
		for _, r in ipairs(P.rings) do r.m:Destroy() end
		P.core:Destroy()
	end
	return P
end

-- ---------------------------------------------------------------- the cosmic stage
local XS      = Vector3.new(0, 40000, 0)                -- Earth top
local XSUN    = XS + Vector3.new(-3000, 5200, 1800)
local XGAL    = XS + Vector3.new(0, -12000, 2000)
local XPC     = XS + Vector3.new(0, 17500, 2000)        -- centre of the space grid
local XTC     = XPC + Vector3.new(0, 520, 0)            -- where the tesseract rests on the grid
local XCT2    = XS + Vector3.new(0, 24000, -13000)      -- camera: tesseract above, solar system below
local XMID    = XS + Vector3.new(-1500, 11610, 1900)
local XCAM_F  = XS + Vector3.new(0, -1500, -9000)       -- camera while the tesseract falls into the galaxy
local XSHOT_E = { c = XS + Vector3.new(0, -250, 0), dir = Vector3.new(-0.7, 0.5, -0.5).Unit, d0 = 1500, d1 = 8000 }
local XSHOT_S = { c = XSUN, dir = Vector3.new(0.15, 0.6, -0.78).Unit, d0 = 6500, d1 = 15000 }
local function xPos(sh, a) return sh.c + sh.dir * (sh.d0 * (sh.d1 / sh.d0) ^ (a ^ 1.35)) end

local function buildTessStage()
	local Q = CONFIG.QUALITY
	local folder = Instance.new("Folder")
	folder.Name = "StellarTessStage"
	folder.Parent = workspace
	local made = 0
	local function P(props, parent)
		made += 1
		if made % 140 == 0 then task.wait() end
		return part(props, parent or folder)
	end
	local rng = Random.new(77)
	local function ringBand(cf, rIn, rOut, segs, thick, color, transp, mat)
		segs = math.max(24, math.floor(segs * Q))
		local mid, width = (rIn + rOut) / 2, rOut - rIn
		local arc = (2 * math.pi * mid / segs) * 1.06
		for i = 1, segs do
			local a = (i / segs) * math.pi * 2
			P({ Size = Vector3.new(width, thick, arc), CFrame = cf * CFrame.new(math.cos(a) * mid, 0, math.sin(a) * mid) * CFrame.Angles(0, -a, 0), Color = color, Transparency = transp, Material = mat or Enum.Material.SmoothPlastic })
		end
	end

	-- Earth
	do
		local c = XS + Vector3.new(0, -1000, 0)
		P({ Shape = BALLS, Size = V(2000), Position = c, Color = Color3.fromRGB(10, 45, 115), Reflectance = 0.08 })
		local lands = { Color3.fromRGB(46, 110, 52), Color3.fromRGB(70, 128, 58), Color3.fromRGB(104, 134, 70), Color3.fromRGB(160, 138, 84) }
		for _ = 1, 8 do
			local cen, spread = randUnit(rng), rng:NextNumber(0.12, 0.26)
			for _ = 1, math.max(6, math.floor(14 * Q)) do
				local d = (cen + randUnit(rng) * spread).Unit
				local diam = rng:NextNumber(70, 190)
				P({ Shape = CYLS, Size = Vector3.new(7, diam, diam), CFrame = flatCF(c + d * 999.2, d), Color = lands[rng:NextInteger(1, #lands)] })
			end
		end
		P({ Shape = BALLS, Size = V(2044), Position = c, Color = Color3.fromRGB(90, 160, 255), Material = NEONM, Transparency = 0.9 })
	end

	-- solar system
	do
		P({ Shape = BALLS, Size = V(520), Position = XSUN, Color = Color3.fromRGB(255, 205, 90), Material = NEONM })
		P({ Shape = BALLS, Size = V(900), Position = XSUN, Color = Color3.fromRGB(255, 150, 40), Material = NEONM, Transparency = 0.85 })
		local planets = {
			{ 450, 38, Color3.fromRGB(150, 150, 150) }, { 780, 58, Color3.fromRGB(230, 200, 140) },
			{ 1100, 62, Color3.fromRGB(60, 120, 220) }, { 1450, 48, Color3.fromRGB(200, 90, 60) },
			{ 1950, 150, Color3.fromRGB(210, 170, 130) }, { 2350, 130, Color3.fromRGB(232, 212, 162) },
			{ 2700, 90, Color3.fromRGB(150, 220, 230) }, { 3050, 88, Color3.fromRGB(70, 100, 230) },
		}
		local pr = Random.new(5)
		for _, pl in ipairs(planets) do
			ringBand(CFrame.new(XSUN), pl[1] - 10, pl[1] + 10, math.floor(pl[1] / 20), 4, Color3.fromRGB(110, 150, 210), 0.3, NEONM)
			local a = pr:NextNumber(0, math.pi * 2)
			P({ Shape = BALLS, Size = V(pl[2] * 2), Position = XSUN + Vector3.new(math.cos(a) * pl[1], 0, math.sin(a) * pl[1]), Color = pl[3] })
		end
	end

	-- Milky Way (far below)
	do
		local R = 9000
		for _ = 1, math.floor(1100 * Q) do
			local t = rng:NextNumber() ^ 0.65
			local rr = t * R
			local arm = rng:NextInteger(0, 3)
			local ang = arm * (math.pi / 2) + t * math.pi * 3.4 + rng:NextNumber(-1, 1) * (0.16 + 0.32 * (1 - t))
			local y = rng:NextNumber(-1, 1) * (30 + 360 * (1 - t) ^ 2)
			local col = Color3.fromRGB(255, 225, 170):Lerp(Color3.fromRGB(150, 185, 255), math.clamp(t * 1.2, 0, 1))
			if rng:NextNumber() < 0.06 then col = Color3.fromRGB(255, 140, 200) end
			P({ Shape = BALLS, Size = V(rng:NextNumber(70, 230) * (1 - 0.4 * t)), Position = XGAL + Vector3.new(math.cos(ang) * rr, y, math.sin(ang) * rr), Color = col, Material = NEONM, Transparency = rng:NextNumber(0, 0.3) })
		end
		P({ Shape = BALLS, Size = V(1800), Position = XGAL, Color = Color3.fromRGB(255, 230, 170), Material = NEONM, Transparency = 0.55 })
		P({ Shape = BALLS, Size = V(3600), Position = XGAL, Color = Color3.fromRGB(255, 220, 160), Material = NEONM, Transparency = 0.86 })
	end

	-- space grid + lines going down to the Milky Way
	do
		local half, step, th = 7000, 1000, 34
		for i = 0, 14 do
			local a = -half + i * step
			for k = 0, 6 do
				local c = -6000 + k * 2000
				local col = Color3.fromHSV((0.5 + (i + k) / 40) % 1, 0.8, 1)
				P({ Size = Vector3.new(2000, th, th), Position = XPC + Vector3.new(c, 0, a), Color = col, Material = NEONM })
				P({ Size = Vector3.new(th, th, 2000), Position = XPC + Vector3.new(a, 0, c), Color = col, Material = NEONM })
			end
		end
		for _, ix in ipairs({ -6, -3, 0, 3, 6 }) do
			for _, iz in ipairs({ -6, -3, 0, 3, 6 }) do
				for k = 0, 13 do
					local fade = k / 13
					P({ Size = Vector3.new(40, 2000, 40), Position = XPC + Vector3.new(ix * 1000, -1000 - k * 2000, iz * 1000), Color = Color3.fromHSV((0.55 + fade * 0.35) % 1, 0.8, 1), Material = NEONM, Transparency = 0.05 + 0.8 * fade })
				end
			end
		end
	end

	return { folder = folder, xt = makeTess(folder) }
end

-- ---------------------------------------------------------------- crushing, folding the map
local function makeCrusher(T, S)
	local list = {}
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
			for _, p in ipairs(workspace:GetPartBoundsInBox(CFrame.new(T + UP * 700), Vector3.new(S * 0.9, 1400, S * 0.9), op)) do
				if #list >= 6000 then break end
				if p ~= workspace.Terrain and p.Size.Magnitude <= 700 then
					local m = p:FindFirstAncestorWhichIsA("Model")
					if not (m and m:FindFirstChildOfClass("Humanoid")) and not (rp and (p.Position - rp.Position).Magnitude < 32) then
						list[#list + 1] = { p, p.Position.Y - T.Y }
					end
				end
			end
			table.sort(list, function(a, b) return a[2] > b[2] end)
		end)
	end
	local idx = 1
	return function(headY) -- erases everything whose height is above headY (the falling bottom face)
		while list[idx] and list[idx][2] >= headY do
			local p = list[idx][1]
			idx += 1
			if p.Parent then p.Parent = nil end
		end
	end
end

local function collectFold(T, f, rootPos)
	local right = f:Cross(UP)
	local flipLeft = (rootPos - T):Dot(right) >= 0 -- you stay on your side, the other half flips
	local parts, cfs, n = {}, {}, 0
	for _, d in ipairs(workspace:GetDescendants()) do
		n += 1
		if n % 2500 == 0 then task.wait() end
		if #parts >= CONFIG.FOLD_MAX_PARTS then break end
		if d:IsA("BasePart") and d.Anchored and d.CanQuery and d ~= workspace.Terrain then
			local lat = (d.Position - T):Dot(right) * (flipLeft and -1 or 1)
			if lat > d.Size.Magnitude / 2 + 6 and (d.Position - rootPos).Magnitude > 70 then
				local m = d:FindFirstAncestorWhichIsA("Model")
				if not (m and m:FindFirstChildOfClass("Humanoid")) then
					parts[#parts + 1] = d
					cfs[#cfs + 1] = d.CFrame
				end
			end
		end
	end
	return { parts = parts, cfs = cfs, T = T, axis = flipLeft and f or -f }
end

local function applyFold(fd, ease) -- ease 0 = original map, 1 = folded over and 200 studs up
	local X = CFrame.new(fd.T + Vector3.new(0, 200 * ease, 0)) * CFrame.fromAxisAngle(fd.axis, math.pi * ease) * CFrame.new(-fd.T)
	local plist, clist = {}, {}
	for i, p in ipairs(fd.parts) do
		if p.Parent then
			plist[#plist + 1] = p
			clist[#clist + 1] = X * fd.cfs[i]
		end
	end
	local CH = 4000
	for s = 1, #plist, CH do
		local e = math.min(s + CH - 1, #plist)
		pcall(function()
			workspace:BulkMoveTo(table.move(plist, s, e, 1, {}), table.move(clist, s, e, 1, {}), Enum.BulkMoveMode.FireCFrameChanged)
		end)
	end
end

local function foldTween(fd, from, to, dur)
	runFor(dur, function(a) applyFold(fd, from + (to - from) * smooth(a)) end)
	applyFold(fd, to)
end

-- ---------------------------------------------------------------- THE SS-05 SEQUENCE
local function runSS05()
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
	local rootPos = root.Position
	local TSIZE = math.min(CONFIG.TESS_SIZE, 1400)
	local pc, foldData, tfold -- persistent bits (tesseract, stone, folded map) that outlive the cutscene

	local ok, err = pcall(function()
		sfx(SND.click, 1.2, 1, 3)
		if env.__StellarTessCleanup then pcall(env.__StellarTessCleanup) end
		tfold = Instance.new("Folder")
		tfold.Name = "StellarTess"
		tfold.Parent = workspace
		local myCleanup
		myCleanup = function()
			if pc then pc:Disconnect(); pc = nil end
			if foldData then pcall(applyFold, foldData, 0); foldData = nil end
			if tfold and tfold.Parent then tfold:Destroy() end
			if env.__StellarTessCleanup == myCleanup then env.__StellarTessCleanup = nil end
		end
		env.__StellarTessCleanup = myCleanup

		-- ---------- aim ----------
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char }
		local vs = cam.ViewportSize
		local ray = cam:ViewportPointToRay(vs.X / 2, vs.Y / 2)
		local res = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
		local T
		if res then
			T = res.Position
		else
			local p = ray.Origin + ray.Direction * 150
			local down = workspace:Raycast(p + Vector3.new(0, 200, 0), Vector3.new(0, -800, 0), params)
			T = down and down.Position or p
		end
		local toPlayer = Vector3.new(rootPos.X - T.X, 0, rootPos.Z - T.Z)
		if toPlayer.Magnitude < 5 then toPlayer = Vector3.new(0, 0, 1) end
		local f = -toPlayer.Unit -- "forward" = away from you

		-- ---------- HUGE rainbow square target ----------
		local target = buildTarget(S.realFolder, T, f, params, CONFIG.TARGET_SIZE)
		local targetSpeed = 0.25

		-- ---------- helpers: rainbow text, rainbow impact frames, camera ----------
		local big = Instance.new("TextLabel")
		big.BackgroundTransparency = 1
		big.Font = Enum.Font.GothamBlack
		big.TextSize = 64
		big.Text = ""
		big.TextColor3 = Color3.new(1, 1, 1)
		big.TextStrokeColor3 = Color3.new(0, 0, 0)
		big.TextStrokeTransparency = 1
		big.TextTransparency = 1
		big.AnchorPoint = Vector2.new(0.5, 0.5)
		big.Position = UDim2.new(0.5, 0, 0.5, 0)
		big.Size = UDim2.new(0.95, 0, 0, 100)
		big.ZIndex = 12
		big.Parent = hud.gui
		local bigGrad = Instance.new("UIGradient")
		bigGrad.Color = RAINBOW
		bigGrad.Parent = big
		local function showBig(text, size)
			big.Text = text
			big.TextSize = size or 64
			big.TextTransparency = 0
			big.TextStrokeTransparency = 0.4
		end
		local function hideBig()
			big.TextTransparency = 1
			big.TextStrokeTransparency = 1
		end

		local rb = Instance.new("Frame")
		rb.BorderSizePixel = 0
		rb.BackgroundColor3 = Color3.new(1, 1, 1)
		rb.BackgroundTransparency = 1
		rb.Size = UDim2.fromScale(1, 1)
		rb.ZIndex = 15
		rb.Parent = hud.gui
		local rg = Instance.new("UIGradient")
		rg.Color = RAINBOW
		rg.Parent = rb
		local function impactFrames() -- rainbow impact frames
			task.spawn(function()
				rg.Rotation = math.random(0, 360)
				rb.BackgroundColor3 = Color3.new(1, 1, 1)
				rb.BackgroundTransparency = 0.05
				RunService.RenderStepped:Wait()
				rg.Rotation = rg.Rotation + 90
				rb.BackgroundTransparency = 0.25
				RunService.RenderStepped:Wait()
				rb.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
				rb.BackgroundTransparency = 0.15
				RunService.RenderStepped:Wait()
				rb.BackgroundColor3 = Color3.new(1, 1, 1)
				rg.Rotation = rg.Rotation - 45
				rb.BackgroundTransparency = 0.35
				TweenService:Create(rb, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			end)
		end

		local shakeAmp = 0
		local function camSet(cf, fov)
			if not useCut then return end
			cam.CFrame = cf * shakeRot(shakeAmp)
			cam.FieldOfView = fov
			shakeAmp = shakeAmp * 0.9
		end
		local function blur(v) if fx then fx.blur.Size = v end end
		local rollWobble = function(a) return CFrame.Angles(0, 0, math.sin(a * 6) * 0.03) end

		-- state of the stage tesseract (cutscene) and the huge real one
		local xs = { on = false, center = XTC, size = 700, spin = 1, rainbow = 1, flash = 0, settle = 0, obj = nil }
		local rt = { on = false, center = T + UP * (TSIZE * 1.35), size = TSIZE, thick = TSIZE * 0.02, spin = 1, rainbow = 0, flash = 0, settle = 0, obj = nil }
		local stone, stoneGrads, orbit
		S.live[#S.live + 1] = RunService.RenderStepped:Connect(function(dt)
			local now = os.clock()
			target.update(now, targetSpeed)
			bigGrad.Rotation = (now * 120) % 360
			if xs.on and xs.obj then
				updateTess(xs.obj, xs.center, xs.size, xs.size * 0.04, dt, xs.spin, xs.rainbow, now, xs.flash, xs.settle)
				xs.flash = xs.flash * 0.9
			end
		end)
		-- persistent updater: the huge tesseract, the stone and the orbiting balls keep running after the cutscene
		pc = RunService.RenderStepped:Connect(function(dt)
			local now = os.clock()
			if rt.on and rt.obj then
				updateTess(rt.obj, rt.center, rt.size, rt.thick, dt, rt.spin, rt.rainbow, now, rt.flash, rt.settle)
				rt.flash = rt.flash * 0.9
			end
			if stoneGrads then
				for _, g in ipairs(stoneGrads) do g.Rotation = (now * 50) % 360 end
			end
			if orbit then
				local c = orbit.center
				local a1 = now * 1.6
				orbit.yb.Position = c + Vector3.new(math.cos(a1) * orbit.R1, math.sin(a1 * 0.7) * orbit.R1 * 0.35, math.sin(a1) * orbit.R1)
				orbit.yh.Position = orbit.yb.Position
				local a2 = -now * 2.1 + 2
				local tilt = CFrame.Angles(0, 0, math.rad(60))
				orbit.ib.Position = c + tilt * Vector3.new(math.cos(a2) * orbit.R2, math.sin(a2 * 0.5) * orbit.R2 * 0.25, math.sin(a2) * orbit.R2)
				orbit.ih.Position = orbit.ib.Position
			end
		end)

		-- rainbow shockwave rings
		local function ringWaveRainbow(center, maxR, dur, delay)
			task.spawn(function()
				task.wait(delay)
				local SEGS = 120
				local ring = {}
				for i = 1, SEGS do ring[i] = part({ Size = Vector3.new(12, 6, 12), Color = Color3.fromHSV(i / SEGS, 0.9, 1), Material = NEONM }, tfold) end
				runFor(dur, function(a)
					local rad = 10 + (a ^ 0.55) * maxR
					local width = 40 * (1 - a) + 4
					local arc = 2 * math.pi * rad / SEGS * 1.1
					for i, p in ipairs(ring) do
						local ang = (i / SEGS) * math.pi * 2
						p.Size = Vector3.new(width, 10 * (1 - a) + 1, arc)
						p.CFrame = CFrame.new(center + Vector3.new(0, 4, 0)) * CFrame.new(math.cos(ang) * rad, 0, math.sin(ang) * rad) * CFrame.Angles(0, -ang, 0)
						p.Transparency = 0.1 + 0.9 * a
					end
				end)
				for _, p in ipairs(ring) do p:Destroy() end
			end)
		end

		-- ================================================================
		saveLighting()
		hud.flash.BackgroundColor3 = Color3.new(1, 1, 1)
		if useCut then
			setControls(false)
			hum.WalkSpeed = 0; hum.JumpPower = 0; hum.JumpHeight = 0
			cam.CameraType = Enum.CameraType.Scriptable
			hud.bars(true)
		end
		hud.setLabel("SS-05  ·  TESSERACT")
		hud.setSub("TARGET LOCKED")
		sfx(SND.launch, 1.4, 0.8, 6)

		local stage, stageReady = nil, false
		local startCF = cam.CFrame
		if useCut then
			task.spawn(function()
				local okb, res2 = pcall(buildTessStage)
				if okb then stage = res2 else warn("[StellarRemote] stage build failed: " .. tostring(res2)) end
				stageReady = true
			end)
		end

		if useCut then
			----------------------------------------------------------------
			-- CUTSCENE ON
			----------------------------------------------------------------
			-- the huge target, then the camera rises and rewinds away from it
			local lockPos = T + toPlayer.Unit * (CONFIG.TARGET_SIZE * 1.1) + Vector3.new(0, CONFIG.TARGET_SIZE * 0.55, 0)
			local lockCF = CFrame.lookAt(lockPos, T)
			runFor(TS(0.9), function(a)
				cam.CFrame = startCF:Lerp(lockCF, smooth(a))
				targetSpeed = 0.25 + 1.2 * a
			end)
			hud.setLabel("◂◂  REWIND")
			runFor(TS(1.1), function(a)
				local k = a ^ 2
				cam.CFrame = CFrame.lookAt(lockPos:Lerp(T + UP * 2600 + toPlayer.Unit * 200, k), T)
				cam.FieldOfView = 70 + 25 * k
				fx.blur.Size = 14 * k
				targetSpeed = 1.5 + 3 * a
				if a > 0.75 then hud.flash.BackgroundTransparency = 1 - smooth((a - 0.75) / 0.25) end
			end)
			hud.flash.BackgroundTransparency = 0
			while not stageReady do RunService.RenderStepped:Wait() end
			if not stage then error("stage not built") end
			S.stage = stage
			S.resetFx()
			S.enterSpace()
			S.hideWorld()
			xs.obj = stage.xt
			xs.on = true
			fx.cc.TintColor = Color3.fromRGB(190, 235, 255)
			fx.cc.Saturation = -0.4

			-- lock on Earth, rewind back
			hud.setLabel("◂◂  REWIND  ·  EARTH")
			sfx(SND.whoosh, 1.4, 0.5, 8)
			runFor(TS(1.0), function(a, dt, e)
				camSet(CFrame.lookAt(xPos(XSHOT_E, a), XSHOT_E.c) * rollWobble(a), 72)
				hud.flash.BackgroundTransparency = smooth(e / 0.4)
				hud.setSub("REWINDING  " .. fmt((1 - a * 0.5) * 13800000) .. "  YEARS")
				blur(4 * a)
			end)
			-- ...whip, lock on the solar system, keep rewinding
			local pe, ps0 = xPos(XSHOT_E, 1), xPos(XSHOT_S, 0)
			runFor(TS(0.2), function(a)
				local k = smooth(a)
				camSet(CFrame.lookAt(pe:Lerp(ps0, k), XSHOT_E.c:Lerp(XSHOT_S.c, k)), 72 + 20 * math.sin(a * math.pi))
				blur(24 * math.sin(a * math.pi))
			end)
			hud.setLabel("◂◂  REWIND  ·  SOLAR SYSTEM")
			runFor(TS(1.2), function(a)
				camSet(CFrame.lookAt(xPos(XSHOT_S, a), XSHOT_S.c) * rollWobble(a + 1), 72)
				hud.setSub("REWINDING  " .. fmt((0.5 - a * 0.5) * 13800000) .. "  YEARS")
				blur(4 * (1 - a))
			end)
			-- the camera goes up to the space grid
			local pse = xPos(XSHOT_S, 1)
			hud.setLabel("")
			hud.setSub("")
			S.resetFx()
			runFor(TS(1.3), function(a)
				local k = smooth(a)
				camSet(CFrame.lookAt(pse:Lerp(XCT2, k), XSHOT_S.c:Lerp(XMID, k)), 72 - 6 * k)
			end)
			-- tesseract above the Milky Way, solar system below it
			showBig("T  E  S  S  E  R  A  C  T", 62)
			sfx(SND.boom, 1.2, 0.6, 6)
			runFor(TS(1.3), function(a)
				camSet(CFrame.lookAt(XCT2, XMID), 66)
				if a > 0.78 then big.TextTransparency = (a - 0.78) / 0.22 end
			end)
			hideBig()
			-- it drops into the Milky Way...
			sfx(SND.whoosh, 2, 0.5, 6)
			local portal
			runFor(TS(1.2), function(a)
				xs.center = XTC:Lerp(XGAL, a ^ 2)
				xs.size = 700 + 600 * a
				camSet(CFrame.lookAt(XCT2:Lerp(XCAM_F, smooth(a)), xs.center), 70)
				blur(8 * a)
				if a > 0.8 and not portal then portal = buildPortal(stage.folder, XGAL + Vector3.new(0, 40, 0), UP, 2600) end
				if portal then portal.update(os.clock(), smooth((a - 0.8) / 0.2)) end
			end)
			-- ...and instantly teleports to the Earth model
			impactFrames()
			sfx(SND.boom, 2.5, 0.8, 8)
			if portal then portal.destroy() end
			blur(0)
			xs.center = XS + Vector3.new(0, 130, 0)
			xs.size = 260
			xs.flash = 2
			for i = 1, 3 do
				local ripple = part({ Shape = CYLS, Size = Vector3.new(0.4, 10, 10), CFrame = flatCF(XS + Vector3.new(0, 1.5, 0), UP), Color = Color3.fromHSV(i / 3, 0.9, 1), Material = NEONM, Transparency = 0.1 }, stage.folder)
				TweenService:Create(ripple, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, (i - 1) * 0.15), { Size = Vector3.new(0.4, 900, 900), Transparency = 1 }):Play()
			end
			runFor(TS(0.9), function(a)
				camSet(CFrame.lookAt(XS + Vector3.new(-380, 230, -520):Lerp(Vector3.new(-300, 190, -420), a), XS + Vector3.new(0, 150, 0)), 62)
				if a > 0.78 then hud.flash.BackgroundTransparency = 1 - smooth((a - 0.78) / 0.22) end
			end)
			hud.flash.BackgroundTransparency = 0
			xs.on = false
			stage.folder:Destroy()
			S.leaveSpace()
			S.resetFx()
			hud.setLabel("")
			hud.setSub("")
		else
			----------------------------------------------------------------
			-- CUTSCENE OFF: just the big target, then the wormhole
			----------------------------------------------------------------
			sfx(SND.launch, 1.3, 0.45, 9)
			local CH = math.min(CONFIG.LIVE_CHARGE, 3.5)
			runFor(CH, function(a, dt, e)
				targetSpeed = 0.25 + 3 * a
				hud.setSub(("TESSERACT INCOMING  ·  %.1f"):format(math.max(CH - e, 0)))
			end)
			hud.setSub("")
		end

		-- ================================================================
		-- THE GAME: the huge tesseract
		-- ================================================================
		local HOVER = TSIZE * 1.35
		local REST = TSIZE * 0.43
		local restCenter = T + UP * REST
		local vant = T + toPlayer.Unit * (TSIZE * 1.25) + Vector3.new(0, TSIZE * 0.28, 0)
		rt.obj = makeTess(tfold)
		rt.center = T + UP * HOVER
		rt.on = true
		local crusher = makeCrusher(T, TSIZE)
		task.spawn(function() foldData = collectFold(T, f, rootPos) end)

		if useCut then
			-- camera in the game, looking up at the sky: a VERY HUGE tesseract
			sfx(SND.whoosh, 2, 0.5, 6)
			runFor(TS(1.3), function(a, dt, e)
				camSet(CFrame.lookAt(vant, rt.center), 70)
				if e < 0.3 then hud.flash.BackgroundTransparency = smooth(e / 0.3) end
				targetSpeed = 1.5
			end)
		else
			-- the huge tesseract enters a wormhole, teleports outside Earth
			sfx(SND.whoosh, 2, 0.5, 6)
			local PWc = rt.center + f * (TSIZE * 1.4)
			local portal = buildPortal(tfold, PWc, -f, TSIZE * 0.75)
			runFor(0.9, function(a, dt, e)
				portal.update(os.clock(), smooth(a))
				targetSpeed = 2
			end)
			sfx(SND.boom, 2, 0.6, 6)
			runFor(1.0, function(a)
				local k = smooth(a)
				portal.update(os.clock(), 1)
				rt.center = (T + UP * HOVER):Lerp(PWc, k)
				rt.size = TSIZE * math.max(1 - k, 0.03)
				rt.thick = rt.size * 0.02
			end)
			rt.on = false
			rt.obj.folder.Parent = nil
			runFor(0.45, function(a) portal.update(os.clock(), 1 - smooth(a)) end)
			portal.destroy()
			task.wait(0.5)
			-- ...and comes back from outside Earth, very high up
			rt.size, rt.thick = TSIZE, TSIZE * 0.02
			rt.center = T + UP * 5200
			rt.on = true
			rt.flash = 2
			impactFrames()
			sfx(SND.boom, 2, 0.9, 6)
		end

		-- turns rainbow, stops spinning
		local startAlt = (rt.center.Y - T.Y)
		runFor(TS(useCut and 1.0 or 0.9), function(a)
			rt.rainbow = smooth(a)
			rt.spin = 1 - smooth(a)
			rt.settle = smooth((a - 0.2) / 0.8)
			camSet(CFrame.lookAt(vant, rt.center), 70)
			targetSpeed = 2 + 2 * a
		end)
		rt.spin, rt.rainbow, rt.settle = 0, 1, 1

		-- CRASHING DOWN TO EARTH
		sfx(SND.shot, 3, 0.5, 8)
		local crashDur = useCut and 0.9 or 1.1
		runFor(TS(crashDur), function(a)
			local e = a ^ 2.2
			local y = startAlt + (REST - startAlt) * e
			rt.center = T + UP * y
			crusher(y - REST) -- everything under the falling bottom face gets crushed
			camSet(CFrame.lookAt(vant, rt.center:Lerp(restCenter, 0.0)), 70 + 8 * a)
			blur(8 * a)
			targetSpeed = 4
		end)
		rt.center = restCenter
		crusher(-1e9)
		target.destroy()
		if CONFIG.CARVE_LAND then
			pcall(function() workspace.Terrain:FillBlock(CFrame.new(T + UP * 20), Vector3.new(TSIZE * 0.9, 50, TSIZE * 0.9), Enum.Material.Air) end)
		end
		ringWaveRainbow(T, 3200, 2.4, 0)
		ringWaveRainbow(T, 2400, 2.0, 0.25)
		do
			local pe2 = part({ Size = Vector3.new(TSIZE * 0.8, 1, TSIZE * 0.8), Position = T + UP * 4, Transparency = 1 }, tfold)
			local sp = Instance.new("ParticleEmitter")
			sp.Rate = 0
			sp.Color = RAINBOW
			sp.LightEmission = 1
			sp.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 10), NumberSequenceKeypoint.new(1, 0) })
			sp.Lifetime = NumberRange.new(1.5, 3)
			sp.Speed = NumberRange.new(120, 420)
			sp.SpreadAngle = Vector2.new(70, 70)
			sp.Acceleration = Vector3.new(0, -120, 0)
			sp.EmissionDirection = Enum.NormalId.Top
			sp.Parent = pe2
			sp:Emit(400)
			local sm = Instance.new("ParticleEmitter")
			sm.Rate = 0
			sm.Texture = "rbxasset://textures/particles/smoke_main.dds"
			sm.Color = ColorSequence.new(Color3.fromRGB(70, 60, 90))
			sm.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 60), NumberSequenceKeypoint.new(1, 240) })
			sm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
			sm.Lifetime = NumberRange.new(3, 6)
			sm.Speed = NumberRange.new(30, 120)
			sm.SpreadAngle = Vector2.new(60, 60)
			sm.EmissionDirection = Enum.NormalId.Top
			sm.Parent = pe2
			sm:Emit(120)
			Debris:AddItem(pe2, 9)
		end
		shakeAmp = 0.06
		rt.flash = 2
		impactFrames()
		sfx(SND.boom, 3, 0.5, 12)
		sfx(SND.shot, 3, 0.3, 12)
		blur(0)
		targetSpeed = 1

		-- ASCENSION x5: shown 0.5 s, gone 0.5 s, with rainbow impact frames every time
		task.wait(TS(0.5))
		for i = 1, 5 do
			showBig("ASCENSION", 72)
			impactFrames()
			rt.flash = 1.6
			shakeAmp = 0.04
			sfx(SND.boom, 2, 0.8 + 0.08 * i, 4)
			local t0 = os.clock()
			while os.clock() - t0 < 0.5 do
				RunService.RenderStepped:Wait()
				camSet(CFrame.lookAt(vant, restCenter), 62)
			end
			hideBig()
			t0 = os.clock()
			while os.clock() - t0 < 0.5 do
				RunService.RenderStepped:Wait()
				camSet(CFrame.lookAt(vant, restCenter), 62)
			end
		end

		-- FOLDED: half the map flips upside down and goes 200 studs up
		showBig("FOLDED", 84)
		impactFrames()
		task.delay(0.15, impactFrames)
		task.delay(0.3, impactFrames)
		rt.flash = 2.2
		shakeAmp = 0.07
		sfx(SND.boom, 3, 0.4, 12)
		sfx(SND.whoosh, 2.5, 0.4, 8)
		task.spawn(function()
			while not foldData do task.wait() end
			if #foldData.parts == 0 then return end
			foldTween(foldData, 0, 1, 0.9)
			task.delay(CONFIG.FLIP_STAY, function()
				local fd = foldData
				if fd then
					foldTween(fd, 1, 0, 1.0)
					if foldData == fd then foldData = nil end
				end
			end)
		end)

		-- the tesseract turns into a rainbow stone: camera just watches, nothing moves
		local sSize = REST * 2 * 0.97
		stone = part({ Size = V(0.5), CFrame = CFrame.new(restCenter), Material = Enum.Material.Granite, Color = Color3.fromRGB(90, 90, 110) }, tfold)
		stoneGrads = {}
		for _, face in ipairs(Enum.NormalId:GetEnumItems()) do
			local sg = Instance.new("SurfaceGui")
			sg.Face = face
			sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
			sg.CanvasSize = Vector2.new(256, 256)
			sg.LightInfluence = 0
			sg.Brightness = 1.4
			sg.Parent = stone
			local fr = Instance.new("Frame")
			fr.Size = UDim2.fromScale(1, 1)
			fr.BackgroundColor3 = Color3.new(1, 1, 1)
			fr.BackgroundTransparency = 0.12
			fr.BorderSizePixel = 0
			fr.Parent = sg
			local g = Instance.new("UIGradient")
			g.Color = RAINBOW
			g.Parent = fr
			stoneGrads[#stoneGrads + 1] = g
		end
		local function ball(d, color)
			local b = part({ Shape = BALLS, Size = V(d), Color = color, Material = NEONM }, tfold)
			local h = part({ Shape = BALLS, Size = V(d * 2.2), Color = color, Material = NEONM, Transparency = 0.8 }, tfold)
			local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, d / 2, 0); a0.Parent = b
			local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -d / 2, 0); a1.Parent = b
			local tr = Instance.new("Trail")
			tr.Attachment0, tr.Attachment1 = a0, a1
			tr.Color = ColorSequence.new(color)
			tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			tr.Lifetime = 1.4
			tr.LightEmission = 1
			tr.FaceCamera = true
			tr.Parent = b
			return b, h
		end
		local yb, yh = ball(TSIZE * 0.09, Color3.fromRGB(255, 255, 40))   -- neon yellow ball
		local ib, ih = ball(TSIZE * 0.07, Color3.fromRGB(170, 240, 255))  -- neon ice ball
		orbit = { center = restCenter, R1 = TSIZE * 0.78, R2 = TSIZE * 0.66, yb = yb, yh = yh, ib = ib, ih = ih }

		local hold = TS(2.0 + CONFIG.STONE_VIEW)
		runFor(hold, function(a, dt, e)
			camSet(CFrame.lookAt(vant, restCenter), 62)
			local g = smooth((e - 0.6) / 0.9)
			stone.Size = V(math.max(sSize * g, 0.5))
			if e > 2.0 then hideBig() end
		end)
		hideBig()

		-- camera goes back to normal; the stone, the orbiting balls and the folded map stay for a while
		impactFrames()
		S.restorePlayer()
		S.resetFx()
		hud.bars(false)
		hud.setLabel("")
		hud.setSub("")
		TweenService:Create(hud.flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		task.delay(CONFIG.STONE_STAYS, function()
			if tfold and tfold.Parent and stone then
				TweenService:Create(stone, TweenInfo.new(1.2), { Size = V(0.5) }):Play()
				rt.on = false
				if rt.obj then rt.obj.folder.Parent = nil end
				task.wait(1.3)
			end
			myCleanup()
		end)
		task.wait(0.6)
	end)

	if not ok then
		warn("[StellarRemote] " .. tostring(err))
		if env.__StellarTessCleanup then pcall(env.__StellarTessCleanup) end
	end
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
	frame.Size = UDim2.fromOffset(300, 436)
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
	local ss04, ss04Stroke = button("SS-04  ·  THE SHOOTING STAR", 6, true)
	ss04.TextSize = 17
	ss04.BackgroundColor3 = Color3.fromRGB(78, 28, 140)
	ss04Stroke.Color = Color3.fromRGB(190, 120, 255)
	local ss05, ss05Stroke = button("SS-05  ·  TESSERACT", 7, true)
	ss05.BackgroundColor3 = Color3.fromRGB(40, 24, 70)
	local ss05Grad = Instance.new("UIGradient")
	ss05Grad.Color = RAINBOW
	ss05Grad.Parent = ss05Stroke
	local close = Instance.new("TextButton")
	close.Font = Enum.Font.Code; close.Text = "CLOSE"; close.TextSize = 16
	close.TextColor3 = Color3.fromRGB(200, 204, 220); close.BackgroundTransparency = 1
	close.Size = UDim2.new(1, 0, 0, 30); close.LayoutOrder = 8; close.Parent = frame

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
	conns[#conns + 1] = ss04.Activated:Connect(function() task.spawn(runSS04) end)
	conns[#conns + 1] = ss05.Activated:Connect(function() task.spawn(runSS05) end)
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
	if env.__StellarTessCleanup then pcall(env.__StellarTessCleanup) end
	for _, o in ipairs(objs) do pcall(function() o:Destroy() end) end
	pcall(function() RunService:UnbindFromRenderStep("StellarShake") end)
end

print("[Stellar Remote v5] ready - equip the remote (or tap SR), set CUTSCENE ON/OFF, press SS-01, SS-03, SS-04 or SS-05.")
