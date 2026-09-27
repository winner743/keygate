-- KeyGate | key menu + your script
local API_KEY    = "KGAPI-4182E0BSTMEG4GNGLR3R83RK"
local SHARE_LINK = "https://winner743.github.io/keygate/#g=eyJ0IjoiS2V5IiwiayI6IktHQVBJLTQxODJFMEJTVE1FRzRHTkdMUjNSODNSSyIsInkiOiJ0d29zdGVwIn0"

-- Your script (runs after a valid key)
local SCRIPT = [[
Print("7")
]]

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")

local KEY_FILE = "keygate_" .. string.sub(API_KEY, 7, 14) .. ".txt"
local KEY_EXPIRES_AT = 0                                  -- unix seconds; 0 = never expires

local function runScript()
	local compile = loadstring or load
	if not compile then
		warn("[KeyGate] loadstring is not available in this environment")
		return
	end
	local fn, err = compile(SCRIPT)
	if not fn then
		warn("[KeyGate] Script error: " .. tostring(err))
		return
	end
	task.spawn(fn)
end

-- key check (offline): same maths as the key generator on the website
local B36 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

local function mul32(a, b)
	local ah, al = math.floor(a / 65536), a % 65536
	local bh, bl = math.floor(b / 65536), b % 65536
	return ((ah * bl + al * bh) % 65536 * 65536 + al * bl) % 4294967296
end

local function hw(secret, data, salt)
	local s = secret .. "|" .. salt .. "|" .. data
	local h = 2166136261
	for i = 1, #s do
		h = mul32(bit32.bxor(h, string.byte(s, i)), 16777619)
	end
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 2246822507)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 3266489909)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

local function enc6(v)
	v = v % 2176782336
	local out = ""
	for _ = 1, 6 do
		local d = v % 36
		out = string.sub(B36, d + 1, d + 1) .. out
		v = math.floor(v / 36)
	end
	return out
end

local function dec36(s)
	local v = 0
	for i = 1, #s do
		local pos = string.find(B36, string.sub(s, i, i), 1, true)
		if not pos then return nil end
		v = v * 36 + (pos - 1)
	end
	return v
end

-- returns ok, message
local function verifyKey(input)
	local key = string.upper((string.gsub(tostring(input or ""), "%s", "")))
	if #key ~= 30 or not string.match(key, "^KFREE%-[A-Z0-9]+$") then
		return false, "Invalid key"
	end
	local body = string.sub(key, 7)
	local a = string.sub(body, 1, 12)
	local mac = string.sub(body, 13, 24)
	if enc6(hw(API_KEY, a, "1")) .. enc6(hw(API_KEY, a, "2")) ~= mac then
		return false, "Invalid key"
	end
	local masked = dec36(string.sub(a, 1, 7))
	if not masked then return false, "Invalid key" end
	local expMin = bit32.bxor(masked % 4294967296, hw(API_KEY, string.sub(a, 8, 12), "m"))
	if expMin ~= 0 and os.time() > expMin * 60 then
		return false, "Key expired"
	end
	return true, "Key accepted", expMin
end

local function readSaved()
	if isfile and readfile then
		local ok, res = pcall(function()
			if isfile(KEY_FILE) then return readfile(KEY_FILE) end
			return nil
		end)
		if ok and type(res) == "string" then return res end
	end
	return nil
end

local function writeSaved(key)
	if writefile then pcall(writefile, KEY_FILE, key) end
end

local function guiParent()
	local ok, ui = pcall(function() return gethui and gethui() end)
	if ok and ui then return ui end
	local ok2, core = pcall(function() return game:GetService("CoreGui") end)
	if ok2 and core then return core end
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Shared "modern blue" palette, used by both the key menu and the HUD
local COL = {
	bg          = Color3.fromRGB(22, 27, 46),
	field       = Color3.fromRGB(14, 18, 32),
	line        = Color3.fromRGB(42, 50, 82),
	text        = Color3.fromRGB(233, 237, 249),
	muted       = Color3.fromRGB(143, 153, 187),
	accent      = Color3.fromRGB(107, 124, 255),
	accentHover = Color3.fromRGB(130, 144, 255),
	dark        = Color3.fromRGB(29, 36, 64),
	darkHover   = Color3.fromRGB(37, 45, 80),
	good        = Color3.fromRGB(61, 220, 151),
	bad         = Color3.fromRGB(255, 92, 122),
	warn        = Color3.fromRGB(255, 196, 77),
	fps         = Color3.fromRGB(107, 124, 255),
	cpu         = Color3.fromRGB(168, 130, 255),
	gamestat    = Color3.fromRGB(61, 220, 151),
	userstat    = Color3.fromRGB(255, 196, 77),
	timestat    = Color3.fromRGB(255, 92, 122),
}

local function corner(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = obj
	return c
end

local function stroke(obj, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
	return s
end

-- Info HUD, shown top-right once a valid key is active. Not draggable, on purpose.
local function openHud()
	local RunService = game:GetService("RunService")
	local Stats      = game:GetService("Stats")
	local MarketplaceService = game:GetService("MarketplaceService")

	local gui = Instance.new("ScreenGui")
	gui.Name = "KeyGateHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 998
	local parent = guiParent()
	local old = parent:FindFirstChild("KeyGateHUD")
	if old then old:Destroy() end
	local okParent = pcall(function() gui.Parent = parent end)
	if not okParent then gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -14, 0, 14)
	panel.Size = UDim2.new(0, 222, 0, 178)
	panel.BackgroundColor3 = COL.bg
	panel.BorderSizePixel = 0
	panel.Active = false                                      -- not a drag surface
	panel.Parent = gui
	corner(panel, 16)
	stroke(panel, COL.line, 1.5)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 14, 0, 10)
	title.Size = UDim2.new(1, -28, 0, 20)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextColor3 = COL.text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "KeyGate"
	title.Parent = panel

	local rows = Instance.new("Frame")
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.new(0, 12, 0, 36)
	rows.Size = UDim2.new(1, -24, 1, -46)
	rows.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = rows

	local valueLabels = {}
	local function addRow(order, label, accent)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 26)
		row.BackgroundColor3 = COL.field
		row.LayoutOrder = order
		row.Parent = rows
		corner(row, 8)
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.new(0, 8, 0.5, 0)
		dot.Size = UDim2.new(0, 6, 0, 6)
		dot.BackgroundColor3 = accent
		dot.BorderSizePixel = 0
		dot.Parent = row
		corner(dot, 3)
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Position = UDim2.new(0, 20, 0, 0)
		lbl.Size = UDim2.new(0.55, -20, 1, 0)
		lbl.Font = Enum.Font.Gotham
		lbl.TextSize = 12
		lbl.TextColor3 = COL.muted
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Text = label
		lbl.Parent = row
		local val = Instance.new("TextLabel")
		val.BackgroundTransparency = 1
		val.Position = UDim2.new(0.55, 0, 0, 0)
		val.Size = UDim2.new(0.45, -8, 1, 0)
		val.Font = Enum.Font.GothamBold
		val.TextSize = 12
		val.TextColor3 = accent
		val.TextXAlignment = Enum.TextXAlignment.Right
		val.TextTruncate = Enum.TextTruncate.AtEnd
		val.Text = "..."
		val.Parent = row
		valueLabels[label] = val
		return val
	end

	local vFps  = addRow(1, "FPS", COL.fps)
	local vCpu  = addRow(2, "CPU", COL.cpu)
	local vGame = addRow(3, "GAME", COL.gamestat)
	local vUser = addRow(4, "PLAYER", COL.userstat)
	local vTime = addRow(5, "KEY TIME", COL.timestat)

	-- player name
	vUser.Text = Players.LocalPlayer.Name

	-- game name: try the marketplace title first, fall back to game.Name / PlaceId
	vGame.Text = "..."
	task.spawn(function()
		local ok, info = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
		if ok and info and info.Name then
			vGame.Text = info.Name
		elseif game.Name ~= "" then
			vGame.Text = game.Name
		else
			vGame.Text = "Place " .. tostring(game.PlaceId)
		end
	end)

	-- FPS: smoothed frame counter
	local frames, fpsClock = 0, os.clock()
	local fpsConn = RunService.RenderStepped:Connect(function()
		frames = frames + 1
		local now = os.clock()
		if now - fpsClock >= 0.5 then
			vFps.Text = tostring(math.floor(frames / (now - fpsClock) + 0.5))
			frames, fpsClock = 0, now
		end
	end)

	-- CPU: best-effort, from Roblox's own performance stats where available
	local function readCpu()
		local ok, ms = pcall(function()
			local perf = Stats:FindFirstChild("PerformanceStats")
			local item = perf and perf:FindFirstChild("CPU (Main)")
			return item and item:GetValue()
		end)
		if ok and ms then return string.format("%.0f%%", math.clamp(ms / 16.67 * 100, 0, 999)) end
		return "N/A"
	end

	-- key time remaining, ticks once a second
	local function formatRemaining()
		if KEY_EXPIRES_AT <= 0 then return "No limit" end
		local left = math.max(0, math.floor(KEY_EXPIRES_AT - os.time()))
		if left <= 0 then return "Expired" end
		local h = math.floor(left / 3600)
		local m = math.floor((left % 3600) / 60)
		local sSec = left % 60
		if h > 0 then return string.format("%dh %02dm", h, m) end
		return string.format("%dm %02ds", m, sSec)
	end

	task.spawn(function()
		while gui.Parent do
			vCpu.Text = readCpu()
			vTime.Text = formatRemaining()
			task.wait(1)
		end
		pcall(function() fpsConn:Disconnect() end)
	end)

end

local function openMenu()
	local alive = true
	local conns = {}

	local gui = Instance.new("ScreenGui")
	gui.Name = "KeyGateMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 999
	local parent = guiParent()
	local old = parent:FindFirstChild("KeyGateMenu")
	if old then old:Destroy() end
	local okParent = pcall(function() gui.Parent = parent end)
	if not okParent then gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui
	TweenService:Create(backdrop, TweenInfo.new(0.35), { BackgroundTransparency = 0.55 }):Play()

	local menu = Instance.new("Frame")
	menu.Name = "Menu"
	menu.AnchorPoint = Vector2.new(0.5, 0.5)
	menu.Position = UDim2.new(0.5, 0, 0.5, 0)
	menu.Size = UDim2.new(0, 290, 0, 150)
	menu.BackgroundColor3 = COL.bg
	menu.BorderSizePixel = 0
	menu.ClipsDescendants = true
	menu.Parent = gui
	corner(menu, 16)
	local menuStroke = stroke(menu, COL.line, 1.5)
	TweenService:Create(menu, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, 340, 0, 214) }):Play()

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 0, 0, 14)
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 28
	title.TextColor3 = COL.text
	title.RichText = true
	title.Text = ""
	title.Parent = menu

	local box = Instance.new("TextBox")
	box.Name = "KeyBox"
	box.Position = UDim2.new(0, 20, 0, 70)
	box.Size = UDim2.new(1, -40, 0, 44)
	box.BackgroundColor3 = COL.field
	box.BorderSizePixel = 0
	box.Font = Enum.Font.Gotham
	box.TextSize = 15
	box.TextColor3 = COL.text
	box.PlaceholderText = "Enter your key..."
	box.PlaceholderColor3 = Color3.fromRGB(92, 102, 136)
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Parent = menu
	corner(box, 10)
	local boxStroke = stroke(box, COL.line, 1)

	local function makeButton(text, pos, size, base, hover)
		local b = Instance.new("TextButton")
		b.Position = pos
		b.Size = size
		b.BackgroundColor3 = base
		b.BorderSizePixel = 0
		b.AutoButtonColor = false
		b.Font = Enum.Font.GothamBold
		b.TextSize = 15
		b.TextColor3 = COL.text
		b.Text = text
		b.Parent = menu
		corner(b, 10)
		b.MouseEnter:Connect(function()
			TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = hover }):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = base }):Play()
		end)
		return b
	end
	local confirmBtn = makeButton("Confirm", UDim2.new(0, 20, 0, 126), UDim2.new(0.5, -25, 0, 42), COL.accent, COL.accentHover)
	local getBtn = makeButton("Get key", UDim2.new(0.5, 5, 0, 126), UDim2.new(0.5, -25, 0, 42), COL.dark, COL.darkHover)

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.new(0, 20, 0, 176)
	status.Size = UDim2.new(1, -40, 0, 22)
	status.Font = Enum.Font.Gotham
	status.TextSize = 13
	status.TextColor3 = COL.muted
	status.Text = ""
	status.Parent = menu

	local function setStatus(text, color)
		status.Text = text
		status.TextColor3 = color or COL.muted
	end

	-- "Key menu" types in, blinks, then deletes. One full cycle every 4 seconds.
	local HIDDEN = '<font transparency="1">|</font>'
	local function render(text, cursor)
		return text .. (cursor and "|" or HIDDEN)
	end
	task.spawn(function()
		local full = "Key menu"
		while alive do
			local t0 = tick()
			for i = 1, #full do
				if not alive then return end
				title.Text = render(string.sub(full, 1, i), true)
				task.wait(0.08)
			end
			local on = true
			while alive and tick() < t0 + 3.2 do
				title.Text = render(full, on)
				on = not on
				task.wait(math.min(0.4, math.max(0.05, t0 + 3.2 - tick())))
			end
			for i = #full - 1, 0, -1 do
				if not alive then return end
				title.Text = render(string.sub(full, 1, i), true)
				task.wait(0.05)
			end
			local left = t0 + 4 - tick()
			if left > 0 then task.wait(left) end
		end
	end)

	-- wrong key: the screen flashes a little red and the menu shakes left and right
	local shaking = false
	local function wrongKey()
		if shaking then return end
		shaking = true
		TweenService:Create(backdrop, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(120, 10, 25), BackgroundTransparency = 0.35 }):Play()
		TweenService:Create(menuStroke, TweenInfo.new(0.1), { Color = COL.bad }):Play()
		TweenService:Create(boxStroke, TweenInfo.new(0.1), { Color = COL.bad }):Play()
		local base = menu.Position
		for _, dx in ipairs({ -14, 14, -11, 11, -7, 7, -3, 3, 0 }) do
			local tw = TweenService:Create(menu, TweenInfo.new(0.04, Enum.EasingStyle.Sine), {
				Position = UDim2.new(base.X.Scale, base.X.Offset + dx, base.Y.Scale, base.Y.Offset),
			})
			tw:Play()
			tw.Completed:Wait()
		end
		menu.Position = base
		TweenService:Create(backdrop, TweenInfo.new(0.6), { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55 }):Play()
		TweenService:Create(menuStroke, TweenInfo.new(0.6), { Color = COL.line }):Play()
		TweenService:Create(boxStroke, TweenInfo.new(0.6), { Color = COL.line }):Play()
		shaking = false
	end

	local function accepted(clean)
		alive = false
		writeSaved(clean)
		setStatus("Key accepted", COL.good)
		TweenService:Create(menuStroke, TweenInfo.new(0.2), { Color = COL.good }):Play()
		task.wait(0.6)
		local tw = TweenService:Create(menu, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Size = UDim2.new(0, 0, 0, 0) })
		TweenService:Create(backdrop, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		tw:Play()
		tw.Completed:Wait()
		for _, c in ipairs(conns) do
			pcall(function() c:Disconnect() end)
		end
		gui:Destroy()
		openHud()
		runScript()
	end

	local busy = false
	local function submit()
		if busy or not alive then return end
		local clean = string.upper((string.gsub(box.Text, "%s", "")))
		if clean == "" then
			setStatus("Enter your key first", COL.warn)
			return
		end
		busy = true
		confirmBtn.Text = "Checking..."
		task.spawn(function()
			local ok, msg, expMin = verifyKey(clean)
			busy = false
			confirmBtn.Text = "Confirm"
			if ok then
				KEY_EXPIRES_AT = (expMin and expMin > 0) and (expMin * 60) or 0
				accepted(clean)
			else
				setStatus(msg, COL.bad)
				wrongKey()
			end
		end)
	end

	confirmBtn.Activated:Connect(submit)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then submit() end
	end)
	box.Focused:Connect(function()
		TweenService:Create(boxStroke, TweenInfo.new(0.15), { Color = COL.accent }):Play()
	end)
	box.FocusLost:Connect(function()
		TweenService:Create(boxStroke, TweenInfo.new(0.15), { Color = COL.line }):Play()
	end)

	-- Get key: copies the share link automatically
	getBtn.Activated:Connect(function()
		local copyFn = setclipboard or toclipboard or set_clipboard or (Clipboard and Clipboard.set)
		local ok = false
		if copyFn then ok = pcall(copyFn, SHARE_LINK) end
		if ok then
			getBtn.Text = "Copied!"
			setStatus("Link copied. Open it in your browser.", COL.good)
			task.delay(2, function()
				if alive then getBtn.Text = "Get key" end
			end)
		else
			box.Text = SHARE_LINK
			setStatus("Copy the link from the box.", COL.warn)
		end
	end)
end

task.spawn(function()
	local saved = readSaved()
	if saved then
		local ok, _, expMin = verifyKey(saved)
		if ok then
			KEY_EXPIRES_AT = (expMin and expMin > 0) and (expMin * 60) or 0
			openHud()
			runScript()
			return
		end
	end
	openMenu()
end)
