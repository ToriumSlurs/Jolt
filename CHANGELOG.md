# Jolt Changelog: Migration from JoltOld to Jolt

This changelog documents all structural, architectural, and protocol changes between `ReplicatedStorage.JoltOld` and `ReplicatedStorage.Jolt`.

---

## Breaking Changes

* **Incompatible Wire Protocol**: The packet framing format has changed. Channel names are no longer sent as raw strings; they are now encoded as 2-byte unsigned integer hashes. Jolt and JoltOld clients and servers cannot communicate with each other.
* **Serialization Format Revision**: The serialization tag layout was restructured. Legacy table reference tracking (`TYPE_REF`) has been removed in favor of typed array and struct encoders.
* **Default Request Timeout**: Reduced from 60 seconds to 30 seconds. Invocations taking longer than 30 seconds will now time out earlier.

---

## Added

### Subsystems and Modules

* **`Utils.Hash`**: Added a deterministic FNV-1a hashing utility that maps channel name strings to 16-bit unsigned integers (`0x0000` to `0xFFFF`). Includes an internal cache (`nameHashCache`) and throws an explicit error if two channel names collide.
* **`Utils.Constants`**: Added a centralized, frozen configuration module containing network boundaries and protocol constants:
  * `PACKET_EVENT = 1`
  * `PACKET_REQUEST = 2`
  * `PACKET_RESPONSE = 3`
  * `REQUEST_TIMEOUT_SECONDS = 30`
  * `MAX_PACKET_ARGUMENTS = 64`
  * `MAX_PENDING_REQUESTS = 128`
  * `MAX_RAW_BUFFER_SIZE = 262144` (256 KB)
* **`Utils.Packet`**: Added a specialized packet encoding and decoding module. Includes unrolled serialization loops for 1 to 6 arguments (`ReadArguments` and `WriteArguments`) to eliminate heap table allocations on hot paths.

### API Methods

* **`Server:FireExcept(exceptPlayer: Player, ...args)`**: Sends an event to all connected players except the specified player.
* **`Server:FireList(players: { Player }, ...args)`**: Sends an event to an explicit list of players using single-encode, multi-copy buffer operations.
* **`Server:Destroy()`**: Tears down a server channel, clears internal listeners, cancels all active request timers, and notifies pending threads.
* **`Client:Destroy()`**: Tears down a client channel, unregisters it from the channel map, destroys its internal signal, and cancels pending request timers.
* **`Signal:Destroy()`**: Added public cleanup method as an alias to `DisconnectAll()`.
* **Exported `Connection` Type**: Exported `Connection` from the root `Jolt` module (`export type Connection = Signal.Connection`).

### Serialization Types (`Buffers.luau`)

* **Float16 (`TAG_F16`)**: Added 16-bit half-precision floating-point encoding and decoding for reduced bandwidth on float values with lower precision requirements.
* **Float24 (`TAG_F24`)**: Added 24-bit floating-point encoding for mid-precision values.
* **Int24 / Uint24 (`TAG_I24`, `TAG_U24`)**: Added 3-byte signed and unsigned integer encoding.
* **Tiered String Encoding**: Added `TAG_STR8` (strings <= 255 bytes) and `TAG_STR16` (strings <= 65,535 bytes) alongside variable LEB128 string encoding (`TAG_STR_VAR`).
* **Packed Booleans (`TAG_ARR_BOOL`)**: Added 8-booleans-per-byte array encoding using a precomputed lookup table.
* **Typed Numeric and Spatial Arrays**: Added optimized homogeneous array encoders for `i8`, `i16`, `i32`, `u8`, `u16`, `u32`, `f32`, `f64`, `string`, `Vector2`, `Vector3`, `Color3`, and `CFrame`.
* **Columnar Struct Arrays (`TAG_ARR_STRUCT`)**: Added schema-based serialization for arrays of uniform tables, serializing keys once in the header followed by contiguous row data.
* **Additional Roblox Types**: Added native buffer support for `ColorSequence`, `ColorSequenceKeypoint`, `NumberRange`, `NumberSequence`, `NumberSequenceKeypoint`, `Region3int16`, `Rect`, `DateTime`, and `Ray`.
* **Optimized CFrames**: Added `TAG_CF_POS` (position-only 12-byte CFrame) and `TAG_CF_YAW` (position + quantized 1-byte yaw angle).

### Security and Validation Guards

* **Buffer Bounds Check**: Incoming buffers larger than 256 KB (`MAX_RAW_BUFFER_SIZE`) or of size 0 are dropped immediately.
* **Argument Count Ceiling**: Packets containing more than 64 arguments (`MAX_PACKET_ARGUMENTS`) are rejected.
* **Pending Request Limit**: Invocations beyond 128 concurrent requests (`MAX_PENDING_REQUESTS`) per player/client error immediately.
* **Instance Sanitization**: Incoming instance tables are verified, capped at 256 entries, and scrubbed to confirm every item is an `Instance`.
* **Request ID Wrap-Around**: Request IDs increment with modulo `0x7FFFFFFF` to prevent integer overflow.
* **Recursion Guard**: Table serialization is capped at `MAX_SERIALIZATION_DEPTH = 16` to prevent stack overflows.

---

## Changed

### Wire Protocol and Addressing

* **Channel Identification**: Channels are now identified on the wire using a 2-byte unsigned integer hash instead of a full string name, reducing framing overhead by up to 90%.
* **Header Structure**: Unified header format to `[ChannelHash: u16][PacketType: u8][ArgumentCount: u8]`.

### Signal Architecture

* **Traversal Order**: Migrated from a singly-linked list storing `_head` (LIFO execution) to a doubly-linked list maintaining `_head` and `_tail` (FIFO execution matching connection order).
* **Node Pooling**: Added `nodePool` (capacity: 512) to recycle connection objects and prevent GC pressure during frequent connect/disconnect cycles.
* **Single-Listener Fast Path**: `Signal:Fire()` now bypasses loop iteration when only one connection is present.

### Bridge and Network Scheduling

* **Heartbeat Dispatch**: Removed the fixed 60 FPS accumulator throttle (`FRAME_TIME = 1/60`). Outgoing buffers are now flushed directly on `RunService.Heartbeat`.
* **Separated Writer Maps**: Replaced the shared polymorphic `WriterMap` with separate pools: `reliablePlayerWriters`, `unreliablePlayerWriters`, `broadcastReliableWriter`, `broadcastUnreliableWriter`, `clientReliableWriter`, and `clientUnreliableWriter`.
* **Selective Flush**: Added `Bridge.FlushPlayer(player)` for flushing a single player's reliable buffer on demand.

### Invocation Handling

* **Unrolled Multi-Returns**: `Client:Invoke` and `Server:Invoke` unroll up to 7 return values to avoid `table.pack` and `table.unpack` allocations.
* **Static Request Handlers**: Extracted incoming invocation callbacks into static functions (`handleIncomingRequest`) to prevent closure allocations per network packet.

### Code Organization and Tooling

* **Instance-Based Requires**: Changed require statements from path aliases (`@self/Client`, `./Utils/Buffers`) to direct instance paths (`script.Parent.Client`, `script.Parent.Utils.Buffers`).
* **Compiler Flags**: Added `--!native` and `--!optimize 2` directives to all modules.

---

## Fixed

* **Buffer Desynchronization on Dead Invoke Coroutines**: When an invoke caller coroutine was terminated before the response arrived, JoltOld left the response arguments unread in the buffer. Jolt correctly reads and discards remaining arguments to preserve reader cursor alignment.
* **Pending Request Counter Leaks**: Clamped pending request tracking using `math.max(0, count - 1)` to prevent counter corruption on timeouts.
* **Typing Bug in `Server:Once`**: Corrected `Server:Once` return type from `()` (void) to `Signal.Connection`.
* **Player Disconnection Leak on Invocation**: Added a `Players.PlayerRemoving` listener in `Server.Initialize()` to cancel active invoke timers and resume threads with `"Player disconnected"`.
* **Client Hang on Missing Remotes**: Replaced unbounded `script:WaitForChild()` calls with `script:FindFirstChild() or script:WaitForChild(..., 10)`, throwing a descriptive error upon timeout.
* **Mid-Frame Disconnection Crashes**: Added `player.Parent ~= nil and player:IsDescendantOf(Players)` checks inside `pcall` wrappers before sending packets to players.

---

## Removed

* **Table Reference Deduplication (`TYPE_REF`)**: Removed `refs` and `refCount` tracking from `Writer` and `Reader`. Eliminates table hashing overhead during writes.
* **`getfenv()` Script Lifecycle Tracking**: Removed `getScript()` and `_script` properties on Signal connections to prevent disabling Luau compiler optimizations.
* **Runtime Colon Checks**: Removed `typeof(self) ~= "table"` runtime assertions from methods (`Fire`, `Invoke`, `Connect`, etc.) to reduce instruction count on hot paths.
* **Unreliable Size Warning**: Removed string formatting and warning logs for unreliable packets exceeding 900 bytes.
* **`Send()` Helper Indirection**: Removed intermediate `Send()` wrapper functions; modules now write directly via `Packet.WriteEvent()`.
* **Legacy `Buffers.Pack()` / `Buffers.Unpack()`**: Removed unused high-level pack and unpack functions in favor of streaming reader/writer APIs.
