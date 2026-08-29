--!strict
--[=[
	Jolt 4.0.1
	High-performance binary networking library for Roblox.
]=]

local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local IS_CLIENT = RunService:IsClient()

local Client = require(script.Client)
local Server = require(script.Server)
local Signal = require(script.Utils.Signal)
local Constants = require(script.Utils.Constants)

export type Connection = Signal.Connection

export type Server<Args... = (...any), Out... = (...any)> = {
	Fire: (self: Server<Args..., Out...>, player: Player, Args...) -> (),
	FireUnreliable: (self: Server<Args..., Out...>, player: Player, Args...) -> (),
	FireAll: (self: Server<Args..., Out...>, Args...) -> (),
	FireAllUnreliable: (self: Server<Args..., Out...>, Args...) -> (),
	FireExcept: (self: Server<Args..., Out...>, exceptPlayer: Player, Args...) -> (),
	FireList: (self: Server<Args..., Out...>, players: { Player }, Args...) -> (),
	Invoke: (self: Server<Args..., Out...>, player: Player, Args...) -> Out...,
	Connect: (self: Server<Args..., Out...>, callback: (player: Player, Args...) -> ()) -> Connection,
	Once: (self: Server<Args..., Out...>, callback: (player: Player, Args...) -> ()) -> Connection,
	Wait: (self: Server<Args..., Out...>) -> (Player, Args...),
	Destroy: (self: Server<Args..., Out...>) -> (),
	OnInvoke: ((player: Player, Args...) -> Out...)?,
}

export type Client<Args... = (...any), Out... = (...any)> = {
	Fire: (self: Client<Args..., Out...>, Args...) -> (),
	FireUnreliable: (self: Client<Args..., Out...>, Args...) -> (),
	Invoke: (self: Client<Args..., Out...>, Args...) -> Out...,
	Connect: (self: Client<Args..., Out...>, callback: (Args...) -> ()) -> Connection,
	Once: (self: Client<Args..., Out...>, callback: (Args...) -> ()) -> Connection,
	Wait: (self: Client<Args..., Out...>) -> Args...,
	Destroy: (self: Client<Args..., Out...>) -> (),
	OnInvoke: ((Args...) -> Out...)?,
}

local Jolt = {
	Version = "4.0.1",
}

function Jolt.Server<Args..., Out...>(channelName: string): Server<Args..., Out...>
	if not IS_SERVER then
		error("Jolt.Server can only be called on the server.", 2)
	end
	return Server.new(channelName) :: any
end

function Jolt.Client<Args..., Out...>(channelName: string): Client<Args..., Out...>
	if not IS_CLIENT then
		error("Jolt.Client can only be called on the client.", 2)
	end
	return Client.new(channelName) :: any
end

return Jolt
