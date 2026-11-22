local addon = _G.EnhanceQoL
-- Keep version-2 read limits while writing smaller batches. Scale the block
-- budget with the line batches; the shared compressed-byte budget stays fixed.
local C = { version = 2, blockLines = 128, blockBytes = 65536, writeBlockLines = 32, writeBlockBytes = 8192, maxBytes = 16 * 1024 * 1024, maxBlocks = 16384, maxManifest = 1024 * 1024, cacheLimit = 16, readCacheBlocks = 128, readCacheBytes = 8 * 1024 * 1024 }
addon.ChatHistoryCodec = C
local serializer = LibStub("AceSerializer-3.0")
local deflate = LibStub("LibDeflate")

function C.Pack(value, level, pause)
	local raw = serializer:Serialize(value)
	if pause then pause() end
	local compressed = deflate:CompressDeflate(raw, { level = level or 1 })
	if pause then pause() end
	-- Verify before replacing a previously saved block, including during migration.
	assert(deflate:DecompressDeflate(compressed) == raw, "Chat history compression verification failed")
	if pause then pause() end
	return tostring(deflate:Adler32(raw)) .. ":" .. deflate:EncodeForPrint(compressed), raw
end

function C.Unpack(data)
	if type(data) ~= "string" then return nil end
	local checksum, encoded = data:match("^(%d+):(.*)$")
	if not checksum then return nil end
	local compressed = deflate:DecodeForPrint(encoded)
	if not compressed then return nil end
	local raw = deflate:DecompressDeflate(compressed)
	if not raw or deflate:Adler32(raw) ~= tonumber(checksum) then return nil end
	local ok, value = serializer:Deserialize(raw)
	if ok and type(value) == "table" then return value, raw end
end

function C.Copy(value, leaves, depth)
	if type(value) ~= "table" then return value end
	depth = (depth or 0) + 1
	assert(depth <= 20, "Chat history metadata is too deeply nested")
	local result = {}
	for key, child in pairs(value) do
		if not (leaves[value] and (key == "lines" or key == "timestamps" or type(key) == "number")) then result[key] = C.Copy(child, leaves, depth) end
	end
	return result
end

function C.At(root, path)
	local value = root
	for _, key in ipairs(path) do
		if type(value) ~= "table" then return nil end
		value = value[key]
	end
	return value
end

function C.Streams(root, kind)
	local streams = {}
	if kind == "im" then
		for key, lines in pairs(root) do
			if type(lines) == "table" then streams[#streams + 1] = { bucket = lines, path = { key } } end
		end
	else
		for faction, realms in pairs(root) do
			if type(realms) == "table" then
				for realm, realmData in pairs(realms) do
					if type(realmData) == "table" then
						for character, characterData in pairs(realmData.characters or {}) do
							for channel, bucket in pairs(characterData.channels or {}) do
								streams[#streams + 1] = { bucket = bucket, path = { faction, realm, "characters", character, "channels", channel } }
							end
						end
					end
				end
			end
		end
	end
	return streams
end

function C.Same(left, right)
	if type(left) ~= type(right) then return false end
	if type(left) ~= "table" then return left == right end
	for key, value in pairs(left) do if not C.Same(value, right[key]) then return false end end
	for key in pairs(right) do if left[key] == nil then return false end end
	return true
end

function C.BlockInfo(block, payload)
	local latest = 0
	for index, item in ipairs(payload.items) do
		local stamp = type(item) == "table" and item.time or payload.timestamps and payload.timestamps[index]
		if type(stamp) == "number" then latest = math.max(latest, stamp) end
	end
	if block.first == payload.first and block.count == #payload.items and block.latest == latest then return block end
	return { data = block.data, time = block.time, first = payload.first, count = #payload.items, latest = latest }
end

function C.IsActive(bucket, index)
	if not bucket._cap or not bucket._head or bucket._count == nil then return true end
	if bucket._cap <= 0 then return false end
	return (index - bucket._head) % bucket._cap < bucket._count and index >= 1 and index <= bucket._cap
end

function C.ActiveCount(bucket, first, count)
	if not bucket._cap or not bucket._head or bucket._count == nil then return count end
	if bucket._cap <= 0 or bucket._count <= 0 then return 0 end
	local last = first + count - 1
	local finish = bucket._head + bucket._count - 1
	local active = math.max(0, math.min(last, finish, bucket._cap) - math.max(first, bucket._head) + 1)
	if finish > bucket._cap then active = active + math.max(0, math.min(last, finish - bucket._cap) - math.max(first, 1) + 1) end
	return active
end

function C.HasRange(block)
	return type(block.first) == "number" and block.first >= 1 and block.first % 1 == 0 and type(block.count) == "number" and block.count >= 1 and block.count <= C.blockLines and block.count % 1 == 0
end

function C.EncodeLines(bucket, kind, previous, pause)
	local lines = kind == "im" and bucket or bucket.lines
	local blocks, index = {}, 1
	local last = kind == "channel" and math.max(#lines, bucket._cap or 0) or #lines
	while index <= last do
		while index <= last and (not lines[index] or (kind == "channel" and not C.IsActive(bucket, index))) do index = index + 1 end
		if index > last then break end
		local payload = { first = index, items = {}, timestamps = kind == "im" and {} or nil }
		local size, stamp = 0, nil
		repeat
			local item = lines[index]
			local bytes = #serializer:Serialize(item)
			if #payload.items > 0 and size + bytes > C.writeBlockBytes then break end
			payload.items[#payload.items + 1] = item
			local time = kind == "im" and bucket.timestamps and bucket.timestamps[index] or type(item) == "table" and item.time
			if payload.timestamps then payload.timestamps[#payload.items] = bucket.timestamps and bucket.timestamps[index] or false end
			if type(time) == "number" then stamp = stamp and math.min(stamp, time) or time end
			size, index = size + bytes, index + 1
		until index > last or #payload.items >= C.writeBlockLines or not lines[index] or (kind == "channel" and not C.IsActive(bucket, index))
		local old = previous and previous[#blocks + 1]
		local oldPayload = old and C.Unpack(old.data)
		if oldPayload and C.Same(oldPayload, payload) then
			blocks[#blocks + 1] = C.BlockInfo(old, payload)
		else
			blocks[#blocks + 1] = C.BlockInfo({ data = C.Pack(payload, nil, pause), time = stamp or 0 }, payload)
		end
		if pause then pause() end
	end
	return blocks
end

-- Preserve old physical ranges so changing a message's size never shifts an
-- unrelated block. Only affected ranges need decoding and subdivision.
function C.EncodeChanges(changes, previous, pause, read, window)
	local blocks, covered = {}, {}
	for blockIndex, block in ipairs(previous) do
		local changed = false
		local active = window and C.ActiveCount(window, block.first, block.count) or block.count
		local extension = block.first + block.count
		if blockIndex == #previous and block.count < C.writeBlockLines and changes[extension] and (not window or C.IsActive(window, extension)) then changed = true end
		for index = block.first, block.first + block.count - 1 do
			if changes[index] then changed = true; covered[index] = true end
		end
		if active > 0 and (changed or active ~= block.count) then
			local payload = read(block)
			if not payload or payload.first ~= block.first or #payload.items ~= block.count then return nil end
			local items, start = {}, nil
			for offset, item in ipairs(payload.items) do
				local index = block.first + offset - 1
				if not window or C.IsActive(window, index) then
					start = start or index
					items[#items + 1] = changes[index] or item
				elseif start then
					for _, replacement in ipairs(C.EncodeRange(items, start, pause)) do blocks[#blocks + 1] = replacement end
					items, start = {}, nil
				end
			end
			while blockIndex == #previous and #items < C.writeBlockLines and changes[extension] and (not window or C.IsActive(window, extension)) do
				start = start or extension
				items[#items + 1] = changes[extension]
				covered[extension], extension = true, extension + 1
			end
			if start then for _, replacement in ipairs(C.EncodeRange(items, start, pause)) do blocks[#blocks + 1] = replacement end end
		elseif active > 0 then
			blocks[#blocks + 1] = block
		end
	end
	local extra = {}
	for index in pairs(changes) do if not covered[index] and (not window or C.IsActive(window, index)) then extra[#extra + 1] = index end end
	table.sort(extra)
	local start, items
	for _, index in ipairs(extra) do
		if not start or index ~= start + #items then
			if start then for _, block in ipairs(C.EncodeRange(items, start, pause)) do blocks[#blocks + 1] = block end end
			start, items = index, {}
		end
		items[#items + 1] = changes[index]
	end
	if start then for _, block in ipairs(C.EncodeRange(items, start, pause)) do blocks[#blocks + 1] = block end end
	table.sort(blocks, function(a, b) return a.first < b.first end)
	return blocks
end

function C.EncodeRange(lines, first, pause)
	local blocks, index = {}, 1
	while index <= #lines do
		local payload = { first = first + index - 1, items = {} }
		local size, stamp = 0, nil
		repeat
			local item = lines[index]
			local bytes = #serializer:Serialize(item)
			if #payload.items > 0 and size + bytes > C.writeBlockBytes then break end
			payload.items[#payload.items + 1] = item
			if type(item.time) == "number" then stamp = stamp and math.min(stamp, item.time) or item.time end
			size, index = size + bytes, index + 1
		until index > #lines or #payload.items >= C.writeBlockLines
		blocks[#blocks + 1] = C.BlockInfo({ data = C.Pack(payload, nil, pause), time = stamp or 0 }, payload)
		if pause then pause() end
	end
	return blocks
end

function C.Restore(bucket, kind, blocks, overrides)
	local items, timestamps, valid, damaged, normalized = {}, {}, 0, false, false
	for _, block in ipairs(blocks) do
		if kind ~= "channel" or not C.HasRange(block) or C.ActiveCount(bucket, block.first, block.count) > 0 then
			local ok, payload = pcall(C.Unpack, block.data)
			if ok and payload and type(payload.first) == "number" and payload.first >= 1 and payload.first % 1 == 0 and type(payload.items) == "table" and #payload.items <= C.blockLines then
				for offset, item in ipairs(payload.items) do
					local index = payload.first + offset - 1
					if kind == "channel" and not C.IsActive(bucket, index) then
						-- A reduced ring window intentionally excludes these old records.
					elseif index <= 100000 and ((kind == "im" and type(item) == "string") or (kind == "channel" and type(item) == "table")) then
						items[index] = item
						timestamps[index] = payload.timestamps and payload.timestamps[offset] or false
						valid = valid + 1
					else
						damaged = true
					end
				end
			else
				damaged = true
			end
		end
	end
	if overrides then
		for index, item in pairs(overrides) do if kind ~= "channel" or C.IsActive(bucket, index) then items[index] = item end end
		valid = 0
		for _ in pairs(items) do valid = valid + 1 end
	end
	if kind == "im" then
		for key in pairs(bucket) do if type(key) == "number" then bucket[key] = nil end end
		bucket.timestamps = {}
		local indices = {}
		for index in pairs(items) do indices[#indices + 1] = index end
		table.sort(indices)
		for _, index in ipairs(indices) do
			bucket[#bucket + 1] = items[index]
			bucket.timestamps[#bucket] = timestamps[index]
		end
	elseif valid ~= (bucket._count or valid) or damaged then
		-- Missing/corrupt blocks leave holes in a ring. Keep surviving lines in order.
		normalized = true
		local ordered = {}
		local cap, head = bucket._cap or valid, bucket._head or 1
		for offset = 0, math.min(cap, 100000) - 1 do
			local item = items[(head + offset - 1) % cap + 1]
			if item then ordered[#ordered + 1] = item end
		end
		items = ordered
		bucket._count, bucket._head, bucket._cap = #items, 1, #items
	end
	if kind == "channel" then rawset(bucket, "lines", items) end
	return damaged or normalized
end

function C.Budget(envelopes)
	local bytes, candidates = 0, {}
	for _, envelope in ipairs(envelopes) do
		bytes = bytes + #envelope.manifest
		for _, entry in ipairs(envelope.entries) do
			for _, block in ipairs(entry.blocks) do
				bytes = bytes + #block.data
				candidates[#candidates + 1] = { entry = entry, block = block }
			end
		end
	end
	local count = #candidates
	if bytes <= C.maxBytes and count <= C.maxBlocks then return {}, bytes, count end
	table.sort(candidates, function(a, b) return a.block.time < b.block.time end)
	local removed = {}
	for _, candidate in ipairs(candidates) do
		if bytes <= C.maxBytes and count <= C.maxBlocks then break end
		removed[candidate.block] = true
		bytes, count = bytes - #candidate.block.data, count - 1
	end
	for _, envelope in ipairs(envelopes) do
		for _, entry in ipairs(envelope.entries) do
			local keep = {}
			for _, block in ipairs(entry.blocks) do if not removed[block] then keep[#keep + 1] = block end end
			entry.blocks = keep
		end
	end
	assert(bytes <= C.maxBytes, "Chat history metadata exceeds storage budget")
	return removed, bytes, count
end
