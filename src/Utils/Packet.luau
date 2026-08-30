--!strict
--!native
--!optimize 2

local Buffers = require(script.Parent.Buffers)
local Constants = require(script.Parent.Constants)

local Packet = {}

local MAX_PACKET_ARGUMENTS = Constants.MAX_PACKET_ARGUMENTS

local Buffers_ReadAny = Buffers.ReadAny
local Buffers_WriteAny = Buffers.WriteAny
local Buffers_WriteEventHeader = Buffers.WriteEventHeader

function Packet.ReadArguments(reader: Buffers.Reader, argumentCount: number): ...any
	if argumentCount <= 0 or reader.cursor >= reader.len then
		return
	end

	if argumentCount == 1 then
		return Buffers_ReadAny(reader)
	elseif argumentCount == 2 then
		return Buffers_ReadAny(reader), Buffers_ReadAny(reader)
	elseif argumentCount == 3 then
		return Buffers_ReadAny(reader), Buffers_ReadAny(reader), Buffers_ReadAny(reader)
	elseif argumentCount == 4 then
		return Buffers_ReadAny(reader), Buffers_ReadAny(reader), Buffers_ReadAny(reader), Buffers_ReadAny(reader)
	elseif argumentCount == 5 then
		return Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader)
	elseif argumentCount == 6 then
		return Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader)
	elseif argumentCount == 7 then
		return Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader)
	elseif argumentCount == 8 then
		return Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader),
			Buffers_ReadAny(reader)
	end

	local clampedCount = if argumentCount > MAX_PACKET_ARGUMENTS then MAX_PACKET_ARGUMENTS else argumentCount
	local argumentList = table.create(clampedCount) :: { any }

	for index = 1, clampedCount do
		if reader.cursor >= reader.len then
			break
		end
		argumentList[index] = Buffers_ReadAny(reader)
	end

	return table.unpack(argumentList, 1, clampedCount)
end

function Packet.WriteArguments(writer: Buffers.Writer, argumentCount: number, ...: any)
	if argumentCount == 1 then
		Buffers_WriteAny(writer, (...), 0)
	elseif argumentCount == 2 then
		local argumentA, argumentB = ...
		Buffers_WriteAny(writer, argumentA, 0)
		Buffers_WriteAny(writer, argumentB, 0)
	elseif argumentCount == 3 then
		local argumentA, argumentB, argumentC = ...
		Buffers_WriteAny(writer, argumentA, 0)
		Buffers_WriteAny(writer, argumentB, 0)
		Buffers_WriteAny(writer, argumentC, 0)
	elseif argumentCount == 4 then
		local argumentA, argumentB, argumentC, argumentD = ...
		Buffers_WriteAny(writer, argumentA, 0)
		Buffers_WriteAny(writer, argumentB, 0)
		Buffers_WriteAny(writer, argumentC, 0)
		Buffers_WriteAny(writer, argumentD, 0)
	elseif argumentCount == 5 then
		local argumentA, argumentB, argumentC, argumentD, argumentE = ...
		Buffers_WriteAny(writer, argumentA, 0)
		Buffers_WriteAny(writer, argumentB, 0)
		Buffers_WriteAny(writer, argumentC, 0)
		Buffers_WriteAny(writer, argumentD, 0)
		Buffers_WriteAny(writer, argumentE, 0)
	elseif argumentCount == 6 then
		local argumentA, argumentB, argumentC, argumentD, argumentE, argumentF = ...
		Buffers_WriteAny(writer, argumentA, 0)
		Buffers_WriteAny(writer, argumentB, 0)
		Buffers_WriteAny(writer, argumentC, 0)
		Buffers_WriteAny(writer, argumentD, 0)
		Buffers_WriteAny(writer, argumentE, 0)
		Buffers_WriteAny(writer, argumentF, 0)
	elseif argumentCount == 7 then
		local argumentA, argumentB, argumentC, argumentD, argumentE, argumentF, argumentG = ...
		Buffers_WriteAny(writer, argumentA, 0)
		Buffers_WriteAny(writer, argumentB, 0)
		Buffers_WriteAny(writer, argumentC, 0)
		Buffers_WriteAny(writer, argumentD, 0)
		Buffers_WriteAny(writer, argumentE, 0)
		Buffers_WriteAny(writer, argumentF, 0)
		Buffers_WriteAny(writer, argumentG, 0)
	elseif argumentCount == 8 then
		local argumentA, argumentB, argumentC, argumentD, argumentE, argumentF, argumentG, argumentH = ...
		Buffers_WriteAny(writer, argumentA, 0)
		Buffers_WriteAny(writer, argumentB, 0)
		Buffers_WriteAny(writer, argumentC, 0)
		Buffers_WriteAny(writer, argumentD, 0)
		Buffers_WriteAny(writer, argumentE, 0)
		Buffers_WriteAny(writer, argumentF, 0)
		Buffers_WriteAny(writer, argumentG, 0)
		Buffers_WriteAny(writer, argumentH, 0)
	elseif argumentCount > 8 then
		local packedArgs = table.pack(...)
		for index = 1, argumentCount do
			Buffers_WriteAny(writer, packedArgs[index], 0)
		end
	end
end

function Packet.WriteEvent(writer: Buffers.Writer, channelHash: number, packetType: number, ...: any)
	local argumentCount = select("#", ...)
	Buffers_WriteEventHeader(writer, channelHash, packetType, argumentCount)

	if argumentCount == 1 then
		Buffers_WriteAny(writer, (...), 0)
	elseif argumentCount == 2 then
		local argumentA, argumentB = ...
		Buffers_WriteAny(writer, argumentA, 0)
		Buffers_WriteAny(writer, argumentB, 0)
	elseif argumentCount == 3 then
		local argumentA, argumentB, argumentC = ...
		Buffers_WriteAny(writer, argumentA, 0)
		Buffers_WriteAny(writer, argumentB, 0)
		Buffers_WriteAny(writer, argumentC, 0)
	elseif argumentCount == 4 then
		local argumentA, argumentB, argumentC, argumentD = ...
		Buffers_WriteAny(writer, argumentA, 0)
		Buffers_WriteAny(writer, argumentB, 0)
		Buffers_WriteAny(writer, argumentC, 0)
		Buffers_WriteAny(writer, argumentD, 0)
	elseif argumentCount > 4 then
		Packet.WriteArguments(writer, argumentCount, ...)
	end
end

return Packet