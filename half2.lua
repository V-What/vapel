print("HALF2 START")

--------------------------------------------------------------------------------
-- Splash d'injection : jouee UNE SEULE fois au chargement du script (pas a
-- chaque ouverture du menu) - vraie barre de progression qui se remplit sur
-- ~1.1s, plutot que les points de playLoadingIntro (reserves aux ouvertures
-- manuelles). A la fin, la fenetre se referme : le menu reste cache par
-- defaut comme avant, la splash sert juste a confirmer le chargement.
--------------------------------------------------------------------------------

local InjectionOverlay = create("Frame", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundColor3 = Theme.Background,
	ZIndex = 25,
	Visible = false,
	Active = true,
}, Main)
corner(InjectionOverlay, 12)

local InjectionLogo = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, -46),
	Size = UDim2.new(0, 64, 0, 64),
	BackgroundColor3 = Theme.Accent,
	ZIndex = 26,
}, InjectionOverlay)
corner(InjectionLogo, 18)
gradient(InjectionLogo, ColorSequence.new(Theme.Accent, Theme.AccentDim), 45)
create("TextLabel", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Text = "V",
	Font = Enum.Font.GothamBold,
	TextSize = 34,
	TextColor3 = Color3.new(1, 1, 1),
	ZIndex = 27,
}, InjectionLogo)

create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 8),
	Size = UDim2.new(0, 240, 0, 26),
	BackgroundTransparency = 1,
	Text = "Von Client",
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	TextColor3 = Theme.Text,
	ZIndex = 26,
}, InjectionOverlay)

local ProgressBarBack = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 42),
	Size = UDim2.new(0, 220, 0, 6),
	BackgroundColor3 = Theme.Element,
	ZIndex = 26,
}, InjectionOverlay)
corner(ProgressBarBack, 3)

local ProgressBarFill = create("Frame", {
	Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = Theme.Accent,
	ZIndex = 27,
}, ProgressBarBack)
corner(ProgressBarFill, 3)
gradient(ProgressBarFill, ColorSequence.new(Theme.Accent, Theme.AccentDim), 0)

local ProgressLabel = create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 64),
	Size = UDim2.new(0, 220, 0, 16),
	BackgroundTransparency = 1,
	Text = "Chargement... 0%",
	Font = Enum.Font.GothamMedium,
	TextSize = 12,
	TextColor3 = Theme.SubText,
	ZIndex = 26,
}, InjectionOverlay)

local function playInjectionSplash()
	InjectionOverlay.Visible = true
	InjectionOverlay.BackgroundTransparency = 0
	ProgressBarFill.Size = UDim2.new(0, 0, 1, 0)
	ProgressLabel.Text = "Chargement... 0%"

	Main.Visible = true
	WindowGlow.Visible = true
	WindowShadow.Visible = true
	WindowGlow.BackgroundTransparency = 1
	WindowShadow.BackgroundTransparency = 1
	Main.Size = scaledSize(targetSize, WINDOW_OPEN_SCALE)
	tweenStyled(Main, { Size = targetSize }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	tween(WindowGlow, { BackgroundTransparency = WINDOW_GLOW_TRANSPARENCY }, 0.28)
	tween(WindowShadow, { BackgroundTransparency = WINDOW_SHADOW_TRANSPARENCY }, 0.28)

	local DURATION = 1.1
	local startTime = os.clock()
	task.spawn(function()
		while true do
			local pct = math.clamp((os.clock() - startTime) / DURATION, 0, 1)
			ProgressBarFill.Size = UDim2.new(pct, 0, 1, 0)
			ProgressLabel.Text = string.format("Chargement... %d%%", math.floor(pct * 100))
			if pct >= 1 then break end
			task.wait()
		end
	end)

	task.delay(DURATION + 0.15, function()
		tween(InjectionOverlay, { BackgroundTransparency = 1 }, 0.25)
		task.delay(0.25, function()
			InjectionOverlay.Visible = false
			-- Le menu reste ouvert apres la splash (pas de closeWindow() ici).
		end)
	end)
end

-- Pas de fond visible : juste un Frame transparent qui sert de zone de drag
-- et de conteneur pour le logo/titre/bouton fermer, poses directement sur le
-- fond de Main (plus de "barre noire" separee).
local TopBar = create("Frame", { Size = UDim2.new(1, 0, 0, TOPBAR_HEIGHT), BackgroundTransparency = 1 }, Main)

-- Logo : monogramme "V" en attendant un vrai logo (remplace juste ce Frame
-- par une ImageLabel avec Image = "rbxassetid://..." le jour ou tu en as un).
local LOGO_SIZE = 56
local Logo = create("Frame", {
	Position = UDim2.new(0, 14, 0, (TOPBAR_HEIGHT - LOGO_SIZE) / 2),
	Size = UDim2.new(0, LOGO_SIZE, 0, LOGO_SIZE),
	BackgroundColor3 = Theme.Accent,
}, TopBar)
corner(Logo, 15)
gradient(Logo, ColorSequence.new(Theme.Accent, Theme.AccentDim), 45)
create("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.85, Thickness = 1 }, Logo)
create("TextLabel", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Text = "V",
	Font = Enum.Font.GothamBold,
	TextSize = 30,
	TextColor3 = Color3.new(1, 1, 1),
}, Logo)

local titleLeft = 14 + LOGO_SIZE + 12
local titleWidth = 1 -- Scale ; l'offset negatif ci-dessous laisse la place au bouton fermer
local TITLE_HEIGHT, SUBTITLE_HEIGHT, TITLE_GAP = 28, 18, 4
local titleTop = (TOPBAR_HEIGHT - (TITLE_HEIGHT + TITLE_GAP + SUBTITLE_HEIGHT)) / 2

create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, titleLeft, 0, titleTop),
	Size = UDim2.new(titleWidth, -(titleLeft + 54), 0, TITLE_HEIGHT),
	Text = "Von Client",
	Font = Enum.Font.GothamBold,
	TextSize = 26,
	TextColor3 = Theme.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
}, TopBar)

create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, titleLeft, 0, titleTop + TITLE_HEIGHT + TITLE_GAP),
	Size = UDim2.new(titleWidth, -(titleLeft + 54), 0, SUBTITLE_HEIGHT),
	Text = "Menu de controle",
	Font = Enum.Font.GothamMedium,
	TextSize = 13,
	TextColor3 = Theme.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
}, TopBar)

local CloseButton = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.5, 0),
	Size = UDim2.new(0, 38, 0, 38),
	BackgroundColor3 = Theme.Element,
	Text = "X",
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextColor3 = Theme.Text,
	AutoButtonColor = false,
}, TopBar)
corner(CloseButton, 10)
CloseButton.MouseButton1Click:Connect(closeWindow)
CloseButton.MouseEnter:Connect(function() tween(CloseButton, { BackgroundColor3 = Theme.Danger }, 0.1) end)
CloseButton.MouseLeave:Connect(function() tween(CloseButton, { BackgroundColor3 = Theme.Element }, 0.1) end)

-- Drag de la fenetre (via la barre de titre)
do
	local dragging, dragStart, startPos
	TopBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = Main.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

-- Redimensionnement (poignee en bas a droite), clampe entre les tailles min/max,
-- sauvegarde dans Settings pour retrouver la meme taille au prochain chargement.
local ResizeHandle = create("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -3, 1, -3),
	Size = UDim2.new(0, 14, 0, 14),
	BackgroundColor3 = Theme.Stroke,
	BackgroundTransparency = 0.4,
	Active = true,
	ZIndex = 10, -- cree avant Sidebar/PagesHolder : sans ca, ces derniers (meme ZIndex par defaut) le recouvriraient
}, Main)
corner(ResizeHandle, 3)
ResizeHandle.MouseEnter:Connect(function() tween(ResizeHandle, { BackgroundTransparency = 0 }, 0.1) end)
ResizeHandle.MouseLeave:Connect(function() tween(ResizeHandle, { BackgroundTransparency = 0.4 }, 0.1) end)

do
	local resizing, resizeStart, startSize
	ResizeHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			resizing = true
			resizeStart = input.Position
			startSize = Main.Size
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					resizing = false
					savePrefs()
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - resizeStart
			local newWidth = math.clamp(startSize.X.Offset + delta.X, WINDOW_MIN_WIDTH, WINDOW_MAX_WIDTH)
			local newHeight = math.clamp(startSize.Y.Offset + delta.Y, WINDOW_MIN_HEIGHT, WINDOW_MAX_HEIGHT)
			targetSize = UDim2.new(0, newWidth, 0, newHeight)
			Main.Size = targetSize
			Prefs.WindowWidth = newWidth
			Prefs.WindowHeight = newHeight
		end
	end)
end

local SIDEBAR_WIDTH = 150

local Sidebar = create("Frame", {
	Position = UDim2.new(0, 0, 0, TOPBAR_HEIGHT),
	Size = UDim2.new(0, SIDEBAR_WIDTH, 1, -TOPBAR_HEIGHT),
	BackgroundColor3 = Theme.Panel,
}, Main)
create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, Sidebar)
create("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, Sidebar)

local PagesHolder = create("Frame", {
	Position = UDim2.new(0, SIDEBAR_WIDTH, 0, TOPBAR_HEIGHT),
	Size = UDim2.new(1, -SIDEBAR_WIDTH, 1, -TOPBAR_HEIGHT),
	BackgroundTransparency = 1,
}, Main)

local pages, sidebarButtons, currentPage = {}, {}, nil

local function selectPage(name)
	if currentPage then
		local prev = sidebarButtons[currentPage]
		prev.Button.BackgroundColor3 = Theme.Element
		prev.Label.TextColor3 = Theme.SubText
		pages[currentPage].Visible = false
	end

	local current = sidebarButtons[name]
	pages[name].Visible = true
	current.Button.BackgroundColor3 = Theme.ElementHover
	current.Label.TextColor3 = current.AccentColor
	currentPage = name
end

-- Chaque categorie a sa propre barre d'accent (pas juste celle qui est
-- selectionnee) : plus besoin d'un indicateur qui glisse dans un calque a
-- part, donc plus de risque de conflit avec le UIListLayout de Sidebar.
local function createCategory(name, accentColor)
	local Button = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = Theme.Element,
		Text = "",
		AutoButtonColor = false,
	}, Sidebar)
	corner(Button, 8)

	local AccentBar = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.new(0, 4, 1, -16),
		BackgroundColor3 = accentColor or Theme.Accent,
	}, Button)
	corner(AccentBar, 2)

	local Label = create("TextLabel", {
		Position = UDim2.new(0, 20, 0, 0),
		Size = UDim2.new(1, -26, 1, 0),
		BackgroundTransparency = 1,
		Text = name,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, Button)

	Button.MouseButton1Click:Connect(function() selectPage(name) end)
	Button.MouseEnter:Connect(function()
		if currentPage ~= name then tween(Button, { BackgroundColor3 = Theme.Stroke }, 0.1) end
	end)
	Button.MouseLeave:Connect(function()
		if currentPage ~= name then tween(Button, { BackgroundColor3 = Theme.Element }, 0.1) end
	end)

	local Page = create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Accent,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, PagesHolder)
	create("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, Page)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 14), PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14),
	}, Page)

	pages[name] = Page
	sidebarButtons[name] = { Button = Button, Label = Label, AccentColor = accentColor or Theme.Accent }
	return Page
end

-- Card avec liseré d'accent plein-hauteur a gauche (façon callout/alert box
-- moderne) et titre a l'interieur, a droite du lisere. ClipsDescendants fait
-- epouser le lisere au coin arrondi de la card au lieu de deborder en carre.
local function addSection(page, title)
	local Card = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		ClipsDescendants = true,
	}, page)
	corner(Card, 12)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.15 }, Card)

	-- Meme style que l'indicateur de la sidebar (barre fine et pleine, sans degrade).
	local AccentBar = create("Frame", {
		Position = UDim2.new(0, 4, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(0, 3, 1, -12),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
	}, Card)
	corner(AccentBar, 2)

	create("TextLabel", {
		Position = UDim2.new(0, 20, 0, 14),
		Size = UDim2.new(1, -36, 0, 22),
		BackgroundTransparency = 1,
		Text = title,
		Font = Enum.Font.GothamBold,
		TextSize = 17,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, Card)

	local Content = create("Frame", {
		Position = UDim2.new(0, 20, 0, 44),
		Size = UDim2.new(1, -36, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, Card)
	create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, Content)
	create("UIPadding", { PaddingBottom = UDim.new(0, 18) }, Content)

	return Content
end

local function addToggleRow(content, text, default, onChange)
	local state = default or false

	local Row = create("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1 }, content)
	create("TextLabel", {
		Size = UDim2.new(1, -66, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, Row)

	local ON_POSITION, OFF_POSITION = UDim2.new(1, -25, 0.5, -11), UDim2.new(0, 3, 0.5, -11)

	local Switch = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 52, 0, 28),
		BackgroundColor3 = state and Theme.Accent or Theme.Element,
	}, Row)
	corner(Switch, 14)
	-- Fin liseré accent qui s'estompe quand le switch est off, s'illumine quand on.
	local switchGlow = create("UIStroke", { Color = Theme.Accent, Thickness = 1.5, Transparency = state and 0.5 or 1 }, Switch)

	local Knob = create("Frame", {
		Size = UDim2.new(0, 22, 0, 22),
		Position = state and ON_POSITION or OFF_POSITION,
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, Switch)
	corner(Knob, 11)

	local Click = create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "" }, Switch)

	local function set(newState)
		state = newState
		tween(Switch, { BackgroundColor3 = state and Theme.Accent or Theme.Element }, 0.15)
		tween(switchGlow, { Transparency = state and 0.5 or 1 }, 0.15)
		tweenStyled(Knob, { Position = state and ON_POSITION or OFF_POSITION }, 0.2)
		if onChange then onChange(state) end
	end
	Click.MouseButton1Click:Connect(function() set(not state) end)

	return { Set = set, Get = function() return state end }
end

local function addDropdownRow(content, text, options, default, onChange)
	local selected = default or options[1]
	local HEADER_HEIGHT, SEARCH_HEIGHT, OPTION_HEIGHT = 40, 36, 34

	local Holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		BackgroundColor3 = Theme.Element,
		ClipsDescendants = true,
	}, content)
	corner(Holder, 8)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.4 }, Holder)

	local MainButton = create("TextButton", {
		Size = UDim2.new(1, -30, 0, HEADER_HEIGHT),
		BackgroundTransparency = 1,
		Text = text .. ": " .. tostring(selected),
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
	}, Holder)

	local Chevron = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.new(0, 18, 0, 18),
		BackgroundTransparency = 1,
		Text = "▾",
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Theme.SubText,
	}, Holder)

	-- Barre de recherche : fond Panel (plus sombre que le Holder en Element,
	-- effet "en creux") pour bien la distinguer. Filtre les options en direct.
	local SearchBox = create("TextBox", {
		Position = UDim2.new(0, 8, 0, HEADER_HEIGHT + 4),
		Size = UDim2.new(1, -16, 0, SEARCH_HEIGHT - 8),
		BackgroundColor3 = Theme.Panel,
		Text = "",
		PlaceholderText = "Rechercher...",
		PlaceholderColor3 = Theme.SubText,
		TextColor3 = Theme.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		ClearTextOnFocus = false,
	}, Holder)
	corner(SearchBox, 6)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.3 }, SearchBox)
	create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, SearchBox)

	local List = create("Frame", {
		Position = UDim2.new(0, 0, 0, HEADER_HEIGHT + SEARCH_HEIGHT),
		Size = UDim2.new(1, 0, 0, #options * OPTION_HEIGHT),
		BackgroundTransparency = 1,
	}, Holder)
	create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, List)

	local optionButtons = {}
	local open = false

	local function visibleOptionCount()
		local count = 0
		for _, btn in ipairs(optionButtons) do
			if btn.Visible then count = count + 1 end
		end
		return count
	end

	local function resizeOpen()
		tween(Holder, { Size = UDim2.new(1, 0, 0, HEADER_HEIGHT + SEARCH_HEIGHT + visibleOptionCount() * OPTION_HEIGHT) }, 0.12)
	end

	local function applyFilter()
		local query = SearchBox.Text:lower()
		for _, btn in ipairs(optionButtons) do
			btn.Visible = query == "" or btn.Text:lower():find(query, 1, true) ~= nil
		end
		if open then resizeOpen() end
	end

	local function close()
		open = false
		tween(Holder, { Size = UDim2.new(1, 0, 0, HEADER_HEIGHT) })
		tween(Chevron, { Rotation = 0 }, 0.15)
		SearchBox.Text = ""
		applyFilter()
	end

	for _, option in ipairs(options) do
		local OptButton = create("TextButton", {
			Size = UDim2.new(1, 0, 0, OPTION_HEIGHT),
			BackgroundColor3 = Theme.Stroke,
			BackgroundTransparency = 1,
			Text = tostring(option),
			Font = Enum.Font.GothamMedium,
			TextSize = 14,
			TextColor3 = Theme.SubText,
		}, List)
		table.insert(optionButtons, OptButton)
		OptButton.MouseEnter:Connect(function() tween(OptButton, { BackgroundTransparency = 0.4 }, 0.1) end)
		OptButton.MouseLeave:Connect(function() tween(OptButton, { BackgroundTransparency = 1 }, 0.1) end)
		OptButton.MouseButton1Click:Connect(function()
			selected = option
			MainButton.Text = text .. ": " .. tostring(selected)
			close()
			if onChange then onChange(selected) end
		end)
	end

	SearchBox:GetPropertyChangedSignal("Text"):Connect(applyFilter)

	MainButton.MouseEnter:Connect(function() tween(Holder, { BackgroundColor3 = Theme.Stroke }, 0.1) end)
	MainButton.MouseLeave:Connect(function() tween(Holder, { BackgroundColor3 = Theme.Element }, 0.1) end)

	MainButton.MouseButton1Click:Connect(function()
		open = not open
		if open then
			tween(Chevron, { Rotation = 180 }, 0.15)
			resizeOpen()
		else
			close()
		end
	end)

	-- Met a jour la valeur affichee sans passer par un clic (utilise par le
	-- chargement de config) ; declenche quand meme onChange pour appliquer l'effet.
	local function set(newValue)
		selected = newValue
		MainButton.Text = text .. ": " .. tostring(selected)
		if onChange then onChange(selected) end
	end

	return { Get = function() return selected end, Set = set, Instance = Holder }
end

local function addSliderRow(content, text, min, max, default, step, onChange)
	step = step or 1
	local value = default or min

	local Holder = create("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1 }, content)
	create("TextLabel", {
		Size = UDim2.new(1, -70, 0, 22),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, Holder)

	local decimals = step < 1 and math.max(0, -math.floor(math.log10(step) + 0.0001)) or 0
	local function formatValue(v)
		if v <= 0 and min <= 0 then return "Illimite" end
		return string.format("%." .. decimals .. "f", v)
	end

	local ValueLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 80, 0, 22),
		BackgroundTransparency = 1,
		Text = formatValue(value),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, Holder)

	local Bar = create("Frame", {
		Position = UDim2.new(0, 0, 0, 36),
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = Theme.Element,
	}, Holder)
	corner(Bar, 4)

	local function pctFor(v) return (v - min) / (max - min) end

	local Fill = create("Frame", { Size = UDim2.new(pctFor(value), 0, 1, 0), BackgroundColor3 = Theme.Accent }, Bar)
	corner(Fill, 4)
	gradient(Fill, ColorSequence.new(Theme.Accent, Theme.AccentDim), 0)

	-- Curseur rond par-dessus la barre fine : plus lisible/tactile qu'un simple
	-- remplissage, et grossit legerement au survol/drag pour le feedback.
	local Knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(pctFor(value), 0, 0.5, 0),
		Size = UDim2.new(0, 16, 0, 16),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 2,
	}, Bar)
	corner(Knob, 8)
	create("UIStroke", { Color = Theme.Accent, Thickness = 2 }, Knob)

	local dragging = false

	local function apply(x)
		local p = math.clamp((x - Bar.AbsolutePosition.X) / Bar.AbsoluteSize.X, 0, 1)
		local raw = min + (max - min) * p
		value = math.clamp(math.floor(raw / step + 0.5) * step, min, max)
		local pct = pctFor(value)
		Fill.Size = UDim2.new(pct, 0, 1, 0)
		Knob.Position = UDim2.new(pct, 0, 0.5, 0)
		ValueLabel.Text = formatValue(value)
		if onChange then onChange(value) end
	end

	local function setKnobHover(hovering)
		tweenStyled(Knob, { Size = hovering and UDim2.new(0, 20, 0, 20) or UDim2.new(0, 16, 0, 16) }, 0.15)
	end
	Bar.MouseEnter:Connect(function() setKnobHover(true) end)
	Bar.MouseLeave:Connect(function() if not dragging then setKnobHover(false) end end)

	Bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setKnobHover(true)
			apply(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			setKnobHover(false)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			apply(input.Position.X)
		end
	end)

	-- Met a jour la valeur directement (utilise par le chargement de config),
	-- sans passer par une position en pixels ; declenche quand meme onChange.
	local function set(newValue)
		value = math.clamp(newValue, min, max)
		local pct = pctFor(value)
		Fill.Size = UDim2.new(pct, 0, 1, 0)
		Knob.Position = UDim2.new(pct, 0, 0.5, 0)
		ValueLabel.Text = formatValue(value)
		if onChange then onChange(value) end
	end

	return { Get = function() return value end, Set = set }
end

local function addLabelRow(content, text)
	return create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}, content)
end

-- Bouton de rebind : au clic, ecoute la prochaine touche clavier pressee et
-- l'assigne. Coupe le toggle du menu (capturingKeybind) pendant la capture
-- pour eviter qu'une touche pressee pour le rebind ne ferme/ouvre le menu en
-- meme temps. Echap annule sans changer.
local function addKeybindRow(content, text, currentKey, onChange)
	local capturing = false

	local Row = create("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1 }, content)
	create("TextLabel", {
		Size = UDim2.new(1, -122, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, Row)

	local KeyButton = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 112, 0, 32),
		BackgroundColor3 = Theme.Element,
		Text = currentKey.Name,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Theme.Accent,
		AutoButtonColor = false,
	}, Row)
	corner(KeyButton, 8)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.4 }, KeyButton)

	KeyButton.MouseEnter:Connect(function()
		if not capturing then tween(KeyButton, { BackgroundColor3 = Theme.Stroke }, 0.1) end
	end)
	KeyButton.MouseLeave:Connect(function()
		if not capturing then tween(KeyButton, { BackgroundColor3 = Theme.Element }, 0.1) end
	end)

	KeyButton.MouseButton1Click:Connect(function()
		if capturing then return end
		capturing = true
		capturingKeybind = true
		KeyButton.Text = "..."
		tween(KeyButton, { BackgroundColor3 = Theme.Accent, TextColor3 = Color3.new(1, 1, 1) }, 0.1)

		local connection
		connection = UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe then return end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

			connection:Disconnect()
			capturing = false
			capturingKeybind = false
			tween(KeyButton, { BackgroundColor3 = Theme.Element, TextColor3 = Theme.Accent }, 0.1)

			if input.KeyCode == Enum.KeyCode.Escape then
				KeyButton.Text = currentKey.Name
				return
			end

			currentKey = input.KeyCode
			KeyButton.Text = currentKey.Name
			if onChange then onChange(currentKey) end
		end)
	end)

	return { Get = function() return currentKey end }
end

local function addButtonRow(content, text, onClick)
	local Button = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = Theme.Element,
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
	}, content)
	corner(Button, 10)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.4 }, Button)
	local buttonScale = create("UIScale", { Scale = 1 }, Button) -- petit effet d'appui (scale), independant du pivot du bouton

	local hovering = false
	Button.MouseEnter:Connect(function()
		hovering = true
		tween(Button, { BackgroundColor3 = Theme.Stroke }, 0.1)
	end)
	Button.MouseLeave:Connect(function()
		hovering = false
		tween(Button, { BackgroundColor3 = Theme.Element }, 0.1)
	end)

	Button.MouseButton1Click:Connect(function()
		tween(Button, { BackgroundColor3 = Theme.Accent }, 0.1)
		tween(buttonScale, { Scale = 0.96 }, 0.08)
		task.delay(0.08, function()
			tween(buttonScale, { Scale = 1 }, 0.12)
		end)
		task.delay(0.1, function()
			tween(Button, { BackgroundColor3 = hovering and Theme.Stroke or Theme.Element }, 0.15)
		end)
		if onClick then onClick() end
	end)

	return Button
end

-- Selecteur (dropdown) + bouton "Teleporter" en dessous, dont les options
-- peuvent changer en cours de partie (rebuild complet du dropdown a chaque
-- refresh -- plus simple que d'etendre addDropdownRow pour un changement
-- d'options a chaud). `getOptions` renvoie la liste de noms courante,
-- `onTeleport(name)` est appele au clic sur le bouton.
--
-- Le dropdown est pose directement dans `section` (comme Chakra Point), PAS
-- dans un Frame intermediaire a AutomaticSize : une chaine AutomaticSize sur
-- 3 niveaux (Card > wrapper > dropdown tweene) propage mal le redimensionnement
-- pendant l'animation d'ouverture, ce qui laissait la card a une taille figee
-- (grande par defaut, ne grossissait pas a l'ouverture). LayoutOrder fixe
-- l'ordre visuel puisque le dropdown est detruit/recree a chaque refresh.
local function addTeleportSelector(section, label, buttonText, getOptions, onTeleport)
	local currentRow = nil
	local selected = nil

	local function rebuild()
		if currentRow then
			currentRow:Destroy()
			currentRow = nil
		end

		local options = getOptions()
		if #options == 0 then
			selected = nil
			currentRow = addLabelRow(section, "Aucune cible disponible pour l'instant.")
		else
			if not selected or not table.find(options, selected) then
				selected = options[1]
			end
			currentRow = addDropdownRow(section, label, options, selected, function(v)
				selected = v
			end).Instance
		end
		currentRow.LayoutOrder = 1
	end

	rebuild()

	local teleportButton = addButtonRow(section, buttonText, function()
		if not selected then
			notify("Aucune cible selectionnee.")
			return
		end
		onTeleport(selected)
	end)
	teleportButton.LayoutOrder = 2

	return { Refresh = rebuild }
end

--------------------------------------------------------------------------------
-- Categories
--------------------------------------------------------------------------------

local VisualsPage = createCategory("Visuels", Theme.Accent)
local PlayerPage = createCategory("Joueur", Color3.fromRGB(196, 120, 255))
local AutoPage = createCategory("Auto", Color3.fromRGB(255, 175, 70))
local SkinPage = createCategory("Skin", Color3.fromRGB(255, 120, 170))
local SettingsPage = createCategory("Settings", Theme.Success)

--------------------------------------------------------------------------------
------------------------------- VISUALS ----------------------------------------
--------------------------------------------------------------------------------

-- Tout ce bloc est dans un do...end et ecrit directement dans FEATURE_CONTROLS
-- (au lieu de ~18 variables locales separees) : Luau limite une fonction (et
-- le script entier EST une seule fonction) a 200 registres locaux, et on l'a
-- depasse. Les locals ici sont liberes a la fin du bloc ; seule
-- applyFeatureSettings (predeclaree juste en dessous) survit.
local applyFeatureSettings
do
	local FEATURE_CONTROLS = {}

	-- Reglages ESP : active/désactive, mode (Lua ou Python), distance max, affichage PV et distance.
	local EspSection = addSection(VisualsPage, "ESP")

	FEATURE_CONTROLS.EspEnabled = addToggleRow(EspSection, "ESP Actif", enabled, function(state)
		setEnabled(state)
		if not state then pushOverlayDisabled() end
		Settings.EspEnabled = state
	end)

	FEATURE_CONTROLS.EspMode = addDropdownRow(EspSection, "Mode ESP", { "Lua", "Python" }, EspMode, function(mode)
		local wasPython = enabled and EspMode == "Python"
		EspMode = mode
		setEnabled(enabled) -- reapplique la visibilite des billboards selon le nouveau mode
		if wasPython and mode ~= "Python" then pushOverlayDisabled() end
		Settings.EspMode = mode
	end)

	FEATURE_CONTROLS.EspMaxDistance = addSliderRow(EspSection, "Distance Max", 0, 10000, EspMaxDistance, 1, function(v)
		EspMaxDistance = v
		Settings.EspMaxDistance = v
	end)

	FEATURE_CONTROLS.ShowHealth = addToggleRow(EspSection, "Afficher PV", ShowHealth, function(state)
		ShowHealth = state
		refreshAllPlayerLabels()
		Settings.ShowHealth = state
	end)

	FEATURE_CONTROLS.ShowDistance = addToggleRow(EspSection, "Afficher Distance", ShowDistance, function(state)
		ShowDistance = state
		refreshAllPlayerLabels()
		Settings.ShowDistance = state
	end)

	FEATURE_CONTROLS.ShowChakra = addToggleRow(EspSection, "Afficher Chakra", ShowChakra, function(state)
		ShowChakra = state
		refreshAllPlayerLabels()
		Settings.ShowChakra = state
	end)

	FEATURE_CONTROLS.ShowBlood = addToggleRow(EspSection, "Afficher Blood", ShowBlood, function(state)
		ShowBlood = state
		refreshAllPlayerLabels()
		Settings.ShowBlood = state
	end)

	local EnvSection = addSection(VisualsPage, "Environnement")

	FEATURE_CONTROLS.NoFogEnabled = addToggleRow(EnvSection, "No Fog", NoFogEnabled, function(state)
		setNoFog(state)
		Settings.NoFogEnabled = state
	end)
	FEATURE_CONTROLS.NoRainEnabled = addToggleRow(EnvSection, "No Rain", NoRainEnabled, function(state)
		setNoRain(state)
		Settings.NoRainEnabled = state
	end)
	FEATURE_CONTROLS.FullBrightEnabled = addToggleRow(EnvSection, "Full Bright", FullBrightEnabled, function(state)
		setFullBright(state)
		Settings.FullBrightEnabled = state
	end)

	FEATURE_CONTROLS.BrightnessLevel = addSliderRow(EnvSection, "Brightness Level", 1, 10, BrightnessLevel, 0.1, function(v)
		BrightnessLevel = v
		Settings.BrightnessLevel = v
	end)

	FEATURE_CONTROLS.TimeOfDay = addDropdownRow(EnvSection, "Heure", { "Morning", "Afternoon", "Evening", "Night" }, TimeOfDay, function(v)
		TimeOfDay = v
		Settings.TimeOfDay = v
	end)

	FEATURE_CONTROLS.TimeChangerEnabled = addToggleRow(EnvSection, "Time Changer", TimeChangerEnabled, function(state)
		setTimeChanger(state)
		Settings.TimeChangerEnabled = state
	end)

	--------------------------------------------------------------------------------
	------------------------------- PLAYER -----------------------------------------
	--------------------------------------------------------------------------------

	local NotifSection = addSection(PlayerPage, "Notifications")

	FEATURE_CONTROLS.ChakraSenseNotifier = addToggleRow(NotifSection, "Chakra Sense Notifier", ChakraSenseNotifier, function(state)
		ChakraSenseNotifier = state
		Settings.ChakraSenseNotifier = state
	end)

	local MovementSection = addSection(PlayerPage, "Mouvement")

	FEATURE_CONTROLS.NoclipEnabled = addToggleRow(MovementSection, "Noclip", NoclipEnabled, function(state)
		setNoclip(state)
		Settings.NoclipEnabled = state
	end)

	FEATURE_CONTROLS.FlyEnabled = addToggleRow(MovementSection, "Fly", FlyEnabled, function(state)
		setFly(state)
		Settings.FlyEnabled = state
	end)

	FEATURE_CONTROLS.FlySpeed = addSliderRow(MovementSection, "Fly Speed", 10, 500, FlySpeed, 10, function(v)
		FlySpeed = v
		Settings.FlySpeed = v
	end)

	addLabelRow(MovementSection, "Fly : ZQSD/WASD pour se deplacer, Espace pour monter, Ctrl pour descendre.")

	local TeleportPlayerSection = addSection(PlayerPage, "Teleport Joueur")
	local playerTeleportSelector = addTeleportSelector(TeleportPlayerSection, "Joueur", "Teleporter au joueur",
		function()
			local names = {}
			for _, player in ipairs(Players:GetPlayers()) do
				if player ~= LocalPlayer then
					table.insert(names, player.Name)
				end
			end
			table.sort(names)
			return names
		end,
		function(name)
			local target = Players:FindFirstChild(name)
			if not target then
				notify("Joueur introuvable.")
				return
			end
			teleportToPlayer(target)
		end
	)
	track(Players.PlayerAdded:Connect(playerTeleportSelector.Refresh))
	track(Players.PlayerRemoving:Connect(function()
		task.wait() -- laisse le joueur sortir de Players:GetPlayers() avant de rafraichir
		playerTeleportSelector.Refresh()
	end))

	local TeleportNpcSection = addSection(PlayerPage, "Teleport PNJ")
	local npcTeleportSelector = addTeleportSelector(TeleportNpcSection, "PNJ", "Teleporter au PNJ",
		function()
			local names = {}
			for name in pairs(NpcsByName) do
				table.insert(names, name)
			end
			table.sort(names)
			return names
		end,
		teleportToNpc
	)
	onNpcListChanged = npcTeleportSelector.Refresh

	local SafeSpotSection = addSection(PlayerPage, "Safe Spot")
	addButtonRow(SafeSpotSection, "Definir Safe Spot", setSafeSpot)
	addButtonRow(SafeSpotSection, "Teleporter au Safe Spot", teleportToSafeSpot)

	local ChakraPointsSection = addSection(PlayerPage, "Chakra Points")
	if #ChakraPointNames > 0 then
		FEATURE_CONTROLS.SelectedChakraPoint = addDropdownRow(ChakraPointsSection, "Chakra Point", ChakraPointNames, SelectedChakraPoint, function(v)
			SelectedChakraPoint = v
			Settings.SelectedChakraPoint = v
		end)
		addButtonRow(ChakraPointsSection, "Teleporter", teleportToChakraPoint)
	else
		addLabelRow(ChakraPointsSection, "Aucun ChakraPoints trouve dans workspace.")
	end

	local InventorySection = addSection(PlayerPage, "Inventaire")
	addLabelRow(InventorySection, "Envoie Inventaire (Loadout) + Hotbar + Lifeforce au webhook Discord. Auto toutes les 5 min. Astuce : ouvre ton inventaire en jeu une fois pour que les slots se remplissent.")
	addButtonRow(InventorySection, "Envoyer au webhook Discord", sendInventoryToWebhook)

	local AfkAgeUpSection = addSection(AutoPage, "AFK AgeUp")
	addLabelRow(AfkAgeUpSection, "Teleporte automatiquement vers une Safe Place des qu'un joueur passe a moins de 300 metres (cooldown 1s entre deux teleportations).")
	FEATURE_CONTROLS.AfkAgeUpEnabled = addToggleRow(AfkAgeUpSection, "AFK AgeUp", Settings.AfkAgeUpEnabled, function(state)
		setAfkAgeUp(state)
		Settings.AfkAgeUpEnabled = state
	end)

	local PanicTeleportSection = addSection(AutoPage, "Panic Teleport")
	addLabelRow(PanicTeleportSection, "Des que tes PV passent sous 50, teleportation toutes les 0.1s entre les Safe Places. S'arrete quand tes PV repassent au-dessus de 100.")
	FEATURE_CONTROLS.PanicTeleportEnabled = addToggleRow(PanicTeleportSection, "Panic Teleport", Settings.PanicTeleportEnabled, function(state)
		setPanicTeleport(state)
		Settings.PanicTeleportEnabled = state
	end)

	-- Pousse une config chargee vers l'UI (declenche l'onChange normal de
	-- chaque controle, qui applique l'effet reel) sans dupliquer la logique.
	applyFeatureSettings = function(data)
		data = data or {}
		for key, control in pairs(FEATURE_CONTROLS) do
			if control then
				local value = data[key]
				if value == nil then value = DEFAULT_FEATURES[key] end
				if value ~= nil then control.Set(value) end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Configs : profils de reglages "cheat" nommes, sauvegardes dans
-- von_client/configs/*.json. Rien n'est charge par defaut sauf si une config
-- est marquee comme telle (etoile).
--------------------------------------------------------------------------------

local function addConfigRow(container, name, isDefault, onLoad, onSetDefault, onDelete)
	local Row = create("Frame", { Size = UDim2.new(1, 0, 0, 78), BackgroundColor3 = Theme.Element }, container)
	corner(Row, 8)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.4 }, Row)

	create("TextLabel", {
		Position = UDim2.new(0, 12, 0, 8),
		Size = UDim2.new(1, -24, 0, 20),
		BackgroundTransparency = 1,
		Text = isDefault and (name .. "  \226\152\133 par defaut") or name,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = isDefault and Theme.Accent or Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, Row)

	local ButtonsHolder = create("Frame", {
		Position = UDim2.new(0, 12, 0, 34),
		Size = UDim2.new(1, -24, 0, 32),
		BackgroundTransparency = 1,
	}, Row)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, ButtonsHolder)

	local function miniButton(text, color)
		local Btn = create("TextButton", {
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = color or Theme.Stroke,
			Text = text,
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextColor3 = Color3.new(1, 1, 1),
			AutoButtonColor = false,
		}, ButtonsHolder)
		corner(Btn, 6)
		create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, Btn)
		return Btn
	end

	miniButton("Charger", Theme.Accent).MouseButton1Click:Connect(onLoad)
	miniButton(isDefault and "Retirer defaut" or "Def. par defaut").MouseButton1Click:Connect(onSetDefault)
	miniButton("Supprimer", Theme.Danger).MouseButton1Click:Connect(onDelete)
end

do
	local ConfigSection = addSection(SettingsPage, "Configs")
	addLabelRow(ConfigSection, "Par defaut, rien n'est active. Enregistre tes reglages actuels sous un nom, puis marque une config par defaut pour qu'elle se recharge automatiquement au prochain chargement du script.")

	local ConfigNameBox = create("TextBox", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Element,
		Text = "",
		PlaceholderText = "Nom de la config...",
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		ClearTextOnFocus = false,
	}, ConfigSection)
	corner(ConfigNameBox, 8)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.4 }, ConfigNameBox)
	create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, ConfigNameBox)

	local ConfigListContainer = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, ConfigSection)
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, ConfigListContainer)

	local function refreshConfigList()
		ConfigListContainer:ClearAllChildren()
		create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, ConfigListContainer)

		local names = listConfigs()
		if #names == 0 then
			addLabelRow(ConfigListContainer, "Aucune config enregistree pour l'instant.")
			return
		end

		for _, name in ipairs(names) do
			addConfigRow(ConfigListContainer, name, Meta.defaultConfig == name,
				function()
					local data = loadConfigData(name)
					if not data then
						notify("Impossible de charger '" .. name .. "'.")
						return
					end
					applyFeatureSettings(data)
					notify("Config '" .. name .. "' chargee.")
				end,
				function()
					Meta.defaultConfig = (Meta.defaultConfig == name) and nil or name
					saveMeta()
					notify(Meta.defaultConfig == name and ("'" .. name .. "' est la config par defaut.") or "Plus de config par defaut.")
					refreshConfigList()
				end,
				function()
					deleteConfig(name)
					notify("Config '" .. name .. "' supprimee.")
					refreshConfigList()
				end
			)
		end
	end

	addButtonRow(ConfigSection, "Enregistrer la config actuelle", function()
		local name = sanitizeConfigName(ConfigNameBox.Text)
		if name == "" then
			notify("Donne un nom a ta config avant d'enregistrer.")
			return
		end
		saveConfig(name)
		notify("Config '" .. name .. "' enregistree.")
		refreshConfigList()
	end)

	refreshConfigList()
end

--------------------------------------------------------------------------------
-- Skin : Recherche (dump exploratoire, colle le resultat pour analyse) +
-- Skin d'arme (equipement reel). D'apres le dump de "Golden Zabunagi" :
-- l'arme portee est un simple MeshPart accroche au perso par un Motor6D
-- (Part0="Main"), avec juste un MeshId/TextureID/Size/Color/Material dessus -
-- pas de systeme d'accessoires/welds complexe comme suppose au debut (c'est
-- d'ailleurs pourquoi le premier essai base sur Humanoid:AddAccessory /
-- MeshPart clone+Weld n'avait rien donne). Reskin = recopier ces proprietes
-- directement sur le MeshPart deja en place, aucun clone/weld necessaire.
--------------------------------------------------------------------------------

do
	-- Workspace/PlayerGui en premier : c'est la que vivent les objets "live"
	-- qui nous interessent (armes portees, UI ouverte). ReplicatedStorage peut
	-- etre enorme (particules, sons, assets...) - le scanner en dernier.
	local SCAN_ROOTS = { workspace, PlayerGui, game:GetService("StarterGui"), game:GetService("ReplicatedFirst"), ReplicatedStorage }
	local SCAN_MAX_MATCHES = 10
	local SCAN_MAX_DEPTH = 10
	-- Budget SEPARE par conteneur (pas partage) : sinon un ReplicatedStorage
	-- enorme epuise tout le budget avant meme d'atteindre Workspace, qui ne
	-- serait alors jamais scanne (bug corrige : c'est ce qui s'est passe ici).
	local SCAN_MAX_VISITED_PER_ROOT = 600000

	-- Cherche (insensible a la casse) tout instance dont le nom contient
	-- `query`, dans les conteneurs listes ci-dessus. S'arrete a
	-- SCAN_MAX_MATCHES resultats et ne descend pas plus loin que
	-- SCAN_MAX_DEPTH pour rester lisible/rapide.
	local function findMatches(query)
		local lowerQuery = query:lower()
		local matches = {}
		local stats = {}

		for _, root in ipairs(SCAN_ROOTS) do
			local visited = 0
			local truncated = false

			local function walk(inst, depth)
				if #matches >= SCAN_MAX_MATCHES then return end
				if visited >= SCAN_MAX_VISITED_PER_ROOT then
					truncated = true
					return
				end
				visited = visited + 1
				if inst.Name:lower():find(lowerQuery, 1, true) then
					table.insert(matches, inst)
				end
				if depth >= SCAN_MAX_DEPTH then return end
				for _, child in ipairs(inst:GetChildren()) do
					if #matches >= SCAN_MAX_MATCHES then return end
					if visited >= SCAN_MAX_VISITED_PER_ROOT then
						truncated = true
						return
					end
					walk(child, depth + 1)
				end
			end

			walk(root, 0)
			table.insert(stats, string.format("%s: %d visite(s)%s", root.Name, visited, truncated and " (limite atteinte)" or ""))
			if #matches >= SCAN_MAX_MATCHES then break end
		end

		return matches, stats
	end

	local SkinSection = addSection(SkinPage, "Scanner (exploration)")
	addLabelRow(SkinSection, "Cherche un nom (ex: Valentine, Shop, Skin...) dans ReplicatedStorage / PlayerGui / StarterGui / ReplicatedFirst / Workspace, et copie un dump des resultats dans le presse-papier. Colle-le moi pour qu'on trouve la vraie structure des items.")

	local QueryBox = create("TextBox", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Element,
		Text = "Valentine",
		PlaceholderText = "Nom a chercher...",
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		ClearTextOnFocus = false,
	}, SkinSection)
	corner(QueryBox, 8)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.4 }, QueryBox)
	create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, QueryBox)

	local ScanResultLabel = addLabelRow(SkinSection, "Aucune recherche effectuee pour l'instant.")

	addButtonRow(SkinSection, "Chercher et copier le dump", function()
		local query = QueryBox.Text
		if query == "" then
			notify("Tape un nom a chercher.")
			return
		end

		local matches, stats = findMatches(query)
		if #matches == 0 then
			ScanResultLabel.Text = "Aucun resultat pour '" .. query .. "'. (" .. table.concat(stats, " | ") .. ")"
			notify("Aucun resultat. Voir le detail sous la recherche (nb d'instances visitees par conteneur).")
			return
		end

		local lines = {
			"=== Recherche '" .. query .. "' ===",
			os.date("%d/%m/%Y %H:%M:%S"),
			#matches .. " resultat(s)" .. (#matches >= SCAN_MAX_MATCHES and " (limite atteinte, affine la recherche pour voir le reste)" or ""),
			"Scan : " .. table.concat(stats, " | "),
			"",
		}
		for _, inst in ipairs(matches) do
			table.insert(lines, "--- " .. inst:GetFullName() .. "  [" .. inst.ClassName .. "] ---")
			table.insert(lines, dumpTree(inst, SCAN_MAX_DEPTH))
			table.insert(lines, "")
		end

		copyOrPrint(table.concat(lines, "\n"))
		ScanResultLabel.Text = #matches .. " resultat(s) pour '" .. query .. "', dump copie."
	end)

	-- Ne garde que les resultats utilisables comme source de skin : soit un
	-- MeshPart avec un mesh charge (armes recentes, ex. Golden Zabunagi),
	-- soit un Part classique avec un SpecialMesh enfant qui lui donne sa
	-- forme (ancienne methode, ex. Spider Gunbai - ClassName="Part", pas
	-- "MeshPart", donc invisible pour le premier filtre si on s'arrete la).
	local function findMeshMatches(query)
		local matches, stats = findMatches(query)
		local meshMatches = {}
		for _, inst in ipairs(matches) do
			if inst:IsA("MeshPart") and inst.MeshId ~= "" then
				table.insert(meshMatches, inst)
			elseif inst:IsA("BasePart") and inst:FindFirstChildWhichIsA("SpecialMesh") then
				table.insert(meshMatches, inst)
			end
		end
		return meshMatches, stats
	end

	-- Ton arme equipee = un MeshPart de ton perso qui a un Motor6D enfant
	-- (c'est le joint qui l'accroche a la part "Main"). Generique : marche
	-- pour n'importe quelle arme, pas seulement Golden Zabunagi.
	local function findMyWeaponParts()
		local character = LocalPlayer.Character
		local found = {}
		if not character then return found end
		for _, desc in ipairs(character:GetDescendants()) do
			if desc:IsA("MeshPart") and desc:FindFirstChildWhichIsA("Motor6D") then
				table.insert(found, desc)
			end
		end
		return found
	end

	local WeaponSkinSection = addSection(SkinPage, "Skin d'arme")
	addLabelRow(WeaponSkinSection, "Ton arme equipee est un simple MeshPart accroche a ton perso par un Motor6D. On recopie juste MeshId/TextureID/Taille/Couleur d'une autre arme trouvee (rack du shop, arme d'un autre joueur...) directement dessus : 100% visuel, rien n'est envoye au serveur. Un respawn ou un changement d'arme remet l'original (a reappliquer).")

	local myWeaponParts = {}
	local myWeaponLabels = {}
	local myWeaponSelector = nil
	local MyWeaponHolder = create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, WeaponSkinSection)
	create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, MyWeaponHolder)

	local function refreshMyWeapon()
		MyWeaponHolder:ClearAllChildren()
		create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, MyWeaponHolder)

		myWeaponParts = findMyWeaponParts()
		if #myWeaponParts == 0 then
			addLabelRow(MyWeaponHolder, "Aucune arme detectee sur ton perso (equipe-la en jeu, puis reessaie).")
			myWeaponSelector = nil
			return
		end

		myWeaponLabels = {}
		for _, part in ipairs(myWeaponParts) do
			table.insert(myWeaponLabels, part.Name)
		end
		myWeaponSelector = addDropdownRow(MyWeaponHolder, "Mon arme", myWeaponLabels, myWeaponLabels[1], nil)
	end

	addButtonRow(WeaponSkinSection, "Detecter mon arme", refreshMyWeapon)
	refreshMyWeapon()

	local skinScanResults = {}
	local skinResultLabels = {}
	local skinSelector = nil

	local SkinQueryBox = create("TextBox", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Element,
		Text = "",
		PlaceholderText = "Nom de l'arme/skin a copier (ex: Golden Zabunagi)...",
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		ClearTextOnFocus = false,
	}, WeaponSkinSection)
	corner(SkinQueryBox, 8)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.4 }, SkinQueryBox)
	create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, SkinQueryBox)

	local SkinSearchResultLabel = addLabelRow(WeaponSkinSection, "Aucune recherche effectuee.")

	local SkinResultHolder = create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, WeaponSkinSection)
	create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, SkinResultHolder)

	addButtonRow(WeaponSkinSection, "Chercher un skin source", function()
		local query = SkinQueryBox.Text
		if query == "" then
			notify("Tape un nom a chercher.")
			return
		end
		local matches, stats = findMeshMatches(query)
		skinScanResults = matches
		SkinSearchResultLabel.Text = #matches .. " MeshPart trouve(s) pour '" .. query .. "'. (" .. table.concat(stats, " | ") .. ")"

		SkinResultHolder:ClearAllChildren()
		create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, SkinResultHolder)

		if #matches == 0 then
			skinSelector = nil
			addLabelRow(SkinResultHolder, "Aucun MeshPart trouve avec ce nom.")
			return
		end

		skinResultLabels = {}
		for _, inst in ipairs(matches) do
			table.insert(skinResultLabels, inst:GetFullName())
		end
		skinSelector = addDropdownRow(SkinResultHolder, "Skin source", skinResultLabels, skinResultLabels[1], nil)
	end)

	addButtonRow(WeaponSkinSection, "Appliquer ce skin sur mon arme", function()
		if not myWeaponSelector or #myWeaponParts == 0 then
			notify("Detecte d'abord ton arme.")
			return
		end
		if not skinSelector or #skinScanResults == 0 then
			notify("Cherche d'abord un skin source.")
			return
		end

		local myIndex = table.find(myWeaponLabels, myWeaponSelector.Get())
		local myPart = myIndex and myWeaponParts[myIndex]
		local sourceIndex = table.find(skinResultLabels, skinSelector.Get())
		local sourcePart = sourceIndex and skinScanResults[sourceIndex]

		if not (myPart and myPart.Parent) then
			notify("Ton arme n'existe plus (respawn ?), redetecte-la.")
			return
		end
		if not (sourcePart and sourcePart.Parent) then
			notify("Le skin source n'existe plus, refais une recherche.")
			return
		end

		-- On NE TOUCHE PLUS a myPart (Motor6D/hitbox/collision intacts) : trop
		-- risque (a deja provoque un "tp sur l'arme" en cassant l'attache
		-- reelle). A la place : originale rendue invisible, et un clone du
		-- skin (juste le mesh, sans particules/attachments de la source)
		-- colle par-dessus via WeldConstraint, qui la suit partout puisque
		-- myPart continue d'etre anime normalement par son propre Motor6D.
		local OVERLAY_NAME = "VonClientWeaponSkin"
		local existingOverlay = myPart:FindFirstChild(OVERLAY_NAME)
		if existingOverlay then existingOverlay:Destroy() end

		local overlay = sourcePart:Clone()
		for _, child in ipairs(overlay:GetChildren()) do
			-- Garde SpecialMesh/Decal/Texture (donnent sa forme/son skin a un
			-- Part classique, ex. Spider Gunbai) ; vire le reste (Weld,
			-- Motor6D, Attachment, ParticleEmitter, Sound, Script...) qui
			-- referencait le contexte de la source et n'a plus de sens isole.
			if not (child:IsA("SpecialMesh") or child:IsA("Decal") or child:IsA("Texture")) then
				child:Destroy()
			end
		end
		overlay.Name = OVERLAY_NAME
		overlay.Anchored = false
		overlay.CanCollide = false
		pcall(function() overlay.Massless = true end)
		overlay.Transparency = 0
		overlay.CFrame = myPart.CFrame
		overlay.Parent = myPart

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = myPart
		weld.Part1 = overlay
		weld.Parent = overlay

		myPart.Transparency = 1

		notify("Skin colle par-dessus ton arme (originale juste rendue invisible, rien d'autre touche).")
	end)

	addButtonRow(WeaponSkinSection, "Retirer le skin colle", function()
		if not myWeaponSelector or #myWeaponParts == 0 then
			notify("Detecte d'abord ton arme.")
			return
		end
		local myIndex = table.find(myWeaponLabels, myWeaponSelector.Get())
		local myPart = myIndex and myWeaponParts[myIndex]
		if not (myPart and myPart.Parent) then
			notify("Ton arme n'existe plus (respawn ?), redetecte-la.")
			return
		end

		local overlay = myPart:FindFirstChild("VonClientWeaponSkin")
		if overlay then overlay:Destroy() end
		myPart.Transparency = 0
		notify("Skin retire, arme d'origine visible.")
	end)
end

do
	local DebugSection = addSection(SettingsPage, "Debug")
	addLabelRow(DebugSection, "Dump recursif de LocalPlayer + Character (pour reperer un systeme d'inventaire perso).")
	addButtonRow(DebugSection, "Dump LocalPlayer", dumpLocalPlayerToClipboard)
	addLabelRow(DebugSection, "Dump complet (sans limite de profondeur) du premier objet trouve dans l'inventaire - pour verifier ou se trouve la quantite.")
	addButtonRow(DebugSection, "Dump 1er item d'inventaire", dumpFirstInventoryItem)
end

-- StatusLabel doit survivre au-dela de ce bloc (mis a jour par la boucle de
-- statut plus bas), donc predeclare ici et assigne dans le do...end.
local StatusLabel
do
	local ConnSection = addSection(SettingsPage, "Connexion serveur Python")
	addLabelRow(ConnSection, "Endpoint : " .. OVERLAY_ENDPOINT)
	StatusLabel = addLabelRow(ConnSection, "Statut : en attente...")
end

--------------------------------------------------------------------------------
------------------------------- SETTINGS ----------------------------------------
--------------------------------------------------------------------------------

do
	local ShortcutSection = addSection(SettingsPage, "Raccourcis")
	addKeybindRow(ShortcutSection, "Touche menu", MENU_TOGGLE_KEY, function(newKey)
		MENU_TOGGLE_KEY = newKey
		Prefs.MenuKeybind = newKey.Name
		savePrefs()
	end)
end

do
	local WebhookSection = addSection(SettingsPage, "Webhook Discord")
	addLabelRow(WebhookSection, "Utilise pour l'envoi automatique de l'inventaire (page Joueur > Inventaire). Colle un lien de webhook Discord puis enregistre.")

	local WebhookUrlBox = create("TextBox", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Element,
		Text = Prefs.InventoryWebhookUrl or "",
		PlaceholderText = "https://discord.com/api/webhooks/...",
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		ClearTextOnFocus = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, WebhookSection)
	corner(WebhookUrlBox, 8)
	create("UIStroke", { Color = Theme.Stroke, Transparency = 0.4 }, WebhookUrlBox)
	create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, WebhookUrlBox)

	addButtonRow(WebhookSection, "Enregistrer le webhook", function()
		local url = WebhookUrlBox.Text
		if url == "" then
			notify("Le lien webhook ne peut pas etre vide.")
			return
		end
		Prefs.InventoryWebhookUrl = url
		savePrefs()
		notify("Webhook enregistre.")
	end)

	addButtonRow(WebhookSection, "Copier le webhook actuel", function()
		local url = Prefs.InventoryWebhookUrl or ""
		if url == "" then
			notify("Aucun webhook configure.")
			return
		end
		if setclipboard then
			local ok = pcall(setclipboard, url)
			notify(ok and "Webhook copie dans le presse-papier." or "Erreur : setclipboard a echoue.")
		else
			notify("setclipboard indisponible. Webhook affiche en console (F9).")
			print(url)
		end
	end)
end

-- Coupe tout proprement : previent le renderer Python (enabled=false), coupe
-- toutes les connexions longue-duree, detruit les billboards et le menu.
local function unload()
	if unloaded then return end
	unloaded = true

	if request then
		pcall(sendOverlayPacket, { enabled = false, players = {} })
	end

	for _, connection in ipairs(Connections) do
		connection:Disconnect()
	end

	for player in pairs(ChatOverlayByPlayer) do
		clearChatOverlay(player)
	end

	ScreenGui:Destroy()
end

local SessionSection = addSection(SettingsPage, "Session")
local UnloadButton = create("TextButton", {
	Size = UDim2.new(1, 0, 0, 50),
	BackgroundColor3 = Theme.Danger,
	Text = "Decharger le script",
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextColor3 = Color3.new(1, 1, 1),
	AutoButtonColor = false,
}, SessionSection)
corner(UnloadButton, 10)
local unloadScale = create("UIScale", { Scale = 1 }, UnloadButton)
UnloadButton.MouseEnter:Connect(function() tween(UnloadButton, { BackgroundColor3 = Color3.fromRGB(250, 110, 110) }, 0.1) end)
UnloadButton.MouseLeave:Connect(function() tween(UnloadButton, { BackgroundColor3 = Theme.Danger }, 0.1) end)
UnloadButton.MouseButton1Click:Connect(function()
	tween(unloadScale, { Scale = 0.96 }, 0.08)
	task.delay(0.08, function() tween(unloadScale, { Scale = 1 }, 0.12) end)
	unload()
end)

-- Alerte si un joueur a le cooldown "Chakra Sense" actif (structure
-- ReplicatedStorage.Cooldowns.<Joueur>.<NomCooldown> propre a ce jeu).
-- Verifie toutes les 15s, seulement quand ChakraSenseNotifier est coche.
task.spawn(function()
	while not unloaded do
		task.wait(15)
		if not (unloaded or not ChakraSenseNotifier) then
			local cooldownsFolder = ReplicatedStorage:FindFirstChild("Cooldowns")
			if cooldownsFolder then
				for _, playerFolder in ipairs(cooldownsFolder:GetChildren()) do
					if playerFolder:FindFirstChild("Chakra Sense") then
						notify(string.format("%s a Chakra Sense actif", playerFolder.Name))
					end
				end
			end
		end
	end
end)

-- Les toggles ne declenchent leur onChange qu'au clic : sans ca, un effet deja
-- actif au demarrage (config par defaut chargee avec NoFog/Fly/etc. a true)
-- s'afficherait allume dans le menu sans que l'effet reel ne soit applique.
setEnabled(enabled)
setNoFog(NoFogEnabled)
setNoRain(NoRainEnabled)
setFullBright(FullBrightEnabled)
setTimeChanger(TimeChangerEnabled)
setNoclip(NoclipEnabled)
setFly(FlyEnabled)

selectPage("Visuels")
playInjectionSplash()

-- Rafraichit le statut de connexion une fois par seconde (pas besoin de plus).
task.spawn(function()
	while not unloaded do
		if lastConnOk == nil then
			StatusLabel.Text = "Statut : en attente..."
			StatusLabel.TextColor3 = Theme.SubText
		elseif lastConnOk then
			StatusLabel.Text = "Statut : connecte"
			StatusLabel.TextColor3 = Theme.Success
		else
			StatusLabel.Text = "Statut : deconnecte (lance light_chat_overlay.py ?)"
			StatusLabel.TextColor3 = Theme.Danger
		end
		task.wait(1)
	end
end)

track(UserInputService.InputBegan:Connect(function(input, gpe)
	if unloaded then return end
	if gpe then return end
	if capturingKeybind then return end
	if input.KeyCode == MENU_TOGGLE_KEY then
		toggleWindow()
	end
end))
print("HALF2 END")
