local _, addon = ...
local Icons = {}
addon.MicroBarIcons = Icons

local shapes = {
 character={{{10,18},{12,17},{13,15},{12,13},{10,12},{8,13},{7,15},{8,17},{10,18}},{{3,2},{3,5},{5,8},{8,9},{12,9},{15,8},{17,5},{17,2},{3,2}}},
 achievements={{{5,18},{15,18},{14,10},{10,7},{6,10},{5,18}},{{5,15},{2,15},{2,11},{6,9}},{{15,15},{18,15},{18,11},{14,9}},{{10,7},{10,3}},{{6,2},{14,2}}},
 calendar={{{3,3},{17,3},{17,16},{3,16},{3,3}},{{3,12},{17,12}},{{6,14},{6,18}},{{14,14},{14,18}},{{7,7},{9,7}}},
 chatchannels={{{2,6},{2,16},{18,16},{18,6},{10,6},{5,2},{5,6},{2,6}}},
 clock={{{10,17},{15,15},{17,10},{15,5},{10,3},{5,5},{3,10},{5,15},{10,17}},{{10,14},{10,10},{13,8}}},
 dungeonjournal={{{3,3},{3,17},{10,15},{17,17},{17,3},{10,1},{3,3}},{{10,1},{10,15}},{{5,12},{8,11}},{{12,11},{15,12}}},
 guild={{{4,18},{16,18},{16,7},{10,2},{4,7},{4,18}},{{8,14},{12,14},{10,10},{8,14}}},
 housing={{{2,10},{10,18},{18,10}},{{5,11},{5,3},{15,3},{15,11}},{{8,3},{8,8},{12,8},{12,3}}},
 lfg={{{3,3},{3,7},{6,9},{9,7},{9,3}},{{12,3},{12,7},{15,9},{18,7},{18,3}},{{6,12},{3,15},{6,18},{9,15},{6,12}},{{15,12},{12,15},{15,18},{18,15},{15,12}}},
 missions={{{4,2},{4,18},{16,18},{14,12},{4,12}}},
 professions={{{3,3},{13,13}},{{10,17},{17,10},{19,12},{12,19},{10,17}}},
 questlog={{{4,2},{4,18},{16,18},{16,2},{4,2}},{{8,13},{12,13}},{{8,9},{12,9}},{{8,5},{11,5}}},
 social={{{3,3},{3,6},{6,9},{10,9},{13,6},{13,3}},{{8,11},{5,14},{8,17},{11,14},{8,11}},{{14,10},{17,7},{17,3}}},
 talents={{{10,3},{10,10},{4,16}},{{10,10},{16,16}},{{2,14},{2,18},{6,18},{6,14},{2,14}},{{14,14},{14,18},{18,18},{18,14},{14,14}},{{8,2},{12,2},{12,6},{8,6},{8,2}}},
 spellbook={{{2,4},{2,16},{7,17},{10,15},{13,17},{18,16},{18,4},{13,5},{10,3},{7,5},{2,4}},{{10,3},{10,15}}},
 collections={{{3,3},{17,3},{17,14},{3,14},{3,3}},{{7,14},{7,18},{13,18},{13,14}},{{3,10},{17,10}},{{9,8},{11,8}}},
 gamemenu={{{3,5},{17,5}},{{3,10},{17,10}},{{3,15},{17,15}}},
 support={{{5,14},{5,16},{8,18},{13,18},{16,15},{15,12},{10,9},{10,7}},{{10,3},{10,4}}},
 worldmap={{{2,3},{2,16},{7,18},{13,15},{18,17},{18,4},{13,2},{7,5},{2,3}},{{7,5},{7,18}},{{13,2},{13,15}}},
 menu={{{3,5},{17,5}},{{3,10},{17,10}},{{3,15},{17,15}}},
}
-- Fit visible contours to the same envelope while preserving each symbol's proportions.
for _, shape in pairs(shapes) do
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, path in ipairs(shape) do
		for _, point in ipairs(path) do
			minX, minY = math.min(minX, point[1]), math.min(minY, point[2])
			maxX, maxY = math.max(maxX, point[1]), math.max(maxY, point[2])
		end
	end
	shape.centerX, shape.centerY = (minX + maxX) / 2, (minY + maxY) / 2
	shape.extent = math.max(maxX - minX, maxY - minY)
end

local defaultColor = { r = 0.92, g = 0.73, b = 0.37 }

local function channel(value, fallback)
	value = tonumber(value)
	if not value or value ~= value then return fallback end
	return math.max(0, math.min(1, value))
end

function Icons.GetSpec(id, db, fallback)
	if db.iconStyle == "blizzard" or not shapes[id] then return fallback end
	local color = type(db.iconColor) == "table" and db.iconColor or defaultColor
	if db.iconClassColor then
		local class = select(2, UnitClass("player"))
		local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
		color = (colors and colors[class]) or color
	end
	return {
		glyph = id,
		color = { r = channel(color.r, defaultColor.r), g = channel(color.g, defaultColor.g), b = channel(color.b, defaultColor.b) },
	}
end

local function paint(button)
	local icon = button.eqolMicroGlyph
	if not icon or not icon.active then return end
	local enabled = button:IsEnabled()
	local hovered = icon.hovered and enabled
	local pressed = icon.pressed and enabled
	local alpha = enabled and (hovered and 1 or 0.88) or 0.3
	for i = 1, icon.count do
		local segment = icon.segments[i]
		segment.texture:SetVertexColor(icon.r, icon.g, icon.b, alpha)
		segment.texture:ClearAllPoints()
		segment.texture:SetPoint("CENTER", button, "CENTER", segment.x + (pressed and 1 or 0), segment.y - (pressed and 1 or 0))
	end
	icon.background:SetVertexColor(icon.r, icon.g, icon.b, enabled and (pressed and 0.18 or hovered and 0.10 or 0) or 0)
end

function Icons.Clear(button)
	local icon = button.eqolMicroGlyph
	if not icon then return end
	icon.active, icon.hovered, icon.pressed = nil, nil, nil
	for _, segment in ipairs(icon.segments) do segment.texture:Hide() end
	icon.background:Hide()
end

local function attach(button)
	local icon = { segments = {}, count = 0 }
	button.eqolMicroGlyph = icon
	icon.background = button:CreateTexture(nil, "BACKGROUND")
	icon.background:SetTexture("Interface\\Buttons\\WHITE8x8")
	icon.background:SetAllPoints(button)
	button:HookScript("OnEnter", function(self) icon.hovered = true; paint(self) end)
	button:HookScript("OnLeave", function(self) icon.hovered, icon.pressed = nil, nil; paint(self) end)
	button:HookScript("OnMouseDown", function(self, key) if key == "LeftButton" then icon.pressed = true; paint(self) end end)
	button:HookScript("OnMouseUp", function(self) icon.pressed = nil; paint(self) end)
	button:HookScript("OnHide", function(self) icon.hovered, icon.pressed = nil, nil; paint(self) end)
	button:HookScript("OnEnable", paint)
	button:HookScript("OnDisable", paint)
	return icon
end

function Icons.Apply(button, spec, defaultSize)
	local shape = spec and spec.glyph and shapes[spec.glyph]
	if not shape then Icons.Clear(button); return false end
	local icon = button.eqolMicroGlyph or attach(button)
	local size = spec.size or defaultSize
	local color = spec.color
	icon.active = true
	icon.r, icon.g, icon.b = color.r, color.g, color.b
	if icon.kind ~= spec.glyph or icon.size ~= size then
		icon.kind, icon.size = spec.glyph, size
		local weight = size <= 18 and math.max(1.3, size * 1.65 / 18) or 1.65 + (size - 18) / 24
		local scale = size * 0.8 / shape.extent
		local count = 0
		for _, path in ipairs(shape) do
			for i = 2, #path do
				local from, to = path[i - 1], path[i]
				local x, y = to[1] - from[1], to[2] - from[2]
				count = count + 1
				local segment = icon.segments[count]
				if not segment then
					local texture = addon.PixelUtil.ApplyTexturePixelSnapping(button:CreateTexture(nil, "ARTWORK"))
					texture:SetTexture("Interface\\Buttons\\WHITE8x8")
					segment = { texture = texture }
					icon.segments[count] = segment
				end
				segment.x, segment.y = ((from[1] + to[1]) / 2 - shape.centerX) * scale, ((from[2] + to[2]) / 2 - shape.centerY) * scale
				segment.texture:SetSize(math.sqrt(x * x + y * y) * scale, weight)
				segment.texture:SetRotation(math.atan2(y, x))
			end
		end
		icon.count = count
	end
	for i, segment in ipairs(icon.segments) do segment.texture:SetShown(i <= icon.count) end
	icon.background:Show()
	paint(button)
	return true
end

function Icons.StyleMenuEntry(description, id, db, enabled)
	local spec = Icons.GetSpec(id, db)
	if not spec then return end
	spec.size = 16
	description:AddInitializer(function(button)
		local host = button.eqolMicroMenuIcon
		if not host then
			host = CreateFrame("Button", nil, button)
			host:EnableMouse(false)
			button.eqolMicroMenuIcon = host
			button:HookScript("OnEnter", function()
				if host.eqolMicroGlyph then host.eqolMicroGlyph.hovered = true; paint(host) end
			end)
			button:HookScript("OnLeave", function()
				if host.eqolMicroGlyph then host.eqolMicroGlyph.hovered = nil; paint(host) end
			end)
		end
		host:SetSize(20, 20)
		host:ClearAllPoints()
		host:SetPoint("LEFT", button, "LEFT", 2, 0)
		host:SetEnabled(enabled ~= false)
		Icons.Apply(host, spec, 16)
		host:Show()
		local label = button.fontString
		label:ClearAllPoints()
		label:SetPoint("LEFT", button, "LEFT", 28, 0)
		return label:GetStringWidth() + 36, 22
	end)
	description:AddResetter(function(button)
		local host = button.eqolMicroMenuIcon
		if host then Icons.Clear(host); host:Hide() end
	end)
end
