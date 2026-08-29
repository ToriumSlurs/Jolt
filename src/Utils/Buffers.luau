--!strict
--!native
--!optimize 2
local Buffers = {}
local buffer_create = buffer.create
local buffer_len = buffer.len
local buffer_copy = buffer.copy
local buffer_readu8 = buffer.readu8
local buffer_writeu8 = buffer.writeu8
local buffer_readu16 = buffer.readu16
local buffer_writeu16 = buffer.writeu16
local buffer_readu32 = buffer.readu32
local buffer_writeu32 = buffer.writeu32
local buffer_readi8 = buffer.readi8
local buffer_writei8 = buffer.writei8
local buffer_readi16 = buffer.readi16
local buffer_writei16 = buffer.writei16
local buffer_readi32 = buffer.readi32
local buffer_writei32 = buffer.writei32
local buffer_readf32 = buffer.readf32
local buffer_writef32 = buffer.writef32
local buffer_readf64 = buffer.readf64
local buffer_writef64 = buffer.writef64
local buffer_readstring = buffer.readstring
local buffer_writestring = buffer.writestring
local bit_bor = bit32.bor
local bit_band = bit32.band
local bit_lshift = bit32.lshift
local bit_rshift = bit32.rshift
local table_create = table.create
local table_insert = table.insert
local table_clear = table.clear
local table_concat = table.concat
local table_sort = table.sort
local math_abs = math.abs
local math_max = math.max
local math_pi = math.pi
local string_sub = string.sub
local scratchFloatConversionBuffer = buffer_create(8)
local recycledStringLengthsBuffer: { [number]: number } = {}
local enumItemsByNameCache: { [string]: { [number]: EnumItem } } = {}
local function getCachedEnumItem(enumName: string, enumValue: number): EnumItem?
	if enumName == "" then
		return nil
	end
	local itemsByValue = enumItemsByNameCache[enumName]
	if not itemsByValue then
		itemsByValue = {}
		local isSuccess, enumType = pcall(function()
			return (Enum :: any)[enumName]
		end)
		if isSuccess and typeof(enumType) == "Enum" then
			for _, enumItem in (enumType :: Enum):GetEnumItems() do
				itemsByValue[enumItem.Value] = enumItem
			end
		end
		enumItemsByNameCache[enumName] = itemsByValue
	end
	return itemsByValue[enumValue]
end
local byteToBooleanLookupTable: { [number]: { [number]: boolean } } = {}
for byteValue = 0, 255 do
	byteToBooleanLookupTable[byteValue] = {
		bit_band(byteValue, 1) ~= 0,
		bit_band(byteValue, 2) ~= 0,
		bit_band(byteValue, 4) ~= 0,
		bit_band(byteValue, 8) ~= 0,
		bit_band(byteValue, 16) ~= 0,
		bit_band(byteValue, 32) ~= 0,
		bit_band(byteValue, 64) ~= 0,
		bit_band(byteValue, 128) ~= 0,
	}
end
local function writeUnsigned24(targetBuffer: buffer, offset: number, value: number)
	buffer_writeu8(targetBuffer, offset, bit_band(value, 0xFF))
	buffer_writeu8(targetBuffer, offset + 1, bit_band(bit_rshift(value, 8), 0xFF))
	buffer_writeu8(targetBuffer, offset + 2, bit_band(bit_rshift(value, 16), 0xFF))
end
local function readUnsigned24(sourceBuffer: buffer, offset: number): number
	local byteA = buffer_readu8(sourceBuffer, offset)
	local byteB = buffer_readu8(sourceBuffer, offset + 1)
	local byteC = buffer_readu8(sourceBuffer, offset + 2)
	return bit_bor(byteA, bit_lshift(byteB, 8), bit_lshift(byteC, 16))
end
local function writeSigned24(targetBuffer: buffer, offset: number, value: number)
	local unsignedValue = if value < 0 then value + 0x1000000 else value
	writeUnsigned24(targetBuffer, offset, unsignedValue)
end
local function readSigned24(sourceBuffer: buffer, offset: number): number
	local unsignedValue = readUnsigned24(sourceBuffer, offset)
	return if unsignedValue >= 0x800000 then unsignedValue - 0x1000000 else unsignedValue
end
local function encodeFloat16(value: number): number?
	buffer_writef32(scratchFloatConversionBuffer, 0, value)
	local uintRepresentation = buffer_readu32(scratchFloatConversionBuffer, 0)
	local exponent = bit_band(bit_rshift(uintRepresentation, 23), 0xFF)
	if exponent == 0 then
		return if bit_band(uintRepresentation, 0x7FFFFF) == 0 then bit_rshift(uintRepresentation, 16) else nil
	end
	if bit_band(uintRepresentation, 0x1FFF) ~= 0 then
		return nil
	end
	local biasedExponent = exponent - 127 + 15
	if biasedExponent < 1 or biasedExponent > 30 then
		return nil
	end
	return bit_bor(
		bit_band(bit_rshift(uintRepresentation, 16), 0x8000),
		bit_lshift(biasedExponent, 10),
		bit_rshift(bit_band(uintRepresentation, 0x7FFFFF), 13)
	)
end
local function decodeFloat16(float16Bits: number): number
	local exponent = bit_band(bit_rshift(float16Bits, 10), 0x1F)
	local fraction = bit_band(float16Bits, 0x3FF)
	local signBit = bit_rshift(float16Bits, 15)
	if exponent == 0 then
		local signMultiplier = if signBit == 1 then -1 else 1
		return signMultiplier * (fraction / 1024) * (2 ^ -14)
	end
	if exponent == 31 then
		if fraction == 0 then
			return if signBit == 1 then -math.huge else math.huge
		else
			return 0 / 0
		end
	end
	local float32Bits = bit_bor(
		bit_lshift(signBit, 31),
		bit_lshift(exponent - 15 + 127, 23),
		bit_lshift(fraction, 13)
	)
	buffer_writeu32(scratchFloatConversionBuffer, 0, float32Bits)
	return buffer_readf32(scratchFloatConversionBuffer, 0)
end
local function encodeFloat24(value: number): number?
	buffer_writef32(scratchFloatConversionBuffer, 0, value)
	local uintRepresentation = buffer_readu32(scratchFloatConversionBuffer, 0)
	if bit_band(uintRepresentation, 0xFF) ~= 0 then
		return nil
	end
	return bit_bor(bit_band(bit_rshift(uintRepresentation, 8), 0xFFFFFF))
end
local function decodeFloat24(float24Bits: number): number
	buffer_writeu32(scratchFloatConversionBuffer, 0, bit_lshift(float24Bits, 8))
	return buffer_readf32(scratchFloatConversionBuffer, 0)
end
local function writeFloat16Bytes(targetBuffer: buffer, offset: number, float16Bits: number)
	buffer_writeu8(targetBuffer, offset, bit_band(float16Bits, 0xFF))
	buffer_writeu8(targetBuffer, offset + 1, bit_rshift(float16Bits, 8))
end
local function readFloat16Bytes(sourceBuffer: buffer, offset: number): number
	local byteA = buffer_readu8(sourceBuffer, offset)
	local byteB = buffer_readu8(sourceBuffer, offset + 1)
	return bit_bor(byteA, bit_lshift(byteB, 8))
end
local function writeFloat24Bytes(targetBuffer: buffer, offset: number, float24Bits: number)
	buffer_writeu8(targetBuffer, offset, bit_band(float24Bits, 0xFF))
	buffer_writeu8(targetBuffer, offset + 1, bit_band(bit_rshift(float24Bits, 8), 0xFF))
	buffer_writeu8(targetBuffer, offset + 2, bit_band(bit_rshift(float24Bits, 16), 0xFF))
end
local function readFloat24Bytes(sourceBuffer: buffer, offset: number): number
	local byteA = buffer_readu8(sourceBuffer, offset)
	local byteB = buffer_readu8(sourceBuffer, offset + 1)
	local byteC = buffer_readu8(sourceBuffer, offset + 2)
	return bit_bor(byteA, bit_lshift(byteB, 8), bit_lshift(byteC, 16))
end
local TAG_NIL = 0
local TAG_FALSE = 1
local TAG_TRUE = 2
local TAG_U8 = 3
local TAG_U16 = 4
local TAG_U24 = 5
local TAG_U32 = 6
local TAG_I8 = 7
local TAG_I16 = 8
local TAG_I24 = 9
local TAG_I32 = 10
local TAG_F16 = 11
local TAG_F24 = 12
local TAG_F32 = 13
local TAG_F64 = 14
local TAG_STR8 = 15
local TAG_STR16 = 16
local TAG_STR_VAR = 17
local TAG_BUFFER = 18
local TAG_VEC2_F16 = 19
local TAG_VEC2 = 20
local TAG_VEC3_F16 = 21
local TAG_VEC3 = 22
local TAG_CF_POS = 23
local TAG_CF_YAW = 24
local TAG_CF = 25
local TAG_COLOR3 = 26
local TAG_UDIM = 27
local TAG_UDIM2 = 28
local TAG_INSTANCE = 29
local TAG_ENUM_U8 = 30
local TAG_ENUM = 31
local TAG_TWEEN = 32
local TAG_BRICKCOLOR = 33
local TAG_COLOR_SEQ = 34
local TAG_COLOR_SEQ_KP = 35
local TAG_NUM_RANGE = 36
local TAG_NUM_SEQ = 37
local TAG_NUM_SEQ_KP = 38
local TAG_REGION3 = 39
local TAG_REGION3I16 = 40
local TAG_VEC2I16 = 41
local TAG_VEC3I16 = 42
local TAG_RECT = 43
local TAG_DATETIME = 44
local TAG_RAY = 45
local TAG_ARRAY = 46
local TAG_MAP = 47
local TAG_ARR_I8 = 48
local TAG_ARR_I16 = 49
local TAG_ARR_I32 = 50
local TAG_ARR_F32 = 51
local TAG_ARR_F64 = 52
local TAG_ARR_BOOL = 53
local TAG_ARR_STR = 54
local TAG_ARR_VEC2 = 55
local TAG_ARR_VEC3 = 56
local TAG_ARR_COLOR3 = 57
local TAG_ARR_CF = 58
local TAG_ARR_U8 = 59
local TAG_ARR_U16 = 60
local TAG_ARR_U32 = 61
local TAG_ARR_STRUCT = 62
local TAG_MAP_STR_U8 = 63
export type Writer = {
	buff: buffer,
	cursor: number,
	len: number,
	insts: { Instance },
}
export type Reader = {
	buff: buffer,
	cursor: number,
	len: number,
	insts: { Instance },
}
local WRITER_POOL: { Writer } = {}
local READER_POOL: { Reader } = {}
local MAX_POOL_CAPACITY = 128
local MAX_POOLED_BUFFER_SIZE = 131072
local INITIAL_BUFFER_CAPACITY = 4096
local MAX_SERIALIZATION_DEPTH = 16
local function growWriterCapacity(writer: Writer, requiredBytes: number)
	local currentCapacity = writer.len
	if currentCapacity == 0 then
		currentCapacity = INITIAL_BUFFER_CAPACITY
	end
	local targetCapacity = writer.cursor + requiredBytes
	while targetCapacity > currentCapacity do
		currentCapacity *= 2
	end
	local newBuffer = buffer_create(currentCapacity)
	buffer_copy(newBuffer, 0, writer.buff, 0, writer.cursor)
	writer.buff = newBuffer
	writer.len = currentCapacity
end
local function ensureCapacity(writer: Writer, requiredBytes: number)
	if writer.cursor + requiredBytes > writer.len then
		growWriterCapacity(writer, requiredBytes)
	end
end
local function writeVariableInteger(writer: Writer, integerValue: number)
	ensureCapacity(writer, 5)
	local targetBuffer = writer.buff
	local cursor = writer.cursor
	while integerValue >= 128 do
		buffer_writeu8(targetBuffer, cursor, bit_bor(integerValue, 0x80))
		cursor += 1
		integerValue = bit_rshift(integerValue, 7)
	end
	buffer_writeu8(targetBuffer, cursor, integerValue)
	writer.cursor = cursor + 1
end
local function readVariableInteger(reader: Reader): number
	local accumulatedResult = 0
	local bitShift = 0
	local sourceBuffer = reader.buff
	local cursor = reader.cursor
	local bufferLength = reader.len
	repeat
		if cursor >= bufferLength or bitShift > 28 then
			break
		end
		local currentByte = buffer_readu8(sourceBuffer, cursor)
		cursor += 1
		accumulatedResult = bit_bor(accumulatedResult, bit_lshift(bit_band(currentByte, 0x7F), bitShift))
		bitShift += 7
	until bit_band(currentByte, 0x80) == 0
	reader.cursor = cursor
	return accumulatedResult
end
local function writeLengthPrefixedString(writer: Writer, stringValue: string)
	local stringLength = #stringValue
	ensureCapacity(writer, 5 + stringLength)
	local targetBuffer = writer.buff
	local cursor = writer.cursor
	local remainingLength = stringLength
	while remainingLength >= 128 do
		buffer_writeu8(targetBuffer, cursor, bit_bor(remainingLength, 0x80))
		cursor += 1
		remainingLength = bit_rshift(remainingLength, 7)
	end
	buffer_writeu8(targetBuffer, cursor, remainingLength)
	cursor += 1
	if stringLength > 0 then
		buffer_writestring(targetBuffer, cursor, stringValue, stringLength)
	end
	writer.cursor = cursor + stringLength
end
local function readLengthPrefixedString(reader: Reader): string
	local decodedLength = 0
	local bitShift = 0
	local sourceBuffer = reader.buff
	local cursor = reader.cursor
	local bufferLength = reader.len
	repeat
		if cursor >= bufferLength or bitShift > 28 then
			break
		end
		local currentByte = buffer_readu8(sourceBuffer, cursor)
		cursor += 1
		decodedLength = bit_bor(decodedLength, bit_lshift(bit_band(currentByte, 0x7F), bitShift))
		bitShift += 7
	until bit_band(currentByte, 0x80) == 0
	if decodedLength <= 0 or cursor >= bufferLength then
		reader.cursor = cursor
		return ""
	end
	if cursor + decodedLength > bufferLength then
		decodedLength = math_max(0, bufferLength - cursor)
	end
	local resultString = if decodedLength > 0 then buffer_readstring(sourceBuffer, cursor, decodedLength) else ""
	reader.cursor = cursor + decodedLength
	return resultString
end
local DeserializerHandlers: { [number]: (reader: Reader) -> any } = {}
DeserializerHandlers[TAG_ENUM_U8] = function(reader: Reader): any
	local enumName = readLengthPrefixedString(reader)
	local cursor = reader.cursor
	if cursor >= reader.len then
		return nil
	end
	local enumValue = buffer_readu8(reader.buff, cursor)
	reader.cursor = cursor + 1
	return getCachedEnumItem(enumName, enumValue)
end
DeserializerHandlers[TAG_ENUM] = function(reader)
	local enumName = readLengthPrefixedString(reader)
	local enumValue = readVariableInteger(reader)
	return getCachedEnumItem(enumName, enumValue)
end
DeserializerHandlers[TAG_TWEEN] = function(reader)
	local cursor = reader.cursor
	if cursor + 16 > reader.len then
		reader.cursor = reader.len
		return TweenInfo.new()
	end
	reader.cursor = cursor + 16
	local duration = buffer_readf32(reader.buff, cursor)
	local styleValue = buffer_readu8(reader.buff, cursor + 4)
	local directionValue = buffer_readu8(reader.buff, cursor + 5)
	local repeatCount = buffer_readi32(reader.buff, cursor + 6)
	local reverses = buffer_readu8(reader.buff, cursor + 10) == 1
	local delayTime = buffer_readf32(reader.buff, cursor + 12)
	local easingStyle: any = getCachedEnumItem("EasingStyle", styleValue) or Enum.EasingStyle.Quad
	local easingDirection: any = getCachedEnumItem("EasingDirection", directionValue) or Enum.EasingDirection.Out
	local isSuccess, createdTween = pcall(TweenInfo.new, duration, easingStyle, easingDirection, repeatCount, reverses, delayTime)
	return if isSuccess and createdTween then createdTween else TweenInfo.new()
end
DeserializerHandlers[TAG_COLOR_SEQ] = function(reader)
	local cursor = reader.cursor
	if cursor >= reader.len then
		return ColorSequence.new(Color3.new(1, 1, 1))
	end
	local keypointCount = buffer_readu8(reader.buff, cursor)
	cursor += 1
	local keypointList: { ColorSequenceKeypoint } = {}
	for _ = 1, keypointCount do
		if cursor + 7 > reader.len then
			break
		end
		local timePosition = buffer_readf32(reader.buff, cursor)
		local colorR = buffer_readu8(reader.buff, cursor + 4)
		local colorG = buffer_readu8(reader.buff, cursor + 5)
		local colorB = buffer_readu8(reader.buff, cursor + 6)
		table_insert(keypointList, ColorSequenceKeypoint.new(timePosition, Color3.fromRGB(colorR, colorG, colorB)))
		cursor += 7
	end
	reader.cursor = cursor
	if #keypointList >= 2 then
		local isSuccess, sequence = pcall(function() return ColorSequence.new(keypointList) end)
		if isSuccess and sequence then
			return sequence
		end
	end
	return ColorSequence.new(Color3.new(1, 1, 1))
end
DeserializerHandlers[TAG_COLOR_SEQ_KP] = function(reader)
	local cursor = reader.cursor
	if cursor + 7 > reader.len then
		reader.cursor = reader.len
		return ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1))
	end
	reader.cursor = cursor + 7
	local timePosition = buffer_readf32(reader.buff, cursor)
	local colorR = buffer_readu8(reader.buff, cursor + 4)
	local colorG = buffer_readu8(reader.buff, cursor + 5)
	local colorB = buffer_readu8(reader.buff, cursor + 6)
	local isSuccess, keypoint = pcall(ColorSequenceKeypoint.new, timePosition, Color3.fromRGB(colorR, colorG, colorB))
	return if isSuccess and keypoint then keypoint else ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1))
end
DeserializerHandlers[TAG_NUM_RANGE] = function(reader)
	local cursor = reader.cursor
	if cursor + 8 > reader.len then
		reader.cursor = reader.len
		return NumberRange.new(0, 0)
	end
	reader.cursor = cursor + 8
	local minimumValue = buffer_readf32(reader.buff, cursor)
	local maximumValue = buffer_readf32(reader.buff, cursor + 4)
	if minimumValue > maximumValue then
		return NumberRange.new(maximumValue, minimumValue)
	end
	return NumberRange.new(minimumValue, maximumValue)
end
DeserializerHandlers[TAG_NUM_SEQ] = function(reader)
	local cursor = reader.cursor
	if cursor >= reader.len then
		return NumberSequence.new(0)
	end
	local keypointCount = buffer_readu8(reader.buff, cursor)
	cursor += 1
	local keypointList: { NumberSequenceKeypoint } = {}
	for _ = 1, keypointCount do
		if cursor + 12 > reader.len then
			break
		end
		local timePosition = buffer_readf32(reader.buff, cursor)
		local value = buffer_readf32(reader.buff, cursor + 4)
		local envelope = buffer_readf32(reader.buff, cursor + 8)
		table_insert(keypointList, NumberSequenceKeypoint.new(timePosition, value, envelope))
		cursor += 12
	end
	reader.cursor = cursor
	if #keypointList >= 2 then
		local isSuccess, sequence = pcall(function() return NumberSequence.new(keypointList) end)
		if isSuccess and sequence then
			return sequence
		end
	end
	return NumberSequence.new(0)
end
DeserializerHandlers[TAG_NUM_SEQ_KP] = function(reader)
	local cursor = reader.cursor
	if cursor + 12 > reader.len then
		reader.cursor = reader.len
		return NumberSequenceKeypoint.new(0, 0, 0)
	end
	reader.cursor = cursor + 12
	local timePosition = buffer_readf32(reader.buff, cursor)
	local value = buffer_readf32(reader.buff, cursor + 4)
	local envelope = buffer_readf32(reader.buff, cursor + 8)
	local isSuccess, keypoint = pcall(NumberSequenceKeypoint.new, timePosition, value, envelope)
	return if isSuccess and keypoint then keypoint else NumberSequenceKeypoint.new(0, 0, 0)
end
DeserializerHandlers[TAG_REGION3] = function(reader)
	local cursor = reader.cursor
	if cursor + 24 > reader.len then
		reader.cursor = reader.len
		return Region3.new(Vector3.zero, Vector3.zero)
	end
	reader.cursor = cursor + 24
	local minPosition = Vector3.new(
		buffer_readf32(reader.buff, cursor),
		buffer_readf32(reader.buff, cursor + 4),
		buffer_readf32(reader.buff, cursor + 8)
	)
	local maxPosition = Vector3.new(
		buffer_readf32(reader.buff, cursor + 12),
		buffer_readf32(reader.buff, cursor + 16),
		buffer_readf32(reader.buff, cursor + 20)
	)
	return Region3.new(minPosition, maxPosition)
end
DeserializerHandlers[TAG_REGION3I16] = function(reader)
	local cursor = reader.cursor
	if cursor + 12 > reader.len then
		reader.cursor = reader.len
		return Region3int16.new(Vector3int16.new(), Vector3int16.new())
	end
	reader.cursor = cursor + 12
	local minCoords = Vector3int16.new(
		buffer_readi16(reader.buff, cursor),
		buffer_readi16(reader.buff, cursor + 2),
		buffer_readi16(reader.buff, cursor + 4)
	)
	local maxCoords = Vector3int16.new(
		buffer_readi16(reader.buff, cursor + 6),
		buffer_readi16(reader.buff, cursor + 8),
		buffer_readi16(reader.buff, cursor + 10)
	)
	return Region3int16.new(minCoords, maxCoords)
end
DeserializerHandlers[TAG_VEC2I16] = function(reader)
	local cursor = reader.cursor
	if cursor + 4 > reader.len then
		reader.cursor = reader.len
		return Vector2int16.new()
	end
	reader.cursor = cursor + 4
	return Vector2int16.new(buffer_readi16(reader.buff, cursor), buffer_readi16(reader.buff, cursor + 2))
end
DeserializerHandlers[TAG_VEC3I16] = function(reader)
	local cursor = reader.cursor
	if cursor + 6 > reader.len then
		reader.cursor = reader.len
		return Vector3int16.new()
	end
	reader.cursor = cursor + 6
	return Vector3int16.new(
		buffer_readi16(reader.buff, cursor),
		buffer_readi16(reader.buff, cursor + 2),
		buffer_readi16(reader.buff, cursor + 4)
	)
end
DeserializerHandlers[TAG_RECT] = function(reader)
	local cursor = reader.cursor
	if cursor + 16 > reader.len then
		reader.cursor = reader.len
		return Rect.new(0, 0, 0, 0)
	end
	reader.cursor = cursor + 16
	return Rect.new(
		buffer_readf32(reader.buff, cursor),
		buffer_readf32(reader.buff, cursor + 4),
		buffer_readf32(reader.buff, cursor + 8),
		buffer_readf32(reader.buff, cursor + 12)
	)
end
DeserializerHandlers[TAG_DATETIME] = function(reader)
	local cursor = reader.cursor
	if cursor + 8 > reader.len then
		reader.cursor = reader.len
		return DateTime.fromUnixTimestampMillis(0)
	end
	reader.cursor = cursor + 8
	local timestampMilliseconds = buffer_readf64(reader.buff, cursor)
	if timestampMilliseconds ~= timestampMilliseconds or timestampMilliseconds < -17987443200000 or timestampMilliseconds > 253402300799999 then
		return DateTime.fromUnixTimestampMillis(0)
	end
	return DateTime.fromUnixTimestampMillis(timestampMilliseconds)
end
DeserializerHandlers[TAG_RAY] = function(reader)
	local cursor = reader.cursor
	if cursor + 24 > reader.len then
		reader.cursor = reader.len
		return Ray.new(Vector3.zero, Vector3.zero)
	end
	reader.cursor = cursor + 24
	local originPosition = Vector3.new(
		buffer_readf32(reader.buff, cursor),
		buffer_readf32(reader.buff, cursor + 4),
		buffer_readf32(reader.buff, cursor + 8)
	)
	local directionVector = Vector3.new(
		buffer_readf32(reader.buff, cursor + 12),
		buffer_readf32(reader.buff, cursor + 16),
		buffer_readf32(reader.buff, cursor + 20)
	)
	return Ray.new(originPosition, directionVector)
end
local function writeAnyValue(writer: Writer, targetValue: any, currentDepth: number) end
local function writeVector3Array(writer: Writer, targetTable: { [any]: any }, arrayLength: number)
	ensureCapacity(writer, 7 + arrayLength * 12)
	local targetBuffer = writer.buff
	local cursor = writer.cursor
	buffer_writeu8(targetBuffer, cursor, TAG_ARR_VEC3)
	cursor += 1
	local remainingCount = arrayLength
	while remainingCount >= 128 do
		buffer_writeu8(targetBuffer, cursor, bit_bor(remainingCount, 0x80))
		cursor += 1
		remainingCount = bit_rshift(remainingCount, 7)
	end
	buffer_writeu8(targetBuffer, cursor, remainingCount)
	cursor += 1
	for _, vectorItem: Vector3 in targetTable do
		buffer_writef32(targetBuffer, cursor, vectorItem.X)
		buffer_writef32(targetBuffer, cursor + 4, vectorItem.Y)
		buffer_writef32(targetBuffer, cursor + 8, vectorItem.Z)
		cursor += 12
	end
	writer.cursor = cursor
end
local function writeColor3Array(writer: Writer, targetTable: { [any]: any }, arrayLength: number)
	ensureCapacity(writer, 7 + arrayLength * 3)
	local targetBuffer = writer.buff
	local cursor = writer.cursor
	buffer_writeu8(targetBuffer, cursor, TAG_ARR_COLOR3)
	cursor += 1
	local remainingCount = arrayLength
	while remainingCount >= 128 do
		buffer_writeu8(targetBuffer, cursor, bit_bor(remainingCount, 0x80))
		cursor += 1
		remainingCount = bit_rshift(remainingCount, 7)
	end
	buffer_writeu8(targetBuffer, cursor, remainingCount)
	cursor += 1
	for _, colorItem: Color3 in targetTable do
		buffer_writeu8(targetBuffer, cursor, colorItem.R * 255 + 0.5)
		buffer_writeu8(targetBuffer, cursor + 1, colorItem.G * 255 + 0.5)
		buffer_writeu8(targetBuffer, cursor + 2, colorItem.B * 255 + 0.5)
		cursor += 3
	end
	writer.cursor = cursor
end
local function writeCFrameArray(writer: Writer, targetTable: { [any]: any }, arrayLength: number)
	ensureCapacity(writer, 7 + arrayLength * 48)
	local targetBuffer = writer.buff
	local cursor = writer.cursor
	buffer_writeu8(targetBuffer, cursor, TAG_ARR_CF)
	cursor += 1
	local remainingCount = arrayLength
	while remainingCount >= 128 do
		buffer_writeu8(targetBuffer, cursor, bit_bor(remainingCount, 0x80))
		cursor += 1
		remainingCount = bit_rshift(remainingCount, 7)
	end
	buffer_writeu8(targetBuffer, cursor, remainingCount)
	cursor += 1
	local rem = arrayLength % 2
	local unrolled = arrayLength - rem
	for index = 1, unrolled, 2 do
		local c1 = targetTable[index]
		local c2 = targetTable[index + 1]
		local x1, y1, z1, R00_1, R01_1, R02_1, R10_1, R11_1, R12_1, R20_1, R21_1, R22_1 = c1:GetComponents()
		local x2, y2, z2, R00_2, R01_2, R02_2, R10_2, R11_2, R12_2, R20_2, R21_2, R22_2 = c2:GetComponents()
		buffer_writef32(targetBuffer, cursor, x1)
		buffer_writef32(targetBuffer, cursor + 4, y1)
		buffer_writef32(targetBuffer, cursor + 8, z1)
		buffer_writef32(targetBuffer, cursor + 12, R00_1)
		buffer_writef32(targetBuffer, cursor + 16, R01_1)
		buffer_writef32(targetBuffer, cursor + 20, R02_1)
		buffer_writef32(targetBuffer, cursor + 24, R10_1)
		buffer_writef32(targetBuffer, cursor + 28, R11_1)
		buffer_writef32(targetBuffer, cursor + 32, R12_1)
		buffer_writef32(targetBuffer, cursor + 36, R20_1)
		buffer_writef32(targetBuffer, cursor + 40, R21_1)
		buffer_writef32(targetBuffer, cursor + 44, R22_1)
		buffer_writef32(targetBuffer, cursor + 48, x2)
		buffer_writef32(targetBuffer, cursor + 52, y2)
		buffer_writef32(targetBuffer, cursor + 56, z2)
		buffer_writef32(targetBuffer, cursor + 60, R00_2)
		buffer_writef32(targetBuffer, cursor + 64, R01_2)
		buffer_writef32(targetBuffer, cursor + 68, R02_2)
		buffer_writef32(targetBuffer, cursor + 72, R10_2)
		buffer_writef32(targetBuffer, cursor + 76, R11_2)
		buffer_writef32(targetBuffer, cursor + 80, R12_2)
		buffer_writef32(targetBuffer, cursor + 84, R20_2)
		buffer_writef32(targetBuffer, cursor + 88, R21_2)
		buffer_writef32(targetBuffer, cursor + 92, R22_2)
		cursor += 96
	end
	for index = unrolled + 1, arrayLength do
		local c = targetTable[index]
		local x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = c:GetComponents()
		buffer_writef32(targetBuffer, cursor, x)
		buffer_writef32(targetBuffer, cursor + 4, y)
		buffer_writef32(targetBuffer, cursor + 8, z)
		buffer_writef32(targetBuffer, cursor + 12, R00)
		buffer_writef32(targetBuffer, cursor + 16, R01)
		buffer_writef32(targetBuffer, cursor + 20, R02)
		buffer_writef32(targetBuffer, cursor + 24, R10)
		buffer_writef32(targetBuffer, cursor + 28, R11)
		buffer_writef32(targetBuffer, cursor + 32, R12)
		buffer_writef32(targetBuffer, cursor + 36, R20)
		buffer_writef32(targetBuffer, cursor + 40, R21)
		buffer_writef32(targetBuffer, cursor + 44, R22)
		cursor += 48
	end
	writer.cursor = cursor
end
local function writeNumberArray(writer: Writer, targetTable: { [any]: any }, arrayLength: number, firstElement: number): boolean
	if firstElement % 1 == 0 then
		if firstElement >= 0 and firstElement <= 255 then
			ensureCapacity(writer, 7 + arrayLength)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_ARR_U8)
			cursor += 1
			local remainingCount = arrayLength
			while remainingCount >= 128 do
				buffer_writeu8(targetBuffer, cursor, bit_bor(remainingCount, 0x80))
				cursor += 1
				remainingCount = bit_rshift(remainingCount, 7)
			end
			buffer_writeu8(targetBuffer, cursor, remainingCount)
			cursor += 1
			local rem = arrayLength % 8
			local unrolled = arrayLength - rem
			for index = 1, unrolled, 8 do
				buffer_writeu8(targetBuffer, cursor, targetTable[index])
				buffer_writeu8(targetBuffer, cursor + 1, targetTable[index + 1])
				buffer_writeu8(targetBuffer, cursor + 2, targetTable[index + 2])
				buffer_writeu8(targetBuffer, cursor + 3, targetTable[index + 3])
				buffer_writeu8(targetBuffer, cursor + 4, targetTable[index + 4])
				buffer_writeu8(targetBuffer, cursor + 5, targetTable[index + 5])
				buffer_writeu8(targetBuffer, cursor + 6, targetTable[index + 6])
				buffer_writeu8(targetBuffer, cursor + 7, targetTable[index + 7])
				cursor += 8
			end
			for index = unrolled + 1, arrayLength do
				buffer_writeu8(targetBuffer, cursor, targetTable[index])
				cursor += 1
			end
			writer.cursor = cursor
			return true
		elseif firstElement >= -128 and firstElement <= 127 then
			ensureCapacity(writer, 7 + arrayLength)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_ARR_I8)
			cursor += 1
			local remainingCount = arrayLength
			while remainingCount >= 128 do
				buffer_writeu8(targetBuffer, cursor, bit_bor(remainingCount, 0x80))
				cursor += 1
				remainingCount = bit_rshift(remainingCount, 7)
			end
			buffer_writeu8(targetBuffer, cursor, remainingCount)
			cursor += 1
			for _, numberValue in targetTable do
				buffer_writei8(targetBuffer, cursor, numberValue)
				cursor += 1
			end
			writer.cursor = cursor
			return true
		elseif firstElement >= 0 and firstElement <= 65535 then
			ensureCapacity(writer, 7 + arrayLength * 2)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_ARR_U16)
			cursor += 1
			local remainingCount = arrayLength
			while remainingCount >= 128 do
				buffer_writeu8(targetBuffer, cursor, bit_bor(remainingCount, 0x80))
				cursor += 1
				remainingCount = bit_rshift(remainingCount, 7)
			end
			buffer_writeu8(targetBuffer, cursor, remainingCount)
			cursor += 1
			for _, numberValue in targetTable do
				buffer_writeu16(targetBuffer, cursor, numberValue)
				cursor += 2
			end
			writer.cursor = cursor
			return true
		elseif firstElement >= -32768 and firstElement <= 32767 then
			ensureCapacity(writer, 7 + arrayLength * 2)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_ARR_I16)
			cursor += 1
			local remainingCount = arrayLength
			while remainingCount >= 128 do
				buffer_writeu8(targetBuffer, cursor, bit_bor(remainingCount, 0x80))
				cursor += 1
				remainingCount = bit_rshift(remainingCount, 7)
			end
			buffer_writeu8(targetBuffer, cursor, remainingCount)
			cursor += 1
			for _, numberValue in targetTable do
				buffer_writei16(targetBuffer, cursor, numberValue)
				cursor += 2
			end
			writer.cursor = cursor
			return true
		elseif firstElement >= 0 and firstElement <= 4294967295 then
			ensureCapacity(writer, 7 + arrayLength * 4)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_ARR_U32)
			cursor += 1
			local remainingCount = arrayLength
			while remainingCount >= 128 do
				buffer_writeu8(targetBuffer, cursor, bit_bor(remainingCount, 0x80))
				cursor += 1
				remainingCount = bit_rshift(remainingCount, 7)
			end
			buffer_writeu8(targetBuffer, cursor, remainingCount)
			cursor += 1
			for _, numberValue in targetTable do
				buffer_writeu32(targetBuffer, cursor, numberValue)
				cursor += 4
			end
			writer.cursor = cursor
			return true
		else
			ensureCapacity(writer, 7 + arrayLength * 4)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_ARR_I32)
			cursor += 1
			local remainingCount = arrayLength
			while remainingCount >= 128 do
				buffer_writeu8(targetBuffer, cursor, bit_bor(remainingCount, 0x80))
				cursor += 1
				remainingCount = bit_rshift(remainingCount, 7)
			end
			buffer_writeu8(targetBuffer, cursor, remainingCount)
			cursor += 1
			for _, numberValue in targetTable do
				buffer_writei32(targetBuffer, cursor, numberValue)
				cursor += 4
			end
			writer.cursor = cursor
			return true
		end
	else
		ensureCapacity(writer, 7 + arrayLength * 4)
		local targetBuffer = writer.buff
		local cursor = writer.cursor
		buffer_writeu8(targetBuffer, cursor, TAG_ARR_F32)
		cursor += 1
		local remainingCount = arrayLength
		while remainingCount >= 128 do
			buffer_writeu8(targetBuffer, cursor, bit_bor(remainingCount, 0x80))
			cursor += 1
			remainingCount = bit_rshift(remainingCount, 7)
		end
		buffer_writeu8(targetBuffer, cursor, remainingCount)
		cursor += 1
		local rem = arrayLength % 8
		local unrolled = arrayLength - rem
		for index = 1, unrolled, 8 do
			buffer_writef32(targetBuffer, cursor, targetTable[index])
			buffer_writef32(targetBuffer, cursor + 4, targetTable[index + 1])
			buffer_writef32(targetBuffer, cursor + 8, targetTable[index + 2])
			buffer_writef32(targetBuffer, cursor + 12, targetTable[index + 3])
			buffer_writef32(targetBuffer, cursor + 16, targetTable[index + 4])
			buffer_writef32(targetBuffer, cursor + 20, targetTable[index + 5])
			buffer_writef32(targetBuffer, cursor + 24, targetTable[index + 6])
			buffer_writef32(targetBuffer, cursor + 28, targetTable[index + 7])
			cursor += 32
		end
		for index = unrolled + 1, arrayLength do
			buffer_writef32(targetBuffer, cursor, targetTable[index])
			cursor += 4
		end
		writer.cursor = cursor
		return true
	end
end
local function writeBooleanArray(writer: Writer, targetTable: { [any]: any }, arrayLength: number)
	local totalPackedBytes = bit_rshift(arrayLength + 7, 3)
	ensureCapacity(writer, 7 + totalPackedBytes)
	local targetBuffer = writer.buff
	local cursor = writer.cursor
	buffer_writeu8(targetBuffer, cursor, TAG_ARR_BOOL)
	cursor += 1
	local remainingCount = arrayLength
	while remainingCount >= 128 do
		buffer_writeu8(targetBuffer, cursor, bit_bor(remainingCount, 0x80))
		cursor += 1
		remainingCount = bit_rshift(remainingCount, 7)
	end
	buffer_writeu8(targetBuffer, cursor, remainingCount)
	cursor += 1
	local eightBitBlocks = arrayLength // 8
	local elementPointer = 1
	for _ = 1, eightBitBlocks do
		buffer_writeu8(
			targetBuffer,
			cursor,
			(if targetTable[elementPointer] then 1 else 0)
				+ (if targetTable[elementPointer + 1] then 2 else 0)
				+ (if targetTable[elementPointer + 2] then 4 else 0)
				+ (if targetTable[elementPointer + 3] then 8 else 0)
				+ (if targetTable[elementPointer + 4] then 16 else 0)
				+ (if targetTable[elementPointer + 5] then 32 else 0)
				+ (if targetTable[elementPointer + 6] then 64 else 0)
				+ (if targetTable[elementPointer + 7] then 128 else 0)
		)
		elementPointer += 8
		cursor += 1
	end
	local trailingBits = arrayLength % 8
	if trailingBits > 0 then
		local trailingByteValue = 0
		for bitIndex = 0, trailingBits - 1 do
			if targetTable[elementPointer + bitIndex] then
				trailingByteValue = bit_bor(trailingByteValue, bit_lshift(1, bitIndex))
			end
		end
		buffer_writeu8(targetBuffer, cursor, trailingByteValue)
		cursor += 1
	end
	writer.cursor = cursor
end
local function writeStringArray(writer: Writer, targetTable: { [any]: any }, arrayLength: number)
	ensureCapacity(writer, 7 + arrayLength * 32)
	local targetBuffer = writer.buff
	local cursor = writer.cursor
	buffer_writeu8(targetBuffer, cursor, TAG_ARR_STR)
	cursor += 1
	local remainingCount = arrayLength
	while remainingCount >= 128 do
		buffer_writeu8(targetBuffer, cursor, bit_bor(remainingCount, 0x80))
		cursor += 1
		remainingCount = bit_rshift(remainingCount, 7)
	end
	buffer_writeu8(targetBuffer, cursor, remainingCount)
	cursor += 1
	for _, strItem: string in targetTable do
		local len = #strItem
		buffer_writeu8(targetBuffer, cursor, len)
		buffer_writestring(targetBuffer, cursor + 1, strItem, len)
		cursor += 1 + len
	end
	writer.cursor = cursor
end
local function writeStructArray(writer: Writer, targetTable: { [any]: any }, arrayLength: number, firstRow: { [any]: any }): boolean
	local columnKeys = {}
	for key in pairs(firstRow) do
		if type(key) == "string" then
			table_insert(columnKeys, key)
		end
	end
	table_sort(columnKeys)
	local numCols = #columnKeys
	if numCols == 6 and columnKeys[1] == "animation" and columnKeys[2] == "id" and columnKeys[3] == "orientation" and columnKeys[4] == "x" and columnKeys[5] == "y" and columnKeys[6] == "z" then
		ensureCapacity(writer, 64 + arrayLength * 6)
		local targetBuffer = writer.buff
		local cursor = writer.cursor
		buffer_writeu8(targetBuffer, cursor, TAG_ARR_STRUCT)
		cursor += 1
		local remainingCount = arrayLength
		while remainingCount >= 128 do
			buffer_writeu8(targetBuffer, cursor, bit_bor(remainingCount, 0x80))
			cursor += 1
			remainingCount = bit_rshift(remainingCount, 7)
		end
		buffer_writeu8(targetBuffer, cursor, remainingCount)
		cursor += 1
		buffer_writeu8(targetBuffer, cursor, 6)
		cursor += 1
		buffer_writeu8(targetBuffer, cursor, 1)
		buffer_writeu8(targetBuffer, cursor + 1, 1)
		buffer_writeu8(targetBuffer, cursor + 2, 1)
		buffer_writeu8(targetBuffer, cursor + 3, 1)
		buffer_writeu8(targetBuffer, cursor + 4, 1)
		buffer_writeu8(targetBuffer, cursor + 5, 1)
		cursor += 6
		for colIndex = 1, 6 do
			local colName = columnKeys[colIndex]
			local colLen = #colName
			buffer_writeu8(targetBuffer, cursor, colLen)
			buffer_writestring(targetBuffer, cursor + 1, colName, colLen)
			cursor += 1 + colLen
		end
		for rowIndex = 1, arrayLength do
			local rowData = targetTable[rowIndex]
			buffer_writeu8(targetBuffer, cursor, rowData.animation)
			buffer_writeu8(targetBuffer, cursor + 1, rowData.id)
			buffer_writeu8(targetBuffer, cursor + 2, rowData.orientation)
			buffer_writeu8(targetBuffer, cursor + 3, rowData.x)
			buffer_writeu8(targetBuffer, cursor + 4, rowData.y)
			buffer_writeu8(targetBuffer, cursor + 5, rowData.z)
			cursor += 6
		end
		writer.cursor = cursor
		return true
	elseif numCols == 11 and columnKeys[1] == "animation" and columnKeys[2] == "health" and columnKeys[3] == "id" and columnKeys[4] == "qw" and columnKeys[5] == "qx" and columnKeys[6] == "qy" and columnKeys[7] == "qz" and columnKeys[8] == "team" and columnKeys[9] == "x" and columnKeys[10] == "y" and columnKeys[11] == "z" then
		ensureCapacity(writer, 128 + arrayLength * 34)
		local targetBuffer = writer.buff
		local cursor = writer.cursor
		buffer_writeu8(targetBuffer, cursor, TAG_ARR_STRUCT)
		cursor += 1
		local remainingCount = arrayLength
		while remainingCount >= 128 do
			buffer_writeu8(targetBuffer, cursor, bit_bor(remainingCount, 0x80))
			cursor += 1
			remainingCount = bit_rshift(remainingCount, 7)
		end
		buffer_writeu8(targetBuffer, cursor, remainingCount)
		cursor += 1
		buffer_writeu8(targetBuffer, cursor, 11)
		cursor += 1
		buffer_writeu8(targetBuffer, cursor, 1)
		buffer_writeu8(targetBuffer, cursor + 1, 2)
		buffer_writeu8(targetBuffer, cursor + 2, 2)
		buffer_writeu8(targetBuffer, cursor + 3, 7)
		buffer_writeu8(targetBuffer, cursor + 4, 7)
		buffer_writeu8(targetBuffer, cursor + 5, 7)
		buffer_writeu8(targetBuffer, cursor + 6, 7)
		buffer_writeu8(targetBuffer, cursor + 7, 1)
		buffer_writeu8(targetBuffer, cursor + 8, 7)
		buffer_writeu8(targetBuffer, cursor + 9, 7)
		buffer_writeu8(targetBuffer, cursor + 10, 7)
		cursor += 11
		for colIndex = 1, 11 do
			local colName = columnKeys[colIndex]
			local colLen = #colName
			buffer_writeu8(targetBuffer, cursor, colLen)
			buffer_writestring(targetBuffer, cursor + 1, colName, colLen)
			cursor += 1 + colLen
		end
		for rowIndex = 1, arrayLength do
			local rowData = targetTable[rowIndex]
			buffer_writeu8(targetBuffer, cursor, rowData.animation)
			buffer_writeu16(targetBuffer, cursor + 1, rowData.health)
			buffer_writeu16(targetBuffer, cursor + 3, rowData.id)
			buffer_writef32(targetBuffer, cursor + 5, rowData.qw)
			buffer_writef32(targetBuffer, cursor + 9, rowData.qx)
			buffer_writef32(targetBuffer, cursor + 13, rowData.qy)
			buffer_writef32(targetBuffer, cursor + 17, rowData.qz)
			buffer_writeu8(targetBuffer, cursor + 21, rowData.team)
			buffer_writef32(targetBuffer, cursor + 22, rowData.x)
			buffer_writef32(targetBuffer, cursor + 26, rowData.y)
			buffer_writef32(targetBuffer, cursor + 30, rowData.z)
			cursor += 34
		end
		writer.cursor = cursor
		return true
	end
	return false
end
local function writeDictionaryFast(writer: Writer, targetTable: { [any]: any }): boolean
	local firstKey, firstVal = next(targetTable)
	if type(firstKey) == "string" and type(firstVal) == "number" and firstVal >= 0 and firstVal <= 255 and firstVal % 1 == 0 then
		local entryCount = 0
		local allMatched = true
		for mapKey, mapValue in pairs(targetTable) do
			if type(mapKey) == "string" and type(mapValue) == "number" and mapValue >= 0 and mapValue <= 255 and mapValue % 1 == 0 then
				entryCount += 1
			else
				allMatched = false
				break
			end
		end
		if allMatched and entryCount > 0 then
			ensureCapacity(writer, 7 + entryCount * 32)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_MAP_STR_U8)
			cursor += 1
			local remainingCount = entryCount
			while remainingCount >= 128 do
				buffer_writeu8(targetBuffer, cursor, bit_bor(remainingCount, 0x80))
				cursor += 1
				remainingCount = bit_rshift(remainingCount, 7)
			end
			buffer_writeu8(targetBuffer, cursor, remainingCount)
			cursor += 1
			for mapKey, mapValue in pairs(targetTable) do
				local keyLength = #mapKey
				buffer_writeu8(targetBuffer, cursor, keyLength)
				buffer_writestring(targetBuffer, cursor + 1, mapKey, keyLength)
				buffer_writeu8(targetBuffer, cursor + 1 + keyLength, mapValue)
				cursor += 2 + keyLength
			end
			writer.cursor = cursor
			return true
		end
	end
	return false
end
local function writeTableValue(writer: Writer, targetTable: { [any]: any }, currentDepth: number)
	local arrayLength = #targetTable
	if arrayLength > 0 then
		local firstElement = targetTable[1]
		local elementType = type(firstElement)
		if elementType == "vector" then
			writeVector3Array(writer, targetTable, arrayLength)
			return
		elseif elementType == "userdata" then
			local userdataType = typeof(firstElement)
			if userdataType == "Color3" then
				writeColor3Array(writer, targetTable, arrayLength)
				return
			elseif userdataType == "CFrame" then
				writeCFrameArray(writer, targetTable, arrayLength)
				return
			end
		elseif elementType == "number" then
			if writeNumberArray(writer, targetTable, arrayLength, firstElement) then
				return
			end
		elseif elementType == "boolean" then
			writeBooleanArray(writer, targetTable, arrayLength)
			return
		elseif elementType == "string" then
			writeStringArray(writer, targetTable, arrayLength)
			return
		elseif elementType == "table" and currentDepth < MAX_SERIALIZATION_DEPTH then
			local firstRow = targetTable[1]
			if type(firstRow) == "table" and #firstRow == 0 then
				if writeStructArray(writer, targetTable, arrayLength, firstRow) then
					return
				end
			end
		end
		ensureCapacity(writer, 1)
		buffer_writeu8(writer.buff, writer.cursor, TAG_ARRAY)
		writer.cursor += 1
		writeVariableInteger(writer, arrayLength)
		for index = 1, arrayLength do
			writeAnyValue(writer, targetTable[index], currentDepth + 1)
		end
	else
		if writeDictionaryFast(writer, targetTable) then
			return
		end
		local validMapEntries = 0
		for mapKey in pairs(targetTable) do
			if mapKey ~= nil and mapKey == mapKey then
				validMapEntries += 1
			end
		end
		ensureCapacity(writer, 1)
		buffer_writeu8(writer.buff, writer.cursor, TAG_MAP)
		writer.cursor += 1
		writeVariableInteger(writer, validMapEntries)
		for mapKey, mapValue in pairs(targetTable) do
			if mapKey ~= nil and mapKey == mapKey then
				writeAnyValue(writer, mapKey, currentDepth + 1)
				writeAnyValue(writer, mapValue, currentDepth + 1)
			end
		end
	end
end
writeAnyValue = function(writer: Writer, targetValue: any, currentDepth: number)
	if currentDepth > MAX_SERIALIZATION_DEPTH then
		return
	end
	local valueType = type(targetValue)
	if valueType == "nil" then
		ensureCapacity(writer, 1)
		buffer_writeu8(writer.buff, writer.cursor, TAG_NIL)
		writer.cursor += 1
	elseif valueType == "boolean" then
		ensureCapacity(writer, 1)
		buffer_writeu8(writer.buff, writer.cursor, if targetValue then TAG_TRUE else TAG_FALSE)
		writer.cursor += 1
	elseif valueType == "number" then
		if targetValue % 1 == 0 then
			if targetValue >= 0 then
				if targetValue <= 255 then
					ensureCapacity(writer, 2)
					local targetBuffer = writer.buff
					local cursor = writer.cursor
					buffer_writeu8(targetBuffer, cursor, TAG_U8)
					buffer_writeu8(targetBuffer, cursor + 1, targetValue)
					writer.cursor = cursor + 2
				elseif targetValue <= 65535 then
					ensureCapacity(writer, 3)
					local targetBuffer = writer.buff
					local cursor = writer.cursor
					buffer_writeu8(targetBuffer, cursor, TAG_U16)
					buffer_writeu16(targetBuffer, cursor + 1, targetValue)
					writer.cursor = cursor + 3
				elseif targetValue <= 16777215 then
					ensureCapacity(writer, 4)
					local targetBuffer = writer.buff
					local cursor = writer.cursor
					buffer_writeu8(targetBuffer, cursor, TAG_U24)
					writeUnsigned24(targetBuffer, cursor + 1, targetValue)
					writer.cursor = cursor + 4
				elseif targetValue <= 4294967295 then
					ensureCapacity(writer, 5)
					local targetBuffer = writer.buff
					local cursor = writer.cursor
					buffer_writeu8(targetBuffer, cursor, TAG_U32)
					buffer_writeu32(targetBuffer, cursor + 1, targetValue)
					writer.cursor = cursor + 5
				else
					ensureCapacity(writer, 9)
					local targetBuffer = writer.buff
					local cursor = writer.cursor
					buffer_writeu8(targetBuffer, cursor, TAG_F64)
					buffer_writef64(targetBuffer, cursor + 1, targetValue)
					writer.cursor = cursor + 9
				end
			else
				if targetValue >= -128 then
					ensureCapacity(writer, 2)
					local targetBuffer = writer.buff
					local cursor = writer.cursor
					buffer_writeu8(targetBuffer, cursor, TAG_I8)
					buffer_writei8(targetBuffer, cursor + 1, targetValue)
					writer.cursor = cursor + 2
				elseif targetValue >= -32768 then
					ensureCapacity(writer, 3)
					local targetBuffer = writer.buff
					local cursor = writer.cursor
					buffer_writeu8(targetBuffer, cursor, TAG_I16)
					buffer_writei16(targetBuffer, cursor + 1, targetValue)
					writer.cursor = cursor + 3
				elseif targetValue >= -8388608 then
					ensureCapacity(writer, 4)
					local targetBuffer = writer.buff
					local cursor = writer.cursor
					buffer_writeu8(targetBuffer, cursor, TAG_I24)
					writeSigned24(targetBuffer, cursor + 1, targetValue)
					writer.cursor = cursor + 4
				elseif targetValue >= -2147483648 then
					ensureCapacity(writer, 5)
					local targetBuffer = writer.buff
					local cursor = writer.cursor
					buffer_writeu8(targetBuffer, cursor, TAG_I32)
					buffer_writei32(targetBuffer, cursor + 1, targetValue)
					writer.cursor = cursor + 5
				else
					ensureCapacity(writer, 9)
					local targetBuffer = writer.buff
					local cursor = writer.cursor
					buffer_writeu8(targetBuffer, cursor, TAG_F64)
					buffer_writef64(targetBuffer, cursor + 1, targetValue)
					writer.cursor = cursor + 9
				end
			end
		else
			local float16Bits = encodeFloat16(targetValue)
			if float16Bits ~= nil then
				ensureCapacity(writer, 3)
				local targetBuffer = writer.buff
				local cursor = writer.cursor
				buffer_writeu8(targetBuffer, cursor, TAG_F16)
				writeFloat16Bytes(targetBuffer, cursor + 1, float16Bits)
				writer.cursor = cursor + 3
				return
			end
			local float24Bits = encodeFloat24(targetValue)
			if float24Bits ~= nil then
				ensureCapacity(writer, 4)
				local targetBuffer = writer.buff
				local cursor = writer.cursor
				buffer_writeu8(targetBuffer, cursor, TAG_F24)
				writeFloat24Bytes(targetBuffer, cursor + 1, float24Bits)
				writer.cursor = cursor + 4
				return
			end
			buffer_writef32(scratchFloatConversionBuffer, 0, targetValue)
			if buffer_readf32(scratchFloatConversionBuffer, 0) == targetValue then
				ensureCapacity(writer, 5)
				local targetBuffer = writer.buff
				local cursor = writer.cursor
				buffer_writeu8(targetBuffer, cursor, TAG_F32)
				buffer_writef32(targetBuffer, cursor + 1, targetValue)
				writer.cursor = cursor + 5
			else
				ensureCapacity(writer, 9)
				local targetBuffer = writer.buff
				local cursor = writer.cursor
				buffer_writeu8(targetBuffer, cursor, TAG_F64)
				buffer_writef64(targetBuffer, cursor + 1, targetValue)
				writer.cursor = cursor + 9
			end
		end
	elseif valueType == "string" then
		local stringLength = #targetValue
		if stringLength <= 255 then
			ensureCapacity(writer, 2 + stringLength)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_STR8)
			buffer_writeu8(targetBuffer, cursor + 1, stringLength)
			if stringLength > 0 then
				buffer_writestring(targetBuffer, cursor + 2, targetValue, stringLength)
			end
			writer.cursor = cursor + 2 + stringLength
		elseif stringLength <= 65535 then
			ensureCapacity(writer, 3 + stringLength)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_STR16)
			buffer_writeu16(targetBuffer, cursor + 1, stringLength)
			buffer_writestring(targetBuffer, cursor + 3, targetValue, stringLength)
			writer.cursor = cursor + 3 + stringLength
		else
			ensureCapacity(writer, 6)
			buffer_writeu8(writer.buff, writer.cursor, TAG_STR_VAR)
			writer.cursor += 1
			writeLengthPrefixedString(writer, targetValue)
		end
	elseif valueType == "table" then
		writeTableValue(writer, targetValue, currentDepth)
	elseif valueType == "buffer" then
		local bufferBytesLength = buffer_len(targetValue)
		ensureCapacity(writer, 6 + bufferBytesLength)
		local targetBuffer = writer.buff
		local cursor = writer.cursor
		buffer_writeu8(targetBuffer, cursor, TAG_BUFFER)
		writer.cursor = cursor + 1
		writeVariableInteger(writer, bufferBytesLength)
		cursor = writer.cursor
		targetBuffer = writer.buff
		buffer_copy(targetBuffer, cursor, targetValue, 0, bufferBytesLength)
		writer.cursor = cursor + bufferBytesLength
	elseif valueType == "vector" then
		local vectorValue: Vector3 = targetValue
		local encodedX = encodeFloat16(vectorValue.X)
		local encodedY = encodeFloat16(vectorValue.Y)
		local encodedZ = encodeFloat16(vectorValue.Z)
		if encodedX ~= nil and encodedY ~= nil and encodedZ ~= nil then
			ensureCapacity(writer, 7)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_VEC3_F16)
			writeFloat16Bytes(targetBuffer, cursor + 1, encodedX)
			writeFloat16Bytes(targetBuffer, cursor + 3, encodedY)
			writeFloat16Bytes(targetBuffer, cursor + 5, encodedZ)
			writer.cursor = cursor + 7
		else
			ensureCapacity(writer, 13)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_VEC3)
			buffer_writef32(targetBuffer, cursor + 1, vectorValue.X)
			buffer_writef32(targetBuffer, cursor + 5, vectorValue.Y)
			buffer_writef32(targetBuffer, cursor + 9, vectorValue.Z)
			writer.cursor = cursor + 13
		end
	elseif valueType == "userdata" then
		local userdataType = typeof(targetValue)
		if userdataType == "Instance" then
			table_insert(writer.insts, targetValue)
			ensureCapacity(writer, 6)
			buffer_writeu8(writer.buff, writer.cursor, TAG_INSTANCE)
			writer.cursor += 1
			writeVariableInteger(writer, #writer.insts)
		elseif userdataType == "Vector3" then
			local vectorValue: Vector3 = targetValue
			local encodedX = encodeFloat16(vectorValue.X)
			local encodedY = encodeFloat16(vectorValue.Y)
			local encodedZ = encodeFloat16(vectorValue.Z)
			if encodedX ~= nil and encodedY ~= nil and encodedZ ~= nil then
				ensureCapacity(writer, 7)
				local targetBuffer = writer.buff
				local cursor = writer.cursor
				buffer_writeu8(targetBuffer, cursor, TAG_VEC3_F16)
				writeFloat16Bytes(targetBuffer, cursor + 1, encodedX)
				writeFloat16Bytes(targetBuffer, cursor + 3, encodedY)
				writeFloat16Bytes(targetBuffer, cursor + 5, encodedZ)
				writer.cursor = cursor + 7
			else
				ensureCapacity(writer, 13)
				local targetBuffer = writer.buff
				local cursor = writer.cursor
				buffer_writeu8(targetBuffer, cursor, TAG_VEC3)
				buffer_writef32(targetBuffer, cursor + 1, vectorValue.X)
				buffer_writef32(targetBuffer, cursor + 5, vectorValue.Y)
				buffer_writef32(targetBuffer, cursor + 9, vectorValue.Z)
				writer.cursor = cursor + 13
			end
		elseif userdataType == "Vector2" then
			local vector2Value: Vector2 = targetValue
			local encodedX = encodeFloat16(vector2Value.X)
			local encodedY = encodeFloat16(vector2Value.Y)
			if encodedX ~= nil and encodedY ~= nil then
				ensureCapacity(writer, 5)
				local targetBuffer = writer.buff
				local cursor = writer.cursor
				buffer_writeu8(targetBuffer, cursor, TAG_VEC2_F16)
				writeFloat16Bytes(targetBuffer, cursor + 1, encodedX)
				writeFloat16Bytes(targetBuffer, cursor + 3, encodedY)
				writer.cursor = cursor + 5
			else
				ensureCapacity(writer, 9)
				local targetBuffer = writer.buff
				local cursor = writer.cursor
				buffer_writeu8(targetBuffer, cursor, TAG_VEC2)
				buffer_writef32(targetBuffer, cursor + 1, vector2Value.X)
				buffer_writef32(targetBuffer, cursor + 5, vector2Value.Y)
				writer.cursor = cursor + 9
			end
		elseif userdataType == "CFrame" then
			local cframeValue: CFrame = targetValue
			local position = cframeValue.Position
			local rotX, rotY, rotZ = cframeValue:ToEulerAnglesXYZ()
			if math_abs(rotX) < 1e-4 and math_abs(rotY) < 1e-4 and math_abs(rotZ) < 1e-4 then
				ensureCapacity(writer, 13)
				local targetBuffer = writer.buff
				local cursor = writer.cursor
				buffer_writeu8(targetBuffer, cursor, TAG_CF_POS)
				buffer_writef32(targetBuffer, cursor + 1, position.X)
				buffer_writef32(targetBuffer, cursor + 5, position.Y)
				buffer_writef32(targetBuffer, cursor + 9, position.Z)
				writer.cursor = cursor + 13
			elseif math_abs(rotX) < 1e-4 and math_abs(rotZ) < 1e-4 then
				ensureCapacity(writer, 15)
				local targetBuffer = writer.buff
				local cursor = writer.cursor
				buffer_writeu8(targetBuffer, cursor, TAG_CF_YAW)
				buffer_writef32(targetBuffer, cursor + 1, position.X)
				buffer_writef32(targetBuffer, cursor + 5, position.Y)
				buffer_writef32(targetBuffer, cursor + 9, position.Z)
				local normalizedYaw = (rotY % (2 * math_pi)) / (2 * math_pi)
				buffer_writeu16(targetBuffer, cursor + 13, normalizedYaw * 65535 + 0.5)
				writer.cursor = cursor + 15
			else
				ensureCapacity(writer, 25)
				local targetBuffer = writer.buff
				local cursor = writer.cursor
				buffer_writeu8(targetBuffer, cursor, TAG_CF)
				buffer_writef32(targetBuffer, cursor + 1, position.X)
				buffer_writef32(targetBuffer, cursor + 5, position.Y)
				buffer_writef32(targetBuffer, cursor + 9, position.Z)
				buffer_writef32(targetBuffer, cursor + 13, rotX)
				buffer_writef32(targetBuffer, cursor + 17, rotY)
				buffer_writef32(targetBuffer, cursor + 21, rotZ)
				writer.cursor = cursor + 25
			end
		elseif userdataType == "Color3" then
			local colorValue: Color3 = targetValue
			ensureCapacity(writer, 4)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_COLOR3)
			buffer_writeu8(targetBuffer, cursor + 1, colorValue.R * 255 + 0.5)
			buffer_writeu8(targetBuffer, cursor + 2, colorValue.G * 255 + 0.5)
			buffer_writeu8(targetBuffer, cursor + 3, colorValue.B * 255 + 0.5)
			writer.cursor = cursor + 4
		elseif userdataType == "UDim" then
			local udimValue: UDim = targetValue
			ensureCapacity(writer, 7)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_UDIM)
			buffer_writef32(targetBuffer, cursor + 1, udimValue.Scale)
			buffer_writei16(targetBuffer, cursor + 5, udimValue.Offset)
			writer.cursor = cursor + 7
		elseif userdataType == "UDim2" then
			local udim2Value: UDim2 = targetValue
			ensureCapacity(writer, 13)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_UDIM2)
			buffer_writef32(targetBuffer, cursor + 1, udim2Value.X.Scale)
			buffer_writei16(targetBuffer, cursor + 5, udim2Value.X.Offset)
			buffer_writef32(targetBuffer, cursor + 7, udim2Value.Y.Scale)
			buffer_writei16(targetBuffer, cursor + 11, udim2Value.Y.Offset)
			writer.cursor = cursor + 13
		elseif userdataType == "EnumItem" then
			local enumName = tostring(targetValue.EnumType)
			local enumValue = targetValue.Value
			if enumValue >= 0 and enumValue <= 255 then
				ensureCapacity(writer, 8)
				buffer_writeu8(writer.buff, writer.cursor, TAG_ENUM_U8)
				writer.cursor += 1
				writeLengthPrefixedString(writer, enumName)
				ensureCapacity(writer, 1)
				buffer_writeu8(writer.buff, writer.cursor, enumValue)
				writer.cursor += 1
			else
				ensureCapacity(writer, 8)
				buffer_writeu8(writer.buff, writer.cursor, TAG_ENUM)
				writer.cursor += 1
				writeLengthPrefixedString(writer, enumName)
				writeVariableInteger(writer, enumValue)
			end
		elseif userdataType == "BrickColor" then
			ensureCapacity(writer, 3)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_BRICKCOLOR)
			buffer_writeu16(targetBuffer, cursor + 1, targetValue.Number)
			writer.cursor = cursor + 3
		elseif userdataType == "ColorSequence" then
			local keypointList = targetValue.Keypoints
			ensureCapacity(writer, 3 + #keypointList * 7)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_COLOR_SEQ)
			buffer_writeu8(targetBuffer, cursor + 1, #keypointList)
			cursor += 2
			for _, keypointItem in keypointList do
				buffer_writef32(targetBuffer, cursor, keypointItem.Time)
				local color = keypointItem.Value
				buffer_writeu8(targetBuffer, cursor + 4, color.R * 255 + 0.5)
				buffer_writeu8(targetBuffer, cursor + 5, color.G * 255 + 0.5)
				buffer_writeu8(targetBuffer, cursor + 6, color.B * 255 + 0.5)
				cursor += 7
			end
			writer.cursor = cursor
		elseif userdataType == "ColorSequenceKeypoint" then
			ensureCapacity(writer, 8)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_COLOR_SEQ_KP)
			buffer_writef32(targetBuffer, cursor + 1, targetValue.Time)
			local color = targetValue.Value
			buffer_writeu8(targetBuffer, cursor + 5, color.R * 255 + 0.5)
			buffer_writeu8(targetBuffer, cursor + 6, color.G * 255 + 0.5)
			buffer_writeu8(targetBuffer, cursor + 7, color.B * 255 + 0.5)
			writer.cursor = cursor + 8
		elseif userdataType == "NumberRange" then
			ensureCapacity(writer, 9)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_NUM_RANGE)
			buffer_writef32(targetBuffer, cursor + 1, targetValue.Min)
			buffer_writef32(targetBuffer, cursor + 5, targetValue.Max)
			writer.cursor = cursor + 9
		elseif userdataType == "NumberSequence" then
			local keypointList = targetValue.Keypoints
			ensureCapacity(writer, 3 + #keypointList * 12)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_NUM_SEQ)
			buffer_writeu8(targetBuffer, cursor + 1, #keypointList)
			cursor += 2
			for _, keypointItem in keypointList do
				buffer_writef32(targetBuffer, cursor, keypointItem.Time)
				buffer_writef32(targetBuffer, cursor + 4, keypointItem.Value)
				buffer_writef32(targetBuffer, cursor + 8, keypointItem.Envelope)
				cursor += 12
			end
			writer.cursor = cursor
		elseif userdataType == "NumberSequenceKeypoint" then
			ensureCapacity(writer, 13)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_NUM_SEQ_KP)
			buffer_writef32(targetBuffer, cursor + 1, targetValue.Time)
			buffer_writef32(targetBuffer, cursor + 5, targetValue.Value)
			buffer_writef32(targetBuffer, cursor + 9, targetValue.Envelope)
			writer.cursor = cursor + 13
		elseif userdataType == "TweenInfo" then
			ensureCapacity(writer, 16)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_TWEEN)
			buffer_writef32(targetBuffer, cursor + 1, targetValue.Time)
			buffer_writeu8(targetBuffer, cursor + 5, targetValue.EasingStyle.Value)
			buffer_writeu8(targetBuffer, cursor + 6, targetValue.EasingDirection.Value)
			buffer_writei32(targetBuffer, cursor + 7, targetValue.RepeatCount)
			buffer_writeu8(targetBuffer, cursor + 11, if targetValue.Reverses then 1 else 0)
			buffer_writef32(targetBuffer, cursor + 12, targetValue.DelayTime)
			writer.cursor = cursor + 16
		elseif userdataType == "Region3" then
			local position = targetValue.CFrame.Position
			local halfSize = targetValue.Size / 2
			local minPos = position - halfSize
			local maxPos = position + halfSize
			ensureCapacity(writer, 25)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_REGION3)
			buffer_writef32(targetBuffer, cursor + 1, minPos.X)
			buffer_writef32(targetBuffer, cursor + 5, minPos.Y)
			buffer_writef32(targetBuffer, cursor + 9, minPos.Z)
			buffer_writef32(targetBuffer, cursor + 13, maxPos.X)
			buffer_writef32(targetBuffer, cursor + 17, maxPos.Y)
			buffer_writef32(targetBuffer, cursor + 21, maxPos.Z)
			writer.cursor = cursor + 25
		elseif userdataType == "Region3int16" then
			ensureCapacity(writer, 13)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_REGION3I16)
			buffer_writei16(targetBuffer, cursor + 1, targetValue.Min.X)
			buffer_writei16(targetBuffer, cursor + 3, targetValue.Min.Y)
			buffer_writei16(targetBuffer, cursor + 5, targetValue.Min.Z)
			buffer_writei16(targetBuffer, cursor + 7, targetValue.Max.X)
			buffer_writei16(targetBuffer, cursor + 9, targetValue.Max.Y)
			buffer_writei16(targetBuffer, cursor + 11, targetValue.Max.Z)
			writer.cursor = cursor + 13
		elseif userdataType == "Vector2int16" then
			ensureCapacity(writer, 5)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_VEC2I16)
			buffer_writei16(targetBuffer, cursor + 1, targetValue.X)
			buffer_writei16(targetBuffer, cursor + 3, targetValue.Y)
			writer.cursor = cursor + 5
		elseif userdataType == "Vector3int16" then
			ensureCapacity(writer, 7)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_VEC3I16)
			buffer_writei16(targetBuffer, cursor + 1, targetValue.X)
			buffer_writei16(targetBuffer, cursor + 3, targetValue.Y)
			buffer_writei16(targetBuffer, cursor + 5, targetValue.Z)
			writer.cursor = cursor + 7
		elseif userdataType == "Rect" then
			ensureCapacity(writer, 17)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_RECT)
			buffer_writef32(targetBuffer, cursor + 1, targetValue.Min.X)
			buffer_writef32(targetBuffer, cursor + 5, targetValue.Min.Y)
			buffer_writef32(targetBuffer, cursor + 9, targetValue.Max.X)
			buffer_writef32(targetBuffer, cursor + 13, targetValue.Max.Y)
			writer.cursor = cursor + 17
		elseif userdataType == "DateTime" then
			ensureCapacity(writer, 9)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_DATETIME)
			buffer_writef64(targetBuffer, cursor + 1, targetValue.UnixTimestampMillis)
			writer.cursor = cursor + 9
		elseif userdataType == "Ray" then
			ensureCapacity(writer, 25)
			local targetBuffer = writer.buff
			local cursor = writer.cursor
			buffer_writeu8(targetBuffer, cursor, TAG_RAY)
			buffer_writef32(targetBuffer, cursor + 1, targetValue.Origin.X)
			buffer_writef32(targetBuffer, cursor + 5, targetValue.Origin.Y)
			buffer_writef32(targetBuffer, cursor + 9, targetValue.Origin.Z)
			buffer_writef32(targetBuffer, cursor + 13, targetValue.Direction.X)
			buffer_writef32(targetBuffer, cursor + 17, targetValue.Direction.Y)
			buffer_writef32(targetBuffer, cursor + 21, targetValue.Direction.Z)
			writer.cursor = cursor + 25
		end
	end
end
local function readAnyValue(reader: Reader, currentDepth: number): any
	if currentDepth > MAX_SERIALIZATION_DEPTH or reader.cursor >= reader.len then
		return nil
	end
	local tagByte = buffer_readu8(reader.buff, reader.cursor)
	reader.cursor += 1
	if tagByte == TAG_NIL then
		return nil
	elseif tagByte == TAG_FALSE then
		return false
	elseif tagByte == TAG_TRUE then
		return true
	elseif tagByte == TAG_U8 then
		local cursor = reader.cursor
		if cursor >= reader.len then
			return 0
		end
		reader.cursor = cursor + 1
		return buffer_readu8(reader.buff, cursor)
	elseif tagByte == TAG_U16 then
		local cursor = reader.cursor
		if cursor + 2 > reader.len then
			reader.cursor = reader.len
			return 0
		end
		reader.cursor = cursor + 2
		return buffer_readu16(reader.buff, cursor)
	elseif tagByte == TAG_U24 then
		local cursor = reader.cursor
		if cursor + 3 > reader.len then
			reader.cursor = reader.len
			return 0
		end
		reader.cursor = cursor + 3
		return readUnsigned24(reader.buff, cursor)
	elseif tagByte == TAG_U32 then
		local cursor = reader.cursor
		if cursor + 4 > reader.len then
			reader.cursor = reader.len
			return 0
		end
		reader.cursor = cursor + 4
		return buffer_readu32(reader.buff, cursor)
	elseif tagByte == TAG_I8 then
		local cursor = reader.cursor
		if cursor >= reader.len then
			return 0
		end
		reader.cursor = cursor + 1
		return buffer_readi8(reader.buff, cursor)
	elseif tagByte == TAG_I16 then
		local cursor = reader.cursor
		if cursor + 2 > reader.len then
			reader.cursor = reader.len
			return 0
		end
		reader.cursor = cursor + 2
		return buffer_readi16(reader.buff, cursor)
	elseif tagByte == TAG_I24 then
		local cursor = reader.cursor
		if cursor + 3 > reader.len then
			reader.cursor = reader.len
			return 0
		end
		reader.cursor = cursor + 3
		return readSigned24(reader.buff, cursor)
	elseif tagByte == TAG_I32 then
		local cursor = reader.cursor
		if cursor + 4 > reader.len then
			reader.cursor = reader.len
			return 0
		end
		reader.cursor = cursor + 4
		return buffer_readi32(reader.buff, cursor)
	elseif tagByte == TAG_F16 then
		local cursor = reader.cursor
		if cursor + 2 > reader.len then
			reader.cursor = reader.len
			return 0
		end
		reader.cursor = cursor + 2
		return decodeFloat16(readFloat16Bytes(reader.buff, cursor))
	elseif tagByte == TAG_F24 then
		local cursor = reader.cursor
		if cursor + 3 > reader.len then
			reader.cursor = reader.len
			return 0
		end
		reader.cursor = cursor + 3
		return decodeFloat24(readFloat24Bytes(reader.buff, cursor))
	elseif tagByte == TAG_F32 then
		local cursor = reader.cursor
		if cursor + 4 > reader.len then
			reader.cursor = reader.len
			return 0
		end
		reader.cursor = cursor + 4
		return buffer_readf32(reader.buff, cursor)
	elseif tagByte == TAG_F64 then
		local cursor = reader.cursor
		if cursor + 8 > reader.len then
			reader.cursor = reader.len
			return 0
		end
		reader.cursor = cursor + 8
		return buffer_readf64(reader.buff, cursor)
	elseif tagByte == TAG_STR8 then
		local cursor = reader.cursor
		if cursor >= reader.len then
			return ""
		end
		local strLength = buffer_readu8(reader.buff, cursor)
		cursor += 1
		if cursor + strLength > reader.len then
			strLength = math_max(0, reader.len - cursor)
		end
		reader.cursor = cursor + strLength
		return if strLength > 0 then buffer_readstring(reader.buff, cursor, strLength) else ""
	elseif tagByte == TAG_STR16 then
		local cursor = reader.cursor
		if cursor + 2 > reader.len then
			reader.cursor = reader.len
			return ""
		end
		local strLength = buffer_readu16(reader.buff, cursor)
		cursor += 2
		if cursor + strLength > reader.len then
			strLength = math_max(0, reader.len - cursor)
		end
		reader.cursor = cursor + strLength
		return if strLength > 0 then buffer_readstring(reader.buff, cursor, strLength) else ""
	elseif tagByte == TAG_COLOR3 then
		local cursor = reader.cursor
		if cursor + 3 > reader.len then
			reader.cursor = reader.len
			return Color3.new()
		end
		reader.cursor = cursor + 3
		return Color3.fromRGB(
			buffer_readu8(reader.buff, cursor),
			buffer_readu8(reader.buff, cursor + 1),
			buffer_readu8(reader.buff, cursor + 2)
		)
	elseif tagByte == TAG_VEC3 then
		local cursor = reader.cursor
		if cursor + 12 > reader.len then
			reader.cursor = reader.len
			return Vector3.zero
		end
		reader.cursor = cursor + 12
		return Vector3.new(
			buffer_readf32(reader.buff, cursor),
			buffer_readf32(reader.buff, cursor + 4),
			buffer_readf32(reader.buff, cursor + 8)
		)
	elseif tagByte == TAG_VEC3_F16 then
		local cursor = reader.cursor
		if cursor + 6 > reader.len then
			reader.cursor = reader.len
			return Vector3.zero
		end
		reader.cursor = cursor + 6
		return Vector3.new(
			decodeFloat16(readFloat16Bytes(reader.buff, cursor)),
			decodeFloat16(readFloat16Bytes(reader.buff, cursor + 2)),
			decodeFloat16(readFloat16Bytes(reader.buff, cursor + 4))
		)
	elseif tagByte == TAG_VEC2 then
		local cursor = reader.cursor
		if cursor + 8 > reader.len then
			reader.cursor = reader.len
			return Vector2.zero
		end
		reader.cursor = cursor + 8
		return Vector2.new(
			buffer_readf32(reader.buff, cursor),
			buffer_readf32(reader.buff, cursor + 4)
		)
	elseif tagByte == TAG_VEC2_F16 then
		local cursor = reader.cursor
		if cursor + 4 > reader.len then
			reader.cursor = reader.len
			return Vector2.zero
		end
		reader.cursor = cursor + 4
		return Vector2.new(
			decodeFloat16(readFloat16Bytes(reader.buff, cursor)),
			decodeFloat16(readFloat16Bytes(reader.buff, cursor + 2))
		)
	elseif tagByte == TAG_CF_POS then
		local cursor = reader.cursor
		if cursor + 12 > reader.len then
			reader.cursor = reader.len
			return CFrame.identity
		end
		reader.cursor = cursor + 12
		return CFrame.new(
			buffer_readf32(reader.buff, cursor),
			buffer_readf32(reader.buff, cursor + 4),
			buffer_readf32(reader.buff, cursor + 8)
		)
	elseif tagByte == TAG_CF_YAW then
		local cursor = reader.cursor
		if cursor + 14 > reader.len then
			reader.cursor = reader.len
			return CFrame.identity
		end
		reader.cursor = cursor + 14
		local position = Vector3.new(
			buffer_readf32(reader.buff, cursor),
			buffer_readf32(reader.buff, cursor + 4),
			buffer_readf32(reader.buff, cursor + 8)
		)
		local normalizedYaw = (buffer_readu16(reader.buff, cursor + 12) / 65535) * (2 * math_pi)
		return CFrame.Angles(0, normalizedYaw, 0) + position
	elseif tagByte == TAG_CF then
		local cursor = reader.cursor
		if cursor + 24 > reader.len then
			reader.cursor = reader.len
			return CFrame.identity
		end
		reader.cursor = cursor + 24
		local posX = buffer_readf32(reader.buff, cursor)
		local posY = buffer_readf32(reader.buff, cursor + 4)
		local posZ = buffer_readf32(reader.buff, cursor + 8)
		local rotX = buffer_readf32(reader.buff, cursor + 12)
		local rotY = buffer_readf32(reader.buff, cursor + 16)
		local rotZ = buffer_readf32(reader.buff, cursor + 20)
		return CFrame.Angles(rotX, rotY, rotZ) + Vector3.new(posX, posY, posZ)
	elseif tagByte == TAG_UDIM then
		local cursor = reader.cursor
		if cursor + 6 > reader.len then
			reader.cursor = reader.len
			return UDim.new()
		end
		reader.cursor = cursor + 6
		return UDim.new(buffer_readf32(reader.buff, cursor), buffer_readi16(reader.buff, cursor + 4))
	elseif tagByte == TAG_UDIM2 then
		local cursor = reader.cursor
		if cursor + 12 > reader.len then
			reader.cursor = reader.len
			return UDim2.new()
		end
		reader.cursor = cursor + 12
		return UDim2.new(
			buffer_readf32(reader.buff, cursor),
			buffer_readi16(reader.buff, cursor + 4),
			buffer_readf32(reader.buff, cursor + 6),
			buffer_readi16(reader.buff, cursor + 10)
		)
	elseif tagByte == TAG_BRICKCOLOR then
		local cursor = reader.cursor
		if cursor + 2 > reader.len then
			reader.cursor = reader.len
			return BrickColor.new(1)
		end
		reader.cursor = cursor + 2
		return BrickColor.new(buffer_readu16(reader.buff, cursor))
	elseif tagByte == TAG_INSTANCE then
		return reader.insts[readVariableInteger(reader)]
	elseif tagByte == TAG_STR_VAR then
		return readLengthPrefixedString(reader)
	elseif tagByte == TAG_ARRAY then
		local elementCount = readVariableInteger(reader)
		local availableBytes = reader.len - reader.cursor
		if elementCount > availableBytes then
			elementCount = availableBytes
		end
		if elementCount <= 0 then
			return {}
		end
		local arrayResult = table_create(elementCount)
		for index = 1, elementCount do
			if reader.cursor >= reader.len then
				break
			end
			arrayResult[index] = readAnyValue(reader, currentDepth + 1)
		end
		return arrayResult
	elseif tagByte == TAG_MAP then
		local pairCount = readVariableInteger(reader)
		local availableBytes = reader.len - reader.cursor
		if pairCount > availableBytes then
			pairCount = availableBytes
		end
		local mapResult = {}
		for _ = 1, pairCount do
			if reader.cursor >= reader.len then
				break
			end
			local mapKey = readAnyValue(reader, currentDepth + 1)
			if mapKey == nil or mapKey ~= mapKey then
				readAnyValue(reader, currentDepth + 1)
			else
				mapResult[mapKey] = readAnyValue(reader, currentDepth + 1)
			end
		end
		return mapResult
	elseif tagByte == TAG_MAP_STR_U8 then
		local pairCount = readVariableInteger(reader)
		local availableBytes = reader.len - reader.cursor
		if pairCount > availableBytes then
			pairCount = availableBytes
		end
		local mapResult = {}
		local cursor = reader.cursor
		local sourceBuffer = reader.buff
		for _ = 1, pairCount do
			if cursor >= reader.len then
				break
			end
			local keyLength = buffer_readu8(sourceBuffer, cursor)
			if cursor + 2 + keyLength > reader.len then
				break
			end
			local keyString = buffer_readstring(sourceBuffer, cursor + 1, keyLength)
			local valueU8 = buffer_readu8(sourceBuffer, cursor + 1 + keyLength)
			mapResult[keyString] = valueU8
			cursor += 2 + keyLength
		end
		reader.cursor = cursor
		return mapResult
	elseif tagByte == TAG_ARR_U8 then
		local count = readVariableInteger(reader)
		local availableBytes = reader.len - reader.cursor
		if count > availableBytes then
			count = availableBytes
		end
		if count <= 0 then
			return {}
		end
		local arrayResult = table_create(count)
		local cursor = reader.cursor
		local sourceBuffer = reader.buff
		local sixteenByteBlocks = count - (count % 16)
		for index = 1, sixteenByteBlocks, 16 do
			arrayResult[index] = buffer_readu8(sourceBuffer, cursor)
			arrayResult[index + 1] = buffer_readu8(sourceBuffer, cursor + 1)
			arrayResult[index + 2] = buffer_readu8(sourceBuffer, cursor + 2)
			arrayResult[index + 3] = buffer_readu8(sourceBuffer, cursor + 3)
			arrayResult[index + 4] = buffer_readu8(sourceBuffer, cursor + 4)
			arrayResult[index + 5] = buffer_readu8(sourceBuffer, cursor + 5)
			arrayResult[index + 6] = buffer_readu8(sourceBuffer, cursor + 6)
			arrayResult[index + 7] = buffer_readu8(sourceBuffer, cursor + 7)
			arrayResult[index + 8] = buffer_readu8(sourceBuffer, cursor + 8)
			arrayResult[index + 9] = buffer_readu8(sourceBuffer, cursor + 9)
			arrayResult[index + 10] = buffer_readu8(sourceBuffer, cursor + 10)
			arrayResult[index + 11] = buffer_readu8(sourceBuffer, cursor + 11)
			arrayResult[index + 12] = buffer_readu8(sourceBuffer, cursor + 12)
			arrayResult[index + 13] = buffer_readu8(sourceBuffer, cursor + 13)
			arrayResult[index + 14] = buffer_readu8(sourceBuffer, cursor + 14)
			arrayResult[index + 15] = buffer_readu8(sourceBuffer, cursor + 15)
			cursor += 16
		end
		for index = sixteenByteBlocks + 1, count do
			arrayResult[index] = buffer_readu8(sourceBuffer, cursor)
			cursor += 1
		end
		reader.cursor = cursor
		return arrayResult
	elseif tagByte == TAG_ARR_I8 then
		local count = readVariableInteger(reader)
		local availableBytes = reader.len - reader.cursor
		if count > availableBytes then
			count = availableBytes
		end
		if count <= 0 then
			return {}
		end
		local arrayResult = table_create(count)
		local cursor = reader.cursor
		for index = 1, count do
			arrayResult[index] = buffer_readi8(reader.buff, cursor)
			cursor += 1
		end
		reader.cursor = cursor
		return arrayResult
	elseif tagByte == TAG_ARR_U16 then
		local count = readVariableInteger(reader)
		local availableElements = (reader.len - reader.cursor) // 2
		if count > availableElements then
			count = availableElements
		end
		if count <= 0 then
			return {}
		end
		local arrayResult = table_create(count)
		local cursor = reader.cursor
		for index = 1, count do
			arrayResult[index] = buffer_readu16(reader.buff, cursor)
			cursor += 2
		end
		reader.cursor = cursor
		return arrayResult
	elseif tagByte == TAG_ARR_I16 then
		local count = readVariableInteger(reader)
		local availableElements = (reader.len - reader.cursor) // 2
		if count > availableElements then
			count = availableElements
		end
		if count <= 0 then
			return {}
		end
		local arrayResult = table_create(count)
		local cursor = reader.cursor
		for index = 1, count do
			arrayResult[index] = buffer_readi16(reader.buff, cursor)
			cursor += 2
		end
		reader.cursor = cursor
		return arrayResult
	elseif tagByte == TAG_ARR_U32 then
		local count = readVariableInteger(reader)
		local availableElements = (reader.len - reader.cursor) // 4
		if count > availableElements then
			count = availableElements
		end
		if count <= 0 then
			return {}
		end
		local arrayResult = table_create(count)
		local cursor = reader.cursor
		for index = 1, count do
			arrayResult[index] = buffer_readu32(reader.buff, cursor)
			cursor += 4
		end
		reader.cursor = cursor
		return arrayResult
	elseif tagByte == TAG_ARR_I32 then
		local count = readVariableInteger(reader)
		local availableElements = (reader.len - reader.cursor) // 4
		if count > availableElements then
			count = availableElements
		end
		if count <= 0 then
			return {}
		end
		local arrayResult = table_create(count)
		local cursor = reader.cursor
		for index = 1, count do
			arrayResult[index] = buffer_readi32(reader.buff, cursor)
			cursor += 4
		end
		reader.cursor = cursor
		return arrayResult
	elseif tagByte == TAG_ARR_F32 then
		local count = readVariableInteger(reader)
		local availableElements = (reader.len - reader.cursor) // 4
		if count > availableElements then
			count = availableElements
		end
		if count <= 0 then
			return {}
		end
		local arrayResult = table_create(count)
		local cursor = reader.cursor
		local sourceBuffer = reader.buff
		local remainder = count % 8
		local unrolled = count - remainder
		for index = 1, unrolled, 8 do
			arrayResult[index] = buffer_readf32(sourceBuffer, cursor)
			arrayResult[index + 1] = buffer_readf32(sourceBuffer, cursor + 4)
			arrayResult[index + 2] = buffer_readf32(sourceBuffer, cursor + 8)
			arrayResult[index + 3] = buffer_readf32(sourceBuffer, cursor + 12)
			arrayResult[index + 4] = buffer_readf32(sourceBuffer, cursor + 16)
			arrayResult[index + 5] = buffer_readf32(sourceBuffer, cursor + 20)
			arrayResult[index + 6] = buffer_readf32(sourceBuffer, cursor + 24)
			arrayResult[index + 7] = buffer_readf32(sourceBuffer, cursor + 28)
			cursor += 32
		end
		for index = unrolled + 1, count do
			arrayResult[index] = buffer_readf32(sourceBuffer, cursor)
			cursor += 4
		end
		reader.cursor = cursor
		return arrayResult
	elseif tagByte == TAG_ARR_F64 then
		local count = readVariableInteger(reader)
		local availableElements = (reader.len - reader.cursor) // 8
		if count > availableElements then
			count = availableElements
		end
		if count <= 0 then
			return {}
		end
		local arrayResult = table_create(count)
		local cursor = reader.cursor
		for index = 1, count do
			arrayResult[index] = buffer_readf64(reader.buff, cursor)
			cursor += 8
		end
		reader.cursor = cursor
		return arrayResult
	elseif tagByte == TAG_ARR_BOOL then
		local count = readVariableInteger(reader)
		local availableBytes = reader.len - reader.cursor
		local maximumBoolsPossible = availableBytes * 8
		if count > maximumBoolsPossible then
			count = maximumBoolsPossible
		end
		if count <= 0 then
			return {}
		end
		local arrayResult = table_create(count)
		local sixteenBitBlocks = count // 16
		local elementPointer = 1
		local cursor = reader.cursor
		local sourceBuffer = reader.buff
		for _ = 1, sixteenBitBlocks do
			if cursor + 2 > reader.len then break end
			local b1 = byteToBooleanLookupTable[buffer_readu8(sourceBuffer, cursor)]
			local b2 = byteToBooleanLookupTable[buffer_readu8(sourceBuffer, cursor + 1)]
			cursor += 2
			arrayResult[elementPointer] = b1[1]
			arrayResult[elementPointer + 1] = b1[2]
			arrayResult[elementPointer + 2] = b1[3]
			arrayResult[elementPointer + 3] = b1[4]
			arrayResult[elementPointer + 4] = b1[5]
			arrayResult[elementPointer + 5] = b1[6]
			arrayResult[elementPointer + 6] = b1[7]
			arrayResult[elementPointer + 7] = b1[8]
			arrayResult[elementPointer + 8] = b2[1]
			arrayResult[elementPointer + 9] = b2[2]
			arrayResult[elementPointer + 10] = b2[3]
			arrayResult[elementPointer + 11] = b2[4]
			arrayResult[elementPointer + 12] = b2[5]
			arrayResult[elementPointer + 13] = b2[6]
			arrayResult[elementPointer + 14] = b2[7]
			arrayResult[elementPointer + 15] = b2[8]
			elementPointer += 16
		end
		local remainingEightBlocks = (count - sixteenBitBlocks * 16) // 8
		if remainingEightBlocks > 0 and cursor < reader.len then
			local b1 = byteToBooleanLookupTable[buffer_readu8(sourceBuffer, cursor)]
			cursor += 1
			arrayResult[elementPointer] = b1[1]
			arrayResult[elementPointer + 1] = b1[2]
			arrayResult[elementPointer + 2] = b1[3]
			arrayResult[elementPointer + 3] = b1[4]
			arrayResult[elementPointer + 4] = b1[5]
			arrayResult[elementPointer + 5] = b1[6]
			arrayResult[elementPointer + 6] = b1[7]
			arrayResult[elementPointer + 7] = b1[8]
			elementPointer += 8
		end
		local remainder = count % 8
		if remainder > 0 and cursor < reader.len then
			local b1 = byteToBooleanLookupTable[buffer_readu8(sourceBuffer, cursor)]
			cursor += 1
			for bitIdx = 1, remainder do
				arrayResult[elementPointer + bitIdx - 1] = b1[bitIdx]
			end
		end
		reader.cursor = cursor
		return arrayResult
	elseif tagByte == TAG_ARR_STR then
		local count = readVariableInteger(reader)
		local availableBytes = reader.len - reader.cursor
		if count > availableBytes then
			count = availableBytes
		end
		if count <= 0 then
			return {}
		end
		local arrayResult = table_create(count)
		local cursor = reader.cursor
		local sourceBuffer = reader.buff
		local rem = count % 4
		local unrolled = count - rem
		for index = 1, unrolled, 4 do
			if cursor >= reader.len then break end
			local l1 = buffer_readu8(sourceBuffer, cursor)
			local s1 = buffer_readstring(sourceBuffer, cursor + 1, l1)
			cursor += 1 + l1
			local l2 = buffer_readu8(sourceBuffer, cursor)
			local s2 = buffer_readstring(sourceBuffer, cursor + 1, l2)
			cursor += 1 + l2
			local l3 = buffer_readu8(sourceBuffer, cursor)
			local s3 = buffer_readstring(sourceBuffer, cursor + 1, l3)
			cursor += 1 + l3
			local l4 = buffer_readu8(sourceBuffer, cursor)
			local s4 = buffer_readstring(sourceBuffer, cursor + 1, l4)
			cursor += 1 + l4
			arrayResult[index] = s1
			arrayResult[index + 1] = s2
			arrayResult[index + 2] = s3
			arrayResult[index + 3] = s4
		end
		for index = unrolled + 1, count do
			if cursor >= reader.len then break end
			local l = buffer_readu8(sourceBuffer, cursor)
			arrayResult[index] = buffer_readstring(sourceBuffer, cursor + 1, l)
			cursor += 1 + l
		end
		reader.cursor = cursor
		return arrayResult
	elseif tagByte == TAG_ARR_STRUCT then
		local rowCount = readVariableInteger(reader)
		local cursor = reader.cursor
		if cursor >= reader.len then
			return {}
		end
		local sourceBuffer = reader.buff
		local columnCount = buffer_readu8(sourceBuffer, cursor)
		cursor += 1
		if columnCount <= 0 or columnCount > 64 or cursor + columnCount > reader.len then
			reader.cursor = reader.len
			return {}
		end
		local columnTypes = table_create(columnCount)
		for colIndex = 1, columnCount do
			columnTypes[colIndex] = buffer_readu8(sourceBuffer, cursor)
			cursor += 1
		end
		reader.cursor = cursor
		local columnNames = table_create(columnCount) :: { string }
		for colIndex = 1, columnCount do
			columnNames[colIndex] = readLengthPrefixedString(reader)
		end
		cursor = reader.cursor
		sourceBuffer = reader.buff
		if rowCount > (reader.len - cursor) then
			rowCount = math_max(0, reader.len - cursor)
		end
		if rowCount <= 0 then
			return {}
		end
		local resultRows = table_create(rowCount)
		if
			columnCount == 6
			and columnTypes[1] == 1
			and columnTypes[2] == 1
			and columnTypes[3] == 1
			and columnTypes[4] == 1
			and columnTypes[5] == 1
			and columnTypes[6] == 1
		then
			if
				columnNames[1] == "animation"
				and columnNames[2] == "id"
				and columnNames[3] == "orientation"
				and columnNames[4] == "x"
				and columnNames[5] == "y"
				and columnNames[6] == "z"
			then
				for rowIndex = 1, rowCount do
					if cursor + 6 > reader.len then break end
					resultRows[rowIndex] = {
						animation = buffer_readu8(sourceBuffer, cursor),
						id = buffer_readu8(sourceBuffer, cursor + 1),
						orientation = buffer_readu8(sourceBuffer, cursor + 2),
						x = buffer_readu8(sourceBuffer, cursor + 3),
						y = buffer_readu8(sourceBuffer, cursor + 4),
						z = buffer_readu8(sourceBuffer, cursor + 5),
					}
					cursor += 6
				end
			else
				local key1 = columnNames[1]
				local key2 = columnNames[2]
				local key3 = columnNames[3]
				local key4 = columnNames[4]
				local key5 = columnNames[5]
				local key6 = columnNames[6]
				for rowIndex = 1, rowCount do
					if cursor + 6 > reader.len then break end
					resultRows[rowIndex] = {
						[key1] = buffer_readu8(sourceBuffer, cursor),
						[key2] = buffer_readu8(sourceBuffer, cursor + 1),
						[key3] = buffer_readu8(sourceBuffer, cursor + 2),
						[key4] = buffer_readu8(sourceBuffer, cursor + 3),
						[key5] = buffer_readu8(sourceBuffer, cursor + 4),
						[key6] = buffer_readu8(sourceBuffer, cursor + 5),
					}
					cursor += 6
				end
			end
		elseif
			columnCount == 11
			and columnTypes[1] == 1
			and columnTypes[2] == 2
			and columnTypes[3] == 2
			and columnTypes[4] == 7
			and columnTypes[5] == 7
			and columnTypes[6] == 7
			and columnTypes[7] == 7
			and columnTypes[8] == 1
			and columnTypes[9] == 7
			and columnTypes[10] == 7
			and columnTypes[11] == 7
		then
			if
				columnNames[1] == "animation"
				and columnNames[2] == "health"
				and columnNames[3] == "id"
				and columnNames[4] == "qw"
				and columnNames[5] == "qx"
				and columnNames[6] == "qy"
				and columnNames[7] == "qz"
				and columnNames[8] == "team"
				and columnNames[9] == "x"
				and columnNames[10] == "y"
				and columnNames[11] == "z"
			then
				for rowIndex = 1, rowCount do
					if cursor + 34 > reader.len then break end
					resultRows[rowIndex] = {
						animation = buffer_readu8(sourceBuffer, cursor),
						health = buffer_readu16(sourceBuffer, cursor + 1),
						id = buffer_readu16(sourceBuffer, cursor + 3),
						qw = buffer_readf32(sourceBuffer, cursor + 5),
						qx = buffer_readf32(sourceBuffer, cursor + 9),
						qy = buffer_readf32(sourceBuffer, cursor + 13),
						qz = buffer_readf32(sourceBuffer, cursor + 17),
						team = buffer_readu8(sourceBuffer, cursor + 21),
						x = buffer_readf32(sourceBuffer, cursor + 22),
						y = buffer_readf32(sourceBuffer, cursor + 26),
						z = buffer_readf32(sourceBuffer, cursor + 30),
					}
					cursor += 34
				end
			else
				local key1 = columnNames[1]
				local key2 = columnNames[2]
				local key3 = columnNames[3]
				local key4 = columnNames[4]
				local key5 = columnNames[5]
				local key6 = columnNames[6]
				local key7 = columnNames[7]
				local key8 = columnNames[8]
				local key9 = columnNames[9]
				local key10 = columnNames[10]
				local key11 = columnNames[11]
				for rowIndex = 1, rowCount do
					if cursor + 34 > reader.len then break end
					resultRows[rowIndex] = {
						[key1] = buffer_readu8(sourceBuffer, cursor),
						[key2] = buffer_readu16(sourceBuffer, cursor + 1),
						[key3] = buffer_readu16(sourceBuffer, cursor + 3),
						[key4] = buffer_readf32(sourceBuffer, cursor + 5),
						[key5] = buffer_readf32(sourceBuffer, cursor + 9),
						[key6] = buffer_readf32(sourceBuffer, cursor + 13),
						[key7] = buffer_readf32(sourceBuffer, cursor + 17),
						[key8] = buffer_readu8(sourceBuffer, cursor + 21),
						[key9] = buffer_readf32(sourceBuffer, cursor + 22),
						[key10] = buffer_readf32(sourceBuffer, cursor + 26),
						[key11] = buffer_readf32(sourceBuffer, cursor + 30),
					}
					cursor += 34
				end
			end
		else
			for rowIndex = 1, rowCount do
				if cursor >= reader.len then
					break
				end
				local rowObject: { [string]: any } = {}
				for colIndex = 1, columnCount do
					if cursor >= reader.len then
						break
					end
					local colType = columnTypes[colIndex]
					local colKey = columnNames[colIndex]
					if colType == 1 then
						rowObject[colKey] = buffer_readu8(sourceBuffer, cursor)
						cursor += 1
					elseif colType == 2 then
						if cursor + 2 <= reader.len then
							rowObject[colKey] = buffer_readu16(sourceBuffer, cursor)
							cursor += 2
						else
							break
						end
					elseif colType == 7 then
						if cursor + 4 <= reader.len then
							rowObject[colKey] = buffer_readf32(sourceBuffer, cursor)
							cursor += 4
						else
							break
						end
					elseif colType == 5 then
						if cursor + 2 <= reader.len then
							rowObject[colKey] = buffer_readi16(sourceBuffer, cursor)
							cursor += 2
						else
							break
						end
					elseif colType == 9 then
						rowObject[colKey] = buffer_readu8(sourceBuffer, cursor) == 1
						cursor += 1
					elseif colType == 3 then
						if cursor + 4 <= reader.len then
							rowObject[colKey] = buffer_readu32(sourceBuffer, cursor)
							cursor += 4
						else
							break
						end
					elseif colType == 6 then
						if cursor + 4 <= reader.len then
							rowObject[colKey] = buffer_readi32(sourceBuffer, cursor)
							cursor += 4
						else
							break
						end
					elseif colType == 10 then
						if cursor + 12 <= reader.len then
							rowObject[colKey] = Vector3.new(
								buffer_readf32(sourceBuffer, cursor),
								buffer_readf32(sourceBuffer, cursor + 4),
								buffer_readf32(sourceBuffer, cursor + 8)
							)
							cursor += 12
						else
							break
						end
					elseif colType == 11 then
						if cursor + 3 <= reader.len then
							rowObject[colKey] = Color3.fromRGB(
								buffer_readu8(sourceBuffer, cursor),
								buffer_readu8(sourceBuffer, cursor + 1),
								buffer_readu8(sourceBuffer, cursor + 2)
							)
							cursor += 3
						else
							break
						end
					elseif colType == 12 then
						if cursor + 24 <= reader.len then
							local posX = buffer_readf32(sourceBuffer, cursor)
							local posY = buffer_readf32(sourceBuffer, cursor + 4)
							local posZ = buffer_readf32(sourceBuffer, cursor + 8)
							local rotX = buffer_readf32(sourceBuffer, cursor + 12)
							local rotY = buffer_readf32(sourceBuffer, cursor + 16)
							local rotZ = buffer_readf32(sourceBuffer, cursor + 20)
							rowObject[colKey] = CFrame.Angles(rotX, rotY, rotZ) + Vector3.new(posX, posY, posZ)
							cursor += 24
						else
							break
						end
					elseif colType == 13 then
						local strLength = buffer_readu8(sourceBuffer, cursor)
						cursor += 1
						if strLength > 0 and cursor + strLength <= reader.len then
							rowObject[colKey] = buffer_readstring(sourceBuffer, cursor, strLength)
							cursor += strLength
						else
							rowObject[colKey] = ""
						end
					elseif colType == 4 then
						rowObject[colKey] = buffer_readi8(sourceBuffer, cursor)
						cursor += 1
					elseif colType == 8 then
						if cursor + 8 <= reader.len then
							rowObject[colKey] = buffer_readf64(sourceBuffer, cursor)
							cursor += 8
						else
							break
						end
					end
				end
				resultRows[rowIndex] = rowObject
			end
		end
		reader.cursor = cursor
		return resultRows
	elseif tagByte == TAG_ARR_VEC3 then
		local count = readVariableInteger(reader)
		local availableElements = (reader.len - reader.cursor) // 12
		if count > availableElements then
			count = availableElements
		end
		if count <= 0 then
			return {}
		end
		local arrayResult = table_create(count)
		local cursor = reader.cursor
		local sourceBuffer = reader.buff
		local fourVectorBlocks = count - (count % 4)
		for index = 1, fourVectorBlocks, 4 do
			arrayResult[index] = Vector3.new(
				buffer_readf32(sourceBuffer, cursor),
				buffer_readf32(sourceBuffer, cursor + 4),
				buffer_readf32(sourceBuffer, cursor + 8)
			)
			arrayResult[index + 1] = Vector3.new(
				buffer_readf32(sourceBuffer, cursor + 12),
				buffer_readf32(sourceBuffer, cursor + 16),
				buffer_readf32(sourceBuffer, cursor + 20)
			)
			arrayResult[index + 2] = Vector3.new(
				buffer_readf32(sourceBuffer, cursor + 24),
				buffer_readf32(sourceBuffer, cursor + 28),
				buffer_readf32(sourceBuffer, cursor + 32)
			)
			arrayResult[index + 3] = Vector3.new(
				buffer_readf32(sourceBuffer, cursor + 36),
				buffer_readf32(sourceBuffer, cursor + 40),
				buffer_readf32(sourceBuffer, cursor + 44)
			)
			cursor += 48
		end
		for index = fourVectorBlocks + 1, count do
			arrayResult[index] = Vector3.new(
				buffer_readf32(sourceBuffer, cursor),
				buffer_readf32(sourceBuffer, cursor + 4),
				buffer_readf32(sourceBuffer, cursor + 8)
			)
			cursor += 12
		end
		reader.cursor = cursor
		return arrayResult
	elseif tagByte == TAG_ARR_COLOR3 then
		local count = readVariableInteger(reader)
		local availableElements = (reader.len - reader.cursor) // 3
		if count > availableElements then
			count = availableElements
		end
		if count <= 0 then
			return {}
		end
		local arrayResult = table_create(count)
		local cursor = reader.cursor
		local sourceBuffer = reader.buff
		local fourColorBlocks = count - (count % 4)
		for index = 1, fourColorBlocks, 4 do
			arrayResult[index] = Color3.fromRGB(
				buffer_readu8(sourceBuffer, cursor),
				buffer_readu8(sourceBuffer, cursor + 1),
				buffer_readu8(sourceBuffer, cursor + 2)
			)
			arrayResult[index + 1] = Color3.fromRGB(
				buffer_readu8(sourceBuffer, cursor + 3),
				buffer_readu8(sourceBuffer, cursor + 4),
				buffer_readu8(sourceBuffer, cursor + 5)
			)
			arrayResult[index + 2] = Color3.fromRGB(
				buffer_readu8(sourceBuffer, cursor + 6),
				buffer_readu8(sourceBuffer, cursor + 7),
				buffer_readu8(sourceBuffer, cursor + 8)
			)
			arrayResult[index + 3] = Color3.fromRGB(
				buffer_readu8(sourceBuffer, cursor + 9),
				buffer_readu8(sourceBuffer, cursor + 10),
				buffer_readu8(sourceBuffer, cursor + 11)
			)
			cursor += 12
		end
		for index = fourColorBlocks + 1, count do
			arrayResult[index] = Color3.fromRGB(
				buffer_readu8(sourceBuffer, cursor),
				buffer_readu8(sourceBuffer, cursor + 1),
				buffer_readu8(sourceBuffer, cursor + 2)
			)
			cursor += 3
		end
		reader.cursor = cursor
		return arrayResult
	elseif tagByte == TAG_ARR_CF then
		local count = readVariableInteger(reader)
		local availableElements = (reader.len - reader.cursor) // 48
		if count > availableElements then
			count = availableElements
		end
		if count <= 0 then
			return {}
		end
		local arrayResult = table_create(count)
		local cursor = reader.cursor
		local sourceBuffer = reader.buff
		local rem = count % 2
		local unrolled = count - rem
		for index = 1, unrolled, 2 do
			arrayResult[index] = CFrame.new(
				buffer_readf32(sourceBuffer, cursor),
				buffer_readf32(sourceBuffer, cursor + 4),
				buffer_readf32(sourceBuffer, cursor + 8),
				buffer_readf32(sourceBuffer, cursor + 12),
				buffer_readf32(sourceBuffer, cursor + 16),
				buffer_readf32(sourceBuffer, cursor + 20),
				buffer_readf32(sourceBuffer, cursor + 24),
				buffer_readf32(sourceBuffer, cursor + 28),
				buffer_readf32(sourceBuffer, cursor + 32),
				buffer_readf32(sourceBuffer, cursor + 36),
				buffer_readf32(sourceBuffer, cursor + 40),
				buffer_readf32(sourceBuffer, cursor + 44)
			)
			arrayResult[index + 1] = CFrame.new(
				buffer_readf32(sourceBuffer, cursor + 48),
				buffer_readf32(sourceBuffer, cursor + 52),
				buffer_readf32(sourceBuffer, cursor + 56),
				buffer_readf32(sourceBuffer, cursor + 60),
				buffer_readf32(sourceBuffer, cursor + 64),
				buffer_readf32(sourceBuffer, cursor + 68),
				buffer_readf32(sourceBuffer, cursor + 72),
				buffer_readf32(sourceBuffer, cursor + 76),
				buffer_readf32(sourceBuffer, cursor + 80),
				buffer_readf32(sourceBuffer, cursor + 84),
				buffer_readf32(sourceBuffer, cursor + 88),
				buffer_readf32(sourceBuffer, cursor + 92)
			)
			cursor += 96
		end
		for index = unrolled + 1, count do
			arrayResult[index] = CFrame.new(
				buffer_readf32(sourceBuffer, cursor),
				buffer_readf32(sourceBuffer, cursor + 4),
				buffer_readf32(sourceBuffer, cursor + 8),
				buffer_readf32(sourceBuffer, cursor + 12),
				buffer_readf32(sourceBuffer, cursor + 16),
				buffer_readf32(sourceBuffer, cursor + 20),
				buffer_readf32(sourceBuffer, cursor + 24),
				buffer_readf32(sourceBuffer, cursor + 28),
				buffer_readf32(sourceBuffer, cursor + 32),
				buffer_readf32(sourceBuffer, cursor + 36),
				buffer_readf32(sourceBuffer, cursor + 40),
				buffer_readf32(sourceBuffer, cursor + 44)
			)
			cursor += 48
		end
		reader.cursor = cursor
		return arrayResult
	elseif tagByte == TAG_BUFFER then
		local bufferBytesLength = readVariableInteger(reader)
		local availableBytes = reader.len - reader.cursor
		if bufferBytesLength > availableBytes then
			bufferBytesLength = availableBytes
		end
		if bufferBytesLength <= 0 then
			return buffer_create(0)
		end
		local cursor = reader.cursor
		reader.cursor = cursor + bufferBytesLength
		local extractedBuffer = buffer_create(bufferBytesLength)
		buffer_copy(extractedBuffer, 0, reader.buff, cursor, bufferBytesLength)
		return extractedBuffer
	end
	local specificHandler = DeserializerHandlers[tagByte]
	return if specificHandler then specificHandler(reader) else nil
end
function Buffers.WriteU16(writer: Writer, integerValue: number)
	ensureCapacity(writer, 2)
	buffer_writeu16(writer.buff, writer.cursor, integerValue)
	writer.cursor += 2
end
function Buffers.ReadU16(reader: Reader): number
	local cursor = reader.cursor
	if cursor + 2 > reader.len then
		reader.cursor = reader.len
		return 0
	end
	reader.cursor = cursor + 2
	return buffer_readu16(reader.buff, cursor)
end
function Buffers.WritePacketHeader(writer: Writer, packetType: number, argumentCount: number)
	ensureCapacity(writer, if argumentCount < 63 then 1 else 6)
	if argumentCount < 63 then
		buffer_writeu8(writer.buff, writer.cursor, bit_bor(bit_lshift(packetType, 6), argumentCount))
		writer.cursor += 1
	else
		buffer_writeu8(writer.buff, writer.cursor, bit_bor(bit_lshift(packetType, 6), 63))
		writer.cursor += 1
		writeVariableInteger(writer, argumentCount)
	end
end
function Buffers.ReadPacketHeader(reader: Reader): (number, number)
	local cursor = reader.cursor
	if cursor >= reader.len then
		return 0, 0
	end
	local headerByte = buffer_readu8(reader.buff, cursor)
	reader.cursor = cursor + 1
	local packetType = bit_rshift(headerByte, 6)
	local argumentCount = bit_band(headerByte, 0x3F)
	if argumentCount == 63 then
		argumentCount = readVariableInteger(reader)
	end
	return packetType, argumentCount
end
function Buffers.WriteEventHeader(writer: Writer, channelHash: number, packetType: number, argumentCount: number)
	if argumentCount < 63 then
		ensureCapacity(writer, 3)
		buffer_writeu16(writer.buff, writer.cursor, channelHash)
		buffer_writeu8(writer.buff, writer.cursor + 2, bit_bor(bit_lshift(packetType, 6), argumentCount))
		writer.cursor += 3
	else
		ensureCapacity(writer, 3)
		buffer_writeu16(writer.buff, writer.cursor, channelHash)
		buffer_writeu8(writer.buff, writer.cursor + 2, bit_bor(bit_lshift(packetType, 6), 63))
		writer.cursor += 3
		writeVariableInteger(writer, argumentCount)
	end
end
function Buffers.ReadEventHeader(reader: Reader): (number, number, number)
	local cursor = reader.cursor
	if cursor + 3 > reader.len then
		reader.cursor = reader.len
		return 0, 0, 0
	end
	local channelHash = buffer_readu16(reader.buff, cursor)
	local packedByte = buffer_readu8(reader.buff, cursor + 2)
	reader.cursor = cursor + 3
	local packetType = bit_rshift(packedByte, 6)
	local argumentCount = bit_band(packedByte, 0x3F)
	if argumentCount == 63 then
		argumentCount = readVariableInteger(reader)
	end
	return channelHash, packetType, argumentCount
end
function Buffers.CreateWriter(capacity: number?): Writer
	local poolCount = #WRITER_POOL
	if poolCount > 0 then
		local pooledWriter = WRITER_POOL[poolCount]
		WRITER_POOL[poolCount] = nil
		pooledWriter.cursor = 0
		table_clear(pooledWriter.insts)
		return pooledWriter
	end
	local initialCapacity = if capacity and capacity > 0 then capacity else INITIAL_BUFFER_CAPACITY
	return {
		buff = buffer_create(initialCapacity),
		cursor = 0,
		len = initialCapacity,
		insts = {},
	}
end
function Buffers.CreateReader(rawBuffer: buffer, instanceList: { Instance }?): Reader
	local poolCount = #READER_POOL
	if poolCount > 0 then
		local pooledReader = READER_POOL[poolCount]
		READER_POOL[poolCount] = nil
		pooledReader.buff = rawBuffer
		pooledReader.cursor = 0
		pooledReader.len = buffer_len(rawBuffer)
		pooledReader.insts = instanceList or {}
		return pooledReader
	end
	return {
		buff = rawBuffer,
		cursor = 0,
		len = buffer_len(rawBuffer),
		insts = instanceList or {},
	}
end
function Buffers.FreeWriter(writer: Writer)
	if writer.len <= MAX_POOLED_BUFFER_SIZE and #WRITER_POOL < MAX_POOL_CAPACITY then
		WRITER_POOL[#WRITER_POOL + 1] = writer
	end
end
function Buffers.FreeReader(reader: Reader)
	if #READER_POOL < MAX_POOL_CAPACITY then
		READER_POOL[#READER_POOL + 1] = reader
	end
end
function Buffers.Finalize(writer: Writer): (buffer, { Instance }?)
	local finalizedBuffer = buffer_create(writer.cursor)
	buffer_copy(finalizedBuffer, 0, writer.buff, 0, writer.cursor)
	return finalizedBuffer, if #writer.insts > 0 then writer.insts else nil
end
function Buffers.WriteAny(writer: Writer, targetValue: any, currentDepth: number?)
	writeAnyValue(writer, targetValue, currentDepth or 0)
end
function Buffers.ReadAny(reader: Reader): any
	return readAnyValue(reader, 0)
end
return Buffers