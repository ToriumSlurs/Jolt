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

## ✨ Features

* **⚡ Blazing Fast:** Zero-allocation packet handling via buffer serialization.
* **🔒 Type Safe:** Full Luau type checking and autocomplete support.
* **📦 Compact:** Automatic data compression.
* **🔄 Hybrid Networking:** Every event supports both reliable and unreliable messaging out of the box.
* **🧘 Developer Friendly:** Simple, declarative syntax that gets out of your way.

## 🚀 Usage

### Server Example
```lua
local Jolt = require(path.to.Jolt)

-- Create a network object (automatically creates reliable and unreliable channels)
local MyEvent = Jolt.Server("MyEvent")

-- Listen for events (receives from both channels)
MyEvent:Connect(function(player, data)
    print(player.Name, "sent:", data)
end)

-- Handle invokes
MyEvent.OnInvoke = function(player, requestData)
    return "Response to " .. player.Name
end

-- Fire Reliable (Important data)
MyEvent:Fire(somePlayer, "Hello World!")
MyEvent:FireAll("Attention everyone!")

-- Fire Unreliable (Fast, volatile data like positions/effects)
MyEvent:FireUnreliable(somePlayer, workspace.Part.Position)
MyEvent:FireAllUnreliable(workspace.Part.Position)
```

### Client Example
```lua
local Jolt = require(path.to.Jolt)

local MyEvent = Jolt.Client("MyEvent")

-- Listen for events
MyEvent:Connect(function(data)
    print("Server sent:", data)
end)

-- Fire Reliable
MyEvent:Fire("Hello World!")

-- Fire Unreliable
MyEvent:FireUnreliable(LocalPlayer.Character.HumanoidRootPart.Position)

-- Invoke the server and wait for a response
local response = MyEvent:Invoke("Can I buy this?")
print(response)
```

## 📦 Supported Types

Jolt automatically serializes the following types:

* `nil`
* `boolean`
* `number`
* `string`
* `table`
* `Instance`
* `Vector3`
* `Vector2`
* `CFrame`
* `Color3`
* `BrickColor`
* `EnumItem`
* `UDim`, `UDim2`
* `TweenInfo`
