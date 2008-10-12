local TL,TC,TR = "TOPLEFT", "TOP", "TOPRIGHT"
local ML,MC,MR = "LEFT", "CENTER", "RIGHT"
local BL,BC,BR = "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"

NHTS_OptionsGeneration = {}

function NHTS_OptionsGeneration:ImportOptionsGeneration(class)
	class.CreatePanel = self.CreatePanel
	class.CreateCheckButton = self.CreateCheckButton
	class.CreateEditBox = self.CreateEditBox
	class.CreateSlider = self.CreateSlider
	class.CreateButton = self.CreateButton
end

function NHTS_OptionsGeneration:CreatePanel(parent, name)
	local panel = CreateFrame('Frame', parent:GetName()..name, parent, 'OptionFrameBoxTemplate')
	panel:SetBackdropBorderColor(0.4, 0.4, 0.4)
	panel:SetBackdropColor(0.15, 0.15, 0.15, 0.5)
	getglobal(panel:GetName() .. 'Title'):SetText(name)
	return panel
end

function NHTS_OptionsGeneration:CreateCheckButton(parent, name)
	local button = CreateFrame('CheckButton', parent:GetName() .. name, parent, 'OptionsCheckButtonTemplate')
	getglobal(button:GetName() .. 'Text'):SetText(name)
	return button
end

local function Slider_OnMouseWheel(self, arg1)
	local step = self:GetValueStep() * arg1
	local value = self:GetValue()
	local minVal, maxVal = self:GetMinMaxValues()

	if step > 0 then
		self:SetValue(min(value+step, maxVal))
	else
		self:SetValue(max(value+step, minVal))
	end
end
function NHTS_OptionsGeneration:CreateSlider(parent, name, min, max, step, orientation)
	local text = parent:GetName()..name
	local slider = CreateFrame("Slider", text, parent, 'OptionsSliderTemplate')
	slider:SetMinMaxValues(min, max)
	slider:SetValueStep(step)
	slider:SetScript('OnMouseWheel', Slider_OnMouseWheel)
	slider:EnableMouseWheel(true)
	
	getglobal(text .. 'Text'):SetText(name)
	getglobal(text .. 'Low'):SetText('')
	getglobal(text .. 'High'):SetText('')
	
	local value = slider:CreateFontString(nil, 'BACKGROUND')
	value:SetFontObject('GameFontHighlightSmall')
	value:SetPoint('LEFT', slider, 'RIGHT', 7, 0)
	slider.valText = value

	return slider
end

function NHTS_OptionsGeneration:CreateButton(parent, name, w, h)
	local button = CreateFrame('Button', parent:GetName()..name, parent, 'UIPanelButtonTemplate')
	button:SetText(name)
	button:SetWidth(w)
	button:SetHeight(h)
	return button
end


function NHTS_OptionsGeneration:CreateEditBox(parent, name, length)
	local editbox = CreateFrame("EditBox", parent:GetName()..name, parent,"InputBoxTemplate")
	editbox:SetAutoFocus(false)
	editbox:SetFontObject(ChatFontNormal)
	editbox:SetMaxLetters(length)
	editbox:SetHeight(20)
	editbox:SetWidth(length*10)
		
	local label = editbox:CreateFontString(editbox:GetName().."Label","OVERLAY","GameFontNormalSmall")
	label:SetHeight(20)
	label:SetPoint(ML, editbox, MR, 3)
	label:SetText(name)
	editbox.label = label
	
	return editbox
end
