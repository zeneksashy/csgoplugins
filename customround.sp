#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#define MODE_NAME_SIZE 32
#define MODE_EXECS_SIZE 64
#pragma newdecls required
#define MODES_CONFIG_PATH "configs/modes/modes.cfg"

enum CustomMode
{
    PrimaryWeaponMode, //0
    SecondaryWeaponMode, //1
    NoShootingMode = 3 , //3
    CustomConfigMode, //4
    Default // 5
}

int votes = 0;
bool customHealthRound = false;
bool customNoScopeRound = false;
bool customRoundFinishing = false;
bool customModeTurnedOn = false;
bool customRoundStarted = false;
int currentModeIndex = 0;
int voteModeIndex = 0;
CustomMode _mode;
bool voteInProgress = false;
ConVar g_voteMaxPlayers;
ConVar g_warmupRounds;
ConVar g_weaponRestrictPluginEnabled;
//ConVar g_allowDrop;
int warmupRounds;
int m_flNextSecondaryAttack = -1;
int hp = 100;
//todo change that into working array of structures
char g_modeName[MODE_NAME_SIZE][MODE_NAME_SIZE];
CustomMode g_modeType[MODE_NAME_SIZE];
char g_execs[MODE_NAME_SIZE][MODE_EXECS_SIZE][MODE_EXECS_SIZE];
char g_serverExecs [MODE_NAME_SIZE][MODE_EXECS_SIZE][MODE_EXECS_SIZE];

char g_warmupStartActions [MODE_NAME_SIZE][MODE_EXECS_SIZE];
char g_warmupEndActions [MODE_NAME_SIZE][MODE_EXECS_SIZE];

public Plugin myinfo = 
{
    name = "Custom Round plugin",
    author = "Zenek",
    description = "Plugin allows to call vote to make next round use custom settings",
    version = "1.8",
    url = "https://github.com/zeneksashy/csgoplugins "
};

stock bool IsValidClient(int client)
{
    if (client <= 0)return false;
    if (client > MaxClients)return false;
    if (!IsClientConnected(client))return false;
    if (IsClientReplay(client))return false;
    if (IsFakeClient(client))return false;
    if (IsClientSourceTV(client))return false;
    return IsClientInGame(client);
}


void read_config()
{
    char configPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configPath, sizeof(configPath), MODES_CONFIG_PATH);


    KeyValues kv = CreateKeyValues("Modes");
    FileToKeyValues(kv, configPath);
    char name[MODE_NAME_SIZE];
    KvGetSectionName(kv, name, sizeof(name));
    PrintToServer("Loading %s", name);
    if(StrEqual(name,"Warmup"))
    {
        if(KvGotoFirstSubKey(kv))
        {
            KvGetSectionName(kv, name, sizeof(name));
            if(StrEqual(name,"Start",false))
            {
                for(int i =0; i < MODE_NAME_SIZE; ++i)
                {
                    char buffer[3];
                    char exec[MODE_EXECS_SIZE];
                    IntToString(i,buffer,sizeof(buffer));
                    KvGetString(kv,buffer,exec,sizeof(exec));
                    g_warmupStartActions[i] = exec;
                }
                KvGotoNextKey(kv);
            }
            KvGetSectionName(kv, name, sizeof(name));
            if(StrEqual(name,"End",false))
            {
                for(int i =0; i < MODE_NAME_SIZE; ++i)
                {
                    char buffer[3];
                    char exec[MODE_EXECS_SIZE];
                    IntToString(i,buffer,sizeof(buffer));
                    KvGetString(kv,buffer,exec,sizeof(exec));
                    g_warmupEndActions[i] = exec;
                }
            }
        }
        KvRewind(kv);
    }
    KvGotoNextKey(kv);
    KvGetSectionName(kv, name, sizeof(name));
    if (!StrEqual(name,"Modes") || !KvGotoFirstSubKey(kv))
    {
        
        PrintToServer("Something wrong, section name: %s", name);
        SetFailState("CFG File content is wrong: %s", configPath);
        CloseHandle(kv);
        return;
    }
    int counter = 0;
    do
    {
        KvGetSectionName(kv, name, sizeof(name));
        g_modeName[counter] = name;
        g_modeType[counter] = KvGetNum(kv,"Type");
        if(KvGotoFirstSubKey(kv))
        {
            bool isClientExec = false;
            KvGetSectionName(kv, name, sizeof(name));
            if(StrEqual(name,"Client Execs"))
            {
                isClientExec = true;
            }
            for(int i =0; i < MODE_NAME_SIZE; ++i)
            {
                char buffer[3];
                char exec[MODE_EXECS_SIZE];
                IntToString(i,buffer,sizeof(buffer));
                KvGetString(kv,buffer,exec,sizeof(exec));
                if(isClientExec)
                {
                    g_execs[counter][i] = exec;
                }
                else
                {
                    g_serverExecs[counter][i] = exec;
                }
            }
            isClientExec = !isClientExec;
            if(KvGotoNextKey(kv))
            {
                for(int i = 0; i < MODE_NAME_SIZE; ++i)
                {
                    char buffer[3];
                    char exec[MODE_EXECS_SIZE];
                    IntToString(i,buffer,sizeof(buffer));
                    KvGetString(kv,buffer,exec,sizeof(exec));
                    if(isClientExec)
                    {
                        g_execs[counter][i] = exec;
                    }
                    else
                    {
                        g_serverExecs[counter][i] = exec;
                    }
                }
            }

            KvGoBack(kv);
        }
        
        ++counter;
    }while (KvGotoNextKey(kv));

    CloseHandle(kv);
}


public void OnPluginStart()
{
    read_config();
    m_flNextSecondaryAttack = FindSendPropInfo("CBaseCombatWeapon", "m_flNextSecondaryAttack");
    PrintToServer("Hello world!");
    //RegConsoleCmd("custom_reload", ReloadPlugin);
    AddCommandListener(ChatListener, "say");
    AddCommandListener(ChatListener, "say2");
    AddCommandListener(ChatListener, "say_team");
    RegAdminCmd("sm_health", Command_Health, ADMFLAG_GENERIC, "Sets a players HP. Usage: sm_health <ammount>");
    RegAdminCmd("sm_noscope",Command_NoScope, ADMFLAG_GENERIC, "Sets current round to no scope: sm_noscope <0|1> (0 for scope available, 1 for only noscope>");
    HookEventEx("entity_visible", entity_visible)
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("round_prestart",Event_RoundStart);
    HookEvent("round_end",Event_RoundEnd);
    HookEvent("player_team",Event_PlayerJoinedTeam);

    _mode = Default;

    g_voteMaxPlayers = CreateConVar("maxplayers_for_vote","9","Sets a vote ratio");
    g_warmupRounds = CreateConVar("warmup_rounds","4","Sets a warmup rounds count");
    g_weaponRestrictPluginEnabled = CreateConVar("weapon_restrict_disable", "1", "Wheater weapon restrict plugin should be unloaded on custom rounds");
   // g_allowDrop = CreateConVar("custom_round_allow_drop", 1, "Wheater allow player to drop weapons or not");

    warmupRounds = g_warmupRounds.IntValue;
    AutoExecConfig(true);
}

public void OnMapStart()
{
    warmupRounds = g_warmupRounds.IntValue;
    if(warmupRounds > 0)
        WarmupStartOperations();
    votes = 0;
    customModeTurnedOn = false;
    customRoundStarted = false;
    voteInProgress = false;
    currentModeIndex = 0;
    _mode = Default;
    
    
}
public void OnMapEnd()
{
    
}

public Action CS_OnBuyCommand(int iClient, const char[] chWeapon)
{
    if(_mode == NoShootingMode)
        return Plugin_Handled;
    if(_mode < NoShootingMode && customRoundStarted)
    {
        const int array_size = 13;
        char allowed[array_size][] = {"vest",
                                  "vesthelm",
                                  "taser",
                                  "defuser",
                                  "heavyarmor",
                                  "molotov",
                                  "incgrenade",
                                  "decoy",
                                  "flashbang",
                                  "hegrenade",
                                  "smokegrenade",
                                  "kevlar",
                                  "assaultsuit"};
        for(int i=0;i<array_size;++i)
            if(StrEqual(chWeapon, allowed[i]))
            {
                return Plugin_Continue;
            }
        return Plugin_Handled;
    }
    return Plugin_Continue;
} 

public void Event_PlayerJoinedTeam(Event event, const char[] name, bool dontBroadcast)
{
    // if(customRoundStarted)
    // {
        // PlayerCheckAndUpdateWeaponOperation(GetClientOfUserId(event.GetInt("userid")));
    // }
    for (int i = 1; i <= MaxClients; i++) if (IsClientInGame(i)) OnClientPutInServer(i);
}
public Action Event_PlayerSpawn(Event hEvent, const char[] chName, bool bDontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
    if (IsClientInGame(client))
    {
        SDKUnhook(client, SDKHook_PreThink, OnPreThink);
    }
        
    if(customRoundStarted)
    {
        if(customNoScopeRound)
        {
            if (IsClientInGame(client))
            {
                SDKHook(client, SDKHook_PreThink, OnPreThink);
            }
        }
        if(customHealthRound)
        {
            
            if (IsClientInGame(client))
            {
                SetHp(client);
            }
        }
        CreateTimer(0.2, TimerPlayerSpawn, GetClientOfUserId(hEvent.GetInt("userid")), TIMER_FLAG_NO_MAPCHANGE);
    }
}
public Action TimerPlayerSpawn(Handle timer, int client)
{
    PlayerCheckAndUpdateWeaponOperation(client);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    customRoundFinishing = false;
    PrintToServer("New round started");
    if(warmupRounds)
    {
        currentModeIndex = warmupRounds;
        _mode = g_modeType[currentModeIndex];
        PrintToChatAll("╔════════════════════════════════════════╗");
        PrintToChatAll("Warmup Round Started, %d Warmup Rounds Left",warmupRounds-1);
        PrintToChatAll("╚════════════════════════════════════════╝");
        PrintToServer("%d Warmup rounds left",warmupRounds);
        customModeTurnedOn = true;
    }
    if(customModeTurnedOn)
    {
        customRoundStarted =true;
        voteInProgress = false;
        customModeTurnedOn = false;
        // if(g_allowDrop.IntValue == 1)
        // {
            // ServerCommand("mp_death_drop_gun 0");
        // }
        //ClientOperations();
        ServerOperations();
        if(g_weaponRestrictPluginEnabled.IntValue == 1)
        {
             ServerCommand("sm plugins unload weapon_restrict")
        }
        PrintToChatAll("╔════════════════════════════════════════╗");
        PrintToChatAll("%s Custom Round Started",g_modeName[currentModeIndex]);
        PrintToServer("%s Custom Round Started",g_modeName[currentModeIndex]);
        PrintToChatAll("╚════════════════════════════════════════╝");
        ServerCommand("sm_csay %s Custom Round Started",g_modeName[currentModeIndex]);
    }
}

public void entity_visible(Event event, const char[] name, bool dontBroadcast)
{

    if(customRoundFinishing)
    {
        char buffer[30];
        GetEventString(event, "classname", buffer, sizeof(buffer));

        if(StrContains(buffer, "weapon_", false) == 0)
        {
            int ref = EntIndexToEntRef(GetEventInt(event, "subject"));

            if(ref != 0 && GetEntProp(ref, Prop_Send, "m_iState") == 0 )
            {
                AcceptEntityInput(ref, "Kill");
            }
        }
    }
} 

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if(warmupRounds)
    {
        --warmupRounds;
        if(warmupRounds == 0)
        {
            PrintToChatAll("Restarting the game");
            WarmupEndOperations();
            ServerCommand("mp_restartgame 1");
        }
    }
    if(customRoundStarted && !customModeTurnedOn)
    {
        customHealthRound = false;
        customNoScopeRound = false;
        customRoundFinishing = true;
        customRoundStarted = false;
        PrintToChatAll("Custom round finished");
        customModeTurnedOn = false;
        RevertServerOperations();
        RevertClientOperations();
        if(g_weaponRestrictPluginEnabled.IntValue == 1)
        {
             ServerCommand("sm plugins load weapon_restrict")
        }
        _mode = Default;
    }
}

void ServerOperations()
{
    for(int j = 0; j < MODE_EXECS_SIZE; ++j)
        ServerCommand(g_serverExecs[currentModeIndex][j]);
}

void RevertServerOperations()
{
    for(int j = 0; j< MODE_EXECS_SIZE; ++j)
    {
        char buffer[MODE_EXECS_SIZE];
        SplitString(g_serverExecs[currentModeIndex][j]," ",buffer,MODE_EXECS_SIZE)
        if(!StrEqual(buffer, ""))
        {
            ConVar command = FindConVar(buffer);
            if(command)
                ResetConVar(command);
        }
        
    }
}

stock void ClientOperations()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        PlayerCheckAndUpdateWeaponOperation(i);
    }
}

void RevertClientOperations()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i))
        {
            if(IsPlayerAlive(i))
            {
                RemoveWeapons(i,3);
            }
        }
    }
}

void RemoveWeapons(int client, int weapons)
{
    if(weapons>=3)
    {
        for(int index = 0; index < GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons"); index++) 
        {
            int item = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", index); 
            if(item != -1) 
            { 
                RemovePlayerItem(client, item);
                AcceptEntityInput(item, "Kill");
            } 
        }
    }
    else
        for (int j = 0; j <= weapons; j++)
        {
            int index = GetPlayerWeaponSlot(client,j);
            if(index != -1)
            {
                RemovePlayerItem(client,index);
                AcceptEntityInput(index, "Kill");
            }
        }

    // Remove grandaes
    if (weapons>=3)
    {
        
        int grenadeOffsets[] = {15, 17, 16, 14, 18, 17};
        //while(RemoveGranades(client)){}
        for(int i = 0; i < sizeof(grenadeOffsets); i++)
            SetEntProp(client, Prop_Send, "m_iAmmo", 0, _, grenadeOffsets[i]);
    }
}

stock bool RemoveGranades(int client)
{
    int iEntity = GetPlayerWeaponSlot(client, 3);
    if(IsValidEdict(iEntity)) {
        RemovePlayerItem(client, iEntity);
        AcceptEntityInput(iEntity, "Kill");
        return true;
    }
    return false;
} 

void PlayerCheckAndUpdateWeaponOperation(int i)
{
    if(IsValidClient(i))
    {
        if(IsPlayerAlive(i))
        {
            if(_mode < Default)
            {
                SinglePlayerWeaponOperations(i);
            }
        }
    }
}

void SinglePlayerWeaponOperations(int i)
{
    if(_mode <CustomConfigMode)
        RemoveWeapons(i,_mode);
    for(int j = 0; j < MODE_EXECS_SIZE; ++j)
        GivePlayerItem(i,g_execs[currentModeIndex][j]);
}

public Action ChatListener(int client, const char[] command, int args)
{
    char msg[128];
    GetCmdArgString(msg, sizeof(msg));
    StripQuotes(msg);
    if(StrEqual(msg, "!custom"))
    {
        return StartVoteMenu(client,args);
    }
    return Plugin_Continue;
}

void ChangeMode(CustomMode newMode,int modeIndex)
{
    PrintToChatAll("Votes %d's out of %d", votes, GetClientCount());
    if((GetClientCount()/2) < votes)
    {
        voteInProgress = true;
        customModeTurnedOn = true;
        currentModeIndex = modeIndex;
        _mode = newMode;
    }
    votes = 0;
}

public int MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    /* If an option was selected, tell the client about the item. */
    voteInProgress = true;
    if (action == MenuAction_Select)
    {
        char info[32];
        bool found = menu.GetItem(param2, info, sizeof(info));
        PrintToConsole(param1, "You selected item: %d (found? %d info: %s)", param2, found, info);
        if(StrEqual(info, "yes"))
            ++votes;
    }
    /* If the menu was cancelled, print a message to the server about it. */
    else if (action == MenuAction_Cancel)
    {
        PrintToServer("Client %d's menu was cancelled.  Reason: %d", param1, param2);
    }
    /* If the menu has ended, destroy it */
    else if (action == MenuAction_End)
    {
        voteInProgress = false;
        delete menu;
        ChangeMode(g_modeType[voteModeIndex],voteModeIndex);
    }
}

public int ClientMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
/* If an option was selected, tell the client about the item. */
    if (action == MenuAction_Select)
    {
        char info[32];
        bool found = menu.GetItem(param2, info, sizeof(info));
        PrintToConsole(param1, "You selected item: %d (found? %d info: %s)", param2, found, info);
        voteModeIndex = param2;
        StartVote(0,0);
    }
    /* If the menu was cancelled, print a message to the server about it. */
    else if (action == MenuAction_Cancel)
    {
        PrintToServer("Client %d's menu was cancelled.  Reason: %d", param1, param2);

    }
    /* If the menu has ended, destroy it */
    else if (action == MenuAction_End)
    {
        delete menu;
    }
}

public Action ReloadPlugin(int client, int args)
{
    if(!voteInProgress && warmupRounds <= 0 && !customRoundStarted)
        ServerCommand("sm plugins reload custom_round");
}

public Action StartVoteMenu(int client, int args)
{
    if(warmupRounds > 0)
    {
        PrintToChat(client, "Can't start vote during warmup round");
        return Plugin_Continue;
    }
    if(voteInProgress)
    {
        PrintToChat(client, "Can't start vote, another vote is in progress, try next round");
        return Plugin_Continue;
    }
    //Todo if admin calling then votes doesn't matter
    if(GetClientCount() > g_voteMaxPlayers.IntValue)
    {
        PrintToChat(client, "Can't start vote, too many players on server.\nMax Players %d",g_voteMaxPlayers.IntValue);
        return Plugin_Continue;
    }
    Menu menu = new Menu(ClientMenuHandler);
    menu.SetTitle("Start vote to play next round with custom settings ");
    for(int i = 0;i < MODE_NAME_SIZE;++i)
    {
        if(strcmp(g_modeName[i],"") != 0)
            menu.AddItem(g_modeName[i], g_modeName[i]);
    }

    menu.ExitButton = true;
    menu.Display(client, 20);

    return Plugin_Handled;
}

public Action StartVote(int client, int args)
{
    Menu menu = new Menu(MenuHandler);
    menu.SetTitle("Do you want to play next round with custom settings? %s",g_modeName[voteModeIndex]);
    menu.AddItem("yes", "Yes");
    menu.AddItem("no", "No");
    menu.ExitButton = false;
    menu.DisplayVoteToAll(20);
 
    return Plugin_Handled;
}

void WarmupStartOperations()
{
     for(int i =0; i < MODE_NAME_SIZE; ++i)
    {
        ServerCommand(g_warmupStartActions[i]);
    }
}
void WarmupEndOperations()
{
    for(int i =0; i < MODE_NAME_SIZE; ++i)
    {
        ServerCommand(g_warmupEndActions[i]);
    }
}
public Action Command_Health(int client, int args)
{
    if(args != 1)
    {
        ReplyToCommand(client, "Error - Usage: sm_health <ammount>");
        return Plugin_Handled;
    }
    customHealthRound = true;
    char buff[5];
    GetCmdArg(1, buff, sizeof(buff));
    hp = StringToInt(buff);
    for (int i = 1; i <= MaxClients; i++)
    {
        SetHp(i);
    }
    return Plugin_Handled;
}

stock void SetHp(int client)
{
    if(IsValidClient(client))
    {
        char buffer[64];
        GetClientName(client,buffer,sizeof(buffer));
        PrintToServer("Set %d hp for %s",hp,buffer);
        SetEntityHealth(client, hp);
    }
}
public Action Command_NoScope(int client, int args)
{
    if(args != 1)
    {
        ReplyToCommand(client, "Error - Usage: sm_noscope <0|1 >");
        return Plugin_Handled;
    }
    char buff[5];
    GetCmdArg(1, buff, sizeof(buff));
    
    int noscope = StringToInt(buff);
    if(noscope)
    {
        customNoScopeRound = true;
    }
    else
        customNoScopeRound = false;
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if(IsValidClient(i))
        {
            if(customNoScopeRound)
                SDKHook(i, SDKHook_PreThink, OnPreThink);
            else
                SDKUnhook(i, SDKHook_PreThink, OnPreThink);
        }

    }
    return Plugin_Handled;
}

public Action OnPreThink(int client)
{
    if(IsValidClient(client))
        if(IsPlayerAlive(client))
        {
            SetNoScope(GetPlayerWeaponSlot(client, 0));
        }
    return Plugin_Handled;
}

stock void SetNoScope(int weapon)
{
    if (IsValidEdict(weapon))
    {
        char classname[MAX_NAME_LENGTH];
        if (GetEdictClassname(weapon, classname, sizeof(classname))
         || StrEqual(classname[7], "ssg08") || StrEqual(classname[7], "aug")
         || StrEqual(classname[7], "sg550") || StrEqual(classname[7], "sg552")
         || StrEqual(classname[7], "sg556") || StrEqual(classname[7], "awp")
         || StrEqual(classname[7], "scar20") || StrEqual(classname[7], "g3sg1"))
        {
                SetEntDataFloat(weapon, m_flNextSecondaryAttack, GetGameTime() + 1.0);
        }
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUse);
}

public Action Hook_WeaponCanUse(int client, int weapon)
{
    char classname[64];
    GetEntityClassname(weapon, classname, sizeof classname);
    
    if ((StrEqual(classname, "weapon_melee") || StrEqual(classname, "weapon_fists")) && !(HasWeapon(client, "weapon_melee") || HasWeapon(client, "weapon_knife")))
        EquipPlayerWeapon(client, weapon);
}


public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if(!customNoScopeRound)
        return Plugin_Continue

    //Client is not valid
    if (!IsValidClient(client) || !IsPlayerAlive(client))
    {
        return Plugin_Continue;
    }

    // if (g_iTeam < 4 && g_iTeam != GetClientTeam(client))
    // {
        // return Plugin_Continue;
    // }

    //Attempting to use right click
    if (buttons & IN_ATTACK2)
    {
        char buffer[128];
        
        int item = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
        
        // prevent log errors
        if(item == -1)
            return Plugin_Continue;
        
        GetEntityClassname(item, buffer, sizeof(buffer));
        
        if (StrEqual(buffer, "weapon_fists", false) || StrEqual(buffer, "weapon_melee", false))
        {
            buttons &= ~IN_ATTACK2; //Don't press attack 2
            return Plugin_Changed;
        }
    }

    return Plugin_Continue;
}


stock bool HasWeapon(int client, const char[] classname)
{
    int index;
    int weapon;
    char sName[64];
    
    while((weapon = GetNextWeapon(client, index)) != -1)
    {
        GetEdictClassname(weapon, sName, sizeof(sName));
        if (StrEqual(sName, classname))
            return true;
    }
    return false;
}

stock int GetNextWeapon(int client, int &weaponIndex)
{
    static int weaponsOffset = -1;
    if (weaponsOffset == -1)
        weaponsOffset = FindDataMapInfo(client, "m_hMyWeapons");
    
    int offset = weaponsOffset + (weaponIndex * 4);
    
    int weapon;
    while (weaponIndex < 48) 
    {
        weaponIndex++;
        
        weapon = GetEntDataEnt2(client, offset);
        
        if (IsValidEdict(weapon)) 
            return weapon;
        
        offset += 4;
    }
    
    return -1;
} 
