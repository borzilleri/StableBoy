local MOUNT_GROUND = 1
local MOUNT_FLYING = 2
local SPEED_SLOW = 1
local SPEED_MEDIUM = 2
local SPEED_FAST = 3
local CONDITION_MOUNTED = '[mounted]'
local CONDITION_MOUNTABLE = '[outdoors]'
local CONDITION_FLYABLE = '[flyable]'
--local mounts = STABLEBOY_MOUNTS
BINDING_HEADER_STABLEBOY = 'StableBoy'
BINDING_NAME_STABLEBOY_MOUNT_BEST = 'Summon Best Mount'
BINDING_NAME_STABLEBOY_MOUNT_GROUND = 'Summon Ground Mount'

CreateFrame("GameTooltip","StableBoyTooltip",UIParent,"GameTooltipTemplate")
StableBoyTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function announce(msg)
	DEFAULT_CHAT_FRAME:AddMessage("StableBoy: "..msg)
end

StableBoy = CreateFrame("frame", "StableBoy", UIParent)
StableBoy:SetScript("OnEvent", function(self, event, ...) return self[event](self, ...) end)
StableBoy:RegisterEvent("ADDON_LOADED")
StableBoy.myGroundMounts = {}
StableBoy.myFlyingMounts = {}

-- I could probably separate the various parts of this method into sub-methods
function StableBoy:ADDON_LOADED(addon,...)
	if( addon == 'StableBoy' ) then
		-- Register Events
		self:RegisterEvent('PLAYER_LOGIN')
		self:RegisterEvent('COMPANION_LEARNED')
		
		-- Set Scripts
		self.frame = CreateFrame("Button", "StableBoyFrame", UIParent)
		self.frame:Hide()
		self.frame:SetScript("OnClick", function(...) StableBoy:ClickHandler() end)
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
		local thisMount = { mountType=MOUNT_GROUND, speed=SPEED_SLOW}
		local flying, extremely, very, fast
		local creatureID,name,spellID = GetCompanionInfo('MOUNT',i)
		
		StableBoyTooltip:SetHyperlink("spell:"..spellID)
		
		local numLines = StableBoyTooltip:NumLines()
		for j=1,numLines do
			local text = _G["StableBoyTooltipTextLeft"..j]:GetText()
			for word in string.gmatch(text, "%a+") do
				if( word == "Outland" or word == "Northrend" ) then
					thisMount.mountType = MOUNT_FLYING
				elseif( word == "extremely" ) then
					extremely = true
				elseif( word == "very" ) then
					very = true
				elseif( word == "fast" ) then
					fast = true
				end
			end -- word in string.gmatch
		end -- j=1,numLines
		
		if( extremely and fast ) then
			thisMount.speed=SPEED_FAST
		elseif( very and fast ) then
			thisMount.speed=SPEED_MEDIUM
		end
		
		if( thisMount.mountType == MOUNT_GROUND and thisMount.speed > maxGroundSpeed ) then
			maxGroundSpeed = thisMount.speed
		elseif( thisMount.mountType == MOUNT_FLYING and thisMount.speed > maxFlyingSpeed ) then
			maxFlyingSpeed = thisMount.speed
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

-- Deprecated
function StableBoy:InitializeMounts()
	self.myFlyingMounts = {}
	self.myGroundMounts = {}
	
	local myMounts = {}
	local maxGroundSpeed = 0
	local maxFlightSpeed = 0
	local maxMounts = GetNumCompanions("MOUNT")

	for i=1,maxMounts do
		local creatureID,name,spellID = GetCompanionInfo("MOUNT",i)		
		announce(i..":"..name..":"..spellID)
		if( mounts[spellID] ) then
			myMounts[spellID] = i
			if( mounts[spellID].mountType == MOUNT_FLYING and mounts[spellID].speed >= maxFlightSpeed ) then
				maxFlightSpeed = mounts[spellID].speed
			elseif( mounts[spellID].mountType == MOUNT_GROUND and mounts[spellID].speed >= maxGroundSpeed ) then
				maxGroundSpeed = mounts[spellID].speed
			end
		else
			-- We don't know about the mount, /cry.
			-- TODO: Try to parse the tooltip to figure out type/speed
		end
	end
	
	for spellID,cID in pairs(myMounts) do
		if( mounts[spellID].mountType == MOUNT_FLYING and mounts[spellID].speed >= maxFlightSpeed ) then
			self.myFlyingMounts[#self.myFlyingMounts+1] = cID
		elseif( mounts[spellID].mountType == MOUNT_GROUND and mounts[spellID].speed >= maxGroundSpeed ) then
			self.myGroundMounts[#self.myGroundMounts+1] = cID
		end
	end
end

function StableBoy:ClickHandler(forceGround)
	if( UnitInVehicle("player") ) then
		VehicleExit()
	elseif( IsMounted() ) then
		Dismount()
	elseif( not InCombatLockdown() and SecureCmdOptionParse("[outdoors,nocombat]") ) then
		-- Only attempt to summon a flying mount if we HAVE flying mounts AND we're in a flyable zone
		-- AND my hacky attempt to get around the fact that [flyable] doesn't work right in northrend
		if( #self.myFlyingMounts > 0 and not forceGround and self:IsFlyableArea() ) then
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

-- This is (slightly) saner than NorthrendFlyable(), but it's a more full-on and
-- robust replacement for the global IsFlyableArea() method.
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


-- Hack of a function until they fix the [flyable] conditional in Northrend
-- Returns TRUE if the player is NOT in northrend, OR if the player knows Cold Weather Flying.
-- Returns false if the player IS in northrend AND does not know Cold Weather Flying
function StableBoy:NorthrendFlyable()
	-- Yes, this is a no-no, and an ugly hack, but I don't care because it'll work,
	-- and I'm lazy. I may fix this, or I may just wait until [flyable] works and
	-- I can ditch this entire function.
	SetMapToCurrentZone()
	
	-- 54197 is the spelID of "Cold Weather Flying"	
	if( GetCurrentMapContinent() ~= 4 or GetSpellInfo(GetSpellInfo(54197))) then
		return true
	else
		return false
	end
end
