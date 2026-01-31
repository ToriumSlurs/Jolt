--!strict
--!native
--!optimize 2
local Client = {}
Client.__index = Client

local Buffers = require("./Utils/Buffers")
local Remotes = require("./Utils/Remotes")
local Signal = require("./Utils/Signal")
local Bridge = require("./Bridge")

local PACKET_EVENT = 1
local PACKET_REQUEST = 2
local PACKET_RESPONSE = 3
local REQUEST_TIMEOUT = 60

local task_spawn = task.spawn
local task_delay = task.delay
local task_cancel = task.cancel
local coroutine_running = coroutine.running
local coroutine_yield = coroutine.yield
local table_unpack = table.unpack

type Request = { thread: thread, timer: thread }

type InternalClient = {
	_id: string,
	_signal: Signal.Signal,
	_requests: { [number]: Request },
	_requestIdCounter: number,
	OnInvoke: ((...any) -> ...any)?,
}

local ReliableConn: RBXScriptConnection?
local UnreliableConn: RBXScriptConnection?
local Instances: { [string]: InternalClient } = {}

local reliable: RemoteEvent
local unreliable: UnreliableRemoteEvent

local function Initialize()
	if ReliableConn and ReliableConn.Connected then
		return
	end

	Bridge.Initialize()
	local group = Remotes.Get()
	reliable = group.Reliable
	unreliable = group.Unreliable

	local function dispatch(id: string, args: { any }, count: number)
		local packetType = args[1]
		local instance = Instances[id]
		if not instance then
			return
		end

		if packetType == PACKET_EVENT then
			instance._signal:Fire(table_unpack(args, 2, count))
		elseif packetType == PACKET_REQUEST then
			local reqId = args[2]
			local handler = instance.OnInvoke
			if handler then
				task_spawn(function()
					local results = table.pack(pcall(handler, table_unpack(args, 3, count)))
					local ok = results[1]

					local w = Bridge.Writer(true)
					Buffers.WriteString(w, id)

					local n = (if ok then results.n - 1 else 1) + 2
					Buffers.WritePacketHeader(w, PACKET_RESPONSE, n)

					Buffers.WriteAny(w, reqId)
					Buffers.WriteAny(w, ok)

					if ok then
						for i = 2, results.n do
							Buffers.WriteAny(w, results[i])
						end
					else
						Buffers.WriteAny(w, results[2])
					end
				end)
			end
		elseif packetType == PACKET_RESPONSE then
			local reqId = args[2]
			local ok = args[3] == true or args[3] == 1

			local req = instance._requests[reqId]
			if req and coroutine.status(req.thread) ~= "dead" then
				instance._requests[reqId] = nil
				task_cancel(req.timer)
				task_spawn(req.thread, ok, table_unpack(args, 4, count))
			elseif req then
				instance._requests[reqId] = nil
				task_cancel(req.timer)
			end
		end
	end

	local function onEvent(b: buffer, i: { Instance })
		local r = Buffers.CreateReader(b, i)

		local success, err = pcall(function()
			while r.cursor < r.len do
				local id = Buffers.ReadString(r)
				local packetType, argCount = Buffers.ReadPacketHeader(r)

				local args = table.create(argCount + 1)
				args[1] = packetType
				for k = 1, argCount do
					args[k + 1] = Buffers.ReadAny(r)
				end

				dispatch(id, args, argCount + 1)
			end
		end)

		Buffers.FreeReader(r)

		if not success then
			warn("Jolt: Error processing network packet: " .. tostring(err))
		end
	end

	ReliableConn = reliable.OnClientEvent:Connect(onEvent)
	UnreliableConn = unreliable.OnClientEvent:Connect(onEvent)
end

function Client.new(name: string): any
	if not ReliableConn or not ReliableConn.Connected then
		Initialize()
	end

	if Instances[name] then
		return Instances[name]
	end

	local self = setmetatable({
		_id = name,
		_signal = Signal.new(),
		_requests = {},
		_requestIdCounter = 0,
		OnInvoke = nil,
	}, Client)

	Instances[name] = self :: any
	return self
end

function Client:Connect(callback: (...any) -> ())
	if typeof(self) ~= "table" or not (self :: any)._id then
		error("Jolt: Client method must be called with ':' (e.g., event:Connect(callback))", 2)
	end
	return (self :: any)._signal:Connect(callback)
end

function Client:Once(callback: (...any) -> ())
	if typeof(self) ~= "table" or not (self :: any)._id then
		error("Jolt: Client method must be called with ':' (e.g., event:Once(callback))", 2)
	end
	return (self :: any)._signal:Once(callback)
end

function Client:Wait()
	if typeof(self) ~= "table" or not (self :: any)._id then
		error("Jolt: Client method must be called with ':' (e.g., event:Wait())", 2)
	end
	return (self :: any)._signal:Wait()
end

local function Send(internal: InternalClient, isReliable: boolean, packetType: number, ...: any)
	local id = internal._id
	local w = Bridge.Writer(isReliable)

	Buffers.WriteString(w, id)

	local n = select("#", ...)
	Buffers.WritePacketHeader(w, packetType, n)

	for i = 1, n do
		Buffers.WriteAny(w, select(i, ...))
	end
end

function Client:Fire(...: any)
	if typeof(self) ~= "table" or not (self :: any)._id then
		error("Jolt: Client method must be called with ':' (e.g., event:Fire(...))", 2)
	end
	Send(self :: any, true, PACKET_EVENT, ...)
end

function Client:FireUnreliable(...: any)
	if typeof(self) ~= "table" or not (self :: any)._id then
		error("Jolt: Client method must be called with ':' (e.g., event:FireUnreliable(...))", 2)
	end
	Send(self :: any, false, PACKET_EVENT, ...)
end

function Client:Invoke(...: any)
	if typeof(self) ~= "table" or not (self :: any)._id then
		error("Jolt: Client method must be called with ':' (e.g., event:Invoke(...))", 2)
	end
	local internal: InternalClient = self :: any
	local reqId = internal._requestIdCounter
	internal._requestIdCounter += 1

	Send(internal, true, PACKET_REQUEST, reqId, ...)

	local thread = coroutine_running()
	local timer = task_delay(REQUEST_TIMEOUT, function()
		if internal._requests[reqId] and internal._requests[reqId].thread == thread then
			internal._requests[reqId] = nil
			if coroutine.status(thread) ~= "dead" then
				task_spawn(thread, false, "Request timed out")
			end
		end
	end)

	internal._requests[reqId] = { thread = thread, timer = timer }

	local results = table.pack(coroutine_yield())
	local success = results[1]

	if not success then
		error(tostring(results[2]))
	end

	return table_unpack(results, 2, results.n)
end

return Client
