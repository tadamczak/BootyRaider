local Raider = BootyRaider
local Settings = {}
Raider.Settings = Settings
local groupLabels={Columns="Columns",ShowLevel="Show level",ShowLootMaster="Show LM icon",ShowRoleIcon="Show role icon",
    HideEmptyGroups="Hide empty groups",AutoAdjustVertically="Auto adjust groups vertically",AutoAdjustHorizontally="Auto adjust groups horizontally",
    AutoTileWidth="Adjust tile width to window",TileWidth="Member tile width",TileHeight="Member tile height",HeaderHeight="Group header height",
    Margin="Margin between groups",TileTextSize="Tile text size",HeaderTextSize="Header text size",HeaderTransparency="Header transparency (%)",
    MemberTexture="Member tile background",BorderTexture="Group border texture",ViewBackgroundTexture="View background",OddLightness="Alternate row lightness (%)"}
local textureOptions={{text="Game texture",value="game"},{text="Color",value="color"}}
local borderOptions={{text="Game texture",value="game"},{text="Booty border",value="project"}}
local fields
local function Field(key,label,kind,path,minimum,maximum,options,enabled,tooltip)
    if kind=="number" then kind="slider" end
    local field={key=key,label=label,type=kind,path=path,min=minimum,max=maximum,step=kind=="slider" and 1 or nil,
        options=options,choices=options,enabled=enabled,tooltip=tooltip}
    field.onChange=function(value) Raider.Database.SetSetting(key,value) end
    table.insert(fields,field)
    return field
end
local function MaskCheckbox(key,label,path,bit,updatePresets)
    local field=Field(key..tostring(bit),label,"checkbox",path)
    field.durableKey,field.maskBit=key,bit
    field.legacyKey=key
    field.readLegacy=function(value)
        local mask=tonumber(value)
        if mask==nil then return nil end
        return math.mod(math.floor(mask/bit),2)==1
    end
    field.get=function(store)
        return math.mod(math.floor((tonumber(store[key]) or 0)/bit),2)==1
    end
    field.set=function(value,store)
        store=store or Raider.Database.Ensure()
        local mask=tonumber(store[key]) or 0
        local checked=math.mod(math.floor(mask/bit),2)==1
        if checked~=(value==true) then mask=mask+(value and bit or -bit) end
        if updatePresets then
            Raider.Database.SetSetting("lmAutoLootExceptions",Raider.Services.AutoLoot.ApplyPresets(store.lmAutoLootExceptions,mask))
        end
        Raider.Database.SetSetting(key,mask)
    end
    field.onChange=nil
end
local function SplitLabel(value)
    return string.gsub(string.gsub(value,"(%l)(%u)","%1 %2"),"^Show ","Show ")
end
local function GroupFields(prefix,path)
    for _,definition in ipairs(Raider.Database.NativeRaidGroupFields) do
        local suffix,default=definition[1],definition[2]
        local section="Display"
        if string.find(suffix,"Color") or suffix=="ClassColors" or suffix=="OddLightness" then section="Member tile color"
        elseif string.find(suffix,"Texture") or suffix=="HeaderTransparency" then section="Appearance"
        elseif definition[3] then section="Size" end
        local fieldPath={path[1],path[2],path[3],path[4],section}
        if path[5] then fieldPath={path[1],path[2],path[3],path[4],path[5],section} end
        local kind=type(default)=="boolean" and "checkbox" or type(default)=="table" and "color" or definition[3] and "number" or "choice"
        local minimum,maximum=definition[3],definition[4]
        if prefix=="raidGroup" and suffix=="TileHeight" then minimum=14 end
        local options=suffix=="BorderTexture" and borderOptions or string.find(suffix,"Texture") and textureOptions or nil
        local enabled
        if suffix=="AutoAdjustVertically" or suffix=="AutoAdjustHorizontally" then
            local hideKey=prefix.."HideEmptyGroups";enabled=function(db) return db[hideKey]==true end
        elseif suffix=="BorderSize" then local key=prefix.."ShowBorder";enabled=function(db) return db[key]==true end
        elseif suffix=="HoverBorderSize" then local key=prefix.."ShowHoverBorder";enabled=function(db) return db[key]==true end
        elseif suffix=="TileWidth" then local key=prefix.."AutoTileWidth";enabled=function(db) return db[key]~=true end end
        Field(prefix..suffix,groupLabels[suffix] or SplitLabel(suffix),kind,fieldPath,minimum,maximum,options,enabled)
    end
end
function Settings.Get()
    local db=Raider.Database.Ensure()
    if not fields then
        fields={}
        Field("raidLiveTrackingEnabled","Live tracking","checkbox",{"Addon UI","Raid","General"},nil,nil,nil,nil,
            "Refresh the physical raid roster while the Raid view or Loot Master window is visible. Session loot recording remains active until the session is paused or ended.")
        Field("raidHideSectionHeader","Hide section header","checkbox",{"Addon UI","Raid","General"})
        Field("raidClassColors","Use class colors","checkbox",{"Addon UI","Raid","General"})
        local chat=Field("chatActionLogs","Show action messages in chat","checkbox",{"Addon UI","Raid","General"})
        chat.get=function() return Raider.Database.GetSetting("chatActionLogs") end
        chat.set=function(value) return Raider.Database.SetSetting("chatActionLogs",value) end
        chat.onChange=nil
        Field("lootMasterOpacity","LM opacity (%)","number",{"Addon UI","Raid","Loot Master Mode"},0,100)
        Field("outOfFocusOpacity","Out of focus opacity (%)","number",{"Addon UI","Raid","Loot Master Mode"},0,100)
        GroupFields("raidGroup",{"Addon UI","Raid","Layout","Group view"})
        GroupFields("nativeRaidGroup",{"Game UI","Layout","Raid","Group view"})
        Field("useMOSRaidTab","Use BootyRaider as default Raid tab","checkbox",{"Game UI","Interface"})
        Field("useMOSRaidLogo","Use Booty logo","checkbox",{"Game UI","Interface"},nil,nil,nil,function()
            return Raider.Modules.RaidContentProvider.IsSelected()
        end)
        Field("nativeRaidButtonStyle","Action button style","choice",{"Game UI","Layout","Raid","Appearance"},nil,nil,
            {{text="Game texture",value="game"},{text="Booty red",value="mos"}})
        local listPath={"Addon UI","Raid","Layout","List view","Display"}
        for _,definition in ipairs({{"Name","Show name"},{"Level","Show level"},{"Status","Show status"},{"Group","Show group"},
            {"Class","Show class"},{"GuildRank","Show guild rank"},{"SR","Show SR"},{"LootMaster","Show LM icon"},{"RoleIcon","Show role icon"},
            {"Filters","Show filters"},{"Search","Show search"},{"HoverBorder","Show hover border"}}) do
            Field("raidListShow"..definition[1],definition[2],"checkbox",listPath)
        end
        Field("raidListRowWidth","Row width","number",{"Addon UI","Raid","Layout","List view","Size"},400,1200)
        Field("raidListRowHeight","Row height","number",{"Addon UI","Raid","Layout","List view","Size"},16,30)
        Field("raidListHoverBorderSize","Hover border size","number",{"Addon UI","Raid","Layout","List view","Size"},1,6,nil,
            function(store) return store.raidListShowHoverBorder==true end)
        for _,definition in ipairs({{"BackgroundColor","Background color"},{"TextColor","Main text color"},{"HoverColor","Hover color"},
            {"PressedColor","Pressed color"},{"HoverBorderColor","Hover border color"}}) do
            Field("raidList"..definition[1],definition[2],"color",{"Addon UI","Raid","Layout","List view","Member tile color"})
        end
        Field("raidListOddLightness","Alternate row lightness (%)","number",{"Addon UI","Raid","Layout","List view","Member tile color"},0,100)
        local mode=Field("lmAutoLootMode","Auto loot mode","choice",{"Addon UI","Raid","Loot Master Mode","Auto loot"},nil,nil,
            {{text="Off",value="off"},{text="Shift",value="shift"},{text="Auto",value="auto"}})
        mode.readLegacy=function(value,old)
            if value~=nil then return value end
            if old.lmAutoLoot~=nil then return old.lmAutoLoot and "auto" or "off" end
        end
        for index,label in ipairs({"Poor","Common","Uncommon","Rare","Epic"}) do
            MaskCheckbox("lmAutoLootRarities",label,{"Addon UI","Raid","Loot Master Mode","Auto loot","Item rarity"},2^(index-1))
        end
        for index,label in ipairs(Raider.Services.AutoLoot.PresetNames) do
            MaskCheckbox("lmAutoLootPresets",label,{"Addon UI","Raid","Loot Master Mode","Auto loot","Raid presets"},2^(index-1),true)
        end
        Field("lmAutoLootExceptions","Auto loot exceptions","text",{"Addon UI","Raid","Loot Master Mode","Auto loot"})
        Field("lmAutoLootInclusions","Auto loot inclusions","text",{"Addon UI","Raid","Loot Master Mode","Auto loot"})
        for _,definition in ipairs(Raider.Services.LootMessages.Definitions) do
            Field(definition.enabledKey,"Send "..definition[2],"checkbox",{"Addon Messages","Loot Master",definition[2]})
            local enabledKey=definition.enabledKey
            Field(definition.textKey,definition[2],"text",{"Addon Messages","Loot Master",definition[2]},nil,nil,nil,
                function(store) return store[enabledKey]~=false end,"Available variables: "..(definition[4]~="" and definition[4] or "none")..". Variables are optional.")
        end
    end
    local visibleFields=fields
    if Raider.Modules.RaidContentProvider.IsControlled() then
        visibleFields={}
        for _,field in ipairs(fields) do
            if field.key=="useMOSRaidTab" then
                table.insert(visibleFields,{key="useMOSRaidTab",label="Raid tab content (BootyUI)",type="action",text="Open BootyUI",
                    path={"Game UI","Interface"},profile=false,persist=false,action=Raider.Modules.RaidContentProvider.OpenSelection,
                    tooltip="Choose the native Raid tab or BootyRaider in BootyUI. The Raider fallback is retained for use after BootyUI stops."})
            else table.insert(visibleFields,field) end
        end
    end
    return {id="raider",label="Raid",db=db,fields=visibleFields,onChange=Raider.OnSettingChanged}
end

-- Profiles reset declared preferences only. Checkbox masks own individual bits;
-- histories, session state and unrelated bits must survive a scoped reset.
local function ResetPreferences(selected)
    local schema=Settings.Get()
    local db,presetsChanged=schema.db,false
    for _,field in ipairs(schema.fields) do
        if field.profile~=false and field.type~="action" and (not selected or selected[field.key]) then
            if field.maskBit then
                local key,bit=field.durableKey,field.maskBit
                local mask=tonumber(db[key]) or 0
                local defaults=key=="lmAutoLootRarities" and 7 or 0
                local current=math.mod(math.floor(mask/bit),2)==1
                local wanted=math.mod(math.floor(defaults/bit),2)==1
                if current~=wanted then db[key]=mask+(wanted and bit or -bit) end
                if key=="lmAutoLootPresets" then presetsChanged=true end
            elseif field.key=="chatActionLogs" then
                Raider.Database.SetSetting(field.key,nil)
            elseif field.key=="lmAutoLootMode" then
                -- The obsolete legacy boolean is not a current preference.
                db.lmAutoLootMode,db.lmAutoLoot="off",false
            else db[field.key]=nil end
        end
    end
    Raider.Database.Ensure()
    if presetsChanged then
        db.lmAutoLootExceptions=Raider.Services.AutoLoot.ApplyPresets(db.lmAutoLootExceptions,db.lmAutoLootPresets)
    end
    return true
end
function Settings.Reset(selected)
    local appearance=Raider.Modules.RaidAppearanceProvider
    if not appearance then return ResetPreferences(selected) end
    local begun,failure=appearance.BeginExternalChange();if not begun then error(failure.message) end
    local ok,result=pcall(ResetPreferences,selected)
    local ended,detail=true,nil
    if (Raider.Runtime.settingsBatchDepth or 0)==0 then ended,detail=appearance.CompleteExternalChange(true) end
    if not ok then error(tostring(result)..(not ended and ("; appearance cleanup: "..detail.message) or "")) end
    if not ended then error(detail.message) end
    return result
end
