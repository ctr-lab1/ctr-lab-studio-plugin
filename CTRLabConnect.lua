--[[
	CTR Lab Connect for Roblox Studio
	Version 0.7.0 (beta)

	WHAT IT DOES
	Reads the structure of the place you have open and, only after you review it and press "Send",
	sends a summary to ctr-lab.com. CTR Lab turns that summary into a game description and a
	thumbnail brief you can use in the CTR Lab chat.

	WHAT IT SENDS (shown to you in full before anything leaves Studio)
	  place name and place ID (a public number, 0 if the place is not published),
	  instance / script / remote counts, script paths and class names, line counts,
	  function names, require paths, remote names, service names.

	WHAT IT NEVER SENDS
	  script source code, comments, string contents, property values, models, meshes, images,
	  other places, your Roblox account or any cookies.

	NETWORK
	  Two requests only, both to https://ctr-lab.com: "pluginPair" (links this Studio with a
	  one-time code from your CTR Lab account) and "pluginAnalyze" (sends the summary you approved).
	  The only other thing it loads is its own logo image from Roblox.

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

local API = "https://ctr-lab.com/api/apps/6af3066f697d7b1811bcf9a9/functions/"
local TOKEN_KEY = "CTRLabToken"
local VERSION = "0.7.0"
local LATEST_KEY = "CTRLabLatest"
local LOGO = "rbxassetid://131268296952051" -- the CTR Lab logo (image asset, 794 x 216)
local LOGO_RATIO = 794 / 216
local MAX_SCRIPTS = 400
local MAX_NAMES = 40
local MAX_REMOTES = 200
local PAGE_SIZE = 8 -- entries per page in the review list, keeps the window light

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
local toggle = toolbar:CreateButton("CTR Lab", "Open CTR Lab Connect", "rbxassetid://127805693114615")
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
make("UIListLayout", { Padding = UDim.new(0, 18), SortOrder = Enum.SortOrder.LayoutOrder }, page)
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

local function card(order, number, title)
	local f = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = CARD,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, page)
	corner(f, 16)
	stroke(f, LIME, 1, 0.75)
	glow(f, 22, 0.84)
	pad(f, 16)
	make("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	local head = label(f, string.format('<font color="#AAFF00">%s</font>    %s', number, title), 15, INK, FONT_BOLD, 0)
	head.RichText = true
	return f
end

-- Primary: lime fill. Ghost: dark with lime text and outline. Both glow on hover, like the Hub.
local function button(parent, text, order, primary, size)
	local rest = primary and LIME or BG
	local hover = primary and LIME_HOVER or CARD_HOVER
	local idleGlow = primary and 0.8 or 1
	local hoverGlow = primary and 0.55 or 0.8
	local b = make("TextButton", {
		Size = size or UDim2.new(1, 0, 0, 42),
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
-- Layout: header, notice, 1 Connect, 2 Review and send, 3 Result, footer
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
label(header, "Turn your game into a thumbnail brief.", 13, MUTED, FONT, 2)

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

local notice = label(page, "", 13, RED, FONT, 2)
notice.Visible = false

-- Shown when CTR Lab says a newer version exists. It uses the answers of the two requests above, so nothing extra is sent.
local updateNote = label(page, "", 12, LIME, FONT, 2)
updateNote.Visible = false

-- 1 Connect
local connectCard = card(3, "1", "Connect")
local statusLabel = label(connectCard, "", 13, MUTED, FONT, 1)
local codeBox = make("TextBox", {
	Size = UDim2.new(1, 0, 0, 46),
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
local disconnectBtn = button(connectCard, "Disconnect", 4, false)

-- 2 Review and send
local reviewCard = card(4, "2", "Review and send")
label(reviewCard, "See exactly what would be sent. Nothing leaves Studio until you press Send.", 13, MUTED, FONT, 1)
local reviewBtn = button(reviewCard, "Review this place", 2, true)
local statsLabel = label(reviewCard, "", 13, LIME, FONT_BOLD, 3)
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
local sendBtn = button(reviewCard, "Send to CTR Lab", 6, true)

-- 3 Result
local resultCard = card(5, "3", "Your thumbnail brief")
local summaryLabel = label(resultCard, "", 13, MUTED, FONT, 1)
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
	LayoutOrder = 2,
}, resultCard)
corner(promptBox, 12)
stroke(promptBox, LIME, 1, 0.7)
pad(promptBox, 12)
label(resultCard, "Select the text, copy it, and paste it into the CTR Lab chat.", 12, MUTED, FONT, 3)
local ideasLabel = label(resultCard, "", 13, INK, FONT, 4)

label(page, "No source code is ever sent  ·  ctr-lab.com/plugin", 11, MUTED, FONT, 6)

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
-- Reading the place. Only names and counts, never the source text.
---------------------------------------------------------------------------
local function collect()
	local scripts, serviceSet, remoteNames = {}, {}, {}
	local instanceCount, scriptTotal = 0, 0
	for _, obj in ipairs(game:GetDescendants()) do
		instanceCount = instanceCount + 1
		if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) and #remoteNames < MAX_REMOTES then
			table.insert(remoteNames, obj:GetFullName())
		end
		if obj:IsA("LuaSourceContainer") then
			scriptTotal = scriptTotal + 1
			if #scripts < MAX_SCRIPTS then
				local src = obj.Source
				local _, newlines = string.gsub(src, "\n", "")
				local functions, requires = {}, {}
				for name in string.gmatch(src, "function%s+([%w_%.:]+)") do
					if #functions < MAX_NAMES then
						table.insert(functions, string.sub(name, 1, 80))
					end
				end
				for path in string.gmatch(src, "require%(([^)\n]+)%)") do
					if #requires < MAX_NAMES then
						table.insert(requires, string.sub(path, 1, 120))
					end
				end
				for svc in string.gmatch(src, 'GetService%("([%w_]+)"%)') do
					serviceSet[svc] = true
				end
				table.insert(scripts, {
					path = obj:GetFullName(),
					class = obj.ClassName,
					lines = newlines + 1,
					functions = functions,
					requires = requires,
				})
			end
		end
	end
	local services = {}
	for svc in pairs(serviceSet) do
		table.insert(services, svc)
	end
	table.sort(services)
	return {
		place_name = game.Name,
		place_id = game.PlaceId,
		stats = { instances = instanceCount, scripts = scriptTotal, remotes = #remoteNames },
		scripts = scripts,
		remotes = remoteNames,
		services = services,
	}
end

-- The exact content of the summary as readable entries, so the user can check it before sending.
local function buildItems(payload)
	local items = {}
	local head = string.format("Place: %s  (place ID %.0f)", payload.place_name, payload.place_id)
	head = head .. "\nServices: " .. (#payload.services > 0 and table.concat(payload.services, ", ") or "none")
	table.insert(items, head)
	for _, r in ipairs(payload.remotes) do
		table.insert(items, "Remote  " .. r)
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
-- State and rendering
---------------------------------------------------------------------------
local pending = nil -- the summary the user is reviewing, not sent yet
local items = {}
local pageIndex = 1
local pageCount = 1
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
	statusLabel.Text = connected and "Connected to your CTR Lab account."
		or "Create a 6-digit code in your CTR Lab library under Games, then enter it here."
	statusLabel.TextColor3 = connected and LIME or MUTED
	codeBox.Visible = not connected
	connectBtn.Visible = not connected
	disconnectBtn.Visible = connected

	reviewCard.Visible = connected
	local reviewing = connected and pending ~= nil
	statsLabel.Visible = reviewing
	previewBox.Visible = reviewing
	pager.Visible = reviewing and pageCount > 1
	sendBtn.Visible = reviewing
	reviewBtn.Text = reviewing and "Review again" or "Review this place"
	reviewBtn.Visible = true

	resultCard.Visible = connected and result ~= nil
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
		render()
	end)
end)

disconnectBtn.Activated:Connect(function()
	run(function()
		plugin:SetSetting(TOKEN_KEY, nil)
		pending = nil
		items = {}
		result = nil
		notify("", false)
		render()
	end)
end)

reviewBtn.Activated:Connect(function()
	run(function()
		notify("", false)
		result = nil
		reviewBtn.Text = "Reading..."
		task.wait() -- let the window redraw before the scan
		local payload = collect()
		pending = payload
		items = buildItems(payload)
		pageCount = math.max(1, math.ceil(#items / PAGE_SIZE))
		pageIndex = 1
		statsLabel.Text = string.format(
			"%d scripts  ·  %d remotes  ·  %d instances",
			payload.stats.scripts,
			payload.stats.remotes,
			payload.stats.instances
		)
		showPage()
		render()
	end)
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

toggle.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggle:SetActive(widget.Enabled)
end)

render()
