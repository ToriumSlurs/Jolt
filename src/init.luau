--!strict
local Jolt = {}

local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local IS_CLIENT = RunService:IsClient()

local Client = require("@self/Client")
local Server = require("@self/Server")

export type Server = {
	Fire: (self: Server, player: Player, ...any) -> (),
	FireUnreliable: (self: Server, player: Player, ...any) -> (),
	FireAll: (self: Server, ...any) -> (),
	FireAllUnreliable: (self: Server, ...any) -> (),
	Connect: (self: Server, callback: (player: Player, ...any) -> ()) -> { Disconnect: () -> () },
	OnInvoke: ((player: Player, ...any) -> ...any)?,
}

export type Client = {
	Fire: (self: Client, ...any) -> (),
	FireUnreliable: (self: Client, ...any) -> (),
	Invoke: (self: Client, ...any) -> ...any,
	Connect: (self: Client, callback: (...any) -> ()) -> { Disconnect: () -> () },
}

function Jolt.Server(name: string): Server
	if not IS_SERVER then
		error("Jolt.Server can only be called on the server.")
	end

	return Server.new(name) :: any
end

function Jolt.Client(name: string): Client
	if not IS_CLIENT then
		error("Jolt.Client can only be called on the client.")
	end

	return Client.new(name) :: any
end

return Jolt
