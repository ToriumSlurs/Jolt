<div align="center">
  <h1>Jolt 4.0.0</h1>
  <p>
    <strong>High-performance binary networking for Roblox. Simplified.</strong>
  </p>
</div>

---

## About

**Jolt** is a strictly typed binary networking library designed as a high-throughput replacement for standard `RemoteEvent`, `UnreliableRemoteEvent`, and `RemoteFunction` instances.

It utilizes 16-bit FNV-1a channel hashing, packed binary buffers, doubly-linked signal dispatching with object pooling, and per-frame batched transmission to minimize network bandwidth, serialization overhead, and garbage collection pressure without requiring schema definition files.

---

## Key Highlights

* **Hash-Based Wire Addressing:** Channel names are hashed to 16-bit unsigned integers on the wire, cutting packet header overhead by up to 90%.
* **High-Throughput Binary Serialization:** Custom buffer engine supporting 63+ data formats (Float16/24, Int24, packed booleans, typed arrays, struct compression, and native Roblox types).
* **Zero-GC Object Pooling:** Recycles signal connection nodes (512-node pool) and buffer writers to eliminate garbage collection spikes during high-frequency events.
* **Frame-Synchronized Batching:** Automatically batches packets in memory and dispatches them once per engine frame directly on `RunService.Heartbeat`.
* **Zero-Trust Security Layer:** Built-in validation enforcing buffer size ceilings (256 KB), argument count caps (64), pending request limits (128), and recursion depth protection (16).
* **Strict Type Safety:** Fully typed in Luau (`--!strict`, `--!native`, `--!optimize 2`) with support for generic argument and return parameter annotations.

---

## API Reference

### Server API (`Jolt.Server`)

Creates or retrieves a server-side network channel.

```lua
local channel = Jolt.Server(channelName: string): Server<Args..., Out...>
```

#### Methods
* **`channel:Fire(player: Player, ...args: any)`**: Sends a reliable event to a specific player.
* **`channel:FireUnreliable(player: Player, ...args: any)`**: Sends an unreliable event to a specific player.
* **`channel:FireAll(...args: any)`**: Broadcasts a reliable event to all connected players.
* **`channel:FireAllUnreliable(...args: any)`**: Broadcasts an unreliable event to all connected players.
* **`channel:FireExcept(exceptPlayer: Player, ...args: any)`**: Broadcasts a reliable event to all connected players except the specified player.
* **`channel:FireList(players: { Player }, ...args: any)`**: Broadcasts a reliable event to an array of target players using optimized buffer cloning.
* **`channel:Invoke(player: Player, ...args: any): Out...`**: Invokes a client and yields until the client returns a response or the 30-second timeout expires.
* **`channel:Connect(callback: (player: Player, Args...) -> ()): Connection`**: Listens for reliable and unreliable client-to-server events. Returns a `Connection` object.
* **`channel:Once(callback: (player: Player, Args...) -> ()): Connection`**: Listens for the next event only, then automatically disconnects.
* **`channel:Wait(): (Player, Args...)`**: Yields the calling thread until the next event is received.
* **`channel:Destroy()`**: Tears down the channel, unregisters it from the active channel table, destroys all signal connections, and cancels pending request timers.

#### Callbacks
* **`channel.OnInvoke = function(player: Player, ...args: any): Out...`**: Defines the handler for incoming client-to-server invocations.

---

### Client API (`Jolt.Client`)

Creates or retrieves a client-side network channel.

```lua
local channel = Jolt.Client(channelName: string): Client<Args..., Out...>
```

#### Methods
* **`channel:Fire(...args: any)`**: Sends a reliable event to the server.
* **`channel:FireUnreliable(...args: any)`**: Sends an unreliable event to the server.
* **`channel:Invoke(...args: any): Out...`**: Invokes the server and yields until a response is returned or the 30-second timeout expires.
* **`channel:Connect(callback: (Args...) -> ()): Connection`**: Listens for server-to-client events. Returns a `Connection` object.
* **`channel:Once(callback: (Args...) -> ()): Connection`**: Listens for the next event only, then automatically disconnects.
* **`channel:Wait(): Args...`**: Yields the calling thread until the next event is received.
* **`channel:Destroy()`**: Tears down the channel, unregisters it, destroys its signal listeners, and cancels pending request timers.

#### Callbacks
* **`channel.OnInvoke = function(...args: any): Out...`**: Defines the handler for incoming server-to-client invocations.

---

### Connection Object

Returned by `:Connect()` and `:Once()`.

* **`connection:Disconnect()`**: Disconnects the listener and returns the internal node to the object pool.
* **`connection.Connected: boolean`**: Indicates whether the connection is currently active.

---

## Code Examples

### 1. Basic Events

#### Server
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Jolt = require(ReplicatedStorage.Jolt)

local CombatEvent = Jolt.Server("CombatEvent")

-- Listen for client attacks
CombatEvent:Connect(function(player, targetId, attackType)
    print(`{player.Name} attacked {targetId} with {attackType}`)
    
    -- Notify all other players
    CombatEvent:FireExcept(player, targetId, attackType)
end)
```

#### Client
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Jolt = require(ReplicatedStorage.Jolt)

local CombatEvent = Jolt.Client("CombatEvent")

-- Listen for other players' attacks
CombatEvent:Connect(function(targetId, attackType)
    print(`Received attack animation trigger: {targetId} ({attackType})`)
end)

-- Send attack to server
CombatEvent:Fire("Enemy_123", "Slash")
```

---

### 2. Two-Way Invocations

#### Server
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Jolt = require(ReplicatedStorage.Jolt)

local InventoryService = Jolt.Server("InventoryService")

InventoryService.OnInvoke = function(player, itemId, amount)
    if typeof(itemId) ~= "string" or typeof(amount) ~= "number" then
        error("Invalid arguments")
    end
    
    local success = true
    local remainingBalance = 150
    return success, remainingBalance
end
```

#### Client
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Jolt = require(ReplicatedStorage.Jolt)

local InventoryService = Jolt.Client("InventoryService")

local success, balance = InventoryService:Invoke("Potion_Health", 2)
print("Purchase result:", success, "New balance:", balance)
```

---

### 3. Strictly Typed Generic Channels

You can supply generic type parameters for compile-time type validation in Luau:

```lua
-- Define parameter types
type PositionPayload = {
    entityId: number,
    position: Vector3,
    velocity: Vector3,
}

-- Server
local PositionChannel = Jolt.Server("EntityPositions") :: Jolt.Server<PositionPayload>
PositionChannel:FireAll({
    entityId = 1,
    position = Vector3.new(0, 5, 0),
    velocity = Vector3.zero,
})

-- Client
local PositionChannel = Jolt.Client("EntityPositions") :: Jolt.Client<PositionPayload>
PositionChannel:Connect(function(payload)
    print(payload.entityId, payload.position)
end)
```

---

## Supported Serialization Types

Jolt serializes the following data types natively through its buffer pipeline:

| Category | Supported Types |
| :--- | :--- |
| **Primitives** | `nil`, `boolean` (individual & bitpacked), `number` (Float16, Float24, Float32, Float64, Int8, Int16, Int24, Int32, Uint8, Uint16, Uint24, Uint32), `string` (8-bit, 16-bit, and variable LEB128 lengths), `buffer` |
| **Vectors & Spatial** | `Vector2`, `Vector2` (Float16), `Vector2int16`, `Vector3`, `Vector3` (Float16), `Vector3int16`, `CFrame` (full), `CFrame` (position-only), `CFrame` (position + 1-byte yaw angle), `Ray`, `Rect`, `Region3`, `Region3int16` |
| **Roblox Objects** | `Instance`, `EnumItem` (cached reverse lookups), `BrickColor`, `Color3`, `ColorSequence`, `ColorSequenceKeypoint`, `NumberRange`, `NumberSequence`, `NumberSequenceKeypoint`, `DateTime`, `TweenInfo`, `UDim`, `UDim2` |
| **Collections** | `Array` (generic), `Map` (generic), `StructArray` (columnar schema compression), and typed homogeneous arrays (`i8`, `i16`, `i32`, `u8`, `u16`, `u32`, `f32`, `f64`, `bool`, `string`, `Vector2`, `Vector3`, `Color3`, `CFrame`) |

---

## Security Boundaries & System Limits

| Boundary | Value | Behavior on Violation |
| :--- | :--- | :--- |
| **Maximum Raw Buffer Size** | 256 KB (`262,144` bytes) | Payload dropped immediately |
| **Maximum Packet Arguments** | 64 parameters | Reading breaks; surplus arguments ignored |
| **Maximum Concurrent Requests** | 128 pending invokes per target | Invocations immediately throw error |
| **Maximum Serialization Depth** | 16 nested levels | Traversal aborts to prevent stack overflow |
| **Request Timeout** | 30 seconds | Yielding thread resumed with `"Request timed out"` |
| **Instance Packet Limit** | 256 instances per payload | Array capped and non-Instance elements stripped |

---

## Links

* **GitHub Repository:** [https://github.com/ToriumSlurs/Jolt](https://github.com/ToriumSlurs/Jolt)
* **RBXM Download:** [Jolt.rbxm|attachment](upload://x1V0nm76E5xzVqMPXvLAEPOX48.rbxm) (12.2 KB)
