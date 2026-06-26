#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <websocket>
#include <mge>

public Plugin myinfo = 
{
    name = "MGE WebSocket Bridge",
    author = "MGE Community",
    description = "Simple WebSocket interface for MGE commands",
    version = "1.0.0",
    url = ""
};

// ===== WEBSOCKET SERVER =====

WebSocketServer g_hWebSocketServer;

// ===== PLUGIN LIFECYCLE =====

public void OnPluginStart()
{
    RegAdminCmd("mge_ws_start", Command_StartWebSocket, ADMFLAG_ROOT, "Start MGE WebSocket server");
    RegAdminCmd("mge_ws_stop", Command_StopWebSocket, ADMFLAG_ROOT, "Stop MGE WebSocket server");
    
    // Auto-start the server
    CreateTimer(2.0, Timer_StartWebSocket, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnPluginEnd()
{
    if (g_hWebSocketServer != null)
    {
        g_hWebSocketServer.Stop();
        delete g_hWebSocketServer;
    }
}

// ===== COMMANDS =====

Action Command_StartWebSocket(int client, int args)
{
    StartWebSocketServer();
    ReplyToCommand(client, "[MGE WS] WebSocket server started on port 9001");
    return Plugin_Handled;
}

Action Command_StopWebSocket(int client, int args)
{
    if (g_hWebSocketServer != null)
    {
        g_hWebSocketServer.Stop();
        delete g_hWebSocketServer;
        g_hWebSocketServer = null;
        ReplyToCommand(client, "[MGE WS] WebSocket server stopped");
    }
    return Plugin_Handled;
}

Action Timer_StartWebSocket(Handle timer)
{
    StartWebSocketServer();
    return Plugin_Stop;
}

// ===== WEBSOCKET SERVER =====

void StartWebSocketServer()
{
    if (g_hWebSocketServer != null)
    {
        PrintToServer("[MGE WS] Server already running");
        return;
    }
    
    g_hWebSocketServer = new WebSocketServer("0.0.0.0", 9001);
    g_hWebSocketServer.SetMessageCallback(OnMessage);
    g_hWebSocketServer.SetOpenCallback(OnOpen);
    g_hWebSocketServer.SetCloseCallback(OnClose);
    g_hWebSocketServer.SetErrorCallback(OnError);
    g_hWebSocketServer.Start();
    
    PrintToServer("[MGE WS] Server started on port 9001");
}

// ===== WEBSOCKET CALLBACKS =====

void OnOpen(WebSocketServer ws, const char[] RemoteAddr, const char[] RemoteId)
{
    PrintToServer("[MGE WS] Client connected: %s", RemoteAddr);
    
    // Send welcome message using yyjson
    JSONObject welcome = new JSONObject();
    welcome.SetString("type", "welcome");
    welcome.SetString("message", "Connected to MGE WebSocket");
    welcome.SetInt("arenas", MGE_GetArenaCount());
    
    char jsonStr[256];
    welcome.ToString(jsonStr, sizeof(jsonStr));
    ws.SendMessageToClient(RemoteId, jsonStr);
    
    delete welcome;
}

void OnClose(WebSocketServer ws, int code, const char[] reason, const char[] RemoteAddr, const char[] RemoteId)
{
    PrintToServer("[MGE WS] Client disconnected: %s", RemoteAddr);
}

void OnError(WebSocketServer ws, const char[] errMsg, const char[] RemoteAddr, const char[] RemoteId)
{
    PrintToServer("[MGE WS] Error: %s", errMsg);
}

void OnMessage(WebSocketServer ws, WebSocket client, const char[] message, int wireSize, const char[] RemoteAddr, const char[] RemoteId)
{
    PrintToServer("[MGE WS] Message from %s: %s", RemoteAddr, message);
    
    // Parse JSON properly
    JSONObject request = JSONObject.FromString(message);
    if (request == null)
    {
        SendErrorResponse(ws, RemoteId, "Invalid JSON format");
        return;
    }
    
    char command[64];
    if (!request.GetString("command", command, sizeof(command)))
    {
        SendErrorResponse(ws, RemoteId, "Missing 'command' field");
        delete request;
        return;
    }
    
    if (StrEqual(command, "get_arenas"))
    {
        HandleGetArenas(ws, RemoteId);
    }
    else if (StrEqual(command, "get_players"))
    {
        HandleGetPlayers(ws, RemoteId);
    }
    else if (StrEqual(command, "add_player_to_arena"))
    {
        HandleAddPlayerToArena(ws, RemoteId, request);
    }
    else if (StrEqual(command, "remove_player_from_arena"))
    {
        HandleRemovePlayerFromArena(ws, RemoteId, request);
    }
    else if (StrEqual(command, "get_player_stats"))
    {
        HandleGetPlayerStats(ws, RemoteId, request);
    }
    else if (StrEqual(command, "get_arena_details"))
    {
        HandleGetArenaDetails(ws, RemoteId, request);
    }
    else if (StrEqual(command, "set_player_ready"))
    {
        HandleSetPlayerReady(ws, RemoteId, request);
    }
    else if (StrEqual(command, "get_server_status"))
    {
        HandleGetServerStatus(ws, RemoteId);
    }
    else
    {
        SendErrorResponse(ws, RemoteId, "Unknown command");
    }
    
    delete request;
}

// ===== COMMAND HANDLERS =====

void HandleGetArenas(WebSocketServer ws, const char[] clientId)
{
    // Create response object
    JSONObject response = new JSONObject();
    response.SetString("type", "response");
    response.SetString("command", "get_arenas");
    
    // Create arenas array
    JSONArray arenas = new JSONArray();
    
    int arenaCount = MGE_GetArenaCount();
    for (int i = 1; i <= arenaCount; i++)
    {
        if (!MGE_IsValidArena(i))
            continue;
            
        JSONObject arena = new JSONObject();
        arena.SetInt("id", i);
        
        // Get all arena info in one call using the struct
        MGEArenaInfo arenaInfo;
        if (!MGE_GetArenaInfo(i, arenaInfo))
            continue; // Skip invalid arenas
            
        arena.SetString("name", arenaInfo.name);
        arena.SetInt("players", arenaInfo.players);
        arena.SetInt("max", arenaInfo.maxSlots);
        arena.SetInt("status", arenaInfo.status);
        arena.SetString("status_name", GetArenaStatusName(arenaInfo.status));
        arena.SetBool("is2v2", arenaInfo.is2v2);
        arena.SetInt("game_mode", arenaInfo.gameMode);
        arena.SetString("game_mode_names", GetGameModeNames(arenaInfo.gameMode));
        arena.SetInt("frag_limit", arenaInfo.fragLimit);
        
        arenas.Push(arena);
        delete arena;
    }
    
    response.Set("arenas", arenas);
    
    // Convert to string and send
    char jsonStr[8192];
    response.ToString(jsonStr, sizeof(jsonStr));
    ws.SendMessageToClient(clientId, jsonStr);
    
    // Cleanup
    delete arenas;
    delete response;
}

void HandleGetPlayers(WebSocketServer ws, const char[] clientId)
{
    // Create response object
    JSONObject response = new JSONObject();
    response.SetString("type", "response");
    response.SetString("command", "get_players");
    
    // Create players array
    JSONArray players = new JSONArray();
    
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
            continue;
            
        char name[64];
        GetClientName(client, name, sizeof(name));
        
        JSONObject player = new JSONObject();
        player.SetInt("id", client);
        player.SetString("name", name);  // yyjson handles escaping automatically
        player.SetInt("arena", MGE_GetPlayerArena(client));
        player.SetBool("inArena", MGE_IsPlayerInArena(client));
        
        // Add ELO and stats preview
        MGEPlayerStats stats;
        if (MGE_GetPlayerStats(client, stats))
        {
            player.SetInt("elo", stats.elo);
            player.SetFloat("rating", stats.rating);
            player.SetInt("wins", stats.wins);
            player.SetInt("losses", stats.losses);
        }
        
        // Add 2v2 specific info
        if (MGE_IsPlayerInArena(client) && IsArena2v2_Safe(MGE_GetPlayerArena(client)))
        {
            player.SetBool("ready", MGE_IsPlayerReady(client));
            int teammate = MGE_GetPlayerTeammate(client);
            if (teammate > 0)
            {
                char teammateName[64];
                GetClientName(teammate, teammateName, sizeof(teammateName));
                player.SetString("teammate", teammateName);
                player.SetInt("teammate_id", teammate);
            }
        }
        
        players.Push(player);
        delete player;
    }
    
    response.Set("players", players);
    
    // Convert to string and send
    char jsonStr[4096];
    response.ToString(jsonStr, sizeof(jsonStr));
    ws.SendMessageToClient(clientId, jsonStr);
    
    // Cleanup
    delete players;
    delete response;
}

void HandleAddPlayerToArena(WebSocketServer ws, const char[] clientId, JSONObject request)
{
    // Extract parameters from JSON
    int playerId = request.GetInt("player_id");
    int arenaId = request.GetInt("arena_id");
    
    // Validate parameters
    if (playerId <= 0 || playerId > MaxClients || !IsClientInGame(playerId))
    {
        SendErrorResponse(ws, clientId, "Invalid player ID");
        return;
    }
    
    if (arenaId <= 0 || !MGE_IsValidArena(arenaId))
    {
        SendErrorResponse(ws, clientId, "Invalid arena ID");
        return;
    }
    
    // Attempt to add player to arena
    bool success = MGE_AddPlayerToArena(playerId, arenaId);
    
    JSONObject response = new JSONObject();
    if (success)
    {
        char playerName[64];
        GetClientName(playerId, playerName, sizeof(playerName));
        
        response.SetString("type", "success");
        response.SetString("message", "Player added to arena successfully");
        response.SetString("player_name", playerName);
        response.SetInt("player_id", playerId);
        response.SetInt("arena_id", arenaId);
    }
    else
    {
        response.SetString("type", "error");
        response.SetString("message", "Failed to add player to arena");
        response.SetInt("player_id", playerId);
        response.SetInt("arena_id", arenaId);
    }
    
    // Send response
    char jsonStr[512];
    response.ToString(jsonStr, sizeof(jsonStr));
    ws.SendMessageToClient(clientId, jsonStr);
    
    delete response;
}

void HandleRemovePlayerFromArena(WebSocketServer ws, const char[] clientId, JSONObject request)
{
    // Extract player ID from JSON
    int playerId = request.GetInt("player_id");
    
    // Validate player
    if (playerId <= 0 || playerId > MaxClients || !IsClientInGame(playerId))
    {
        SendErrorResponse(ws, clientId, "Invalid player ID");
        return;
    }
    
    // Check if player is actually in an arena
    if (!MGE_IsPlayerInArena(playerId))
    {
        SendErrorResponse(ws, clientId, "Player is not in an arena");
        return;
    }
    
    // Get current arena for response
    int currentArena = MGE_GetPlayerArena(playerId);
    char playerName[64];
    GetClientName(playerId, playerName, sizeof(playerName));
    
    // Attempt to remove player from arena
    bool success = MGE_RemovePlayerFromArena(playerId);
    
    JSONObject response = new JSONObject();
    if (success)
    {
        response.SetString("type", "success");
        response.SetString("message", "Player removed from arena successfully");
        response.SetString("player_name", playerName);
        response.SetInt("player_id", playerId);
        response.SetInt("arena_id", currentArena);
    }
    else
    {
        response.SetString("type", "error");
        response.SetString("message", "Failed to remove player from arena");
        response.SetString("player_name", playerName);
        response.SetInt("player_id", playerId);
        response.SetInt("arena_id", currentArena);
    }
    
    // Send response
    char jsonStr[512];
    response.ToString(jsonStr, sizeof(jsonStr));
    ws.SendMessageToClient(clientId, jsonStr);
    
    delete response;
}

void HandleGetPlayerStats(WebSocketServer ws, const char[] clientId, JSONObject request)
{
    int playerId = request.GetInt("player_id");
    
    if (playerId <= 0 || playerId > MaxClients || !IsClientInGame(playerId))
    {
        SendErrorResponse(ws, clientId, "Invalid player ID");
        return;
    }
    
    char playerName[64];
    GetClientName(playerId, playerName, sizeof(playerName));
    
    JSONObject response = new JSONObject();
    response.SetString("type", "response");
    response.SetString("command", "get_player_stats");
    response.SetInt("player_id", playerId);
    response.SetString("player_name", playerName);
    
    MGEPlayerStats stats;
    if (MGE_GetPlayerStats(playerId, stats))
    {
        JSONObject playerStats = new JSONObject();
        playerStats.SetInt("elo", stats.elo);
        playerStats.SetInt("kills", stats.kills);
        playerStats.SetInt("deaths", stats.deaths);
        playerStats.SetInt("wins", stats.wins);
        playerStats.SetInt("losses", stats.losses);
        playerStats.SetFloat("rating", stats.rating);
        
        // Calculate additional stats
        int totalMatches = stats.wins + stats.losses;
        float winPercent = totalMatches > 0 ? (float(stats.wins) / float(totalMatches)) * 100.0 : 0.0;
        float kdr = stats.deaths > 0 ? float(stats.kills) / float(stats.deaths) : float(stats.kills);
        
        playerStats.SetInt("total_matches", totalMatches);
        playerStats.SetFloat("win_percentage", winPercent);
        playerStats.SetFloat("kdr", kdr);
        
        response.Set("stats", playerStats);
        delete playerStats;
    }
    else
    {
        response.SetString("error", "Could not retrieve player statistics");
    }
    
    // Add current arena info
    if (MGE_IsPlayerInArena(playerId))
    {
        int arena = MGE_GetPlayerArena(playerId);
        response.SetInt("current_arena", arena);
        response.SetBool("in_2v2", IsArena2v2_Safe(arena));
        
        if (IsArena2v2_Safe(arena))
        {
            response.SetBool("ready", MGE_IsPlayerReady(playerId));
            int teammate = MGE_GetPlayerTeammate(playerId);
            if (teammate > 0)
            {
                char teammateName[64];
                GetClientName(teammate, teammateName, sizeof(teammateName));
                response.SetString("teammate", teammateName);
                response.SetInt("teammate_id", teammate);
            }
        }
    }
    
    char jsonStr[2048];
    response.ToString(jsonStr, sizeof(jsonStr));
    ws.SendMessageToClient(clientId, jsonStr);
    
    delete response;
}

void HandleGetArenaDetails(WebSocketServer ws, const char[] clientId, JSONObject request)
{
    int arenaId = request.GetInt("arena_id");
    
    if (arenaId <= 0 || !MGE_IsValidArena(arenaId))
    {
        SendErrorResponse(ws, clientId, "Invalid arena ID");
        return;
    }
    
    JSONObject response = new JSONObject();
    response.SetString("type", "response");
    response.SetString("command", "get_arena_details");
    response.SetInt("arena_id", arenaId);
    
    // Get arena info using the struct for consistency
    MGEArenaInfo arenaInfo;
    if (!MGE_GetArenaInfo(arenaId, arenaInfo))
    {
        SendErrorResponse(ws, clientId, "Failed to get arena information");
        return;
    }
    
    response.SetString("arena_name", arenaInfo.name);
    response.SetInt("players", arenaInfo.players);
    response.SetInt("max_slots", arenaInfo.maxSlots);
    response.SetInt("status", arenaInfo.status);
    response.SetString("status_name", GetArenaStatusName(arenaInfo.status));
    response.SetBool("is_2v2", arenaInfo.is2v2);
    response.SetInt("game_mode", arenaInfo.gameMode);
    response.SetString("game_mode_names", GetGameModeNames(arenaInfo.gameMode));
    response.SetInt("frag_limit", arenaInfo.fragLimit);
    
    // Player slot details
    JSONArray slots = new JSONArray();
    int maxSlots = arenaInfo.maxSlots;
    
    for (int slot = 1; slot <= maxSlots; slot++)
    {
        JSONObject slotInfo = new JSONObject();
        slotInfo.SetInt("slot", slot);
        slotInfo.SetBool("valid", MGE_IsValidSlotForArena(arenaId, slot));
        
        int player = MGE_GetArenaPlayer(arenaId, slot);
        if (player > 0 && IsClientInGame(player))
        {
            char playerName[64];
            GetClientName(player, playerName, sizeof(playerName));
            slotInfo.SetInt("player_id", player);
            slotInfo.SetString("player_name", playerName);
            slotInfo.SetBool("occupied", true);
            
            if (IsArena2v2_Safe(arenaId))
            {
                slotInfo.SetBool("ready", MGE_IsPlayerReady(player));
            }
        }
        else
        {
            slotInfo.SetBool("occupied", false);
        }
        
        slots.Push(slotInfo);
        delete slotInfo;
    }
    
    response.Set("slots", slots);
    delete slots;
    
    char jsonStr[2048];
    response.ToString(jsonStr, sizeof(jsonStr));
    ws.SendMessageToClient(clientId, jsonStr);
    
    delete response;
}

void HandleSetPlayerReady(WebSocketServer ws, const char[] clientId, JSONObject request)
{
    int playerId = request.GetInt("player_id");
    bool ready = request.GetBool("ready");
    
    if (playerId <= 0 || playerId > MaxClients || !IsClientInGame(playerId))
    {
        SendErrorResponse(ws, clientId, "Invalid player ID");
        return;
    }
    
    if (!MGE_IsPlayerInArena(playerId))
    {
        SendErrorResponse(ws, clientId, "Player is not in an arena");
        return;
    }
    
    int arena = MGE_GetPlayerArena(playerId);
    if (!IsArena2v2_Safe(arena))
    {
        SendErrorResponse(ws, clientId, "Player is not in a 2v2 arena");
        return;
    }
    
    bool success = MGE_SetPlayerReady(playerId, ready);
    
    JSONObject response = new JSONObject();
    if (success)
    {
        char playerName[64];
        GetClientName(playerId, playerName, sizeof(playerName));
        
        response.SetString("type", "success");
        response.SetString("message", ready ? "Player marked as ready" : "Player marked as not ready");
        response.SetString("player_name", playerName);
        response.SetInt("player_id", playerId);
        response.SetInt("arena_id", arena);
        response.SetBool("ready", ready);
    }
    else
    {
        response.SetString("type", "error");
        response.SetString("message", "Failed to set player ready status");
        response.SetInt("player_id", playerId);
        response.SetBool("ready", ready);
    }
    
    char jsonStr[512];
    response.ToString(jsonStr, sizeof(jsonStr));
    ws.SendMessageToClient(clientId, jsonStr);
    
    delete response;
}

void HandleGetServerStatus(WebSocketServer ws, const char[] clientId)
{
    JSONObject response = new JSONObject();
    response.SetString("type", "response");
    response.SetString("command", "get_server_status");
    
    // Server info
    response.SetInt("max_clients", MaxClients);
    response.SetInt("current_clients", GetClientCount());
    response.SetInt("arena_count", MGE_GetArenaCount());
    
    char hostname[128], mapname[64];
    GetConVarString(FindConVar("hostname"), hostname, sizeof(hostname));
    GetCurrentMap(mapname, sizeof(mapname));
    
    response.SetString("hostname", hostname);
    response.SetString("current_map", mapname);
    
    // Arena statistics
    int totalPlayers = 0;
    int activeFights = 0;
    int readyPhases = 0;
    
    JSONArray gameModeStats = new JSONArray();
    int gameModeCount[9]; // Track count for each game mode
    
    for (int i = 1; i <= MGE_GetArenaCount(); i++)
    {
        if (!MGE_IsValidArena(i))
            continue;
            
        totalPlayers += GetArenaPlayerCount_Safe(i);
        int status = GetArenaStatus_Safe(i);
        
        if (status == 3) // AS_FIGHT
            activeFights++;
        else if (status == 6) // AS_WAITING_READY
            readyPhases++;
            
        // Count game modes
        int gameMode = GetArenaGameMode_Safe(i);
        for (int mode = 0; mode < 9; mode++)
        {
            if (gameMode & (1 << mode))
                gameModeCount[mode]++;
        }
    }
    
    response.SetInt("total_players_in_arenas", totalPlayers);
    response.SetInt("active_fights", activeFights);
    response.SetInt("ready_phases", readyPhases);
    
    // Add game mode breakdown
    char gameModeNames[9][32] = {"MGE", "BBall", "KOTH", "Ammomod", "Midair", "Endif", "Ultiduo", "Turris", "2v2"};
    for (int i = 0; i < 9; i++)
    {
        if (gameModeCount[i] > 0)
        {
            JSONObject modeInfo = new JSONObject();
            modeInfo.SetString("name", gameModeNames[i]);
            modeInfo.SetInt("count", gameModeCount[i]);
            gameModeStats.Push(modeInfo);
            delete modeInfo;
        }
    }
    
    response.Set("game_mode_stats", gameModeStats);
    delete gameModeStats;
    
    char jsonStr[2048];
    response.ToString(jsonStr, sizeof(jsonStr));
    ws.SendMessageToClient(clientId, jsonStr);
    
    delete response;
}

// ===== HELPER FUNCTIONS =====

void SendErrorResponse(WebSocketServer ws, const char[] clientId, const char[] errorMessage)
{
    JSONObject response = new JSONObject();
    response.SetString("type", "error");
    response.SetString("message", errorMessage);
    
    char jsonStr[256];
    response.ToString(jsonStr, sizeof(jsonStr));
    ws.SendMessageToClient(clientId, jsonStr);
    
    delete response;
}

char[] GetArenaStatusName(int status)
{
    char statusName[32];
    switch (status)
    {
        case 0: strcopy(statusName, sizeof(statusName), "🟢 Idle");        // AS_IDLE
        case 1: strcopy(statusName, sizeof(statusName), "🟡 Pre-Countdown"); // AS_PRECOUNTDOWN
        case 2: strcopy(statusName, sizeof(statusName), "🟠 Countdown");   // AS_COUNTDOWN
        case 3: strcopy(statusName, sizeof(statusName), "🔥 Fighting");    // AS_FIGHT
        case 4: strcopy(statusName, sizeof(statusName), "🏁 After Fight"); // AS_AFTERFIGHT
        case 5: strcopy(statusName, sizeof(statusName), "📊 Reported");    // AS_REPORTED
        case 6: strcopy(statusName, sizeof(statusName), "⏳ Waiting Ready"); // AS_WAITING_READY
        default: strcopy(statusName, sizeof(statusName), "❓ Unknown");
    }
    return statusName;
}

char[] GetGameModeNames(int gameModeFlags)
{
    char modes[256];
    modes[0] = '\0';
    
    if (gameModeFlags & (1 << 0)) StrCat(modes, sizeof(modes), "🎯 MGE ");
    if (gameModeFlags & (1 << 1)) StrCat(modes, sizeof(modes), "🏀 BBall ");
    if (gameModeFlags & (1 << 2)) StrCat(modes, sizeof(modes), "👑 KOTH ");
    if (gameModeFlags & (1 << 3)) StrCat(modes, sizeof(modes), "🔫 Ammomod ");
    if (gameModeFlags & (1 << 4)) StrCat(modes, sizeof(modes), "✈️ Midair ");
    if (gameModeFlags & (1 << 5)) StrCat(modes, sizeof(modes), "🔚 Endif ");
    if (gameModeFlags & (1 << 6)) StrCat(modes, sizeof(modes), "⚔️ Ultiduo ");
    if (gameModeFlags & (1 << 7)) StrCat(modes, sizeof(modes), "🗼 Turris ");
    if (gameModeFlags & (1 << 8)) StrCat(modes, sizeof(modes), "👥 2v2 ");
    
    // Remove trailing space
    int len = strlen(modes);
    if (len > 0 && modes[len-1] == ' ')
        modes[len-1] = '\0';
        
    if (modes[0] == '\0')
        strcopy(modes, sizeof(modes), "❓ Unknown");
        
    return modes;
}

// ===== MGE FORWARD IMPLEMENTATIONS =====

// Called after a player is successfully added to an arena
public void MGE_OnPlayerArenaAdded(int client, int arena_index, int slot)
{
    if (!IsValidClient(client))
        return;
        
    char playerName[64];
    GetClientName(client, playerName, sizeof(playerName));
    
    JSONObject event = new JSONObject();
    event.SetString("type", "event");
    event.SetString("event", "player_arena_added");
    event.SetInt("player_id", GetClientUserId(client));
    event.SetString("player_name", playerName);
    event.SetInt("arena_id", arena_index);
    event.SetInt("slot", slot);
    event.SetInt("timestamp", GetTime());
    
    BroadcastToAllClients(event);
    delete event;
}

// Called after a player is successfully removed from an arena
public void MGE_OnPlayerArenaRemoved(int client, int arena_index)
{
    if (!IsValidClient(client))
        return;
        
    char playerName[64];
    GetClientName(client, playerName, sizeof(playerName));
    
    JSONObject event = new JSONObject();
    event.SetString("type", "event");
    event.SetString("event", "player_arena_removed");
    event.SetInt("player_id", GetClientUserId(client));
    event.SetString("player_name", playerName);
    event.SetInt("arena_id", arena_index);
    event.SetInt("timestamp", GetTime());
    
    BroadcastToAllClients(event);
    delete event;
}

// Called when a 1v1 match starts
public void MGE_On1v1MatchStart(int arena_index, int player1, int player2)
{
    if (!IsValidClient(player1) || !IsValidClient(player2))
        return;
        
    char player1Name[64], player2Name[64];
    GetClientName(player1, player1Name, sizeof(player1Name));
    GetClientName(player2, player2Name, sizeof(player2Name));
    
    JSONObject event = new JSONObject();
    event.SetString("type", "event");
    event.SetString("event", "match_start_1v1");
    event.SetInt("arena_id", arena_index);
    event.SetInt("player1_id", GetClientUserId(player1));
    event.SetString("player1_name", player1Name);
    event.SetInt("player2_id", GetClientUserId(player2));
    event.SetString("player2_name", player2Name);
    event.SetInt("timestamp", GetTime());
    
    BroadcastToAllClients(event);
    delete event;
}

// Called when a 1v1 match ends
public void MGE_On1v1MatchEnd(int arena_index, int winner, int loser, int winner_score, int loser_score)
{
    if (!IsValidClient(winner) || !IsValidClient(loser))
        return;
        
    char winnerName[64], loserName[64];
    GetClientName(winner, winnerName, sizeof(winnerName));
    GetClientName(loser, loserName, sizeof(loserName));
    
    JSONObject event = new JSONObject();
    event.SetString("type", "event");
    event.SetString("event", "match_end_1v1");
    event.SetInt("arena_id", arena_index);
    event.SetInt("winner_id", GetClientUserId(winner));
    event.SetString("winner_name", winnerName);
    event.SetInt("loser_id", GetClientUserId(loser));
    event.SetString("loser_name", loserName);
    event.SetInt("winner_score", winner_score);
    event.SetInt("loser_score", loser_score);
    event.SetInt("timestamp", GetTime());
    
    BroadcastToAllClients(event);
    delete event;
}

// Called when a 2v2 match starts
public void MGE_On2v2MatchStart(int arena_index, int team1_player1, int team1_player2, int team2_player1, int team2_player2)
{
    if (!IsValidClient(team1_player1) || !IsValidClient(team1_player2) || 
        !IsValidClient(team2_player1) || !IsValidClient(team2_player2))
        return;
        
    char t1p1Name[64], t1p2Name[64], t2p1Name[64], t2p2Name[64];
    GetClientName(team1_player1, t1p1Name, sizeof(t1p1Name));
    GetClientName(team1_player2, t1p2Name, sizeof(t1p2Name));
    GetClientName(team2_player1, t2p1Name, sizeof(t2p1Name));
    GetClientName(team2_player2, t2p2Name, sizeof(t2p2Name));
    
    JSONObject event = new JSONObject();
    event.SetString("type", "event");
    event.SetString("event", "match_start_2v2");
    event.SetInt("arena_id", arena_index);
    event.SetInt("team1_player1_id", GetClientUserId(team1_player1));
    event.SetString("team1_player1_name", t1p1Name);
    event.SetInt("team1_player2_id", GetClientUserId(team1_player2));
    event.SetString("team1_player2_name", t1p2Name);
    event.SetInt("team2_player1_id", GetClientUserId(team2_player1));
    event.SetString("team2_player1_name", t2p1Name);
    event.SetInt("team2_player2_id", GetClientUserId(team2_player2));
    event.SetString("team2_player2_name", t2p2Name);
    event.SetInt("timestamp", GetTime());
    
    BroadcastToAllClients(event);
    delete event;
}

// Called when a 2v2 match ends
public void MGE_On2v2MatchEnd(int arena_index, int winning_team, int winning_score, int losing_score, 
                             int team1_player1, int team1_player2, int team2_player1, int team2_player2)
{
    if (!IsValidClient(team1_player1) || !IsValidClient(team1_player2) || 
        !IsValidClient(team2_player1) || !IsValidClient(team2_player2))
        return;
        
    char t1p1Name[64], t1p2Name[64], t2p1Name[64], t2p2Name[64];
    GetClientName(team1_player1, t1p1Name, sizeof(t1p1Name));
    GetClientName(team1_player2, t1p2Name, sizeof(t1p2Name));
    GetClientName(team2_player1, t2p1Name, sizeof(t2p1Name));
    GetClientName(team2_player2, t2p2Name, sizeof(t2p2Name));
    
    JSONObject event = new JSONObject();
    event.SetString("type", "event");
    event.SetString("event", "match_end_2v2");
    event.SetInt("arena_id", arena_index);
    event.SetInt("winning_team", winning_team);
    event.SetInt("winning_score", winning_score);
    event.SetInt("losing_score", losing_score);
    event.SetInt("team1_player1_id", GetClientUserId(team1_player1));
    event.SetString("team1_player1_name", t1p1Name);
    event.SetInt("team1_player2_id", GetClientUserId(team1_player2));
    event.SetString("team1_player2_name", t1p2Name);
    event.SetInt("team2_player1_id", GetClientUserId(team2_player1));
    event.SetString("team2_player1_name", t2p1Name);
    event.SetInt("team2_player2_id", GetClientUserId(team2_player2));
    event.SetString("team2_player2_name", t2p2Name);
    event.SetInt("timestamp", GetTime());
    
    BroadcastToAllClients(event);
    delete event;
}

// Called when a player dies in an arena
public void MGE_OnArenaPlayerDeath(int victim, int attacker, int arena_index)
{
    if (!IsValidClient(victim))
        return;
        
    char victimName[64], attackerName[64];
    GetClientName(victim, victimName, sizeof(victimName));
    
    if (IsValidClient(attacker))
        GetClientName(attacker, attackerName, sizeof(attackerName));
    else
        strcopy(attackerName, sizeof(attackerName), "World");
    
    JSONObject event = new JSONObject();
    event.SetString("type", "event");
    event.SetString("event", "arena_player_death");
    event.SetInt("victim_id", GetClientUserId(victim));
    event.SetString("victim_name", victimName);
    event.SetInt("attacker_id", IsValidClient(attacker) ? GetClientUserId(attacker) : 0);
    event.SetString("attacker_name", attackerName);
    event.SetInt("arena_id", arena_index);
    event.SetInt("timestamp", GetTime());
    
    BroadcastToAllClients(event);
    delete event;
}

// Called when a player's ELO changes
public void MGE_OnPlayerELOChange(int client, int old_elo, int new_elo, int arena_index)
{
    if (!IsValidClient(client))
        return;
        
    char playerName[64];
    GetClientName(client, playerName, sizeof(playerName));
    
    JSONObject event = new JSONObject();
    event.SetString("type", "event");
    event.SetString("event", "player_elo_change");
    event.SetInt("player_id", GetClientUserId(client));
    event.SetString("player_name", playerName);
    event.SetInt("old_elo", old_elo);
    event.SetInt("new_elo", new_elo);
    event.SetInt("elo_change", new_elo - old_elo);
    event.SetInt("arena_id", arena_index);
    event.SetInt("timestamp", GetTime());
    
    BroadcastToAllClients(event);
    delete event;
}

// Called when 2v2 ready system starts
public void MGE_On2v2ReadyStart(int arena_index)
{
    JSONObject event = new JSONObject();
    event.SetString("type", "event");
    event.SetString("event", "2v2_ready_start");
    event.SetInt("arena_id", arena_index);
    event.SetInt("timestamp", GetTime());
    
    BroadcastToAllClients(event);
    delete event;
}

// Called when a player changes ready status in 2v2
public void MGE_On2v2PlayerReady(int client, int arena_index, bool ready_status)
{
    if (!IsValidClient(client))
        return;
        
    char playerName[64];
    GetClientName(client, playerName, sizeof(playerName));
    
    JSONObject event = new JSONObject();
    event.SetString("type", "event");
    event.SetString("event", "2v2_player_ready");
    event.SetInt("player_id", GetClientUserId(client));
    event.SetString("player_name", playerName);
    event.SetInt("arena_id", arena_index);
    event.SetBool("ready_status", ready_status);
    event.SetInt("timestamp", GetTime());
    
    BroadcastToAllClients(event);
    delete event;
}

// ===== UTILITY FUNCTIONS =====

// Validates if a client is valid and in-game
bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client));
}


// Helper function to check if arena is 2v2 
bool IsArena2v2_Safe(int arena_index)
{
    MGEArenaInfo info;
    if (!MGE_GetArenaInfo(arena_index, info))
        return false;
    return info.is2v2;
}

// Helper function to get arena player count
int GetArenaPlayerCount_Safe(int arena_index)
{
    MGEArenaInfo info;
    if (!MGE_GetArenaInfo(arena_index, info))
        return 0;
    return info.players;
}

// Helper function to get arena status
int GetArenaStatus_Safe(int arena_index)
{
    MGEArenaInfo info;
    if (!MGE_GetArenaInfo(arena_index, info))
        return 0; // AS_IDLE
    return info.status;
}

// Helper function to get arena game mode
int GetArenaGameMode_Safe(int arena_index)
{
    MGEArenaInfo info;
    if (!MGE_GetArenaInfo(arena_index, info))
        return 0;
    return info.gameMode;
}

// Broadcasts an event to all connected WebSocket clients
void BroadcastToAllClients(JSONObject event)
{
    if (g_hWebSocketServer == null)
        return;
    
    char json[2048];
    event.ToString(json, sizeof(json));
    
    g_hWebSocketServer.BroadcastMessage(json);
}
