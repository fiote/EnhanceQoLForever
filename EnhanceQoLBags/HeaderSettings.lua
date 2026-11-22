local addon=_G.EnhanceQoL
local H=addon.Bags.Header
local L=addon.L
H.rows={{"HeaderTitleLabel","HeaderTitleButton","settingsBagTitleMode"},{"SearchBorderLabel","SearchBorderButton","settingsBagSearchBorder"},{"SearchColorLabel","SearchColorSwatch","settingsBagSearchColor"},{"SearchOpacityLabel","SearchOpacityControl","settingsBagSearchOpacity"}}
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
 local swatch=CreateFrame("Button",nil,page.TextAppearanceCard,"ColorSwatchTemplate");swatch:SetSize(22,22)
 swatch:SetScript("OnClick",function() picker(H.Get("searchBackgroundColor"),function(r,g,b) H.Set("searchBackgroundColor",{r,g,b}) end) end)
 page.SearchColorSwatch=swatch
 local parent=CreateFrame("Frame",nil,page.TextAppearanceCard);parent:SetSize(260,26)
 parent.Numeric=UI.CreateNumeric(parent,{min=0,max=100,step=1,suffix="%",get=function() return H.Get("searchBackgroundOpacity") end,set=function(v) H.Set("searchBackgroundOpacity",v) end})
 page.SearchOpacityControl=parent
 page.HeaderControls=true
end
function H.RefreshControls(page)
 for _,spec in ipairs({{"HeaderTitleButton","headerTitleMode",H.TitleOptions},{"SearchBorderButton","searchBorderTexture",H.BorderOptions}}) do
  local value=H.Get(spec[2]);local label=value
  for _,option in ipairs(spec[3]()) do if option.value==value then label=option.label;break end end
  page[spec[1]]:SetText(label)
 end
 local color=H.Get("searchBackgroundColor");page.SearchColorSwatch:SetColorRGB(color[1],color[2],color[3])
 page.SearchOpacityControl.Numeric:Sync()
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
  app:RegisterControl(page,control)
 end
 register("headerTitleMode","dropdown","settingsBagTitleMode","text",535,"Bags_headerTitleMode")
 register("searchBorderTexture","dropdown","settingsBagSearchBorder","__skin__",540,"Bags_searchBorderTexture")
 register("searchBackgroundColor","colorpicker","settingsBagSearchColor",H.color,545,"Bags_searchBackgroundColor")
 register("searchBackgroundOpacity","slider","settingsBagSearchOpacity",100,550,"Bags_searchBackgroundOpacity")
end
