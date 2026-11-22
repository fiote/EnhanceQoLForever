local addon = _G.EnhanceQoL
local T = { buttons = setmetatable({}, { __mode = "k" }), defaultColor = { 0.92, 0.73, 0.37, 1 }, frames = setmetatable({}, { __mode = "k" }), editors = setmetatable({}, { __mode = "k" }), settingsPages = setmetatable({}, { __mode = "k" }) }
addon.Bags.Toolbar = T

local function component(value, fallback)
 value = tonumber(value)
 if not value or value ~= value then return fallback end
 return math.max(0, math.min(1, value))
end
function T.GetSpacing()
 local value=tonumber(addon.GetSettings().toolbarSpacing)
 if not value or value~=value then return 4 end
 return math.floor(math.max(0,math.min(20,value))+.5)
end
function T.RequestLayouts()
 for _,name in ipairs({"RequestLayoutUpdate","RequestBankLayoutUpdate"}) do
  local request=addon.Bags.functions and addon.Bags.functions[name]
  if request then request(false,true) end
 end
end
function T.SetSpacing(value)
 local settings=addon.GetSettings()
 settings.toolbarSpacing=value
 settings.toolbarSpacing=T.GetSpacing()
 for frame in pairs(T.frames) do T.Layout(frame) end
 T.RefreshAll();T.RequestLayouts()
end
function T.GetWidth(frame)
 local count=0
 for _,kind in ipairs(T.GetOrder()) do
  local button=frame and frame[T.byKind[kind]]
  if (frame and button and button:IsShown()) or (not frame and T.IsVisible(kind)) then count=count+1 end
 end
 return count*24+math.max(0,count-1)*T.GetSpacing()
end
function T.GetCustomColor()
 local color = addon.GetSettings().toolbarIconColor or T.defaultColor
 return { component(color[1], 0.92), component(color[2], 0.73), component(color[3], 0.37), 1 }
end
function T.GetUseCustomColor() return addon.GetSettings().toolbarCustomColor == true end
function T.GetColor()
 if T.GetUseCustomColor() then return unpack(T.GetCustomColor()) end
 local skin = addon.GetActiveSkinDefinition().frame
 return unpack(skin.toolbarColor or skin.titleColor or T.defaultColor)
end
function T.SetUseCustomColor(value)
 addon.GetSettings().toolbarCustomColor = value == true
 T.RefreshAll()
end
function T.SetColor(r, g, b)
 addon.GetSettings().toolbarIconColor = { component(r,0.92), component(g,0.73), component(b,0.37), 1 }
 T.RefreshAll()
end
local function line(parent,x1,y1,x2,y2,color,thickness)
 local length=math.sqrt((x2-x1)^2+(y2-y1)^2)
 local half=(thickness or 1.5)/2
 local extraX=length>0 and math.abs(y2-y1)/length*half or half
 local extraY=length>0 and math.abs(x2-x1)/length*half or half
 parent.minX=math.min(parent.minX or math.huge,x1-extraX,x2-extraX)
 parent.maxX=math.max(parent.maxX or -math.huge,x1+extraX,x2+extraX)
 parent.minY=math.min(parent.minY or math.huge,y1-extraY,y2-extraY)
 parent.maxY=math.max(parent.maxY or -math.huge,y1+extraY,y2+extraY)
 local t=addon.PixelUtil.ApplyTexturePixelSnapping(parent:CreateTexture(nil,'ARTWORK'))
 t:SetTexture('Interface\\Buttons\\WHITE8x8');t:SetVertexColor(unpack(color));parent.parts[#parent.parts+1]=t;t:SetSize(math.sqrt((x2-x1)^2+(y2-y1)^2),thickness or 1.5)
 t:SetPoint('CENTER',parent,'BOTTOMLEFT',(x1+x2)/2,(y1+y2)/2)
 t:SetRotation(math.atan2(y2-y1,x2-x1));return t
end
local function path(parent,points,color,weight,close)
 for i=2,#points do line(parent,points[i-1][1],points[i-1][2],points[i][1],points[i][2],color,weight) end
 if close then line(parent,points[#points][1],points[#points][2],points[1][1],points[1][2],color,weight) end
end
local function box(parent,x,y,w,h,color,weight)
 path(parent,{{x,y},{x+w,y},{x+w,y+h},{x,y+h}},color,weight,true)
end
local function glyph(parent,kind,color,weight,alternate)
 if kind=='bank' then
  if alternate then
   path(parent,{{1,14},{10,19},{19,14}},color,weight)
   line(parent,2,12,18,12,color,weight);line(parent,1,2,19,2,color,weight)
   for _,x in ipairs({4,10,16}) do line(parent,x,4,x,11,color,weight) end
  else
   box(parent,2,3,16,14,color,weight);line(parent,2,11,18,11,color,weight)
   box(parent,8,8,4,5,color,weight)
  end
 elseif kind=='lists' then
  box(parent,3,2,14,16,color,weight)
  for _,y in ipairs({6,10,14}) do
   if alternate then path(parent,{{5,y},{6,y-1},{8,y+1}},color,weight) else line(parent,5,y,6,y,color,weight) end
   line(parent,10,y,15,y,color,weight)
  end
 elseif kind=='bags' then
  path(parent,{{2,3},{18,3},{17,15},{14,17},{6,17},{3,15}},color,weight,true)
  path(parent,{{7,17},{7,19},{13,19},{13,17}},color,weight)
  if alternate then box(parent,6,6,8,5,color,weight) else line(parent,5,12,15,12,color,weight) end
 elseif kind=='mode' then
  line(parent,5,2,5,18,color,weight);path(parent,{{1,14},{5,18},{9,14}},color,weight)
  line(parent,15,18,15,2,color,weight);path(parent,{{11,6},{15,2},{19,6}},color,weight)
 elseif kind=='sort' then
  local function point(x,y) return {9+.975*x+.22*y,8-.22*x+.975*y} end
  path(parent,{point(-1.7,0),point(1.7,0),point(4.4,-5.5),point(-4.4,-5.5)},color,weight,true)
  for _,segment in ipairs({{0,.8,0,11.5},{-2,-1,2,-1},{-2.4,-5,-.8,-2},{0,-5,0,-2},{2.4,-5,.8,-2}}) do
   local from,to=point(segment[1],segment[2]),point(segment[3],segment[4])
   line(parent,from[1],from[2],to[1],to[2],color,weight)
  end
 elseif kind=='settings' then
  local points={}
  for i=0,15 do
   local theta=math.rad(i*22.5)
   points[#points+1]={10+6.5*math.cos(theta),10+6.5*math.sin(theta)}
  end
  path(parent,points,color,weight,true)
  local inner={}
  for i=0,11 do local theta=math.rad(i*30);inner[#inner+1]={10+2.5*math.cos(theta),10+2.5*math.sin(theta)} end
  path(parent,inner,color,weight,true)
  for i=0,7 do local theta=math.rad(i*45);line(parent,10+6.5*math.cos(theta),10+6.5*math.sin(theta),10+9*math.cos(theta),10+9*math.sin(theta),color,weight+0.4) end
 elseif kind=='close' then
  line(parent,3,3,17,17,color,weight);line(parent,3,17,17,3,color,weight)
 end
end

function T.PositionIcon(button)
 local icon=button.ToolbarIcon
 if not icon then return end
 local x,y=icon.offsetX or 0,icon.offsetY or 0
 if button._toolbarPressed then x,y=x+1,y-1 end
 icon:ClearAllPoints()
 if math.abs(x)<.0001 and math.abs(y)<.0001 then icon:SetPoint("CENTER")
 else icon:SetPoint("CENTER",x,y) end
end
function T.AlignBorder(button)
 if not button.ToolbarBorder then return end
 local pixel=addon.PixelUtil
 local thickness=math.max(pixel.OnePixel(button),pixel.Snap(1,button))
 if button._toolbarBorderThickness==thickness then return end
 button._toolbarBorderThickness=thickness
 for index,edge in ipairs(button.ToolbarBorder) do
  edge:ClearAllPoints()
  if index==1 or index==2 then
   local side=index==1 and "TOP" or "BOTTOM"
   edge:SetPoint(side.."LEFT",button,side.."LEFT")
   edge:SetPoint(side.."RIGHT",button,side.."RIGHT")
   edge:SetHeight(thickness)
  else
   local side=index==3 and "LEFT" or "RIGHT"
   edge:SetPoint("TOP"..side,button,"TOP"..side,0,-thickness)
   edge:SetPoint("BOTTOM"..side,button,"BOTTOM"..side,0,thickness)
   edge:SetWidth(thickness)
  end
 end
end
function T.Update(button, r, g, b)
 local icon = button.ToolbarIcon
 if not icon then return end
 if not r then r,g,b = T.GetColor() end
 local enabled = not button.IsEnabled or button:IsEnabled()
 local active = addon.Bags.SortMode and addon.Bags.SortMode.button == button and addon.Bags.SortMode.active
 local alpha = enabled and ((button._toolbarHovered or active) and 1 or 0.88) or 0.3
 if button._toolbarHovered and enabled then
  if button._toolbarKind == "close" then r,g,b=1,0.22,0.16 else r,g,b=math.min(1,r*1.12),math.min(1,g*1.12),math.min(1,b*1.12) end
 end
 if button._toolbarPaintR==r and button._toolbarPaintG==g and button._toolbarPaintB==b and button._toolbarPaintA==alpha and button._toolbarPaintActive==active and button._toolbarPaintHover==button._toolbarHovered and button._toolbarPaintPressed==button._toolbarPressed then return end
 button._toolbarPaintR,button._toolbarPaintG,button._toolbarPaintB,button._toolbarPaintA=r,g,b,alpha
 button._toolbarPaintActive,button._toolbarPaintHover,button._toolbarPaintPressed=active,button._toolbarHovered,button._toolbarPressed
 for _, part in ipairs(icon.parts) do part:SetVertexColor(r,g,b,alpha) end
 if button.ToolbarBorder then
  for _, edge in ipairs(button.ToolbarBorder) do edge:SetVertexColor(r,g,b,enabled and (button._toolbarHovered and 0.98 or 0.62) or 0.25) end
 end
 button.ToolbarBackground:SetVertexColor(r,g,b,enabled and (button._toolbarPressed and 0.173 or button._toolbarHovered and 0.36 or active and 0.24 or 0) or 0)
end
function T.RefreshAll()
 local r,g,b=T.GetColor()
 for button in pairs(T.buttons) do T.AlignBorder(button);T.Update(button,r,g,b) end
 for editor in pairs(T.editors) do if editor:IsShown() then editor:Refresh() end end
 for page in pairs(T.settingsPages) do T.RefreshSettingsControl(page) end
end
function T.Style(button, kind)
 if not button then return end
 button:SetSize(24,24)
 if button.SetHitRectInsets then button:SetHitRectInsets(0,0,0,0) end
 if button.Icon then button.Icon:SetAlpha(0) end
 for _, key in ipairs({"Normal","Highlight","Pushed","Disabled"}) do
  local getter=button["Get"..key.."Texture"]
  local texture=getter and getter(button)
  if texture then texture:SetAlpha(0) end
 end
 if button.HighlightTexture then button.HighlightTexture:SetAlpha(0) end
 if button.ToolbarIcon then T.AlignBorder(button);return end
 button._toolbarKind=kind
 local icon=CreateFrame("Frame",nil,button)
 icon:SetSize(20,20);icon:SetPoint("CENTER");icon.parts={}
 glyph(icon,kind,{1,1,1,1},1.45,kind=="bank")
 icon.offsetX=10-(icon.minX+icon.maxX)/2
 icon.offsetY=10-(icon.minY+icon.maxY)/2
 button.ToolbarIcon=icon
 T.PositionIcon(button)
 local backing=button:CreateTexture(nil,"BACKGROUND",nil,-1)
 backing:SetTexture("Interface\\Buttons\\WHITE8x8");backing:SetAllPoints();backing:SetVertexColor(0.028,0.023,0.018,0.88)
 button.ToolbarBacking=backing
 local background=button:CreateTexture(nil,"BACKGROUND")
 background:SetTexture("Interface\\Buttons\\WHITE8x8");background:SetAllPoints()
 button.ToolbarBackground=background
 do
  button.ToolbarBorder={}
  for index=1,4 do
   local edge=addon.PixelUtil.ApplyTexturePixelSnapping(button:CreateTexture(nil,"BORDER"))
   edge:SetTexture("Interface\\Buttons\\WHITE8x8")
   if edge.SetRoundLayoutToNearestPixel then edge:SetRoundLayoutToNearestPixel(true) end
   button.ToolbarBorder[index]=edge
  end
  T.AlignBorder(button)
 end
 button:HookScript("OnEnter",function(self) self._toolbarHovered=true;T.Update(self) end)
 button:HookScript("OnLeave",function(self) self._toolbarHovered=nil;self._toolbarPressed=nil;T.PositionIcon(self);T.Update(self) end)
 button:HookScript("OnMouseDown",function(self,mouse) if mouse=="LeftButton" then self._toolbarPressed=true;T.PositionIcon(self);T.Update(self) end end)
 local function release(self)
  self._toolbarPressed=nil;T.PositionIcon(self);T.Update(self)
 end
 button:HookScript("OnMouseUp",release)
 button:HookScript("OnShow",T.AlignBorder)
 button:HookScript("OnSizeChanged",T.AlignBorder)
 button:HookScript("OnHide",function(self) self._toolbarHovered=nil;release(self) end)
 if button.SetEnabled then hooksecurefunc(button,"SetEnabled",function() T.Update(button) end) end
 T.buttons[button]=true
 T.Update(button)
end
T.fields={ {"CloseButton","close"},{"SettingsButton","settings"},{"SortButton","sort"},{"SortModeButton","mode"},{"BagSlotsButton","bags"},{"VendorListsButton","lists"},{"OfflineBankButton","bank"} }
T.defaultOrder={"bank","lists","bags","mode","sort","settings","close"}
T.byKind={}
for _,spec in ipairs(T.fields) do T.byKind[spec[2]]=spec[1] end
function T.GetOrder()
 local result,seen={},{}
 local stored=addon.GetSettings().toolbarOrder
 for _,kind in ipairs(type(stored)=="table" and stored or {}) do
  if T.byKind[kind] and not seen[kind] then result[#result+1]=kind;seen[kind]=true end
 end
 for _,kind in ipairs(T.defaultOrder) do if not seen[kind] then result[#result+1]=kind end end
 return result
end
function T.IsVisible(kind)
 if kind=="settings" then return true end
 local settings=addon.GetSettings()
 if kind=="close" then return settings.showCloseButton~=false end
 if kind=="mode" then return settings.sortModeButton==true end
 return type(settings.toolbarHidden)~="table" or settings.toolbarHidden[kind]~=true
end
-- The configured width is available before child buttons become visible.
function T.GetConfiguredWidth()
 local count=0
 for _,kind in ipairs(T.defaultOrder) do if T.IsVisible(kind) then count=count+1 end end
 return count*24+math.max(0,count-1)*T.GetSpacing()
end
function T.GetLayout()
 local value={order=T.GetOrder(),visible={}}
 for _,kind in ipairs(T.defaultOrder) do value.visible[kind]=T.IsVisible(kind) end
 return value
end
function T.GetDefaultLayout()
 local value={order={},visible={}}
 for i,kind in ipairs(T.defaultOrder) do value.order[i]=kind;value.visible[kind]=kind~="mode" end
 return value
end
function T.SetLayout(value)
 if type(value)~="table" then return end
 local settings=addon.GetSettings()
 settings.toolbarOrder=type(value.order)=="table" and value.order or {}
 settings.toolbarOrder=T.GetOrder()
 local visible=type(value.visible)=="table" and value.visible or {}
 settings.toolbarHidden={}
 for _,kind in ipairs(T.defaultOrder) do
  if kind=="close" then settings.showCloseButton=visible[kind]~=false
  elseif kind=="mode" then settings.sortModeButton=visible[kind]==true
  elseif kind~="settings" and visible[kind]==false then settings.toolbarHidden[kind]=true end
 end
 T.ApplyAll()
end
function T.SetVisible(kind,visible)
 if not T.byKind[kind] then return end
 local value=T.GetLayout();value.visible[kind]=visible==true;T.SetLayout(value)
end
function T.Move(fromIndex,toIndex)
 local value=T.GetLayout()
 if not value.order[fromIndex] or not value.order[toIndex] or fromIndex==toIndex then return end
 table.insert(value.order,toIndex,table.remove(value.order,fromIndex));T.SetLayout(value)
end
function T.ApplyButton(button)
 local kind=button._toolbarKind
 local available=button._toolbarAvailable~=false
 if kind=="close" or kind=="settings" then available=true end
 if kind=="mode" then
  local settings=addon.GetSettings()
  available=settings.showCategories==true and not (addon.GetOneBagMode and addon.GetOneBagMode())
 end
 button._toolbarApplying=true
 button:SetShown(available and T.IsVisible(kind))
 button._toolbarApplying=nil
end
function T.Layout(frame)
 if frame._toolbarLayout then return end
 frame._toolbarLayout=true
 local previous,leftmost
 local order=T.GetOrder()
 for i=#order,1,-1 do
  local button=frame[T.byKind[order[i]]]
  if button and button:IsShown() then
   button:ClearAllPoints()
   if previous then button:SetPoint("RIGHT",previous,"LEFT",-T.GetSpacing(),0)
   else button:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-(frame._toolbarPadding or 10),-6) end
   previous,leftmost=button,button
  end
 end
 if frame.SearchBox and frame.Title then
  frame.SearchBox:ClearAllPoints()
  frame.SearchBox:SetPoint("TOPLEFT",frame.Title,"TOPRIGHT",18,2)
  if leftmost then frame.SearchBox:SetPoint("TOPRIGHT",leftmost,"TOPLEFT",-10,-2)
  else frame.SearchBox:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-(frame._toolbarPadding or 10),-8) end
 end
 if addon.Bags.Header then addon.Bags.Header.Apply(frame,leftmost) end
 frame._toolbarLayout=nil
end
function T.Attach(frame,padding)
 if not frame then return end
 frame._toolbarPadding=padding or (addon.GetInsideHorizontalPadding and addon.GetInsideHorizontalPadding()) or 10
 T.frames[frame]=true
 for _,spec in ipairs(T.fields) do
  local button=frame[spec[1]]
  if button then
   T.Style(button,spec[2])
   if not button._toolbarBound then
    button._toolbarBound=true;button._toolbarAvailable=button:IsShown()
    local function changed(self)
     if self._toolbarApplying then return end
     self._toolbarAvailable=self:IsShown();T.ApplyButton(self);T.Layout(frame)
    end
    for _,method in ipairs({"Show","Hide","SetShown"}) do hooksecurefunc(button,method,changed) end
   end
   T.ApplyButton(button)
  end
 end
 T.Layout(frame);T.RefreshAll()
end
function T.ApplyAll()
 local mode=addon.Bags.SortMode
 if mode and mode.Refresh and mode.frame then mode.Refresh(mode.frame) end
 for frame in pairs(T.frames) do
  for _,spec in ipairs(T.fields) do
   local button=frame[spec[1]]
   if button then T.ApplyButton(button) end
  end
  if not T.IsVisible("bags") and frame.BagSlotsPanel then frame.BagSlotsPanel:Hide() end
  T.Layout(frame)
 end
 T.RefreshAll();T.RequestLayouts()
end
function T.Reset()
 local settings=addon.GetSettings()
 settings.toolbarSpacing=4
 settings.toolbarCustomColor=false
 settings.toolbarIconColor={unpack(T.defaultColor)}
 T.SetLayout(T.GetDefaultLayout())
end
function T.CreateSettingsControl(page,openPicker,refresh)
 local parent
 local card=CreateFrame("Frame",nil,page.Content,"BackdropTemplate")
 card._bagsToolbarCard=true
 card:SetPoint("TOPLEFT",0,-4);card:SetPoint("RIGHT",-4,0);card:SetHeight(512)
 card:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
 card:SetBackdropColor(.035,.045,.065,1);card:SetBackdropBorderColor(.15,.2,.28,1)
 page.ToolbarCard=card
 local title=card:CreateFontString(nil,"OVERLAY","GameFontHighlight")
 title:SetPoint("TOPLEFT",14,-14);title:SetText(addon.L["settingsToolbarTitle"])
 local editor=T.CreateEditor(card);editor:SetPoint("TOPLEFT",6,-34);editor:SetPoint("RIGHT",-6,0)
 page.ToolbarEditor=editor
 parent=card
 local label=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 label:SetText(addon.L["settingsToolbarCustomColor"])
 local control=CreateFrame("Frame",nil,parent);control:SetHeight(24)
 local toggle=addon.Bags.SettingsNavigation.CreateCheckbox("CheckButton",nil,control);toggle:SetPoint("LEFT")
 local swatch=CreateFrame("Button",nil,control,"ColorSwatchTemplate");swatch:SetSize(22,22);swatch:SetPoint("LEFT",label,"RIGHT",10,0)
 toggle:SetScript("OnClick",function(self) T.SetUseCustomColor(self:GetChecked());T.RefreshSettingsControl(page);refresh() end)
 swatch:SetScript("OnClick",function()
  if not T.GetUseCustomColor() then return end
  openPicker(T.GetCustomColor(),function(r,g,b) T.SetColor(r,g,b);T.RefreshSettingsControl(page) end)
 end)
 for _,widget in ipairs({toggle,swatch}) do
  widget:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(addon.L["settingsToolbarCustomColor"]);GameTooltip:AddLine(addon.L["settingsToolbarCustomColorDesc"],1,1,1,true);GameTooltip:Show() end)
  widget:SetScript("OnLeave",function() GameTooltip:Hide() end)
 end
 page.ToolbarColorLabel,page.ToolbarColorControl=label,control
 T.settingsPages[page]=true
 control.Toggle,control.Swatch=toggle,swatch
 label:SetPoint("LEFT",toggle,"RIGHT",6,0);label:SetJustifyH("LEFT")
 control:SetPoint("TOPLEFT",14,-422);control:SetPoint("RIGHT",-14,0)
 local divider=card:CreateTexture(nil,"BORDER")
 divider:SetPoint("TOPLEFT",14,-462);divider:SetPoint("RIGHT",-14,0);divider:SetHeight(1)
 divider:SetColorTexture(.15,.2,.28,.6)
 local reset=addon.Bags.SettingsNavigation.CreateButton("Button",nil,card)
 reset:SetText(RESET_TO_DEFAULT)
 reset:SetSize(math.max(120,reset:GetFontString():GetStringWidth()+18),22)
 reset:SetPoint("TOPRIGHT",-14,-476)
 reset:GetNormalTexture():SetVertexColor(.07,.09,.12,.7)
 reset:GetFontString():SetTextColor(.68,.71,.76)
 reset:SetScript("OnClick",T.Reset)
 page.ToolbarEditor.Reset=reset
 T.RefreshSettingsControl(page)
end
function T.RefreshSettingsControl(page)
 local control=page.ToolbarColorControl
 if not control then return end
 local custom=T.GetUseCustomColor()
 control.Toggle:SetChecked(custom)
 control.Swatch:SetEnabled(custom);control.Swatch:SetAlpha(custom and 1 or 0.4)
 local color=T.GetCustomColor();control.Swatch:SetColorRGB(color[1],color[2],color[3])
end

function T.GetColorValue()
 local color=T.GetCustomColor()
 return {r=color[1],g=color[2],b=color[3],a=1}
end
function T.RegisterColor(app,pageID)
 app:RegisterControl(pageID,{
  id="toolbarIconColor",type="colorpicker",groupID="toolbar",order=30,
  label=addon.L["settingsToolbarColor"],description=addon.L["settingsToolbarCustomColorDesc"],
  newTagID="Bags_toolbarIconColor",default={r=0.92,g=0.73,b=0.37,a=1},hasOpacity=false,
  getValue=T.GetColorValue,setValue=function(value) T.SetColor(value.r,value.g,value.b) end,
  getColor=function() return unpack(T.GetCustomColor()) end,
  setColor=function(_,r,g,b) T.SetColor(r,g,b) end,isEnabled=T.GetUseCustomColor,
 })
end

T.pixelEvents=CreateFrame("Frame")
T.pixelEvents:RegisterEvent("UI_SCALE_CHANGED")
T.pixelEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
T.pixelEvents:SetScript("OnEvent",T.RefreshAll)
