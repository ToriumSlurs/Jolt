--!strict
--!native
--!optimize 2
local Buffers = {}

local b_create = buffer.create
local b_len = buffer.len
local b_copy = buffer.copy
local b_w_u8 = buffer.writeu8
local b_r_u8 = buffer.readu8
local b_w_u16 = buffer.writeu16
local b_r_u16 = buffer.readu16
local b_w_u32 = buffer.writeu32
local b_r_u32 = buffer.readu32
local b_w_i8 = buffer.writei8
local b_r_i8 = buffer.readi8
local b_w_i16 = buffer.writei16
local b_r_i16 = buffer.readi16
local b_w_i32 = buffer.writei32
local b_r_i32 = buffer.readi32
local b_w_f32 = buffer.writef32
local b_r_f32 = buffer.readf32
local b_w_f64 = buffer.writef64
local b_r_f64 = buffer.readf64
local b_w_str = buffer.writestring
local b_r_str = buffer.readstring

local t_insert = table.insert
local t_remove = table.remove
local t_clear = table.clear
local t_create = table.create

local b_lshift = bit32.lshift
local b_rshift = bit32.rshift
local b_bor = bit32.bor
local b_band = bit32.band

export type Writer = {
	buff: buffer,
	cursor: number,
	len: number,
	insts: { Instance },
	refs: { [ { [any]: any } ]: number },
	refCount: number,
}

export type Reader = {
	buff: buffer,
	cursor: number,
	len: number,
	insts: { Instance },
	refs: { [number]: any },
	refCount: number,
}

local ALLOC_SIZE = 4096
local POOL_SIZE = 512
local MAX_REUSE_SIZE = 64 * 1024

local TYPE_NIL = 0
local TYPE_BOOL = 1
local TYPE_NUMBER = 2
local TYPE_STRING = 3
local TYPE_BUFFER = 4
local TYPE_VECTOR2 = 5
local TYPE_VECTOR3 = 6
local TYPE_CFRAME = 7
local TYPE_COLOR3 = 8
local TYPE_UDIM = 9
local TYPE_UDIM2 = 10
local TYPE_REGION3 = 11
local TYPE_INSTANCE = 12
local TYPE_ENUM = 13
local TYPE_BRICKCOLOR = 14
local TYPE_TWEENINFO = 15
local TYPE_TABLE = 16
local TYPE_INT_U8 = 17
local TYPE_INT_U16 = 18
local TYPE_INT_U32 = 19
local TYPE_INT_I16 = 20
local TYPE_INT_I32 = 21
local TYPE_REF = 22
local TYPE_ARRAY = 23
local TYPE_STRING_U8 = 24
local TYPE_STRING_U16 = 25

local WriterPool: { [number]: Writer } = {}
local ReaderPool: { [number]: Reader } = {}

local EnumCache: { [EnumItem]: string } = {}
local StringToEnumCache: { [string]: EnumItem } = {}

local function Resize(w: Writer, needed: number)
	local oldLen = w.len
	local newLen = oldLen
	while w.cursor + needed > newLen do
		newLen = newLen * 2
	end
	if newLen ~= oldLen then
		local newBuff = b_create(newLen)
		b_copy(newBuff, 0, w.buff, 0, w.cursor)
		w.buff = newBuff
		w.len = newLen
	end
end

function Buffers.EnsureCapacity(w: Writer, needed: number)
	if w.cursor + needed > w.len then
		Resize(w, needed)
	end
end

function Buffers.CreateWriter(capacity: number?): Writer
	local w = t_remove(WriterPool)
	if w then
		w.cursor = 0
		w.refCount = 0
		t_clear(w.insts)
		t_clear(w.refs)
		return w
	end

	local cap = capacity or ALLOC_SIZE

	return {
		buff = b_create(cap),
		cursor = 0,
		len = cap,
		insts = {},
		refs = {},
		refCount = 0,
	}
end

function Buffers.CreateReader(buff: buffer, instances: { Instance }?): Reader
	local r = t_remove(ReaderPool)
	if r then
		r.buff = buff
		r.cursor = 0
		r.len = b_len(buff)
		r.insts = instances or {}
		r.refCount = 0
		t_clear(r.refs)
		return r
	end

	return {
		buff = buff,
		cursor = 0,
		len = b_len(buff),
		insts = instances or {},
		refs = {},
		refCount = 0,
	}
end

function Buffers.FreeWriter(w: Writer)
	if w.len > MAX_REUSE_SIZE then
		return
	end

	if #WriterPool < POOL_SIZE then
		t_insert(WriterPool, w)
	end
end

function Buffers.FreeReader(r: Reader)
	if #ReaderPool < POOL_SIZE then
		t_insert(ReaderPool, r)
	end
end

function Buffers.Finalize(w: Writer): (buffer, { Instance })
	local b = b_create(w.cursor)
	b_copy(b, 0, w.buff, 0, w.cursor)
	return b, table.clone(w.insts)
end

function Buffers.WriteU8(w: Writer, v: number)
	if w.cursor + 1 > w.len then
		Resize(w, 1)
	end
	b_w_u8(w.buff, w.cursor, v)
	w.cursor += 1
end

function Buffers.ReadU8(r: Reader): number
	if r.cursor + 1 > r.len then
		r.cursor = r.len
		return 0
	end
	local v = b_r_u8(r.buff, r.cursor)
	r.cursor += 1
	return v
end

function Buffers.WriteU16(w: Writer, v: number)
	if w.cursor + 2 > w.len then
		Resize(w, 2)
	end
	b_w_u16(w.buff, w.cursor, v)
	w.cursor += 2
end

function Buffers.ReadU16(r: Reader): number
	if r.cursor + 2 > r.len then
		r.cursor = r.len
		return 0
	end
	local v = b_r_u16(r.buff, r.cursor)
	r.cursor += 2
	return v
end

function Buffers.WriteU32(w: Writer, v: number)
	if w.cursor + 4 > w.len then
		Resize(w, 4)
	end
	b_w_u32(w.buff, w.cursor, v)
	w.cursor += 4
end

function Buffers.ReadU32(r: Reader): number
	if r.cursor + 4 > r.len then
		r.cursor = r.len
		return 0
	end
	local v = b_r_u32(r.buff, r.cursor)
	r.cursor += 4
	return v
end

function Buffers.WriteI8(w: Writer, v: number)
	if w.cursor + 1 > w.len then
		Resize(w, 1)
	end
	b_w_i8(w.buff, w.cursor, v)
	w.cursor += 1
end

function Buffers.ReadI8(r: Reader): number
	if r.cursor + 1 > r.len then
		r.cursor = r.len
		return 0
	end
	local v = b_r_i8(r.buff, r.cursor)
	r.cursor += 1
	return v
end

function Buffers.WriteI16(w: Writer, v: number)
	if w.cursor + 2 > w.len then
		Resize(w, 2)
	end
	b_w_i16(w.buff, w.cursor, v)
	w.cursor += 2
end

function Buffers.ReadI16(r: Reader): number
	if r.cursor + 2 > r.len then
		r.cursor = r.len
		return 0
	end
	local v = b_r_i16(r.buff, r.cursor)
	r.cursor += 2
	return v
end

function Buffers.WriteI32(w: Writer, v: number)
	if w.cursor + 4 > w.len then
		Resize(w, 4)
	end
	b_w_i32(w.buff, w.cursor, v)
	w.cursor += 4
end

function Buffers.ReadI32(r: Reader): number
	if r.cursor + 4 > r.len then
		r.cursor = r.len
		return 0
	end
	local v = b_r_i32(r.buff, r.cursor)
	r.cursor += 4
	return v
end

function Buffers.WriteF32(w: Writer, v: number)
	if w.cursor + 4 > w.len then
		Resize(w, 4)
	end
	b_w_f32(w.buff, w.cursor, v)
	w.cursor += 4
end

function Buffers.ReadF32(r: Reader): number
	if r.cursor + 4 > r.len then
		r.cursor = r.len
		return 0
	end
	local v = b_r_f32(r.buff, r.cursor)
	r.cursor += 4
	return v
end

function Buffers.WriteF64(w: Writer, v: number)
	if w.cursor + 8 > w.len then
		Resize(w, 8)
	end
	b_w_f64(w.buff, w.cursor, v)
	w.cursor += 8
end

function Buffers.ReadF64(r: Reader): number
	if r.cursor + 8 > r.len then
		r.cursor = r.len
		return 0
	end
	local v = b_r_f64(r.buff, r.cursor)
	r.cursor += 8
	return v
end

function Buffers.WriteBool(w: Writer, v: boolean)
	Buffers.WriteU8(w, v and 1 or 0)
end

function Buffers.ReadBool(r: Reader): boolean
	return Buffers.ReadU8(r) == 1
end

function Buffers.WriteVarInt(w: Writer, v: number)
	if w.cursor + 5 > w.len then
		Resize(w, 5)
	end
	local val = v
	while val >= 128 do
		b_w_u8(w.buff, w.cursor, b_bor(val, 0x80))
		w.cursor += 1
		val = b_rshift(val, 7)
	end
	b_w_u8(w.buff, w.cursor, val)
	w.cursor += 1
end

function Buffers.ReadVarInt(r: Reader): number
	local c = 0
	local v = 0
	local b
	repeat
		if r.cursor + 1 > r.len then
			r.cursor = r.len
			return 0
		end
		b = b_r_u8(r.buff, r.cursor)
		r.cursor += 1
		v = b_bor(v, b_lshift(b_band(b, 0x7F), c))
		c += 7
	until b_band(b, 0x80) == 0
	return v
end

function Buffers.WriteString(w: Writer, v: string)
	local len = #v
	Buffers.WriteVarInt(w, len)
	if w.cursor + len > w.len then
		Resize(w, len)
	end
	b_w_str(w.buff, w.cursor, v, len)
	w.cursor += len
end

function Buffers.ReadString(r: Reader): string
	local len = Buffers.ReadVarInt(r)
	if r.cursor + len > r.len then
		r.cursor = r.len
		return ""
	end
	local v = b_r_str(r.buff, r.cursor, len)
	r.cursor += len
	return v
end

function Buffers.WriteBuffer(w: Writer, v: buffer)
	local len = b_len(v)
	Buffers.WriteVarInt(w, len)
	if w.cursor + len > w.len then
		Resize(w, len)
	end
	b_copy(w.buff, w.cursor, v, 0, len)
	w.cursor += len
end

function Buffers.ReadBuffer(r: Reader): buffer
	local len = Buffers.ReadVarInt(r)
	if r.cursor + len > r.len then
		r.cursor = r.len
		return b_create(0)
	end
	local b = b_create(len)
	b_copy(b, 0, r.buff, r.cursor, len)
	r.cursor += len
	return b
end

function Buffers.WriteVector2(w: Writer, v: Vector2)
	Buffers.WriteF32(w, v.X)
	Buffers.WriteF32(w, v.Y)
end

function Buffers.ReadVector2(r: Reader): Vector2
	return Vector2.new(Buffers.ReadF32(r), Buffers.ReadF32(r))
end

function Buffers.WriteVector3(w: Writer, v: Vector3)
	Buffers.WriteF32(w, v.X)
	Buffers.WriteF32(w, v.Y)
	Buffers.WriteF32(w, v.Z)
end

function Buffers.ReadVector3(r: Reader): Vector3
	return Vector3.new(Buffers.ReadF32(r), Buffers.ReadF32(r), Buffers.ReadF32(r))
end

function Buffers.WriteCFrame(w: Writer, v: CFrame)
	local axis, angle = v:ToAxisAngle()
	Buffers.WriteVector3(w, v.Position)
	Buffers.WriteVector3(w, axis)
	Buffers.WriteF32(w, angle)
end

function Buffers.ReadCFrame(r: Reader): CFrame
	local pos = Buffers.ReadVector3(r)
	local axis = Buffers.ReadVector3(r)
	local angle = Buffers.ReadF32(r)
	return CFrame.fromAxisAngle(axis, angle) + pos
end

function Buffers.WriteColor3(w: Writer, v: Color3)
	Buffers.WriteU8(w, math.round(v.R * 255))
	Buffers.WriteU8(w, math.round(v.G * 255))
	Buffers.WriteU8(w, math.round(v.B * 255))
end

function Buffers.ReadColor3(r: Reader): Color3
	return Color3.fromRGB(Buffers.ReadU8(r), Buffers.ReadU8(r), Buffers.ReadU8(r))
end

function Buffers.WriteUDim(w: Writer, v: UDim)
	Buffers.WriteF32(w, v.Scale)
	Buffers.WriteI32(w, v.Offset)
end

function Buffers.ReadUDim(r: Reader): UDim
	return UDim.new(Buffers.ReadF32(r), Buffers.ReadI32(r))
end

function Buffers.WriteUDim2(w: Writer, v: UDim2)
	Buffers.WriteUDim(w, v.X)
	Buffers.WriteUDim(w, v.Y)
end

function Buffers.ReadUDim2(r: Reader): UDim2
	return UDim2.new(Buffers.ReadUDim(r), Buffers.ReadUDim(r))
end

function Buffers.WriteRegion3(w: Writer, v: Region3)
	Buffers.WriteCFrame(w, v.CFrame)
	Buffers.WriteVector3(w, v.Size)
end

function Buffers.ReadRegion3(r: Reader): Region3
	local cf = Buffers.ReadCFrame(r)
	local size = Buffers.ReadVector3(r)
	return Region3.new(cf.Position - size / 2, cf.Position + size / 2)
end

function Buffers.WriteInstance(w: Writer, v: Instance)
	t_insert(w.insts, v)
	Buffers.WriteVarInt(w, #w.insts)
end

function Buffers.ReadInstance(r: Reader): Instance?
	local idx = Buffers.ReadVarInt(r)
	return r.insts[idx]
end

function Buffers.WriteEnum(w: Writer, v: EnumItem)
	local str = EnumCache[v]
	if not str then
		str = tostring(v)
		EnumCache[v] = str
	end
	Buffers.WriteString(w, str)
end

function Buffers.ReadEnum(r: Reader): EnumItem?
	local str = Buffers.ReadString(r)
	local v = StringToEnumCache[str]
	if v then
		return v
	end

	local firstDot = string.find(str, ".", 1, true)
	if not firstDot then
		return nil
	end
	local secondDot = string.find(str, ".", firstDot + 1, true)
	if not secondDot then
		return nil
	end

	local enumName = string.sub(str, firstDot + 1, secondDot - 1)
	local itemName = string.sub(str, secondDot + 1)

	local enum = (Enum :: any)[enumName]
	if enum then
		local item = enum[itemName]
		if item then
			StringToEnumCache[str] = item
			return item
		end
	end
	return nil
end

function Buffers.WriteBrickColor(w: Writer, v: BrickColor)
	Buffers.WriteU16(w, v.Number)
end

function Buffers.ReadBrickColor(r: Reader): BrickColor
	return BrickColor.new(Buffers.ReadU16(r))
end

function Buffers.WriteTweenInfo(w: Writer, v: TweenInfo)
	Buffers.WriteF64(w, v.Time)
	Buffers.WriteEnum(w, v.EasingStyle)
	Buffers.WriteEnum(w, v.EasingDirection)
	Buffers.WriteI32(w, v.RepeatCount)
	Buffers.WriteBool(w, v.Reverses)
	Buffers.WriteF64(w, v.DelayTime)
end

function Buffers.ReadTweenInfo(r: Reader): TweenInfo
	local t = Buffers.ReadF64(r)
	local es = Buffers.ReadEnum(r) or Enum.EasingStyle.Linear
	local ed = Buffers.ReadEnum(r) or Enum.EasingDirection.In
	local rc = Buffers.ReadI32(r)
	local rev = Buffers.ReadBool(r)
	local dt = Buffers.ReadF64(r)
	return TweenInfo.new(t, es :: Enum.EasingStyle, ed :: Enum.EasingDirection, rc, rev, dt)
end

function Buffers.WritePacketHeader(w: Writer, packetType: number, n: number)
	if n < 63 then
		Buffers.WriteU8(w, b_bor(b_lshift(packetType, 6), n))
	else
		Buffers.WriteU8(w, b_bor(b_lshift(packetType, 6), 63))
		Buffers.WriteVarInt(w, n)
	end
end

function Buffers.ReadPacketHeader(r: Reader): (number, number)
	local h = Buffers.ReadU8(r)
	local t = b_rshift(h, 6)
	local c = b_band(h, 0x3F)
	if c == 63 then
		c = Buffers.ReadVarInt(r)
	end
	return t, c
end

local function isPureArray(t: { any }): boolean
	return #t > 0 and next(t, #t) == nil
end

function Buffers.WriteAny(w: Writer, v: any)
	local t = typeof(v)

	if t == "nil" then
		Buffers.WriteU8(w, TYPE_NIL)
	elseif t == "boolean" then
		Buffers.WriteU8(w, TYPE_BOOL)
		Buffers.WriteBool(w, v)
	elseif t == "number" then
		if v % 1 == 0 then
			if v >= 0 then
				if v <= 255 then
					Buffers.WriteU8(w, TYPE_INT_U8)
					Buffers.WriteU8(w, v)
				elseif v <= 65535 then
					Buffers.WriteU8(w, TYPE_INT_U16)
					Buffers.WriteU16(w, v)
				elseif v <= 4294967295 then
					Buffers.WriteU8(w, TYPE_INT_U32)
					Buffers.WriteU32(w, v)
				else
					Buffers.WriteU8(w, TYPE_NUMBER)
					Buffers.WriteF64(w, v)
				end
			else
				if v >= -32768 and v <= 32767 then
					Buffers.WriteU8(w, TYPE_INT_I16)
					Buffers.WriteI16(w, v)
				elseif v >= -2147483648 and v <= 2147483647 then
					Buffers.WriteU8(w, TYPE_INT_I32)
					Buffers.WriteI32(w, v)
				else
					Buffers.WriteU8(w, TYPE_NUMBER)
					Buffers.WriteF64(w, v)
				end
			end
		else
			Buffers.WriteU8(w, TYPE_NUMBER)
			Buffers.WriteF64(w, v)
		end
	elseif t == "string" then
		local len = #v
		if len <= 255 then
			Buffers.WriteU8(w, TYPE_STRING_U8)
			Buffers.WriteU8(w, len)
		elseif len <= 65535 then
			Buffers.WriteU8(w, TYPE_STRING_U16)
			Buffers.WriteU16(w, len)
		else
			Buffers.WriteU8(w, TYPE_STRING)
			Buffers.WriteVarInt(w, len)
		end
		if w.cursor + len > w.len then
			Resize(w, len)
		end
		b_w_str(w.buff, w.cursor, v, len)
		w.cursor += len
	elseif t == "buffer" then
		Buffers.WriteU8(w, TYPE_BUFFER)
		Buffers.WriteBuffer(w, v)
	elseif t == "Vector2" then
		Buffers.WriteU8(w, TYPE_VECTOR2)
		Buffers.WriteVector2(w, v)
	elseif t == "Vector3" then
		Buffers.WriteU8(w, TYPE_VECTOR3)
		Buffers.WriteVector3(w, v)
	elseif t == "CFrame" then
		Buffers.WriteU8(w, TYPE_CFRAME)
		Buffers.WriteCFrame(w, v)
	elseif t == "Color3" then
		Buffers.WriteU8(w, TYPE_COLOR3)
		Buffers.WriteColor3(w, v)
	elseif t == "UDim" then
		Buffers.WriteU8(w, TYPE_UDIM)
		Buffers.WriteUDim(w, v)
	elseif t == "UDim2" then
		Buffers.WriteU8(w, TYPE_UDIM2)
		Buffers.WriteUDim2(w, v)
	elseif t == "Region3" then
		Buffers.WriteU8(w, TYPE_REGION3)
		Buffers.WriteRegion3(w, v)
	elseif t == "Instance" then
		Buffers.WriteU8(w, TYPE_INSTANCE)
		Buffers.WriteInstance(w, v)
	elseif t == "EnumItem" then
		Buffers.WriteU8(w, TYPE_ENUM)
		Buffers.WriteEnum(w, v)
	elseif t == "BrickColor" then
		Buffers.WriteU8(w, TYPE_BRICKCOLOR)
		Buffers.WriteBrickColor(w, v)
	elseif t == "TweenInfo" then
		Buffers.WriteU8(w, TYPE_TWEENINFO)
		Buffers.WriteTweenInfo(w, v)
	elseif t == "table" then
		local ref = w.refs[v]
		if ref then
			Buffers.WriteU8(w, TYPE_REF)
			Buffers.WriteVarInt(w, ref)
		elseif isPureArray(v) then
			w.refCount += 1
			w.refs[v] = w.refCount
			Buffers.WriteU8(w, TYPE_ARRAY)
			local len = #v
			Buffers.WriteVarInt(w, len)
			for i = 1, len do
				Buffers.WriteAny(w, v[i])
			end
		else
			w.refCount += 1
			w.refs[v] = w.refCount
			Buffers.WriteU8(w, TYPE_TABLE)
			for k, val in pairs(v) do
				Buffers.WriteAny(w, k)
				Buffers.WriteAny(w, val)
			end
			Buffers.WriteU8(w, TYPE_NIL)
		end
	else
		Buffers.WriteU8(w, TYPE_NIL)
	end
end

function Buffers.ReadAny(r: Reader): any
	if r.cursor >= r.len then
		return nil
	end
	local typeId = Buffers.ReadU8(r)

	if typeId == TYPE_NIL then
		return nil
	elseif typeId == TYPE_BOOL then
		return Buffers.ReadBool(r)
	elseif typeId == TYPE_NUMBER then
		return Buffers.ReadF64(r)
	elseif typeId == TYPE_STRING then
		return Buffers.ReadString(r)
	elseif typeId == TYPE_STRING_U8 then
		local len = Buffers.ReadU8(r)
		if r.cursor + len > r.len then
			r.cursor = r.len
			return ""
		end
		local v = b_r_str(r.buff, r.cursor, len)
		r.cursor += len
		return v
	elseif typeId == TYPE_STRING_U16 then
		local len = Buffers.ReadU16(r)
		if r.cursor + len > r.len then
			r.cursor = r.len
			return ""
		end
		local v = b_r_str(r.buff, r.cursor, len)
		r.cursor += len
		return v
	elseif typeId == TYPE_BUFFER then
		return Buffers.ReadBuffer(r)
	elseif typeId == TYPE_VECTOR2 then
		return Buffers.ReadVector2(r)
	elseif typeId == TYPE_VECTOR3 then
		return Buffers.ReadVector3(r)
	elseif typeId == TYPE_CFRAME then
		return Buffers.ReadCFrame(r)
	elseif typeId == TYPE_COLOR3 then
		return Buffers.ReadColor3(r)
	elseif typeId == TYPE_UDIM then
		return Buffers.ReadUDim(r)
	elseif typeId == TYPE_UDIM2 then
		return Buffers.ReadUDim2(r)
	elseif typeId == TYPE_REGION3 then
		return Buffers.ReadRegion3(r)
	elseif typeId == TYPE_INSTANCE then
		return Buffers.ReadInstance(r)
	elseif typeId == TYPE_ENUM then
		return Buffers.ReadEnum(r)
	elseif typeId == TYPE_BRICKCOLOR then
		return Buffers.ReadBrickColor(r)
	elseif typeId == TYPE_TWEENINFO then
		return Buffers.ReadTweenInfo(r)
	elseif typeId == TYPE_TABLE then
		local t: { [any]: any } = {}
		r.refCount += 1
		r.refs[r.refCount] = t
		while true do
			local k = Buffers.ReadAny(r)
			if k == nil then
				break
			end
			local val = Buffers.ReadAny(r)
			t[k] = val
		end
		return t
	elseif typeId == TYPE_ARRAY then
		local len = Buffers.ReadVarInt(r)
		local t = table.create(len)
		r.refCount += 1
		r.refs[r.refCount] = t
		for i = 1, len do
			t[i] = Buffers.ReadAny(r)
		end
		return t
	elseif typeId == TYPE_REF then
		local ref = Buffers.ReadVarInt(r)
		return (r.refs[ref] :: any)
	elseif typeId == TYPE_INT_U8 then
		return Buffers.ReadU8(r)
	elseif typeId == TYPE_INT_U16 then
		return Buffers.ReadU16(r)
	elseif typeId == TYPE_INT_U32 then
		return Buffers.ReadU32(r)
	elseif typeId == TYPE_INT_I16 then
		return Buffers.ReadI16(r)
	elseif typeId == TYPE_INT_I32 then
		return Buffers.ReadI32(r)
	end

	return nil
end

function Buffers.Pack(w: Writer, ...)
	local n = select("#", ...)
	Buffers.WriteVarInt(w, n)
	for i = 1, n do
		Buffers.WriteAny(w, select(i, ...))
	end
end

function Buffers.Unpack(r: Reader): { any }
	local n = Buffers.ReadVarInt(r)
	local t = t_create(n)
	for i = 1, n do
		t[i] = Buffers.ReadAny(r)
	end
	return t
end

return Buffers
