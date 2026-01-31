--!strict
--!native
--!optimize 2
local Signal = {}
Signal.__index = Signal

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
	_signal: Signal,
	_callback: (...any) -> (),
	_next: Connection?,
	_prev: Connection?,
}

export type Signal = {
	Connect: (self: Signal, callback: (...any) -> ()) -> Connection,
	Once: (self: Signal, callback: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Wait: (self: Signal) -> ...any,
	DisconnectAll: (self: Signal) -> (),
	_head: Connection?,
}

type InternalConnection = Connection & {
	_signal: InternalSignal,
	_next: InternalConnection?,
	_prev: InternalConnection?,
	_script: LuaSourceContainer?,
}

type InternalSignal = Signal & {
	_head: InternalConnection?,
}

local Connection = {}
Connection.__index = Connection

local function getScript(f: (...any) -> ...any): LuaSourceContainer?
	local success, result = pcall(function()
		return (getfenv(f) :: any).script
	end)
	return if success and typeof(result) == "Instance" and result:IsA("LuaSourceContainer") then result else nil
end

function Connection:Disconnect()
	local self = self :: InternalConnection
	if not self.Connected then
		return
	end
	self.Connected = false

	self._script = nil

	if self._signal._head == self then
		self._signal._head = self._next
	end

	if self._prev then
		self._prev._next = self._next
	end

	if self._next then
		self._next._prev = self._prev
	end

	self._next = nil
	self._prev = nil
end

local function createConnection(signal: InternalSignal, callback: (...any) -> ()): InternalConnection
	return setmetatable({
		Connected = true,
		_signal = signal,
		_callback = callback,
		_script = getScript(callback),
		_next = nil,
		_prev = nil,
	}, Connection) :: any
end

local freeRunnerThread: thread?

local function runHandler(callback: (...any) -> (), thread: thread, ...)
	callback(...)
	freeRunnerThread = thread
end

local function yieldLoop(callback: (...any) -> (), thread: thread, ...)
	runHandler(callback, thread, ...)
	while true do
		runHandler(coroutine.yield())
	end
end

function Signal.new(): Signal
	return setmetatable({
		_head = nil,
	}, Signal) :: any
end

function Signal:Connect(callback: (...any) -> ()): Connection
	local self = self :: InternalSignal
	local connection = createConnection(self, callback)

	if self._head then
		connection._next = self._head
		self._head._prev = connection
	end
	self._head = connection

	return connection
end

function Signal:Once(callback: (...any) -> ()): Connection
	local self = self :: Signal
	local connection: Connection?
	connection = self:Connect(function(...)
		if connection then
			connection:Disconnect()
		end
		callback(...)
	end)
	return connection :: Connection
end

function Signal:Fire(...: any)
	local self = self :: InternalSignal
	local item = self._head
	while item do
		local next = item._next
		if item.Connected then
			local s = item._script
			if s and not s.Parent then
				item:Disconnect()
			else
				local callback = item._callback
				local thread = freeRunnerThread or coroutine.create(yieldLoop)
				freeRunnerThread = nil
				task.spawn(thread, callback, thread, ...)
			end
		end
		item = next
	end
end

function Signal:Wait(): ...any
	local self = self :: Signal
	local thread = coroutine.running()
	local connection: Connection?
	connection = self:Connect(function(...)
		if coroutine.status(thread) == "dead" then
			if connection then
				connection:Disconnect()
			end
			return
		end
		if connection then
			connection:Disconnect()
		end
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	local self = self :: InternalSignal
	local item = self._head
	while item do
		local next = item._next
		item:Disconnect()
		item = next
	end
	self._head = nil
end

return Signal
