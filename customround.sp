#include <sourcemod>
#include <sdktools>

#pragma newdecls required
int votes = 0;
bool customModeTurnedOn =false;
bool customRoundStarted =false;
int currentModeIndex = 0;
enum CustomMode
{
	PrimaryWeaponMode = 0,
	SecondaryWeaponMode = 0,
	NoShootingMode = 1,
	CustomConfigMode,
	Default
}

CustomMode _mode;
#define MODE_NAME_SIZE 32
#define MODE_EXECS_SIZE 64

//todo change that into working array of structures
char g_modeName[MODE_NAME_SIZE][MODE_NAME_SIZE];
CustomMode g_modeType[MODE_NAME_SIZE];
char g_execs[MODE_NAME_SIZE][MODE_EXECS_SIZE][MODE_EXECS_SIZE];

/*void getElementAt(int index, char [] name, CustomMode& mode, char [][] execs)
{
	name = g_modeName[index];
	mode = g_modeType[index];
	execs = g_execs[index];
}*/

void initialize_modes()
{
	//todo read from config
	g_modeName[0] = "deagle only";
	g_modeType[0] = SecondaryWeaponMode;
	g_execs[0][0] = "weapon_deagle";
	
	g_modeName[1] = "scout only";
	g_modeType[1] = PrimaryWeaponMode;
	g_execs[1][0] = "weapon_ssg08";
	
	g_modeName[2] = "sniper mode";
	g_modeType[2] = PrimaryWeaponMode;
	g_execs[2][0] = "weapon_ssg08";
	g_execs[2][1] = "weapon_deagle";
	
	g_modeName[3] = "Tank mode";
	g_modeType[3] = PrimaryWeaponMode;
	g_execs[3][0] = "weapon_negev";
	g_execs[3][1] = "weapon_deagle";
	
}

enum struct ModeInfo
{
	CustomMode supportedMode;
	char modeName[MODE_NAME_SIZE];
	char execs[MODE_EXECS_SIZE]; // up to 32 commands with 64 bit length per mode semicolon separated
	void init(CustomMode mode,const char [] name, const char[] newExecs)
	{
		this.supportedMode = mode;
		strcopy(this.modeName,MODE_NAME_SIZE,name);
		strcopy(this.execs,MODE_EXECS_SIZE,newExecs);
	}
}


public Plugin myinfo = 
{
	name = "Custom Round plugin",
	author = "Zenek",
	description = "Plugin allows to call vote to make next round use custom settings",
	version = "1.0",
	url = "http://www.sourcemod.net/"
};

public void OnPluginStart()
{
	initialize_modes();
	PrintToServer("Hello world!");
	RegConsoleCmd("menu_test", StartVote);
	AddCommandListener(ChatListener, "say");
	AddCommandListener(ChatListener, "say2");
	AddCommandListener(ChatListener, "say_team");
	HookEvent("round_start",Event_RoundStart);
	HookEvent("round_end",Event_RoundEnd);
	HookEvent("player_team",Event_PlayerJoinedTeam);
	_mode = Default;
}

public Action CS_OnBuyCommand(int iClient, const char[] chWeapon)
{
	if(_mode<CustomConfigMode && customRoundStarted)
	{
		const int array_size = 13;
		PrintToServer("On buy command %s",chWeapon);
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
				return Plugin_Continue; // Continue as normal.
			}
		PrintToServer("Blocking the buy of %s",chWeapon);
		return Plugin_Handled; // Block the buy.
	}
	return Plugin_Continue;
} 

public void Event_PlayerJoinedTeam(Event event, const char[] name, bool dontBroadcast)
{
	PrintToServer("On Player Join");
	if(customRoundStarted)
	{
		SinglePlayerWeaponOperations(GetClientOfUserId(event.GetInt("userid")));
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	PrintToServer("On Round Start");
	if(customModeTurnedOn)
	{
		customRoundStarted =true;
		PrintToServer("Custom round started");
		customModeTurnedOn = false;
		WeaponOperations();
	}
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if(customRoundStarted && !customModeTurnedOn)
	{
		customRoundStarted = false;
		PrintToServer("Custom round finished");
		customModeTurnedOn = false;
		_mode = Default;
	}
}

void WeaponOperations()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientConnected(i) || IsClientObserver(i))
		{
			continue;
		}
		PrintToServer("Weapon should be changed");
		/*char other[32];
		GetClientName(i, other, sizeof(other));*/
		if(_mode <CustomConfigMode)
		{
			SinglePlayerWeaponOperations(i);
		}
		
	}
}

void SinglePlayerWeaponOperations(int i)
{
	for (int j = 0; j < 2; j++)
	{
		int index = GetPlayerWeaponSlot(i,j);
		if(index != -1)
			RemovePlayerItem(i,index);
	}
	for(int j = 0; j<MODE_EXECS_SIZE;++j)
		GivePlayerItem(i,g_execs[currentModeIndex][j]);
}

public Action ChatListener(int client, const char[] command, int args)
{
	char msg[128];
	GetCmdArgString(msg, sizeof(msg));
	StripQuotes(msg);
	if(StrEqual(msg, "!custom"))
	{
		PrintToServer("Menu should appear");
		return StartVoteMenu(client,args);
	}
	return Plugin_Continue;
}

void ChangeMode(CustomMode newMode)
{
	PrintToServer("Votes %d's out of %d", votes, GetClientCount());
	if((GetClientCount()/2) < votes)
	{
		PrintToServer("Next round should be custom");
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
		PrintToServer("Menu was deleted");
        delete menu;
		ChangeMode(SecondaryWeaponMode);
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
		PrintToServer("Menu was deleted");
        delete menu;
		ChangeMode(SecondaryWeaponMode);
    }
}


public Action StartVoteMenu(int client, int args)
{
    Menu menu = new Menu(ClientMenuHandler);
    menu.SetTitle("Start vote to play next round with custom settings ");
	for(int i =0;i<MODE_NAME_SIZE;++i)
	{
		if(strcmp(g_modeName[i],"")!=0)
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
