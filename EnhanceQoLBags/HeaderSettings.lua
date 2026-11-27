local addon=_G.EnhanceQoL
local H=addon.Bags.Header
local L=addon.L
H.rows = {
 {"HeaderTitleLabel","HeaderTitleButton","settingsBagTitleMode"},
 {"SearchBorderLabel","SearchBorderButton","settingsBagSearchBorder"},
 {"SearchBorderColorLabel","SearchBorderColorSwatch","settingsBagSearchBorderColor"},
 {"SearchBorderOpacityLabel","SearchBorderOpacityControl","settingsBagSearchBorderOpacity"},
 {"SearchColorLabel","SearchColorSwatch","settingsBagSearchColor"},
 {"SearchOpacityLabel","SearchOpacityControl","settingsBagSearchOpacity"},
}
local function borderEnabled() return H.Get("searchBorderTexture") ~= "__none__" end
local colorControls = {{"SearchColorSwatch","searchBackgroundColor"},{"SearchBorderColorSwatch","searchBorderColor"}}
local opacityControls = {{"SearchOpacityControl","searchBackgroundOpacity"},{"SearchBorderOpacityControl","searchBorderOpacity"}}
function H.CreateControls(page,menu,picker)
 local UI=addon.Bags.SettingsNavigation
 for _,row in ipairs(H.rows) do
  local label=page.TextAppearanceCard:CreateFontString(nil,"OVERLAY","GameFontHighlight");label:SetText(L[row[3]]);label:SetJustifyH("LEFT");page[row[1]]=label
 end
 for _,spec in ipairs({{"HeaderTitleButton","headerTitleMode",H.TitleOptions},{"SearchBorderButton","searchBorderTexture",H.BorderOptions}}) do
  local button=UI.CreateButton("Button",nil,page.TextAppearanceCard)
  button:SetScript("OnClick",function(self) menu(self,spec[3](),H.Get(spec[2]),function(value) H.Set(spec[2],value) end) end)
  page[spec[1]]=button
 end
 for _,spec in ipairs(colorControls) do
  local field,key=spec[1],spec[2]
  local swatch=CreateFrame("Button",nil,page.TextAppearanceCard,"ColorSwatchTemplate")
  swatch:SetSize(22,22)
  if key=="searchBorderColor" then
   swatch:RegisterForClicks("LeftButtonUp","RightButtonUp")
   swatch:HookScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    GameTooltip:SetText(L["settingsBagSearchBorderColor"])
    GameTooltip:AddLine(L["settingsFrameBorderColorTooltip"],.78,.78,.78,true)
    GameTooltip:Show()
   end)
   swatch:HookScript("OnLeave",function() GameTooltip:Hide() end)
  end
  swatch:SetScript("OnClick",function(_,button)
   if key=="searchBorderColor" then
    if not borderEnabled() then return end
    if button=="RightButton" then H.Set(key,nil);return end
   end
   picker(H.Get(key),function(r,g,b) H.Set(key,{r,g,b}) end)
  end)
  page[field]=swatch
 end
 for _,spec in ipairs(opacityControls) do
  local field,key=spec[1],spec[2]
  local parent=CreateFrame("Frame",nil,page.TextAppearanceCard)
  parent:SetSize(260,26)
  parent.Numeric=UI.CreateNumeric(parent,{min=0,max=100,step=1,suffix="%",get=function() return H.Get(key) end,
   set=function(value) H.Set(key,value) end,enabled=key=="searchBorderOpacity" and borderEnabled or nil})
  page[field]=parent
 end
 page.HeaderControls=true
end
function H.RefreshControls(page)
 for _,spec in ipairs({{"HeaderTitleButton","headerTitleMode",H.TitleOptions},{"SearchBorderButton","searchBorderTexture",H.BorderOptions}}) do
  local value=H.Get(spec[2]);local label=value
  for _,option in ipairs(spec[3]()) do if option.value==value then label=option.label;break end end
  page[spec[1]]:SetText(label)
 end
 for _,spec in ipairs(colorControls) do
  local color=H.Get(spec[2])
  page[spec[1]]:SetColorRGB(color[1],color[2],color[3])
 end
 local enabled=borderEnabled()
 page.SearchBorderColorSwatch:SetEnabled(enabled)
 page.SearchBorderColorSwatch:SetAlpha(enabled and 1 or .65)
 for _,spec in ipairs(opacityControls) do page[spec[1]].Numeric:Sync() end
end
function H.RegisterSettings(app,page)
 local function register(key,kind,label,default,order,tag)
  local control={id=key,type=kind,groupID="layout",label=L[label],default=default,order=order,newTagID=tag,getValue=function() return H.Get(key) end,setValue=function(value) H.Set(key,value) end}
  if kind=="dropdown" then control.optionfunc=key=="headerTitleMode" and H.TitleOptions or H.BorderOptions
  elseif kind=="slider" then control.min,control.max,control.step,control.suffix=0,100,1,"%"
  else
   control.getColor=function() local c=H.Get(key);return c[1],c[2],c[3],1 end
   control.setColor=function(_,r,g,b) H.Set(key,{r,g,b}) end
   control.getDefaultColor=function() return H.color[1],H.color[2],H.color[3],1 end
  end
  if key=="searchBorderColor" then
   control.isEnabled=borderEnabled
   control.hasOpacity=false
   control.getValue=function() return addon.GetSettings()[key] end
   control.dbDefault=function() return nil,true end
   control.getDefaultColor=function() local c=H.GetSearchBorderBaseColor();return c[1],c[2],c[3],1 end
   control.actions={{id="followSkin",label=L["settingsFrameBorderTextureSkin"],onClick=function() H.Set(key,nil) end}}
  elseif key=="searchBorderOpacity" then
   control.isEnabled=borderEnabled
  end
  app:RegisterControl(page,control)
 end
 register("headerTitleMode","dropdown","settingsBagTitleMode","text",535,"Bags_headerTitleMode")
 register("searchBorderTexture","dropdown","settingsBagSearchBorder","__skin__",540,"Bags_searchBorderTexture")
 register("searchBorderColor","colorpicker","settingsBagSearchBorderColor",nil,541,"Bags_searchBorderColor")
 register("searchBorderOpacity","slider","settingsBagSearchBorderOpacity",100,542,"Bags_searchBorderOpacity")
 register("searchBackgroundColor","colorpicker","settingsBagSearchColor",H.color,545,"Bags_searchBackgroundColor")
 register("searchBackgroundOpacity","slider","settingsBagSearchOpacity",100,550,"Bags_searchBackgroundOpacity")
end
