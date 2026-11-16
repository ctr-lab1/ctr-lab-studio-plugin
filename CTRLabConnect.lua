--[[
	CTR Lab Connect for Roblox Studio
	Version 0.8.0 (beta)

	WHAT IT DOES
	Looks at the layout of the place you have open (how big the map is, which models and tools it has,
	roughly where things are, what colours and materials they use, the lighting) and at what your scripts
	do (names of functions, modules, DataStores, stats, game passes), and, only after you review it and
	press "Send", sends that summary to ctr-lab.com. CTR Lab's AI turns it into a game description, a
	picture of the map and thumbnail briefs for the CTR Lab chat.
	It can also set up a small photo set for one item (a copy, never the original) so you can take a screenshot.

	WHAT IT SENDS (shown to you in full before anything leaves Studio)
	  place name and place ID (a public number, 0 if the place is not published),
	  counts of parts, models, meshes, tools, scripts and remotes,
	  the size of the map and a coarse 10 x 10 overview (how many parts, main material and colour per square),
	  names, sizes, positions, main colours and materials of the biggest models and of tools,
	  mesh asset numbers of tools (public numbers), spawn positions,
	  lighting values (time of day, brightness, colours, sky and atmosphere),
	  script paths and class names, for each script its line count, function names and require paths,
	  remote names, names of ScreenGuis,
	  names found in your scripts: Roblox services used, DataStore names, attribute and tag names,
	  leaderstat names, game pass and developer product numbers, names of remotes that are fired.

	WHAT IT NEVER SENDS
	  your script source code. Studio Link reads the scripts on your computer only to find the names
	  listed above, and only those names are sent: never the code, its comments, strings or logic.
	  Also never text typed in your game, models, meshes, textures, images, sounds, other places,
	  your Roblox account or any cookies.

	NETWORK
	  Two requests only, both to https://ctr-lab.com: "pluginPair" (links this Studio with a
	  one-time code from your CTR Lab account) and "pluginAnalyze" (sends the summary you approved).
	  The only other thing it loads is its own logo image from Roblox.

	PHOTO SET (optional)
	  Select a Tool or Model, press "Make photo set". The plugin puts a copy into Workspace > CTR Lab >
	  Session <id>, far above the map, in front of a white wall, and points the camera at it. Your original is
	  not moved. The folder is not saved with your place. "Clean up" removes it and restores the camera.
	  The plugin cannot take the screenshot itself: use your computer's screenshot tool and paste the picture
	  into CTR Lab (Ctrl+V).

	INSTALL
	  1. In Studio add a new Script, paste this whole file into it.
	  2. Right-click the Script, choose "Save as Local Plugin...", then delete the Script.
	  3. Open the "CTR Lab" button in the Plugins tab.

	LICENSE AND TERMS OF USE
	Copyright (c) 2026 CTR Lab. All rights reserved. CTR Lab Connect is owned by CTR Lab.

	You are welcome to read this file, run it in your own Studio and analyse it, so you can
	see for yourself that it is safe and that it never sends your code. That is what the source
	is published for.

	Please do not copy, modify, repackage, redistribute, resell or reuse it or parts of it in
	other plugins or products. It only works together with CTR Lab and a CTR Lab account.
	No licence beyond personal use and inspection is granted. If you want to build on it,
	ask first at https://ctr-lab.com.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
]]

local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local API = "https://ctr-lab.com/api/apps/6af3066f697d7b1811bcf9a9/functions/"
local TOKEN_KEY = "CTRLabToken"
local VERSION = "0.8.0"
local LATEST_KEY = "CTRLabLatest"
local LOGO = "rbxassetid://131268296952051" -- the CTR Lab logo (image asset, 794 x 216)
local LOGO_RATIO = 794 / 216
local MAX_SCRIPTS = 300
local MAX_NAMES = 40
local MAX_REMOTES = 150
local MAX_PARTS_SEEN = 60000 -- a hard stop so a gigantic place cannot freeze Studio
local MAX_GROUPS = 60
local MAX_TOOLS = 40
local GRID = 10
local PAGE_SIZE = 8 -- entries per page in the details list

-- The same look as the CTR Lab Hub: near black green, lime accent, the lime glow is Roblox's own UIShadow.
local LIME = Color3.fromRGB(170, 255, 0)
local LIME_HOVER = Color3.fromRGB(196, 255, 64)
local ON_LIME = Color3.fromRGB(9, 13, 7)
local BG = Color3.fromRGB(9, 13, 7)
local CARD = Color3.fromRGB(15, 22, 11)
local CARD_HOVER = Color3.fromRGB(21, 31, 15)
local FIELD = Color3.fromRGB(6, 9, 5)
local INK = Color3.fromRGB(236, 246, 224)
local MUTED = Color3.fromRGB(128, 148, 108)
local RED = Color3.fromRGB(255, 107, 107)
local FONT = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamBold

---------------------------------------------------------------------------
-- Window and building blocks
---------------------------------------------------------------------------
local toolbar = plugin:CreateToolbar("CTR Lab")
local toggle = toolbar:CreateButton("CTR Lab", "Open CTR Lab Connect", "rbxassetid://86792551935093")
toggle.ClickableWhenViewportHidden = true

local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 340, 600, 300, 380)
local widget = plugin:CreateDockWidgetPluginGui("CTRLabConnect", info)
widget.Title = "CTR Lab"

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function tween(obj, time, goal)
	TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal):Play()
end

local function corner(parent, radius)
	return make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return make("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function pad(parent, amount)
	return make("UIPadding", {
		PaddingTop = UDim.new(0, amount),
		PaddingBottom = UDim.new(0, amount),
		PaddingLeft = UDim.new(0, amount),
		PaddingRight = UDim.new(0, amount),
	}, parent)
end

-- Roblox's own UIShadow as a lime glow. If a Studio does not know it, the UI simply has no glow.
local function glow(parent, blur, transparency)
	local ok, shadow = pcall(function()
		return make("UIShadow", {
			Color = LIME,
			BlurRadius = UDim.new(0, blur),
			Transparency = transparency,
			Spread = UDim2.fromOffset(2, 2),
		}, parent)
	end)
	return ok and shadow or nil
end

local page = make("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = BG,
	BorderSizePixel = 0,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = MUTED,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, widget)
make("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, page)
pad(page, 22) -- room for the glow, so it is never cut off at the edge

local function label(parent, text, size, color, font, order)
	return make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = color,
		Font = font,
		TextSize = size,
		LayoutOrder = order or 0,
	}, parent)
end

-- A card with a title. The title is plain; the card glows softly.
local function card(order, title)
	local f = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = CARD,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, page)
	corner(f, 16)
	stroke(f, LIME, 1, 0.75)
	glow(f, 22, 0.86)
	pad(f, 16)
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	label(f, title, 16, INK, FONT_BOLD, 0)
	return f
end

-- Primary: lime fill. Ghost: dark with lime text and outline. Both glow on hover, like the Hub.
local function button(parent, text, order, primary, size)
	local rest = primary and LIME or BG
	local hover = primary and LIME_HOVER or CARD_HOVER
	local idleGlow = primary and 0.8 or 1
	local hoverGlow = primary and 0.55 or 0.8
	local b = make("TextButton", {
		Size = size or UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = rest,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = text,
		TextColor3 = primary and ON_LIME or LIME,
		Font = FONT_BOLD,
		TextSize = 14,
		LayoutOrder = order,
	}, parent)
	corner(b, 12)
	local outline = (not primary) and stroke(b, LIME, 1.5, 0.55) or nil
	local shadow = glow(b, 16, idleGlow)
	b.MouseEnter:Connect(function()
		tween(b, 0.16, { BackgroundColor3 = hover })
		if outline then
			tween(outline, 0.16, { Transparency = 0.1 })
		end
		if shadow then
			tween(shadow, 0.2, { Transparency = hoverGlow })
		end
	end)
	b.MouseLeave:Connect(function()
		tween(b, 0.16, { BackgroundColor3 = rest })
		if outline then
			tween(outline, 0.16, { Transparency = 0.55 })
		end
		if shadow then
			tween(shadow, 0.2, { Transparency = idleGlow })
		end
	end)
	return b
end

---------------------------------------------------------------------------
-- Layout: header, 3 steps, one card at a time, photo set, footer
---------------------------------------------------------------------------
local header = make("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	LayoutOrder = 1,
}, page)
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, header)

local brand = make("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = 1 }, header)
local logo = make("ImageLabel", {
	Size = UDim2.fromOffset(math.floor(34 * LOGO_RATIO), 34),
	BackgroundTransparency = 1,
	Image = LOGO,
	ScaleType = Enum.ScaleType.Fit,
}, brand)
local logoText = make("TextLabel", {
	Size = UDim2.fromOffset(140, 34),
	BackgroundTransparency = 1,
	Text = "CTR Lab",
	TextColor3 = LIME,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = FONT_BOLD,
	TextSize = 24,
	Visible = false,
}, brand)
local pill = make("TextLabel", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(1, 0.5),
	Size = UDim2.fromOffset(88, 22),
	BackgroundColor3 = CARD,
	BorderSizePixel = 0,
	Text = "BETA  v" .. VERSION,
	TextColor3 = LIME,
	Font = FONT_BOLD,
	TextSize = 10,
}, brand)
corner(pill, 11)
stroke(pill, LIME, 1, 0.6)

-- If the logo cannot be loaded (offline, or Roblox blocks it), the name in text takes its place.
task.spawn(function()
	local ok = pcall(function()
		ContentProvider:PreloadAsync({ logo }, function(_, status)
			if status ~= Enum.AssetFetchStatus.Success then
				logo.Visible = false
				logoText.Visible = true
			end
		end)
	end)
	if not ok then
		logo.Visible = false
		logoText.Visible = true
	end
end)

-- The three steps, always visible, the current one lit.
local stepper = make("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 2 }, page)
local stepPills = {}
local STEP_NAMES = { "1  Connect", "2  Scan", "3  Brief" }
for i, name in ipairs(STEP_NAMES) do
	local p = make("TextLabel", {
		Size = UDim2.new(0.32, 0, 1, 0),
		Position = UDim2.new((i - 1) * 0.34, 0, 0, 0),
		BackgroundColor3 = CARD,
		BorderSizePixel = 0,
		Text = name,
		TextColor3 = MUTED,
		Font = FONT_BOLD,
		TextSize = 12,
	}, stepper)
	corner(p, 15)
	stepPills[i] = { frame = p, stroke = stroke(p, LIME, 1, 0.85) }
end

local notice = label(page, "", 13, RED, FONT, 3)
notice.Visible = false

-- Shown when CTR Lab says a newer version exists. It uses the answers of the two requests, so nothing extra is sent.
local updateNote = label(page, "", 12, LIME, FONT, 4)
updateNote.Visible = false

-- Step 1: Connect
local connectCard = card(5, "Connect your CTR Lab account")
label(connectCard, "In CTR Lab open Library, then Games, and press Create a code. Type the code here.", 13, MUTED, FONT, 1)
local codeBox = make("TextBox", {
	Size = UDim2.new(1, 0, 0, 48),
	BackgroundColor3 = FIELD,
	BorderSizePixel = 0,
	PlaceholderText = "6-digit code",
	PlaceholderColor3 = MUTED,
	Text = "",
	TextColor3 = LIME,
	ClearTextOnFocus = false,
	Font = Enum.Font.Code,
	TextSize = 22,
	LayoutOrder = 2,
}, connectCard)
corner(codeBox, 12)
local codeStroke = stroke(codeBox, LIME, 1, 0.7)
codeBox.Focused:Connect(function()
	tween(codeStroke, 0.16, { Transparency = 0.15 })
end)
codeBox.FocusLost:Connect(function()
	tween(codeStroke, 0.16, { Transparency = 0.7 })
end)
local connectBtn = button(connectCard, "Connect", 3, true)

-- Step 2: Scan
local scanCard = card(6, "Scan your game")
label(scanCard, "Reads the map, models, tools and what your scripts do. Nothing is sent before you press Send.", 13, MUTED, FONT, 1)
local scanBtn = button(scanCard, "Scan my game", 2, true)

-- Step 2b: check and send
local reviewCard = card(7, "Check and send")
local statsLabel = label(reviewCard, "", 13, LIME, FONT_BOLD, 1)
local sendBtn = button(reviewCard, "Send to CTR Lab", 2, true)
local detailsBtn = button(reviewCard, "Show what is sent", 3, false)
local previewBox = make("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = FIELD,
	BorderSizePixel = 0,
	LayoutOrder = 4,
}, reviewCard)
corner(previewBox, 12)
stroke(previewBox, LIME, 1, 0.8)
pad(previewBox, 12)
local previewLabel = label(previewBox, "", 12, INK, Enum.Font.Code, 1)
local pager = make("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = 5 }, reviewCard)
local prevBtn = button(pager, "Back", 1, false, UDim2.new(0.28, 0, 1, 0))
prevBtn.Position = UDim2.fromScale(0, 0)
local pageLabel = make("TextLabel", {
	Size = UDim2.new(0.44, 0, 1, 0),
	Position = UDim2.fromScale(0.28, 0),
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = MUTED,
	Font = FONT,
	TextSize = 13,
}, pager)
local nextBtn = button(pager, "Next", 3, false, UDim2.new(0.28, 0, 1, 0))
nextBtn.Position = UDim2.fromScale(0.72, 0)
local rescanBtn = button(reviewCard, "Scan again", 6, false)

-- Step 3: Result
local resultCard = card(8, "Your brief is ready")
label(resultCard, "Open ctr-lab.com, Library, Games, and press Open in EZ AI Chat. Or copy the brief below.", 13, MUTED, FONT, 1)
local summaryLabel = label(resultCard, "", 13, INK, FONT, 2)
local promptBox = make("TextBox", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = FIELD,
	BorderSizePixel = 0,
	Text = "",
	TextColor3 = INK,
	TextWrapped = true,
	MultiLine = true,
	ClearTextOnFocus = false,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Font = FONT,
	TextSize = 13,
	LayoutOrder = 3,
}, resultCard)
corner(promptBox, 12)
stroke(promptBox, LIME, 1, 0.7)
pad(promptBox, 12)
local ideasLabel = label(resultCard, "", 12, MUTED, FONT, 4)
local againBtn = button(resultCard, "Scan again", 5, false)

-- Item photo set
local photoCard = card(9, "Photo of an item (optional)")
label(photoCard, "Select a Tool or Model in the Explorer. A copy goes on a white wall far above the map. Take a screenshot and paste it into CTR Lab.", 13, MUTED, FONT, 1)
local photoBtn = button(photoCard, "Make photo set", 2, false)
local cleanBtn = button(photoCard, "Clean up", 3, false)

-- Footer
local footer = make("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	LayoutOrder = 10,
}, page)
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, footer)
local disconnectBtn = button(footer, "Disconnect", 1, false, UDim2.new(1, 0, 0, 34))
label(footer, "Only names are sent, never your code  ·  ctr-lab.com/plugin", 11, MUTED, FONT, 2)

---------------------------------------------------------------------------
-- Network
---------------------------------------------------------------------------
-- Returns data, errorText, httpStatus
local function request(name, body, token)
	local headers = { ["Content-Type"] = "application/json" }
	if token then
		headers["Authorization"] = "Bearer " .. token
	end
	local ok, res = pcall(function()
		return HttpService:RequestAsync({
			Url = API .. name,
			Method = "POST",
			Headers = headers,
			Body = HttpService:JSONEncode(body),
		})
	end)
	if not ok then
		return nil,
			"Could not reach CTR Lab. Check your connection. If Studio asks to allow ctr-lab.com, choose Allow. If it keeps failing, turn on Game Settings > Security > Allow HTTP Requests.",
			0
	end
	local data = nil
	pcall(function()
		data = HttpService:JSONDecode(res.Body)
	end)
	if not res.Success then
		local message = (type(data) == "table" and data.error) or ("Error " .. tostring(res.StatusCode))
		return nil, message, res.StatusCode
	end
	return data, nil, res.StatusCode
end

---------------------------------------------------------------------------
-- Reading the place. Names, counts, sizes, colours and materials. Script source is never read.
---------------------------------------------------------------------------
local function round(n, d)
	local m = 10 ^ (d or 0)
	return math.floor(n * m + 0.5) / m
end

local function hex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function vec(v)
	return { round(v.X), round(v.Y), round(v.Z) }
end

-- The last number in an asset link ("rbxassetid://123" or ".../asset/?id=123").
local function assetNumber(s)
	return tonumber(string.match(tostring(s or ""), "(%d+)[^%d]*$"))
end

local function newStats(name, class)
	return {
		name = name,
		class = class,
		parts = 0,
		meshes = 0,
		unions = 0,
		weight = 0,
		r = 0,
		g = 0,
		b = 0,
		mats = {},
		npc = false,
		meshIds = {},
		minV = nil,
		maxV = nil,
	}
end

local function addPart(st, p)
	st.parts += 1
	if p:IsA("MeshPart") then
		st.meshes += 1
		local id = assetNumber(p.MeshId)
		if id and #st.meshIds < 3 and not table.find(st.meshIds, id) then
			table.insert(st.meshIds, id)
		end
	elseif p:IsA("UnionOperation") then
		st.unions += 1
	end
	local pos, sz = p.Position, p.Size
	local half = math.max(sz.X, sz.Y, sz.Z) / 2
	local lo = Vector3.new(pos.X - half, pos.Y - half, pos.Z - half)
	local hi = Vector3.new(pos.X + half, pos.Y + half, pos.Z + half)
	if st.minV == nil then
		st.minV, st.maxV = lo, hi
	else
		st.minV = Vector3.new(math.min(st.minV.X, lo.X), math.min(st.minV.Y, lo.Y), math.min(st.minV.Z, lo.Z))
		st.maxV = Vector3.new(math.max(st.maxV.X, hi.X), math.max(st.maxV.Y, hi.Y), math.max(st.maxV.Z, hi.Z))
	end
	local w = math.min(sz.X * sz.Y * sz.Z, 400) + 1
	st.weight += w
	local c = p.Color
	st.r += c.R * w
	st.g += c.G * w
	st.b += c.B * w
	local m = p.Material.Name
	st.mats[m] = (st.mats[m] or 0) + w
end

local function topMaterials(mats, n)
	local list = {}
	for name, w in pairs(mats) do
		table.insert(list, { name = name, w = w })
	end
	table.sort(list, function(a, b)
		return a.w > b.w
	end)
	local out = {}
	for i = 1, math.min(n, #list) do
		table.insert(out, list[i].name)
	end
	return out
end

local function finishStats(st)
	local size = st.minV and (st.maxV - st.minV) or Vector3.zero
	local center = st.minV and ((st.minV + st.maxV) / 2) or Vector3.zero
	local color = st.weight > 0 and Color3.new(st.r / st.weight, st.g / st.weight, st.b / st.weight) or Color3.new(0.5, 0.5, 0.5)
	return {
		name = st.name,
		class = st.class,
		parts = st.parts,
		meshes = st.meshes,
		unions = st.unions,
		size = vec(size),
		center = vec(center),
		color = hex(color),
		materials = topMaterials(st.mats, 2),
		npc = st.npc,
		meshIds = st.meshIds,
	}
end

-- The child of Workspace an instance sits in. Folders are opened one more level, so a folder with many models gives many entries.
local function groupKey(inst)
	local node = inst
	while node and node.Parent ~= workspace do
		node = node.Parent
	end
	if node == nil or node == inst then
		return nil, nil
	end
	if node.ClassName == "Folder" then
		local second = inst
		while second and second.Parent ~= node do
			second = second.Parent
		end
		if second and second ~= inst then
			return second, node.Name .. " / " .. second.Name
		end
		return node, node.Name .. " (loose parts)"
	end
	return node, node.Name
end

local function readLighting()
	local out = {}
	pcall(function()
		out.clock = round(Lighting.ClockTime, 1)
		out.brightness = round(Lighting.Brightness, 1)
		out.ambient = hex(Lighting.Ambient)
		out.outdoor = hex(Lighting.OutdoorAmbient)
		out.fogEnd = round(math.min(Lighting.FogEnd, 100000))
		out.tech = tostring(Lighting.Technology)
	end)
	pcall(function()
		local atm = Lighting:FindFirstChildOfClass("Atmosphere")
		if atm then
			out.atmosphere = { density = round(atm.Density, 2), color = hex(atm.Color), haze = round(atm.Haze, 1) }
		end
		local sky = Lighting:FindFirstChildOfClass("Sky")
		if sky then
			out.sky = true
			local ids = {}
			for _, face in ipairs({ "SkyboxBk", "SkyboxUp", "SkyboxFt" }) do
				local id = assetNumber(sky[face])
				if id then
					table.insert(ids, id)
				end
			end
			out.skyIds = ids
		else
			out.sky = false
		end
	end)
	return out
end

local function collect()
	local scripts, remoteNames, spawns = {}, {}, {}
	local scriptTotal, remoteTotal, instanceCount = 0, 0, 0
	local partsSeen, partTotal, modelTotal = 0, 0, 0
	local truncated = false
	local groups, order, npcKeys = {}, {}, {}
	local serviceSet = {}
	local systems = { datastores = {}, attributes = {}, tags = {}, leaderstats = {}, products = {}, events = {} }
	local function addUnique(list, v, max)
		if v ~= nil and #list < max and not table.find(list, v) then
			table.insert(list, v)
		end
	end
	local samples = {}
	local gMin, gMax = nil, nil

	local all = game:GetDescendants()
	for i, obj in ipairs(all) do
		instanceCount += 1
		if i % 1500 == 0 then
			task.wait() -- let Studio breathe on big places
		end
		if obj:IsA("LuaSourceContainer") then
			scriptTotal += 1
			if #scripts < MAX_SCRIPTS then
				local entry = { path = obj:GetFullName(), class = obj.ClassName, lines = 0, functions = {}, requires = {} }
				-- The code is read here on your computer only to find names. Only the names are kept; the code is dropped.
				local okSrc, src = pcall(function()
					return obj.Source
				end)
				if okSrc and type(src) == "string" then
					local _, newlines = string.gsub(src, "\n", "")
					entry.lines = newlines + 1
					for name in string.gmatch(src, "function%s+([%w_%.:]+)") do
						if #entry.functions < MAX_NAMES then
							table.insert(entry.functions, string.sub(name, 1, 80))
						end
					end
					for path in string.gmatch(src, "require%(([^)\n]+)%)") do
						if #entry.requires < MAX_NAMES then
							table.insert(entry.requires, string.sub(path, 1, 120))
						end
					end
					for svc in string.gmatch(src, "GetService%(%s*[\"']([%w_]+)[\"']%s*%)") do
						serviceSet[svc] = true
					end
					for n in string.gmatch(src, "GetDataStore%(%s*[\"']([^\"']+)[\"']") do
						addUnique(systems.datastores, string.sub(n, 1, 40), 20)
					end
					for n in string.gmatch(src, "SetAttribute%(%s*[\"']([^\"']+)[\"']") do
						addUnique(systems.attributes, string.sub(n, 1, 40), 40)
					end
					for n in string.gmatch(src, "GetTagged%(%s*[\"']([^\"']+)[\"']") do
						addUnique(systems.tags, string.sub(n, 1, 40), 20)
					end
					for n in string.gmatch(src, ":AddTag%([^,%)]-,%s*[\"']([^\"']+)[\"']") do
						addUnique(systems.tags, string.sub(n, 1, 40), 20)
					end
					if string.find(src, "leaderstats", 1, true) then
						for n in string.gmatch(src, "%.Name%s*=%s*[\"']([^\"']+)[\"']") do
							addUnique(systems.leaderstats, string.sub(n, 1, 30), 12)
						end
					end
					for id in string.gmatch(src, "[Pp]roductId%s*=%s*(%d+)") do
						addUnique(systems.products, tonumber(id), 20)
					end
					for id in string.gmatch(src, "GamePassId%s*=%s*(%d+)") do
						addUnique(systems.products, tonumber(id), 20)
					end
					for id in string.gmatch(src, "Prompt%w*Purchase%([^,%)]*,%s*(%d+)") do
						addUnique(systems.products, tonumber(id), 20)
					end
					for n in string.gmatch(src, "([%w_]+):Fire%w*%(") do
						addUnique(systems.events, string.sub(n, 1, 40), 40)
					end
				end
				table.insert(scripts, entry)
			end
		elseif obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
			remoteTotal += 1
			if #remoteNames < MAX_REMOTES then
				table.insert(remoteNames, obj:GetFullName())
			end
		elseif obj:IsA("Model") then
			modelTotal += 1
		end
		if obj:IsDescendantOf(workspace) then
			if obj:IsA("SpawnLocation") and #spawns < 20 then
				table.insert(spawns, vec(obj.Position))
			end
			if obj:IsA("Humanoid") then
				local key = groupKey(obj)
				if key then
					npcKeys[key] = true
				end
			end
			if obj:IsA("BasePart") and not obj:IsA("Terrain") then
				partTotal += 1
				if partsSeen < MAX_PARTS_SEEN then
					partsSeen += 1
					local pos = obj.Position
					if gMin == nil then
						gMin, gMax = pos, pos
					else
						gMin = Vector3.new(math.min(gMin.X, pos.X), math.min(gMin.Y, pos.Y), math.min(gMin.Z, pos.Z))
						gMax = Vector3.new(math.max(gMax.X, pos.X), math.max(gMax.Y, pos.Y), math.max(gMax.Z, pos.Z))
					end
					local sz = obj.Size
					local w = math.min(sz.X * sz.Y * sz.Z, 400) + 1
					table.insert(samples, { pos.X, pos.Y, pos.Z, w, obj.Material.Name, obj.Color })
					local key, name = groupKey(obj)
					if key then
						local g = groups[key]
						if not g then
							g = newStats(name, key.ClassName)
							groups[key] = g
							table.insert(order, key)
						end
						addPart(g, obj)
					end
				else
					truncated = true
				end
			end
		end
	end

	-- The coarse overview: GRID x GRID squares over the map, seen from above.
	local cells = {}
	local bounds = nil
	if gMin then
		local sx = math.max(gMax.X - gMin.X, 1)
		local sz = math.max(gMax.Z - gMin.Z, 1)
		bounds = { min = vec(gMin), max = vec(gMax), size = vec(gMax - gMin) }
		local acc = {}
		for _, s in ipairs(samples) do
			local cx = math.min(GRID - 1, math.floor((s[1] - gMin.X) / sx * GRID))
			local cz = math.min(GRID - 1, math.floor((s[3] - gMin.Z) / sz * GRID))
			local k = cz * GRID + cx + 1
			local a = acc[k]
			if not a then
				a = { n = 0, w = 0, r = 0, g = 0, b = 0, top = -math.huge, mats = {} }
				acc[k] = a
			end
			a.n += 1
			a.w += s[4]
			a.r += s[6].R * s[4]
			a.g += s[6].G * s[4]
			a.b += s[6].B * s[4]
			if s[2] > a.top then
				a.top = s[2]
			end
			a.mats[s[5]] = (a.mats[s[5]] or 0) + s[4]
		end
		for k = 1, GRID * GRID do
			local a = acc[k]
			if a then
				local m = topMaterials(a.mats, 1)[1] or "Plastic"
				table.insert(cells, { a.n, m, hex(Color3.new(a.r / a.w, a.g / a.w, a.b / a.w)), round(a.top) })
			else
				table.insert(cells, { 0, "", "", 0 })
			end
		end
	end

	-- The biggest models and folders of Workspace.
	table.sort(order, function(x, y)
		return groups[x].parts > groups[y].parts
	end)
	local models = {}
	for i = 1, math.min(MAX_GROUPS, #order) do
		local g = groups[order[i]]
		g.npc = npcKeys[order[i]] == true
		table.insert(models, finishStats(g))
	end

	-- Tools (what players hold or can get): StarterPack and the storage services.
	local tools = {}
	for _, svcName in ipairs({ "StarterPack", "ServerStorage", "ReplicatedStorage" }) do
		local ok, svc = pcall(function()
			return game:GetService(svcName)
		end)
		if ok and svc then
			for _, obj in ipairs(svc:GetDescendants()) do
				if obj:IsA("Tool") and #tools < MAX_TOOLS then
					local st = newStats(obj.Name, "Tool")
					for _, d in ipairs(obj:GetDescendants()) do
						if d:IsA("BasePart") then
							addPart(st, d)
						end
					end
					local fin = finishStats(st)
					fin.where = svcName
					table.insert(tools, fin)
				end
			end
		end
	end

	local guis = {}
	pcall(function()
		for _, g in ipairs(game:GetService("StarterGui"):GetChildren()) do
			if g:IsA("ScreenGui") and #guis < 20 then
				table.insert(guis, g.Name)
			end
		end
	end)

	local hasTerrain = false
	pcall(function()
		local n = workspace.Terrain:CountCells()
		hasTerrain = type(n) == "number" and n > 0
	end)

	local services = {}
	for svc in pairs(serviceSet) do
		table.insert(services, svc)
	end
	table.sort(services)

	return {
		place_name = game.Name,
		place_id = game.PlaceId,
		stats = {
			instances = instanceCount,
			scripts = scriptTotal,
			remotes = remoteTotal,
			parts = partTotal,
			models = modelTotal,
			tools = #tools,
		},
		scripts = scripts,
		remotes = remoteNames,
		services = services,
		systems = systems,
		scene = {
			bounds = bounds,
			terrain = hasTerrain,
			spawns = spawns,
			grid = { n = GRID, cells = cells },
			models = models,
			tools = tools,
			lighting = readLighting(),
			guis = guis,
			truncated = truncated,
		},
	}
end

local function sizeText(s)
	return string.format("%d x %d x %d studs", s[1], s[2], s[3])
end

-- The exact content of the summary as readable entries, so the user can check it before sending.
local function buildItems(payload)
	local items = {}
	local sc = payload.scene
	local head = string.format("Place: %s  (place ID %.0f)", payload.place_name, payload.place_id)
	head = head .. "\nServices used by scripts: " .. (#payload.services > 0 and table.concat(payload.services, ", ") or "none")
	table.insert(items, head)
	local map = "Map"
	if sc.bounds then
		map = map .. ": " .. sizeText(sc.bounds.size)
	end
	map = map .. (sc.terrain and ", has terrain" or ", no terrain") .. string.format(", %d spawn(s)", #sc.spawns)
	table.insert(items, map .. "\nA 10 x 10 overview of part counts, main material and colour is included.")
	local L = sc.lighting
	if L and L.clock then
		local lt = string.format("Lighting: clock %.1f, brightness %.1f, ambient %s", L.clock, L.brightness or 0, L.ambient or "?")
		if L.atmosphere then
			lt = lt .. ", atmosphere " .. L.atmosphere.color
		end
		lt = lt .. (L.sky and ", custom sky" or ", default sky")
		table.insert(items, lt)
	end
	for _, m in ipairs(sc.models) do
		local t = string.format("%s  %s  (%d parts, %s, %s%s)", m.npc and "NPC" or "Model", m.name, m.parts, sizeText(m.size), m.color, #m.materials > 0 and ", " .. table.concat(m.materials, "/") or "")
		table.insert(items, t)
	end
	for _, tl in ipairs(sc.tools) do
		local t = string.format("Tool  %s  in %s  (%d parts, %s, %s)", tl.name, tl.where, tl.parts, sizeText(tl.size), tl.color)
		if #tl.meshIds > 0 then
			local ids = {}
			for _, id in ipairs(tl.meshIds) do
				table.insert(ids, tostring(id))
			end
			t = t .. "\n  mesh numbers: " .. table.concat(ids, ", ")
		end
		table.insert(items, t)
	end
	if #sc.guis > 0 then
		table.insert(items, "Screens: " .. table.concat(sc.guis, ", "))
	end
	for _, r in ipairs(payload.remotes) do
		table.insert(items, "Remote  " .. r)
	end
	local sy = payload.systems
	local names = {}
	for _, key in ipairs({ "datastores", "attributes", "tags", "leaderstats", "products", "events" }) do
		if sy[key] and #sy[key] > 0 then
			local list = {}
			for _, v in ipairs(sy[key]) do
				table.insert(list, tostring(v))
			end
			table.insert(names, key .. ": " .. table.concat(list, ", "))
		end
	end
	if #names > 0 then
		table.insert(items, "Names found in scripts\n" .. table.concat(names, "\n"))
	end
	for _, s in ipairs(payload.scripts) do
		local t = string.format("%s  (%s, %d lines)", s.path, s.class, s.lines)
		if #s.functions > 0 then
			t = t .. "\n  functions: " .. table.concat(s.functions, ", ")
		end
		if #s.requires > 0 then
			t = t .. "\n  requires: " .. table.concat(s.requires, ", ")
		end
		table.insert(items, t)
	end
	return items
end

---------------------------------------------------------------------------
-- Photo set: a copy of the selected item on a white wall, far above the map. The original is never moved.
---------------------------------------------------------------------------
local photoSession = nil -- { model, camera, cameraCFrame, cameraFocus }
local PHOTO_ORIGIN = Vector3.new(0, 20000, 0)

local function cleanPhoto()
	if photoSession then
		local s = photoSession
		photoSession = nil
		if s.folderModel and s.folderModel.Parent then
			s.folderModel:Destroy()
		end
		local root = workspace:FindFirstChild("CTR Lab")
		if root and #root:GetChildren() == 0 then
			root:Destroy()
		end
		pcall(function()
			if s.camera then
				s.camera.CFrame = s.cameraCFrame
				s.camera.Focus = s.cameraFocus
			end
		end)
		ChangeHistoryService:SetWaypoint("CTR Lab clean up")
	end
end

local function makePhoto()
	local sel = Selection:Get()
	local src = sel[1]
	if not src or not (src:IsA("Tool") or src:IsA("Model") or src:IsA("BasePart")) then
		return nil, "Select a Tool, a Model or a Part in the Explorer first."
	end
	cleanPhoto()
	local copy = src:Clone()
	if not copy then
		return nil, "This item cannot be copied."
	end
	local session = string.sub(HttpService:GenerateGUID(false), 1, 8)

	local root = workspace:FindFirstChild("CTR Lab")
	if not root then
		root = Instance.new("Folder")
		root.Name = "CTR Lab"
		root.Archivable = false -- the photo set is never saved with the place
		root.Parent = workspace
	end
	local set = Instance.new("Model")
	set.Name = "Session " .. session
	set:SetAttribute("CTRLabSession", session)
	set.Archivable = false

	-- The copy is only for looking: no scripts, no physics.
	local holder = Instance.new("Model")
	holder.Name = "Item"
	copy.Parent = holder
	for _, d in ipairs(holder:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	if holder:IsA("Model") and copy:IsA("BasePart") then
		copy.Anchored = true
	end
	holder.Parent = set
	local cf, size = holder:GetBoundingBox()
	holder:PivotTo(holder:GetPivot() - (cf.Position - PHOTO_ORIGIN))
	local radius = math.max(size.Magnitude / 2, 2)

	local cam = workspace.CurrentCamera
	local fov = cam and cam.FieldOfView or 70
	local dist = (radius / math.tan(math.rad(fov / 2))) * 1.2
	local camPos = PHOTO_ORIGIN + Vector3.new(0, radius * 0.15, dist)

	local wall = Instance.new("Part")
	wall.Name = "White wall"
	wall.Anchored = true
	wall.CanCollide = false
	wall.CastShadow = false
	wall.Material = Enum.Material.SmoothPlastic
	wall.Color = Color3.new(1, 1, 1)
	wall.Size = Vector3.new(radius * 40, radius * 40, 1)
	wall.CFrame = CFrame.new(PHOTO_ORIGIN + Vector3.new(0, 0, -(size.Z / 2 + radius * 0.8)))
	wall.Parent = set

	local lamp = Instance.new("Part")
	lamp.Name = "Light"
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.Transparency = 1
	lamp.Size = Vector3.new(1, 1, 1)
	lamp.Position = camPos + Vector3.new(radius * 0.4, radius * 0.8, 0)
	local pl = Instance.new("PointLight")
	pl.Range = 60
	pl.Brightness = 2
	pl.Parent = lamp
	lamp.Parent = set

	set.Parent = root

	photoSession = { folderModel = set, camera = cam, cameraCFrame = cam and cam.CFrame, cameraFocus = cam and cam.Focus }
	if cam then
		cam.CFrame = CFrame.lookAt(camPos, PHOTO_ORIGIN)
		cam.Focus = CFrame.new(PHOTO_ORIGIN)
	end
	Selection:Set({})
	ChangeHistoryService:SetWaypoint("CTR Lab photo set")
	return session, nil
end

---------------------------------------------------------------------------
-- State and rendering
---------------------------------------------------------------------------
local pending = nil -- the summary the user is reviewing, not sent yet
local items = {}
local pageIndex = 1
local pageCount = 1
local showDetails = false
local result = nil
local busy = false

local function versionParts(v)
	local a, b, c = string.match(tostring(v or ""), "^(%d+)%.(%d+)%.(%d+)$")
	return { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0 }
end

local function isNewer(a, b)
	local x, y = versionParts(a), versionParts(b)
	for i = 1, 3 do
		if x[i] ~= y[i] then
			return x[i] > y[i]
		end
	end
	return false
end

local function showUpdate(latest)
	if type(latest) == "string" and isNewer(latest, VERSION) then
		updateNote.Text = "A new version (" .. latest .. ") is available. Studio updates plugins from the Creator Store by itself. If you installed it by hand, get the new file from github.com/ctr-lab1/ctr-lab-studio-plugin"
		updateNote.Visible = true
	else
		updateNote.Visible = false
	end
end

-- Remember what the last answer said, so the hint is still there the next time the window opens.
local function noteLatest(data)
	if type(data) == "table" and type(data.latest_version) == "string" then
		plugin:SetSetting(LATEST_KEY, data.latest_version)
		showUpdate(data.latest_version)
	end
end

showUpdate(plugin:GetSetting(LATEST_KEY))

local function notify(text, isError)
	notice.Text = text
	notice.TextColor3 = isError and RED or LIME
	notice.Visible = text ~= ""
end

local function showPage()
	local first = (pageIndex - 1) * PAGE_SIZE + 1
	local last = math.min(first + PAGE_SIZE - 1, #items)
	local chunk = {}
	for i = first, last do
		table.insert(chunk, items[i])
	end
	previewLabel.Text = table.concat(chunk, "\n\n")
	pageLabel.Text = string.format("%d / %d", pageIndex, pageCount)
end

local function render()
	local connected = plugin:GetSetting(TOKEN_KEY) ~= nil
	local reviewing = connected and pending ~= nil
	local done = connected and result ~= nil
	local step = (not connected) and 1 or (done and 3 or 2)
	for i, p in ipairs(stepPills) do
		local on = i == step
		local past = i < step
		p.frame.TextColor3 = on and ON_LIME or (past and LIME or MUTED)
		p.frame.BackgroundColor3 = on and LIME or CARD
		p.stroke.Transparency = on and 1 or (past and 0.4 or 0.85)
	end

	connectCard.Visible = not connected
	scanCard.Visible = connected and not reviewing and not done
	reviewCard.Visible = reviewing
	resultCard.Visible = done
	photoCard.Visible = connected
	cleanBtn.Visible = photoSession ~= nil
	footer.Visible = true
	disconnectBtn.Visible = connected

	previewBox.Visible = reviewing and showDetails
	pager.Visible = reviewing and showDetails and pageCount > 1
	detailsBtn.Text = showDetails and "Hide details" or "Show what is sent"
end

-- One action at a time, and any error ends up as a message instead of a broken window.
local function run(fn)
	if busy then
		return
	end
	busy = true
	local ok, err = pcall(fn)
	busy = false
	if not ok then
		notify("Something went wrong: " .. tostring(err), true)
		render()
	end
end

connectBtn.Activated:Connect(function()
	run(function()
		local code = string.gsub(codeBox.Text, "%s", "")
		if not string.match(code, "^%d%d%d%d%d%d$") then
			notify("Enter the 6-digit code from your CTR Lab account.", true)
			return
		end
		notify("", false)
		connectBtn.Text = "Connecting..."
		local data, err = request("pluginPair", { code = code, label = "Roblox Studio" })
		connectBtn.Text = "Connect"
		if not data or not data.token then
			notify(err or "Connection failed.", true)
			return
		end
		plugin:SetSetting(TOKEN_KEY, data.token)
		noteLatest(data)
		codeBox.Text = ""
		notify("Connected. Next: scan your game.", false)
		render()
	end)
end)

disconnectBtn.Activated:Connect(function()
	run(function()
		plugin:SetSetting(TOKEN_KEY, nil)
		pending = nil
		items = {}
		result = nil
		showDetails = false
		notify("", false)
		render()
	end)
end)

local function scan(button)
	run(function()
		notify("", false)
		result = nil
		button.Text = "Scanning..."
		task.wait() -- let the window redraw before the scan
		local payload = collect()
		button.Text = (button == scanBtn) and "Scan my game" or "Scan again"
		pending = payload
		items = buildItems(payload)
		pageCount = math.max(1, math.ceil(#items / PAGE_SIZE))
		pageIndex = 1
		showDetails = false
		local st = payload.stats
		statsLabel.Text = string.format("%d parts  ·  %d models  ·  %d tools  ·  %d scripts", st.parts, st.models, st.tools, st.scripts)
		showPage()
		render()
	end)
end

scanBtn.Activated:Connect(function()
	scan(scanBtn)
end)
rescanBtn.Activated:Connect(function()
	scan(rescanBtn)
end)
againBtn.Activated:Connect(function()
	result = nil
	pending = nil
	render()
end)

detailsBtn.Activated:Connect(function()
	showDetails = not showDetails
	render()
end)

prevBtn.Activated:Connect(function()
	pageIndex = math.max(1, pageIndex - 1)
	showPage()
end)

nextBtn.Activated:Connect(function()
	pageIndex = math.min(pageCount, pageIndex + 1)
	showPage()
end)

sendBtn.Activated:Connect(function()
	run(function()
		local token = plugin:GetSetting(TOKEN_KEY)
		if not token or not pending then
			return
		end
		notify("", false)
		sendBtn.Text = "Sending..."
		local data, err, code = request("pluginAnalyze", pending, token)
		sendBtn.Text = "Send to CTR Lab"
		if not data or not data.analysis then
			if code == 401 then
				plugin:SetSetting(TOKEN_KEY, nil)
				pending = nil
				err = "This link was removed. Connect again with a new code."
			end
			notify(err or "The analysis failed.", true)
			render()
			return
		end
		noteLatest(data)
		local a = data.analysis
		pending = nil
		items = {}
		result = a
		summaryLabel.Text = (type(a.spec) == "table" and a.spec.summary) or ""
		promptBox.Text = a.prompt or ""
		if type(a.improvements) == "table" and #a.improvements > 0 then
			ideasLabel.Text = "Ideas\n- " .. table.concat(a.improvements, "\n- ")
			ideasLabel.Visible = true
		else
			ideasLabel.Visible = false
		end
		render()
	end)
end)

photoBtn.Activated:Connect(function()
	run(function()
		notify("", false)
		local id, err = makePhoto()
		if not id then
			notify(err or "Could not make the photo set.", true)
		else
			notify("Photo set ready (session " .. id .. "). Take a screenshot, then press Clean up.", false)
		end
		render()
	end)
end)

cleanBtn.Activated:Connect(function()
	run(function()
		cleanPhoto()
		notify("Photo set removed.", false)
		render()
	end)
end)

toggle.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggle:SetActive(widget.Enabled)
end)
-- Never leave a photo set behind when the plugin is unloaded.
plugin.Unloading:Connect(cleanPhoto)

render()
