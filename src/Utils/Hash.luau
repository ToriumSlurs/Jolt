--!strict
--!native
--!optimize 2

local Hash = {}

local nameHashCache: { [string]: number } = {}

local FNV_PRIME = 0x01000193
local FNV_OFFSET_BASIS = 0x811C9DC5

function Hash.HashName(channelName: string): number
	local cachedHash = nameHashCache[channelName]
	if cachedHash ~= nil then
		return cachedHash
	end

	local hashValue = FNV_OFFSET_BASIS
	local nameLength = #channelName

	for index = 1, nameLength do
		local characterByte = string.byte(channelName, index)
		hashValue = bit32.bxor(hashValue, characterByte)
		hashValue = bit32.band(hashValue * FNV_PRIME, 0xFFFFFFFF)
	end

	local foldedHash16 = bit32.band(bit32.bxor(bit32.rshift(hashValue, 16), hashValue), 0xFFFF)
	nameHashCache[channelName] = foldedHash16
	return foldedHash16
end

return Hash
