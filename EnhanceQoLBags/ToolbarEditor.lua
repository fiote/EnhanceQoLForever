local addon = _G.EnhanceQoL
local T = addon.Bags.Toolbar
local L = addon.L
T.editorPool = {}
T.labelKeys = { bank = "bagsOfflineBankTitle", lists = "vendorListEditor", bags = "settingsToolbarBags", mode = "bagSortMode", sort = "settingsToolbarCleanup", settings = "settingsTitleSuffix", close = "settingsShowCloseButton" }

function T.Label(kind)
 return kind == "close" and CLOSE or L[T.labelKeys[kind]]
end

function T.CreateEditor(parent,showSpacing)
 showSpacing=showSpacing~=false
 local pooled=table.remove(T.editorPool)
 if pooled then
  pooled.released=nil;pooled.Reset=nil;pooled:SetSpacingShown(showSpacing);pooled:SetParent(parent);pooled:ClearAllPoints();T.editors[pooled]=true;pooled:Show();pooled:Refresh();return pooled
 end
 local editor = CreateFrame("Frame", nil, parent)
 editor._bagsToolbarEditor=true
 editor:SetHeight(370)
 editor.rows, editor.previewButtons = {}, {}
 local hint = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
 hint:SetPoint("TOPLEFT", 8, -4);hint:SetPoint("RIGHT", -8, 0);hint:SetJustifyH("LEFT")
 hint:SetText(L["settingsToolbarHint"])
 editor.Hint = hint
 local preview = CreateFrame("Frame", nil, editor, "BackdropTemplate")
 preview:SetPoint("TOPLEFT", 8, -46);preview:SetPoint("RIGHT", -8, 0);preview:SetHeight(48)
 preview:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
 preview:SetBackdropBorderColor(.35,.3,.2,1)
 preview.BackgroundTexture=preview:CreateTexture(nil,"BACKGROUND",nil,-7)
 preview.BackgroundShade=preview:CreateTexture(nil,"BACKGROUND",nil,-6)
 editor.Preview = preview
 for _,kind in ipairs(T.defaultOrder) do
  local b=CreateFrame("Button",nil,preview)
  T.Style(b,kind);editor.previewButtons[kind]=b
  b:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText(T.Label(kind));GameTooltip:Show() end)
  b:SetScript("OnLeave",function() GameTooltip:Hide() end)
 end
 function editor:CancelDrag()
  self.dragIndex=nil
  self:SetScript("OnUpdate",nil)
  for _,row in ipairs(self.rows) do row:SetAlpha(1);row.Target:Hide() end
 end
 function editor:Drop()
  local from=self.dragIndex
  local target
  if from then
   for i,row in ipairs(self.rows) do
    if addon.functions.MouseIsOver(row) then target=i;break end
   end
  end
  self:CancelDrag()
  if from and target then T.Move(from,target) end
 end
 for index,kind in ipairs(T.defaultOrder) do
  local row=CreateFrame("Button",nil,editor)
  row:SetPoint("TOPLEFT",8,-104-(index-1)*34);row:SetPoint("RIGHT",-8,0);row:SetHeight(30)
  row:RegisterForDrag("LeftButton")
  local bg=row:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetColorTexture(.09,.1,.12,.5)
  row.Target=row:CreateTexture(nil,"BORDER");row.Target:SetAllPoints();row.Target:SetColorTexture(.5,.65,1,.3);row.Target:Hide()
  row.Icon=CreateFrame("Button",nil,row);row.Icon:SetPoint("LEFT",50,0);T.Style(row.Icon,kind)
  row.icons={[kind]=row.Icon}
  row.Grip=row:CreateFontString(nil,"OVERLAY","GameFontDisableSmall");row.Grip:SetPoint("LEFT",4,0);row.Grip:SetText("::")
  row.Label=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");row.Label:SetPoint("LEFT",82,0);row.Label:SetPoint("RIGHT",-12,0);row.Label:SetJustifyH("LEFT")
  row.Toggle=addon.Bags.SettingsNavigation.CreateCheckbox("CheckButton",nil,row);row.Toggle:SetPoint("LEFT",20,0)
  row.Toggle:SetScript("OnClick",function(self) T.SetVisible(row.kind,self:GetChecked()) end)
  row:SetScript("OnDragStart",function(self)
   editor:CancelDrag();editor.dragIndex=index;self:SetAlpha(.5)
   editor:SetScript("OnUpdate",function()
    for _,candidate in ipairs(editor.rows) do candidate.Target:SetShown(addon.functions.MouseIsOver(candidate)) end
   end)
  end)
  row:SetScript("OnDragStop",function() editor:Drop() end)
  -- The glyph should be draggable as part of its row as well.
  row.Icon:RegisterForDrag("LeftButton")
  row.Icon:SetScript("OnDragStart",function() row:GetScript("OnDragStart")(row) end)
  row.Icon:SetScript("OnDragStop",function() editor:Drop() end)
  row.kind=kind;editor.rows[index]=row
 end
 local gapRow=CreateFrame("Frame",nil,editor)
 gapRow:SetPoint("TOPLEFT",8,-350);gapRow:SetPoint("RIGHT",-8,0);gapRow:SetHeight(26)
 local gapLabel=gapRow:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 gapLabel:SetPoint("LEFT");gapLabel:SetPoint("RIGHT",gapRow,"LEFT",170,0);gapLabel:SetJustifyH("LEFT");gapLabel:SetText(L["settingsToolbarSpacing"])
 local gapControl=CreateFrame("Frame",nil,gapRow)
 gapControl:SetPoint("TOPLEFT",180,0);gapControl:SetPoint("BOTTOMRIGHT")
 editor.Spacing=addon.Bags.SettingsNavigation.CreateNumeric(gapControl,{min=0,max=20,step=1,get=T.GetSpacing,set=T.SetSpacing})
 function editor:SetSpacingShown(shown)
  gapRow:SetShown(shown);self:SetHeight(shown and 382 or 346)
 end
 editor:SetSpacingShown(showSpacing)
 function editor:Refresh()
  self.Spacing:Sync()
  local skin=addon.GetActiveSkinDefinition().frame
  addon.ApplyFrameBackgroundSkin(self.Preview,skin)
  local order=T.GetOrder()
  local previous
  for _,kind in ipairs(order) do
   local b=self.previewButtons[kind]
   b:SetShown(T.IsVisible(kind));T.Update(b)
   if b:IsShown() then
    b:ClearAllPoints()
    if previous then b:SetPoint("LEFT",previous,"RIGHT",T.GetSpacing(),0)
    else b:SetPoint("LEFT",12,0) end
    previous=b
   end
  end
  for i,kind in ipairs(order) do
   local row=self.rows[i]
   row.kind=kind;row.Label:SetText(T.Label(kind));row.Toggle:SetChecked(T.IsVisible(kind));row.Toggle:SetShown(kind~="settings")
   if row.Icon._toolbarKind~=kind then
    -- Reuse one glyph per kind; rows themselves keep stable drag targets.
    if row.CurrentIcon then row.CurrentIcon:Hide() end
    local icon=row.icons[kind]
    if not icon then
     icon=CreateFrame("Button",nil,row);icon:SetPoint("LEFT",50,0);T.Style(icon,kind)
     icon:RegisterForDrag("LeftButton")
     icon:SetScript("OnDragStart",function() row:GetScript("OnDragStart")(row) end)
     icon:SetScript("OnDragStop",function() self:Drop() end)
     row.icons[kind]=icon
    end
    row.Icon=icon
   end
   row.Icon:Show();row.CurrentIcon=row.Icon;T.Update(row.Icon)
  end
 end
 function editor:Release()
  if self.released then return end
  self.released=true;self:CancelDrag();T.editors[self]=nil;self:Hide();self:SetParent(nil);T.editorPool[#T.editorPool+1]=self
 end
 editor:SetScript("OnHide",function(self) self:CancelDrag() end)
 editor:SetScript("OnShow",function(self) self:Refresh() end)
 T.editors[editor]=true
 editor:Refresh()
 return editor
end

function T.RegisterSpacing(app,pageID)
 app:RegisterControl(pageID,{
  id="toolbarSpacing",type="slider",groupID="toolbar",order=15,label=L["settingsToolbarSpacing"],
  default=4,min=0,max=20,step=1,newTagID="Bags_toolbarSpacing",getValue=T.GetSpacing,setValue=T.SetSpacing,
 })
end

function T.RegisterEditor(app,pageID)
 app:RegisterGroup(pageID,{id="toolbar",title=L["settingsToolbarTitle"],order=15,columns=1})
 T.RegisterSpacing(app,pageID)
 app:RegisterControl(pageID,{
  id="toolbarReset",type="button",groupID="toolbar",order=40,label=RESET_TO_DEFAULT,buttonText=RESET_TO_DEFAULT,
  onClick=T.Reset,trackCustomized=false,refreshOnChange=true,
 })
 app:RegisterControl(pageID,{
  id="toolbarLayout",type="custom",groupID="toolbar",order=10,label=L["settingsToolbarTitle"],
  description=L["settingsToolbarHint"],hideHeader=true,rowHeight=370,newTagID="Bags_toolbarLayout",
  default=T.GetDefaultLayout(),getValue=T.GetLayout,setValue=T.SetLayout,
  render=function(parent)
   local editor=T.CreateEditor(parent,false);editor:SetPoint("TOPLEFT");editor:SetPoint("RIGHT");return editor
  end,
  refresh=function(handle) if handle then handle:Refresh() end end,
  release=function(handle) if handle then handle:Release() end end,
 })
end
