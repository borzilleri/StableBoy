How To Localize StableBoy:

- All the strings you need to localize are found in \locales\enUS.lua
- You can email me (nighthawkthesane@gmail.com) the localilized strings, or send me an entire local file
- If you send me a local file, please use the format below (or look at one of the other non-enUS locales as an example):

-- Start of the locale file
local L = STABLEBOY_LOCALE

if ( GetLocale() == "deDE" ) then
	L.SomeString = "Localized String"
end
-- End of the local file
