--[[
	Rivals Hub
	Rivals · WindUI panel
	Open/close the panel: RightShift (changeable in Settings)
]]

-- Address of an optional key server (anonymous health pings only), without a
-- trailing slash. Keys are issued and checked by Junkie.
local KEY_SERVER = ""

-- Lua line queued for the next place (see autoexec.luau): runs the hub again
-- after a teleport. Dev builds override it with a readfile of a local copy.
local AUTOEXEC_SOURCE = [==[]==]

-- How the key screen looks for this hub.
local KEY_GATE = {
	title = "Rivals Hub",
	subtitle = "Key System  ·  Rivals",
	icon = "🎯",
	folder = "RivalsHub",
	prefix = "RV",
}

local env = (getgenv and getgenv()) or _G

-- After a teleport the queued copy starts before the place has finished
-- loading: wait for the game, the local player and its scripts and GUI, or
-- every part fails on a nil LocalPlayer.
if not game:IsLoaded() then
	game.Loaded:Wait()
end
do
	local Players = game:GetService("Players")
	while not Players.LocalPlayer do
		task.wait(0.1)
	end
	local lp = Players.LocalPlayer
	lp:WaitForChild("PlayerGui", 30)
	lp:WaitForChild("PlayerScripts", 30)
end

-- Running the hub again replaces the copy that is already running.
if env.RV_Stop then
	pcall(env.RV_Stop)
end

-- Every run starts from scratch with the features off.
if env.RV_Hub then
	env.RV_Hub.enabled = false
	env.RV_Hub.runId = -1
end
env.RV_Hub = { enabled = false }

local function newState()
	local conns, cleanups, running = {}, {}, true
	local S = {}
	function S.connect(signal, fn)
		local c = signal:Connect(fn)
		table.insert(conns, c)
		return c
	end
	function S.onCleanup(fn)
		table.insert(cleanups, fn)
	end
	function S.alive()
		return running
	end
	local stopped = false
	function S._stop()
		if stopped then
			return
		end
		stopped = true
		running = false
		for _, c in ipairs(conns) do
			pcall(function()
				c:Disconnect()
			end)
		end
		for i = #cleanups, 1, -1 do
			pcall(cleanups[i])
		end
	end
	return S
end

local parts = {}

local function run(name, chunk)
	local S = newState()
	table.insert(parts, S)
	local ok, err = pcall(chunk, S)
	if not ok then
		warn("[Rivals Hub] " .. name .. " failed: " .. tostring(err))
	end
	return S
end

env.RV_Stop = function()
	for i = #parts, 1, -1 do
		parts[i]._stop()
	end
	table.clear(parts)
end

-- The features and the panel, apart from the key gate, so the gate can lock
-- the hub (key expired or revoked) and start it again after a new key.
local hubParts = {}

local function stopHub()
	for i = #hubParts, 1, -1 do
		hubParts[i]._stop()
	end
	table.clear(hubParts)
	if env.RV_Hub then
		env.RV_Hub.enabled = false
	end
	-- loader build: the hub came from a hosted script, which replaced RV_Stop
	if env.RV_HostedLoaded and env.RV_Stop then
		env.RV_HostedLoaded = nil
		pcall(env.RV_Stop)
	end
end

local function startHub()
	getgenv().SCRIPT_KEY = env.RV_ActiveKey
	local ok, err = pcall(function()
		loadstring(game:HttpGet("https://api.jnkie.com/api/v1/luascripts/public/13639d57a8c2c0dde96cb4017c9748bb6d35e0d9d8749065926cf9b943543bc6/download"))()
	end)
	if ok then
		env.RV_HostedLoaded = true
	else
		warn("[Rivals Hub] could not start the script: " .. tostring(err))
	end

end

-- ===== Key gate (key_gate_junkie.luau) =====
local JUNKIE_CFG = { service = 114434, provider = "Rivals Hub", keyLink = "https://jnkie.com/get-key/rival-hub" }
run("Key gate", function(STATE)
-- Key screen shown before the hub starts, styled after the WindUI Dark theme
-- the panel opens with. It checks the key against the key server
-- (keyserver/worker.js), starts the hub once the key is valid, and keeps
-- re-checking it while the hub runs: if the server says the key is no longer
-- valid (expired, or used on too many devices) the hub is closed and the key
-- screen comes back. A valid key is remembered in Ticketless/key.txt.
--
-- Bundled by build_hub.sh: runs as run("Key gate", function(STATE) ... end),
-- with KEY_SERVER, startHub and stopHub defined by the bundle. Another hub
-- (apex/build.sh) also defines KEY_GATE to put its own name on the screen.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local BRAND = {
	title = "Ticketless",
	subtitle = "Key System  ·  Fraude Express",
	icon = "🎫",
	folder = "Ticketless",
	prefix = "FE",
}
for k, v in pairs(type(KEY_GATE) == "table" and KEY_GATE or {}) do
	BRAND[k] = v
end

pcall(function()
	if not isfolder(BRAND.folder) then
		makefolder(BRAND.folder)
	end
end)
local KEY_FILE = BRAND.folder .. "/key.txt"
local CHECK_EVERY = 900 -- seconds between re-checks (Junkie asks not to poll)

-- Keys are issued and checked by Junkie (jnkie.com). KEY_SERVER, when set, is
-- only used for the anonymous health pings below.
local JUNKIE = {
	service = 113034, -- "Ticketless Hub" service id
	identifier = "1233349", -- the service owner's Junkie user id
	provider = "Ticketless Hub", -- checkpoint provider (used by get_key_link)
	keyLink = "https://jnkie.com/get-key/ticketlesshub",
	library = "https://jnkie.com/sdk/library.lua",
}
-- Another hub (apex/build.sh) defines JUNKIE_CFG to use its own service.
for k, v in pairs(type(JUNKIE_CFG) == "table" and JUNKIE_CFG or {}) do
	JUNKIE[k] = v
end

-- JUNKIE.alt (optional): a second Junkie service with another checkpoint
-- provider; a key from either service opens the hub.
local ALT = type(JUNKIE.alt) == "table" and JUNKIE.alt or nil

local junkieLib
local function loadJunkie()
	if junkieLib then
		return junkieLib
	end
	local ok, lib = pcall(function()
		return loadstring(game:HttpGet(JUNKIE.library))()
	end)
	if ok and type(lib) == "table" and lib.check_key then
		lib.service = JUNKIE.service
		lib.identifier = JUNKIE.identifier
		lib.provider = JUNKIE.provider
		junkieLib = lib
		return lib
	end
	return nil
end

-- Anonymous health ping (event + short label, e.g. executor name or a missing
-- function) so the server can tell whether the key screen really appears.
local pingSeq = 0
local function ping(event, detail)
	-- No stats server configured (Ticketless uses Junkie only): send nothing.
	if KEY_SERVER == nil or KEY_SERVER == "" then
		return
	end
	task.spawn(function()
		pcall(function()
			pingSeq += 1
			local x = tostring(detail or ""):gsub("[^%w _%.,%+%-]", ""):sub(1, 60)
			game:HttpGet(
				KEY_SERVER
					.. "/ping?e="
					.. event
					.. "&x="
					.. game:GetService("HttpService"):UrlEncode(x)
					.. "&_="
					.. pingSeq
					.. "-"
					.. math.floor(os.clock() * 1000)
			)
		end)
	end)
end

do
	local name = "unknown"
	pcall(function()
		if identifyexecutor then
			name = tostring((identifyexecutor())):sub(1, 24)
		end
	end)
	local missing = {}
	for _, fn in ipairs({ "setclipboard", "isfile", "readfile", "writefile", "gethui" }) do
		local ok, v = pcall(function()
			return getfenv()[fn] or (getgenv and getgenv()[fn])
		end)
		if not (ok and v) then
			table.insert(missing, fn)
		end
	end
	ping("gate_start", name)
	if #missing > 0 then
		ping("gate_error", "missing " .. table.concat(missing, ",") .. " on " .. name)
	end
end

local function deviceId()
	local raw = ""
	pcall(function()
		raw = tostring(gethwid and gethwid() or "")
	end)
	raw = raw:gsub("[^%w_%-%.:]", ""):sub(1, 128)
	if #raw < 3 then
		raw = "U" .. Players.LocalPlayer.UserId
	end
	return raw
end

local HWID = deviceId()

-- Returns valid, message, expiresAt (ms). message is "unreachable" when the
-- server could not be asked at all, which is never treated as a refusal.
-- Junkie does not return the expiry time, so expiresAt is always nil here and
-- the periodic re-check below is what notices an expired key.
local function checkOne(key, service, provider)
	local lib = loadJunkie()
	if not lib then
		return false, "unreachable"
	end
	lib.service = service
	lib.provider = provider
	local ok, res = pcall(lib.check_key, key)
	if not ok or type(res) ~= "table" then
		return false, "unreachable"
	end
	if res.valid == true then
		return true, "ok", nil
	end
	-- A rate limit or a network problem is not a refusal of the key.
	local err = tostring(res.error or "")
	if err:upper():find("RATE") or err:upper():find("NETWORK") or err:upper():find("TIMEOUT") then
		return false, "unreachable"
	end
	return false, "invalid or expired key"
end

local function checkKey(key)
	local valid, message, expiresAt = checkOne(key, JUNKIE.service, JUNKIE.provider)
	if valid or not ALT or message == "unreachable" then
		return valid, message, expiresAt
	end
	-- not a key of the first service: it may be one of the second
	local valid2, message2, expiresAt2 = checkOne(key, ALT.service, ALT.provider or JUNKIE.provider)
	if valid2 then
		return true, "ok", expiresAt2
	end
	if message2 == "unreachable" then
		return false, "unreachable"
	end
	return false, message
end

local function readSaved()
	local ok, key = pcall(function()
		return isfile(KEY_FILE) and readfile(KEY_FILE) or nil
	end)
	return ok and key and key:match("^%s*(.-)%s*$") or nil
end

local function save(key)
	pcall(function()
		writefile(KEY_FILE, key)
	end)
end

local function forget()
	pcall(function()
		if isfile(KEY_FILE) then
			delfile(KEY_FILE)
		end
	end)
end

local function nowMs()
	return DateTime.now().UnixTimestampMillis
end

-- What to tell the player when a key is refused.
local function refusalText(message)
	if message == "device limit reached" or message == "key belongs to another device" then
		return "This key is already used on too many devices"
	elseif message == "invalid or expired key" then
		return "Your key expired — get a new one"
	end
	return "Your key is no longer valid"
end

---------------------------------------------------------------------------
-- Session: the hub runs while the key stays valid
---------------------------------------------------------------------------

local env = (getgenv and getgenv()) or _G
local activeKey, activeExpires
local showGate -- defined below

local function startSession(key, expiresAt)
	save(key)
	activeKey, activeExpires = key, tonumber(expiresAt)
	env.FE_KeyExpiresAt = activeExpires
	env.FE_KeyMode = "junkie"
	env.RV_ActiveKey = key -- read by a loader build that hands the key to a Junkie-hosted script
	startHub()
end

local function lock(message)
	activeKey, activeExpires = nil, nil
	env.FE_KeyExpiresAt = nil
	stopHub()
	forget()
	showGate(refusalText(message))
end

-- Re-check every CHECK_EVERY seconds, and right when the key is due to expire.
task.spawn(function()
	local nextCheck = os.clock() + CHECK_EVERY
	while STATE.alive() do
		task.wait(1)
		if activeKey then
			local dueToExpire = activeExpires and nowMs() >= activeExpires
			if dueToExpire or os.clock() >= nextCheck then
				nextCheck = os.clock() + CHECK_EVERY
				local key = activeKey
				local valid, message, expiresAt = checkKey(key)
				if STATE.alive() and activeKey == key then
					if valid then
						activeExpires = tonumber(expiresAt) or activeExpires
						env.FE_KeyExpiresAt = activeExpires
					elseif message ~= "unreachable" then
						lock(message)
					end
				end
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Key window (WindUI Dark look)
---------------------------------------------------------------------------

local getKeyUrl = JUNKIE.keyLink
local getWorkinkUrl = JUNKIE.keyLink

local C = {
	backdrop = Color3.new(0, 0, 0),
	card = Color3.fromRGB(16, 16, 18),
	field = Color3.fromRGB(26, 26, 30),
	button = Color3.fromRGB(34, 34, 38),
	buttonHover = Color3.fromRGB(44, 44, 50),
	primary = Color3.fromRGB(245, 245, 247),
	primaryHover = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(245, 245, 247),
	dim = Color3.fromRGB(161, 161, 170),
	faint = Color3.fromRGB(113, 113, 122),
	line = Color3.new(1, 1, 1),
	accent = Color3.fromRGB(59, 130, 246),
	ok = Color3.fromRGB(74, 222, 128),
	err = Color3.fromRGB(248, 113, 113),
}

local FONT = "rbxasset://fonts/families/BuilderSans.json"
local MONO = "rbxasset://fonts/families/RobotoMono.json"

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function tween(inst, t, goal)
	local tw = TweenService:Create(inst, TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local currentGui
STATE.onCleanup(function()
	if currentGui then
		currentGui:Destroy()
	end
end)

-- notice: optional line explaining why the key is being asked again.
function showGate(notice)
	if currentGui then
		currentGui:Destroy()
	end

	local root = (gethui and gethui()) or game:GetService("CoreGui")
	local gui = new("ScreenGui", {
		Name = BRAND.folder .. "_KeyGate",
		ResetOnSpawn = false,
		DisplayOrder = 100,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	currentGui = gui

	local backdrop = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.backdrop,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, gui)

	-- CanvasGroup fades the whole card in and out as one piece.
	local card = new("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(420, ALT and 372 or 318),
		BackgroundColor3 = C.card,
		GroupTransparency = 1,
		BorderSizePixel = 0,
	}, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 18) }, card)
	new("UIStroke", { Color = C.line, Transparency = 0.9, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	local scale = new("UIScale", { Scale = 0.96 }, card)

	local function text(props, parent)
		local t = new("TextLabel", {
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextWrapped = true,
			TextColor3 = C.text,
			TextSize = 14,
			FontFace = Font.new(FONT, Enum.FontWeight.Medium),
		}, parent or card)
		for k, v in pairs(props) do
			t[k] = v
		end
		return t
	end

	-- Header --------------------------------------------------------------
	local icon = new("Frame", {
		Position = UDim2.fromOffset(24, 22),
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = C.button,
		BorderSizePixel = 0,
	}, card)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, icon)
	new("UIStroke", { Color = C.line, Transparency = 0.9 }, icon)
	text({ Size = UDim2.fromScale(1, 1), Text = BRAND.icon, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center }, icon)

	text({
		Position = UDim2.fromOffset(78, 22),
		Size = UDim2.new(1, -140, 0, 22),
		Text = BRAND.title,
		TextSize = 20,
		FontFace = Font.new(FONT, Enum.FontWeight.Bold),
	})
	text({
		Position = UDim2.fromOffset(78, 44),
		Size = UDim2.new(1, -140, 0, 18),
		Text = BRAND.subtitle,
		TextSize = 13,
		TextColor3 = C.dim,
	})

	local close = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 18),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = C.button,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	}, card)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, close)
	-- Two crossed bars: the ✕ glyph is missing from the game's fonts.
	for _, angle in ipairs({ 45, -45 }) do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(14, 2),
			Rotation = angle,
			BackgroundColor3 = C.dim,
			BorderSizePixel = 0,
		}, close)
	end
	close.MouseEnter:Connect(function()
		tween(close, 0.15, { BackgroundTransparency = 0 })
	end)
	close.MouseLeave:Connect(function()
		tween(close, 0.15, { BackgroundTransparency = 1 })
	end)

	new("Frame", {
		Position = UDim2.fromOffset(0, 82),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.line,
		BackgroundTransparency = 0.92,
		BorderSizePixel = 0,
	}, card)

	-- Body ----------------------------------------------------------------
	text({
		Position = UDim2.fromOffset(24, 98),
		Size = UDim2.new(1, -48, 0, 34),
		Text = notice or (ALT and "Pick a key link (your browser opens on the key page), finish the checkpoint, then paste your key below." or "Press Get Key (your browser opens on the key page), finish one checkpoint, then paste your key below."),
		TextSize = 13,
		TextColor3 = notice and C.err or C.dim,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	local field = new("Frame", {
		Position = UDim2.fromOffset(24, 142),
		Size = UDim2.new(1, -48, 0, 46),
		BackgroundColor3 = C.field,
		BorderSizePixel = 0,
	}, card)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, field)
	local fieldStroke = new("UIStroke", { Color = C.line, Transparency = 0.9, Thickness = 1 }, field)
	local box = new("TextBox", {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -28, 1, 0),
		BackgroundTransparency = 1,
		PlaceholderText = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
		PlaceholderColor3 = C.faint,
		Text = "",
		TextColor3 = C.text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		FontFace = Font.new(MONO, Enum.FontWeight.Medium),
	}, field)
	box.Focused:Connect(function()
		tween(fieldStroke, 0.2, { Color = C.accent, Transparency = 0.2 })
	end)
	box.FocusLost:Connect(function()
		tween(fieldStroke, 0.2, { Color = C.line, Transparency = 0.9 })
	end)

	local function button(label, x, primary, y, full)
		local b = new("TextButton", {
			Position = UDim2.new(x, x == 0 and 24 or 6, 0, y or 202),
			Size = full and UDim2.new(1, -48, 0, 44) or UDim2.new(0.5, -30, 0, 44),
			BackgroundColor3 = primary and C.primary or C.button,
			Text = "",
			AutoButtonColor = false,
			BorderSizePixel = 0,
		}, card)
		new("UICorner", { CornerRadius = UDim.new(0, 12) }, b)
		if not primary then
			new("UIStroke", { Color = C.line, Transparency = 0.9, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		end
		local t = text({
			Size = UDim2.fromScale(1, 1),
			Text = label,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = primary and Color3.fromRGB(10, 10, 12) or C.text,
			FontFace = Font.new(FONT, Enum.FontWeight.Bold),
		}, b)
		b.MouseEnter:Connect(function()
			tween(b, 0.15, { BackgroundColor3 = primary and C.primaryHover or C.buttonHover })
		end)
		b.MouseLeave:Connect(function()
			tween(b, 0.15, { BackgroundColor3 = primary and C.primary or C.button })
		end)
		return b, t
	end

	local getKeyBtn = button("Get Key", 0, false)
	local altKeyBtn = ALT and button(ALT.label or "Get Key (Lootlabs)", 0.5, false) or nil
	local checkBtn, checkLabel
	if ALT then
		checkBtn, checkLabel = button("Check Key", 0, true, 256, true)
	else
		checkBtn, checkLabel = button("Check Key", 0.5, true)
	end
	local rowShift = ALT and 54 or 0

	local status = text({
		Position = UDim2.fromOffset(24, 254 + rowShift),
		Size = UDim2.new(1, -48, 0, 20),
		Text = "",
		TextSize = 13,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	text({
		Position = UDim2.fromOffset(24, 282 + rowShift),
		Size = UDim2.new(1, -48, 0, 18),
		Text = "Keys last 24 hours and work only on this device",
		TextSize = 12,
		TextColor3 = C.faint,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local function setStatus(msg, kind)
		status.Text = msg
		local color = C.dim
		if kind == "error" then
			color = C.err
		elseif kind == "ok" then
			color = C.ok
		end
		status.TextColor3 = color
	end

	-- Open / close --------------------------------------------------------
	local function closeGate(then_)
		tween(backdrop, 0.25, { BackgroundTransparency = 1 })
		tween(scale, 0.25, { Scale = 0.96 })
		tween(card, 0.25, { GroupTransparency = 1 }).Completed:Wait()
		gui:Destroy()
		if currentGui == gui then
			currentGui = nil
		end
		if then_ then
			then_()
		end
	end

	close.MouseButton1Click:Connect(function()
		closeGate()
	end)

	local function openKeyLink(url)
		-- The link always goes to the clipboard, as the fallback, and the
		-- browser is sent to it.
		local copied = pcall(function()
			setclipboard(url)
		end)
		local opened = pcall(function()
			game:GetService("GuiService"):OpenBrowserWindow(url)
		end)
		if opened then
			ping("open_browser")
			setStatus(copied and "Opening your browser… (link also copied)" or "Opening your browser…", "ok")
		elseif copied then
			setStatus("Link copied — paste it in your browser (Ctrl+V)", "ok")
		else
			setStatus(url, "info")
		end
	end

	getKeyBtn.MouseButton1Click:Connect(function()
		openKeyLink(getWorkinkUrl)
	end)
	if altKeyBtn then
		altKeyBtn.MouseButton1Click:Connect(function()
			openKeyLink(ALT.keyLink)
		end)
	end

	local checking = false
	local function tryKey()
		if checking then
			return
		end
		-- Junkie keys are lowercase UUIDs: leave the case as typed.
		local key = box.Text:match("^%s*(.-)%s*$")
		if key == "" then
			setStatus("Paste your key first", "error")
			return
		end
		checking = true
		checkLabel.Text = "Checking…"
		setStatus("", "info")
		local valid, message, expiresAt = checkKey(key)
		checking = false
		checkLabel.Text = "Check Key"
		if valid then
			setStatus("Key accepted", "ok")
			task.wait(0.35)
			closeGate(function()
				startSession(key, expiresAt)
			end)
		elseif message == "unreachable" then
			setStatus("Can't reach the key server, try again", "error")
		elseif message == "device limit reached" or message == "key belongs to another device" then
			setStatus("This key is already used on too many devices", "error")
		else
			setStatus("Invalid or expired key", "error")
		end
	end

	checkBtn.MouseButton1Click:Connect(tryKey)
	box.FocusLost:Connect(function(enter)
		if enter then
			tryKey()
		end
	end)

	gui.Parent = root
	if not notice then
		ping("gate_shown")
	end
	tween(backdrop, 0.3, { BackgroundTransparency = 0.45 })
	tween(scale, 0.35, { Scale = 1 })
	tween(card, 0.35, { GroupTransparency = 0 })
end

---------------------------------------------------------------------------
-- Start: a saved key that is still good goes straight in
---------------------------------------------------------------------------

local saved = readSaved()
if saved and saved ~= "" then
	local valid, message, expiresAt = checkKey(saved)
	if valid then
		startSession(saved, expiresAt)
		return
	end
	if message ~= "unreachable" then
		forget()
	end
end

local shownOk, shownErr = pcall(showGate)
if not shownOk then
	ping("gate_error", "show failed " .. tostring(shownErr))
	warn("[Key gate] " .. tostring(shownErr))
end

end)
