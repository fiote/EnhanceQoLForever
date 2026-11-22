local addon = _G.EnhanceQoL
local L = addon.L
local UI = {}
addon.Bags.SettingsNavigation = UI

UI.checkboxes = { "OneBagMode", "OneBagFreeSlotsAtEnd", "ShowCategories", "CombineFreeSlots", "ShowFreeSlots", "CombineDuplicateItems", "ShowNewItems", "ClearNewItemsOnHeaderClick", "CompactCategoryLayout", "CompactCategoryWrap", "CategoryTreeView", "CategoryQuickAdd", "DragBackground", "ShowCloseButton", "RememberLastBankTab", "UseIntegratedBank" }
UI.appearance = { { "SkinPresetLabel", "SkinPresetButton" }, { "IconShapeLabel", "IconShapeButton" }, { "FreeSlotDisplayLabel", "FreeSlotDisplayButton" }, { "FreeSlotNormalColorLabel", "FreeSlotNormalColorSwatch" }, { "FreeSlotReagentColorLabel", "FreeSlotReagentColorSwatch" }, { "FrameBackgroundLabel", "FrameBackgroundButton" }, { "FrameBackgroundColorLabel", "FrameBackgroundColorSwatch" }, { "FrameBackgroundOpacityLabel", "FrameBackgroundOpacityStepper" }, { "FrameBorderTextureLabel", "FrameBorderTextureButton" }, { "FrameBorderColorLabel", "FrameBorderColorSwatch" }, { "FrameBorderSizeLabel", "FrameBorderSizeStepper" }, { "FrameBorderOffsetLabel", "FrameBorderOffsetStepper" } }
UI.typography = { { "TextFontLabel", "TextFontButton" }, { "TextSizeLabel", "TextSizeStepper" }, { "TextOverlaySizeLabel", "TextOverlaySizeStepper" }, { "TextOutlineLabel", "TextOutlineButton" } }

UI.themeButtons=setmetatable({}, {__mode="k"})
function UI.LoadTheme()
 local lib=addon.LibSettingsDesigner.UI
 lib.ApplyThemeColors(addon.ConfigApp);lib.ApplyThemeBorders(addon.ConfigApp);lib.ApplyThemeTextures(addon.ConfigApp)
 UI.colors=lib.ResolveThemeColors(addon.ConfigApp)
 UI.borders=lib.ResolveThemeBorders(addon.ConfigApp)
 return UI.colors
end
function UI.Colors() return UI.colors or UI.LoadTheme() end
function UI.Asset(file)
 local root=addon.ConfigApp and addon.ConfigApp.opts.assetRoot or "Interface\\AddOns\\EnhanceQoL\\libs\\LibSettingsDesigner\\Assets\\"
 return root..file
end
function UI.Paint(frame,kind,bg,border)
 if not frame.SetBackdrop then Mixin(frame,BackdropTemplateMixin) end
 local style=(UI.borders or addon.LibSettingsDesigner.UI.ResolveThemeBorders(addon.ConfigApp))[kind]
 frame:SetBackdrop(style and style.backdrop or {bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
 frame._LibSettingsDesignerBorderStyleKey=kind
 frame:SetBackdropColor(unpack(bg));frame:SetBackdropBorderColor(unpack(border))
 addon.LibSettingsDesigner.UI.ApplyTextureStyle(frame,bg,border,kind)
end
function UI.IsToolbar(frame)
 while frame do
  if frame._bagsToolbarEditor or frame._bagsToolbarCard then return true end
  frame=frame:GetParent()
 end
 return false
end
-- Feature callbacks may be replaced after a control is styled. Keep visual updates attached.
function UI.UpdateVisualScript(frame,event,handler)
 if handler and handler==frame._bagsVisualWrappers[event] then return end
 local visual=frame._bagsVisualCallbacks[event]
 local wrapper=function(...)
  if handler then handler(...) end
  visual(...)
 end
 frame._bagsVisualWrappers[event]=wrapper
 frame._bagsBindingVisual=true
 frame:SetScript(event,wrapper)
 frame._bagsBindingVisual=nil
end
function UI.BindVisualScript(frame,event,callback)
 if not frame._bagsVisualCallbacks then
  frame._bagsVisualCallbacks={};frame._bagsVisualWrappers={}
  hooksecurefunc(frame,"SetScript",function(self,name,handler)
   if not self._bagsBindingVisual and self._bagsVisualCallbacks[name] then UI.UpdateVisualScript(self,name,handler) end
  end)
 end
 if frame._bagsVisualCallbacks[event] then return end
 frame._bagsVisualCallbacks[event]=callback
 UI.UpdateVisualScript(frame,event,frame:GetScript(event))
end
function UI.RefreshOnEnabled(frame,callback)
 for _,method in ipairs({"SetEnabled","Enable","Disable"}) do
  if frame[method] then hooksecurefunc(frame,method,callback) end
 end
end

function UI.PaintButton(button)
 if UI.IsToolbar(button) then return end
 local c=UI.Colors()
 local enabled=not button.IsEnabled or button:IsEnabled()
 local bg,border=c.buttonBg,c.buttonBorder
 if button._bagsDropdown then bg,border=c.dropdownBg,c.dropdownBorder end
 if button._bagsTab then
  bg,border=button.selected and c.tabSelectedBg or c.tabBg,{0,0,0,0}
 elseif button._bagsNavigation then
  bg,border=button.selected and c.selectedBg or {0,0,0,0},{0,0,0,0}
 end
 if not enabled then bg,border=c.disabledControlBg,c.disabledControlBorder
 elseif button._bagsHovered then bg,border=c.buttonHoverBg,c.buttonHoverBorder
 elseif button._bagsPressed then bg,border=c.selectedBg,c.buttonHoverBorder end
 UI.Paint(button,(button._bagsTab or button._bagsNavigation) and "row" or button._bagsDropdown and "dropdownControl" or "button",bg,border)
 if button._bagsTab then
  bg,border={0,0,0,0},{0,0,0,0}
  UI.Paint(button,"row",bg,border)
  if not button._bagsUnderline then
   button._bagsUnderline=button.ActiveUnderline or button:CreateTexture(nil,"OVERLAY")
   button._bagsUnderline:SetHeight(2);button._bagsUnderline:SetPoint("BOTTOMLEFT",8,0);button._bagsUnderline:SetPoint("BOTTOMRIGHT",-8,0)
  end
 end
 if button.BagsCloseIcon then
  for _,part in ipairs(button.BagsCloseIcon.parts) do part:SetColorTexture(unpack(button._bagsHovered and c.accent or c.textMain)) end
 end
 if button.BagsNavIcon then
  for _,part in ipairs(button.BagsNavIcon.parts) do part:SetColorTexture(unpack((button.selected or button._bagsHovered) and c.accent or c.textMuted)) end
 end
 local label=button.NavLabel or button.Label or button:GetFontString()
 if label then label:SetTextColor(unpack(not enabled and c.textDisabled or (button.selected or (button._bagsTab and button._bagsHovered)) and c.accent or c.textMain)) end
 if button._bagsUnderline then button._bagsUnderline:SetColorTexture(unpack(c.tabUnderline));button._bagsUnderline:SetShown(button.selected==true or button._bagsHovered==true) end
 if button.SelectedTexture then button.SelectedTexture:SetVertexColor(unpack(c.accent)) end
end
function UI.StyleDropdown(button)
 if button._bagsDropdown or UI.IsToolbar(button) then return end
 button._bagsDropdown=true
 local arrow=button:CreateTexture(nil,"OVERLAY");arrow:SetTexture(UI.Asset("LibSettingsDesigner_DropdownDown.tga"));arrow:SetSize(12,12);arrow:SetPoint("RIGHT",-8,0);arrow:SetVertexColor(unpack(UI.Colors().accent))
 local label=button:GetFontString();if label then label:SetPoint("RIGHT",-26,0) end
 UI.PaintButton(button)
end
function UI.PaintToggle(button)
 local c=UI.Colors();local enabled=button:IsEnabled();local checked=button:GetChecked()
 local bg=checked and {.020,.520,.380,.94} or {.030,.036,.038,.94}
 local knob=checked and {.92,1,.92,1} or {.34,.38,.34,1}
 if not enabled then bg,knob=c.disabledControlBg,c.textDisabled end
 UI.Paint(button.BagsSwitch,"toggle",bg,{0,0,0,0})
 UI.Paint(button.BagsSwitch.Knob,"toggleKnob",knob,{0,0,0,0})
 button.BagsSwitch.Knob:ClearAllPoints();button.BagsSwitch.Knob:SetPoint(checked and "RIGHT" or "LEFT",button.BagsSwitch,checked and "RIGHT" or "LEFT",checked and -2 or 2,0)
end
function UI.StyleToggle(button)
 if UI.IsToolbar(button) then return end
 if button.BagsSwitch then UI.PaintToggle(button);return end
 for _,region in ipairs({button:GetRegions()}) do if region:GetObjectType()=="Texture" then region:SetAlpha(0) end end
 local body=CreateFrame("Frame",nil,button,"BackdropTemplate");body:SetSize(34,18);body:SetPoint("CENTER")
 body.Knob=CreateFrame("Frame",nil,body,"BackdropTemplate");body.Knob:SetSize(12,12)
 button.BagsSwitch=body
 UI.BindVisualScript(button,"OnClick",UI.PaintToggle);UI.BindVisualScript(button,"OnShow",UI.PaintToggle)
 hooksecurefunc(button,"SetChecked",UI.PaintToggle);UI.RefreshOnEnabled(button,UI.PaintToggle)
 UI.PaintToggle(button)
end
function UI.StyleInput(input)
 if UI.IsToolbar(input) or input._bagsMultiline then return end
 if input._bagsThemedInput then input.BagsRefreshInput();return end
 input._bagsThemedInput=true
 input:SetFontObject(GameFontHighlightSmall)
 for _,region in ipairs({input:GetRegions()}) do if region:GetObjectType()=="Texture" then region:Hide() end end
 local bg=input;input.BagsInputBackground=input
 local function refresh()
  local c=UI.Colors();local focus=input:HasFocus();local enabled=not input.IsEnabled or input:IsEnabled()
  UI.Paint(bg,"inputControl",not enabled and c.disabledControlBg or focus and c.inputFocusBg or c.inputBg,not enabled and c.disabledControlBorder or focus and c.inputFocusBorder or c.inputBorder)
  input:SetTextColor(unpack(enabled and c.textMain or c.textDisabled))
 end
 input.BagsRefreshInput=refresh
 UI.RefreshOnEnabled(input,refresh)
 input:SetTextInsets(14,14,0,0)
 UI.BindVisualScript(input,"OnEditFocusGained",refresh);UI.BindVisualScript(input,"OnEditFocusLost",refresh);UI.BindVisualScript(input,"OnShow",refresh)
 refresh()
end
function UI.StyleEditorInput(input,viewport)
 local function refresh()
  local c=UI.Colors();local focused=input:HasFocus()
  UI.Paint(viewport,"card",c.inputBg,focused and c.inputFocusBorder or c.inputBorder)
  input:SetTextColor(unpack(c.textMain))
 end
 UI.BindVisualScript(input,"OnEditFocusGained",refresh);UI.BindVisualScript(input,"OnEditFocusLost",refresh);UI.BindVisualScript(viewport,"OnShow",refresh)
 refresh()
end
function UI.CreateInput(_,name,parent,template)
 local input=CreateFrame("EditBox",name,parent,"BackdropTemplate")
 input:SetJustifyH("LEFT")
 UI.StyleInput(input)
 return input
end
function UI.OuterBorder(frame)
 if frame.BagsWindowBorder then return end
 local pieces={};frame.BagsWindowBorder=pieces
 for _,key in ipairs({"tl","tr","bl","br","t","b","l","r"}) do
  local tx=frame:CreateTexture(nil,"BORDER",nil,2);tx:SetTexture(UI.Asset("PanelBorder_"..key..".tga"));pieces[key]=tx
 end
 for _,spec in ipairs({{"tl","TOPLEFT",-10,10},{"tr","TOPRIGHT",16,10},{"bl","BOTTOMLEFT",-10,-10},{"br","BOTTOMRIGHT",16,-10}}) do
  local tx=pieces[spec[1]];tx:SetSize(58,58);tx:SetPoint(spec[2],frame,spec[2],spec[3],spec[4])
 end
 pieces.t:SetPoint("TOPLEFT",pieces.tl,"TOPRIGHT");pieces.t:SetPoint("TOPRIGHT",pieces.tr,"TOPLEFT");pieces.t:SetHeight(58);pieces.t:SetHorizTile(true)
 pieces.b:SetPoint("BOTTOMLEFT",pieces.bl,"BOTTOMRIGHT");pieces.b:SetPoint("BOTTOMRIGHT",pieces.br,"BOTTOMLEFT");pieces.b:SetHeight(58);pieces.b:SetHorizTile(true)
 pieces.l:SetPoint("TOPLEFT",pieces.tl,"BOTTOMLEFT");pieces.l:SetPoint("BOTTOMLEFT",pieces.bl,"TOPLEFT");pieces.l:SetWidth(58);pieces.l:SetVertTile(true)
 pieces.r:SetPoint("TOPRIGHT",pieces.tr,"BOTTOMRIGHT");pieces.r:SetPoint("BOTTOMRIGHT",pieces.br,"TOPRIGHT");pieces.r:SetWidth(58);pieces.r:SetVertTile(true)
end
function UI.ThemeTree(frame)
 if UI.IsToolbar(frame) then return end
 for _,region in ipairs({frame:GetRegions()}) do
  if region:GetObjectType()=="FontString" and (region:GetFontObject()==GameFontDisableSmall or (_G.GameFontDisable and region:GetFontObject()==_G.GameFontDisable)) then
   region:SetTextColor(unpack(UI.Colors().textMuted))
  end
 end
 if frame:GetObjectType()=="EditBox" then UI.StyleInput(frame) end
 if frame.BagsCheckboxBorder then UI.StyleToggle(frame) end
 if frame._bagsCard then UI.Paint(frame,"card",UI.Colors().cardBg,UI.Colors().cardBorder) end
 for _,child in ipairs({frame:GetChildren()}) do UI.ThemeTree(child) end
end

function UI.FlatButton(button)
 if button._bagsFlat then UI.PaintButton(button);return end
 button._bagsFlat=true
 if UI.IsToolbar(button) then
  for _,state in ipairs({{"Normal",.12,.17,.23,1},{"Highlight",.3,.65,1,.22},{"Pushed",.16,.38,.56,1},{"Disabled",.08,.10,.13,1}}) do
   button["Set"..state[1].."Texture"](button,"Interface\\Buttons\\WHITE8x8")
   local tx=addon.PixelUtil.ApplyTexturePixelSnapping(button["Get"..state[1].."Texture"](button));tx:SetVertexColor(state[2],state[3],state[4],state[5])
  end
  button:SetNormalFontObject(GameFontHighlightSmall);button:SetHighlightFontObject(GameFontHighlightSmall);button:SetDisabledFontObject(GameFontDisableSmall)
  return
 end
 for _,key in ipairs({"Normal","Highlight","Pushed","Disabled"}) do
  button["Set"..key.."Texture"](button,"Interface\\Buttons\\WHITE8x8")
  button["Get"..key.."Texture"](button):SetAlpha(0)
 end
 button:SetNormalFontObject(GameFontHighlightSmall);button:SetHighlightFontObject(GameFontHighlightSmall);button:SetDisabledFontObject(GameFontDisableSmall)
 UI.BindVisualScript(button,"OnEnter",function(self) self._bagsHovered=true;UI.PaintButton(self) end)
 UI.BindVisualScript(button,"OnLeave",function(self) self._bagsHovered=nil;self._bagsPressed=nil;UI.PaintButton(self) end)
 UI.BindVisualScript(button,"OnMouseDown",function(self) self._bagsPressed=true;UI.PaintButton(self) end)
 UI.BindVisualScript(button,"OnMouseUp",function(self) self._bagsPressed=nil;UI.PaintButton(self) end)
 UI.BindVisualScript(button,"OnHide",function(self) self._bagsHovered=nil;self._bagsPressed=nil;UI.PaintButton(self) end)
 UI.RefreshOnEnabled(button,UI.PaintButton)
 UI.themeButtons[button]=true;UI.PaintButton(button)
end

-- Plain buttons avoid template scripts restoring the native artwork on state changes.
function UI.CreateButton(_, name, parent)
	local button = CreateFrame("Button", name, parent,"BackdropTemplate")
	local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", 6, 0)
	label:SetPoint("RIGHT", -6, 0)
	label:SetWordWrap(false)
	button:SetFontString(label)
	UI.FlatButton(button)
	return button
end

function UI.CreateCheckbox(_, name, parent)
	local button = CreateFrame("CheckButton", name, parent)
	button:SetSize(UI.IsToolbar(button) and 24 or 34, 24)
	local background = addon.PixelUtil.ApplyTexturePixelSnapping(button:CreateTexture(nil, "BACKGROUND"))
	background:SetSize(17, 17)
	background:SetPoint("CENTER")
	background:SetColorTexture(0.07, 0.1, 0.14, 1)
	button.BagsCheckboxBorder = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local edge = addon.PixelUtil.ApplyTexturePixelSnapping(button:CreateTexture(nil, "BORDER"))
		edge:SetPoint(side, background, side)
		edge:SetSize((side == "TOP" or side == "BOTTOM") and 17 or 1, (side == "TOP" or side == "BOTTOM") and 1 or 17)
		edge:SetColorTexture(0.48, 0.6, 0.72, 1)
		button.BagsCheckboxBorder[#button.BagsCheckboxBorder + 1] = edge
	end
	local check = addon.PixelUtil.ApplyTexturePixelSnapping(button:CreateTexture(nil, "OVERLAY"))
	check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	check:SetSize(22, 22)
	check:SetPoint("CENTER")
	check:SetVertexColor(0.45, 0.85, 1, 1)
	button:SetCheckedTexture(check)
	local disabled = addon.PixelUtil.ApplyTexturePixelSnapping(button:CreateTexture(nil, "OVERLAY"))
	disabled:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	disabled:SetSize(22, 22)
	disabled:SetPoint("CENTER")
	disabled:SetVertexColor(0.42, 0.5, 0.6, 1)
	button:SetDisabledCheckedTexture(disabled)
	local hover = addon.PixelUtil.ApplyTexturePixelSnapping(button:CreateTexture(nil, "HIGHLIGHT"))
	hover:SetColorTexture(0.3, 0.65, 1, 0.25)
	hover:SetSize(17, 17)
	hover:SetPoint("CENTER")
	button:SetHighlightTexture(hover)
	UI.StyleToggle(button)
	return button
end

-- Nested lists pass wheel input outward when they cannot scroll any further.
function UI.ScrollMouseWheel(frame, delta)
	while frame do
		local bar = frame.ScrollBar
		if bar then
			local low, high = bar:GetMinMaxValues()
			local current = bar:GetValue()
			local value = math.max(low, math.min(high, current - delta * 32))
			if value ~= current then
				bar:SetValue(value)
				return
			end
		end
		frame = frame:GetParent()
	end
end

-- Keep the bar outside the clipped viewport while retaining its visibility lifecycle.
function UI.StyleScrollBar(scrollFrame, scrollBar)
	scrollBar:SetParent(scrollFrame:GetParent())
	-- The template callback resolves the scroll target through GetParent().
	-- Bind the original viewport explicitly after moving the bar out of its clip.
	scrollBar:SetScript("OnValueChanged", function(_, value) scrollFrame:SetVerticalScroll(value) end)
	scrollBar:SetFrameLevel(scrollFrame:GetFrameLevel() + 2)
	scrollFrame:HookScript("OnHide", function() scrollBar:Hide() end)
	scrollFrame:HookScript("OnShow", function()
		local _, maximum = scrollBar:GetMinMaxValues()
		scrollBar:SetShown(maximum > 0)
	end)
	-- The classic template stores its arrow buttons as named globals.
	for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton", "Top", "Bottom", "Middle" }) do
		local part = scrollBar[key] or (scrollBar:GetName() and _G[scrollBar:GetName() .. key])
		if part then
			part:Hide()
			part:SetAlpha(0)
			if part.EnableMouse then part:EnableMouse(false) end
		end
	end
	for _,region in ipairs({scrollBar:GetRegions()}) do if region:GetObjectType()=="Texture" then region:Hide() end end
	local track = addon.PixelUtil.ApplyTexturePixelSnapping(scrollBar:CreateTexture(nil, "BACKGROUND"))
	track:SetPoint("TOP");track:SetPoint("BOTTOM");track:SetWidth(4)
	track:SetColorTexture(unpack(UI.Colors().panelBorder))
	scrollBar:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
	local thumb = addon.PixelUtil.ApplyTexturePixelSnapping(scrollBar:GetThumbTexture())
	thumb:Show();thumb:SetSize(6, 32)
	thumb:SetVertexColor(unpack(UI.Colors().accent))
end

-- Small line symbols share the sidebar text colors and remain readable at 20 pixels.
UI.navGlyphs = {
 layout = {{2,2,9,2},{9,2,9,9},{9,9,2,9},{2,9,2,2},{13,2,20,2},{20,2,20,9},{20,9,13,9},{13,9,13,2},{2,13,9,13},{9,13,9,20},{9,20,2,20},{2,20,2,13},{13,13,20,13},{20,13,20,20},{20,20,13,20},{13,20,13,13}},
 categories = {{3,19,3,3},{3,16,8,16},{3,6,8,6},{8,13,20,13},{20,13,20,19},{20,19,8,19},{8,19,8,13},{8,3,20,3},{20,3,20,9},{20,9,8,9},{8,9,8,3}},
 overlays = {{2,8,2,20},{2,20,14,20},{14,20,14,16},{8,2,20,2},{20,2,20,14},{20,14,8,14},{8,14,8,2},{2,8,6,8}},
 footer = {{2,3,20,3},{20,3,20,19},{20,19,2,19},{2,19,2,3},{2,9,20,9},{6,6,8,6},{12,6,16,6}},
 tracking = {{4,4,4,18},{4,18,18,18},{18,18,18,4},{18,4,4,4},{1,11,7,11},{15,11,21,11},{11,1,11,7},{11,15,11,21},{9,9,13,9},{13,9,13,13},{13,13,9,13},{9,13,9,9}},
}
function UI.StyleNavIcon(button)
 if button.BagsNavIcon then return end
 button.Icon:Hide()
 local icon=CreateFrame("Frame",nil,button);icon:SetSize(22,22);icon:SetPoint("LEFT",12,0);icon.parts={}
 for _,segment in ipairs(UI.navGlyphs[button.pageID] or UI.navGlyphs.layout) do
  local part=icon:CreateLine(nil,"ARTWORK");part:SetThickness(1.5)
  part:SetStartPoint("BOTTOMLEFT",icon,segment[1],segment[2]);part:SetEndPoint("BOTTOMLEFT",icon,segment[3],segment[4])
  part:SetColorTexture(unpack(UI.Colors().textMuted));icon.parts[#icon.parts+1]=part
 end
 button.BagsNavIcon=icon
end
function UI.StyleDialog(frame)
 local c=UI.Colors()
 UI.Paint(frame,"card",{c.cardBg[1],c.cardBg[2],c.cardBg[3],1},c.cardBorder)
 if not frame.BagsDialogSurface then
  frame.BagsDialogSurface=frame:CreateTexture(nil,"BACKGROUND",nil,1);frame.BagsDialogSurface:SetAllPoints()
 end
 frame.BagsDialogSurface:SetColorTexture(c.cardBg[1],c.cardBg[2],c.cardBg[3],1)
 UI.ThemeTree(frame)
end

function UI.StyleNavigationButton(button)
	button:SetSize(154, 42)
	button._bagsNavigation=true
	UI.FlatButton(button)
	button.Background:Hide()
	button.HighlightTexture:Hide()
	button.SelectedTexture:SetTexture("Interface\\Buttons\\WHITE8x8")
	button.SelectedTexture:ClearAllPoints()
	button.SelectedTexture:SetPoint("TOPLEFT")
	button.SelectedTexture:SetPoint("BOTTOMLEFT")
	button.SelectedTexture:SetWidth(3)
	button.SelectedTexture:SetVertexColor(unpack(UI.Colors().accent))
	button.Icon:ClearAllPoints()
	button.Icon:SetPoint("LEFT", 12, 0)
	button.Icon:SetSize(20, 20)
	UI.StyleNavIcon(button)
	local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", button, "LEFT", 40, 0)
	label:SetPoint("RIGHT", button, "RIGHT", -8, 0)
	label:SetJustifyH("LEFT")
	label:SetText(button.tooltipTitle)
	button.NavLabel = label
	-- Keep icons fixed when pressing a text navigation row.
	button:SetScript("OnMouseDown", nil)
	button:SetScript("OnMouseUp", nil)
end

function UI.StyleWindowControls(frame)
 local close=frame.CloseButton
 if not close.BagsCloseIcon then
  close:GetFontString():Hide()
  local icon=CreateFrame("Frame",nil,close);icon:SetSize(14,14);icon:SetPoint("CENTER");icon.parts={}
  for _,segment in ipairs({{2,2,12,12},{2,12,12,2}}) do
   local part=icon:CreateLine(nil,"ARTWORK");part:SetThickness(2)
   part:SetStartPoint("BOTTOMLEFT",icon,segment[1],segment[2]);part:SetEndPoint("BOTTOMLEFT",icon,segment[3],segment[4])
   icon.parts[#icon.parts+1]=part
  end
  close.BagsCloseIcon=icon
 end
 UI.PaintButton(close)
 local resize=frame.ResizeButton
 resize:ClearAllPoints();resize:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",14,-8);resize:SetSize(20,20)
 resize:SetFrameLevel(frame:GetFrameLevel()+25)
 if frame.ScaleSlider then frame.ScaleSlider:SetFrameLevel(frame:GetFrameLevel()+4) end
end

function UI.StyleFrame(frame)
	local c=UI.LoadTheme()
	UI.Paint(frame,"panel",c.frameBg,{0,0,0,0})
	frame.Background:SetDrawLayer("BACKGROUND",1)
	frame.Background:SetColorTexture(c.detailSectionBg[1],c.detailSectionBg[2],c.detailSectionBg[3],1)
	frame.Background:SetVertexColor(1,1,1,1)
	frame.Background:SetAlpha(1)
	frame.BackgroundShade:Hide()
 if not frame.BagsHeader then
  frame.BagsHeader=frame:CreateTexture(nil,"BACKGROUND",nil,3)
  frame.BagsHeader:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-10);frame.BagsHeader:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-16,-10);frame.BagsHeader:SetHeight(22)
 end
 frame.BagsHeader:SetColorTexture(c.detailSectionBg[1],c.detailSectionBg[2],c.detailSectionBg[3],1)
 frame.CloseButton:SetFrameLevel(frame:GetFrameLevel()+3)
	if not frame.MaterialOverlay then
		frame.MaterialOverlay=frame:CreateTexture(nil,"BACKGROUND",nil,-6);frame.MaterialOverlay:SetAllPoints(frame.Background)
		frame.MaterialOverlay:SetTexture(UI.Asset("LibSettingsDesigner_BackgroundDark.tga"));frame.MaterialOverlay:SetAlpha(.08)
	end
	frame.MaterialOverlay:SetDrawLayer("BACKGROUND",2)
	frame.MaterialOverlay:SetVertexColor(unpack(c.overlayTint))
	frame.MaterialOverlay:SetAlpha(0)
	UI.OuterBorder(frame)
	UI.ThemeTree(frame)
	if not frame.BagsSidebar then
		frame.BagsSidebar=CreateFrame("Frame",nil,frame,"BackdropTemplate");frame.BagsSidebar:SetPoint("TOPLEFT",12,-32);frame.BagsSidebar:SetPoint("BOTTOMLEFT",12,16);frame.BagsSidebar:SetWidth(166)
		frame.BagsSidebar:SetFrameLevel(frame:GetFrameLevel()+1)
	end
	UI.Paint(frame.BagsSidebar,"sidebar",{0,0,0,0},c.panelBorder)
	if not frame.BagsContentShell then
		frame.BagsContentShell=CreateFrame("Frame",nil,frame,"BackdropTemplate")
		frame.BagsContentShell:SetPoint("TOPLEFT",178,-32);frame.BagsContentShell:SetPoint("BOTTOMRIGHT",-16,16)
		frame.BagsContentShell:SetFrameLevel(frame:GetFrameLevel()+1)
	end
	UI.Paint(frame.BagsContentShell,"content",{0,0,0,0},c.panelBorder)
	for _,spec in ipairs({{frame.BagsSidebar,"sidebar"},{frame.BagsContentShell,"content"}}) do
		local pane,kind=spec[1],spec[2]
		local opts=addon.ConfigApp.opts[kind] or {}
		if not pane.Material then pane.Material=pane:CreateTexture(nil,"BACKGROUND",nil,1);pane.Material:SetAllPoints() end
		pane.Material:SetTexture(opts.backgroundTexture);pane.Material:SetAlpha(opts.backgroundAlpha or .85)
	end
	frame.PanelBackground:SetColorTexture(0,0,0,0)
	frame.PanelShade:SetColorTexture(0, 0, 0, 0)
	frame.PanelBorder:Hide()
	frame.PanelTopDetail:Hide()
	frame.TitleText:SetTextColor(unpack(c.topbarAccent))
	frame.NavPanel:ClearAllPoints()
	frame.NavPanel:SetPoint("TOPLEFT", frame.PanelBackground, "TOPLEFT", 12, -34)
	frame.NavPanel:SetWidth(154)
	frame.NavPanel:SetFrameLevel(frame.BagsSidebar:GetFrameLevel()+1)
	frame.ModeCard:ClearAllPoints()
	frame.ModeCard:SetPoint("TOPLEFT", frame.PanelBackground, "TOPLEFT", 182, -76)
	frame.ModeCard:SetPoint("TOPRIGHT", frame.PanelBackground, "TOPRIGHT", -20, -76)
	frame.PageContainer:ClearAllPoints()
	frame.PageContainer:SetPoint("TOPLEFT", frame.ModeCard, "BOTTOMLEFT", 14, -12)
	frame.PageContainer:SetPoint("BOTTOMRIGHT", frame.BagsContentShell, "BOTTOMRIGHT", -26, 12)
	frame.ModeCard:SetFrameLevel(frame:GetFrameLevel()+2)
	frame.PageContainer:SetFrameLevel(frame:GetFrameLevel()+2)
	if frame.BagsSearchInput then frame.BagsSearchInput:SetFrameLevel(frame:GetFrameLevel()+3) end
	UI.FlatButton(frame.ModeCard.SwitchButton)
	UI.FlatButton(frame.ModeCard.CopyButton)
	UI.CompactModeCard(frame.ModeCard)
	UI.StyleWindowControls(frame)
	for button in pairs(UI.themeButtons) do UI.PaintButton(button) end
end

function UI.CompactModeCard(card)
	card:SetHeight(48)
	card.Title:ClearAllPoints()
	card.Title:SetPoint("TOPLEFT", 14, -8)
	card.Status:ClearAllPoints()
	card.Status:SetPoint("TOPLEFT", card.Title, "BOTTOMLEFT", 0, -3)
	card.Status:SetFontObject(GameFontHighlightSmall)
	card.Description:Hide()
	card.SwitchButton:ClearAllPoints()
	card.SwitchButton:SetPoint("RIGHT", card, "RIGHT", -14, 0)
	card.CopyButton:ClearAllPoints()
	card.CopyButton:SetPoint("RIGHT", card.SwitchButton, "LEFT", -8, 0)
	card:EnableMouse(true)
	card:SetScript("OnEnter", function()
		GameTooltip:SetOwner(card, "ANCHOR_TOP")
		GameTooltip:SetText(card.Title:GetText())
		GameTooltip:AddLine(card.Description:GetText(), 1, 1, 1, true)
		GameTooltip:Show()
	end)
	card:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI.CreateGlobalSort(page, openMenu, afterChange)
	local label = page.Content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetText(L["settingsGlobalCategorySortLabel"])
	label:SetJustifyH("LEFT")
	page.GlobalSortLabel = label
	local button = UI.CreateButton("Button", nil, page.Content)
	button:SetScript("OnClick", function(self)
		addon.Bags.SortMode.OpenMenu(self, addon.GetGlobalCategorySortMode(), true, nil, function(value)
			if addon.SetGlobalCategorySortMode(value) then afterChange() end
		end)
	end)
	page.GlobalSortButton = button
	local hint = page.Content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetText(L["settingsGlobalCategorySortDesc"])
	hint:SetJustifyH("LEFT")
	page.GlobalSortHint = hint
	local toggle = UI.CreateCheckbox("CheckButton", nil, page.Content)
	toggle.Label = toggle:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	toggle.Label:SetText(L["settingsBagSortModeButton"])
	toggle:SetScript("OnClick", function(self)
		addon.GetSettings().sortModeButton = self:GetChecked() == true
		afterChange()
	end)
	page.SortModeButtonToggle = toggle
end

function UI.CreateTabs(page)
	page.LayoutTab = "general"
	page.LayoutTabs = {}
	local previewCard = CreateFrame("Frame", nil, page.Content, "BackdropTemplate")
	previewCard:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	previewCard:SetBackdropColor(0.045, 0.06, 0.085, 1)
	previewCard:SetBackdropBorderColor(0.15, 0.2, 0.28, 1)
	previewCard:SetHeight(84)
	page.TextPreviewCard = previewCard
	for _, key in ipairs({ "TextPreviewLabel", "TextPreview", "TextOverlayPreview" }) do page[key]:SetParent(previewCard) end
	local labels = { GENERAL, L["settingsBasicLayoutTitle"], L["settingsBasicLookTitle"], L["settingsTextAppearanceTitle"], L["settingsToolbarTitle"] }
	for index, id in ipairs({ "general", "size", "appearance", "text", "toolbar" }) do
		local button = CreateFrame("Button", nil, page)
		button:SetHeight(32)
		button:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -48)
		local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("TOPLEFT", 6, -3)
		text:SetPoint("BOTTOMRIGHT", -6, 3)
		text:SetText(labels[index])
		button.Label = text
		button._bagsTab=true
		button._bagsUnderline=button:CreateTexture(nil,"OVERLAY");button._bagsUnderline:SetHeight(2);button._bagsUnderline:SetPoint("BOTTOMLEFT",12,0);button._bagsUnderline:SetPoint("BOTTOMRIGHT",-12,0)
		UI.FlatButton(button)
		button:SetScript("OnClick", function()
			page.LayoutTab = id
			page.ScrollFrame:SetVerticalScroll(0)
			if page.ScrollFrame.ScrollBar then page.ScrollFrame.ScrollBar:SetValue(0) end
			addon.RefreshSettingsFrame("layout")
		end)
		button.tabID = id
		page.LayoutTabs[index] = button
	end
	page.ScrollFrame:ClearAllPoints()
	page.ScrollFrame:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -96)
	page.ScrollFrame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -28, 0)
	local itemInfo = UI.CreateCheckbox("CheckButton", nil, page.Content)
	itemInfo.Label = itemInfo:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	itemInfo.Label:SetText(L["bagItemInfoOption"])
	itemInfo:SetScript("OnClick", function(self)
		addon.GetSettings().itemInfoTooltip = self:GetChecked() == true
	end)
	itemInfo:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["bagItemInfoOption"])
		GameTooltip:AddLine(L["bagItemInfoOptionDesc"], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	itemInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
	page.ItemInfoTooltip = itemInfo
	if addon.Bags.EquipmentSets and addon.Bags.EquipmentSets.IsSupported() then
		local checkbox = UI.CreateCheckbox("CheckButton", nil, page.Content)
		checkbox:SetSize(34, 24)
		local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("LEFT", checkbox, "RIGHT", 10, 0)
		label:SetPoint("RIGHT", page.Content, "RIGHT", -12, 0)
		label:SetJustifyH("LEFT")
		label:SetText(L["settingsAutoEquipmentSetCategories"])
		checkbox.Label = label
		local hint = page.Content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		hint:SetPoint("TOPLEFT", checkbox, "BOTTOMLEFT", 28, -4)
		hint:SetPoint("RIGHT", page.Content, "RIGHT", -12, 0)
		hint:SetJustifyH("LEFT")
		hint:SetText(L["settingsAutoEquipmentSetCategoriesDesc"])
		checkbox.Hint = hint
		checkbox:SetScript("OnClick", function(self)
			addon.GetSettings().autoEquipmentSetCategories = self:GetChecked() == true
			addon.MarkCategoryModeStateDirty()
			for _, name in ipairs({ "RequestLayoutUpdate", "RequestBankLayoutUpdate" }) do
				if addon.Bags.functions[name] then addon.Bags.functions[name](true, true) end
			end
			addon.RefreshSettingsFrame("layout")
		end)
		page.AutoEquipmentSets = checkbox
	end
end

function UI.LayoutPairs(page, entries, visible, offset)
	for _, pair in ipairs(entries) do
		local label, control = page[pair[1]], page[pair[2]]
		if label and control then
			label:SetShown(visible)
			control:SetShown(visible)
			if visible then
				control:ClearAllPoints()
				if pair[2]:match("Button$") then UI.StyleDropdown(control);control:SetSize(math.min(260, math.max(170, page.TextAppearanceCard:GetWidth() * 0.42)), 26) end
				control:SetPoint("TOPRIGHT", page.TextAppearanceCard, "TOPRIGHT", -14, -offset)
				label:ClearAllPoints()
				label:SetPoint("LEFT", page.TextAppearanceCard, "LEFT", 14, 0)
				label:SetPoint("RIGHT", control, "LEFT", -16, 0)
				label:SetPoint("TOP", control, "TOP", 0, 0)
				label:SetPoint("BOTTOM", control, "BOTTOM", 0, 0)
				label:SetTextColor(unpack(UI.Colors().textMain))
				offset = offset + math.max(34, control:GetHeight() + 10, label:GetStringHeight() + 10)
			end
		end
	end
	return offset
end

function UI.LayoutText(page, offset, visible, basic)
	local card = page.TextAppearanceCard
	page.TextStylesTitle:SetShown(visible and not basic)
	page.TextStylesTitle:ClearAllPoints()
	page.TextStylesTitle:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -offset - 8)
	if not basic then offset = offset + page.TextStylesTitle:GetStringHeight() + 20 end
	local available = math.max(240, card:GetWidth() - 28)
	local sizeWidth = UI.sliderSpecs["textElementSize.categoryHeader"] and 260 or 74
	local compact = available < (sizeWidth + 604)
	for _, row in ipairs(page.TextStyleRows or {}) do
		row:SetShown(visible and not basic)
		if not basic then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -offset)
			row:SetPoint("RIGHT", card, "RIGHT", -14, 0)
			local labelHeight = math.max(16, row.Label:GetStringHeight())
			local controlsTop = labelHeight + 8
			row.Label:SetTextColor(unpack(UI.Colors().textMain))
			row.FontButton:ClearAllPoints()
			row.FontButton:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -controlsTop)
			row.FontButton:SetSize(math.min(260, available - (compact and sizeWidth + 10 or sizeWidth + 344)), 26)
			row.SizeStepper:ClearAllPoints()
			row.SizeStepper:SetPoint("LEFT", row.FontButton, "RIGHT", 10, 0)
			row.SizeStepper:SetSize(sizeWidth, 26)
			local selector = row.ElementID == "stackCount" and row.StackAnchorButton or row.CaseButton
			selector:ClearAllPoints()
			selector:SetSize(120, 26)
			if compact then
				selector:SetPoint("TOPLEFT", row.FontButton, "BOTTOMLEFT", 0, -8)
			else
				selector:SetPoint("LEFT", row.SizeStepper, "RIGHT", 10, 0)
			end
			row.OutlineButton:ClearAllPoints()
			row.OutlineButton:SetPoint("LEFT", selector, "RIGHT", 10, 0)
			row.OutlineButton:SetSize(math.min(194, available - 130), 26)
			row:SetHeight(controlsTop + (compact and 60 or 26))
			offset = offset + row:GetHeight() + 16
		end
	end
	local checkbox = page.SubcategoryFullLabels
	checkbox:SetShown(visible and not basic)
	checkbox.Label:SetShown(visible and not basic)
	if not basic then
		checkbox:ClearAllPoints()
		checkbox:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -offset)
		UI.PlaceCheckboxLabel(checkbox, card:GetWidth() - 42)
		offset = offset + math.max(24, checkbox.Label:GetStringHeight()) + 16
	end
	local preview = page.TextPreviewCard
	preview:SetShown(visible)
	preview:ClearAllPoints()
	preview:SetPoint("TOPLEFT", page.Content, "TOPLEFT", 0, -4)
	preview:SetPoint("RIGHT", page.Content, "RIGHT", -4, 0)
	for _, name in ipairs({ "TextPreviewLabel", "TextPreview", "TextOverlayPreview" }) do page[name]:SetShown(visible); page[name]:SetJustifyH("LEFT") end
	UI.PlaceText(page.TextPreviewLabel, preview, 14, 14, 100)
	local previewOffset = UI.PlaceText(page.TextPreview, preview, 130, 14, math.max(100, preview:GetWidth() - 148)) + 8
	previewOffset = UI.PlaceText(page.TextOverlayPreview, preview, 130, previewOffset, math.max(100, preview:GetWidth() - 148))
	preview:SetHeight(previewOffset + 16)
	if visible then
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -12)
		card:SetPoint("RIGHT", page.Content, "RIGHT", -4, 0)
	end
	return offset
end

function UI.LayoutCategories(page)
	if page.GroupButton then UI.StyleDropdown(page.GroupButton) end
	local width = math.max(240, math.min(340, math.floor(page:GetWidth() * 0.32), page:GetWidth() - 440))
	page.ListCard:ClearAllPoints()
	page.DetailPanel:ClearAllPoints()
	if page:GetWidth() < 720 then
		page.ListCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -74)
		page.ListCard:SetPoint("RIGHT", page, "RIGHT", -6, 0)
		page.ListCard:SetHeight(230)
		page.DetailPanel:SetPoint("TOPLEFT", page.ListCard, "BOTTOMLEFT", 0, -12)
	else
		page.ListCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -74)
		page.ListCard:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
		page.DetailPanel:SetPoint("TOPLEFT", page.ListCard, "TOPRIGHT", 14, 0)
	end
	page.DetailPanel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -6, 0)
	page.ListCard:SetWidth(width)
	for index, button in ipairs({ page.AddCategoryButton, page.AddGroupButton, page.TemplateButton }) do
		button:ClearAllPoints()
		button:SetPoint("BOTTOMLEFT", page.ListCard, "BOTTOMLEFT", 12, 12 + ((index - 1) * 32))
		button:SetPoint("RIGHT", page.ListCard, "RIGHT", -12, 0)
		button:SetHeight(24)
	end
	page.ListScrollFrame:ClearAllPoints()
	page.ListScrollFrame:SetPoint("TOPLEFT", page.ListHint, "BOTTOMLEFT", -2, -10)
	page.ListScrollFrame:SetPoint("BOTTOMRIGHT", page.ListCard, "BOTTOMRIGHT", -28, page.TemplateButton and 112 or 80)
end

function UI.GroupPanel(page,id,top,bottom)
 page.GeneralGroupPanels=page.GeneralGroupPanels or {}
 local panel=page.GeneralGroupPanels[id]
 if not panel then
  panel={fill=page.Content:CreateTexture(nil,"BACKGROUND",nil,1),edges={}}
  panel.fill:SetTexture("Interface\\Buttons\\WHITE8x8")
  for _,side in ipairs({"TOP","BOTTOM","LEFT","RIGHT"}) do
   local edge=page.Content:CreateTexture(nil,"BACKGROUND",nil,2);edge:SetTexture("Interface\\Buttons\\WHITE8x8")
   if side=="TOP" or side=="BOTTOM" then
    edge:SetPoint(side.."LEFT",panel.fill,side.."LEFT");edge:SetPoint(side.."RIGHT",panel.fill,side.."RIGHT");edge:SetHeight(1)
   else
    edge:SetPoint("TOP"..side,panel.fill,"TOP"..side,0,-1);edge:SetPoint("BOTTOM"..side,panel.fill,"BOTTOM"..side,0,1);edge:SetWidth(1)
   end
   panel.edges[#panel.edges+1]=edge
  end
  page.GeneralGroupPanels[id]=panel
 end
 panel.fill:ClearAllPoints();panel.fill:SetPoint("TOPLEFT",0,-top);panel.fill:SetPoint("RIGHT",-4,0);panel.fill:SetHeight(math.max(24,bottom-top))
 panel.fill:SetVertexColor(unpack(UI.Colors().cardBg));panel.fill:Show()
 for _,edge in ipairs(panel.edges) do edge:SetVertexColor(unpack(UI.Colors().cardBorder));edge:Show() end
end

function UI.ApplyLayout(page)
 for _,panel in pairs(page.GeneralGroupPanels or {}) do panel.fill:Hide();for _,edge in ipairs(panel.edges) do edge:Hide() end end
	UI.SyncSliders(page)
	local tab = page.LayoutTab
	local general, size, appearance, text = tab == "general", tab == "size", tab == "appearance", tab == "text"
	local basic = addon.GetActiveCategoryMode and addon.GetActiveCategoryMode() == "basic"
	local oneBag = addon.GetOneBagMode and addon.GetOneBagMode()
	local width = math.max(60, (page:GetWidth() - 24) / 5)
	for index, button in ipairs(page.LayoutTabs) do
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", page, "TOPLEFT", (index - 1) * (width + 6), -48)
		button:SetWidth(width)
		button.selected=tab==button.tabID;UI.PaintButton(button)
	end
	local offset = 8
	local activeGroup,groupTop
	local function closeGroup(bottom) if activeGroup then UI.GroupPanel(page,activeGroup,groupTop,bottom) end end
	page.GeneralHeadings = page.GeneralHeadings or {}
	for _, id in ipairs({ "contents", "categories", "bank", "window" }) do
		if not page.GeneralHeadings[id] then page.GeneralHeadings[id] = page.Content:CreateFontString(nil, "OVERLAY", "GameFontNormal") end
		page.GeneralHeadings[id]:Hide()
	end
	local function heading(id, label)
		if not general then return end
		closeGroup(offset-12)
		activeGroup,groupTop=id,math.max(0,offset-4)
		offset=offset+4
		local text = page.GeneralHeadings[id]
		if not text then text = page.Content:CreateFontString(nil, "OVERLAY", "GameFontNormal"); page.GeneralHeadings[id] = text end
		text:SetText(label)
		text:SetTextColor(unpack(UI.Colors().accent))
		text:ClearAllPoints()
		text:SetPoint("TOPLEFT", page.Content, "TOPLEFT", 14, -offset)
		text:Show()
		offset = offset + text:GetStringHeight() + 12
	end
	heading("contents", L["settingsBagsContentsTitle"])
	local function placeCheckbox(name)
		local button = page[name]
		if button then
			local visible = general and button:IsShown()
			button:SetShown(visible)
			button.Label:SetShown(visible)
			if visible then
				button:SetSize(UI.IsToolbar(button) and 24 or 34, 24)
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", page.Content, "TOPLEFT", 10, -offset)
				button.Label:SetTextColor(unpack(UI.Colors().textMain))
				UI.PlaceCheckboxLabel(button, page.Content:GetWidth() - 40)
				offset = offset + math.max(32, button.Label:GetStringHeight() + 8)
			end
		end
	end
	for _, name in ipairs({ "OneBagMode", "OneBagFreeSlotsAtEnd", "CombineFreeSlots", "CombineDuplicateItems", "ClearNewItemsOnHeaderClick" }) do placeCheckbox(name) end
	if oneBag then placeCheckbox("ShowFreeSlots") else page.ShowFreeSlots:Hide(); page.ShowFreeSlots.Label:Hide() end
	page.ShowNewItems:Hide(); page.ShowNewItems.Label:Hide()
	if not oneBag then offset = offset + 12; heading("categories", L["settingsCategoriesLabel"]) end
	for _, name in ipairs({ "ShowCategories", "CompactCategoryLayout", "CategoryTreeView" }) do placeCheckbox(name) end
	if page.GlobalSortButton then
		page.GlobalSortLabel:SetShown(general)
		page.GlobalSortButton:SetShown(general)
		page.GlobalSortHint:SetShown(general)
		UI.SetWidgetEnabled(page.GlobalSortButton, not oneBag and addon.GetSettings().showCategories == true)
		local mode = addon.GetGlobalCategorySortMode()
		for _, option in ipairs(addon.GetCategorySortModeOptions(true)) do
			if option.value == mode then page.GlobalSortButton:SetText(option.label); break end
		end
		if general then
			offset = UI.PlaceText(page.GlobalSortLabel, page.Content, 14, offset + 8, page.Content:GetWidth() - 28) + 8
			page.GlobalSortButton:ClearAllPoints()
			page.GlobalSortButton:SetPoint("TOPLEFT", page.Content, "TOPLEFT", 14, -offset)
			page.GlobalSortButton:SetSize(math.min(300, math.max(100, page.Content:GetWidth() - 28)), 26)
			offset = UI.PlaceText(page.GlobalSortHint, page.Content, 14, offset + 34, page.Content:GetWidth() - 28) + 16
		end
	end
	if page.AutoEquipmentSets then
		local button = page.AutoEquipmentSets
		button:SetShown(general and not oneBag)
		button.Label:SetShown(general and not oneBag)
		button.Hint:SetShown(general and not oneBag)
		button:SetChecked(addon.GetSettings().autoEquipmentSetCategories == true)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", page.Content, "TOPLEFT", 10, -offset)
		UI.PlaceCheckboxLabel(button, page.Content:GetWidth() - 40)
		if not oneBag then offset = offset + 36 + button.Hint:GetStringHeight() end
	end
	placeCheckbox("CompactCategoryWrap")
	for _, name in ipairs({ "CompactCategoryGapControl", "CategoryTreeIndentControl" }) do
		local control = page[name]
		if control and control.Row then
			control.Row:SetShown(general and not oneBag)
			control.Row:ClearAllPoints()
			control.Row:SetPoint("TOPLEFT", page.Content, "TOPLEFT", 38, -offset)
			control.Row:SetPoint("RIGHT", page.Content, "RIGHT", -14, 0)
			if not oneBag then offset = offset + 32 end
		end
	end
	if general then offset = offset + 16 end
	heading("bank", _G.BANK)
	placeCheckbox("UseIntegratedBank")
	placeCheckbox("RememberLastBankTab")
	if general then offset = offset + 16 end
	heading("window", L["settingsBagsWindowTitle"])
	if page.SortModeButtonToggle then page.SortModeButtonToggle:Hide();page.SortModeButtonToggle.Label:Hide() end
	if page.ShowCloseButton then page.ShowCloseButton:Hide();page.ShowCloseButton.Label:Hide() end
	placeCheckbox("CategoryQuickAdd")
	placeCheckbox("DragBackground")
	if page.ItemInfoTooltip then
		page.ItemInfoTooltip:SetShown(general)
		page.ItemInfoTooltip:SetChecked(addon.GetSettings().itemInfoTooltip == true)
		placeCheckbox("ItemInfoTooltip")
	end
	closeGroup(offset+8)
	page.ResetButton:SetShown(general)
	page.ResetButton:ClearAllPoints()
	page.ResetButton:SetPoint("TOPLEFT", page.Content, "TOPLEFT", 14, -offset - 24)
	UI.FlatButton(page.ResetButton)
	page.PaddingCard:SetShown(size)
	page.PaddingCard:ClearAllPoints()
	page.PaddingCard:SetPoint("TOPLEFT", page.Content, "TOPLEFT", 0, -4)
	page.PaddingCard:SetPoint("RIGHT", page.Content, "RIGHT", -4, 0)
	page.TextAppearanceCard:SetShown(appearance or text)
	page.TextAppearanceCard:ClearAllPoints()
	page.TextAppearanceCard:SetPoint("TOPLEFT", page.Content, "TOPLEFT", 0, -4)
	page.TextAppearanceCard:SetPoint("RIGHT", page.Content, "RIGHT", -4, 0)
	page.TextAppearanceTitle:SetText(text and L["settingsTextAppearanceTitle"] or L["settingsBasicLookTitle"])
	page.TextAppearanceHint:SetShown(text)
	UI.LayoutPadding(page, basic)
	local rowOffset = UI.LayoutPairs(page, UI.appearance, appearance, 46)
	if page.HeaderControls then
		addon.Bags.Header.RefreshControls(page)
		rowOffset=UI.LayoutPairs(page,addon.Bags.Header.rows,appearance,rowOffset+12)
	end
	local textOffset = UI.LayoutPairs(page, UI.typography, text, math.max(72, 48 + page.TextAppearanceHint:GetStringHeight()))
	local textBottom = UI.LayoutText(page, textOffset, text, basic)
	page.TextAppearanceCard:SetHeight(appearance and rowOffset + 12 or textBottom + 16)
	page.LayoutContentHeight = general and offset + 80 or size and page.PaddingCard:GetHeight() + 16 or page.TextAppearanceCard:GetHeight() + 16
	if page.ToolbarCard then
		page.ToolbarCard:SetShown(tab == "toolbar")
		if tab == "toolbar" then
			page.ToolbarEditor:Refresh()
			page.LayoutContentHeight = page.ToolbarCard:GetHeight() + 16
		end
	end
	if text then page.LayoutContentHeight = page.LayoutContentHeight + page.TextPreviewCard:GetHeight() + 12 end
end


-- Apply after dragging so the slider does not move beneath the cursor.
function UI.CreateWindowScale(frame, db)
	local scale = tonumber(db.scale) or 1
	if scale ~= scale then scale = 1 end
	scale = math.max(0.6, math.min(1.2, scale))
	frame:SetScale(scale)
	local slider = CreateFrame("Slider", nil, frame)
	slider:SetFrameLevel(frame:GetFrameLevel()+4)
	slider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 22, 22)
	slider:SetSize(130, 16); slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(60, 120); slider:SetValueStep(1); slider:SetObeyStepOnDrag(true)
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT",5,0);track:SetPoint("RIGHT",-5,0);track:SetHeight(4);track:SetColorTexture(unpack(UI.Colors().textSubtle))
 local fill=slider:CreateTexture(nil,"BACKGROUND",nil,1);fill:SetPoint("LEFT",track,"LEFT");fill:SetHeight(4);fill:SetColorTexture(unpack(UI.Colors().accent))
 slider.Track,slider.Progress=track,fill
 local function updateProgress(value)
  local progress=math.max(0,math.min(1,(value-60)/60))
  fill:SetWidth(math.max(1,(slider:GetWidth()-10)*progress));fill:SetShown(progress>0)
 end
	slider:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
	local thumb = slider:GetThumbTexture(); thumb:SetSize(10, 18); thumb:SetVertexColor(unpack(UI.Colors().accent))
	local caption = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	caption:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 6)
	local function apply(value)
		db.scale = math.max(60, math.min(120, math.floor(value + 0.5))) / 100
		frame:SetScale(db.scale)
	end
	slider:SetScript("OnValueChanged", function(_, value)
		caption:SetText(string.format("%s: %d%%", L["Scale"], math.floor(value + 0.5)))
		updateProgress(value)
	end)
	slider:SetScript("OnMouseDown", function() slider.dragging = true end)
	slider:SetScript("OnMouseUp", function() slider.dragging = nil; apply(slider:GetValue()) end)
	slider:SetScript("OnHide", function() if slider.dragging then slider.dragging = nil; apply(slider:GetValue()) end end)
	slider:SetScript("OnSizeChanged",function() updateProgress(slider:GetValue()) end)
	slider:SetValue(scale * 100)
	frame.ScaleSlider = slider
end

return UI
