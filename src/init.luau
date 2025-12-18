--!strict
local Jolt = {}

local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local IS_CLIENT = RunService:IsClient()

local Client = require("@self/Client")
local Server = require("@self/Server")

export type Server<Args... = (...any), Out... = (...any)> = {
	Fire: (self: Server<Args..., Out...>, player: Player, Args...) -> (),
	FireUnreliable: (self: Server<Args..., Out...>, player: Player, Args...) -> (),
	FireAll: (self: Server<Args..., Out...>, Args...) -> (),
	FireAllUnreliable: (self: Server<Args..., Out...>, Args...) -> (),
	Connect: (self: Server<Args..., Out...>, callback: (player: Player, Args...) -> ()) -> { Disconnect: () -> () },
	OnInvoke: ((player: Player, Args...) -> Out...)?,
}

export type Client<Args... = (...any), Out... = (...any)> = {
	Fire: (self: Client<Args..., Out...>, Args...) -> (),
	FireUnreliable: (self: Client<Args..., Out...>, Args...) -> (),
	Invoke: (self: Client<Args..., Out...>, Args...) -> Out...,
	Connect: (self: Client<Args..., Out...>, callback: (Args...) -> ()) -> { Disconnect: () -> () },
}

--[[
	Creates a new Jolt event (Server side).

	```luau
	local myEvent = Jolt.Server("MyEvent") :: Jolt.Server<{ Arg: string }>
	myEvent.Fire(player, { Arg = "Hello World" })

	local myInvokeEvent = Jolt.Server("MyInvokeEvent") :: Jolt.Server<(), (boolean, string)>
	myEvent.OnInvoke = function(player)
		return true, "Success!"
	end
	```
]]
function Jolt.Server<Args..., Out...>(name: string): Server<Args..., Out...>
	if not IS_SERVER then
		error("Jolt.Server can only be called on the server.")
	end

	return Server.new(name) :: any
end

--[[
	Creates a new Jolt event (Client side).

	```luau
	local myEvent = Jolt.Client("MyEvent") :: Jolt.Client<{ Arg: string }>
	myEvent.Connect(function(data)
		print(data.Arg)
	end)

	local myInvokeEvent = Jolt.Client("MyInvokeEvent") :: Jolt.Client<(), (boolean, string)>
	local success, message = myEvent.Invoke()
	```
]]
function Jolt.Client<Args..., Out...>(name: string): Client<Args..., Out...>
	if not IS_CLIENT then
		error("Jolt.Client can only be called on the client.")
	end

	return Client.new(name) :: any
end

return Jolt
