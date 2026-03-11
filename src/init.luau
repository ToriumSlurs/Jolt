--!strict
local Jolt = {}

local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local IS_CLIENT = RunService:IsClient()

local Client = require("@self/Client")
local Server = require("@self/Server")


export type Client<Args... = (...any), Out... = (...any)> = Client.Client<Args..., Out...>
export type Server<Args... = (...any), Out... = (...any)> = Server.Server<Args..., Out...>

export type Bridge<Args... = (...any), Out... = (...any)> = Client<Args..., Out...> & Server<Args..., Out...>

function Jolt.ReferenceBridge<Args..., Out...>(name: string): Bridge<Args..., Out...>
	if IS_SERVER then
		return Server.new(name)
	elseif IS_CLIENT then
		return Client.new(name)
	else
		error("Jolt.ReferenceBridge can only be used on the server or the client.")
	end
end


function Jolt.Server<Args..., Out...>(name: string): Server<Args..., Out...>
	if not IS_SERVER then
		error("Jolt.Server can only be called on the server.")
	end

	return Server.new(name)
end

function Jolt.Client<Args..., Out...>(name: string): Client<Args..., Out...>
	if not IS_CLIENT then
		error("Jolt.Client can only be called on the client.")
	end

	return Client.new(name)
end

return Jolt
