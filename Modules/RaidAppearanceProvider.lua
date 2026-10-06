local Raider = BootyRaider
local Appearance = {}
Raider.Modules.RaidAppearanceProvider = Appearance

-- These are appearance preferences, not a prefix-based slice of raid policy.
local definitions = {
    {key="ClassColors",type="checkbox",label="Class colors",default=true},
    {key="MemberTexture",type="choice",label="Member tile background",default="color"},
    {key="BackgroundColor",type="color",label="Member background color",default={0.025,0.025,0.025}},
    {key="TextColor",type="color",label="Member text color",default={1,1,1}},
    {key="HeaderTextColor",type="color",label="Header text color",default={1,0.82,0}},
    {key="HeaderBackgroundColor",type="color",label="Header background color",default={0.025,0.025,0.025}},
    {key="HeaderHoverTextColor",type="color",label="Header hover text color",default={1,1,1}},
    {key="HeaderTransparency",type="slider",label="Header transparency (%)",min=0,max=100,step=1,default=0},
    {key="TileTextSize",type="slider",label="Member text size",min=8,max=16,step=1,default=10},
    {key="HeaderTextSize",type="slider",label="Header text size",min=8,max=16,step=1,default=9},
    {key="ViewBackgroundTexture",type="choice",label="View background",default="color"},
    {key="ViewBackgroundColor",type="color",label="View background color",default={0.025,0.025,0.025}},
}
local choices = {{text="Game texture",value="game"},{text="Color",value="color"}}
local byKey, owners, busy = {}, {}, false
for _, field in ipairs(definitions) do byKey[field.key]=field end
local function Copy(value)
    if type(value)~="table" then return value end
    local copy={};for key,item in pairs(value) do copy[key]=Copy(item) end;return copy
end
local function Equal(first,second)
    if type(first)~="table" or type(second)~="table" then return first==second end
    for key,value in pairs(first) do if not Equal(value,second[key]) then return false end end
    for key in pairs(second) do if first[key]==nil then return false end end
    return true
end
local function Failure(code,message,rollback)
    return false,{code=code,message=tostring(message or code),rollbackError=rollback}
end
local function Message(value) return type(value)=="table" and tostring(value.message or value.code) or tostring(value) end
local function Combine(first,second) return first and second and (first.."; "..second) or first or second end
local function Defaults(owner)
    local values={}
    for _,field in ipairs(definitions) do values[field.key]=Copy(field.default) end
    if owner.native then values.MemberTexture="game";values.ViewBackgroundTexture="game";values.HeaderTransparency=100 end
    return values
end
local function Fields()
    local fields={}
    for _,field in ipairs(definitions) do
        local copy=Copy(field);copy.default=nil
        if copy.type=="choice" then copy.choices=Copy(choices) end
        table.insert(fields,copy)
    end
    return fields
end
local function Store()
    if type(BootyRaiderDB)~="table" then error("BootyRaider appearance data is not ready.") end
    return BootyRaiderDB
end
local function Values(owner,store)
    local values={}
    for _,field in ipairs(definitions) do values[field.key]=Copy(store[owner.prefix..field.key]) end
    return values
end
local function Validate(values)
    if type(values)~="table" then return Failure("invalid-values","Expected complete Raid appearance values.") end
    for key in pairs(values) do if not byKey[key] then return Failure("unknown-field","Unknown Raid appearance field: "..tostring(key)) end end
    local copy={}
    for _,field in ipairs(definitions) do
        local value=values[field.key]
        local valid=false
        if field.type=="color" then
            valid=type(value)=="table"
            if valid then
                for key in pairs(value) do if key~=1 and key~=2 and key~=3 then valid=false end end
                for index=1,3 do
                    local part=value[index]
                    if type(part)~="number" or part~=part or part<0 or part>1 then valid=false end
                end
            end
        elseif field.type=="checkbox" then valid=type(value)=="boolean"
        elseif field.type=="choice" then valid=value=="game" or value=="color"
        else valid=type(value)=="number" and value==value and value>=field.min and value<=field.max and value==math.floor(value) end
        if not valid then return Failure("invalid-field","Invalid Raid appearance field: "..field.key) end
        copy[field.key]=Copy(value)
    end
    return true,copy
end
local function Refresh(owner)
    local ok,result,detail=pcall(function()
        if not Raider.active then return true end
        local runtime=Raider.Runtime
        local view=owner.native and runtime.nativeRaidTab or runtime.views.raid
        if not view or not view.RefreshAppearance then return true end
        if view.IsVisible and not view:IsVisible() then return true end
        local frame=view.frame or view.page
        if frame and frame.IsVisible and not frame:IsVisible() then return true end
        return view:RefreshAppearance()
    end)
    if not ok then return false,tostring(result) end
    if result==false then return false,Message(detail) end
    return true
end
local function End(owner,session,reason,result)
    if owner.active==session then owner.active=nil end
    if session.onEnded then
        local ok,accepted,detail=pcall(session.onEnded,reason,Copy(result))
        if not ok or accepted==false then return false,Message(ok and detail or accepted) end
    end
    return true
end
local function Finish(owner,session,reason,refresh)
    owner.active=nil
    local restored,message=true,nil
    if refresh then restored,message=Refresh(owner) end
    local ready,result=pcall(function() return Values(owner,Store()) end)
    local notified,notification=End(owner,session,reason,ready and result or {code="appearance-unavailable",message=Message(result)})
    -- A listener refusal must not strand the old preview on screen when the
    -- caller stops before its ordinary settings refresh can run.
    if not notified and not refresh then restored,message=Refresh(owner) end
    if not restored or not notified then return Failure("cleanup-failed",message or notification,not restored and notification or nil) end
    return true,ready and result or nil
end
local function Check(owner,session)
    if not session or owner.active~=session then return Failure("stale-token","This Raid appearance edit has ended.") end
    if BootyRaiderDB~=session.store or not Equal(Values(owner,session.store),session.stored) then
        local ok,result=Finish(owner,session,"external-change",true)
        return Failure("external-change","Saved Raid appearance changed while editing.",not ok and Message(result) or nil)
    end
    return true
end
local function Session(owner,token) return type(token)=="table" and owner.active and owner.active.token==token and owner.active or nil end
local function Run(owner,callback,token)
    if busy then return Failure("busy","A Raid appearance operation is already in progress.") end
    busy=true
    local ok,result,detail=pcall(callback)
    local rollback
    if not ok then
        local session=Session(owner,token)
        if session then
            local cleaned,failure=Finish(owner,session,"error",true)
            if not cleaned then rollback=Message(failure) end
        end
    end
    busy=false
    if not ok then return Failure("appearance-error",result,rollback) end
    return result,detail
end
local function Rollback(owner,session,candidate)
    local failure
    if BootyRaiderDB~=session.store then failure="A later Raid appearance store was preserved."
    else
        for _,field in ipairs(definitions) do
            local key=owner.prefix..field.key
            if Equal(session.store[key],candidate[field.key]) then
                local ok,message=pcall(function() session.store[key]=Copy(session.stored[field.key]) end)
                if not ok then failure=Combine(failure,tostring(message)) end
            elseif not Equal(session.store[key],session.stored[field.key]) then failure=Combine(failure,"A later value of "..key.." was preserved.") end
        end
        if BootyRaiderDB~=session.store then failure=Combine(failure,"The Raid appearance store changed during rollback.") end
    end
    owner.active=nil
    local restored,message=Refresh(owner)
    if not restored then failure=Combine(failure,message) end
    return failure
end
local function CreateOwner(id,prefix,native)
    local owner={id=id,apiVersion=1,prefix=prefix,native=native}
    function owner.ReadAppearance(element)
        if element~=id then return Failure("unknown-element","Unknown Raid appearance element.") end
        local ok,values=pcall(function() return Values(owner,Store()) end)
        local valid,failure
        if ok then valid,failure=Validate(values) end
        return true,{available=ok and valid==true,reason=not ok and Message(values) or not valid and Message(failure) or nil,
            values=ok and Copy(owner.active and owner.active.values or values) or Defaults(owner),fields=Fields(),defaults=Defaults(owner)}
    end
    function owner.BeginAppearancePreview(element,onEnded)
        return Run(owner,function()
            if element~=id then return Failure("unknown-element","Unknown Raid appearance element.") end
            if owner.active or owner.pending then return Failure("busy","These Raid appearance preferences are already being edited.") end
            if onEnded~=nil and type(onEnded)~="function" then return Failure("invalid-callback","Expected an editing completion callback.") end
            local store=Store();local valid,values=Validate(Values(owner,store));if not valid then return valid,values end
            local token={};owner.active={token=token,store=store,stored=Copy(values),values=values,onEnded=onEnded}
            return true,token
        end)
    end
    function owner.PreviewAppearance(token,values)
        return Run(owner,function()
            local session=Session(owner,token);local checked,failure=Check(owner,session);if not checked then return checked,failure end
            local valid,candidate=Validate(values);if not valid then return valid,candidate end
            if Equal(candidate,session.values) then return true,Copy(candidate) end
            session.values=candidate
            local refreshed,message=Refresh(owner)
            if not refreshed then
                local cleaned,result=Finish(owner,session,"error",true)
                return Failure("preview-failed",message,not cleaned and Message(result) or nil)
            end
            checked,failure=Check(owner,session);if not checked then return checked,failure end
            return true,Copy(candidate)
        end,token)
    end
    function owner.ApplyAppearance(token)
        return Run(owner,function()
            local session=Session(owner,token);local checked,failure=Check(owner,session);if not checked then return checked,failure end
            local candidate=session.values
            local wrote,message=pcall(function()
                for _,field in ipairs(definitions) do
                    if BootyRaiderDB~=session.store then error("The Raid appearance store changed during application.") end
                    local key=prefix..field.key
                    if not Equal(session.store[key],session.stored[field.key]) then error("Raid appearance changed during application: "..key) end
                    session.store[key]=Copy(candidate[field.key])
                end
                if BootyRaiderDB~=session.store or not Equal(Values(owner,session.store),candidate) then error("Raid appearance store did not confirm the values.") end
            end)
            if not wrote then
                local rollback=Rollback(owner,session,candidate)
                local notified,notification=End(owner,session,"error",{code="commit-failed",message=tostring(message)})
                return Failure("commit-failed",message,Combine(rollback,not notified and notification or nil))
            end
            owner.active=nil
            local refreshed,message=Refresh(owner)
            if not refreshed then
                local rollback=Rollback(owner,session,candidate)
                local notified,notification=End(owner,session,"error",{code="apply-failed",message=message})
                return Failure("apply-failed",message,Combine(rollback,not notified and notification or nil))
            end
            local notified,notification=End(owner,session,"apply",candidate)
            if not notified then return Failure("notification-failed",notification,Rollback(owner,session,candidate)) end
            return true,Copy(candidate)
        end,token)
    end
    function owner.CancelAppearance(token)
        return Run(owner,function()
            local session=Session(owner,token);local checked,failure=Check(owner,session);if not checked then return checked,failure end
            return Finish(owner,session,"cancel",true)
        end,token)
    end
    function owner.ResetAppearance(token) return owner.PreviewAppearance(token,Defaults(owner)) end
    owners[id]=owner
    return owner
end
local main=CreateOwner("booty.raider.appearance.groups","raidGroup",false)
local native=CreateOwner("booty.raider.appearance.native-groups","nativeRaidGroup",true)
function Appearance.GetProvider(id) return owners[id] end
function Appearance.GetValue(prefix,suffix)
    local owner=prefix=="nativeRaidGroup" and native or main
    if byKey[suffix] and owner.active then return owner.active.values[suffix] end
    return BootyRaiderDB and BootyRaiderDB[prefix..suffix]
end
-- Main rendering must not acquire getGroupSettings: its presence is the
-- existing compact/native layout marker. This stable proxy changes reads only.
local effectiveMain=setmetatable({}, {__index=function(_,key)
    local suffix=string.sub(key,10)
    if string.sub(key,1,9)=="raidGroup" then return Appearance.GetValue("raidGroup",suffix) end
    return BootyRaiderDB and BootyRaiderDB[key]
end})
function Appearance.GetGroupSettings() return effectiveMain end
function Appearance.IsAppearanceKey(key)
    if type(key)~="string" then return false end
    return string.sub(key,1,9)=="raidGroup" and byKey[string.sub(key,10)]~=nil
        or string.sub(key,1,15)=="nativeRaidGroup" and byKey[string.sub(key,16)]~=nil
end
function Appearance.Refresh(id) local owner=owners[id];if not owner then return Failure("unknown-element","Unknown Raid appearance element.") end;return Refresh(owner) end
function Appearance.EndTarget(id,reason,refresh)
    local owner=owners[id]
    if not owner or not owner.active then return true end
    return Run(owner,function() return Finish(owner,owner.active,reason or "hide",refresh==true) end,owner.active.token)
end
function Appearance.EndAll(reason)
    for _,owner in ipairs({main,native}) do
        local ok,result=Appearance.EndTarget(owner.id,reason,true);if not ok then return ok,result end
    end
    return true
end
-- Profiles write ordinary fields directly inside the existing Settings batch.
-- Withdraw overlays first, but report their final durable values only after
-- those writes (or the profile rollback) have completed.
function Appearance.BeginExternalChange()
    if busy then return Failure("busy","A Raid appearance operation is already in progress.") end
    for _,owner in ipairs({main,native}) do
        if owner.active then owner.pending=owner.active;owner.active=nil end
    end
    return true
end
function Appearance.CompleteExternalChange(refresh)
    return Run(main,function()
        local failure
        for _,owner in ipairs({main,native}) do
            local session=owner.pending
            if session then
                owner.pending=nil
                local ok,result=Finish(owner,session,"external-change",refresh==true)
                if not ok then failure=Combine(failure,Message(result)) end
            end
        end
        if failure then return Failure("cleanup-failed",failure) end
        return true
    end)
end
function Appearance.OnSettingChanged(key)
    if not Appearance.IsAppearanceKey(key) then return true end
    local owner=string.sub(key,1,15)=="nativeRaidGroup" and native or main
    return Appearance.EndTarget(owner.id,"external-change",false)
end
