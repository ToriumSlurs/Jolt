--!strict
--!native
--!optimize 2

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local IS_SERVER = RunService:IsServer()

local Buffers = require(script.Parent.Utils.Buffers)
local Remotes = require(script.Parent.Utils.Remotes)

local Buffers_CreateWriter = Buffers.CreateWriter
local Buffers_FreeWriter = Buffers.FreeWriter
local Buffers_Finalize = Buffers.Finalize
local table_clear = table.clear

local Bridge = {}

local reliablePlayerWriters: { [Player]: Buffers.Writer } = {}
local unreliablePlayerWriters: { [Player]: Buffers.Writer } = {}
local broadcastReliableWriter: Buffers.Writer? = nil
local broadcastUnreliableWriter: Buffers.Writer? = nil

local clientReliableWriter: Buffers.Writer? = nil
local clientUnreliableWriter: Buffers.Writer? = nil

local reliableRemote: RemoteEvent
local unreliableRemote: UnreliableRemoteEvent
local frameConnection: RBXScriptConnection?
local playerRemovingConnection: RBXScriptConnection?

local isInitializing = false

function Bridge.Initialize()
	if (frameConnection and frameConnection.Connected) or isInitializing then
		return
	end
	isInitializing = true

	local remoteGroup = if IS_SERVER then Remotes.Create() else Remotes.Get()

	if frameConnection and frameConnection.Connected then
		isInitializing = false
		return
	end

	reliableRemote = remoteGroup.Reliable
	unreliableRemote = remoteGroup.Unreliable
	frameConnection = RunService.Heartbeat:Connect(Bridge.FlushAll)

	if IS_SERVER and not playerRemovingConnection then
		playerRemovingConnection = Players.PlayerRemoving:Connect(Bridge.FlushPlayer)
	end

	isInitializing = false
end

function Bridge.FlushPlayer(player: Player)
	local relWriter = reliablePlayerWriters[player]
	if relWriter ~= nil then
		reliablePlayerWriters[player] = nil
		if relWriter.cursor > 0 and reliableRemote and player.Parent ~= nil and player:IsDescendantOf(Players) then
			local packetBuffer, instances = Buffers_Finalize(relWriter)
			pcall(reliableRemote.FireClient, reliableRemote, player, packetBuffer, instances)
		end
		Buffers_FreeWriter(relWriter)
	end

	local unrelWriter = unreliablePlayerWriters[player]
	if unrelWriter ~= nil then
		unreliablePlayerWriters[player] = nil
		if unrelWriter.cursor > 0 and unreliableRemote and player.Parent ~= nil and player:IsDescendantOf(Players) then
			local packetBuffer, instances = Buffers_Finalize(unrelWriter)
			pcall(unreliableRemote.FireClient, unreliableRemote, player, packetBuffer, instances)
		end
		Buffers_FreeWriter(unrelWriter)
	end
end

function Bridge.FlushAll()
	if not reliableRemote or not unreliableRemote then
		return
	end

	if IS_SERVER then
		if broadcastReliableWriter ~= nil then
			local writer = broadcastReliableWriter
			broadcastReliableWriter = nil
			if writer.cursor > 0 then
				local packetBuffer, instances = Buffers_Finalize(writer)
				reliableRemote:FireAllClients(packetBuffer, instances)
			end
			Buffers_FreeWriter(writer)
		end

		if broadcastUnreliableWriter ~= nil then
			local writer = broadcastUnreliableWriter
			broadcastUnreliableWriter = nil
			if writer.cursor > 0 then
				local packetBuffer, instances = Buffers_Finalize(writer)
				unreliableRemote:FireAllClients(packetBuffer, instances)
			end
			Buffers_FreeWriter(writer)
		end

		for targetPlayer, writer in reliablePlayerWriters do
			if writer.cursor > 0 and targetPlayer.Parent ~= nil and targetPlayer:IsDescendantOf(Players) then
				local packetBuffer, instances = Buffers_Finalize(writer)
				pcall(reliableRemote.FireClient, reliableRemote, targetPlayer, packetBuffer, instances)
			end
			Buffers_FreeWriter(writer)
		end
		table_clear(reliablePlayerWriters)

		for targetPlayer, writer in unreliablePlayerWriters do
			if writer.cursor > 0 and targetPlayer.Parent ~= nil and targetPlayer:IsDescendantOf(Players) then
				local packetBuffer, instances = Buffers_Finalize(writer)
				pcall(unreliableRemote.FireClient, unreliableRemote, targetPlayer, packetBuffer, instances)
			end
			Buffers_FreeWriter(writer)
		end
		table_clear(unreliablePlayerWriters)
	else
		if clientReliableWriter ~= nil then
			local writer = clientReliableWriter
			clientReliableWriter = nil
			if writer.cursor > 0 then
				local packetBuffer, instances = Buffers_Finalize(writer)
				reliableRemote:FireServer(packetBuffer, instances)
			end
			Buffers_FreeWriter(writer)
		end

		if clientUnreliableWriter ~= nil then
			local writer = clientUnreliableWriter
			clientUnreliableWriter = nil
			if writer.cursor > 0 then
				local packetBuffer, instances = Buffers_Finalize(writer)
				unreliableRemote:FireServer(packetBuffer, instances)
			end
			Buffers_FreeWriter(writer)
		end
	end
end

function Bridge.ClientWriter(isReliable: boolean): Buffers.Writer
	if isReliable then
		local writer = clientReliableWriter
		if writer == nil then
			if not frameConnection then
				Bridge.Initialize()
			end
			if clientReliableWriter ~= nil then
				return clientReliableWriter
			end
			writer = Buffers_CreateWriter()
			clientReliableWriter = writer
		end
		return writer :: Buffers.Writer
	end

	local writer = clientUnreliableWriter
	if writer == nil then
		if not frameConnection then
			Bridge.Initialize()
		end
		if clientUnreliableWriter ~= nil then
			return clientUnreliableWriter
		end
		writer = Buffers_CreateWriter()
		clientUnreliableWriter = writer
	end
	return writer :: Buffers.Writer
end

function Bridge.Writer(isReliable: boolean, targetPlayer: Player?): Buffers.Writer
	if IS_SERVER then
		if targetPlayer ~= nil then
			local writerMap = if isReliable then reliablePlayerWriters else unreliablePlayerWriters
			local writer = writerMap[targetPlayer]
			if writer == nil then
				if not frameConnection then
					Bridge.Initialize()
				end
				if writerMap[targetPlayer] ~= nil then
					return writerMap[targetPlayer]
				end
				writer = Buffers_CreateWriter()
				writerMap[targetPlayer] = writer
			end
			return writer :: Buffers.Writer
		else
			if isReliable then
				local writer = broadcastReliableWriter
				if writer == nil then
					if not frameConnection then
						Bridge.Initialize()
					end
					if broadcastReliableWriter ~= nil then
						return broadcastReliableWriter
					end
					writer = Buffers_CreateWriter()
					broadcastReliableWriter = writer
				end
				return writer :: Buffers.Writer
			else
				local writer = broadcastUnreliableWriter
				if writer == nil then
					if not frameConnection then
						Bridge.Initialize()
					end
					if broadcastUnreliableWriter ~= nil then
						return broadcastUnreliableWriter
					end
					writer = Buffers_CreateWriter()
					broadcastUnreliableWriter = writer
				end
				return writer :: Buffers.Writer
			end
		end
	else
		return Bridge.ClientWriter(isReliable)
	end
end

return Bridge