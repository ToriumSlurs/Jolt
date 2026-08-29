# Jolt Changelog

All notable changes to the Jolt networking library are documented in this file.

---

## [4.0.0] - 2026-08-29

### Breaking Changes

* **Wire Protocol Format**: Channel names are now encoded as 2-byte unsigned integer hashes instead of variable-length UTF-8 strings. Jolt v4.0.0 clients and servers cannot communicate with v3.x.x instances.
* **Serialization Tag Reorganization**: Legacy table reference deduplication (`TYPE_REF`) has been replaced by specialized typed array and struct encoders.
* **Default Request Timeout**: Reduced from 60 seconds to 30 seconds. Invocations taking longer than 30 seconds will now time out earlier.

---

### Added

#### Subsystems and Modules

* **`Utils.Hash`**: Added a deterministic FNV-1a hashing utility that maps channel name strings to 16-bit unsigned integers (`0x0000` to `0xFFFF`). Includes an internal cache (`nameHashCache`) and throws an explicit runtime error on hash collisions.
* **`Utils.Constants`**: Added a centralized, immutable configuration module defining engine constants and security boundaries:
  * `PACKET_EVENT = 1`
  * `PACKET_REQUEST = 2`
  * `PACKET_RESPONSE = 3`
  * `REQUEST_TIMEOUT_SECONDS = 30`
  * `MAX_PACKET_ARGUMENTS = 64`
  * `MAX_PENDING_REQUESTS = 128`
  * `MAX_RAW_BUFFER_SIZE = 262144` (256 KB)
* **`Utils.Packet`**: Added a dedicated packet encoding and decoding module. Includes unrolled serialization loops for 1 to 6 arguments (`ReadArguments` and `WriteArguments`) to eliminate heap table allocations on hot paths.

#### API Methods

* **`Server:FireExcept(exceptPlayer: Player, ...args)`**: Sends a reliable event to all connected players except the specified player.
* **`Server:FireList(players: { Player }, ...args)`**: Sends a reliable event to an explicit list of players using single-encode, multi-copy buffer operations.
* **`Server:Destroy()`**: Tears down a server channel, clears listeners, cancels pending request timers, and notifies waiting threads.
* **`Client:Destroy()`**: Tears down a client channel, unregisters it from the active channel map, destroys internal signals, and cancels pending request timers.
* **`Signal:Destroy()`**: Public cleanup method aliasing `DisconnectAll()`.
* **Exported `Connection` Type**: Exported `Connection` from the root `Jolt` module (`export type Connection = Signal.Connection`).
* **`Jolt.Version`**: Added version string property on the root module (`Version = "4.0.0"`).

#### Serialization Types (`Buffers.luau`)

* **Float16 (`TAG_F16`)**: 16-bit half-precision floating-point encoding and decoding for reduced bandwidth on coordinate and ratio floats.
* **Float24 (`TAG_F24`)**: 24-bit floating-point encoding for mid-precision rotational values.
* **Int24 / Uint24 (`TAG_I24`, `TAG_U24`)**: 3-byte signed and unsigned integer encoding.
* **Tiered String Encoding**: Added `TAG_STR8` (strings <= 255 bytes) and `TAG_STR16` (strings <= 65,535 bytes) alongside variable LEB128 string encoding (`TAG_STR_VAR`).
* **Packed Booleans (`TAG_ARR_BOOL`)**: Encodes 8 booleans per byte using a precomputed 256-element lookup table.
* **Typed Numeric and Spatial Arrays**: Homogeneous array encoders for `i8`, `i16`, `i32`, `u8`, `u16`, `u32`, `f32`, `f64`, `string`, `Vector2`, `Vector3`, `Color3`, and `CFrame`.
* **Columnar Struct Arrays (`TAG_ARR_STRUCT`)**: Schema-based serialization for arrays of uniform tables, serializing keys once in the header followed by contiguous row data.
* **Additional Roblox Types**: Added native support for `ColorSequence`, `ColorSequenceKeypoint`, `NumberRange`, `NumberSequence`, `NumberSequenceKeypoint`, `Region3int16`, `Rect`, `DateTime`, and `Ray`.
* **Optimized CFrames**: Added `TAG_CF_POS` (position-only 12-byte CFrame) and `TAG_CF_YAW` (position + quantized 1-byte yaw angle).

#### Security and Validation Guards

* **Buffer Bounds Check**: Drops incoming buffers larger than 256 KB (`MAX_RAW_BUFFER_SIZE`) or of size 0.
* **Argument Count Ceiling**: Rejects packets containing more than 64 arguments (`MAX_PACKET_ARGUMENTS`).
* **Pending Request Limit**: Enforces a maximum of 128 concurrent requests (`MAX_PENDING_REQUESTS`) per player/client.
* **Instance Sanitization**: Verifies incoming instance tables, caps count at 256, and validates each entry is an `Instance`.
* **Request ID Wrap-Around**: Wraps request IDs using modulo `0x7FFFFFFF` to prevent integer overflow.
* **Recursion Guard**: Caps table serialization depth at `MAX_SERIALIZATION_DEPTH = 16` to prevent stack overflow.

---

### Changed

#### Wire Protocol and Addressing

* **Channel Addressing**: Channels are identified on the wire using a 2-byte integer hash instead of full string names, reducing header overhead by up to 90%.
* **Header Structure**: Unified header format to `[ChannelHash: u16][PacketType: u8][ArgumentCount: u8]`.

#### Signal Architecture

* **Traversal Order**: Migrated from a singly-linked list (`_head`, LIFO execution) to a doubly-linked list (`_head` and `_tail`, FIFO execution matching subscription sequence).
* **Node Pooling**: Added `nodePool` (capacity: 512) to recycle connection objects and eliminate GC allocation churn.
* **Single-Listener Fast Path**: Bypasses loop traversal when only one connection is attached.

#### Bridge and Network Scheduling

* **Heartbeat Dispatch**: Removed the fixed 60 FPS accumulator throttle (`FRAME_TIME = 1/60`). Outgoing buffers are now flushed directly on `RunService.Heartbeat`.
* **Separated Writer Maps**: Replaced the shared polymorphic `WriterMap` with distinct pools for client, player, and broadcast writers.
* **Selective Flush**: Added `Bridge.FlushPlayer(player)` for flushing a single player's buffer on demand.

#### Invocation Handling

* **Unrolled Multi-Returns**: `Client:Invoke` and `Server:Invoke` unroll up to 7 return values to avoid `table.pack` and `table.unpack` allocations.
* **Static Request Handlers**: Extracted incoming invocation callbacks into static functions (`handleIncomingRequest`) to prevent closure allocations per network packet.

#### Code Organization and Tooling

* **Instance-Based Requires**: Replaced string path aliases (`@self/Client`, `./Utils/Buffers`) with direct instance references (`script.Parent.Client`, `script.Parent.Utils.Buffers`).
* **Compiler Directives**: Added `--!native` and `--!optimize 2` to all modules.

---

### Fixed

* **Buffer Desynchronization on Dead Invoke Coroutines**: Response arguments are now fully drained from the buffer when an invoke caller thread is cancelled before completion, preserving stream alignment for subsequent packets.
* **Pending Request Counter Leaks**: Clamped pending request counters using `math.max(0, count - 1)` to prevent counter drift on timeouts.
* **Typing Bug in `Server:Once`**: Corrected `Server:Once` return type from `()` (void) to `Signal.Connection`.
* **Player Disconnection Leak on Invocation**: Added a `Players.PlayerRemoving` listener in `Server.Initialize()` to cancel active invoke timers and resume threads with `"Player disconnected"`.
* **Client Hang on Missing Remotes**: Replaced unbounded `script:WaitForChild()` calls with `script:FindFirstChild() or script:WaitForChild(..., 10)`.
* **Mid-Frame Disconnection Crashes**: Added `player.Parent ~= nil and player:IsDescendantOf(Players)` checks inside `pcall` wrappers before sending packets to players.

---

### Removed

* **Table Reference Deduplication (`TYPE_REF`)**: Removed `refs` and `refCount` tracking from `Writer` and `Reader` to eliminate table hashing overhead during writes.
* **`getfenv()` Script Lifecycle Tracking**: Removed `getScript()` and `_script` properties on Signal connections to preserve Luau compiler optimizations.
* **Runtime Colon Checks**: Removed `typeof(self) ~= "table"` runtime assertions from methods (`Fire`, `Invoke`, `Connect`, etc.).
* **Unreliable Size Warning**: Removed string formatting and warning logs for unreliable packets exceeding 900 bytes.
* **`Send()` Helper Indirection**: Removed intermediate `Send()` wrapper functions; modules now write directly via `Packet.WriteEvent()`.
* **Legacy `Buffers.Pack()` / `Buffers.Unpack()`**: Removed unused pack and unpack wrappers in favor of streaming reader/writer APIs.
