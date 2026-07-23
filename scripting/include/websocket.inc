#if defined _websocket_included
  #endinput
#endif
#define _websocket_included

/**
 * Trimmed vendored copy of sm-ext-websocket's barrel include.
 *
 * Upstream also pulls in <json> (for JSON-mode WebSocket/HTTP helpers) and websocket/http.
 * This plugin is a WebSocket server only, always in WebSocket_STRING mode (JSON is handled
 * via ripext, see scripting/include/websocket/ws_client.inc), so none of those are needed
 * here and are intentionally left out to avoid a JSON methodmap collision with ripext.
 */
#include <websocket/ws_client>
#include <websocket/ws_server>

public Extension __ext_websocket = {
  name = "websocket",
  file = "websocket.ext",
#if defined AUTOLOAD_EXTENSIONS
  autoload = 1,
#else
  autoload = 0,
#endif
#if defined REQUIRE_EXTENSIONS
  required = 1,
#else
  required = 0,
#endif
};
