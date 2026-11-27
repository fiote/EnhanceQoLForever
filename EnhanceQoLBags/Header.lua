local addon = _G.EnhanceQoL
local H = { defaults = { headerTitleMode = "text", searchBorderTexture = "__skin__", searchBorderOpacity = 100, searchBackgroundOpacity = 100 }, color = { 0.03, 0.03, 0.04 } }
addon.Bags.Header = H
H.specialColors = { newItemsTitleColor = { 0.48, 0.82, 0.34 }, freeSlotsTitleColor = { 0.9, 0.78, 0.28 } }

function H.GetSearchBorderBaseColor()
 local skin = addon.GetActiveSkinDefinition().frame
 return addon.GetFrameBorderColor(skin.borderColor)
end

function H.Get(key)
 local value = addon.GetSettings()[key]
 if H.specialColors[key] then
  local default = H.specialColors[key]
  local color = type(value) == "table" and value or default
  return { tonumber(color[1]) or default[1], tonumber(color[2]) or default[2], tonumber(color[3]) or default[3] }
 end
 if key == "newItemsSeparator" then return value == true end
 if key == "headerTitleMode" then return value == "hidden" and "hidden" or "text" end
 if key == "searchBackgroundColor" then
  local color = type(value) == "table" and value or H.color
  return { tonumber(color[1]) or H.color[1], tonumber(color[2]) or H.color[2], tonumber(color[3]) or H.color[3] }
 end
 if key == "searchBorderColor" then
  if type(value) == "table" and value[1] and value[2] and value[3] then return value end
  return H.GetSearchBorderBaseColor()
 end
 if key == "searchBackgroundOpacity" or key == "searchBorderOpacity" then return math.max(0, math.min(100, tonumber(value) or H.defaults[key])) end
 return type(value) == "string" and value or H.defaults[key]
end
function H.Refresh()
 local toolbar = addon.Bags.Toolbar
 for frame in pairs(toolbar.frames) do toolbar.Layout(frame) end
 toolbar.RequestLayouts()
 local state=addon.Bags.variables.settingsState
 local page=state and state.frame and state.frame.Pages.layout
 if page and page.HeaderControls and H.RefreshControls then H.RefreshControls(page) end
end
function H.Set(key, value)
 if key == "headerTitleMode" then
  value = value == "hidden" and "hidden" or "text"
 elseif key == "searchBackgroundOpacity" or key == "searchBorderOpacity" then
  value = math.floor(math.max(0, math.min(100, tonumber(value) or H.defaults[key])) + .5)
 elseif key == "newItemsSeparator" then
  value = value == true
 elseif key == "searchBackgroundColor" or key == "searchBorderColor" or H.specialColors[key] then
  if type(value) == "table" then
   value = { math.max(0, math.min(1, tonumber(value[1]) or 0)), math.max(0, math.min(1, tonumber(value[2]) or 0)), math.max(0, math.min(1, tonumber(value[3]) or 0)) }
  elseif key ~= "searchBorderColor" or value ~= nil then return end
 elseif key ~= "searchBorderTexture" then return end
 addon.GetSettings()[key] = value
 if key == "newItemsSeparator" or H.specialColors[key] then
  for _, name in ipairs({ "RequestLayoutUpdate", "RequestBankLayoutUpdate" }) do
   local refresh = addon.Bags.functions and addon.Bags.functions[name]
   if refresh then refresh(true, true) end
  end
 else
  H.Refresh()
 end
end
function H.GetSpecialCategory(id, groups)
 if id ~= "newItems" and id ~= "freeSlots" then return nil end
 local settings = addon.GetSettings()
 local state = settings.specialCategories and settings.specialCategories[id] or {}
 local groupID = state.groupID
 if id == "freeSlots" and groupID == nil then
  for _, group in ipairs(groups or (addon.GetCustomCategoryGroups and addon.GetCustomCategoryGroups()) or {}) do
   if group.includeFreeSlots then groupID = group.id; break end
  end
 end
 if groupID then
  local found = false
  for _, group in ipairs(groups or (addon.GetCustomCategoryGroups and addon.GetCustomCategoryGroups()) or {}) do
   if group.id == groupID then found = true; break end
  end
  if not found then groupID = nil end
 end
 local label = id == "newItems" and "categoryNewItems" or "categoryFreeSlots"
 local color = id == "newItems" and "newItemsTitleColor" or "freeSlotsTitleColor"
 local visible = id == "newItems" and addon.GetShowNewItems() or id == "freeSlots" and addon.GetShowFreeSlots()
 return { id=id, name=addon.L[label], color=H.Get(color), useClassColor=state.useClassColor == true, groupID=groupID, hidden=not visible,
  spacerBefore=id == "newItems" and settings.newItemsSeparator == true or id == "freeSlots" and state.spacerBefore == true,
  sortOrder=tonumber(state.sortOrder) or (id == "newItems" and 0 or 999),
  renderAfterBuiltIns=id == "freeSlots" and state.sortOrder == nil, isSpecial=true, collapsible=false }
end
function H.SetSpecialCategory(id, field, value)
 if id ~= "newItems" and id ~= "freeSlots" then return false end
 if field == "hidden" then
  if id == "newItems" then addon.SetShowNewItems(not value) else addon.SetShowFreeSlots(not value) end
 elseif field == "spacerBefore" and id == "newItems" then
  H.Set("newItemsSeparator", value)
 elseif field == "color" then
  H.Set(id == "newItems" and "newItemsTitleColor" or "freeSlotsTitleColor", value)
 elseif field == "groupID" or field == "sortOrder" or field == "useClassColor" or field == "spacerBefore" then
  local settings=addon.GetSettings()
  settings.specialCategories=settings.specialCategories or {}
  settings.specialCategories[id]=settings.specialCategories[id] or {}
  if field == "sortOrder" then value=math.max(0,math.min(999,math.floor((tonumber(value) or 0)+.5))) end
  if field == "useClassColor" or field == "spacerBefore" then value=value == true or nil end
  settings.specialCategories[id][field]=value
  if id == "freeSlots" and field == "groupID" then
   for _, group in ipairs(addon.GetCustomCategoryGroups()) do group.includeFreeSlots=group.id == value end
  end
 else return false end
 if addon.MarkCategoryModeStateDirty then addon.MarkCategoryModeStateDirty() end
 return true
end

function H.TitleOptions()
 local L = addon.L
 return {{value="text",label=L["settingsBagTitleText"]},{value="hidden",label=L["settingsBagTitleHidden"]}}
end
function H.BorderOptions()
 local result = addon.GetFrameBorderTextureOptions()
 table.insert(result,2,{value="__none__",label=_G.NONE})
 return result
end
local function applySearchPadding(search)
 if not search.searchIcon or search.HeaderPaddingApplied then return end
 local left,right,top,bottom=search:GetTextInsets()
 local point,relativeTo,relativePoint,x,y=search.searchIcon:GetPoint(1)
 search.searchIcon:ClearAllPoints()
 search.searchIcon:SetPoint(point,relativeTo,relativePoint,x+4,y)
 search:SetTextInsets(left+4,right,top,bottom)
 search.HeaderPaddingApplied=true
end
function H.ApplySearch(frame)
 local search = frame.SearchBox
 if not search then return end
 if not search.HeaderNativeParts then
  search.HeaderNativeParts={}
  for _,key in ipairs({"Left","Middle","Right","LeftTexture","MiddleTexture","RightTexture"}) do
   local texture=search[key]
   if texture and texture.SetAlpha then search.HeaderNativeParts[texture]=true end
  end
 end
 applySearchPadding(search)
 for texture in pairs(search.HeaderNativeParts) do texture:SetAlpha(0) end
 if not frame.SearchAppearance then
  frame.SearchAppearance=CreateFrame("Frame",nil,frame,"BackdropTemplate")
  frame.SearchAppearance:EnableMouse(false)
 end
 local surface=frame.SearchAppearance
 surface:ClearAllPoints();surface:SetPoint("TOPLEFT",search,"TOPLEFT",-5,0);surface:SetPoint("BOTTOMRIGHT",search,"BOTTOMRIGHT",5,0)
 surface:SetFrameLevel(frame:GetFrameLevel()+2);search:SetFrameLevel(frame:GetFrameLevel()+3)
 local key=H.Get("searchBorderTexture")
 local edge="Interface\\Buttons\\WHITE8X8"
 if key~="__skin__" and key~="__none__" and addon.functions.ResolveLSMMedia then edge=addon.functions.ResolveLSMMedia("border",key,edge,true) or edge end
 surface:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile=key~="__none__" and edge or nil,edgeSize=key=="__skin__" and 1 or 3})
 local color=H.Get("searchBackgroundColor")
 surface:SetBackdropColor(color[1],color[2],color[3],H.Get("searchBackgroundOpacity")/100)
 local border=H.Get("searchBorderColor")
 surface:SetBackdropBorderColor(border[1],border[2],border[3],H.Get("searchBorderOpacity")/100)
 surface:SetShown(search:IsShown())
end
function H.Apply(frame,leftmost)
 if not (frame.SearchBox and frame.Title) then return end
 local padding=frame._toolbarPadding or 10
 local mode=frame:GetName()=="BagsMainFrame" and H.Get("headerTitleMode") or "text"
 frame.Title:SetShown(mode=="text")
 local search=frame.SearchBox
 search:ClearAllPoints()
 if frame.HeaderSearchRight then
  search:SetPoint("LEFT",frame.Title,"RIGHT",18,0)
  search:SetPoint("RIGHT",frame.HeaderSearchRight,"LEFT",-10,0)
 else
  if mode=="text" then search:SetPoint("TOPLEFT",frame.Title,"TOPRIGHT",18,2)
  else search:SetPoint("TOPLEFT",frame,"TOPLEFT",padding+5,-8) end
  if leftmost then search:SetPoint("TOPRIGHT",leftmost,"TOPLEFT",-10,-2)
  else search:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-padding,-8) end
 end
 H.ApplySearch(frame)
end
