--!strict
local Client = {}
Client.__index = Client

local RunService = game:GetService("RunService")
local Buffers = require("./Utils/Buffers")
local Remotes = require("./Utils/Remotes")

local PACKET_EVENT = 1
local PACKET_REQUEST = 2
local PACKET_RESPONSE = 3
local REQUEST_TIMEOUT = 60

local task_spawn = task.spawn
local task_delay = task.delay
local coroutine_running = coroutine.running
local coroutine_yield = coroutine.yield
local table_unpack = table.unpack

local GlobalInitialized = false
local Listeners = {} :: {[string]: (...any) -> ()}
local Requests = {} :: {[string]: {[number]: thread}}
local RequestIdCounters = {} :: {[string]: number}

local OutgoingReliable = nil :: Buffers.Writer?
local OutgoingUnreliable = nil :: Buffers.Writer?

local function Initialize()
	if GlobalInitialized then return end
	GlobalInitialized = true

	local group = Remotes.Get()
	local reliable = group.Reliable
	local unreliable = group.Unreliable

	RunService.PostSimulation:Connect(function()
		if OutgoingReliable then
			local b, i = Buffers.Finalize(OutgoingReliable)
			reliable:FireServer(b, i)
			Buffers.FreeWriter(OutgoingReliable)
			OutgoingReliable = nil
		end

		if OutgoingUnreliable then
			local b, i = Buffers.Finalize(OutgoingUnreliable)
			unreliable:FireServer(b, i)
			Buffers.FreeWriter(OutgoingUnreliable)
			OutgoingUnreliable = nil
		end
	end)

	local function onEvent(b: buffer, i: {Instance})
		local r = Buffers.CreateReader(b, i)

		while r.cursor < r.len do
			local id = Buffers.ReadString(r)
			local type = Buffers.ReadU8(r)

			if type == PACKET_EVENT then
				local vals = Buffers.Unpack(r)
				local cb = Listeners[id]
				if cb then
					task_spawn(cb, table_unpack(vals))
				end
			elseif type == PACKET_RESPONSE then
				local reqId = Buffers.ReadVarInt(r)
				local ok = Buffers.ReadU8(r) == 1
				local vals = Buffers.Unpack(r)

				local channelRequests = Requests[id]
				if channelRequests then
					local thread = channelRequests[reqId]
					if thread then
						channelRequests[reqId] = nil
						task_spawn(thread, ok, table_unpack(vals))
					end
				end
			else
				break
			end
		end
		Buffers.FreeReader(r)
	end

	reliable.OnClientEvent:Connect(onEvent)
	unreliable.OnClientEvent:Connect(onEvent)
end

function Client.new(name: string)
	if not GlobalInitialized then
		Initialize()
	end

	local self = setmetatable({}, Client)
	self._id = name

	if not Requests[name] then
		Requests[name] = {}
		RequestIdCounters[name] = 0
	end

	return self
end

function Client:Connect(callback: (...any) -> ())
	Listeners[self._id] = callback
	return {
		Disconnect = function()
			if Listeners[self._id] == callback then
				Listeners[self._id] = nil
			end
		end,
	}
end

function Client:Fire(...: any)
	local w = OutgoingReliable
	if not w then
		w = Buffers.CreateWriter()
		OutgoingReliable = w
	end

	Buffers.WriteString(w, self._id)
	Buffers.WriteU8(w, PACKET_EVENT)
	Buffers.Pack(w, ...)
end

function Client:FireUnreliable(...: any)
	local w = OutgoingUnreliable
	if not w then
		w = Buffers.CreateWriter()
		OutgoingUnreliable = w
	end

	Buffers.WriteString(w, self._id)
	Buffers.WriteU8(w, PACKET_EVENT)
	Buffers.Pack(w, ...)
end

function Client:Invoke(...: any)
	local id = RequestIdCounters[self._id]
	RequestIdCounters[self._id] += 1

	local w = OutgoingReliable
	if not w then
		w = Buffers.CreateWriter()
		OutgoingReliable = w
	end

	Buffers.WriteString(w, self._id)
	Buffers.WriteU8(w, PACKET_REQUEST)
	Buffers.WriteVarInt(w, id)
	Buffers.Pack(w, ...)

	local thread = coroutine_running()
	Requests[self._id][id] = thread

	task_delay(REQUEST_TIMEOUT, function()
		if Requests[self._id][id] == thread then
			Requests[self._id][id] = nil
			task_spawn(thread, false, "Request timed out")
		end
	end)

	local success, result = coroutine_yield()

	if not success then
		error(result)
	end

	return result
end

return Client
