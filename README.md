<div align="center">
  <h1>Jolt ⚡</h1>
  <p>
    <strong>High-performance networking for Roblox. Simplified.</strong>
  </p>
  
  <a href="https://github.com/ToriumSlurs/jolt/blob/main/LICENSE"><img src="https://img.shields.io/github/license/ToriumSlurs/jolt?style=flat" alt="License"></a>
</div>

---

## 📖 About

**Jolt** is a lightweight networking library designed to replace standard `RemoteEvent`, `UnreliableRemoteEvent` and `RemoteFunction` usage with a streamlined, strictly typed API.

If you have used the [Warp](https://github.com/imezx/Warp) networking library before, you will find Jolt's API very familiar. Since Warp has been archived, I wanted to create a modern, reliable alternative that developers can count on, including myself. 
## 🤝 Contributing & Feedback 
I am actively looking for help with: 
* **Testing:** properly testing the module, especially covering edge cases. 
* **Improvements:** suggestions or PRs to improve performance or usability. 
* **Bug Fixes:** identifying and fixing any issues that arise. 

If you're interested in helping out or just want to use a maintained, high-performance networking library, please check it out!

## ✨ Features

* **⚡ Blazing Fast:** Zero-allocation packet handling via buffer serialization.
* **🔒 Type Safe:** Full Luau type checking and autocomplete support.
* **📦 Compact:** Automatic data compression and circular table support.
* **🔄 Hybrid Networking:** Every event supports both reliable and unreliable messaging out of the box.
* **🧘 Developer Friendly:** Simple, declarative syntax that gets out of your way.

## 🚀 Usage

### Server Example
```lua
local Jolt = require(path.to.Jolt)

-- Create a new event
local MyEvent = Jolt.Server("MyEvent")

-- Fire an event to a client
MyEvent:Fire(player, "Hello from the server!")

-- Listen for client events
MyEvent:Connect(function(player, message)
    print(player.Name, "sent:", message)
end)

-- Handle client invokes
MyEvent.OnInvoke = function(player, data)
	return "Hello, " .. player.Name .. "!"
end
```

### Client Example
```lua
local Jolt = require(path.to.Jolt)

-- Create a new event
local MyEvent = Jolt.Client("MyEvent")

-- Listen for server events
MyEvent:Connect(function(message)
    print("Server sent:", message)
end)

-- Fire an event to the server
MyEvent:Fire("Hello from the client!")

-- Invoke the server
local response = MyEvent:Invoke()
print(response) -- "Hello, Player1!"
```

### Server-to-Client Invocations
Jolt supports full round-trip invocations.

```lua
-- Server
local MyInvoke = Jolt.Server("MyInvoke")
local success, response = pcall(function()
    return MyInvoke:Invoke(player, "Requesting data")
end)

-- Client
local MyInvoke = Jolt.Client("MyInvoke")
MyInvoke.OnInvoke = function(data)
    return "Processed: " .. data
end
```

### Disconnection & Resilience
Jolt is built to be resilient to script lifecycle changes. If a script is destroyed, its connections are **automatically cleaned up** to prevent memory leaks.

However, if you need to stop listening while the script is still running, you can manually disconnect:

```lua
local connection = MyEvent:Connect(function(...)
    print("Received event!")
end)

-- Stop listening manually
connection:Disconnect()
```

### With Generics
For enhanced type safety, you can provide a type cast to your Jolt objects. The generic parameters are `<Args...>` for event/invoke arguments and `<Out...>` for invoke return values.

```lua
-- Server
local myEvent = Jolt.Server("MyEvent") :: Jolt.Server<{ Arg: string }>
myEvent:Fire(player, { Arg = "Hello World" })

local myInvokeEvent = Jolt.Server("MyInvokeEvent") :: Jolt.Server<(), (boolean, string)>
myInvokeEvent.OnInvoke = function(player)
  return true, "Success!"
end

-- Client
local myEvent = Jolt.Client("MyEvent") :: Jolt.Client<{ Arg: string }>
myEvent:Connect(function(data)
  print(data.Arg)
end)

local myInvokeEvent = Jolt.Client("MyInvokeEvent") :: Jolt.Client<(), (boolean, string)>
local success, message = myInvokeEvent:Invoke()
```

## 📦 Supported Types

Jolt automatically serializes the following types:

* `nil`
* `boolean`
* `buffer`
* `number`
* `string`
* `table`
* `Instance`
* `Vector3`
* `Vector2`
* `CFrame`
* `Color3`
* `BrickColor`
* `Region3`
* `EnumItem`
* `UDim`, `UDim2`
* `TweenInfo`
