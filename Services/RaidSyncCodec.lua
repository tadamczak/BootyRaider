local Raider = BootyRaider
Raider.Services = Raider.Services or {}
local Codec = {}
Raider.Services.RaidSyncCodec = Codec

-- A data grammar, never Lua source. Hex strings keep NUL/control bytes off the
-- addon channel. Jobs yield per node so large imports do not decode in OnEvent.
Codec.limits = {bytes=1048576,nodes=65536,depth=16,string=4096}
local function Count(values) return table.getn(values) end
local function Finite(value) return type(value)=="number" and value==value and value-value==0 end
local function Key(value)
    return type(value)=="string" or (Finite(value) and value>=0 and value<=9007199254740991 and value==math.floor(value))
end
local function Job(callback)
    local job={thread=coroutine.create(callback),done=false}
    function job:Step(limit)
        if self.done then return true,self.value,self.failure,0 end
        limit=math.max(1,math.min(512,math.floor(tonumber(limit) or 128)))
        for index=1,limit do
            local ok,value=coroutine.resume(self.thread)
            if not ok then self.done=true;self.failure=tostring(value);return true,nil,self.failure,index end
            if coroutine.status(self.thread)=="dead" then self.done=true;self.value=value;return true,value,nil,index end
        end
        return false,nil,nil,limit
    end
    return job
end
local function Raise(reason) error(reason,0) end

function Codec.BeginEncode(value)
    return Job(function()
        local output,seen,nodes,bytes={}, {},0,0
        local function Emit(text)
            bytes=bytes+string.len(text)
            if bytes>Codec.limits.bytes then Raise("codec-byte-limit") end
            table.insert(output,text)
        end
        local function Visit(entry,depth)
            nodes=nodes+1
            if nodes>Codec.limits.nodes then Raise("codec-node-limit") end
            if depth>Codec.limits.depth then Raise("codec-depth-limit") end
            coroutine.yield()
            local kind=type(entry)
            if kind=="nil" then Emit("z")
            elseif kind=="boolean" then Emit(entry and "t" or "f")
            elseif kind=="number" then
                if not Finite(entry) then Raise("codec-number") end
                local text=string.format("%.17g",entry);Emit("n"..string.len(text)..":"..text)
            elseif kind=="string" then
                if string.len(entry)>Codec.limits.string then Raise("codec-string-limit") end
                Emit("s"..string.len(entry)..":"..string.gsub(entry,".",function(char) return string.format("%02x",string.byte(char)) end))
            elseif kind=="table" then
                if getmetatable(entry) or seen[entry] then Raise("codec-non-plain-data") end
                seen[entry]=true
                local keys={}
                for key in pairs(entry) do
                    if not Key(key) then Raise("codec-key") end
                    table.insert(keys,key)
                    if Count(keys)>Codec.limits.nodes then Raise("codec-node-limit") end
                    coroutine.yield()
                end
                Emit("m"..Count(keys)..":")
                for _,key in ipairs(keys) do Visit(key,depth+1);Visit(entry[key],depth+1) end
                seen[entry]=nil
            else Raise("codec-type") end
        end
        Visit(value,0)
        return table.concat(output)
    end)
end

function Codec.BeginDecode(text)
    return Job(function()
        if type(text)~="string" or string.len(text)>Codec.limits.bytes then Raise("codec-byte-limit") end
        local position,nodes,length=1,0,string.len(text)
        local function Size(maximum)
            local delimiter=string.find(text,":",position,true)
            if not delimiter or delimiter-position>7 or delimiter==position then Raise("codec-length") end
            local digits=string.sub(text,position,delimiter-1)
            if string.find(digits,"[^0-9]") then Raise("codec-length") end
            local size=tonumber(digits)
            if not size or size>maximum then Raise("codec-length-limit") end
            position=delimiter+1
            return size
        end
        local function Read(depth)
            nodes=nodes+1
            if nodes>Codec.limits.nodes then Raise("codec-node-limit") end
            if depth>Codec.limits.depth then Raise("codec-depth-limit") end
            coroutine.yield()
            local tag=string.sub(text,position,position);position=position+1
            if tag=="z" then return nil
            elseif tag=="t" then return true
            elseif tag=="f" then return false
            elseif tag=="s" or tag=="n" then
                local size=Size(tag=="s" and Codec.limits.string or 32)
                if tag=="s" then size=size*2 end
                if position+size-1>length then Raise("codec-truncated") end
                local part=string.sub(text,position,position+size-1);position=position+size
                if tag=="n" then
                    if string.find(part,"[^0-9eE+%.%-]") then Raise("codec-number") end
                    local number=tonumber(part)
                    if not Finite(number) then Raise("codec-number") end
                    return number
                end
                if string.find(part,"[^0-9a-f]") then Raise("codec-hex") end
                return string.gsub(part,"..",function(pair) return string.char(tonumber(pair,16)) end)
            elseif tag=="m" then
                local count=Size(Codec.limits.nodes)
                local output,seen={},{}
                for index=1,count do
                    local key=Read(depth+1)
                    if not Key(key) or seen[key] then Raise("codec-key") end
                    seen[key]=true
                    local entry=Read(depth+1)
                    if entry==nil then Raise("codec-nil-value") end
                    output[key]=entry
                end
                return output
            end
            Raise("codec-tag")
        end
        local result=Read(0)
        if position~=length+1 then Raise("codec-trailing-data") end
        return result
    end)
end

local function Complete(job)
    while true do
        local done,value,failure=job:Step(512)
        if done then return value,failure end
    end
end
function Codec.Encode(value) return Complete(Codec.BeginEncode(value)) end
function Codec.Decode(text) return Complete(Codec.BeginDecode(text)) end
