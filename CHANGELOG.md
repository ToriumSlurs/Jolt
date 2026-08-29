# Changelog

All notable changes to the Jolt library are documented in this file.

The format is based on Keep a Changelog: Added, Changed, Fixed, Removed.

---

### Added
- **`Server:FireListUnreliable(players, ...)`**: Unreliable multicast to a list of players using single-pass serialization and `buffer.copy`.
- **`Server:FireExceptUnreliable(exceptPlayer, ...)`**: Unreliable broadcast to all players except one.
- **`TAG_ARR_VEC2` (Tag 55)**: Serializer and deserializer for packed `Vector2` arrays (8 bytes/element).
- **Player Lifecycle Hooks**: `Players.PlayerRemoving` listeners in `Bridge` and `Server` to flush buffers, recycle writers, and cancel pending invocation timers.
- **Bounds Clamping**: Boundary checks (`availableBytes` and `math.max(0, len - cursor)`) across all array, string, and map deserializers.

### Changed
- **Argument Serialization (`Packet.lua`)**: Unrolled 1–8 parameter branches for `Packet.ReadArguments` and `Packet.WriteArguments`; replaced quadratic `select(i, ...)` with `table.pack` fallback for $>8$ arguments.
- **Multicast Optimization (`Server.lua`)**: `Server:FireList` and `Server:FireListUnreliable` serialize once into a temporary buffer and copy raw bytes via `buffer.copy()`.
- **Float Serialization (`Buffers.lua`)**: Replaced speculative float16/float24 bit-testing on hot paths with direct 32-bit round-trip checks in scratch buffers.
- **Array Unpacking (`Buffers.lua`)**: Vectorized boolean unpacking via `bit32.btest`; unrolled 8-way and 16-way integer array unpack loops (`TAG_ARR_U8`, `TAG_ARR_I8`, `TAG_ARR_F32`).
- **Luau Directives**: Added `--!strict`, `--!native`, and `--!optimize 2` to all modules.
- **Type Definitions (`init.lua`)**: Added `FireListUnreliable` and `FireExceptUnreliable` to `export type Server`.
- **Version Constant**: Bumped version to `4.2.0` across `init.lua`, `Constants.lua`, and docstrings.

### Fixed
- **Signal GC Leak (`Signal.lua`)**: Zeroed `node._next` and `node._prev` before recycling nodes into `nodePool`, allowing GC to collect disconnected closures.
- **Reader Pool Buffer Retention (`Buffers.lua`)**: `Buffers.FreeReader` now replaces `reader.buff` with a 0-byte dummy buffer and clears `reader.insts` in-place.
- **Mixed Table Corruption (`Buffers.lua`)**: Replaced `#targetTable > 0` with `arrayLength > 0 and next(targetTable, arrayLength) == nil` to prevent dropping hash map keys.
- **Dictionary Key Truncation (`Buffers.lua`)**: Fixed `writeDictionaryFast` key length checks ($>255$ bytes) and added automatic fallback to `TAG_MAP`.
- **Instance Reference Mutation (`Buffers.lua`)**: Decoupled `writer.insts` in `Buffers.Finalize` to prevent recycled writers from mutating in-flight packets.
- **Player Writer Leaks (`Bridge.lua`)**: `Bridge.FlushPlayer` now flushes and frees both reliable and unreliable writers.
- **Disconnected Player Remote Errors (`Bridge.lua`)**: Added `player.Parent ~= nil and player:IsDescendantOf(Players)` checks before remote calls.
- **Server Request Memory Leaks (`Server.lua`)**: Cancelled pending `task.delay` timers and cleared request tables on player disconnect and channel destruction.
- **Client Parsing Safety (`Client.lua`)**: Protected incoming network loops against malformed headers and out-of-bounds argument counts.

### Removed
- **Table Allocations**: Removed temporary argument tables and vararg allocations on event/RPC paths.
- **Dangling References**: Removed unsevered linked list pointers in `Signal.nodePool`.
- **Dead Code**: Removed duplicated helper functions in `Buffers.lua`.
