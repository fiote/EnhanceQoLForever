local addon = _G.EnhanceQoL
if not addon then error("EnhanceQoL is not loaded") end
local QC = addon.QuickCast

-- Decorations never participate in secure selection or mouse hit testing.
function QC:UpdateMenuBackgrounds(visual)
	visual.menuBackgrounds = visual.menuBackgrounds or {}
	for depth, level in ipairs(visual.levels) do
		local menu = level.menu
		local frame = visual.menuBackgrounds[depth]
		if menu.backgroundEnabled then
			if not frame then
				frame = _G.CreateFrame("Frame", nil, visual)
				frame:EnableMouse(false)
				frame:SetFrameLevel(visual:GetFrameLevel())
				frame.fill = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
				frame.fill:SetAllPoints()
				frame.innerMask = frame:CreateMaskTexture()
				frame.innerMask:SetTexture("Interface\\AddOns\\EnhanceQoLQuickActions\\Assets\\RingCutout.tga", "CLAMP", "CLAMP")
				frame.innerMask:SetPoint("CENTER", frame, "CENTER")
				frame.lines = {}
				visual.menuBackgrounds[depth] = frame
			end
			local radial = menu.layout == "radial"
			local half = math.max(1, menu.iconSize / 2 + menu.backgroundPadding)
			local minX, maxX, minY, maxY, radius = 0, 0, 0, 0, 0
			for index = 1, #level.entries do
				local x, y = self:GetSlotOffset(menu, index, #level.entries)
				minX, maxX = math.min(minX, x), math.max(maxX, x)
				minY, maxY = math.min(minY, y), math.max(maxY, y)
				local radialX, radialY = x - (menu.offsetX or 0), y - (menu.offsetY or 0)
				radius = math.max(radius, math.sqrt(radialX * radialX + radialY * radialY))
			end
			local width, height, x, y
			if radial then
				width, height = (radius + half) * 2, (radius + half) * 2
				x, y = menu.offsetX or 0, menu.offsetY or 0
			else
				width, height = maxX - minX + half * 2, maxY - minY + half * 2
				x, y = (minX + maxX) / 2, (minY + maxY) / 2
			end
			frame:SetSize(width, height)
			frame:ClearAllPoints()
			frame:SetPoint("CENTER", visual.originAnchor, "CENTER", level.originOffsetX + x, level.originOffsetY + y)
			if frame.round ~= radial then
				if radial then frame.fill:SetTexture("Interface\\AddOns\\EnhanceQoLQuickActions\\Assets\\CircleFill.tga") end
				frame.round = radial
			end
			local innerRadius = radial and menu.backgroundStyle == "ring" and math.max(0, radius - half) or 0
			local ring = innerRadius > 0
			if ring then frame.innerMask:SetSize(innerRadius * 2 / 0.9375, innerRadius * 2 / 0.9375) end
			if frame.ring ~= ring then
				if ring then frame.fill:AddMaskTexture(frame.innerMask) else frame.fill:RemoveMaskTexture(frame.innerMask) end
				frame.ring = ring
			end
			local active = depth == visual.activeDepth
			local color = active and menu.backgroundColor or menu.backgroundParentColor
			if radial then
				frame.fill:SetVertexColor(unpack(color))
			else
				frame.fill:SetVertexColor(1, 1, 1, 1)
				frame.fill:SetColorTexture(unpack(color))
			end
			local count = menu.backgroundBorderEnabled and (radial and (ring and 192 or 96) or 4) or 0
			local border = menu.backgroundBorderColor
			local r, g, b, alpha = border[1], border[2], border[3], border[4]
			if menu.backgroundBorderUseClassColor then
				local _, classToken = _G.UnitClass("player")
				local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
				local color = colors and colors[classToken]
				if color then r, g, b = color.r, color.g, color.b end
				alpha = menu.backgroundBorderClassAlpha
			end
			for index = 1, math.max(count, #frame.lines) do
				local line = frame.lines[index]
				if index <= count then
					if not line then
						line = frame:CreateLine(nil, "BACKGROUND", nil, -7)
						frame.lines[index] = line
					end
					local x1, y1, x2, y2
					if radial then
						local segment = (index - 1) % 96
						local a, b = segment * math.pi * 2 / 96, (segment + 1) * math.pi * 2 / 96
						local edgeRadius = index > 96 and innerRadius or width / 2
						x1, y1 = math.cos(a) * edgeRadius, math.sin(a) * edgeRadius
						x2, y2 = math.cos(b) * edgeRadius, math.sin(b) * edgeRadius
					else
						local corners = { { -width / 2, -height / 2 }, { width / 2, -height / 2 }, { width / 2, height / 2 }, { -width / 2, height / 2 } }
						x1, y1 = unpack(corners[index])
						x2, y2 = unpack(corners[index % 4 + 1])
					end
					line:SetStartPoint("CENTER", frame, x1, y1)
					line:SetEndPoint("CENTER", frame, x2, y2)
					line:SetThickness(menu.backgroundBorderSize)
					line:SetColorTexture(r, g, b, alpha * (active and 1 or 0.45))
					line:Show()
				elseif line then line:Hide() end
			end
			frame:Show()
		elseif frame then frame:Hide() end
	end
	for depth = #visual.levels + 1, #visual.menuBackgrounds do visual.menuBackgrounds[depth]:Hide() end
end
