--!strict
--!native
--!optimize 2

local Remotes = {}

local RELIABLE_REMOTE_NAME = "Jolt_Reliable"
local UNRELIABLE_REMOTE_NAME = "Jolt_Unreliable"

export type RemoteGroup = {
	Reliable: RemoteEvent,
	Unreliable: UnreliableRemoteEvent,
}

local cachedRemoteGroup: RemoteGroup? = nil

function Remotes.Get(): RemoteGroup
	if cachedRemoteGroup then
		return cachedRemoteGroup
	end

	local reliableEvent = script:FindFirstChild(RELIABLE_REMOTE_NAME) or script:WaitForChild(RELIABLE_REMOTE_NAME, 10)
	local unreliableEvent = script:FindFirstChild(UNRELIABLE_REMOTE_NAME) or script:WaitForChild(UNRELIABLE_REMOTE_NAME, 10)

	if not reliableEvent or not unreliableEvent then
		error("Jolt: RemoteEvents under Jolt.Utils.Remotes timed out during client initialization.", 2)
	end

	local group: RemoteGroup = {
		Reliable = reliableEvent :: RemoteEvent,
		Unreliable = unreliableEvent :: UnreliableRemoteEvent,
	}

	cachedRemoteGroup = group
	return group
end

function Remotes.Create(): RemoteGroup
	if cachedRemoteGroup then
		return cachedRemoteGroup
	end

	local reliableEvent = script:FindFirstChild(RELIABLE_REMOTE_NAME)
	local unreliableEvent = script:FindFirstChild(UNRELIABLE_REMOTE_NAME)

	if not reliableEvent then
		reliableEvent = Instance.new("RemoteEvent")
		reliableEvent.Name = RELIABLE_REMOTE_NAME
		reliableEvent.Parent = script
	end

	if not unreliableEvent then
		unreliableEvent = Instance.new("UnreliableRemoteEvent")
		unreliableEvent.Name = UNRELIABLE_REMOTE_NAME
		unreliableEvent.Parent = script
	end

	local group: RemoteGroup = {
		Reliable = reliableEvent :: RemoteEvent,
		Unreliable = unreliableEvent :: UnreliableRemoteEvent,
	}

	cachedRemoteGroup = group
	return group
end

return Remotes
