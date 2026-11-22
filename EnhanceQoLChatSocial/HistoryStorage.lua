local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.variables = addon.variables or {}
local C = addon.ChatHistoryCodec
local S = { states = setmetatable({}, { __mode = "k" }), imGeneration = 0, clock = 0, revision = 0, savedRevision = -1, manifests = {}, readCache = {}, readBytes = 0, readCount = 0 }
addon.ChatHistoryStorage = S
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

function S.MarkChannelDirty(bucket, index)
	S.MarkChanged()
	local state = S.states[bucket]
	if state then
		S.clock = S.clock + 1
		state.generation, state.access = state.generation + 1, S.clock
		if index and not state.fullDirty then
			state.dirty = state.dirty or {}
			state.dirty[index] = true
		else
			state.fullDirty, state.dirty = true, nil
		end
	end
end

-- A normalized ring can accept a complete new record without loading the record
-- it replaces. Keep cold writes separate from the immutable archived blocks.
function S.AppendChannelSlot(bucket, cap)
	local state = S.states[bucket]
	if not state or not state.sparseSafe or not bucket._cap or bucket._cap < cap or not bucket._head or not bucket._count or bucket._count > cap or cap <= 0 then return false end
	local index = (bucket._head + bucket._count - 1) % bucket._cap + 1
	S.MarkChannelDirty(bucket, index)
	local slot = {}
	local lines = rawget(bucket, "lines")
	if lines then
		lines[index] = slot
	else
		state.writes = state.writes or {}
		state.writes[index] = slot
	end
	if bucket._count < cap then
		bucket._count = bucket._count + 1
	else
		if bucket._cap > cap then
			if lines then lines[bucket._head] = nil elseif state.writes then state.writes[bucket._head] = nil end
		end
		bucket._head = bucket._head % bucket._cap + 1
	end
	return true, slot
end

function S.ResizeChannel(bucket, cap)
	local state = S.states[bucket]
	if not state or not bucket._cap or not bucket._head or bucket._count == nil or cap < 0 then return false end
	local growing = cap > bucket._cap
	if not growing and not state.sparseSafe then return false end
	-- A suspended writer owns metadata from before this resize. Its completed
	-- blocks remain valid, but its unpublished envelope must never be resumed.
	S.worker = nil
	frame:SetScript("OnUpdate", nil)
	local history = addon.ChatIM.ChannelHistory
	if history.CancelHistoryView then history:CancelHistoryView() end
	if not getmetatable(bucket) then S.Bind(bucket, state) end
	if growing then
		if not state.sparseSafe or bucket._head + bucket._count - 1 > bucket._cap then
			-- Freeze the old coordinates. New messages use the larger canonical
			-- ring immediately; decoding/repacking the old records is deferred.
			state.rebaseSource = S.FreezeSource(bucket, state)
			state.writes, state.dirty, state.fullDirty = nil, nil, nil
			rawset(bucket, "lines", nil)
			bucket._head = 1
		end
		bucket._cap = cap
		state.sparseSafe = true
	end
	local count = math.min(bucket._count, cap)
	if bucket._cap > 0 then bucket._head = (bucket._head + bucket._count - count - 1) % bucket._cap + 1 end
	bucket._count = count
	if cap == 0 then bucket._cap, bucket._head, state.rebaseSource = 0, 1, nil end
	local lines = rawget(bucket, "lines")
	for _, values in pairs({ lines = lines, writes = state.writes, dirty = state.dirty }) do
		for index in pairs(values) do if type(index) == "number" and not C.IsActive(bucket, index) then values[index] = nil end end
	end
	if not state.rebaseSource then
		local blocks = {}
		for _, block in ipairs(state.blocks or {}) do if C.ActiveCount(bucket, block.first, block.count) > 0 then blocks[#blocks + 1] = block end end
		state.blocks = blocks
	end
	S.clock = S.clock + 1
	state.generation, state.access, state.trim = state.generation + 1, S.clock, true
	S.MarkChanged()
	history.runtime = history.runtime or {}
	history.runtime.eqolIndex = nil
	return true
end

-- Sources are runtime-only views, never part of the SavedVariables manifest.
-- Detached sources retain their old ring and overlays until conversion finishes.
function S.FreezeSource(bucket, state, snapshot)
	local source = C.Copy(bucket, { [bucket] = true })
	local writes = state.writes
	if snapshot and writes then writes = C.Copy(writes, {}) end
	S.states[source] = { blocks = state.blocks, writes = writes, info = state.info, rebaseSource = state.rebaseSource, frozen = true }
	local lines = rawget(bucket, "lines")
	if lines then rawset(source, "lines", snapshot and C.Copy(lines, {}) or lines) end
	return source
end

function S.RestoreRebase(bucket)
	local lines = {}
	for position = 1, bucket._count do
		local index = (bucket._head + position - 2) % bucket._cap + 1
		local line = S.ReadLine(bucket, index)
		if line then lines[index] = C.Copy(line, {}) end
	end
	rawset(bucket, "lines", lines)
	S.states[bucket].writes = nil
	return lines
end

function S.EncodeRebase(bucket, state, pause)
	local snapshot = C.Copy(bucket, { [bucket] = true })
	local source = S.FreezeSource(bucket, state, true)
	local lines = {}
	for position = 1, snapshot._count do
		local index = (snapshot._head + position - 2) % snapshot._cap + 1
		local line = S.ReadLine(source, index, pause)
		if line then lines[#lines + 1] = C.Copy(line, {}) end
		if pause and position % C.writeBlockLines == 0 then pause() end
	end
	snapshot.lines, snapshot._head, snapshot._count = lines, 1, #lines
	return snapshot, C.EncodeLines(snapshot, "channel", nil, pause)
end

function S.MarkIMDirty()
	S.imGeneration = S.imGeneration + 1
	S.MarkChanged()
end

function S.MarkChanged()
	S.revision = S.revision + 1
	S.Schedule()
end

function S.CancelTimer()
	if S.timer then S.timer:Cancel(); S.timer = nil end
end

function S.Schedule()
	if not addon.variables.chatSocialSavedVariablesReady or S.worker or S.timer or S.savedRevision == S.revision then return end
	S.timer = C_Timer.NewTimer(15, function()
		S.timer = nil
		if S.savedRevision ~= S.revision then S.StartWorker() end
	end)
end

function S.OnUpdate() S.Step() end

function S.StartWorker()
	if S.worker then return end
	S.CancelTimer()
	S.lastError = nil
	S.worker = coroutine.create(function() S.Build(coroutine.yield) end)
	frame:SetScript("OnUpdate", S.OnUpdate)
end

function S.ReadClock() return debugprofilestop() end

function S.ReadCheckpoint(force)
	if S.readerThread and coroutine.running() == S.readerThread and (force or S.ReadClock() >= S.readDeadline) then coroutine.yield() end
end

function S.TrimReadCache()
	while S.readCount > C.readCacheBlocks or S.readBytes > C.readCacheBytes do
		local oldestData, oldest
		for data, entry in pairs(S.readCache) do
			if not oldest or entry.access < oldest.access then oldestData, oldest = data, entry end
		end
		if not oldest then return end
		S.readCache[oldestData] = nil
		S.readCount, S.readBytes = S.readCount - 1, S.readBytes - oldest.bytes
	end
end

function S.ReadBlock(block, pause)
	if type(block) ~= "table" or type(block.data) ~= "string" then return nil end
	S.clock = S.clock + 1
	local entry = S.readCache[block.data]
	if entry then entry.access = S.clock; return entry.payload or nil end
	local ok, payload, raw = pcall(C.Unpack, block.data)
	if not ok or not payload or type(payload.first) ~= "number" or payload.first < 1 or payload.first % 1 ~= 0 or type(payload.items) ~= "table" or #payload.items > C.blockLines then payload, raw = nil, nil end
	entry = { payload = payload or false, bytes = raw and #raw or 0, access = S.clock }
	S.readCache[block.data] = entry
	S.readCount, S.readBytes = S.readCount + 1, S.readBytes + entry.bytes
	S.TrimReadCache()
	-- At most one newly decoded message block per reader continuation.
	S.ReadCheckpoint(true)
	if pause then pause() end
	return payload
end

function S.ReadLine(bucket, index, pause)
	S.ReadCheckpoint(false)
	if not C.IsActive(bucket, index) then return end
	local state = S.states[bucket]
	if state and state.writes and state.writes[index] then return state.writes[index] end
	local lines = rawget(bucket, "lines")
	if lines then return lines[index] end
	if not state then return bucket.lines and bucket.lines[index] end
	if state.rebaseSource then
		local source = state.rebaseSource
		if index > source._count then return end
		local item = S.ReadLine(source, (source._head + index - 2) % source._cap + 1, pause)
		if C.IsActive(bucket, index) then return item end
		return
	end
	state.info = state.info or {}
	for _, block in ipairs(state.blocks) do
		local info = state.info[block.data] or block
		local payload
		if not C.HasRange(info) then
			payload = S.ReadBlock(block, pause)
			if payload then
				info = C.BlockInfo(block, payload)
				state.info[block.data] = info
				if info ~= block and not state.frozen then S.MarkChanged() end
			end
		end
		if C.HasRange(info) and index >= info.first and index < info.first + info.count then
			payload = payload or S.ReadBlock(block, pause)
			if not C.IsActive(bucket, index) then return end
			local item = payload and payload.items[index - payload.first + 1]
			return type(item) == "table" and item or nil
		end
	end
end

function S.LatestTime(bucket)
	local state = S.states[bucket]
	if not state or state.generation ~= state.savedGeneration then return math.huge end
	local latest = 0
	for _, block in ipairs(state.blocks) do
		local info = state.info and state.info[block.data] or block
		if type(info.latest) ~= "number" then return math.huge end
		latest = math.max(latest, info.latest)
	end
	return latest
end

function S.HasCompleteRanges(bucket, blocks)
	local count, last = 0, 0
	for _, block in ipairs(blocks) do
		if not C.HasRange(block) or block.first <= last then return false end
		count = count + C.ActiveCount(bucket, block.first, block.count)
		last = block.first + block.count - 1
	end
	return count == bucket._count
end

function S.Attach(bucket, blocks)
	local state = { blocks = blocks, generation = 0, savedGeneration = 0, access = 0, sparseSafe = S.HasCompleteRanges(bucket, blocks) }
	S.states[bucket] = state
	return S.Bind(bucket, state)
end

function S.Bind(bucket, state)
	setmetatable(bucket, { __index = function(_, key)
		if key ~= "lines" then return end
		S.clock = S.clock + 1
		state.access = S.clock
		if state.rebaseSource then return S.RestoreRebase(bucket) end
		local damaged = C.Restore(bucket, "channel", state.blocks, state.writes)
		state.writes = nil
		if damaged then state.sparseSafe = false; S.MarkChannelDirty(bucket) end
		return rawget(bucket, "lines")
	end })
	return state
end

function S.ChannelSnapshot(bucket, state)
	if state.fullDirty or (not state.dirty and not state.trim) or not state.blocks then return end
	for _, block in ipairs(state.blocks) do
		if not C.HasRange(block) then return end
	end
	local changes = {}
	for index in pairs(state.dirty or {}) do
		if C.IsActive(bucket, index) then
			local line = S.ReadLine(bucket, index)
			if type(line) ~= "table" then return end
			changes[index] = C.Copy(line, {})
		end
	end
	return changes
end

function S.Decode(saved, kind)
	if saved.format == nil then return saved end
	assert(saved.format == C.version, "Unsupported chat history storage version")
	local manifest = C.Unpack(saved.manifest)
	assert(manifest and type(manifest.root) == "table" and type(manifest.paths) == "table" and type(saved.entries) == "table", "Invalid chat history manifest")
	assert(#manifest.paths <= 2048 and #saved.entries == #manifest.paths, "Invalid chat history stream count")
	S.manifests[kind] = { value = C.Copy(manifest, {}), data = saved.manifest }
	local root = manifest.root
	for index, path in ipairs(manifest.paths) do
		assert(type(path) == "table" and #path == (kind == "im" and 1 or 6), "Invalid chat history path")
		local bucket, entry = C.At(root, path), saved.entries[index]
		assert(type(bucket) == "table" and type(entry) == "table" and type(entry.blocks) == "table", "Invalid chat history stream")
		if kind == "channel" then
			S.Attach(bucket, entry.blocks)
		else
			local damaged = C.Restore(bucket, kind, entry.blocks)
			S.states[bucket] = { blocks = entry.blocks, savedGeneration = damaged and -1 or S.imGeneration }
		end
	end
	return root
end

function S.TrimStreams(root, kind)
	local streams = C.Streams(root, kind)
	if #streams > 2048 then
		table.sort(streams, function(a, b) return (a.bucket.lastUpdated or (a.bucket.timestamps and a.bucket.timestamps[#a.bucket]) or 0) > (b.bucket.lastUpdated or (b.bucket.timestamps and b.bucket.timestamps[#b.bucket]) or 0) end)
		for index = #streams, 2049, -1 do
			local path, parent = streams[index].path, root
			for part = 1, #path - 1 do parent = parent[path[part]] end
			parent[path[#path]] = nil
			if kind == "channel" and next(parent) == nil then
				local realms = root[path[1]]
				local realm = realms[path[2]]
				realm.characters[path[4]] = nil
				if next(realm.characters) == nil then realms[path[2]] = nil end
				if next(realms) == nil then root[path[1]] = nil end
			end
			streams[index] = nil
		end
	end
	return streams
end

function S.EvictCache()
	local cached = {}
	for bucket, state in pairs(S.states) do
		if not state.frozen and state.generation and rawget(bucket, "lines") and state.savedGeneration == state.generation then cached[#cached + 1] = { bucket = bucket, state = state } end
	end
	table.sort(cached, function(a, b) return (a.state.access or 0) > (b.state.access or 0) end)
	for index = C.cacheLimit + 1, #cached do rawset(cached[index].bucket, "lines", nil) end
	if #cached > C.cacheLimit then addon.ChatIM.ChannelHistory.runtime.eqolIndex = nil end
end

function S.Build(pause)
	local revision = S.revision
	local envelopes, pending, manifests = {}, {}, {}
	for index, kind in ipairs({ "im", "channel" }) do
		local root = kind == "im" and addon.ChatIM.history or addon.ChatIM.ChannelHistory.history
		local streams, leaves = S.TrimStreams(root, kind), {}
		for _, stream in ipairs(streams) do leaves[stream.bucket] = true end
		local skeleton, paths, entries = C.Copy(root, leaves), {}, {}
		for _, stream in ipairs(streams) do
			local bucket = stream.bucket
			local state = S.states[bucket]
			if not state then
				state = { generation = kind == "channel" and 0 or nil }
				S.states[bucket] = state
			end
			local generation = kind == "im" and S.imGeneration or state.generation
			local snapshot = bucket
			local rebased = kind == "channel" and state.rebaseSource ~= nil
			local encoded
			if rebased then
				snapshot, encoded = S.EncodeRebase(bucket, state, pause)
			elseif state.savedGeneration ~= generation then
				-- A bounded stream snapshot lets compression yield between blocks while
				-- incoming messages continue changing the live ring independently.
				local changes = kind == "channel" and S.ChannelSnapshot(bucket, state)
				if changes then
					snapshot = C.Copy(bucket, { [bucket] = true })
					local blocks = C.EncodeChanges(changes, state.blocks, pause, S.ReadBlock, snapshot)
					if blocks then state.blocks = blocks else changes = nil end
				end
				if not changes then
					if kind == "channel" then local _ = bucket.lines end
					snapshot = C.Copy(bucket, {})
					state.blocks = C.EncodeLines(snapshot, kind, state.blocks, pause)
				end
				state.savedGeneration = generation
				if kind == "channel" then state.sparseSafe = S.HasCompleteRanges(snapshot, state.blocks) end
				if kind == "channel" and state.generation == generation then state.dirty, state.fullDirty, state.writes, state.trim = nil, nil, nil, nil end
			end
			local snapshotLeaves = { [snapshot] = true }
			local copy, parent = C.Copy(snapshot, snapshotLeaves), skeleton
			for part = 1, #stream.path - 1 do parent = parent[stream.path[part]] end
			parent[stream.path[#stream.path]] = copy
			paths[#paths + 1] = stream.path
			local blocks = {}
			for blockIndex, block in ipairs(encoded or state.blocks) do
				-- Persist only indexes learned through actual reads. Idle saves must
				-- never deserialize an old archive merely to enrich its metadata.
				blocks[blockIndex] = not rebased and state.info and state.info[block.data] or block
			end
			local entry = { blocks = blocks }
			entries[#entries + 1] = entry
			pending[#pending + 1] = { bucket = bucket, state = state, entry = entry, kind = kind, beforeBudget = blocks, rebased = rebased, snapshot = snapshot, generation = generation }
			if pause then pause() end
		end
		local value = { root = skeleton, paths = paths }
		local previous = S.manifests[kind]
		local manifest
		if previous and C.Same(previous.value, value) then
			manifest = previous.data
		else
			-- Stored DEFLATE blocks retain format compatibility. Spread manifest
			-- serialization and verification across continuations as for messages.
			local raw
			manifest, raw = C.Pack(value, 0, pause)
			assert(#raw <= C.maxManifest, "Chat history manifest exceeds metadata budget")
		end
		manifests[kind] = { value = value, data = manifest }
		envelopes[index] = { format = C.version, manifest = manifest, entries = entries }
	end
	local removed, bytes, blocks = C.Budget(envelopes)
	-- A trimmed snapshot cannot invalidate a newer live ring by its old physical
	-- indexes. Retry from that ring on the next pass (or synchronous logout flush).
	for _, item in ipairs(pending) do
		local generation = item.kind == "im" and S.imGeneration or item.state.generation
		if item.generation ~= generation then
			for _, block in ipairs(item.beforeBudget) do if removed[block] then return end end
		end
	end
	-- Publish only fully encoded and verified snapshots. Runtime tables never enter SV.
	_G.EnhanceQoL_IMHistory, _G.EnhanceQoL_ChannelHistory = envelopes[1], envelopes[2]
	if S.privateDB then S.privateDB.chatSocialHistoryMigration = nil end
	S.bytes, S.blocks, S.manifests = bytes, blocks, manifests
	for _, item in ipairs(pending) do
		local changed = false
		for _, block in ipairs(item.beforeBudget) do if removed[block] then changed = true; break end end
		if item.rebased and item.state.generation == item.generation then
			-- Install the new coordinates only if the live ring still matches the
			-- snapshot. Otherwise retain its frozen source and newer writes for retry.
			item.bucket._cap, item.bucket._head, item.bucket._count = item.snapshot._cap, item.snapshot._head, item.snapshot._count
			rawset(item.bucket, "lines", item.snapshot.lines)
			item.state.rebaseSource, item.state.writes, item.state.dirty, item.state.fullDirty, item.state.trim = nil, nil, nil, nil, nil
			item.state.savedGeneration = item.generation
			item.state.sparseSafe = S.HasCompleteRanges(item.snapshot, item.entry.blocks)
		end
		if not item.rebased or item.state.generation == item.generation then
			item.state.blocks = item.entry.blocks
			if changed and item.state.savedGeneration == (item.kind == "im" and S.imGeneration or item.state.generation) then
				if item.kind == "im" then
					C.Restore(item.bucket, "im", item.state.blocks)
				else
					rawset(item.bucket, "lines", nil)
					item.state.writes, item.state.dirty = nil, nil
					item.state.sparseSafe = false
				end
			end
			if item.kind == "channel" and not getmetatable(item.bucket) then
				S.Bind(item.bucket, item.state)
			end
		end
	end
	addon.ChatIM.ChannelHistory.runtime = addon.ChatIM.ChannelHistory.runtime or {}
	addon.ChatIM.ChannelHistory.runtime.eqolIndex = nil
	S.EvictCache()
	S.savedRevision = revision
end

function S.Report(message)
	S.lastError = tostring(message)
	if geterrorhandler then geterrorhandler()(S.lastError) end
end

function S.Step()
	if not S.worker then return end
	local ok, message = coroutine.resume(S.worker)
	if not ok then
		S.worker = nil
		S.Report(message)
	elseif coroutine.status(S.worker) == "dead" then
		S.worker = nil
	end
	if not S.worker then frame:SetScript("OnUpdate", nil); S.Schedule() end
end

function S.Flush()
	S.CancelTimer()
	S.lastError = nil
	while S.worker do
		S.Step()
		if S.lastError then return false, S.lastError end
	end
	S.CancelTimer()
	frame:SetScript("OnUpdate", nil)
	S.lastError = nil
	local ok, message = pcall(S.Build)
	if not ok then S.Report(message) end
	S.Schedule()
	return ok, message
end

-- Called after the central loader returns, or by ADDON_LOADED for other loaders.
-- A listener created while Core handles ADDON_LOADED can miss the nested event.
function addon.functions.InitializeChatSocialHistory()
	if addon.variables.chatSocialSavedVariablesReady then return end
	local privateDB = addon.functions.GetPrivateDB()
	local legacy = privateDB.chatSocialHistoryMigration
	local im = type(_G.EnhanceQoL_IMHistory) == "table" and _G.EnhanceQoL_IMHistory or type(legacy) == "table" and legacy.EnhanceQoL_IMHistory or {}
	local channel = type(_G.EnhanceQoL_ChannelHistory) == "table" and _G.EnhanceQoL_ChannelHistory or type(legacy) == "table" and legacy.EnhanceQoL_ChannelHistory or {}
	-- Decode both before changing runtime ownership or removing a staged migration.
	local runtimeIM, runtimeChannel = S.Decode(im, "im"), S.Decode(channel, "channel")
	addon.ChatIM.history, addon.ChatIM.ChannelHistory.history = runtimeIM, runtimeChannel
	S.privateDB = privateDB
	addon.variables.chatSocialSavedVariablesReady = true
	frame:UnregisterEvent("ADDON_LOADED")
	frame:RegisterEvent("PLAYER_LOGOUT")
	addon.functions.InitChatSocial()
	S.StartWorker()
end

frame:SetScript("OnEvent", function(_, event, loadedAddon)
	if event == "PLAYER_LOGOUT" then
		S.Flush()
	elseif loadedAddon == addonName then
		addon.functions.InitializeChatSocialHistory()
	end
end)
