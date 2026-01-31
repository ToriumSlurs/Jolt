--!strict
--!native
--!optimize 2
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Buffers = require("./Utils/Buffers")
local Remotes = require("./Utils/Remotes")

local Bridge = {}

local IS_SERVER = RunService:IsServer()
local FRAME_TIME = 1 / 60

type WriterMap = { [Player | string]: Buffers.Writer }

local ReliableMap: WriterMap = {}
local UnreliableMap: WriterMap = {}

local BroadcastReliable: Buffers.Writer? = nil
local BroadcastUnreliable: Buffers.Writer? = nil

local reliableRemote: RemoteEvent
local unreliableRemote: UnreliableRemoteEvent

local accumulator = 0
local HeartbeatConn: RBXScriptConnection?
local SERVER_KEY = "SERVER"

function Bridge.Initialize()
	if HeartbeatConn and HeartbeatConn.Connected then
		return
	end

	local group = if IS_SERVER then Remotes.Create() else Remotes.Get()
	reliableRemote = group.Reliable
	unreliableRemote = group.Unreliable

	if IS_SERVER then
		Players.PlayerRemoving:Connect(function(player)
			local w = ReliableMap[player]
			if w then
				Buffers.FreeWriter(w)
				ReliableMap[player] = nil
			end
			local uw = UnreliableMap[player]
			if uw then
				Buffers.FreeWriter(uw)
				UnreliableMap[player] = nil
			end
		end)
	end

	HeartbeatConn = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= FRAME_TIME then
			accumulator %= FRAME_TIME
			Bridge.FlushAll()
		end
	end)
end

local function finalizeAndCheck(w: Buffers.Writer, isUnreliable: boolean): (buffer, { Instance })
	local b, i = Buffers.Finalize(w)
	if isUnreliable and buffer.len(b) > 900 then
		warn(
			string.format(
				"[Jolt] Unreliable payload exceeds 900 bytes (size: %d). This may cause the packet to be dropped by the engine.",
				buffer.len(b)
			)
		)
	end
	return b, i
end

function Bridge.FlushAll()
	if not HeartbeatConn or not HeartbeatConn.Connected then
		return
	end

	if IS_SERVER then
		if BroadcastReliable then
			local w = BroadcastReliable
			BroadcastReliable = nil
			local b, i = Buffers.Finalize(w)
			reliableRemote:FireAllClients(b, i)
			Buffers.FreeWriter(w)
		end

		if BroadcastUnreliable then
			local w = BroadcastUnreliable
			BroadcastUnreliable = nil
			local b, i = finalizeAndCheck(w, true)
			unreliableRemote:FireAllClients(b, i)
			Buffers.FreeWriter(w)
		end

		for player, w in pairs(ReliableMap) do
			ReliableMap[player] = nil
			local b, i = Buffers.Finalize(w)
			reliableRemote:FireClient(player :: Player, b, i)
			Buffers.FreeWriter(w)
		end

		for player, w in pairs(UnreliableMap) do
			UnreliableMap[player] = nil
			local b, i = finalizeAndCheck(w, true)
			unreliableRemote:FireClient(player :: Player, b, i)
			Buffers.FreeWriter(w)
		end
	else
		local w = ReliableMap[SERVER_KEY]
		if w then
			ReliableMap[SERVER_KEY] = nil
			local b, i = Buffers.Finalize(w)
			reliableRemote:FireServer(b, i)
			Buffers.FreeWriter(w)
		end

		local uw = UnreliableMap[SERVER_KEY]
		if uw then
			UnreliableMap[SERVER_KEY] = nil
			local b, i = finalizeAndCheck(uw, true)
			unreliableRemote:FireServer(b, i)
			Buffers.FreeWriter(uw)
		end
	end
end

function Bridge.Writer(reliable: boolean, player: Player?): Buffers.Writer
	if not HeartbeatConn or not HeartbeatConn.Connected then
		Bridge.Initialize()
	end

	if IS_SERVER then
		if player then
			local map = if reliable then ReliableMap else UnreliableMap
			local w = map[player]
			if not w then
				w = Buffers.CreateWriter()
				map[player] = w
			end
			return w
		else
			if reliable then
				local w = BroadcastReliable
				if not w then
					w = Buffers.CreateWriter()
					BroadcastReliable = w
				end
				return w :: Buffers.Writer
			else
				local w = BroadcastUnreliable
				if not w then
					w = Buffers.CreateWriter()
					BroadcastUnreliable = w
				end
				return w :: Buffers.Writer
			end
		end
	else
		local map = if reliable then ReliableMap else UnreliableMap
		local w = map[SERVER_KEY]
		if not w then
			w = Buffers.CreateWriter()
			map[SERVER_KEY] = w
		end
		return w
	end
end

return Bridge
