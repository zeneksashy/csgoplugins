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
	NoShootingMode , //2
	CustomConfigMode, //3
	Default // 4
}

int votes = 0;
bool customModeTurnedOn = false;
bool customRoundStarted = false;
int currentModeIndex = 0;
CustomMode _mode;
bool voteInProgress = false;
ConVar g_voteMaxPlayers;
ConVar g_warmupRounds;
ConVar g_vipPluginEnabled;
int warmupRounds;

//todo change that into working array of structures
char g_modeName[MODE_NAME_SIZE][MODE_NAME_SIZE];
CustomMode g_modeType[MODE_NAME_SIZE];
char g_execs[MODE_NAME_SIZE][MODE_EXECS_SIZE][MODE_EXECS_SIZE];
char g_serverExecs [MODE_NAME_SIZE][MODE_EXECS_SIZE][MODE_EXECS_SIZE];

public Plugin myinfo = 
{
	name = "Custom Round plugin",
	author = "Zenek",
	description = "Plugin allows to call vote to make next round use custom settings",
	version = "1.3",
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
	
	if (!KvGotoFirstSubKey(kv))
	{
		SetFailState("CFG File not found: %s", configPath);
		CloseHandle(kv);
	}
	int counter = 0;
	do
	{
		char name[MODE_NAME_SIZE];
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
	
	HookEvent("round_start",Event_RoundStart);
	HookEvent("round_end",Event_RoundEnd);
	HookEvent("player_team",Event_PlayerJoinedTeam);
	
	_mode = Default;
	
	g_voteMaxPlayers = CreateConVar("maxplayers_for_vote","9","Sets a vote ratio");
	g_warmupRounds = CreateConVar("warmup_rounds","4","Sets a warmup rounds count");
	g_vipPluginEnabled = CreateConVar("vip_plugin_enabled", "1", "Wheater Advaned vip plugin should be reseted after warmup");
	
	warmupRounds = g_warmupRounds.IntValue;
	AutoExecConfig(true);
}

public void OnMapStart()
{
	ServerCommand("mp_startmoney 16000");
	ServerCommand("mp_roundtime_defuse 0.5");
	ServerCommand("mp_freezetime 1");
	votes = 0;
	customModeTurnedOn = false;
	customRoundStarted = false;
	voteInProgress = false;
	currentModeIndex = 0;
	_mode = Default;
	warmupRounds = g_warmupRounds.IntValue;
	
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

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
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
		ClientOperations();
		ServerOperations();
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
			if(g_vipPluginEnabled.IntValue == 1)
			{
				 ServerCommand("sm plugins reload H2K_VipNormalMode")
			}
            
            ServerCommand("exec gamemode_competitive.cfg");
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

void ClientOperations()
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
		while(RemoveGranades(client)){}
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

void ChangeMode(CustomMode newMode)
{
	// Change to print to chat?
	PrintToServer("Votes %d's out of %d", votes, GetClientCount());
	if((GetClientCount()/2) < votes)
	{
		voteInProgress = true;
		customModeTurnedOn = true;
		_mode = newMode;
	}
	votes = 0;
}

public int MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    /* If an option was selected, tell the client about the item. */
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
        delete menu;
        ChangeMode(_mode);
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
        currentModeIndex = param2;
        _mode = g_modeType[currentModeIndex];
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
