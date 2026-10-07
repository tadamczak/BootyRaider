local Raider = BootyRaider
local Runtime = Raider.Runtime
local function CreateRaid(parent,host) return Raider.Modules.RaidScreen.Create(parent,host) end
local function CreateStatistics(parent,host)
    Runtime.Initialize(host)
    local view=Raider.Modules.RaidStatistics.Create(parent,Raider.Database.GetRaidStatistics,Raider.Database.DeleteRaidStatistic,Raider.Database.UpdateRaidStatistic)
    view.frame=view.page
    Runtime.views.raidStatistics=view
    return view
end
local function CreateCSR(parent,host)
    Runtime.Initialize(host)
    local view=Raider.Modules.CSR.Create(parent,Raider.Database.GetRaidStatistics,Raider.Database.GetLootRules,Raider.Database.GetRosterData,
        function(id)
            Runtime.OpenView("raidStatistics")
            local statistics=Runtime.GetView("raidStatistics")
            if statistics and statistics.SelectRaid then statistics:SelectRaid(id) end
        end)
    view.frame=view.page
    Runtime.views.csr=view
    return view
end
function Raider.HandleCommand(text)
    if not Raider.active then Runtime.Print("BootyRaider is stopped. Resume it in Plugins or reload with the addon enabled.");return false end
    local _,_,command,arguments=string.find(tostring(text or ""),"^%s*(%S*)%s*(.-)%s*$")
    command=string.lower(command or "")
    if command=="roll" then
        if not Raider.Services.LootRollRequest.CanOrganize() then
            Runtime.Print("Only the Loot Master, raid leader or an assistant can start a roll.");return false
        end
        if arguments=="" then return Raider.Modules.MasterLootWindow.OpenNewRollDialog() end
        return Raider.Modules.MasterLootWindow.OpenLinkedItemRoll(arguments)
    elseif command=="stats" then return Runtime.OpenView("raidStatistics")
    elseif command=="csr" then return Runtime.OpenView("csr")
    elseif command=="settings" then if Runtime.host and Runtime.host.OpenSettings then return Runtime.host.OpenSettings() end
    elseif command=="" or command=="raid" then return Runtime.OpenView("raid") end
    Runtime.Print("Use /br, /br stats, /br csr, /br settings or /br roll [item] [players] [Tmog OS MS RC SR].")
    return false
end
local function QuickMenu(host)
    if host then Runtime.host=host end
    local function RaidView() return Runtime.GetView("raid") end
    local function Run(action,id)
        local view=RaidView()
        return view and view.quickActions and view.quickActions:Run(action,id)
    end
    local function Entry(text,icon,action,enabled,children)
        return {text=text,icon=icon,onClick=action,action=action,enabled=enabled~=false,children=children}
    end
    local view=RaidView()
    local quick=view and view.quickActions
    local state=quick and quick:GetState() or {}
    local leader,loot,snapshots={},{},{}
    if quick then
        for _,kind in ipairs({"leader","loot"}) do
            local target=kind=="leader" and leader or loot
            for _,tool in ipairs(quick:GetTools(kind)) do
                local id=tool.id
                table.insert(target,Entry(tool.text,tool.icon,function() return Run(id) end,tool.enabled))
            end
        end
        for _,snapshot in ipairs(quick:GetRecentSnapshots(5)) do
            local id=snapshot.id
            table.insert(snapshots,Entry(snapshot.text,"archive",function() return Run("load",id) end,snapshot.enabled))
        end
    end
    local raid={
        Entry(state.active and "Open Raid" or "New raid","start",function() return Run("primary") end,state.active or state.canStart),
        Entry("RL Tools","raid_tools",nil,state.canTools,leader),Entry("ML Tools","loot_tools",nil,state.canTools,loot),
        Entry("Test Raid","groups",function() return Run("test") end,state.canTest),
        Entry("Load Raid","archive",nil,state.canLoad and table.getn(snapshots)>0,snapshots),
        Entry("Save Raid","save",function() return Run("save") end,state.canSave),
        Entry("End Raid","quit",function() return Run("quit") end,state.canQuit),
    }
    local stats=Entry("Raid Stats","raid_stats",function() return Runtime.OpenView("raidStatistics") end)
    local entries={Entry("Raid","raids",function() return Runtime.OpenView("raid") end,true,raid)}
    if host and host.standalone then table.insert(entries,stats) else table.insert(raid,stats) end
    table.insert(entries,Entry("CSR","csr",function() return Runtime.OpenView("csr") end))
    if host and host.standalone then table.insert(entries,Entry("Settings","settings",function() return host.OpenSettings() end)) end
    return entries
end

local descriptor={id="raider",name="BootyRaider",label="Raid",namespace=Raider,version=Raider.version,apiVersion=1,OnHostReady=Runtime.Initialize,
    Initialize=Runtime.Initialize,Start=Runtime.Initialize,Stop=Runtime.Stop,IsBusy=Runtime.IsBusy,GetSettings=Raider.Settings.Get,
    OnActivationFailed=Runtime.OnActivationFailed,
    GetDatabase=Raider.Database.Ensure,GetQuickMenu=QuickMenu,ResetSettings=Raider.Settings.Reset,OnSettingChanged=Raider.OnSettingChanged,Command=Raider.HandleCommand,
    BeginSettingsBatch=Runtime.BeginSettingsBatch,EndSettingsBatch=Runtime.EndSettingsBatch,OnSettingsProfileApplied=Runtime.OnSettingsProfileApplied,
    GetGuildDirectoryDemand=function() return Raider.active and Raider.Services.Raid.IsInRaid() end,
    OnGuildDirectoryUpdated=Runtime.RefreshViews,
    views={{id="raid",label="Raid",icon="raids",create=CreateRaid},
        {id="raidStatistics",label="Raid Stats",icon="raid_stats",create=CreateStatistics},
        {id="csr",label="CSR",icon="csr",create=CreateCSR}},
}
Raider.descriptor=descriptor
BootyLib.RegisterProduct(descriptor)
SlashCmdList=SlashCmdList or {}
SLASH_BOOTYRAIDER1="/br";SLASH_BOOTYRAIDER2="/bootyraider";SlashCmdList.BOOTYRAIDER=Raider.HandleCommand
-- Suite can replace this alias with its own dispatcher; standalone preserves
-- the established roll command without requiring the old addon to be loaded.
if not SlashCmdList.MUKLA_OFFICER_SUITE and not SlashCmdList.BOOTYSUITE then
    SLASH_BOOTYRAIDERMOS1="/mos";SlashCmdList.BOOTYRAIDERMOS=Raider.HandleCommand
end
