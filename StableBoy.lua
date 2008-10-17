local TL,TC,TR = "TOPLEFT", "TOP", "TOPRIGHT"
local ML,MC,MR = "LEFT", "CENTER", "RIGHT"
local BL,BC,BR = "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"

local MOUNT_GROUND = 1
local MOUNT_FLYING = 2

local SPEED_ADAPTS = 0 -- This mount adaps to the fastest speed known for its type.
local SPEED_SLOW = 1 -- 60% (Ground/Flying)
local SPEED_MEDIUM = 2 -- 100% (Ground) / 280% (Flying)
local SPEED_FAST = 3 -- 310% (Flying)

local MAX_CHECKBOXES_SHOWN = 15
local CHECKBOX_VERTICAL_SIZE = 20

local L = STABLEBOY_LOCALE

local function announce(msg)
	DEFAULT_CHAT_FRAME:AddMessage(L.Prefix..msg)
end

-- This table is for special-casing certain mounts that won't parse properly
-- in the ParseMounts() method.
local mountBypass = {
	[54729] = { mountType=MOUNT_FLYING, speed=SPEED_ADAPTS } -- Winged Steed of the Ebon Blade
	[58983] = { mountType=MOUNT_GROUND, speed=SPEED_ADAPTS } -- Big Blizzard Bear (BlizzCon 2008)
}

StableBoy = CreateFrame("frame", "StableBoyFrame", UIParent)
StableBoy:SetScript("OnEvent", function(self, event, ...) return self[event](self, ...) end)
StableBoy:RegisterEvent("ADDON_LOADED")

-- This should be a -COMPLETE- list of our BEST Flying & Ground Mounts.
-- This is what the options frame will use to generate its list of mounts for filtering.
-- NOTE: The Key->Value pairs for these lists should be in the following format:
--[[
[spellID] = {
	cID = 1, -- The index of the mount in your character tab, that you would pass to CallCompanion()
	name = "Armored Brown Bear",
	enabled = true,
}
]]--
StableBoy.mounts = {
	[MOUNT_GROUND] = {},
	[MOUNT_FLYING] = {},
}

-- This is a list of the FILTERED Flying & Ground mounts.
-- This is what gets passed to SummonMount(), to determine which random mount to summon.
-- NOTE: These tables MUST have consecutive integer indices.
-- This is necessary for random() to work.
StableBoy.mountsFiltered = {
	[MOUNT_GROUND] = {},
	[MOUNT_FLYING] = {},
}

StableBoy.mountOrder = {
	[MOUNT_GROUND] = {},
	[MOUNT_FLYING] = {},
}

--[[
self.chardb = 
[spellID] = true -- This indicates the user DOES want to include this in the filtered list
[spellID] = nil -- This indicates the user DOES NOT want to include this in the filtered list
]]--

-- Create a scanning tooltip
CreateFrame("GameTooltip","StableBoyTooltip",UIParent,"GameTooltipTemplate")
StableBoyTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local menu = {
	[MOUNT_FLYING] = {
		text = L.FlyingMounts,
		value = { ["Level1_Key"] = MOUNT_FLYING },
		notCheckable = true,
		hasArrow = true,
		submenu = {}
	},
	[MOUNT_GROUND] = {
		text = L.GroundMounts,
		value = { ["Level1_Key"] = MOUNT_GROUND },
		notCheckable = true,
		hasArrow = true,
		submenu = {}
	}
}

-- I could probably separate the various parts of this method into sub-methods
function StableBoy:ADDON_LOADED(addon,...)
	if( addon == 'StableBoy' ) then
		-- db/SV Setup
		self.chardb = StableBoyPCDB
		
		-- Register Events
		self:RegisterEvent('PLAYER_LOGIN')
		self:RegisterEvent('COMPANION_LEARNED')
		
		-- Set Scripts
		self.frame = CreateFrame("Button", "StableBoyClickFrame", UIParent)
		self.frame:Hide()
		self.frame:SetScript("OnClick", function(...) StableBoy:ClickHandler(IsShiftKeyDown()) end)
		
		-- Setup LDB plugin
		self.ldb = LibStub:GetLibrary("LibDataBroker-1.1"):NewDataObject("StableBoyLDB", {label=L.Title,text=""})
		self.ldb.icon = "Interface\\Icons\\Spell_Holy_CrusaderAura"
		self.ldb.OnClick = function(...) StableBoy:LDB_OnClick(...) end
		
		-- Setup Menu
		self.menu = CreateFrame("Frame", "StableBoyDropDownMenu", UIParent, "UIDropDownMenuTemplate")
--		StableBoyDropDownMenu:SetPoint("CENTER", UIParent)
		UIDropDownMenu_Initialize(self.menu, StableBoy_InitializeMenu, "MENU")

		-- Interface Options
		NHTS_OptionsGeneration:ImportOptionsGeneration(self)
		self.options = self:OptionsFrameCreate()
		InterfaceOptions_AddCategory(self.options)
		InterfaceOptions_AddCategory(self.options.panels[MOUNT_GROUND])
		InterfaceOptions_AddCategory(self.options.panels[MOUNT_FLYING])

		-- Slash Commands		
		SlashCmdList["StableBoyCOMMAND"] = function(cmd)
			if( cmd == "ground" ) then
				InterfaceOptionsFrame_OpenToCategory(L.GroundMounts)
			elseif( cmd == "flying" ) then
				InterfaceOptionsFrame_OpenToCategory(L.FlyingMounts)
			else
				InterfaceOptionsFrame_OpenToCategory(L.Title)
			end
		end
		SLASH_StableBoyCOMMAND1 = "/stableboy"
	end
end

function StableBoy:PLAYER_LOGIN(...)
	self:ParseMounts(true)
	self:Options_Update()
--	StableBoy_ScrollBar_Update(MOUNT_GROUND)
--	StableBoy_ScrollBar_Update(MOUNT_FLYING)
end

function StableBoy:COMPANION_LEARNED(...)
	self:ParseMounts(false)
	self:Options_Update()
--	StableBoy_ScrollBar_Update(MOUNT_GROUND)
--	StableBoy_ScrollBar_Update(MOUNT_FLYING)
end

function StableBoy:ParseMounts(login)
	GameTooltip_SetDefaultAnchor(StableBoyTooltip, UIParent)
	
	local mounts = {
		[MOUNT_FLYING] = {},
		[MOUNT_GROUND] = {}
	}
	local mountsFiltered = {
		[MOUNT_FLYING] = {},
		[MOUNT_GROUND] = {}
	}
	local mountOrder = {
		[MOUNT_GROUND] = {},
		[MOUNT_FLYING] = {},
	}
	local submenus = {
		[MOUNT_FLYING] = {},
		[MOUNT_GROUND] = {}
	}
	local maxSpeeds = {
		[MOUNT_FLYING] = SPEED_SLOW, 
		[MOUNT_GROUND] = SPEED_SLOW
	}
	chardb = {}
	
	local maxMounts = GetNumCompanions('MOUNT')
	for i=1,maxMounts do
		local creatureID,name,spellID = GetCompanionInfo('MOUNT',i)
		local thisType = MOUNT_GROUND
		local thisSpeed = SPEED_SLOW
		
		if( mountBypass[spellID] ) then
			if( mountBypass[spellID].speed == SPEED_ADAPTS ) then
				mountBypass[spellID].addLater = true
				mountBypass[spellID].cID = i
				mountBypass[spellID].name = name
			else
				thisType = mountBypass[spellID].mountType
				thisSpeed = mountBypass[spellID].speed
			end
		else
			StableBoyTooltip:SetHyperlink("spell:"..spellID)
			local numLines = StableBoyTooltip:NumLines()
			local text = ""
			for j=1,numLines do
				text = string.format("%s %s", text, _G["StableBoyTooltipTextLeft"..j]:GetText())
			end

			-- Determine if we're a flying mount.
			-- Flying mounts can only be used in Outland or Northrend,
			-- And say so on the tooltip.
			if text:match(L.Outland) or text:match(L.Northrend) then
				thisType = MOUNT_FLYING
			end

			-- Figure out how fast this mount is.
			if text:match(L.SpeedFast) then
				-- 310% Flying Mount
				thisSpeed = SPEED_FAST
			elseif text:match(L.SpeedMedium) then
				-- 100% Ground Mount or 280% Flying Mount
				thisSpeed = SPEED_MEDIUM
			end
		end

		-- Add Mount to LDB Menu
		submenus[thisType][i] = {text=name,value=i}
		
		-- If this mount is faster than anything seen yet, 
		-- wipe out the mount list, and set our max speed to this mount's speed
		if( thisSpeed > maxSpeeds[thisType] ) then
			mounts[thisType] = {}
			mountsFiltered[thisType] = {}
			maxSpeeds[thisType] = thisSpeed
		end

		-- Add this mount to our list, only if it's at least as fast
		-- as the fastest mount seen. (which may be this very mount)
		if( thisSpeed >= maxSpeeds[thisType] ) then
			-- Add the mount to the list.
			mounts[thisType][spellID] = {cID=i,name=name}
			
			-- Add the mount if:
			-- self.chardb is nil (no saved vars, new install)
			-- it's in self.chardb
			-- we're NOT logging in and it's NOT in self.mounts
			if( (not self.chardb or self.chardb[spellID]) or (not login and not self.mounts[thisType][spellID]) ) then
				chardb[spellID] = 1
				mountsFiltered[thisType][#mountsFiltered[thisType]+1] = mounts[thisType][spellID]
				mounts[thisType][spellID].enabled = 1
			end
		end
	end -- for i=1,maxMounts
	StableBoyTooltip:Hide()
	
	-- Check the mountBypass table, for any mounts flagged as "add later".
	-- Typically this indicates mounts that adapt to the user's best riding skill
	-- So we should always add them.
	for spellID,info in pairs(mountBypass) do
		if( info.addLater ) then
			mounts[info.mountType][spellID] = {cID=info.cID,name=info.name}
			
			if( (not self.chardb or self.chardb[spellID]) or (not login and not self.mounts[info.mountType][spellID]) ) then
				chardb[spellID] = 1
				mountsFiltered[info.mountType][#mountsFiltered[info.mountType]+1] = mounts[info.mountType][spellID]
				mounts[info.mountType][spellID].enabled = 1
			end
		end
	end
	
	-- Generate an order for the mounts we have.
	-- This is necessary to handle updating the checkboxes in the FauxScrollFrame properly
	for mountType,list in pairs(mounts) do
		local i = 1
		for sID,info in pairs(list) do
			mountOrder[mountType][i] = sID
			i = i + 1
		end
	end	
	
	-- Persist our generated data back to the mod
	-- I have to wonder if this would not be better as multiple return values
	self.mounts = mounts
	self.mountsFiltered = mountsFiltered
	self.mountOrder = mountOrder
	StableBoyPCDB = chardb
	self.chardb = chardb
	menu[MOUNT_GROUND].submenu = submenus[MOUNT_GROUND]
	menu[MOUNT_FLYING].submenu = submenus[MOUNT_FLYING]
end

function StableBoy:RebuildFilteredMounts()
	local mountsFiltered = {
		[MOUNT_GROUND] = {},
		[MOUNT_FLYING] = {}
	}
	
	for mountType, list in pairs(self.mounts) do
		for spellID, info in pairs(list) do
			if( self.chardb[spellID]) then
				mountsFiltered[mountType][#mountsFiltered[mountType]+1] = info
			end
		end
	end
	
	self.mountsFiltered = mountsFiltered
end

function StableBoy:ClickHandler(forceGround)
	if( UnitInVehicle("player") ) then
		VehicleExit()
	elseif( IsMounted() ) then
		Dismount()
	elseif( not InCombatLockdown() and IsOutdoors() ) then
		-- Only attempt to summon a flying mount if we HAVE flying mounts AND we're in a flyable zone
		-- AND my hacky attempt to get around the fact that [flyable] doesn't work right in northrend
		if( #self.mountsFiltered[MOUNT_FLYING] > 0 and not forceGround and self:IsFlyableArea() ) then
			self:SummonMount(self.mountsFiltered[MOUNT_FLYING])
		elseif( #self.mountsFiltered[MOUNT_GROUND] > 0 ) then
			self:SummonMount(self.mountsFiltered[MOUNT_GROUND])
		end
	end
end

function StableBoy:SummonMount(mountList)
	CallCompanion("MOUNT",mountList[random(#mountList)].cID)
end

-- A more robust replacement for the IsFlyableArea() method.
-- This does some advanced checking, to handle the oddities of flying in
-- northrend. It checks for Cold Weather Flying, whether your in Dalaran,
-- and if you're in Krasus' Landing.
function StableBoy:IsFlyableArea()
	SetMapToCurrentZone()
	local zone = GetRealZoneText()
	local subzone = GetSubZoneText()

	-- Are we in a 'Flyable' area?
	if( not IsFlyableArea() ) then return false end;
	
	-- We ARE in a 'Flyable' area, are we in Northrend?
	if( GetCurrentMapContinent() ~= 4 ) then return true end;

	-- We ARE in Northrend, do we have Cold Weather Flying (spell ID 54197)?
	if( not GetSpellInfo(GetSpellInfo(54197)) ) then return false end;
	
	-- We HAVE Cold Weather Flying, are we in Lake Wintergrasp?
	if( zone == L.Wintergrasp ) then return false end;

	-- We ARE NOT in Lake Wintergrasp, are we in Dalaran?
	if( not (zone == L.Dalaran) ) then return true end;
	
	-- We ARE in Dalaran, are we in Krasus' Landing?	
	if( not (subzone == L.KrasusLanding) ) then return false end;
	
	-- We ARE in Krasus' Landing, we can fly.
	return true;
end

function StableBoy:LDB_OnClick(frame,button,down)
	if( button == "LeftButton" ) then
		local forceGround = false
		if( IsShiftKeyDown() ) then forceGround = true; end
		StableBoy:ClickHandler(forceGround)
	elseif( button == "RightButton" ) then
		ToggleDropDownMenu(1, nil, StableBoyDropDownMenu, frame, 0, 0);
	end
end

function StableBoy:Menu_OnClick()
	CallCompanion("MOUNT",this.value)
end

function StableBoy_InitializeMenu(frame,level)
	level = level or 1
	
	if level == 1 then
		for k,v in pairs(menu) do
			if( select(2,next(v.submenu)) ) then
				v.owner = frame:GetParent()
				v.func = function() StableBoy:Menu_OnClick() end;
				UIDropDownMenu_AddButton(v,level)
			end
		end
	end
	
	if level == 2 then
		local l1_key = UIDROPDOWNMENU_MENU_VALUE["Level1_Key"];
		local submenu = menu[l1_key].submenu
		for k,v in pairs(submenu) do
			v.owner = frame:GetParent()
			v.func = function() StableBoy:Menu_OnClick() end;
			UIDropDownMenu_AddButton(v,level)
		end
	end
end

function StableBoy:OptionsFrameCreate()
	local options,title,subtitle,panel

	-- Setup the base panel
	options = CreateFrame('Frame', 'StableBoyOptionsFrame', UIParent)
	options.panels = {}
	options.name = L.Title
	options.okay = function(self,...) StableBoy:Options_Okay(self,...); end
	options.cancel = function(self,...) StableBoy:Options_Cancel(self,...); end
	options.default = function(self,...) StableBoy:Options_Defaults(self,...); end
	options.refresh = function(self,...) StableBoy:Options_Update(); end
	
	title = options:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint(TL, 16, -16)
	title:SetText(L.Title)
	options.title = title
	
	-- Setup the ground mount panel
	panel = CreateFrame('Frame', 'StableBoyOptionsGroundFrame', UIParent)
	panel.mountType = MOUNT_GROUND
	panel.name = L.GroundMounts
	panel.parent = L.Title
	panel.default = function(self,...) StableBoy:Options_Defaults(self,...); end
	panel.refresh = function(self,...) StableBoy:Options_Update(self.mountType); end
	
	title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint(TL, 16, -16)
	title:SetText(L.GroundMounts)
	panel.title = title
	
	subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	subtitle:SetHeight(32)
	subtitle:SetPoint(TL, title, BL, 0, -8)
	subtitle:SetPoint(MR, panel, -32, 0)
	subtitle:SetNonSpaceWrap(true)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetJustifyV("TOP")
	subtitle:SetText(L.OptionsDescription)
	panel.subtitle = subtitle

	panel.apply = self:CreateButton(panel, L.Apply, 96, 22)
	panel.apply:SetPoint(BR, -16, 16)
	panel.apply:SetScript('OnClick', function(self,...) StableBoy:Options_Okay(self,...) end)
	
	panel.scrollFrame = CreateFrame('ScrollFrame', 'StableBoyOptionsGroundScrollFrame', panel, 'FauxScrollFrameTemplate')
	panel.scrollFrame:SetPoint(TL, 0, -60)
	panel.scrollFrame:SetPoint(TR, -30, -60)
	panel.scrollFrame:SetHeight(MAX_CHECKBOXES_SHOWN * CHECKBOX_VERTICAL_SIZE)
	panel.scrollFrame:SetScript('OnVerticalScroll', function(self, offset) return FauxScrollFrame_OnVerticalScroll(self, offset, 20, function() return StableBoy:Options_Update(MOUNT_GROUND) end) end)
	
	panel.checkboxes = {}
	for i=1,MAX_CHECKBOXES_SHOWN do
		local verticalOffset = (-60 + (-CHECKBOX_VERTICAL_SIZE * (i-1)))
		local checkbox = self:CreateCheckButton(panel, "StableBoyGroundCheckBox"..i)
		checkbox:SetPoint(TL, 10, verticalOffset)
		checkbox:SetScript('OnClick', function(self,...) StableBoy:CheckBox_OnClick(self, MOUNT_GROUND, ...) end)
		panel.checkboxes[i] = checkbox
	end
	options.panels[MOUNT_GROUND] = panel
	
	-- Setup the flying mount panel
	panel = CreateFrame('Frame', 'StableBoyOptionsFlyingFrame', UIParent)
	panel.mountType = MOUNT_FLYING
	panel.name = L.FlyingMounts
	panel.parent = L.Title
	panel.default = function(self,...) StableBoy:Options_Defaults(self,...); end
	panel.refresh = function(self,...) StableBoy:Options_Update(self.mountType); end

	title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint(TL, 16, -16)
	title:SetText(L.FlyingMounts)
	panel.title = title

	subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	subtitle:SetHeight(32)
	subtitle:SetPoint(TL, title, BL, 0, -8)
	subtitle:SetPoint(MR, panel, -32, 0)
	subtitle:SetNonSpaceWrap(true)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetJustifyV("TOP")
	subtitle:SetText(L.OptionsDescription)
	panel.subtitle = subtitle

	panel.apply = self:CreateButton(panel, L.Apply, 96, 22)
	panel.apply:SetPoint(BR, -16, 16)
	panel.apply:SetScript('OnClick', function(self,...) StableBoy:Options_Okay(self,...) end)
	
	panel.scrollFrame = CreateFrame('ScrollFrame', 'StableBoyOptionsFlyingScrollFrame', panel, 'FauxScrollFrameTemplate')
	panel.scrollFrame:SetPoint(TL, 0, -60)
	panel.scrollFrame:SetPoint(TR, -30, -60)
	panel.scrollFrame:SetHeight(MAX_CHECKBOXES_SHOWN * CHECKBOX_VERTICAL_SIZE)
	panel.scrollFrame:SetScript('OnVerticalScroll', function(self, offset) return FauxScrollFrame_OnVerticalScroll(self, offset, 20, function() return StableBoy:Options_Update(MOUNT_FLYING) end) end)
	
	panel.checkboxes = {}
	for i=1,MAX_CHECKBOXES_SHOWN do
		local verticalOffset = (-60 + (-CHECKBOX_VERTICAL_SIZE * (i-1)))
		local checkbox = self:CreateCheckButton(panel, "StableBoyFlyingCheckBox"..i)
		checkbox:SetPoint(TL, 10, verticalOffset)
		checkbox:SetScript('OnClick', function(self,...) StableBoy:CheckBox_OnClick(self, MOUNT_FLYING, ...) end)
		panel.checkboxes[i] = checkbox
	end
	options.panels[MOUNT_FLYING] = panel
	
	return options
end

function StableBoy:CheckBox_OnClick(button, mountType, ...)
	self.mounts[mountType][button.spellID].enabled = button:GetChecked()
end

--[[
The user hit "Okay" so we want to take their selections, and apply it to our
saved vars, and rebuild our filtered mounts list.
The user's selections should be represented by the "enabled" variable in the 
mounts[mountType] table.
]]--
function StableBoy:Options_Okay(panel)
	for mountType,list in pairs(self.mounts) do
		for spellID,info in pairs(list) do
			self.chardb[spellID] = info.enabled
		end
	end
	self:RebuildFilteredMounts()
end

--[[
The user hit "Cancel", so we need to reset their selections. We update the
"enabled" varaible in the mounts[mountType] table to reflect the setting in the
saved vars.

NOTE: We should NOT have to rebuild our filtered mounts list here, because
nothing should have changed.
]]--
function StableBoy:Options_Cancel(panel,...)
	for mountType,list in pairs(self.mounts) do
		for spellID,info in pairs(list) do
			info.enabled = self.chardb[spellID]
		end
	end
end

--[[
The user hit "Defaults", so we return to our default state, which is every mount
enabled.
]]--
function StableBoy:Options_Defaults(panel,...)
	for spellID,info in pairs(self.mounts[panel.mountType]) do
		info.enabled = 1
		self.chardb[spellID] = 1
	end
	self:RebuildFilteredMounts()
end

function StableBoy:Options_Update(mountType,...)
	-- If we weren't passed in a mount type, just call ourself twice,
	-- passing in mount types explicitly
	if( not mountType ) then
		self:Options_Update(MOUNT_GROUND,...)
		self:Options_Update(MOUNT_FLYING,...)
	else
		local scrollFrame = self.options.panels[mountType].scrollFrame
		local mounts = self.mounts[mountType]
		local mountOrder = self.mountOrder[mountType]
		FauxScrollFrame_Update( scrollFrame, #mountOrder, MAX_CHECKBOXES_SHOWN, CHECKBOX_VERTICAL_SIZE )
		
		for line=1,MAX_CHECKBOXES_SHOWN do
			local linePlusOffset = line + FauxScrollFrame_GetOffset( scrollFrame )
			
			local button = self.options.panels[mountType].checkboxes[line]
			
			if( linePlusOffset <= #mountOrder ) then
				getglobal(button:GetName()..'Text'):SetText(mounts[mountOrder[linePlusOffset]].name)
				button:SetChecked(mounts[mountOrder[linePlusOffset]].enabled)
				button.spellID = mountOrder[linePlusOffset]
				button:Show()
			else
				button:Hide()
			end
		end
	end
end
