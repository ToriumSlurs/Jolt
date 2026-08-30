--!strict
--!native
--!optimize 2

local Hash = {}

local nameHashCache: { [string]: number } = {}

local FNV_PRIME = 0x01000193
local FNV_OFFSET_BASIS = 0x811C9DC5

local string_byte = string.byte
local bit_bxor = bit32.bxor
local bit_band = bit32.band
local bit_rshift = bit32.rshift

function Hash.HashName(channelName: string): number
	local cachedHash = nameHashCache[channelName]
	if cachedHash ~= nil then
		return cachedHash
	end

	local hashValue = FNV_OFFSET_BASIS
	local nameLength = #channelName

	for index = 1, nameLength do
		local characterByte = string_byte(channelName, index)
		hashValue = bit_bxor(hashValue, characterByte)
		hashValue = bit_band(hashValue * FNV_PRIME, 0xFFFFFFFF)
	end

	local foldedHash16 = bit_band(bit_bxor(bit_rshift(hashValue, 16), hashValue), 0xFFFF)
	nameHashCache[channelName] = foldedHash16
	return foldedHash16
end

return Hash
