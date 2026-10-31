local Raider = BootyRaider
local Settings = {}
Raider.Settings = Settings
local groupLabels={Columns="Columns",ShowLevel="Show level",ShowLootMaster="Show LM icon",ShowRoleIcon="Show role icon",
    HideEmptyGroups="Hide empty groups",AutoAdjustVertically="Auto adjust groups vertically",AutoAdjustHorizontally="Auto adjust groups horizontally",
    AutoTileWidth="Adjust tile width to window",TileWidth="Member tile width",TileHeight="Member tile height",HeaderHeight="Group header height",
    Margin="Margin between groups",TileTextSize="Tile text size",HeaderTextSize="Header text size",HeaderTransparency="Header transparency (%)",
    MemberTexture="Member tile background",BorderTexture="Group border texture",ViewBackgroundTexture="View background",OddLightness="Alternate row lightness (%)",
    GroupPadding="Group padding",TileSpacing="Space between members",ColumnSpacing="Space between columns",FontStyle="Font",EmptySlotTexture="Empty member slots"}
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
    if updatePresets then field.rollbackKeys={"lmAutoLootExceptions"} end
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
local function PresetEditor(loot,path,kind,title,prefix,definitionKey)
    local definitions=Field(definitionKey,title,"text",path)
    definitions.profileOnly=true;definitions.onChange=nil;definitions.legacyKey="lmAutoLootPresetDefinitions"
    definitions.retiredKey="lmAutoLootPresetDefinitions"
    definitions.get=function(store) return loot.GetDefinitions(store,kind) end
    definitions.readLegacy=function(value)
        if value==nil then return nil end
        local valid,reason=loot.ReadCombinedDefinitions(value,kind);assert(valid,reason);return valid
    end
    definitions.set=function(value,store)
        local valid,reason=loot.ValidateDefinitions(value);assert(valid,reason);store[definitionKey]=valid
    end
    local draft={index=0,name="",items="",status=""}
    local refresh={}
    for _,suffix in ipairs({"Editor","Name","Items","Status"}) do refresh[prefix..suffix]=true end
    local function DraftField(suffix,label,fieldType,property)
        local field=Field(prefix..suffix,label,fieldType,path)
        field.profile=false;field.persist=false;field.onChange=nil;field.fullWidth=true
        if property then
            field.get=function() return draft[property] end
            field.set=function(value) draft[property]=value end
        end
        return field
    end
    local function Select(value,store)
        local entry=loot.GetDefinitions(store,kind)[value]
        draft.index=value;draft.source=entry;draft.name=entry and entry.name or ""
        draft.items=entry and entry.items or "";draft.status=""
    end
    local function Current(store)
        if draft.index~=0 and draft.source~=loot.GetDefinitions(store,kind)[draft.index] then
            draft.status="This preset changed. Select it again before saving.";return false
        end
        return true
    end
    DraftField("Heading",title,"heading")
    local selector=DraftField("Editor","Preset","choice","index")
    selector.getChoices=function(store) return loot.GetPresetChoices(store,kind,true) end
    selector.refreshKeys=refresh;selector.commitPending=true;selector.set=Select
    local name=DraftField("Name","Preset name","text","name");name.maxLength=64
    name.enabled=function() return draft.index==0 or draft.index>5 end
    local items=DraftField("Items",kind=="exclusions" and "Exclusions" or "Inclusions","text","items");items.maxLength=2048
    items.tooltip="Comma-separated item names or patterns. * matches any text. Exclusions always win."
    local function Action(suffix,label,callback)
        local action=DraftField(suffix,label,"action")
        action.fullWidth=nil;action.row=prefix.."Actions";action.refreshKeys=refresh;action.action=callback
        return action
    end
    Action("Add","Add",function(store) Select(0,store) end)
    Action("Save","Save",function(store)
        if not Current(store) then return end
        local ok,result=loot.SavePreset(store,kind,draft.index,draft.name,draft.items)
        if ok then
            Select(result,store);draft.status="Preset saved."
            if Raider.OnSettingChanged then Raider.OnSettingChanged(definitionKey) end
        else draft.status=result end
    end)
    local remove=Action("Delete","Delete",function(store)
        if not Current(store) then return end
        local ok,reason=loot.DeletePreset(store,kind,draft.index)
        if ok then
            Select(0,store);draft.status="Preset deleted."
            if Raider.OnSettingChanged then Raider.OnSettingChanged(definitionKey) end
        else draft.status=reason end
    end)
    remove.enabled=function() return draft.index>5 end
    DraftField("Status","","status","status")
end
local function AutoLootFields()
    local loot=Raider.Services.AutoLoot
    local path={"Addon UI","Raid","Loot Master Mode","LM Config"}
    local mode=Field("lmAutoLootMode","LM Auto Loot","choice",path,nil,nil,loot.ModeChoices)
    mode.rollbackKeys={"lmAutoLoot"}
    mode.readLegacy=function(value,old)
        if value~=nil then return value end
        if old.lmAutoLoot~=nil then return old.lmAutoLoot and "auto" or "off" end
    end
    local rarityOptions={}
    local rarityNames=loot.RarityNames or {"Poor","Common","Uncommon","Rare","Epic"}
    for index,name in ipairs(rarityNames) do
        local color
        if GetItemQualityColor then local r,g,b=GetItemQualityColor(index-1);color={r,g,b} end
        table.insert(rarityOptions,{text=name,value=name,color=color})
    end
    local rarity=Field("lmAutoLootRaritySelection","Auto Loot Rarity","multiselect",path,nil,nil,rarityOptions)
    rarity.profile=false;rarity.persist=false;rarity.onChange=nil
    rarity.get=function(store) return loot.MaskSelection(store.lmAutoLootRarities,rarityNames) end
    rarity.set=function(value) Raider.Database.SetSetting("lmAutoLootRarities",loot.SelectionMask(value,rarityNames)) end
    -- Retain the old per-bit profile keys without displaying separate checkboxes.
    for index,name in ipairs(rarityNames) do
        MaskCheckbox("lmAutoLootRarities",name,path,2^(index-1));fields[table.getn(fields)].profileOnly=true
    end
    for index,name in ipairs(loot.PresetNames) do
        MaskCheckbox("lmAutoLootPresets",name,path,2^(index-1),true);fields[table.getn(fields)].profileOnly=true
    end
    -- Full masks also preserve custom preset slots; legacy profiles still use the bit fields.
    for _,key in ipairs({"lmAutoLootPresets","lmAutoLootInclusionPresets"}) do Field(key,key,"text",path).profileOnly=true end
    Field("lmAutoLootExceptions","Auto loot exclusions","text",path).profileOnly=true
    Field("lmAutoLootInclusions","Auto loot inclusions","text",path).profileOnly=true
    PresetEditor(loot,path,"exclusions","Exclusion Presets","lmExclusionPreset","lmAutoLootExclusionPresetDefinitions")
    PresetEditor(loot,path,"inclusions","Inclusion Presets","lmInclusionPreset","lmAutoLootInclusionPresetDefinitions")
end
local function SplitLabel(value)
    return string.gsub(string.gsub(value,"(%l)(%u)","%1 %2"),"^Show ","Show ")
end
local function GroupFields(prefix,path)
    for _,definition in ipairs(Raider.Database.NativeRaidGroupFields) do
        local suffix,default=definition[1],definition[2]
        local section="Display"
        if string.find(suffix,"Color") or suffix=="ClassColors" or suffix=="OddLightness" then section="Member tile color"
        elseif string.find(suffix,"Texture") or suffix=="HeaderTransparency" or suffix=="FontStyle" then section="Appearance"
        elseif definition[3] then section="Size" end
        local fieldPath={path[1],path[2],path[3],path[4],section}
        if path[5] then fieldPath={path[1],path[2],path[3],path[4],path[5],section} end
        local kind=type(default)=="boolean" and "checkbox" or type(default)=="table" and "color" or definition[3] and "number" or "choice"
        local minimum,maximum=definition[3],definition[4]
        if prefix=="raidGroup" and suffix=="TileHeight" then minimum=14 end
        local options=suffix=="BorderTexture" and borderOptions or string.find(suffix,"Texture") and textureOptions or
            suffix=="FontStyle" and {{text="Game font",value="game"},{text="Booty font",value="booty"}} or nil
        local enabled
        if suffix=="AutoAdjustVertically" or suffix=="AutoAdjustHorizontally" then
            local hideKey=prefix.."HideEmptyGroups";enabled=function(db) return db[hideKey]==true end
        elseif suffix=="BorderSize" then local key=prefix.."ShowBorder";enabled=function(db) return db[key]==true end
        elseif suffix=="HoverBorderSize" then local key=prefix.."ShowHoverBorder";enabled=function(db) return db[key]==true end
        elseif suffix=="TileWidth" then local key=prefix.."AutoTileWidth";enabled=function(db) return db[key]~=true end end
        Field(prefix..suffix,groupLabels[suffix] or SplitLabel(suffix),kind,fieldPath,minimum,maximum,options,enabled)
    end
end
local function AddSectionResets()
    local sections,order={},{}
    for _,field in ipairs(fields) do
        local path=field.path or {}
        local eligible=path[1]=="Addon UI" and ((path[2]=="Raid" and path[3]=="Layout" and (path[4]=="Group view" or path[4]=="List view")) or
            (path[2]=="Raid Stats" or path[2]=="CSR") and path[3]=="Layout") or
            path[1]=="Game UI" and path[2]=="Raid" and path[3]=="Layout" or path[1]=="Addon Messages" and path[2]=="Loot Master"
        if eligible and field.persist~=false and not field.profileOnly then
            local id=table.concat(path,"/")
            if not sections[id] then sections[id]={path=path,keys={}};table.insert(order,id) end
            sections[id].keys[field.key]=true
        end
    end
    for index,id in ipairs(order) do
        local section=sections[id]
        local field=Field("resetLayoutSection"..index,"Reset","action",section.path)
        field.profile=false;field.persist=false;field.onChange=nil
        field.row=field.key;field.resetKeys=section.keys;field.resetCaption=section.path[table.getn(section.path)]
        field.tooltip="Reset only this section to defaults. Other settings and saved raid data are retained."
    end
end
function Settings.Get()
    local db=Raider.Database.Ensure()
    if not fields then
        fields={}
        Field("raidSyncEnabled","Synchronize raids and CSR with other officers","checkbox",{"General"},nil,nil,nil,nil,
            "Share raid changes with authorized guild officers. Only saved, ended raids appear in Raid Stats and contribute to CSR.")
        Field("raidLiveTrackingEnabled","Live tracking","checkbox",{"Addon UI","Raid","General"},nil,nil,nil,nil,
            "Refresh the physical raid roster while the Raid view or Loot Master window is visible. Session loot recording remains active until the session is paused or ended.")
        Field("raidHideSectionHeader","Hide section header","checkbox",{"Addon UI","Raid","General"})
        Field("raidClassColors","Use class colors","checkbox",{"Addon UI","Raid","General"})
        Field("raidStatsHideSectionHeader","Hide section header","checkbox",{"Addon UI","Raid Stats","General"})
        local statsColors=Field("raidStatsUseClassColors","Use class colors","checkbox",{"Addon UI","Raid Stats","General"})
        statsColors.legacyKey="raidStatsSingleUseClassColors"
        statsColors.readLegacy=function(value,old)
            if value~=nil then return value end
            if old.raidStatsSingleUseClassColors~=nil then return old.raidStatsSingleUseClassColors end
            return old.raidStatsMultiUseClassColors
        end
        local statsFilters={"Addon UI","Raid Stats","Layout","Filters"}
        for _,option in ipairs({{"raidStatsShowRaidFilter","Show Raid filter"},{"raidStatsShowSearchFilter","Show Search"},
            {"raidStatsShowFromFilter","Show From date"},{"raidStatsShowToFilter","Show To date"},{"raidStatsShowSelectAll","Show Select all"}}) do
            Field(option[1],option[2],"checkbox",statsFilters)
        end
        local statsPath={"Addon UI","Raid Stats","Layout","Raid List"}
        Field("raidStatsListShowId","Show Raid ID","checkbox",statsPath)
        Field("raidStatsListShowTime","Show Time","checkbox",statsPath)
        local singlePath={"Addon UI","Raid Stats","Layout","Single Raid Details"}
        Field("raidStatsSingleShowAttendance","Show Attendance","checkbox",singlePath)
        local multiPath={"Addon UI","Raid Stats","Layout","Multi Raid Details"}
        Field("raidStatsMultiShowAttendance","Show Attendance","checkbox",multiPath)
        Field("raidStatsMultiShowSR","Show SR","checkbox",multiPath)
        Field("raidStatsMultiShowLoot","Show Loot","checkbox",multiPath)
        Field("csrHideSectionHeader","Hide section header","checkbox",{"Addon UI","CSR","General"})
        Field("csrUseClassColors","Use class colors","checkbox",{"Addon UI","CSR","General"})
        Field("csrShowClassIcon","Show class icon","checkbox",{"Addon UI","CSR","Layout","General"})
        for _,option in ipairs({{"csrShowRaidFilter","Show Raid filter"},{"csrShowSearchFilter","Show Search"},
            {"csrShowGroupFilter","Show Group By"},{"csrShowArchivedFilter","Show archived CSR filter"},{"csrShowAwardedFilter","Show awarded CSR filter"}}) do
            Field(option[1],option[2],"checkbox",{"Addon UI","CSR","Layout","Filters"})
        end
        local chat=Field("chatActionLogs","Show action messages in chat","checkbox",{"General"})
        chat.get=function() return Raider.Database.GetSetting("chatActionLogs") end
        chat.set=function(value) return Raider.Database.SetSetting("chatActionLogs",value) end
        chat.onChange=nil
        local minimap=Field("hideMinimapIcon","Hide minimap icon","checkbox",{"General"})
        minimap.default=false;minimap.standaloneOnly=true
        GroupFields("raidGroup",{"Addon UI","Raid","Layout","Group view"})
        local nativeTab=Field("useBootyRaidTab","Use BootyRaider as default Raid tab","checkbox",{"Game UI","Raid","Interface"})
        nativeTab.legacyKey=Raider.Database.GetLegacyPreferenceKey(nativeTab.key)
        nativeTab.retiredKey=nativeTab.legacyKey
        local nativeLogo=Field("useBootyRaidLogo","Use Booty logo","checkbox",{"Game UI","Raid","Interface"},nil,nil,nil,function(store) return store.useBootyRaidTab==true end)
        nativeLogo.legacyKey=Raider.Database.GetLegacyPreferenceKey(nativeLogo.key)
        nativeLogo.retiredKey=nativeLogo.legacyKey
        GroupFields("nativeRaidGroup",{"Game UI","Raid","Layout","Group view"})
        local buttonStyle=Field("nativeRaidButtonStyle","Action button style","choice",{"Game UI","Raid","Interface"},nil,nil,
            {{text="Game texture",value="game"},{text="Booty red",value="booty"}})
        buttonStyle.profileOnly=true
        buttonStyle.readSaved=Raider.Database.NormalizeNativeRaidButtonStyle
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
        Field("lootMasterOpacity","Opacity","number",{"Addon UI","Raid","Layout","Loot Master Mode View"},0,100)
        Field("outOfFocusOpacity","Out of focus opacity (%)","number",{"Addon UI","Raid","Layout","Loot Master Mode View"},0,100)
        AutoLootFields()
        for _,definition in ipairs(Raider.Services.LootMessages.Definitions) do
            local path={"Addon Messages","Loot Master",definition.group,definition[2]}
            Field(definition.enabledKey,"Send "..definition[2],"checkbox",path)
            local enabledKey,messageKey=definition.enabledKey,definition[1]
            if definition.whisperKey then
                Field(definition.whisperKey,"Send in whisper","checkbox",path,nil,nil,nil,
                    function(store) return store[enabledKey]~=false end,"Send only to the player concerned, instead of raid chat.")
            end
            local message=Field(definition.textKey,definition[2],"text",path,nil,nil,nil,
                function(store) return store[enabledKey]~=false end,"Available variables: "..(definition[4]~="" and definition[4] or "none")..". Variables are optional.")
            message.preview=function(store,drafts) return Raider.Services.LootMessages.Preview(messageKey,store,drafts) end
        end
        AddSectionResets()
    end
    return {id="raider",label="Raid",db=db,fields=fields,onChange=Raider.OnSettingChanged}
end

-- Profiles reset declared preferences only. Checkbox masks own individual bits;
-- histories, session state and unrelated bits must survive a scoped reset.
function Settings.Reset(selected)
    local schema=Settings.Get()
    local db,presetsChanged=schema.db,false
    for _,field in ipairs(schema.fields) do
        if field.persist~=false and (not selected or selected[field.key]) then
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
