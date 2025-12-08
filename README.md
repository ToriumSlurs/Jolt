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
