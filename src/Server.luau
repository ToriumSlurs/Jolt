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
local table_remove = table.remove
local table_unpack = table.unpack
local table_clear = table.clear

local GlobalInitialized = false
local Listeners = {} :: {[string]: (Player, ...any) -> ()}
local InvokeHandlers = {} :: {[string]: (Player, ...any) -> ...any}
local ActiveInstances = setmetatable({}, {__mode = "k"})

local OutgoingReliable = {} :: {[Player]: Buffers.Writer}
local OutgoingUnreliable = {} :: {[Player]: Buffers.Writer}

local BroadcastReliable = nil :: Buffers.Writer?
local BroadcastUnreliable = nil :: Buffers.Writer?

local function Initialize()
	if GlobalInitialized then return end
	GlobalInitialized = true

	local group = Remotes.Create()
	local reliable = group.Reliable
	local unreliable = group.Unreliable

	RunService.Heartbeat:Connect(function()
		for p, w in pairs(OutgoingReliable) do
			local b, i = Buffers.Finalize(w)
			reliable:FireClient(p, b, i)
			Buffers.FreeWriter(w)
		end
		
		table_clear(OutgoingReliable)

		for p, w in pairs(OutgoingUnreliable) do
			local b, i = Buffers.Finalize(w)
			unreliable:FireClient(p, b, i)
			Buffers.FreeWriter(w)
		end
		table_clear(OutgoingUnreliable)

		if BroadcastReliable then
			local b, i = Buffers.Finalize(BroadcastReliable)
			reliable:FireAllClients(b, i)
			Buffers.FreeWriter(BroadcastReliable)
			BroadcastReliable = nil
		end

		if BroadcastUnreliable then
			local b, i = Buffers.Finalize(BroadcastUnreliable)
			unreliable:FireAllClients(b, i)
			Buffers.FreeWriter(BroadcastUnreliable)
			BroadcastUnreliable = nil
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if OutgoingReliable[player] then
			Buffers.FreeWriter(OutgoingReliable[player])
			OutgoingReliable[player] = nil
		end
		if OutgoingUnreliable[player] then
			Buffers.FreeWriter(OutgoingUnreliable[player])
			OutgoingUnreliable[player] = nil
		end
	end)

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
