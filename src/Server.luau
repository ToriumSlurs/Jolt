--!strict
local Server = {}
Server.__index = Server

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Buffers = require("./Utils/Buffers")
local Remotes = require("./Utils/Remotes")

local PACKET_EVENT = 1
local PACKET_REQUEST = 2
local PACKET_RESPONSE = 3

local task_spawn = task.spawn
local task_defer = task.defer
local table_remove = table.remove
local table_unpack = table.unpack

local GlobalInitialized = false
local Listeners = {} :: {[string]: (Player, ...any) -> ()}
local InvokeHandlers = {} :: {[string]: (Player, ...any) -> ...any}

local OutgoingReliable = {} :: {[Player]: Buffers.Writer}
local OutgoingUnreliable = {} :: {[Player]: Buffers.Writer}
local BroadcastReliable = nil :: Buffers.Writer?
local BroadcastUnreliable = nil :: Buffers.Writer?

local reliable: RemoteEvent
local unreliable: UnreliableRemoteEvent

local function FlushReliable(player: Player)
	local w = OutgoingReliable[player]
	if w then
		OutgoingReliable[player] = nil
		local b, i = Buffers.Finalize(w)
		reliable:FireClient(player, b, i)
		Buffers.FreeWriter(w)
	end
end

local function FlushUnreliable(player: Player)
	local w = OutgoingUnreliable[player]
	if w then
		OutgoingUnreliable[player] = nil
		local b, i = Buffers.Finalize(w)
		unreliable:FireClient(player, b, i)
		Buffers.FreeWriter(w)
	end
end

local function FlushBroadcastReliable()
	local w = BroadcastReliable
	if w then
		BroadcastReliable = nil
		local b, i = Buffers.Finalize(w)
		reliable:FireAllClients(b, i)
		Buffers.FreeWriter(w)
	end
end

local function FlushBroadcastUnreliable()
	local w = BroadcastUnreliable
	if w then
		BroadcastUnreliable = nil
		local b, i = Buffers.Finalize(w)
		unreliable:FireAllClients(b, i)
		Buffers.FreeWriter(w)
	end
end

local function Initialize()
	if GlobalInitialized then return end
	GlobalInitialized = true

	local group = Remotes.Create()
	reliable = group.Reliable
	unreliable = group.Unreliable

	local function onEvent(player: Player, b: buffer, i: {Instance})
		local r = Buffers.CreateReader(b, i)

		while r.cursor < r.len do
			local id = Buffers.ReadString(r)
			local type = Buffers.ReadU8(r)

			if type == PACKET_EVENT then
				local vals = Buffers.Unpack(r)
				local cb = Listeners[id]
				if cb then
					task_spawn(cb, player, table_unpack(vals))
				end
			elseif type == PACKET_REQUEST then
				local reqId = Buffers.ReadVarInt(r)
				local vals = Buffers.Unpack(r)
				local handler = InvokeHandlers[id]

				if handler then
					task_spawn(function()
						local results = {pcall(handler, player, table_unpack(vals))}
						local ok = results[1]
						table_remove(results, 1)

						local w = OutgoingReliable[player]
						if not w then
							w = Buffers.CreateWriter()
							OutgoingReliable[player] = w
							task_defer(FlushReliable, player)
						end

						Buffers.WriteString(w, id)
						Buffers.WriteU8(w, PACKET_RESPONSE)
						Buffers.WriteVarInt(w, reqId)
						Buffers.WriteU8(w, ok and 1 or 0)
						Buffers.Pack(w, table_unpack(results))
					end)
				end
			else
				break
			end
		end
		Buffers.FreeReader(r)
	end

	reliable.OnServerEvent:Connect(onEvent)
	unreliable.OnServerEvent:Connect(onEvent)
end

function Server.new(name: string)
	if not GlobalInitialized then
		Initialize()
	end

	local self = setmetatable({}, Server)
	self._id = name

	return self
end

function Server:Connect(callback: (Player, ...any) -> ())
	Listeners[self._id] = callback
	return {
		Disconnect = function()
			if Listeners[self._id] == callback then
				Listeners[self._id] = nil
			end
		end,
	}
end

function Server:Fire(player: Player, ...: any)
	local w = OutgoingReliable[player]
	if not w then
		w = Buffers.CreateWriter()
		OutgoingReliable[player] = w
		task_defer(FlushReliable, player)
	end

	Buffers.WriteString(w, self._id)
	Buffers.WriteU8(w, PACKET_EVENT)
	Buffers.Pack(w, ...)
end

function Server:FireUnreliable(player: Player, ...: any)
	local w = OutgoingUnreliable[player]
	if not w then
		w = Buffers.CreateWriter()
		OutgoingUnreliable[player] = w
		task_defer(FlushUnreliable, player)
	end

	Buffers.WriteString(w, self._id)
	Buffers.WriteU8(w, PACKET_EVENT)
	Buffers.Pack(w, ...)
end

function Server:FireAll(...: any)
	local w = BroadcastReliable
	if not w then
		w = Buffers.CreateWriter()
		BroadcastReliable = w
		task_defer(FlushBroadcastReliable)
	end

	Buffers.WriteString(w, self._id)
	Buffers.WriteU8(w, PACKET_EVENT)
	Buffers.Pack(w, ...)
end

function Server:FireAllUnreliable(...: any)
	local w = BroadcastUnreliable
	if not w then
		w = Buffers.CreateWriter()
		BroadcastUnreliable = w
		task_defer(FlushBroadcastUnreliable)
	end

	Buffers.WriteString(w, self._id)
	Buffers.WriteU8(w, PACKET_EVENT)
	Buffers.Pack(w, ...)
end

function Server:__newindex(k, v)
	if k == "OnInvoke" then
		InvokeHandlers[self._id] = v
	else
		rawset(self, k, v)
	end
end

return Server
