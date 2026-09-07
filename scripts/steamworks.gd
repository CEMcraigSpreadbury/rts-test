extends Node
## Initializes the Steamworks API for Quick Play / Steam lobby matchmaking
## (see Network autoload). Uses Valve's public test AppID 480 ("Spacewar")
## during development so real cross-internet testing works without owning a
## real AppID yet or paying the Steam Direct fee — see
## https://godotsteam.com/tutorials/initializing/. Swap APP_ID to the real
## one once the game has an AppID and is ready to publish; nothing else
## needs to change.
const APP_ID: int = 480

var is_available: bool = false
var steam_id: int = 0
var steam_username: String = ""

func _init() -> void:
	OS.set_environment("SteamAppId", str(APP_ID))
	OS.set_environment("SteamGameId", str(APP_ID))

func _ready() -> void:
	var response: Dictionary = Steam.steamInitEx(APP_ID, true)
	is_available = response.get("status", 1) == 0
	if not is_available:
		push_warning("Steam did not initialize (Quick Play / Steam lobbies unavailable): %s" % response.get("verbal", "unknown error"))
		return
	steam_id = Steam.getSteamID()
	steam_username = Steam.getPersonaName()
