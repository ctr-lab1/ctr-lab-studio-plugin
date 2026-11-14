--[[
	CTR Lab Connect for Roblox Studio
	Version 0.4.0 (closed beta)

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

	INSTALL
	  1. In Studio add a new Script, paste this whole file into it.
	  2. Right-click the Script, choose "Save as Local Plugin...", then delete the Script.
	  3. Open the "CTR Lab" button in the Plugins tab.

	MIT License

	Copyright (c) CTR Lab

	Permission is hereby granted, free of charge, to any person obtaining a copy of this software
	and associated documentation files (the "Software"), to deal in the Software without
	restriction, including without limitation the rights to use, copy, modify, merge, publish,
	distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
	Software is furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all copies or
	substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
	BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
	NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
	DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

local HttpService = game:GetService("HttpService")

local API = "https://ctr-lab.com/api/apps/6af3066f697d7b1811bcf9a9/functions/"
local TOKEN_KEY = "CTRLabToken"
local VERSION = "0.4.0"
local MAX_SCRIPTS = 400
local MAX_NAMES = 40
local MAX_REMOTES = 200
local PAGE_SIZE = 8 -- entries per page in the review list, keeps the window light

-- Colours match the CTR Lab website (dark with a lime green accent).
local C = {
	bg = Color3.fromRGB(9, 11, 10),
	card = Color3.fromRGB(16, 19, 18),
	input = Color3.fromRGB(26, 30, 28),
	border = Color3.fromRGB(35, 41, 38),
	text = Color3.fromRGB(245, 247, 245),
	muted = Color3.fromRGB(161, 175, 168),
	green = Color3.fromRGB(166, 255, 0),
	greenHover = Color3.fromRGB(190, 255, 60),
	onGreen = Color3.fromRGB(6, 14, 10),
	red = Color3.fromRGB(255, 107, 107),
}
local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local toolbar = plugin:CreateToolbar("CTR Lab")
local toggle = toolbar:CreateButton("CTR Lab", "Open CTR Lab Connect", "")
toggle.ClickableWhenViewportHidden = true

local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 340, 560, 300, 360)
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

local function corner(parent, radius)
	return make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function stroke(parent, color)
	return make("UIStroke", { Color = color, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

local function pad(parent, amount)
	return make("UIPadding", {
		PaddingTop = UDim.new(0, amount),
		PaddingBottom = UDim.new(0, amount),
		PaddingLeft = UDim.new(0, amount),
		PaddingRight = UDim.new(0, amount),
	}, parent)
end

-- Roblox's own UIShadow. Wrapped in pcall so an older Studio simply shows no shadow.
local function shadow(parent)
	pcall(function()
		make("UIShadow", {
			Color = Color3.new(0, 0, 0),
			Transparency = 0.5,
			BlurRadius = UDim.new(0, 12),
			Offset = UDim2.fromOffset(0, 3),
			ShowBehindParent = true,
		}, parent)
	end)
end

local page = make("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.bg,
	BorderSizePixel = 0,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = C.border,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, widget)
make("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, page)
pad(page, 16)

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

local function card(order, title)
	local f = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.card,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, page)
	corner(f, 12)
	stroke(f, C.border)
	shadow(f)
	pad(f, 14)
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	label(f, title, 15, C.text, FONT_BOLD, 0)
	return f
end

local function button(parent, text, order, primary, size)
	local base = primary and C.green or C.input
	local hover = primary and C.greenHover or C.border
	local b = make("TextButton", {
		Size = size or UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = base,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = text,
		TextColor3 = primary and C.onGreen or C.text,
		Font = FONT_BOLD,
		TextSize = 14,
		LayoutOrder = order,
	}, parent)
	corner(b, 8)
	if not primary then
		stroke(b, C.border)
	end
	b.MouseEnter:Connect(function()
		b.BackgroundColor3 = hover
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = base
	end)
	return b
end

---------------------------------------------------------------------------
-- Layout: header, notice, 1 Connect, 2 Review, 3 Result, footer
---------------------------------------------------------------------------
local header = make("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	LayoutOrder = 1,
}, page)
make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, header)
label(header, "CTR Lab", 22, C.green, FONT_BOLD, 1)
label(header, "Turn your game into a thumbnail brief.", 13, C.muted, FONT, 2)

local notice = label(page, "", 13, C.red, FONT, 2)
notice.Visible = false

-- 1 Connect
local connectCard = card(3, "1   Connect")
local statusLabel = label(connectCard, "", 13, C.muted, FONT, 1)
local codeBox = make("TextBox", {
	Size = UDim2.new(1, 0, 0, 38),
	BackgroundColor3 = C.input,
	BorderSizePixel = 0,
	PlaceholderText = "6-digit code",
	PlaceholderColor3 = C.muted,
	Text = "",
	TextColor3 = C.text,
	ClearTextOnFocus = false,
	Font = Enum.Font.Code,
	TextSize = 18,
	LayoutOrder = 2,
}, connectCard)
corner(codeBox, 8)
local codeStroke = stroke(codeBox, C.border)
codeBox.Focused:Connect(function()
	codeStroke.Color = C.green
end)
codeBox.FocusLost:Connect(function()
	codeStroke.Color = C.border
end)
local connectBtn = button(connectCard, "Connect", 3, true)
local disconnectBtn = button(connectCard, "Disconnect", 4, false)

-- 2 Review and send
local reviewCard = card(4, "2   Review and send")
label(reviewCard, "See exactly what would be sent. Nothing leaves Studio until you press Send.", 13, C.muted, FONT, 1)
local reviewBtn = button(reviewCard, "Review this place", 2, true)
local statsLabel = label(reviewCard, "", 13, C.green, FONT_BOLD, 3)
local previewBox = make("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = C.input,
	BorderSizePixel = 0,
	LayoutOrder = 4,
}, reviewCard)
corner(previewBox, 8)
pad(previewBox, 10)
local previewLabel = label(previewBox, "", 12, C.text, Enum.Font.Code, 1)
local pager = make("Frame", {
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundTransparency = 1,
	LayoutOrder = 5,
}, reviewCard)
local prevBtn = button(pager, "Back", 1, false, UDim2.new(0.28, 0, 1, 0))
prevBtn.Position = UDim2.fromScale(0, 0)
local pageLabel = make("TextLabel", {
	Size = UDim2.new(0.44, 0, 1, 0),
	Position = UDim2.fromScale(0.28, 0),
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = C.muted,
	Font = FONT,
	TextSize = 13,
}, pager)
local nextBtn = button(pager, "Next", 3, false, UDim2.new(0.28, 0, 1, 0))
nextBtn.Position = UDim2.fromScale(0.72, 0)
local sendBtn = button(reviewCard, "Send to CTR Lab", 6, true)

-- 3 Result
local resultCard = card(5, "3   Your thumbnail brief")
local summaryLabel = label(resultCard, "", 13, C.muted, FONT, 1)
local promptBox = make("TextBox", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = C.input,
	BorderSizePixel = 0,
	Text = "",
	TextColor3 = C.text,
	TextWrapped = true,
	MultiLine = true,
	ClearTextOnFocus = false,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Font = FONT,
	TextSize = 13,
	LayoutOrder = 2,
}, resultCard)
corner(promptBox, 8)
pad(promptBox, 10)
label(resultCard, "Select the text, copy it, and paste it into the CTR Lab chat.", 12, C.muted, FONT, 3)
local ideasLabel = label(resultCard, "", 13, C.text, FONT, 4)

label(page, "v" .. VERSION .. "  ·  No source code is ever sent  ·  ctr-lab.com/plugin", 11, C.muted, FONT, 6)

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

local function notify(text, isError)
	notice.Text = text
	notice.TextColor3 = isError and C.red or C.green
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
		or "Create a 6-digit code in your CTR Lab account, then enter it here."
	statusLabel.TextColor3 = connected and C.green or C.muted
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
