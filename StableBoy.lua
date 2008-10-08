local MOUNT_GROUND = 1
local MOUNT_FLYING = 2
local SPEED_SLOW = 1 -- 60% (Ground/Flying)
local SPEED_MEDIUM = 2 -- 100% (Ground) / 280% (Flying)
local SPEED_FAST = 3 -- 310% (Flying)
BINDING_HEADER_STABLEBOY = 'StableBoy'
BINDING_NAME_STABLEBOY_MOUNT_BEST = 'Summon Best Mount'
BINDING_NAME_STABLEBOY_MOUNT_GROUND = 'Summon Ground Mount'

local function announce(msg)
	DEFAULT_CHAT_FRAME:AddMessage("StableBoy: "..msg)
end

-- This table is for special-casing certain mounts that won't parse properly
-- in the ParseMounts() method.
local mountBypass = {
	[54729] = { mountType=MOUNT_GROUND, speed=SPEED_MEDIUM } -- Winged Steed of the Ebon Blade
}


StableBoy = CreateFrame("frame", "StableBoyFrame", UIParent)
StableBoy:SetScript("OnEvent", function(self, event, ...) return self[event](self, ...) end)
StableBoy:RegisterEvent("ADDON_LOADED")
StableBoy.myGroundMounts = {}
StableBoy.myFlyingMounts = {}

-- Create a scanning tooltip
CreateFrame("GameTooltip","StableBoyTooltip",UIParent,"GameTooltipTemplate")
StableBoyTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local menu = {
	["Flying"] = {
		text = "Flying Mounts",
		value = { ["Level1_Key"] = "Flying" },
		notCheckable = true,
		hasArrow = true,
		submenu = {}
	},
	["Ground"] = {
		text = "Ground Mounts",
		value = { ["Level1_Key"] = "Ground" },
		notCheckable = true,
		hasArrow = true,
		submenu = {}
	}
}

-- I could probably separate the various parts of this method into sub-methods
function StableBoy:ADDON_LOADED(addon,...)
	if( addon == 'StableBoy' ) then
		-- Register Events
		self:RegisterEvent('PLAYER_LOGIN')
		self:RegisterEvent('COMPANION_LEARNED')
		
		-- Set Scripts
		self.frame = CreateFrame("Button", "StableBoyClickFrame", UIParent)
		self.frame:Hide()
		self.frame:SetScript("OnClick", function(...) StableBoy:ClickHandler() end)
		
		-- Setup LDB plugin
		self.ldb = LibStub:GetLibrary("LibDataBroker-1.1"):NewDataObject("StableBoyLDB", {label="StableBoy",text=""})
		self.ldb.icon = "Interface\\Icons\\Spell_Holy_CrusaderAura"
		self.ldb.OnClick = function(...) StableBoy:LDB_OnClick(...) end
		
		-- Setup Menu
		self.menu = CreateFrame("Frame", "StableBoyDropDownMenu", UIParent, "UIDropDownMenuTemplate")
--		StableBoyDropDownMenu:SetPoint("CENTER", UIParent)
		UIDropDownMenu_Initialize(self.menu, StableBoy_InitializeMenu, "MENU")
	end
end

function StableBoy:PLAYER_LOGIN(...)
	self:ParseMounts()
	--self:InitializeMounts()
end

function StableBoy:COMPANION_LEARNED(...)
	self:ParseMounts()
	--self:InitializeMounts()
end

function StableBoy:ParseMounts()
	self.myFlyingMounts = {}
	self.myGroundMounts = {}
	GameTooltip_SetDefaultAnchor(StableBoyTooltip, UIParent)

	local myMounts = {}
	local maxMounts = GetNumCompanions('MOUNT')
	local maxGroundSpeed = SPEED_SLOW
	local maxFlyingSpeed = SPEED_SLOW
	for i=1,maxMounts do
		local thisMount
		local creatureID,name,spellID = GetCompanionInfo('MOUNT',i)
		if( mountBypass[spellID] ) then
			thisMount = mountBypass[spellID]
		else
			thisMount = { mountType=MOUNT_GROUND, speed=SPEED_SLOW}
			StableBoyTooltip:SetHyperlink("spell:"..spellID)
			local numLines = StableBoyTooltip:NumLines()
			local text = ""
			for j=1,numLines do
				text = string.format("%s %s", text, _G["StableBoyTooltipTextLeft"..j]:GetText())
			end
	
			-- Determine if we're a flying mount.
			-- Flying mounts can only be used in Outland or Northrend,
			-- And say so on the tooltip.
			if text:match("Outland") or text:match("Northrend") then
				thisMount.mountType = MOUNT_FLYING
			end
	
			-- Figure out how fast this mount is.
			if text:match("extremely%s+fast") then
				-- "extremely fast" means it's a 310% Flying mount.
				thisMount.speed = SPEED_FAST
			elseif text:match("very%s+fast") then
				-- "very fast" means it's a 100% speed ground mount, or a 280% speed flying mount.
				thisMount.speed = SPEED_MEDIUM
			end
			
			-- Update our max speed values if this is the fastest mount we've seen yet
			if( thisMount.mountType == MOUNT_GROUND and thisMount.speed > maxGroundSpeed ) then
				maxGroundSpeed = thisMount.speed
			elseif( thisMount.mountType == MOUNT_FLYING and thisMount.speed > maxFlyingSpeed ) then
				maxFlyingSpeed = thisMount.speed
			end
			
			-- Add this mount to our menu
			if( thisMount.mountType == MOUNT_FLYING ) then
				menu["Flying"].submenu[i] = { text=name, value=i }
			elseif( thisMount.mountType == MOUNT_GROUND ) then
				menu["Ground"].submenu[i] = { text=name, value=i }
			end
		end
		
		myMounts[i] = thisMount
	end -- i=1,maxMounts
	StableBoyTooltip:Hide()
		
	for i,thisMount in pairs(myMounts) do
		if( thisMount.mountType == MOUNT_GROUND and thisMount.speed >= maxGroundSpeed ) then
			self.myGroundMounts[#self.myGroundMounts+1] = i
		elseif( thisMount.mountType == MOUNT_FLYING and thisMount.speed >= maxFlyingSpeed ) then
			self.myFlyingMounts[#self.myFlyingMounts+1] = i
		end
	end -- i,thisMount in myMounts
end

function StableBoy:ClickHandler(forceGround)
	if( UnitInVehicle("player") ) then
		VehicleExit()
	elseif( IsMounted() ) then
		Dismount()
	elseif( not InCombatLockdown() and IsOutdoors() ) then
		-- Only attempt to summon a flying mount if we HAVE flying mounts AND we're in a flyable zone
		-- AND my hacky attempt to get around the fact that [flyable] doesn't work right in northrend
		if( #self.myFlyingMounts > 0 and not forceGround and not IsShiftKeyDown() and self:IsFlyableArea() ) then
			self:SummonMount(self.myFlyingMounts)
		else
			self:SummonMount(self.myGroundMounts)
		end
	end
end

function StableBoy:SummonMount(mountList)
	--announce("Summoning!")
	CallCompanion("MOUNT",mountList[random(#mountList)])
end

-- A more robust replacement for the IsFlyableArea() method.
-- This does some advanced checking, to handle the oddities of flying in
-- northrend. It checks for Cold Weather Flying, whether your in Dalaran,
-- and if you're in Krasus' Landing.
function StableBoy:IsFlyableArea()
	SetMapToCurrentZone()

	-- Are we in a 'Flyable' area?
	if( not IsFlyableArea() ) then return false end;
	
	-- We ARE in a 'Flyable' area, are we in Northrend?
	if( GetCurrentMapContinent() ~= 4 ) then return true end;

	-- We ARE in Northrend, do we have Cold Weather Flying (spell ID 54197)?
	if( not GetSpellInfo(GetSpellInfo(54197)) ) then return false end;
	
	-- we HAVE Cold Weather Flying, are we in Dalaran?
	if( not (GetRealZoneText() == 'Dalaran') ) then return true end;
	
	-- We ARE in Dalaran, are we in Krasus' Landing?	
	if( not (GetSubZoneText() == "Krasus' Landing") ) then return false end;
	
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
