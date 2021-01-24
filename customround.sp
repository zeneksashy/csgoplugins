#include <sourcemod>
#include <sdktools>
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
bool customModeTurnedOn = false;
bool customRoundStarted = false;
int currentModeIndex = 0;
CustomMode _mode;
bool voteInProgress = false;
ConVar g_voteMaxPlayers;
ConVar g_warmupRounds;
ConVar g_weaponRestrictPluginEnabled;
int warmupRounds;

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
    version = "1.5",
    url = "https://github.com/zeneksashy/csgoplugins"
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
    PrintToServer("Hello world!");
    RegConsoleCmd("custom_reload", ReloadPlugin);
    AddCommandListener(ChatListener, "say");
    AddCommandListener(ChatListener, "say2");
    AddCommandListener(ChatListener, "say_team");

    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("round_prestart",Event_RoundStart);
    HookEvent("round_end",Event_RoundEnd);
    //HookEvent("player_team",Event_PlayerJoinedTeam);

    _mode = Default;

    g_voteMaxPlayers = CreateConVar("maxplayers_for_vote","9","Sets a vote ratio");
    g_warmupRounds = CreateConVar("warmup_rounds","4","Sets a warmup rounds count");
    g_weaponRestrictPluginEnabled = CreateConVar("weapon_restrict_disable", "1", "Wheater weapon restrict plugin should be unloaded on custom rounds");

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
        PrintToServer("Blocking the buy of %s",chWeapon);
        return Plugin_Handled;
    }
    return Plugin_Continue;
} 

public void Event_PlayerJoinedTeam(Event event, const char[] name, bool dontBroadcast)
{
    if(customRoundStarted)
    {
        PlayerCheckAndUpdateWeaponOperation(GetClientOfUserId(event.GetInt("userid")));
    }
}
public Action Event_PlayerSpawn(Event hEvent, const char[] chName, bool bDontBroadcast)
{
    PrintToServer("Player spawn");
    if(customRoundStarted)
    {
        PrintToServer("Player spawned during custom round");
        CreateTimer(0.2, TimerPlayerSpawn, GetClientOfUserId(hEvent.GetInt("userid")), TIMER_FLAG_NO_MAPCHANGE);
    }
}
public Action TimerPlayerSpawn(Handle timer, int client)
{
    PlayerCheckAndUpdateWeaponOperation(client);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
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
        
        //ClientOperations();
        ServerOperations();
        if(g_weaponRestrictPluginEnabled.IntValue == 1)
        {
             ServerCommand("sm plugins unload weapon_restrict")
        }
        PrintToChatAll("╔════════════════════════════════════════╗");
        PrintToChatAll("%s Custom Round Started",g_modeName[currentModeIndex]);
        PrintToChatAll("╚════════════════════════════════════════╝");
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
    /*if (weapons>=3)
    {
        
        int grenadeOffsets[] = {15, 17, 16, 14, 18, 17};
        while(RemoveGranades(client)){}
        for(int i = 0; i < sizeof(grenadeOffsets); i++)
            SetEntProp(client, Prop_Send, "m_iAmmo", 0, _, grenadeOffsets[i]);
    }*/
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
        ChangeMode(g_modeType[param2],param2);
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
    menu.SetTitle("Do you want to play next round with custom settings? %s",g_modeName[currentModeIndex]);
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
