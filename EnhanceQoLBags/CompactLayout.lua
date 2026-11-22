local addon = _G.EnhanceQoL

-- Plan consecutive category blocks without changing their order or group ownership.
function addon.Bags.PlanCompactRow(entries, available, gap, size, spacing, sectionGap, widthOf)
 local heights, seen = {1}, {[1]=true}
 for _, entry in ipairs(entries) do
  local m = entry.metrics
  entry.contentOffset = widthOf(entry.section, m) - m.blockWidth
  if not entry.collapsed then
   for columns = 1, m.sectionColumnCount do
    local rows = math.ceil(m.itemCount / columns)
    if not seen[rows] then seen[rows]=true; heights[#heights+1]=rows end
   end
  end
 end
 table.sort(heights)
 local best, plans = {[#entries+1]=0}, {}
 for first = #entries, 1, -1 do
  for _, targetRows in ipairs(heights) do
   local width, height, columnsByIndex = 0, 0, {}
   for last = first, #entries do
    local entry, columns = entries[last], nil
    local m = entry.metrics
    local blockWidth, blockHeight = m.blockWidth, m.blockHeight
    if not entry.collapsed then
     columns = math.max(1, math.ceil(m.itemCount / targetRows))
     if columns > m.sectionColumnCount then break end
     local rows = math.ceil(m.itemCount / columns)
     blockWidth = columns * size + (columns-1)*spacing
     local oldItemsHeight = m.rows > 0 and m.rows*size+(m.rows-1)*spacing or 0
     blockHeight = m.blockHeight-oldItemsHeight+rows*size+(rows-1)*spacing
    end
    width = width + blockWidth + entry.contentOffset + (last > first and gap or 0)
    if width > available and last > first then break end
    if width > available and not entry.collapsed then break end
    height = math.max(height, blockHeight)
    columnsByIndex[last] = columns
    local cost = height + (last < #entries and sectionGap or 0) + best[last+1]
    if not best[first] or cost < best[first] then
     best[first]=cost
     local chosen={}
     for i=first,last do chosen[i]=columnsByIndex[i] end
     plans[first]={last=last, columns=chosen}
    end
   end
  end
  -- Preserve a single oversized block rather than dropping it.
  if not plans[first] then
   best[first]=entries[first].metrics.blockHeight+sectionGap+best[first+1]
   plans[first]={last=first,columns={}}
  end
 end
 local plan, row, width, height = plans[1], {}, 0, 0
 for i=1,plan.last do
  local entry = entries[i]
  local m, columns = entry.metrics, plan.columns[i]
  if columns then
   local oldItemsHeight=m.rows > 0 and m.rows*size+(m.rows-1)*spacing or 0
   m.sectionColumnCount=columns
   m.visibleColumns=columns
   m.rows=math.ceil(m.itemCount/columns)
   m.blockWidth=columns*size+(columns-1)*spacing
   m.blockHeight=m.blockHeight-oldItemsHeight+m.rows*size+(m.rows-1)*spacing
  end
  row[#row+1]=entry
  width=width+widthOf(entry.section,m)+(i>1 and gap or 0)
  height=math.max(height,m.blockHeight)
 end
 return row,width,height
end
