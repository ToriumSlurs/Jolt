--!strict
--!native
--!optimize 2

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

local Connection = {}
Connection.__index = Connection

type SignalNode = typeof(setmetatable(
	{} :: {
		Connected: boolean,
		_signal: Signal,
		_callback: (...any) -> (),
		_next: SignalNode?,
		_prev: SignalNode?,
	},
	Connection
))

export type Signal = {
	Connect: (self: Signal, callback: (...any) -> ()) -> Connection,
	Once: (self: Signal, callback: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Wait: (self: Signal) -> ...any,
	DisconnectAll: (self: Signal) -> (),
	Destroy: (self: Signal) -> (),
	_head: SignalNode?,
	_tail: SignalNode?,
}

local Signal = {}
Signal.__index = Signal

local nodePool: { SignalNode } = {}
local MAX_NODE_POOL_SIZE = 512

local task_spawn = task.spawn
local coroutine_running = coroutine.running
local coroutine_yield = coroutine.yield

local function dispatch(eventCallback: (...any) -> (), ...: any)
	task_spawn(eventCallback, ...)
end

function Connection.Disconnect(self: any)
	local node: SignalNode = self
	if not node.Connected then
		return
	end
	node.Connected = false

	local parentSignal = node._signal
	if parentSignal ~= nil then
		if parentSignal._head == node then
			parentSignal._head = node._next
		end
		if parentSignal._tail == node then
			parentSignal._tail = node._prev
		end
	end

	if node._prev ~= nil then
		node._prev._next = node._next
	end

	if node._next ~= nil then
		node._next._prev = node._prev
	end

	node._prev = nil
	node._next = nil
	node._callback = nil :: any
	node._signal = nil :: any

	if #nodePool < MAX_NODE_POOL_SIZE then
		table.insert(nodePool, node)
	end
end

function Signal.new(): Signal
	return setmetatable({
		_head = nil,
		_tail = nil,
	}, Signal) :: any
end

function Signal:Connect(callback: (...any) -> ()): Connection
	local selfSignal = self :: Signal
	local poolSize = #nodePool
	local newNode: SignalNode

	if poolSize > 0 then
		newNode = nodePool[poolSize]
		nodePool[poolSize] = nil
		newNode.Connected = true
		newNode._signal = selfSignal
		newNode._callback = callback
		newNode._next = nil
		newNode._prev = selfSignal._tail
	else
		newNode = setmetatable({
			Connected = true,
			_signal = selfSignal,
			_callback = callback,
			_next = nil,
			_prev = selfSignal._tail,
		}, Connection) :: any
	end

	if selfSignal._tail ~= nil then
		selfSignal._tail._next = newNode
	else
		selfSignal._head = newNode
	end
	selfSignal._tail = newNode

	return newNode :: any
end

function Signal:Once(callback: (...any) -> ()): Connection
	local selfSignal = self :: Signal
	local connection: Connection

	connection = selfSignal:Connect(function(...)
		if connection.Connected then
			connection:Disconnect()
		end
		callback(...)
	end)

	return connection
end

function Signal:Fire(...: any)
	local selfSignal = self :: Signal
	local currentNode = selfSignal._head

	if currentNode ~= nil and currentNode._next == nil then
		if currentNode.Connected then
			dispatch(currentNode._callback, ...)
		end
		return
	end

	while currentNode ~= nil do
		local nextNode = currentNode._next
		if currentNode.Connected then
			dispatch(currentNode._callback, ...)
		end
		currentNode = nextNode
	end
end

function Signal:Wait(): ...any
	local selfSignal = self :: Signal
	local callingThread = coroutine_running()
	local connection: Connection

	connection = selfSignal:Connect(function(...)
		if connection.Connected then
			connection:Disconnect()
		end
		task_spawn(callingThread, ...)
	end)

	return coroutine_yield()
end

function Signal:DisconnectAll()
	local selfSignal = self :: Signal
	local currentNode = selfSignal._head

	while currentNode ~= nil do
		local nextNode = currentNode._next
		currentNode.Connected = false
		currentNode._prev = nil
		currentNode._next = nil
		currentNode._callback = nil :: any
		currentNode._signal = nil :: any

		if #nodePool < MAX_NODE_POOL_SIZE then
			table.insert(nodePool, currentNode)
		end

		currentNode = nextNode
	end

	selfSignal._head = nil
	selfSignal._tail = nil
end

function Signal:Destroy()
	self:DisconnectAll()
end

return Signal