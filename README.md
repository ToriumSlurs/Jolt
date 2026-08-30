# Jolt

Networking library for Roblox that serializes data into binary buffers and batches transmissions per frame.

---

## What It Does

- **Binary serialization**: Encodes Luau values (numbers, strings, vectors, CFrames, etc.) into compact binary buffers instead of relying on Roblox's default serialization.
- **Per-frame batching**: Accumulates all `:Fire()` calls during a frame and sends them in a single packet on `RunService.Heartbeat`.
- **Channel hashing**: Channel names are hashed to 16-bit integers (FNV-1a) to reduce packet header size.
- **Two-way invocations**: `:Invoke()` provides request-response semantics with a 30-second timeout.
- **Typed API**: Fully typed in Luau with `--!strict` and generic type parameters.

---

## Installation

### Wally
```toml
[dependencies]
Jolt = "toriumslurs/jolt@4.3.1"
```

### Manual
Place the `Jolt` folder inside `ReplicatedStorage` and require it:
```lua
local Jolt = require(game.ReplicatedStorage.Jolt)
```

---

## API

### Server

```lua
local channel = Jolt.Server("ChannelName")
```

| Method | Description |
|--------|-------------|
| `channel:Fire(player, ...)` | Send reliable event to a player |
| `channel:FireUnreliable(player, ...)` | Send unreliable event to a player |
| `channel:FireAll(...)` | Broadcast reliable event to all players |
| `channel:FireAllUnreliable(...)` | Broadcast unreliable event to all players |
| `channel:FireExcept(player, ...)` | Broadcast to all players except one |
| `channel:FireList(players, ...)` | Send to a list of players |
| `channel:Invoke(player, ...): ...` | Request-response to a client (yields, 30s timeout) |
| `channel:Connect(callback): Connection` | Listen for client events |
| `channel:Once(callback): Connection` | Listen for one event then disconnect |
| `channel:Wait(): (Player, ...)` | Yield until next event |
| `channel:Destroy()` | Tear down the channel |
| `channel.OnInvoke = function(player, ...): ...` | Handler for client invocations |

### Client

```lua
local channel = Jolt.Client("ChannelName")
```

| Method | Description |
|--------|-------------|
| `channel:Fire(...)` | Send reliable event to server |
| `channel:FireUnreliable(...)` | Send unreliable event to server |
| `channel:Invoke(...): ...` | Request-response to server (yields, 30s timeout) |
| `channel:Connect(callback): Connection` | Listen for server events |
| `channel:Once(callback): Connection` | Listen for one event then disconnect |
| `channel:Wait(): ...` | Yield until next event |
| `channel:Destroy()` | Tear down the channel |
| `channel.OnInvoke = function(...): ...` | Handler for server invocations |

### Connection

| Member | Description |
|--------|-------------|
| `connection:Disconnect()` | Stop listening |
| `connection.Connected` | Whether the connection is active |

---

## Examples

### Events

```lua
-- Server
local Jolt = require(game:GetService("ReplicatedStorage").Jolt)
local Combat = Jolt.Server("Combat")

Combat:Connect(function(player, targetId, attackType)
    print(player.Name, "attacked", targetId, "with", attackType)
    Combat:FireExcept(player, targetId, attackType)
end)

-- Client
local Jolt = require(game:GetService("ReplicatedStorage").Jolt)
local Combat = Jolt.Client("Combat")

Combat:Connect(function(targetId, attackType)
    print("Attack:", targetId, attackType)
end)

Combat:Fire("Enemy_123", "Slash")
```

### Invocations

```lua
-- Server
local Inventory = Jolt.Server("Inventory")
Inventory.OnInvoke = function(player, itemId, amount)
    -- validate and process
    return true, 150
end

-- Client
local Inventory = Jolt.Client("Inventory")
local success, balance = Inventory:Invoke("Potion_Health", 2)
```

### Typed Channels

```lua
type Payload = { entityId: number, position: Vector3, velocity: Vector3 }

-- Server
local Positions = Jolt.Server("Positions") :: Jolt.Server<Payload>
Positions:FireAll({ entityId = 1, position = Vector3.new(0, 5, 0), velocity = Vector3.zero })

-- Client
local Positions = Jolt.Client("Positions") :: Jolt.Client<Payload>
Positions:Connect(function(data)
    print(data.entityId, data.position)
end)
```

---

## Supported Types

| Category | Types |
|----------|-------|
| Primitives | `nil`, `boolean`, `number` (auto-selects integer/float width), `string`, `buffer` |
| Vectors & Spatial | `Vector2`, `Vector2int16`, `Vector3`, `Vector3int16`, `CFrame`, `Ray`, `Rect`, `Region3`, `Region3int16` |
| Roblox Objects | `Instance`, `EnumItem`, `BrickColor`, `Color3`, `ColorSequence`, `NumberRange`, `NumberSequence`, `DateTime`, `TweenInfo`, `UDim`, `UDim2` |
| Collections | Arrays, dictionaries, and homogeneous typed arrays (integers, floats, booleans, strings, vectors, colors, CFrames) |

Numbers are automatically compressed to the smallest representation that fits (u8, i16, f32, etc.). Booleans in arrays are bitpacked (8 per byte).

---

## Limits

| Limit | Value | What happens |
|-------|-------|--------------|
| Max buffer size | 256 KB | Packet dropped |
| Max arguments per packet | 64 | Packet dropped |
| Max pending invocations | 128 per target | Error thrown |
| Max serialization depth | 16 levels | Serialization stops |
| Invocation timeout | 30 seconds | Yields resume with error |
| Max instances per packet | 256 | Non-Instance values stripped; surplus dropped |

---

## License

MIT — see [LICENSE](LICENSE).
