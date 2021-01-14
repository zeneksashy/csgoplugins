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
bool customModeTurnedOn =false;
bool customRoundStarted =false;
int currentModeIndex = 0;
CustomMode _mode;
bool voteInProgress = false;
ConVar g_voteMaxPlayers;
ConVar g_warmupRounds;
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
	version = "1.2",
	url = "https://github.com/zeneksashy/csgoplugins"
};


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
		PrintToServer("Key value name %s",name);
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
					PrintToServer("Client exec %s",g_execs[counter][i]);
				}
				else
				{
					g_serverExecs[counter][i] = exec;
					PrintToServer("Server exec %s",g_serverExecs[counter][i]);
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
						PrintToServer("Client exec %s",g_execs[counter][i]);
					}
					else
					{
						g_serverExecs[counter][i] = exec;
						PrintToServer("Server exec %s",g_serverExecs[counter][i]);
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
	RegConsoleCmd("menu_test", StartVote);
	AddCommandListener(ChatListener, "say");
	AddCommandListener(ChatListener, "say2");
	AddCommandListener(ChatListener, "say_team");
	
	HookEvent("round_start",Event_RoundStart);
	HookEvent("round_end",Event_RoundEnd);
	HookEvent("player_team",Event_PlayerJoinedTeam);
	
	_mode = Default;
	
	g_voteMaxPlayers = CreateConVar("maxplayers_for_vote","8","Sets a vote ratio");
	g_warmupRounds = CreateConVar("warmup_rounds","4","Sets a warmup rounds count");
	
	warmupRounds = g_warmupRounds.IntValue;
	AutoExecConfig(true);
}

public void OnMapStart()
{
	ServerCommand("mp_startmoney 16000");
	ServerCommand("mp_roundtime_defuse 0.5");
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
		SinglePlayerWeaponOperations(GetClientOfUserId(event.GetInt("userid")));
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if(warmupRounds)
	{
		_mode = g_modeType[currentModeIndex];
		currentModeIndex = warmupRounds;
		PrintToServer("%d Warmup rounds left",warmupRounds);
		customModeTurnedOn = true;
	}
	if(customModeTurnedOn)
	{
		customRoundStarted =true;
		voteInProgress = false;
		PrintToServer("Custom round started %s", g_modeName[currentModeIndex]);		
		customModeTurnedOn = false;
		ClientOperations();
		ServerOperations();
	}
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if(warmupRounds)
	{
		--warmupRounds;
		if(warmupRounds == 0)
		{
			PrintToServer("Restarting the game");
			ConVar command = FindConVar("mp_startmoney");
			ResetConVar(command);
			command = FindConVar("mp_roundtime_defuse");
			ResetConVar(command);
			ServerCommand("mp_restartgame 1");
		}
	}
	if(customRoundStarted && !customModeTurnedOn)
	{
		customRoundStarted = false;
		PrintToServer("Custom round finished");
		customModeTurnedOn = false;
		RevertServerOperations();
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
			ResetConVar(command);
		}
		
	}
}

void ClientOperations()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && IsClientInGame(i))
		{
			if(IsPlayerAlive(i))
			{
				if(_mode <CustomConfigMode)
				{
					SinglePlayerWeaponOperations(i);
				}
			}
		}
	}
}

void SinglePlayerWeaponOperations(int i)
{
	for (int j = 0; j <= _mode; j++)
	{
		int index = GetPlayerWeaponSlot(i,j);
		if(index != -1)
			RemovePlayerItem(i,index);
	}
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
		if(strcmp(g_modeName[i],"")! = 0)
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
