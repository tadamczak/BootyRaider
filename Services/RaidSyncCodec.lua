local Raider = BootyRaider
Raider.Services = Raider.Services or {}
local Codec = {}
Raider.Services.RaidSyncCodec = Codec

-- A data grammar, never Lua source. Printable text uses quoted ASCII; reserved
-- channel bytes stay escaped. Jobs advance in bounded slices without depending
-- on the optional coroutine library. Stack frames are reused by nesting depth.
Codec.limits = {bytes=1048576,nodes=65536,depth=16,string=4096,references=512}
local unsafe = "[%z\001-\031\127-\255%%|~]"
local function HexByte(char) return string.format("%02x",string.byte(char)) end
local function QuoteByte(char) return "%"..HexByte(char) end
local function Unhex(pair) return string.char(tonumber(pair,16)) end
local function Count(values) return table.getn(values) end
local function Finite(value) return type(value)=="number" and value==value and value-value==0 end
local function Key(value)
    return type(value)=="string" or (Finite(value) and value>=0 and value<=9007199254740991 and value==math.floor(value))
end
local function Raise(reason) error(reason,0) end
local function Finish(job,value,failure)
    job.done=true;job.value=value;job.failure=failure
    job.state=nil;job.advance=nil
end
local function Slice(job,limit)
    for index=1,limit do
        job.work=index
        job.advance(job)
        if job.done then return end
    end
end
local function Step(job,limit)
    if job.done then return true,job.value,job.failure,0 end
    limit=math.max(1,math.min(512,math.floor(tonumber(limit) or 128)))
    local ok,failure=pcall(Slice,job,limit)
    if not ok then Finish(job,nil,tostring(failure)) end
    return job.done,job.value,job.failure,job.work
end
local function Job(state,advance) return {state=state,advance=advance,Step=Step,done=false} end
local function Node(state,depth)
    state.nodes=state.nodes+1
    if state.nodes>Codec.limits.nodes then Raise("codec-node-limit") end
    if depth>Codec.limits.depth then Raise("codec-depth-limit") end
end
local function Emit(state,text)
    state.bytes=state.bytes+string.len(text)
    if state.bytes>Codec.limits.bytes then Raise("codec-byte-limit") end
    table.insert(state.output,text)
end
local function EncodeString(state,entry)
    local size=string.len(entry)
    if size>Codec.limits.string then Raise("codec-string-limit") end
    state.stringBytes=state.stringBytes+size
    if state.stringBytes>Codec.limits.bytes then Raise("codec-string-byte-limit") end
    local reference=state.strings[entry] and ("r"..state.strings[entry]..":")
    -- At most512 entries: any repeated3-byte string already has
    -- a shorter reference than its smallest possible literal.
    if reference and string.len(reference)<size+3 then Emit(state,reference)
    else
        local quoted=string.gsub(entry,unsafe,QuoteByte)
        local prefix="q"..string.len(quoted)..":"
        local hexPrefix="s"..size..":"
        local literal
        if string.len(prefix)+string.len(quoted)<=string.len(hexPrefix)+size*2 then literal=prefix..quoted
        else literal=hexPrefix..string.gsub(entry,".",HexByte) end
        Emit(state,reference and string.len(reference)<string.len(literal) and reference or literal)
    end
    if not state.strings[entry] and state.stringCount<Codec.limits.references then
        state.stringCount=state.stringCount+1;state.strings[entry]=state.stringCount
    end
end
local function NextEntry(job)
    local state=job.state
    while state.top>0 do
        local frame=state.frames[state.top]
        if frame.index<=Count(frame.keys) then
            local key=frame.keys[frame.index]
            state.depth=frame.depth+1
            if frame.nextValue then
                state.entry=frame.value[key];frame.index=frame.index+1;frame.nextValue=false
            else state.entry=key;frame.nextValue=true end
            return
        end
        state.seen[frame.value]=nil;frame.value=nil;frame.keys=nil
        state.top=state.top-1
    end
    Finish(job,table.concat(state.output))
end
local function EncodeStep(job)
    local state=job.state
    local frame=state.frames[state.top]
    if frame and frame.collecting then
        local key=next(frame.value,frame.key)
        if key~=nil then
            if not Key(key) then Raise("codec-key") end
            table.insert(frame.keys,key);frame.key=key
            if Count(frame.keys)>Codec.limits.nodes then Raise("codec-node-limit") end
        else
            frame.collecting=false;frame.key=nil
            Emit(state,"m"..Count(frame.keys)..":");NextEntry(job)
        end
        return
    end
    local entry=state.entry
    Node(state,state.depth)
    local kind=type(entry)
    if kind=="nil" then Emit(state,"z")
    elseif kind=="boolean" then Emit(state,entry and "t" or "f")
    elseif kind=="number" then
        if not Finite(entry) then Raise("codec-number") end
        local text=string.format("%.17g",entry);Emit(state,"n"..string.len(text)..":"..text)
    elseif kind=="string" then EncodeString(state,entry)
    elseif kind=="table" then
        if getmetatable(entry) or state.seen[entry] then Raise("codec-non-plain-data") end
        state.seen[entry]=true;state.top=state.top+1
        frame=state.frames[state.top] or {};state.frames[state.top]=frame
        frame.value=entry;frame.depth=state.depth;frame.keys={};frame.index=1
        frame.key=nil;frame.collecting=true;frame.nextValue=false
        state.entry=nil
        return
    else Raise("codec-type") end
    NextEntry(job)
end
function Codec.BeginEncode(value)
    return Job({entry=value,depth=0,top=0,frames={},seen={},nodes=0,bytes=0,output={},
        strings={},stringCount=0,stringBytes=0},EncodeStep)
end

local function DecodeString(state,value,remember)
    local size=string.len(value)
    if size>Codec.limits.string then Raise("codec-string-limit") end
    state.stringBytes=state.stringBytes+size
    if state.stringBytes>Codec.limits.bytes then Raise("codec-string-byte-limit") end
    if remember and not state.stringIds[value] and state.stringCount<Codec.limits.references then
        state.stringCount=state.stringCount+1;state.strings[state.stringCount]=value;state.stringIds[value]=state.stringCount
    end
    return value
end
local function Size(state,maximum)
    local delimiter=string.find(state.text,":",state.position,true)
    if not delimiter or delimiter-state.position>7 or delimiter==state.position then Raise("codec-length") end
    local digits=string.sub(state.text,state.position,delimiter-1)
    if string.find(digits,"[^0-9]") then Raise("codec-length") end
    local size=tonumber(digits)
    if not size or size>maximum then Raise("codec-length-limit") end
    state.position=delimiter+1
    return size
end
local function Accept(job,value)
    local state=job.state
    while state.top>0 do
        local frame=state.frames[state.top]
        if frame.key==nil then
            if not Key(value) or frame.seen[value] then Raise("codec-key") end
            frame.seen[value]=true;frame.key=value
            return
        end
        if value==nil then Raise("codec-nil-value") end
        frame.value[frame.key]=value;frame.key=nil;frame.remaining=frame.remaining-1
        if frame.remaining>0 then return end
        value=frame.value;frame.value=nil;frame.seen=nil;state.top=state.top-1
    end
    if state.position~=state.length+1 then Raise("codec-trailing-data") end
    Finish(job,value)
end
local function DecodeStep(job)
    local state=job.state
    if not state.length then
        if type(state.text)~="string" or string.len(state.text)>Codec.limits.bytes then Raise("codec-byte-limit") end
        state.length=string.len(state.text)
    end
    Node(state,state.top)
    local tag=string.sub(state.text,state.position,state.position);state.position=state.position+1
    local value
    if tag=="z" then value=nil
    elseif tag=="t" then value=true
    elseif tag=="f" then value=false
    elseif tag=="r" then
        local index=Size(state,Codec.limits.references)
        if index<1 or not state.strings[index] then Raise("codec-reference") end
        value=DecodeString(state,state.strings[index],false)
    elseif tag=="s" or tag=="n" or tag=="q" then
        local size=Size(state,tag=="q" and Codec.limits.string*3 or tag=="s" and Codec.limits.string or 32)
        if tag=="s" then size=size*2 end
        if state.position+size-1>state.length then Raise("codec-truncated") end
        local part=string.sub(state.text,state.position,state.position+size-1);state.position=state.position+size
        if tag=="q" then
            if string.find(part,"[%z\001-\031\127-\255|~]") then Raise("codec-quote") end
            local remainder=string.gsub(part,"%%[0-9a-f][0-9a-f]","")
            if string.find(remainder,"%%") then Raise("codec-quote") end
            value=DecodeString(state,string.gsub(part,"%%([0-9a-f][0-9a-f])",Unhex),true)
        elseif tag=="n" then
            if string.find(part,"[^0-9eE+%.%-]") then Raise("codec-number") end
            value=tonumber(part)
            if not Finite(value) then Raise("codec-number") end
        else
            if string.find(part,"[^0-9a-f]") then Raise("codec-hex") end
            value=DecodeString(state,string.gsub(part,"..",Unhex),true)
        end
    elseif tag=="m" then
        local count=Size(state,Codec.limits.nodes)
        value={}
        if count>0 then
            state.top=state.top+1
            local frame=state.frames[state.top] or {};state.frames[state.top]=frame
            frame.value=value;frame.seen={};frame.remaining=count;frame.key=nil
            return
        end
    else Raise("codec-tag") end
    Accept(job,value)
end
function Codec.BeginDecode(text)
    return Job({text=text,position=1,nodes=0,top=0,frames={},strings={},stringIds={},stringCount=0,stringBytes=0},DecodeStep)
end

local function Complete(job)
    while true do
        local done,value,failure=job:Step(512)
        if done then return value,failure end
    end
end
function Codec.Encode(value) return Complete(Codec.BeginEncode(value)) end
function Codec.Decode(text) return Complete(Codec.BeginDecode(text)) end
