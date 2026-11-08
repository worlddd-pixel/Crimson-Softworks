-- crimson softworks | murder mystery 2
-- RightShift hides the menu, ctrl+click teleports

local plrs = game:GetService("Players")
local rs = game:GetService("RunService")
local uis = game:GetService("UserInputService")
local lighting = game:GetService("Lighting")
local tps = game:GetService("TeleportService")
local http = game:GetService("HttpService")
local vu = game:GetService("VirtualUser")
local core = game:GetService("CoreGui")
local sg = game:GetService("StarterGui")
local lp = plrs.LocalPlayer

local cfg = {
	speed = 32, jump = 65, fly = 70, fov = 90, grav = 140, clock = 14,
	espRange = 0, alert = 30,
	version = "1.0.6",
	url = "https://raw.githubusercontent.com/worldcupi3/apex-hub/refs/heads/main/crimson_mm2.lua",
	discord = "https://discord.gg/9KkKHQZdHF",
	file = "crimson_mm2.json",
	-- name guesses, check them with Run Diagnostics
	knife = { "knife" },
	gun = { "gun", "revolver" },
	coin = { "coin" },
	gundrop = { "gundrop" },
}
local nums = { "speed", "jump", "fly", "fov", "grav", "clock", "espRange", "alert" }

local conns = {}
local function bind(sig, fn)
	conns[#conns + 1] = sig:Connect(fn)
end

local function note(t)
	pcall(sg.SetCore, sg, "SendNotification", { Title = "Crimson Softworks", Text = t, Duration = 3 })
end

local function root()
	local c = lp.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function hum()
	local c = lp.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function others()
	local out = {}
	for _, p in ipairs(plrs:GetPlayers()) do
		if p ~= lp and p.Character then
			local r = p.Character:FindFirstChild("HumanoidRootPart")
			local h = p.Character:FindFirstChildOfClass("Humanoid")
			if r and h and h.Health > 0 then
				out[#out + 1] = { p = p, r = r, h = h }
			end
		end
	end
	return out
end

-- roles come from who is holding the knife or the gun
local function hasTool(p, names)
	local function scan(c)
		if not c then return false end
		for _, t in ipairs(c:GetChildren()) do
			if t:IsA("Tool") then
				local n = t.Name:lower()
				for _, k in ipairs(names) do
					if n:find(k, 1, true) then return true end
				end
			end
		end
		return false
	end
	return scan(p:FindFirstChildOfClass("Backpack")) or scan(p.Character)
end

local function roleOf(p)
	if hasTool(p, cfg.knife) then return "murderer" end
	if hasTool(p, cfg.gun) then return "sheriff" end
	return "innocent"
end

local function withRole(role)
	for _, o in ipairs(others()) do
		if roleOf(o.p) == role then return o end
	end
end

-- coins and the dropped gun
local coins, guns = {}, {}
local function track(i)
	local isPart = i:IsA("BasePart")
	if not isPart and not i:IsA("Model") then return end
	local n = i.Name:lower()
	for _, k in ipairs(cfg.gundrop) do
		if n:find(k, 1, true) then guns[i] = true return end
	end
	if not isPart then return end
	for _, k in ipairs(cfg.coin) do
		if n:find(k, 1, true) then coins[i] = true return end
	end
end
for _, i in ipairs(workspace:GetDescendants()) do track(i) end
bind(workspace.DescendantAdded, track)
bind(workspace.DescendantRemoving, function(i)
	coins[i] = nil
	guns[i] = nil
end)

local function posOf(i)
	return i:IsA("Model") and i:GetPivot().Position or i.Position
end

local function nearestOf(set)
	local me = root()
	if not me then return end
	local best, bd
	for i in pairs(set) do
		if i.Parent then
			local d = (posOf(i) - me.Position).Magnitude
			if not bd or d < bd then best, bd = i, d end
		end
	end
	return best, bd
end

-- feature registry
local F, order = {}, {}
local function feat(key, name, up, down)
	local f = { name = name, on = false, up = up, down = down }
	F[key] = f
	order[#order + 1] = f
	return f
end

local function set(f, v)
	if f.on == v then return end
	f.on = v
	local fn = v and f.up or f.down
	if fn then
		local ok, err = pcall(fn)
		if not ok then warn("[crimson] " .. f.name .. ": " .. tostring(err)) end
	end
	if f.refresh then f.refresh() end
end

local gui
local saved, lastSafe
local flyBV, flyBG
local orig = { grav = workspace.Gravity, zoom = lp.CameraMaxZoomDistance }
local esp, objEsp, lines = {}, {}, {}
local ragHum
local specIdx = 0
local alertCd = 0
local lastRole
local hud, arrow, arrowTarget
local fullOrig, fogOrig, speedOrig, jumpOrig, clockOrig
local drawing = Drawing ~= nil

-- movement
local function stopFly()
	if flyBV then flyBV:Destroy() flyBV = nil end
	if flyBG then flyBG:Destroy() flyBG = nil end
	local h = hum()
	if h then h.PlatformStand = false end
end

local function startFly()
	local r, h = root(), hum()
	if not r then return end
	flyBV = Instance.new("BodyVelocity")
	flyBV.MaxForce = Vector3.one * 1e9
	flyBV.Velocity = Vector3.zero
	flyBV.Parent = r
	flyBG = Instance.new("BodyGyro")
	flyBG.MaxTorque = Vector3.one * 1e9
	flyBG.P = 1e4
	flyBG.CFrame = r.CFrame
	flyBG.Parent = r
	if h then h.PlatformStand = true end
end

feat("speed", "Speed Boost", function()
	local h = hum()
	-- never save our own boosted value as the original
	if h and (h.WalkSpeed ~= cfg.speed or not speedOrig) then speedOrig = h.WalkSpeed end
end,
	function() local h = hum() if h and speedOrig then h.WalkSpeed = speedOrig end end)
feat("jump", "Jump Boost", function()
	local h = hum()
	if h and (h.JumpPower ~= cfg.jump or not jumpOrig) then jumpOrig = { h.JumpPower, h.UseJumpPower } end
end,
	function() local h = hum() if h and jumpOrig then h.UseJumpPower = jumpOrig[2] h.JumpPower = jumpOrig[1] end end)
feat("infjump", "Infinite Jump")
feat("fly", "Fly", startFly, stopFly)
feat("noclip", "Noclip")
feat("clicktp", "Click Teleport (PC, Ctrl+Click)")
feat("antivoid", "Anti-Void")
feat("antiragdoll", "Anti-Ragdoll", function() ragHum = nil end, function()
	local h = hum()
	if h then
		h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
		h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
	end
	ragHum = nil
end)
feat("bhop", "Bunny Hop")
feat("grav", "Gravity Changer", function() orig.grav = workspace.Gravity end, function() workspace.Gravity = orig.grav end)

bind(uis.JumpRequest, function()
	if F.infjump.on then
		local h = hum()
		if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)

-- esp
local roleColor = {
	murderer = Color3.fromRGB(255, 60, 60),
	sheriff = Color3.fromRGB(70, 140, 255),
	innocent = Color3.fromRGB(230, 230, 230),
}

local function clearEsp(p)
	local e = esp[p]
	if e then
		for _, i in ipairs(e.items) do pcall(i.Destroy, i) end
		esp[p] = nil
	end
end

local function label(adornee)
	local g = Instance.new("BillboardGui")
	g.Adornee = adornee
	g.AlwaysOnTop = true
	g.Size = UDim2.fromOffset(180, 28)
	g.StudsOffset = Vector3.new(0, 3, 0)
	local t = Instance.new("TextLabel", g)
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0
	t.Font = Enum.Font.GothamBold
	t.TextSize = 13
	g.Parent = adornee
	return g, t
end

local function updateEsp()
	local me = root()
	local seen = {}
	for _, o in ipairs(others()) do
		local head = o.p.Character:FindFirstChild("Head")
		local d = me and (o.r.Position - me.Position).Magnitude or 0
		if head and (cfg.espRange == 0 or d <= cfg.espRange) then
			seen[o.p] = true
			local e = esp[o.p]
			if not e or e.char ~= o.p.Character then
				clearEsp(o.p)
				local hl = Instance.new("Highlight")
				hl.Adornee = o.p.Character
				hl.FillTransparency = 0.5
				hl.OutlineColor = Color3.new(1, 1, 1)
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.Parent = o.p.Character
				local g, t = label(head)
				e = { char = o.p.Character, items = { hl, g }, hl = hl, txt = t }
				esp[o.p] = e
			end
			local role = roleOf(o.p)
			e.hl.FillColor = roleColor[F.roles.on and role or "innocent"]
			e.txt.Text = ("%s [%d]%s"):format(o.p.DisplayName, math.floor(d), role ~= "innocent" and (" " .. role) or "")
		end
	end
	for p in pairs(esp) do
		if not seen[p] then clearEsp(p) end
	end
end

local function clearObj(i)
	local h = objEsp[i]
	if h then pcall(h.Destroy, h) objEsp[i] = nil end
end

local function updateObj()
	local want = {}
	if F.gunesp.on then
		for g in pairs(guns) do
			if g.Parent then want[g] = Color3.fromRGB(80, 170, 255) end
		end
	end
	if F.coinesp.on then
		local me = root()
		local list = {}
		for c in pairs(coins) do
			if c.Parent then list[#list + 1] = c end
		end
		if me then
			table.sort(list, function(a, b)
				return (posOf(a) - me.Position).Magnitude < (posOf(b) - me.Position).Magnitude
			end)
		end
		for i = 1, math.min(12, #list) do want[list[i]] = Color3.fromRGB(255, 215, 0) end
	end
	for inst, col in pairs(want) do
		if not objEsp[inst] then
			local h = Instance.new("Highlight")
			h.Adornee = inst
			h.FillTransparency = 0.3
			h.OutlineColor = Color3.new(1, 1, 1)
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			h.Parent = inst
			objEsp[inst] = h
		end
		objEsp[inst].FillColor = col
	end
	for inst in pairs(objEsp) do
		if not want[inst] or not inst.Parent then clearObj(inst) end
	end
end

local function clearLines()
	for p, l in pairs(lines) do
		pcall(function() l:Remove() end)
		lines[p] = nil
	end
end

feat("esp", "Player ESP", nil, function() for p in pairs(esp) do clearEsp(p) end end)
feat("roles", "Role Colors (murderer / sheriff)")
feat("gunesp", "Gun Drop ESP", nil, function() updateObj() end)
feat("coinesp", "Coin ESP", nil, function() updateObj() end)
feat("tracers", "Tracers", function()
	if not drawing then
		note("Tracers need the Drawing API")
		task.defer(set, F.tracers, false)
	end
end, clearLines)
feat("arrow", "Arrow to Coin / Gun", function()
	arrow = Instance.new("TextLabel")
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Size = UDim2.fromOffset(32, 32)
	arrow.BackgroundTransparency = 1
	arrow.Text = "▲"
	arrow.TextSize = 28
	arrow.Font = Enum.Font.GothamBold
	arrow.TextColor3 = Color3.fromRGB(255, 215, 0)
	arrow.TextStrokeTransparency = 0
	arrow.Visible = false
	arrow.Parent = gui
end, function()
	if arrow then arrow:Destroy() arrow = nil end
end)
feat("fullbright", "Fullbright", function()
	fullOrig = { Brightness = lighting.Brightness, ClockTime = lighting.ClockTime,
		GlobalShadows = lighting.GlobalShadows, Ambient = lighting.Ambient }
	lighting.Brightness = 2
	lighting.ClockTime = 14
	lighting.GlobalShadows = false
	lighting.Ambient = Color3.fromRGB(180, 180, 180)
end, function()
	if fullOrig then for k, v in pairs(fullOrig) do lighting[k] = v end end
end)
feat("nofog", "Remove Fog", function()
	fogOrig = { lighting.FogStart, lighting.FogEnd, {} }
	lighting.FogStart = 0
	lighting.FogEnd = 1e6
	for _, a in ipairs(lighting:GetChildren()) do
		if a:IsA("Atmosphere") then fogOrig[3][a] = a.Density a.Density = 0 end
	end
end, function()
	if fogOrig then
		lighting.FogStart, lighting.FogEnd = fogOrig[1], fogOrig[2]
		for a, d in pairs(fogOrig[3]) do if a.Parent then a.Density = d end end
	end
end)
local fovOrig
feat("fovchg", "FOV Changer", function()
	local c = workspace.CurrentCamera
	fovOrig = c and c.FieldOfView
end, function()
	local c = workspace.CurrentCamera
	if c and fovOrig then c.FieldOfView = fovOrig end
end)
feat("timelock", "Time of Day Lock", function() clockOrig = lighting.ClockTime end,
	function() if clockOrig then lighting.ClockTime = clockOrig end end)
feat("zoom", "Max Zoom Out", function() orig.zoom = lp.CameraMaxZoomDistance lp.CameraMaxZoomDistance = 1000 end,
	function() lp.CameraMaxZoomDistance = orig.zoom end)
feat("hidetag", "Hide Name Tag", function()
	local h = hum()
	if h then h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
end, function()
	local h = hum()
	if h then h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer end
end)
feat("hud", "FPS / Ping Counter", function()
	hud = Instance.new("TextLabel")
	hud.Size = UDim2.fromOffset(170, 22)
	hud.Position = UDim2.new(1, -180, 0, 6)
	hud.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	hud.BackgroundTransparency = 0.3
	hud.BorderSizePixel = 0
	hud.TextColor3 = Color3.new(1, 1, 1)
	hud.Font = Enum.Font.GothamBold
	hud.TextSize = 13
	hud.Parent = gui
end, function()
	if hud then hud:Destroy() hud = nil end
end)

-- round awareness
feat("alert", "Murderer Proximity Alert")
feat("rolenote", "Role Notifications")

-- utility
feat("antiafk", "Anti-AFK")
bind(lp.Idled, function()
	if F.antiafk.on then
		vu:CaptureController()
		vu:ClickButton2(Vector2.new())
	end
end)

local rejoining = false
feat("autorejoin", "Auto Rejoin on Kick")
pcall(function()
	local ov = core:WaitForChild("RobloxPromptGui", 5):WaitForChild("promptOverlay", 5)
	bind(ov.ChildAdded, function(c)
		if F.autorejoin.on and c.Name == "ErrorPrompt" and not rejoining then
			rejoining = true
			task.delay(30, function() rejoining = false end)
			task.wait(2)
			tps:Teleport(game.PlaceId, lp)
		end
	end)
end)

feat("joinalerts", "Join / Leave Alerts")
bind(plrs.PlayerAdded, function(p) if F.joinalerts.on then note(p.DisplayName .. " joined") end end)
bind(plrs.PlayerRemoving, function(p)
	clearEsp(p)
	if lines[p] then pcall(function() lines[p]:Remove() end) lines[p] = nil end
	if F.joinalerts.on then note(p.DisplayName .. " left") end
end)

-- main loop
local t1, t2, t3, fpsT, frames = 0, 0, 0, 0, 0
bind(rs.Heartbeat, function(dt)
	local h, r = hum(), root()
	if not h or not r then return end

	if F.speed.on then h.WalkSpeed = cfg.speed end
	if F.jump.on then h.UseJumpPower = true h.JumpPower = cfg.jump end
	if F.grav.on then workspace.Gravity = cfg.grav end
	if F.hidetag.on then h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
	if F.timelock.on then lighting.ClockTime = cfg.clock end
	if F.bhop.on and h.FloorMaterial ~= Enum.Material.Air and h.MoveDirection.Magnitude > 0 then h.Jump = true end
	if F.antiragdoll.on and h ~= ragHum then
		h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		ragHum = h
	end

	local floor = workspace.FallenPartsDestroyHeight + 80
	if h.FloorMaterial ~= Enum.Material.Air and r.Position.Y > floor then
		lastSafe = r.CFrame
	elseif F.antivoid.on and r.Position.Y < floor and lastSafe then
		r.AssemblyLinearVelocity = Vector3.zero
		r.CFrame = lastSafe
	end

	if F.fly.on then
		if not flyBV or flyBV.Parent ~= r then stopFly() startFly() end
		if flyBV and flyBG then
			local cf = workspace.CurrentCamera.CFrame
			local d = Vector3.zero
			if uis:IsKeyDown(Enum.KeyCode.W) then d += cf.LookVector end
			if uis:IsKeyDown(Enum.KeyCode.S) then d -= cf.LookVector end
			if uis:IsKeyDown(Enum.KeyCode.D) then d += cf.RightVector end
			if uis:IsKeyDown(Enum.KeyCode.A) then d -= cf.RightVector end
			if uis:IsKeyDown(Enum.KeyCode.Space) then d += Vector3.yAxis end
			if uis:IsKeyDown(Enum.KeyCode.LeftShift) then d -= Vector3.yAxis end
			flyBV.Velocity = d.Magnitude > 0 and d.Unit * cfg.fly or Vector3.zero
			flyBG.CFrame = cf
		end
	end

	t1 += dt
	if t1 >= 0.25 then
		t1 = 0
		if F.esp.on then updateEsp() end
		if F.gunesp.on or F.coinesp.on then updateObj() end
		if arrow then arrowTarget = nearestOf(guns) or nearestOf(coins) end
	end

	t2 += dt
	if t2 >= 0.5 then
		t2 = 0
		if F.alert.on and os.clock() - alertCd > 6 then
			local m = withRole("murderer")
			if m and roleOf(lp) ~= "murderer" and (m.r.Position - r.Position).Magnitude <= cfg.alert then
				alertCd = os.clock()
				note("Murderer is close: " .. m.p.DisplayName)
			end
		end
	end

	t3 += dt
	if t3 >= 1 then
		t3 = 0
		if F.rolenote.on then
			local role = roleOf(lp)
			if role ~= lastRole then
				if role ~= "innocent" then note("You are the " .. role) end
				lastRole = role
			end
		end
	end
end)

bind(rs.Stepped, function()
	if F.noclip.on and lp.Character then
		for _, p in ipairs(lp.Character:GetDescendants()) do
			if p:IsA("BasePart") then p.CanCollide = false end
		end
	end
end)

bind(rs.RenderStepped, function(dt)
	local cam = workspace.CurrentCamera
	if F.fovchg.on and cam then cam.FieldOfView = cfg.fov end
	if hud then
		fpsT += dt
		frames += 1
		if fpsT >= 0.5 then
			hud.Text = ("FPS %d | Ping %dms"):format(math.floor(frames / fpsT), math.floor(lp:GetNetworkPing() * 1000))
			fpsT, frames = 0, 0
		end
	end
	if arrow and cam then
		local target = arrowTarget
		if target and not target.Parent then
			arrowTarget = nearestOf(guns) or nearestOf(coins)
			target = arrowTarget
		end
		if not target then
			arrow.Visible = false
		else
			local v = cam:WorldToViewportPoint(posOf(target))
			local center = cam.ViewportSize / 2
			local dir = Vector2.new(v.X, v.Y) - center
			if v.Z < 0 then dir = -dir end
			if dir.Magnitude < 1 then dir = Vector2.new(0, -1) end
			local u = dir.Unit
			local p = center + u * math.min(dir.Magnitude, 180)
			arrow.Visible = true
			arrow.Position = UDim2.fromOffset(p.X, p.Y)
			arrow.Rotation = math.deg(math.atan2(u.Y, u.X)) + 90
		end
	end
	if F.tracers.on and drawing and cam then
		local from = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y)
		for _, o in ipairs(others()) do
			local l = lines[o.p]
			if not l then
				l = Drawing.new("Line")
				l.Thickness = 1.5
				lines[o.p] = l
			end
			local v, on = cam:WorldToViewportPoint(o.r.Position)
			l.Color = roleColor[F.roles.on and roleOf(o.p) or "innocent"]
			l.From = from
			l.To = Vector2.new(v.X, v.Y)
			l.Visible = on
		end
	end
end)

-- input
bind(uis.InputBegan, function(input, gp)
	-- F1 can come in as already handled by roblox, so check it before the gp guard
	if input.KeyCode == Enum.KeyCode.F1 and not uis:GetFocusedTextBox() then
		set(F.esp, not F.esp.on)
		return
	end
	if gp then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and F.clicktp.on and uis:IsKeyDown(Enum.KeyCode.LeftControl) then
		local r, cam = root(), workspace.CurrentCamera
		if r and cam then
			local m = uis:GetMouseLocation()
			local ray = cam:ViewportPointToRay(m.X, m.Y)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { lp.Character }
			local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
			if hit then r.CFrame = CFrame.new(hit.Position + Vector3.new(0, 4, 0)) end
		end
	end
	local k = input.KeyCode
	if k == Enum.KeyCode.RightBracket then
		cfg.fly = math.clamp(cfg.fly + 10, 20, 300)
		note("Fly speed " .. cfg.fly)
	elseif k == Enum.KeyCode.LeftBracket then
		cfg.fly = math.clamp(cfg.fly - 10, 20, 300)
		note("Fly speed " .. cfg.fly)
	end
	local hk = { [Enum.KeyCode.F2] = F.speed, [Enum.KeyCode.F3] = F.fly,
		[Enum.KeyCode.F4] = F.noclip, [Enum.KeyCode.F5] = F.coinesp, [Enum.KeyCode.F6] = F.alert }
	if hk[k] then set(hk[k], not hk[k].on) end
end)

-- actions
local acts = {}
local function act(name, fn) acts[#acts + 1] = { name, fn } end

local function tpTo(pos)
	local r = root()
	if r and pos then r.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) end
end

act("Teleport to Nearest Coin", function()
	local c = nearestOf(coins)
	if c then tpTo(c.Position) else note("No coin found") end
end)
act("Teleport to Dropped Gun", function()
	local g = nearestOf(guns)
	if g then tpTo(posOf(g)) else note("No gun drop right now") end
end)
local spawnIdx = 0
act("Teleport to Spawn (press again for next)", function()
	local list = {}
	for _, i in ipairs(workspace:GetDescendants()) do
		if i:IsA("SpawnLocation") then list[#list + 1] = i end
	end
	if #list == 0 then note("No spawn found") return end
	spawnIdx = spawnIdx % #list + 1
	tpTo(list[spawnIdx].Position)
	note(("Spawn %d of %d"):format(spawnIdx, #list))
end)
act("Teleport to Screen Center (mobile)", function()
	local cam, r = workspace.CurrentCamera, root()
	if not cam or not r then return end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { lp.Character }
	local ray = cam:ViewportPointToRay(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if hit then r.CFrame = CFrame.new(hit.Position + Vector3.new(0, 4, 0)) else note("Nothing in range") end
end)
act("Save Safe Spot", function()
	local r = root()
	if r then saved = r.CFrame note("Safe spot saved") end
end)
act("Return to Safe Spot", function()
	local r = root()
	if r and saved then r.CFrame = saved else note("Nothing saved") end
end)

local function spectate(p)
	local ph = p and p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	if ph then workspace.CurrentCamera.CameraSubject = ph note("Spectating " .. p.DisplayName) else note("Nobody to spectate") end
end
act("Spectate Murderer", function() local o = withRole("murderer") spectate(o and o.p) end)
act("Spectate Sheriff", function() local o = withRole("sheriff") spectate(o and o.p) end)
act("Spectate Next Player", function()
	local list = others()
	if #list == 0 then note("No other players") return end
	specIdx = specIdx % #list + 1
	spectate(list[specIdx].p)
end)
act("Stop Spectating", function()
	local h = hum()
	if h then workspace.CurrentCamera.CameraSubject = h end
end)
act("Rejoin Server", function() tps:TeleportToPlaceInstance(game.PlaceId, game.JobId, lp) end)
act("Server Hop (Low Population)", function()
	note("Looking for a server...")
	task.spawn(function()
		local ok, res = pcall(function()
			return http:JSONDecode(game:HttpGet(("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)))
		end)
		if not ok or type(res) ~= "table" or type(res.data) ~= "table" then note("Server list failed") return end
		local best
		for _, s in ipairs(res.data) do
			if s.id ~= game.JobId and s.playing and s.maxPlayers and s.playing < s.maxPlayers and s.playing < #plrs:GetPlayers() then
				if not best or s.playing < best.playing then best = s end
			end
		end
		if best then tps:TeleportToPlaceInstance(game.PlaceId, best.id, lp) else note("No emptier server found") end
	end)
end)
act("FPS Boost (one-way)", function()
	lighting.GlobalShadows = false
	pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
	for _, i in ipairs(workspace:GetDescendants()) do
		if i:IsA("ParticleEmitter") or i:IsA("Trail") or i:IsA("Smoke") or i:IsA("Fire") then i.Enabled = false end
	end
	for _, i in ipairs(lighting:GetChildren()) do
		if i:IsA("BloomEffect") or i:IsA("BlurEffect") or i:IsA("SunRaysEffect") or i:IsA("DepthOfFieldEffect") then i.Enabled = false end
	end
	note("FPS boost applied")
end)

local steppers = {}

local function saveCfg()
	if typeof(writefile) ~= "function" then note("No writefile on this executor") return end
	local d = { nums = {}, tog = {} }
	for _, k in ipairs(nums) do d.nums[k] = cfg[k] end
	for _, f in ipairs(order) do d.tog[f.name] = f.on end
	writefile(cfg.file, http:JSONEncode(d))
	note("Config saved")
end

local function loadCfg(silent)
	if typeof(isfile) ~= "function" or typeof(readfile) ~= "function" or not isfile(cfg.file) then
		if not silent then note("No saved config") end
		return
	end
	local ok, d = pcall(function() return http:JSONDecode(readfile(cfg.file)) end)
	if not ok or type(d) ~= "table" then if not silent then note("Config is corrupted") end return end
	for k, v in pairs(d.nums or {}) do
		if type(v) == "number" and table.find(nums, k) then cfg[k] = v end
	end
	for _, r in ipairs(steppers) do r() end
	for _, f in ipairs(order) do
		if d.tog and d.tog[f.name] ~= nil then set(f, d.tog[f.name] == true) end
	end
	if not silent then note("Config loaded") end
end

local function checkUpdate(silent)
	task.spawn(function()
		local ok, src = pcall(game.HttpGet, game, cfg.url)
		if not ok or type(src) ~= "string" then
			-- fallback, usually blocked on the client but harmless to try
			ok, src = pcall(function() return http:GetAsync(cfg.url) end)
		end
		if not ok or type(src) ~= "string" then
			if not silent then note("Update check isn't supported on this executor") end
			return
		end
		local v = src:match('version = "([%d%.]+)"')
		if v and v ~= cfg.version then
			note("Update available: v" .. v .. " (you have v" .. cfg.version .. ")")
		elseif not silent then
			note("You're on the latest version")
		end
	end)
end

act("Save Config", saveCfg)
act("Load Config", function() loadCfg(false) end)
act("Check for Updates", function() checkUpdate(false) end)
act("Copy Discord Invite", function()
	if typeof(setclipboard) == "function" then setclipboard(cfg.discord) note("Invite copied") else note(cfg.discord) end
end)

act("Run Diagnostics", function()
	local out = {}
	local function add(s) out[#out + 1] = s end
	local function yn(v) return v and "yes" or "NO" end
	local function count(t) local n = 0 for _ in pairs(t) do n += 1 end return n end
	add("crimson mm2 v" .. cfg.version .. " diagnostics")
	add("Drawing: " .. yn(drawing) .. " | setclipboard: " .. yn(typeof(setclipboard) == "function") ..
		" | writefile: " .. yn(typeof(writefile) == "function"))
	add("coins tracked: " .. count(coins) .. " | gun drops tracked: " .. count(guns))
	local c = nearestOf(coins)
	if c then add("nearest coin: " .. c:GetFullName()) end
	local g = nearestOf(guns)
	if g then add("nearest gun drop: " .. g:GetFullName()) end
	add("my role: " .. roleOf(lp))
	add("-- players (role | tools) --")
	for _, p in ipairs(plrs:GetPlayers()) do
		local tools = {}
		for _, box in ipairs({ p:FindFirstChildOfClass("Backpack"), p.Character }) do
			if box then
				for _, t in ipairs(box:GetChildren()) do
					if t:IsA("Tool") then tools[#tools + 1] = t.Name end
				end
			end
		end
		add(("%s | %s | %s"):format(p.Name, roleOf(p), #tools > 0 and table.concat(tools, ",") or "no tools"))
	end
	add("-- workspace top level --")
	local n = 0
	for _, i in ipairs(workspace:GetChildren()) do
		n += 1
		if n <= 30 then add(i.Name .. " [" .. i.ClassName .. "]") end
	end
	local report = table.concat(out, "\n")
	print(report)
	if typeof(setclipboard) == "function" then setclipboard(report) note("Diagnostics copied (also in F9)") else note("Diagnostics in F9 console") end
end)

local function unload()
	for _, f in ipairs(order) do set(f, false) end
	clearLines()
	for p in pairs(esp) do clearEsp(p) end
	for i in pairs(objEsp) do clearObj(i) end
	for _, c in ipairs(conns) do c:Disconnect() end
	table.clear(conns)
	if gui then gui:Destroy() end
	note("Unloaded")
end
act("Unload Script", unload)

-- ui
gui = Instance.new("ScreenGui")
gui.Name = "CrimsonMM2"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
if not pcall(function() gui.Parent = (typeof(gethui) == "function" and gethui()) or core end) or not gui.Parent then
	gui.Parent = lp:WaitForChild("PlayerGui")
end

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(280, 430)
main.Position = UDim2.new(0, 20, 0.5, -215)
main.BackgroundColor3 = Color3.fromRGB(22, 16, 18)
main.BorderSizePixel = 0
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

local accent = Color3.fromRGB(220, 40, 60)
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundColor3 = accent
title.BorderSizePixel = 0
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextScaled = true
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Crimson Softworks | MM2"
title.Parent = main
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(0, 34)
scroll.Size = UDim2.new(1, 0, 1, -38)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = main
local lay = Instance.new("UIListLayout", scroll)
lay.SortOrder = Enum.SortOrder.LayoutOrder
lay.Padding = UDim.new(0, 4)
lay.HorizontalAlignment = Enum.HorizontalAlignment.Center

local ord = 0
local function nxt()
	ord += 1
	return ord
end

do
	local drag, ds, sp
	bind(title.InputBegan, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			drag, ds, sp = true, i.Position, main.Position
		end
	end)
	bind(uis.InputChanged, function(i)
		if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - ds
			main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
		end
	end)
	bind(uis.InputEnded, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = false end
	end)
end

local heads = {}
local function sec(text)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -16, 0, 20)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 12
	l.TextColor3 = accent
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.LayoutOrder = nxt()
	l.Parent = scroll
	heads[#heads + 1] = l
end

local function styleBtn(b, parent)
	b.Size = parent == scroll and UDim2.new(1, -16, 0, 26) or UDim2.new(1, 0, 0, 26)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.Gotham
	b.TextSize = 13
	b.TextColor3 = Color3.new(1, 1, 1)
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
	b.LayoutOrder = nxt()
	b.Parent = parent
end

local function btn(text, fn, color, parent)
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = color or Color3.fromRGB(80, 40, 50)
	b.Text = text
	styleBtn(b, parent or scroll)
	bind(b.MouseButton1Click, fn)
	return b
end

local function tog(key)
	local f = F[key]
	local b = Instance.new("TextButton")
	styleBtn(b, scroll)
	f.refresh = function()
		b.Text = f.name .. ": " .. (f.on and "ON" or "OFF")
		b.BackgroundColor3 = f.on and Color3.fromRGB(40, 140, 70) or Color3.fromRGB(48, 40, 44)
	end
	f.refresh()
	bind(b.MouseButton1Click, function() set(f, not f.on) end)
end

local function step(text, key, inc, lo, hi)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -16, 0, 26)
	row.BackgroundColor3 = Color3.fromRGB(36, 28, 32)
	row.BorderSizePixel = 0
	row.LayoutOrder = nxt()
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)
	row.Parent = scroll
	local l = Instance.new("TextLabel", row)
	l.Size = UDim2.new(1, -60, 1, 0)
	l.Position = UDim2.fromOffset(8, 0)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Gotham
	l.TextSize = 13
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	local function refresh() l.Text = text .. ": " .. tostring(cfg[key]) end
	refresh()
	steppers[#steppers + 1] = refresh
	for i, d in ipairs({ -inc, inc }) do
		local b = Instance.new("TextButton", row)
		b.Size = UDim2.fromOffset(24, 20)
		b.Position = UDim2.new(1, i == 1 and -54 or -28, 0, 3)
		b.BackgroundColor3 = Color3.fromRGB(60, 48, 54)
		b.BorderSizePixel = 0
		b.Font = Enum.Font.GothamBold
		b.TextSize = 14
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = i == 1 and "-" or "+"
		bind(b.MouseButton1Click, function()
			cfg[key] = math.clamp(cfg[key] + d, lo, hi)
			refresh()
		end)
	end
end

local function box()
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, -16, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BackgroundTransparency = 1
	f.LayoutOrder = nxt()
	local fl = Instance.new("UIListLayout", f)
	fl.SortOrder = Enum.SortOrder.LayoutOrder
	fl.Padding = UDim.new(0, 4)
	f.Parent = scroll
	return f
end

local function clearBox(b)
	for _, c in ipairs(b:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
end

sec("MM2")
tog("roles") tog("gunesp") tog("coinesp") tog("arrow")
tog("alert") step("Alert Range", "alert", 5, 10, 100)
tog("rolenote")

sec("MOVEMENT")
tog("speed") step("Walk Speed", "speed", 4, 16, 200)
tog("jump") step("Jump Power", "jump", 5, 50, 300)
tog("infjump") tog("fly") step("Fly Speed", "fly", 10, 20, 300)
tog("noclip") tog("clicktp") tog("antivoid") tog("antiragdoll") tog("bhop")
tog("grav") step("Gravity", "grav", 20, 0, 400)

sec("VISUALS")
tog("esp") step("ESP Range (0 = any)", "espRange", 100, 0, 3000)
tog("tracers") tog("fullbright") tog("nofog")
tog("fovchg") step("FOV", "fov", 5, 40, 120)
tog("timelock") step("Time of Day", "clock", 1, 0, 24)
tog("zoom") tog("hidetag") tog("hud")

sec("UTILITY")
tog("antiafk") tog("autorejoin") tog("joinalerts")

sec("ACTIONS")
for _, a in ipairs(acts) do btn(a[1], a[2]) end

sec("WAYPOINTS")
local wpBox
local wpn = 0
btn("Save Waypoint Here", function()
	local r = root()
	if not r then return end
	wpn += 1
	local cf, n = r.CFrame, wpn
	btn("TP: Waypoint " .. n, function()
		local rr = root()
		if rr then rr.CFrame = cf end
	end, Color3.fromRGB(40, 90, 90), wpBox)
	note("Waypoint " .. n .. " saved")
end)
btn("Clear Waypoints", function() clearBox(wpBox) wpn = 0 end, Color3.fromRGB(110, 50, 50))
wpBox = box()

sec("PLAYERS")
local plBox
btn("Refresh Player List", function()
	clearBox(plBox)
	for _, p in ipairs(plrs:GetPlayers()) do
		if p ~= lp then
			btn("TP: " .. p.DisplayName, function()
				local r, pr = root(), p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if r and pr then r.CFrame = pr.CFrame * CFrame.new(0, 0, 4) end
			end, Color3.fromRGB(70, 60, 40), plBox)
			btn("Spectate: " .. p.DisplayName, function() spectate(p) end, Color3.fromRGB(50, 70, 50), plBox)
		end
	end
end)
plBox = box()

sec("MENU")
local themes = { Color3.fromRGB(220, 40, 60), Color3.fromRGB(80, 160, 255), Color3.fromRGB(80, 210, 120), Color3.fromRGB(255, 170, 0) }
local ti = 1
btn("Cycle Theme", function()
	ti = ti % #themes + 1
	accent = themes[ti]
	title.BackgroundColor3 = accent
	for _, l in ipairs(heads) do l.TextColor3 = accent end
end)

do
	local mb = Instance.new("TextButton", title)
	mb.Size = UDim2.fromOffset(28, 26)
	mb.Position = UDim2.new(1, -32, 0, 2)
	mb.BackgroundTransparency = 1
	mb.Font = Enum.Font.GothamBold
	mb.TextSize = 18
	mb.TextColor3 = Color3.new(1, 1, 1)
	mb.Text = "-"
	local small = false
	bind(mb.MouseButton1Click, function()
		small = not small
		scroll.Visible = not small
		main.Size = small and UDim2.fromOffset(280, 30) or UDim2.fromOffset(280, 430)
		mb.Text = small and "+" or "-"
	end)
end

if uis.TouchEnabled then
	local tb = Instance.new("TextButton", gui)
	tb.Size = UDim2.fromOffset(46, 46)
	tb.Position = UDim2.new(1, -56, 0.5, -23)
	tb.BackgroundColor3 = accent
	tb.BorderSizePixel = 0
	tb.Font = Enum.Font.GothamBold
	tb.TextSize = 12
	tb.TextColor3 = Color3.new(1, 1, 1)
	tb.Text = "MM2"
	Instance.new("UICorner", tb).CornerRadius = UDim.new(1, 0)
	bind(tb.MouseButton1Click, function() main.Visible = not main.Visible end)
end

bind(uis.InputBegan, function(i, gp)
	if not gp and i.KeyCode == Enum.KeyCode.RightShift then main.Visible = not main.Visible end
end)

loadCfg(true)
checkUpdate(true)
note("Crimson Softworks MM2 v" .. cfg.version .. " loaded | RightShift hides the menu")
