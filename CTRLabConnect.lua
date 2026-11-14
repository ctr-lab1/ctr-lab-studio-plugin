--[[
	CTR Lab Connect for Roblox Studio
	Version 0.2.0 (closed beta)

	WHAT IT DOES
	Reads the structure of the place you have open and, only after you review it and press "Send",
	sends a summary to ctr-lab.com. CTR Lab turns that summary into a game description and a
	thumbnail brief you can use in the CTR Lab chat.

	WHAT IT SENDS (shown to you in full before anything leaves Studio)
	  place name, instance / script / remote counts, script paths and class names, line counts,
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
local MAX_SCRIPTS = 400
local MAX_NAMES = 40
local MAX_REMOTES = 200

local toolbar = plugin:CreateToolbar("CTR Lab")
local toggle = toolbar:CreateButton("CTR Lab", "Connect this place to CTR Lab", "")
toggle.ClickableWhenViewportHidden = true

local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 340, 520, 300, 320)
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

local scroll = make("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(24, 24, 28),
	BorderSizePixel = 0,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	ScrollBarThickness = 6,
}, widget)
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
make("UIPadding", {
	PaddingTop = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
	PaddingBottom = UDim.new(0, 12),
}, scroll)

local function addLabel(text, order)
	return make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Color3.fromRGB(230, 230, 235),
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		LayoutOrder = order,
	}, scroll)
end

local function addButton(text, order, color, onClick)
	local b = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		LayoutOrder = order,
	}, scroll)
	b.Activated:Connect(onClick)
	return b
end

local function addBox(order, minHeight)
	return make("TextBox", {
		Size = UDim2.new(1, 0, 0, minHeight),
		AutomaticSize = Enum.AutomaticSize.Y,
		MultiLine = true,
		TextWrapped = true,
		ClearTextOnFocus = false,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		BackgroundColor3 = Color3.fromRGB(40, 40, 46),
		BorderSizePixel = 0,
		TextColor3 = Color3.fromRGB(230, 230, 235),
		Font = Enum.Font.Code,
		TextSize = 13,
		LayoutOrder = order,
		Visible = false,
	}, scroll)
end

local status = addLabel("Not connected. Create a code in your CTR Lab account and enter it below.", 1)

local codeBox = make("TextBox", {
	Size = UDim2.new(1, 0, 0, 32),
	PlaceholderText = "6-digit code",
	Text = "",
	ClearTextOnFocus = false,
	TextColor3 = Color3.new(1, 1, 1),
	BackgroundColor3 = Color3.fromRGB(40, 40, 46),
	BorderSizePixel = 0,
	Font = Enum.Font.Code,
	TextSize = 16,
	LayoutOrder = 2,
}, scroll)

local pending = nil -- the summary the user is reviewing, not sent yet

local previewTitle = addLabel("This is everything that will be sent (no source code):", 7)
previewTitle.Visible = false
local previewBox = addBox(8, 120)
local resultTitle = addLabel("Thumbnail brief (copy it into the CTR Lab chat):", 9)
resultTitle.Visible = false
local resultBox = addBox(10, 120)
local improvements = addLabel("", 11)
improvements.Visible = false

local function setStatus(text)
	status.Text = text
end

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

-- Builds the summary. Only names and counts, never the source text.
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
		stats = { instances = instanceCount, scripts = scriptTotal, remotes = #remoteNames },
		scripts = scripts,
		remotes = remoteNames,
		services = services,
	}
end

-- The exact content of the summary, as readable text, so the user can check it before sending.
local function describe(payload)
	local lines = {}
	table.insert(lines, "Place: " .. payload.place_name)
	table.insert(
		lines,
		string.format(
			"%d instances, %d scripts, %d remotes",
			payload.stats.instances,
			payload.stats.scripts,
			payload.stats.remotes
		)
	)
	table.insert(lines, "Services: " .. (#payload.services > 0 and table.concat(payload.services, ", ") or "none"))
	table.insert(lines, "")
	table.insert(lines, "Remotes:")
	if #payload.remotes == 0 then
		table.insert(lines, "  (none)")
	end
	for _, r in ipairs(payload.remotes) do
		table.insert(lines, "  " .. r)
	end
	table.insert(lines, "")
	table.insert(lines, "Scripts:")
	for _, s in ipairs(payload.scripts) do
		local line = string.format("  %s (%s, %d lines)", s.path, s.class, s.lines)
		if #s.functions > 0 then
			line = line .. "\n    functions: " .. table.concat(s.functions, ", ")
		end
		if #s.requires > 0 then
			line = line .. "\n    requires: " .. table.concat(s.requires, ", ")
		end
		table.insert(lines, line)
	end
	return table.concat(lines, "\n")
end

local function clearResults()
	pending = nil
	previewTitle.Visible = false
	previewBox.Visible = false
	resultTitle.Visible = false
	resultBox.Visible = false
	improvements.Visible = false
end

local sendButton

addButton("Connect", 3, Color3.fromRGB(59, 130, 246), function()
	local code = string.gsub(codeBox.Text, "%s", "")
	if not string.match(code, "^%d%d%d%d%d%d$") then
		setStatus("Enter the 6-digit code from your CTR Lab account.")
		return
	end
	setStatus("Connecting...")
	local data, err = request("pluginPair", { code = code, label = "Roblox Studio" })
	if not data or not data.token then
		setStatus(err or "Connection failed.")
		return
	end
	plugin:SetSetting(TOKEN_KEY, data.token)
	codeBox.Text = ""
	setStatus("Connected. Press Review to see what would be sent. Nothing is sent yet.")
end)

addButton("Review this place", 4, Color3.fromRGB(34, 160, 90), function()
	if not plugin:GetSetting(TOKEN_KEY) then
		setStatus("Connect first with a code from your CTR Lab account.")
		return
	end
	clearResults()
	setStatus("Reading the place structure. No source code is collected...")
	task.wait()
	local payload = collect()
	pending = payload
	previewBox.Text = describe(payload)
	previewTitle.Visible = true
	previewBox.Visible = true
	sendButton.Visible = true
	setStatus("Nothing has been sent yet. Check the list below, then press Send to CTR Lab.")
end)

sendButton = addButton("Send to CTR Lab", 5, Color3.fromRGB(217, 119, 6), function()
	local token = plugin:GetSetting(TOKEN_KEY)
	if not token or not pending then
		setStatus("Press Review first.")
		return
	end
	setStatus(string.format("Sending %d scripts and %d remotes...", #pending.scripts, #pending.remotes))
	local data, err, code = request("pluginAnalyze", pending, token)
	if not data or not data.analysis then
		if code == 401 then
			plugin:SetSetting(TOKEN_KEY, nil)
			err = "The link was removed. Connect again with a new code."
		end
		setStatus(err or "The analysis failed.")
		return
	end
	local a = data.analysis
	local summary = type(a.spec) == "table" and a.spec.summary or nil
	clearResults()
	sendButton.Visible = false
	setStatus("Done. Saved in your CTR Lab account. " .. (summary or ""))
	resultBox.Text = a.prompt or ""
	resultTitle.Visible = true
	resultBox.Visible = true
	if type(a.improvements) == "table" and #a.improvements > 0 then
		improvements.Text = "Ideas:\n- " .. table.concat(a.improvements, "\n- ")
		improvements.Visible = true
	end
end)
sendButton.Visible = false

addButton("Disconnect", 6, Color3.fromRGB(90, 90, 100), function()
	plugin:SetSetting(TOKEN_KEY, nil)
	clearResults()
	sendButton.Visible = false
	setStatus("Disconnected. This Studio no longer has access to your account.")
end)

if plugin:GetSetting(TOKEN_KEY) then
	setStatus("Connected. Press Review to see what would be sent. Nothing is sent yet.")
end

toggle.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
