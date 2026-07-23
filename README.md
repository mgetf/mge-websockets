# mge-websockets

A SourceMod plugin that exposes real-time MGEMod data over a WebSocket connection. Consumers receive push events the instant something happens in-game and can also issue request/response commands to poll state on demand.

## Requirements

| Dependency | Version |
|---|---|
| **MGEMod** | **≥ 3.1.0-beta28** |
| SourceMod | ≥ 1.12.x |
| [sm-ext-websocket](https://github.com/nicklvsa/sm-ext-websocket) | latest |
| [sm-ripext](https://github.com/ErikMinekus/sm-ripext) | latest |

> MGEMod 3.1.0-beta24 introduced the `MGE_OnArenaScoreChange` forward and `MGE_GetArenaScore` native that this plugin depends on for live score tracking. MGEMod 3.1.0-beta28 introduced the `MGE_OnArenaStatusChange` forward that this plugin depends on for instant, unconditional arena status updates. Earlier versions will fail to load the plugin.

---

## Installation

1. Copy `plugins/mge_websocket.smx` to `addons/sourcemod/plugins/`.
2. Ensure the websocket and ripext SourceMod extensions are installed.
3. Restart the server or `sm plugins load mge_websocket`.
4. The WebSocket server starts automatically 2 seconds after plugin load.

---

## Server ConVars

| ConVar | Default | Description |
|---|---|---|
| `mge_ws_port` | `9001` | TCP port the WebSocket server listens on. Changing this live restarts the server immediately. |
| `mge_ws_secret` | *(empty)* | Shared secret required for all write commands. An **empty value disables write commands entirely** — set this to enable them. |

Both ConVars carry `FCVAR_PROTECTED` and will not appear in `cvarlist` output or RCON queries.

### Example `server.cfg` snippet

```
mge_ws_port   9001
mge_ws_secret "my_lan_production_secret"
```

---

## Connecting

Connect to `ws://<server-ip>:<mge_ws_port>` using any WebSocket client.

On connect you immediately receive a welcome frame:

```json
{
  "type": "welcome",
  "message": "Connected to MGE WebSocket",
  "arenas": 12
}
```

All subsequent messages are UTF-8 JSON.

---

## Message envelope

Every message sent in either direction contains a `type` field:

| `type` | Direction | Meaning |
|---|---|---|
| `response` | server → client | Reply to a request command |
| `event` | server → client | Unsolicited push event |
| `error` | server → client | Command failed or was unauthorized |

---

## Commands (client → server)

Send a JSON object with at minimum a `"command"` field.

### Read-only commands

These require no authentication.

---

#### `get_arenas`

Returns a snapshot of every arena on the current map.

**Request**
```json
{ "command": "get_arenas" }
```

**Response**
```json
{
  "type": "response",
  "command": "get_arenas",
  "arenas": [
    {
      "id": 1,
      "name": "Spire",
      "players": 2,
      "max": 2,
      "status": 3,
      "status_name": "🔥 Fighting",
      "is2v2": false,
      "game_mode": 1,
      "game_mode_names": "🎯 MGE",
      "frag_limit": 20,
      "red_score": 7,
      "blu_score": 5
    }
  ]
}
```

**Arena status values**

| Value | Name |
|---|---|
| 0 | Idle |
| 1 | Pre-Countdown |
| 2 | Countdown |
| 3 | Fighting |
| 4 | After Fight |
| 5 | Reported |
| 6 | Waiting Ready (2v2) |

**Game mode bitmask flags**

| Bit | Mode |
|---|---|
| 0 (1) | MGE |
| 1 (2) | BBall |
| 2 (4) | KOTH |
| 3 (8) | Ammomod |
| 4 (16) | Midair |
| 5 (32) | Endif |
| 6 (64) | Ultiduo |
| 7 (128) | Turris |
| 8 (256) | 2v2 |

---

#### `get_arena_details`

Returns full slot-level detail for one arena.

**Request**
```json
{ "command": "get_arena_details", "arena_id": 1 }
```

**Response**
```json
{
  "type": "response",
  "command": "get_arena_details",
  "arena_id": 1,
  "arena_name": "Spire",
  "players": 2,
  "max_slots": 2,
  "status": 3,
  "status_name": "🔥 Fighting",
  "is_2v2": false,
  "game_mode": 1,
  "game_mode_names": "🎯 MGE",
  "frag_limit": 20,
  "red_score": 7,
  "blu_score": 5,
  "slots": [
    {
      "slot": 1,
      "valid": true,
      "occupied": true,
      "steam_id": "76561198012345678",
      "player_name": "Alice"
    },
    {
      "slot": 2,
      "valid": true,
      "occupied": true,
      "steam_id": "76561198087654321",
      "player_name": "Bob"
    }
  ]
}
```

For 2v2 arenas each occupied slot also includes `"ready": bool`.

---

#### `get_players`

Returns all non-bot players currently on the server.

**Request**
```json
{ "command": "get_players" }
```

**Response**
```json
{
  "type": "response",
  "command": "get_players",
  "players": [
    {
      "steam_id": "76561198012345678",
      "name": "Alice",
      "arena": 1,
      "inArena": true,
      "elo": 1450,
      "rating": 1450.0,
      "wins": 120,
      "losses": 80
    }
  ]
}
```

Players in a 2v2 arena additionally include:
```json
{
  "ready": true,
  "teammate": "Bob",
  "teammate_steam_id": "76561198087654321"
}
```

---

#### `get_player_stats`

Returns detailed stats for one player identified by SteamID64.

**Request**
```json
{ "command": "get_player_stats", "steam_id": "76561198012345678" }
```

**Response**
```json
{
  "type": "response",
  "command": "get_player_stats",
  "steam_id": "76561198012345678",
  "player_name": "Alice",
  "stats": {
    "elo": 1450,
    "kills": 980,
    "deaths": 860,
    "wins": 120,
    "losses": 80,
    "rating": 1450.0,
    "total_matches": 200,
    "win_percentage": 60.0,
    "kdr": 1.14
  },
  "current_arena": 1,
  "in_2v2": false
}
```

`stats` is omitted and an `"error"` string is set instead when the database is unavailable or the player has no recorded stats.

---

#### `get_server_status`

Returns aggregate server and arena statistics.

**Request**
```json
{ "command": "get_server_status" }
```

**Response**
```json
{
  "type": "response",
  "command": "get_server_status",
  "max_clients": 32,
  "current_clients": 18,
  "arena_count": 12,
  "hostname": "mge.example.com",
  "current_map": "mge_training_v8_beta4b",
  "total_players_in_arenas": 14,
  "active_fights": 6,
  "ready_phases": 1,
  "game_mode_stats": [
    { "name": "MGE",  "count": 8 },
    { "name": "BBall","count": 2 },
    { "name": "2v2",  "count": 2 }
  ]
}
```

---

### Write commands

Write commands mutate server state. They require a `"secret"` field matching the `mge_ws_secret` ConVar. If the ConVar is empty or the secret doesn't match, the server responds with:

```json
{ "type": "error", "message": "Unauthorized: valid 'secret' required for write commands" }
```

All write requests share the same envelope:
```json
{
  "command": "<command_name>",
  "secret": "my_lan_production_secret",
  ...
}
```

---

#### `add_player_to_arena`

Moves a player into an arena without showing any in-game menu.

**Request fields**

| Field | Type | Required | Description |
|---|---|---|---|
| `steam_id` | string | Yes | SteamID64 of the player to add |
| `arena_id` | integer | Yes | Target arena index |
| `slot` | integer | No | Explicit slot (1–4). Overrides `team`. |
| `team` | string | No | `"red"` or `"blu"`. Only meaningful for 2v2 arenas; ignored for 1v1. |
| `secret` | string | Yes | Write secret |

When neither `slot` nor `team` is supplied the server auto-assigns the first open slot.

**Slot layout for 2v2 arenas**

| Slot | Team |
|---|---|
| 1, 3 | RED |
| 2, 4 | BLU |

**Success response**
```json
{
  "type": "success",
  "message": "Player added to arena successfully",
  "steam_id": "76561198012345678",
  "player_name": "Alice",
  "arena_id": 1
}
```

**Failure response**
```json
{
  "type": "error",
  "message": "Red team slots are full",
  "steam_id": "76561198012345678",
  "arena_id": 1
}
```

Possible error messages: `"Invalid or missing steam_id"`, `"Invalid arena ID"`, `"Invalid 'team' value: use 'red' or 'blu'"`, `"Red team slots are full"`, `"Blu team slots are full"`, `"Failed to add player to arena"`.

---

#### `remove_player_from_arena`

Removes a player from whatever arena they are currently in.

**Request**
```json
{
  "command": "remove_player_from_arena",
  "steam_id": "76561198012345678",
  "secret": "my_lan_production_secret"
}
```

**Success response**
```json
{
  "type": "success",
  "message": "Player removed from arena successfully",
  "steam_id": "76561198012345678",
  "player_name": "Alice",
  "arena_id": 1
}
```

---

#### `set_player_ready`

Sets the ready state for a player in a 2v2 arena's pre-match ready phase.

**Request**
```json
{
  "command": "set_player_ready",
  "steam_id": "76561198012345678",
  "ready": true,
  "secret": "my_lan_production_secret"
}
```

**Success response**
```json
{
  "type": "success",
  "message": "Player marked as ready",
  "steam_id": "76561198012345678",
  "player_name": "Alice",
  "arena_id": 3,
  "ready": true
}
```

Fails with an error if the player is not in a 2v2 arena.

---

## Push events (server → all clients)

Events are broadcast to **every** connected client the instant they occur. No subscription model exists — filter client-side by `arena_id` or `steam_id` if needed.

Every event shares a common envelope:

```json
{
  "type": "event",
  "event": "<event_name>",
  "arena_id": 1,
  "timestamp": 1719432000
}
```

`timestamp` is a Unix epoch integer (seconds).

---

### `player_arena_added`

Fired when any player joins or is placed into an arena slot.

```json
{
  "type": "event",
  "event": "player_arena_added",
  "steam_id": "76561198012345678",
  "player_name": "Alice",
  "arena_id": 1,
  "slot": 1,
  "timestamp": 1719432000
}
```

---

### `player_arena_removed`

Fired when a player leaves or is removed from an arena.

```json
{
  "type": "event",
  "event": "player_arena_removed",
  "steam_id": "76561198012345678",
  "player_name": "Alice",
  "arena_id": 1,
  "timestamp": 1719432001
}
```

---

### `match_start_1v1`

Fired when a 1v1 countdown completes and fighting begins. Also immediately followed by a `score_update` event with 0–0 scores.

```json
{
  "type": "event",
  "event": "match_start_1v1",
  "arena_id": 1,
  "player1_steam_id": "76561198012345678",
  "player1_name": "Alice",
  "player2_steam_id": "76561198087654321",
  "player2_name": "Bob",
  "timestamp": 1719432005
}
```

---

### `match_end_1v1`

Fired when a 1v1 match concludes.

```json
{
  "type": "event",
  "event": "match_end_1v1",
  "arena_id": 1,
  "winner_steam_id": "76561198012345678",
  "winner_name": "Alice",
  "loser_steam_id": "76561198087654321",
  "loser_name": "Bob",
  "winner_score": 20,
  "loser_score": 14,
  "timestamp": 1719432120
}
```

---

### `match_start_2v2`

Fired when a 2v2 match begins. Also immediately followed by a `score_update` event with 0–0 scores.

Team 1 occupies RED slots (1, 3); team 2 occupies BLU slots (2, 4).

```json
{
  "type": "event",
  "event": "match_start_2v2",
  "arena_id": 3,
  "team1_player1_steam_id": "76561198000000001",
  "team1_player1_name": "Alice",
  "team1_player2_steam_id": "76561198000000002",
  "team1_player2_name": "Charlie",
  "team2_player1_steam_id": "76561198000000003",
  "team2_player1_name": "Bob",
  "team2_player2_steam_id": "76561198000000004",
  "team2_player2_name": "Dave",
  "timestamp": 1719432005
}
```

---

### `match_end_2v2`

Fired when a 2v2 match concludes.

```json
{
  "type": "event",
  "event": "match_end_2v2",
  "arena_id": 3,
  "winning_team": 2,
  "winning_score": 20,
  "losing_score": 11,
  "team1_player1_steam_id": "76561198000000001",
  "team1_player1_name": "Alice",
  "team1_player2_steam_id": "76561198000000002",
  "team1_player2_name": "Charlie",
  "team2_player1_steam_id": "76561198000000003",
  "team2_player1_name": "Bob",
  "team2_player2_steam_id": "76561198000000004",
  "team2_player2_name": "Dave",
  "timestamp": 1719432180
}
```

`winning_team` is `1` or `2` corresponding to the team numbering above.

---

### `score_update`

Fired every time a team's score changes during an active match. Also fired with 0–0 values at the start of every match (both 1v1 and 2v2) so consumers can initialize scoreboard state without polling.

```json
{
  "type": "event",
  "event": "score_update",
  "arena_id": 1,
  "arena_name": "Spire",
  "red_score": 8,
  "blu_score": 5,
  "frag_limit": 20,
  "timestamp": 1719432060
}
```

For 1v1 arenas `red_score` maps to slot 1 (the first player) and `blu_score` maps to slot 2.
For 2v2 arenas `red_score` is team 1 (slots 1, 3) and `blu_score` is team 2 (slots 2, 4).

---

### `arena_status_change`

Fired whenever an arena's status changes, for any reason. This is a real push forward
(`MGE_OnArenaStatusChange`) that MGEMod calls from a single setter every time it writes an
arena's status, so it fires instantly with no polling latency and reliably catches transitions
that `player_arena_removed` and the match-end events can miss, such as a player leaving
mid-fight with no one else queued.

```json
{
  "type": "event",
  "event": "arena_status_change",
  "arena_id": 1,
  "arena_name": "Spire",
  "old_status": 3,
  "old_status_name": "🔥 Fighting",
  "status": 0,
  "status_name": "🟢 Idle",
  "players": 0,
  "max": 2,
  "timestamp": 1719432140
}
```

See [`get_arenas`](#get_arenas) for the full list of `status` values.

---

### `arena_player_death`

Fired on every in-arena kill. `attacker_steam_id` is an empty string for environmental deaths.

```json
{
  "type": "event",
  "event": "arena_player_death",
  "victim_steam_id": "76561198087654321",
  "victim_name": "Bob",
  "attacker_steam_id": "76561198012345678",
  "attacker_name": "Alice",
  "arena_id": 1,
  "timestamp": 1719432058
}
```

---

### `player_elo_change`

Fired after a match is reported to the database and ELO has been recalculated.

```json
{
  "type": "event",
  "event": "player_elo_change",
  "steam_id": "76561198012345678",
  "player_name": "Alice",
  "old_elo": 1420,
  "new_elo": 1450,
  "elo_change": 30,
  "arena_id": 1,
  "timestamp": 1719432125
}
```

Not fired when the server has no database configured.

---

### `2v2_ready_start`

Fired when all four players are slotted in a 2v2 arena and the ready-up phase begins.

```json
{
  "type": "event",
  "event": "2v2_ready_start",
  "arena_id": 3,
  "timestamp": 1719432000
}
```

---

### `2v2_player_ready`

Fired each time a player toggles their ready state during the 2v2 ready phase.

```json
{
  "type": "event",
  "event": "2v2_player_ready",
  "steam_id": "76561198012345678",
  "player_name": "Alice",
  "arena_id": 3,
  "ready_status": true,
  "timestamp": 1719432003
}
```

---

## Player identification

All player references use **SteamID64** strings (e.g. `"76561198012345678"`). This format is stable across name changes and is directly usable with the Steam Web API.

---

## Error responses

Any failed command returns:

```json
{ "type": "error", "message": "<human-readable reason>" }
```

Common messages:

| Message | Cause |
|---|---|
| `Unauthorized: valid 'secret' required for write commands` | Write command sent without a correct `secret` field, or `mge_ws_secret` is empty |
| `Invalid or missing steam_id` | `steam_id` absent, malformed, or player not currently on the server |
| `Invalid arena ID` | `arena_id` is 0, negative, or refers to a non-existent arena |
| `Invalid JSON format` | Malformed JSON received |
| `Missing 'command' field` | JSON object has no `command` key |
| `Unknown command` | Unrecognized `command` value |
| `Red team slots are full` | Both RED slots (1 and 3) in a 2v2 arena are occupied |
| `Blu team slots are full` | Both BLU slots (2 and 4) in a 2v2 arena are occupied |
| `Invalid 'team' value: use 'red' or 'blu'` | `team` field contained an unrecognized string |

---

## Suggested consumption patterns

### Live scoreboard (read-only)

1. On connect, send `get_arenas` to populate initial state.
2. Listen for `match_start_1v1` / `match_start_2v2` to open a score card — a `score_update` with 0–0 is always emitted immediately after.
3. Update the card on each `score_update`.
4. Close the card on `match_end_1v1` / `match_end_2v2`, or on `arena_status_change` when `status` drops below `AS_FIGHT` (3). Prefer this over `player_arena_removed` for detecting an aborted fight — that event is not always fired when a player leaves mid-match, while `arena_status_change` always is.
5. Optionally poll `get_arenas` every few seconds as a fallback sync.

### LAN production overlay (read-only)

Same pattern as the live scoreboard. Filter `score_update` by `arena_id` to target a specific featured match. Use `arena_player_death` for kill-feed overlays.

### Remote arena management (write)

Set `mge_ws_secret` to a strong random string in `server.cfg`. Keep the secret server-side in your management tool; never expose it in a client-side browser application.

---

## Admin console commands

| Command | Access | Description |
|---|---|---|
| `mge_ws_start` | `ADMFLAG_ROOT` | Start the WebSocket server (auto-starts on plugin load) |
| `mge_ws_stop` | `ADMFLAG_ROOT` | Stop the WebSocket server |

---

## Test client

`mge_websocket_test.html` is a self-contained browser page that demonstrates the full API. Open it in any modern browser, enter the server URL and write secret, and connect. It provides:

- Live arena score cards updated by `score_update` push events
- A score event feed log
- Arena table with game-mode filtering
- Player list with per-player stats and inline arena management
- Modals for adding players to arenas with team selection for 2v2
