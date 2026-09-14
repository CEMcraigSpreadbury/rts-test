# Quests, Scenarios & Campaign — Implementation Plan

Handover document. The design below was agreed with the project owner on
2026-09-14; treat the "Settled decisions" as fixed unless the owner changes
them. Work proceeds one build step at a time: finish a step, give the owner a
short test list, and wait for "continue" before starting the next.

References for feel: Warcraft 3 campaign + World Editor, Battle for
Middle-earth.

## Goal

A quest system (tracker UI, steps with prerequisites, several steps can be
required before progress) used to build a set of tutorial scenarios and a short
campaign. Campaign missions can change costs, available units/buildings/shrine
monsters, and starting buildings/units. Scenarios must also work in multiplayer
co-op: every human on one team, sharing the same quest steps, completed
together. Missions are authored in the Godot editor through a dock (like the
existing MapGenerator tool). Keep it lean — no systems beyond what is listed.

## Settled decisions

- **Step flow:** each step lists the steps it requires. A step activates once
  all of those are complete, so several can be active at once. Linear,
  parallel ("do A and B, then C") and branching flows all come from this.
- **Step contents:** title, `optional` and `hidden` flags, `requires[]`,
  `conditions[]` with an ALL/ANY completion rule, `fail_conditions[]`, and
  `on_start[]` / `on_complete[]` / `on_fail[]` actions.
- **Co-op:** each player has their own base, resources and army. Players are
  allied and share vision. Quest counts add up across the whole team.
- **Enemies:** three kinds: a full AI opponent (the existing AiPlayer, possibly
  restricted by modifiers), pre-placed defenders that hold their ground, and
  scripted waves spawned by actions. There is no dormant AI, but an action can
  switch an AI slot's mode (normal / defend only / attack a target).
- **Conditions (v1):**
  - Economy: have/train N units, build N buildings, gather or hold N of a
    resource, reach population N.
  - Location and combat: units in a zone (N units or one specific unit),
    destroy specific targets, kill N enemies, eliminate a slot.
  - Conquest: capture or hold a point (optionally for X seconds), survive X
    seconds, team reaches N Favour.
  - Timers: a deadline that fails the step.
  - Tutorial input: select units, move or rotate the camera, use a hotkey,
    open the research panel, buy a node, cast a power, use formations or
    control groups.
- **Actions (v1):**
  - Units and resources: spawn units or waves at a marker for a slot (with an
    optional attack-move target), give or take resources, transfer ownership
    of placed units/buildings.
  - Rules: lock or unlock buildings, units, shrine monsters, research tiers and
    HUD features.
  - Story and camera: dialogue line, **Show Briefing** (mid-mission briefing
    for storytelling), camera pan, minimap ping, reveal a fog area, world
    marker, UI highlight.
  - AI: set an AI slot's mode.
  - Outcome: win or lose the mission.
- **Presentation:**
  - A briefing screen before each mission (title, story text, starting
    objectives, Ruler pick, difficulty, Start).
  - A dialogue box: speaker name, portrait, text, auto-advances, and the game
    keeps running. In single player, lines marked for it pause the game until
    dismissed.
  - Mid-mission briefings pause in single player. In multiplayer each player
    sees their own overlay and the game keeps running.
- **Portraits:** each dialogue line has an optional portrait texture. When it
  is empty, the line names a speaker unit scene and the portrait is an
  auto-crop of that unit's head: the top part of its first idle frame, cut
  from its sprite sheet the same way `SpriteSheetFrames` builds `AtlasTexture`s.
- **Defeat:**
  - The whole team loses every main base (a single co-op player losing theirs
    is just knocked out, as now).
  - A key unit or building dies.
  - A deadline runs out.
  - A step fails; the scenario decides the consequence through `on_fail`
    actions.
- **Carry-over:** nothing carries between missions.
- **Rulers:** the player picks one on the briefing screen. The scenario can cap
  research tiers, disable research, or lock it until a step unlocks it.
- **Favour:** there is no Favour-race win in scenarios by default. "Team
  reaches N Favour" is available as a condition, and a scenario can turn
  Favour off entirely. Capture points still pay gold and research points.
- **Empty human slots** in a co-op scenario are filled by an allied AI.
- **Difficulty:** Easy/Normal/Hard, picked per mission. It sets the enemy AI
  difficulty and scales scripted wave sizes and enemy starting resources
  (0.7 / 1.0 / 1.4).
- **Progress:** the main menu gets Tutorial and Campaign entries, each an
  ordered mission list where winning unlocks the next. Progress is saved in
  `user://`.
- **Multiplayer:** the lobby gets a Campaign game mode. The host picks from the
  missions they have unlocked, and a win unlocks it for every human who played.
- **Team skirmish:** in normal matches players may pick the same colour, and
  the same colour means the same team (team = colour index, max 4 teams).
  Start is refused if everyone is on one team.

## Architecture

### Scenario scene

A scenario is a scene that **inherits a map scene** (`scenes/maps/*.tscn`) and
adds one `Scenario` node:

```
Scenario                (scripts/quests/scenario.gd)
├─ Slots/               ScenarioSlot nodes: kind (HUMAN / ENEMY_AI / DEFENDERS),
│   │                   team, colour, AI difficulty, AI ruler, spawn point index
│   │                   (or none), starting resources, per-slot modifiers
│   └─ <units/buildings placed as children start owned by that slot>
├─ Zones/               ScenarioZone (position + radius, circle gizmo in the editor)
├─ Markers/             Marker3D-style points: spawn spots, camera targets, world markers
└─ Quests/
    └─ QuestStep ...    see "Step contents" above
```

`ScenarioInfo` (.tres in `resources/scenarios/`, modelled on `MapInfo`) holds
the name, scene path, briefing title/text, human slot count and an id.
`Campaign` (.tres in `resources/campaigns/`) is an ordered
`Array[ScenarioInfo]`. There are two: `tutorial.tres` and `campaign.tres`.

### Extensibility

`QuestCondition` and `QuestAction` are Resource base classes. Each type is one
subclass script in `scripts/quests/conditions/` or `scripts/quests/actions/`.
The editor dock finds types by scanning those folders, so adding a type means
adding one script and nothing else.

### MatchRules

A single object on Main that every system asks: cost multipliers,
allowed/locked sets (buildings, units, shrine monsters, research tiers, HUD
features), per-slot starting setup, population cap, Favour on/off. Skirmish
uses the defaults, which change nothing. Hook points:

- `ProductionBuilding.costs_for` (already query-time with research discounts)
  and building placement costs.
- The HUD build and produce lists: filter them.
- `ShrineObjective._fresh_roll`: restrict to the allowed monster pool.
- `Research.requirements_met`: tier cap and locks.
- `Main._spawn_player_base`: starting units, buildings and resources from the
  slot instead of `Faction`.

### QuestRunner

A host-only component on Main, the same pattern as `Research`:

- Conditions that describe the current state (unit counts, units in a zone,
  holding a point) are polled about 4 times a second.
- Conditions about things happening listen to an event bus that Main and other
  systems emit: unit trained, building completed, unit killed, point captured,
  node bought, power cast, tutorial input.
- Tutorial input happens on the client and is sent to the host by RPC.
- Step states and progress are broadcast to all peers as compact snapshots.
- Client-side actions (dialogue, briefing, camera, highlight, marker, ping)
  are sent by RPC to the humans on the player team.

### Teams layer (a prerequisite for co-op and team skirmish)

Today every hostility check is an inline `owner_peer_id != x` test: about 75
places in 14 files (unit.gd, main.gd, ai/*, combat_utils.gd, objective.gd,
research.gd, fog_of_war.gd, world_feedback.gd, minimap.gd,
building_placement.gd, ability_zone.gd, conquest_hud.gd). The changes:

- Add `team` to `Network.players`.
- Add one static `is_enemy(a, b)` helper. Peer 0 (neutral guards) is hostile
  to everyone, and a peer is never an enemy of itself.
- Replace every hostility test with that helper. Tests meaning "is this *mine*"
  (command rights, selection) stay as ownership checks.
- Fog: something is visible if any unit or building of an ally can see it.
- Objectives: allies can't capture points from each other. Capture counts
  whole teams.
- AI: targets and threat estimates only count enemies.
- Victory and scores go by team. The Conquest HUD shows one bar per team.

### Editor dock (`addons/scenario_editor/`)

- **New Scenario:** pick a map (from `MapInfo.list_all()`) and a name. It
  writes `scenes/scenarios/<id>.tscn` inheriting the map, with a skeleton
  `Scenario` node (one HUMAN slot per spawn point), plus a `ScenarioInfo`.
- **Step list** for the open scenario: add, remove, rename, reorder, and
  requires checkboxes. Adding a condition or action uses a type dropdown; its
  fields are edited in the normal inspector.
- **Pick in viewport** fills NodePath fields (zone, target, marker) by clicking
  in the 3D view. Zones draw as circles.
- **Validate** reports broken NodePaths, prerequisite cycles, steps that can
  never activate, and missions with no win action.
- **Play** runs the scenario directly on the single player offline path.

### UI

- **Quest tracker** (top-right): active, non-hidden steps with progress
  ("2/5") and countdowns. Completed steps tick and fade; failed steps show red;
  optional steps are marked.
- **Dialogue box** above the bottom bar.
- **Briefing screen**, used both before a mission and mid-mission.
- **World markers, UI highlight pulse, minimap ping.**

Respect the owner's standing rule: no extra tooltips, hints or explanatory UI
text beyond what the quests themselves provide.

## Story — *The Shadow Returns*

For three hundred years the kingdom of **Aldmere** has lived in the Long Peace.
The forts along its borders have become farmland, the beacon towers have gone
dark, and only three old offices still hold the realm together: the Warlord,
the Steward and the Mystic (the three Rulers). The peace began when the **Dark
Lord Vorgrath** (the existing Dark Lord monster unit) was beaten and sealed
beneath the Ashen Peaks. The seal has weakened, and now he is waking. The
Beastmen of the wild woods (the existing beastmen units), who once served him,
are heeding his call again.

**Tutorials — *The Long Peace*.** These are the peaceful prologue, where the
player is a young lord in training. There are five:

1. Basics: camera, selection, movement, attack.
2. Economy: gathering, houses, mines, villagers.
3. Army: barracks, training, formations, control groups, attacking an outpost.
4. Conquest and shrines: capture points, shrines, monsters.
5. Rulers: the research panel, buying a node, casting a power.

Each ends with a hint that something is wrong (a dead grove, a far-off fire, a
tremor under the mountains). The last ends on a mid-mission briefing: "The
beacon on the eastern border is lit."

**Campaign:**

| # | Mission | What happens | What it uses |
|---|---|---|---|
| 1 | Embers on the Border | Beastmen raid a border village. Rebuild it, hold out against the raiding waves, then burn their camp. | Economy, waves, a key building that must survive, restricted roster (no cavalry) |
| 2 | The Watchfires | Relight the old beacon towers (capture points) while a Beastmen AI competes for them. The last beacon brings a mid-mission briefing: the Dark Lord is free. | Capture/hold, Favour as a condition, an AI that switches from defending to attacking |
| 3 | The Druids' Grove | Escort the Mystic's envoy to the corrupted shrine and cleanse it, which frees the Phoenix to recruit. | A key unit that must not die, zones, shrine monster unlocks, reveal and camera pan |
| 4 | The Siege of Aldmere | A Skeleton Dragon leads the siege of the capital. Survive until the relief army arrives, then break the siege. | Survive timer, waves, spawned reinforcements, pre-placed walls and towers |
| 5 | The Ashen Peaks | Storm Vorgrath's fortress and kill him before his ritual finishes. | Pre-placed defenders, a full AI, a specific target to destroy, a deadline that fails the mission |

All five are co-op capable: player 2 plays a neighbouring lord's base, and an
allied AI takes it when solo. Costs get tighter and enemy starts grow as the
campaign goes on, using the modifier system.

## Build order

Pause after each step for the owner to playtest.

1. **Teams layer.** Team per player, `is_enemy` helper replacing every
   hostility test, allied vision, team-aware objectives, AI, victory and HUD.
   In the lobby and single player setup, a shared colour means a shared team.
   Headless test: two allied AIs against one enemy AI; free-for-all unchanged.
2. **MatchRules + scenario data.** Scenario/ScenarioSlot/Zone/Marker nodes,
   placed units owned per slot, modifiers applied, a Scenario game mode, and
   a way to load a scenario scene.
3. **Quest core.** QuestStep, the QuestCondition/QuestAction bases and v1
   types, QuestRunner, the event bus, win/lose rules.
4. **Presentation.** Quest tracker, dialogue box with portraits (sprite-sheet
   head crop fallback), Show Briefing, camera pan, ping, reveal, world markers.
5. **Editor dock.**
6. **Enemies.** AI slot modes, defenders holding ground, scripted waves,
   difficulty scaling.
7. **Tutorial support.** Input conditions, UI highlight, HUD locks, pause on
   messages.
8. **Campaign flow.** Campaign resources, menu mission lists, briefing screen,
   saved progress.
9. **Multiplayer.** Lobby Campaign mode, allied AI fill, two-process co-op test.
10. **Content.** Five tutorials, then the five campaign missions, built with
    the dock.

## Appendix A — Step 1 work list (teams)

### Rules

- `Network.players[id]["team"]`: derived from the chosen colour index, so two
  players on the same colour are allies. AI slots follow the same rule.
- `Teams.is_enemy(a, b)`: `false` when `a == b` or both are on the same team;
  `true` when either is peer 0 (neutral guards are hostile to everyone) or the
  teams differ. Place it where both Main and the AI can reach it without a
  Main lookup (a static helper on a small `Teams` class).
- Lobby and single player setup: stop forcing unique colours
  (`Network.available_color_indices` / `_color_holder` /
  `_apply_color_change`), and refuse Start when every player is on one team.
- Victory: `Main.defeated_peers` and `_check_for_game_over` judge teams, not
  peers. A player with no main base left is still knocked out individually,
  but the team survives while any member holds one. Conquest scores and the
  Conquest HUD aggregate per team.

### Call sites

Every hostility test today is an inline `owner_peer_id` comparison. Line
numbers are from 2026-09-14 and will drift.

**Becomes `is_enemy` (or ally-aware):**

| File | Lines | What it is |
|---|---|---|
| `unit.gd` | 1611, 2465, 2733, 2761 | target search and retaliation |
| `unit.gd` | 1420 | ally cohesion — should include allies |
| `combat_utils.gd` | 26, 65 | ally defence search, nearest enemy |
| `ai/ai_combat.gd` | 189, 248, 262, 269, 315, 448, 532, 616, 620 | hostile scans, wave targets, point ownership |
| `objective.gd` | 184, 231, 239, 245, 291 | capture: allies must not flip each other's points |
| `fog_of_war.gd` | 228, 255, 372, 377 | vision sources and visibility — allies share |
| `minimap.gd` | 89, 101 | own/enemy blip colour — allies get the ally colour |
| `world_feedback.gd` | 947, 948 | attack cursor over a target |
| `main.gd` | 1476, 1483, 1500, 1791, 1805 | order target resolution and smart commands |
| `ability_zone.gd` | 51 | skips its own units; must skip allies |
| `conquest_hud.gd` | 208 | "owned by me" slot frame |
| `research.gd` | 156 | kill credit — no research points for killing an ally |

**Stays an ownership test** (these mean "mine", not "friendly"): all of
`building_placement.gd`; `main.gd` command validation and selection (1115,
1304, 1334, 1349, 1378, 1410, 1457, 1558, 1640, 1745, 1835, 1857, 1935, 1995,
2068, 2093, 2108, 2136, 2201); `ai/ai_player.gd` 155, 165, 303;
`ai/ai_economy.gd` 273; `unit.gd` 236, 2343; `research.gd` 315, 334, 344, 443,
446 (research effects are per player, not per team); `world_feedback.gd` 363,
674, 736, 766; `production_building.gd` 497; `combat_utils.gd` 116 (monarch
aura).

### Test list for step 1

- Free-for-all skirmish is unchanged: AI still fights everyone, capture and
  victory behave as before.
- Two players on one colour: allied units ignore each other, vision is shared,
  neither can capture the other's points, and the match ends only when both
  lose their bases.
- Headless: two allied AIs against one enemy AI; the pair should win.
- Start is refused when every slot shares a colour.

## Status

- 2026-09-15: **step 10 started — the first three tutorial missions exist**,
  awaiting playtest. They live in the one Campaign, ahead of the co-op mission:
  1. **First Steps** (`t01_first_steps.tscn`) — move the view, select
     villagers, walk three of them into a marked ring. Everything but movement
     is locked away.
  2. **The Woodcutters** (`t02_the_woodcutters.tscn`) — gather 120 wood, raise
     a House (build unlocked, action panel highlighted), train two villagers.
  3. **Blades for the Border** (`t03_blades_for_the_border.tscn`) — build a
     Barracks, train three soldiers (which unlocks formations and control
     groups), then destroy three placed Beastmen raiders leashed to their camp.
  Each is short, teaches through its dialogue rather than tooltips, and every
  line waits for Continue. Missions are one `.tscn` plus one `ScenarioInfo`
  `.tres` listed in `resources/campaigns/campaign.tres`; the sandbox scenes
  remain on disk but are no longer listed.
  **Bug found and fixed by building them:** the quest's first evaluation ran
  before `QuestUi` existed, so every mission's *opening* line was announced to
  nothing and lost. `Main._ready` now builds the quest UI before
  `quests.setup()`; the opening line queues behind the briefing and plays when
  it is closed.
  Verified: all four missions load with the right steps, prerequisites, HUD
  locks, zones and placed units; each opens with its line, speaker and
  sprite-sheet portrait. "First Steps" was played through end to end —
  briefing, three steps with their lines, closing line, Victory, and the win
  written to campaign progress.
- 2026-09-15: the victory screen offers **"Next: <mission>"** when the mission
  just won has another after it (`Campaign.next_mission_after`,
  `Main._offer_next_mission`), so a player carries straight on instead of
  walking back through the menus. Single player only — in co-op one player
  cannot decide what everyone plays next. Verified: winning First Steps shows
  the button and pressing it loads The Woodcutters with its own quest.
- 2026-09-15: zone placement is eyeballed at your peril — "First Steps" put its
  ring **inside a wood** (1.0 units from the nearest tree). Positions are now
  chosen by measuring: a headless sweep of the map's gatherables and scenery
  for the clearest spot in a band of distances from the player's base. The ring
  moved to (-22, 0, 40) with 7.1 units of clearance, and the raiders' camp in
  "Blades for the Border" to (-32, 0, 4) with 9.3. Placing a zone by hand in
  the editor is fine too — that is what the Scenario dock's zone gizmo is for —
  but check it against the trees.

- 2026-09-14: design agreed and documented.
- 2026-09-14: **step 1 (teams layer) implemented**, awaiting playtest.
  `scripts/teams.gd` holds `Teams.team_of / is_enemy / is_friendly /
  peers_on_team / teams_of / team_color`. A team is the colour index + 1, so
  sharing a colour is sharing a side; an explicit `"team"` in
  `Network.players` overrides that (what scenarios will set), and a peer with
  no lobby entry gets the private team `-(peer + 1)`.
  Colours are no longer unique (`available_color_indices` returns all,
  `_apply_color_change` lost its veto); `Network.can_start_match()` gates both
  Start buttons. `Main.scores` is now keyed by **team**
  (`{score, active, tint}`, see `_team_scores`), victory and `_rpc_game_over`
  work in teams with `Main.DRAW` for no winner, and ConquestHud draws one bar
  per team. Objective capture counts per team (`team_rep` names the player who
  ends up owning the point) and a point never changes hands inside a team.
  Fog shares allied vision; the minimap draws allies through the fog but
  outlines only your own. Ruler powers treat allies as friendly, including
  casting vision. Kept deliberately as ownership, not team:
  `CombatUtils.alert_nearby_allies` (it would command a teammate's army),
  research effects, per-player unit limits, gather rights, and every command
  or selection check.
  Verified headless (two allied Hard AIs vs one, Four Kingdoms, ~7 match
  minutes): zero units ever ordered onto a friendly target, allies each held
  their own point with neither flipping the other's, and the score snapshot
  carried exactly two teams with their members' Favour added together. The
  Start gate refuses a lobby where everyone shares a colour and allows a lone
  player. Still unverified: a real two-human co-op session, and the allied
  pair actually winning a full match.
  Known gap: spawn points are still handed out at random, so allies can start
  on opposite corners of a skirmish map. Scenarios will place spawns
  explicitly, so this was left alone.
- 2026-09-14: **step 2 (MatchRules + scenario data) implemented**, awaiting
  playtest. New: `scripts/match_rules.gd`, `scripts/scenario/scenario.gd`,
  `scenario_slot.gd`, `scenario_zone.gd`, `scenario_modifiers.gd`,
  `scenario_info.gd`.
  A scenario scene is an ordinary map plus a `Scenario` node — there is no
  mode flag. The node installs `MatchRules.current` in `_enter_tree` (Main
  clears it there first), so prices and rosters are right before any `_ready`
  runs, which is what a Shrine's monster roll needs.
  `Scenario.resolve_players()` maps slots to peers identically on every
  machine (humans by sorted peer id with the host first, other sides taking
  the lowest free small peer id, "random" Rulers picked from the slot index),
  so no part of the mapping is networked. Sides the scenario invents get a
  normal `Network.players` entry marked `"scenario": true`, with the slot's
  explicit team.
  `Main` gained `scenario` / `scenario_peer_by_slot`,
  `_apply_scenario_modifiers`, `_adopt_scenario_entities` (every peer:
  hand-placed units/buildings get their owner and colour, are renamed
  `Slot<N>_<name>` and reparented into Units/Buildings so the AI, fog and
  minimap see them), `_register_placed_building`, and `_spawn_scenario_sides`
  (host: starting resources, starting base from the slot's own lists, an AI
  brain only for ENEMY_AI). DEFENDERS sides deliberately never enter
  `main_base_count_by_peer`, so wiping a garrison is not a win condition.
  Modifiers are enforced at: `ProductionBuilding.costs_for` and `enqueue`,
  `BuildingPlacement.costs_for` + the build/wall/gate paths (client and host),
  the HUD's build and produce lists, `Research.buy_as` + the research panel,
  `Population.get_cap`, and `ShrineObjective._fresh_roll`.
  Verified headless on `scenes/scenarios/sandbox.tscn`: slots resolved
  1/2/3 with the right teams, starting resources banked, Stables/Blacksmith/
  Wall/Gate/Watchtower refused, Watchtower 30 gold charged as 15, Monarchy 300
  charged as 150, research allowed at tiers 1-2 and refused at 3-4, both
  garrison soldiers adopted as peer 3 under Units, an AI brain for the enemy
  slot only, and the zone lookup working.
  `scenes/scenarios/sandbox.tscn` is a scratch scenario for testing, listed in
  the menus through `resources/maps/zz_sandbox_scenario.tres` (a MapInfo) until
  the campaign menus exist in step 8. Delete both when real content lands.
- 2026-09-14: **step 3 (quest core) implemented**, awaiting playtest.
  `scripts/quests/`: `quest_step.gd` (node: title, optional, hidden, requires,
  ALL/ANY, conditions, fail_conditions, on_start/on_complete/on_fail),
  `quest_condition.gd`, `quest_action.gd`, `quest_runner.gd`, plus
  `conditions/` (HaveUnits, TrainedUnits, HaveBuildings, HaveResources,
  Population, UnitsInZone, DestroyTargets, KillCount, CapturePoints,
  ElapsedTime, Favour, EliminateSlot) and `actions/` (SpawnUnits,
  GiveResources, TransferOwnership, SetUnlocks, EndMission).
  `QuestRunner` is a Main component (`main.quests`) built like Research:
  host-only evaluation four times a second, state broadcast to every peer as
  `{index: {state, progress}}` where progress is [current, target] pairs, so
  the step 4 tracker just draws it and co-op works for free. Counting is
  team-wide. Conditions are duplicated per mission so event tallies never
  cross wires between steps sharing an authored resource.
  Events reach conditions through `QuestRunner.notify`, called from
  `Main._on_building_item_completed` (unit_trained / upgrade_bought),
  `_on_building_construction_finished` (building_completed),
  `announce_point_captured` (point_captured) and `Unit._die` (unit_killed).
  Mid-mission changes that clients must see travel as runner RPCs:
  `set_entity_owner` (placed entities aren't spawner-replicated) and
  `set_unlocks` (rules are per peer; it also refreshes the build menu).
  `Main.end_mission(victory, team)` ends a mission; losing hands victory to
  `Main.NO_TEAM`, a team nobody is on, so everyone sees Defeat.
  **GDScript gotcha:** `QuestRunner -> QuestStep -> QuestCondition ->
  QuestRunner` is a type cycle the parser can't resolve, so conditions and
  actions take an **untyped** `runner` parameter. Anything read off it needs an
  explicit type (`var p: Vector2i = condition.progress(self)`), or inference
  fails with "cannot infer the type".
  Verified headless on the sandbox quest: a 3-second timer step completed,
  its actions spawned 2 soldiers and paid 200 gold, two dependent steps
  unlocked and completed, a mid-mission SetUnlocks turned Stables on while
  leaving Watchtower locked, and destroying the named garrison ended the
  mission in victory.
  Presentation actions (dialogue, briefing, camera, ping, reveal, markers, UI
  highlight) are deliberately **not** here — they arrive with their UI in step
  4 and will ride on `QuestRunner.show_to_players` / the `presentation` signal,
  which already exist.
- 2026-09-14: **step 4 (presentation) implemented**, awaiting playtest.
  `scripts/quests/quest_ui.gd` (`QuestUi`, built by Main into `$UI` when the
  match is a scenario, `main.quest_ui`) draws the tracker (top-right, active
  steps with `current/target` counts, completed ticked and dropped after 6s,
  failed in red, optional dimmed), the dialogue box (speaker, portrait, text,
  auto-advance by line length, queued) and the briefing screen (also shown for
  the scenario's own briefing as the mission opens).
  Portraits: a line's explicit `portrait` texture, else the speaker's head cut
  from their unit's sprite sheet — the top `PORTRAIT_TOP_FRACTION` of the first
  idle frame, cached per unit scene, nearest-filtered. Tune the crop constants
  at the top of `quest_ui.gd` when real art arrives.
  New actions: Dialogue, ShowBriefing, CameraPan, PingMinimap, RevealArea,
  WorldMarker. They send payloads through `show_to_players`; `QuestUi` renders
  them. Supporting additions: `Main.focus_camera_on`, `FogOfWar.add_reveal`
  (timed extra vision sources, folded into `_update_vision_sources`).
  Pausing is single-player only and self-undoing (`_paused_by_us`), so a
  briefing never fights the pause menu and never freezes a co-op match.
  **Layout:** the project stretches `canvas_items`, so the UI is laid out in a
  space 648 tall by however wide the aspect makes it (1372 on a 2932x1384
  window) — never in window pixels. Panels are anchored, not positioned: the
  briefing and dialogue box sit in CenterContainers (full-rect, and a band
  300-160 up from the bottom, clear of the command bar), and the tracker pins
  both its x anchors to the right with explicit offsets.
  `PRESET_MODE_MINSIZE` is not usable here: it measures a panel before it has
  any content and leaves it hanging off the screen edge, which is exactly how
  the first version went missing.
  **A briefing owns the screen while it is open:** it dims the battlefield
  behind it (a full-rect ColorRect that also swallows clicks, so a briefing in
  multiplayer — where nothing pauses — can't be played through), hides the
  dialogue box, and holds the line queue with its timer stopped. Closing it
  resumes whatever was being said. Without this, a step whose actions include
  both a briefing and a line draws them on top of each other, since every
  action on a step runs in the same instant.
  Verified headless: briefing paused and unpaused, tracker counted 0/3 → 2/3
  then ticked, dialogue showed with a cropped portrait, a marker appeared and
  was cleared, the fog reveal registered, and the mission still ended.
- 2026-09-14: **step 5 (editor dock) implemented**, awaiting playtest.
  `addons/scenario_editor/` — `plugin.cfg`, `scenario_editor_plugin.gd`,
  `scenario_dock.gd`, `scenario_builder.gd`, `zone_gizmo.gd`; enabled in
  `project.godot`. The dock (right-hand slot, "Scenario" tab) makes a scenario
  from any MapInfo map, adds sides/zones/markers/quest steps, lists the steps
  and selects them for the inspector, appends conditions and actions by type
  (both pickers scan `scripts/quests/conditions|actions/`, so a new script
  shows up with no list to update), validates, and plays the current scene.
  `ScenarioZone` gets a viewport gizmo drawing its radius.
  `ScenarioBuilder.create()` is deliberately separate from the dock so it can
  run without the editor UI. **It rewrites the packed scene's text to make the
  scene inherit the map** — the same technique `MapGenerator._save_inherited_scene`
  uses and for the same reason: `PackedScene.pack()` cannot produce an
  inherited scene from script. `GEN_EDIT_STATE_MAIN_INHERITED` was tried first
  and is not testable outside a running editor, so it was dropped.
  Verified headless: creating from Trial Forest produced a scene that inherits
  the map (`instance=ExtResource("map_base")`), carries the map's own nodes,
  has the Scenario skeleton with all four groups, and wrote a matching
  ScenarioInfo. The dock's UI itself has only been checked for loading cleanly
  — it needs the editor to exercise.
- 2026-09-14: dialogue lines no longer auto-advance. Each waits for a
  **Continue button** on the box (centred under the text); deliberately not any
  click or key, since those are how the player commands their army and a line
  would be gone before it was read. The box takes mouse input rather than
  ignoring it, so clicking it cannot also order units. `DialogueAction.seconds`
  is gone; `pause_in_single_player` still decides whether the game itself is
  held.
- 2026-09-14: **the quest holds while the host is reading**
  (`QuestRunner.presentation_hold`, set by `QuestUi`). Evaluation *and* match
  time stop while a line or briefing is on the host's screen, so the step a
  line announces cannot complete and start talking over it, and a deadline
  does not tick away while someone reads. Only the host's screen counts — in
  co-op the mission must not stall on each player's reading speed. Without
  this, the sandbox's Gather step completed the instant its soldiers spawned
  and fired its briefing behind the Captain's line.
- 2026-09-14: portraits are cut from the **figure**, not the cell.
  `QuestUi._head_of` scans the first idle frame for its opaque bounding box and
  keeps the top `PORTRAIT_HEAD_FRACTION` of that. A fixed crop off the top of
  the cell gave a blank portrait, because the art sits low in its frame (the
  Soldier's figure starts 16px down a 32px cell).
- 2026-09-14: `DestroyTargetsCondition` no longer counts a name the scenario
  never placed as "destroyed" — a typo used to satisfy the step immediately and
  win the mission. The dock's validator now also checks every `target_names` /
  `entity_name` against what the scenario actually places.
  **Content trap found the hard way:** the sandbox's garrison was placed near
  Trial Forest's centre shrine, whose neutral monster killed both guards within
  16 seconds; the destroy step completed, the mission auto-won, and every later
  AI test showed an enemy that "built nothing" because the match was long over.
  Place scenario units clear of neutral objective guards.
- 2026-09-14: **step 6 (enemies) implemented**, awaiting playtest.
  `AiPlayer.Mode` — NORMAL plays the whole game, DEFEND never sends a wave out
  (`AiCombat._maybe_launch_wave` returns early; defending itself is untouched),
  ATTACK throws every wave at `attack_position` instead of weighing up the map.
  `ScenarioSlot` gained `ai_mode`, `attack_at` and `defender_leash_radius`;
  `SetAiModeAction` + `QuestRunner.set_ai_mode` change it mid-mission (host
  only — the brains only exist there).
  DEFENDERS units are leashed to a post node created at their placed position
  (`Main._leash_defender`), the same arrangement Objective guards use, so a
  garrison chases and then returns.
  Difficulty: `Network.campaign_difficulty` (0/1/2) shifts every enemy AI a
  level in `Scenario.resolve_players` (so every machine agrees) and
  `MatchRules.enemy_scale()` (0.7/1.0/1.4) scales enemy starting resources
  (`_spawn_scenario_sides`) and enemy wave sizes (`SpawnUnitsAction`). The
  player's own stipend and reinforcements are never scaled.
  `Scenario.player_team()` / `position_of()` / `marker()` moved onto the
  Scenario itself, because sides are set up **before** `QuestRunner.setup()`
  runs — asking the runner for the player team during spawning returns its
  default.
  Verified headless on Hard: scale 1.4, enemy level shifted Normal → Hard,
  enemy purse 500 → 700 with the player's 600 untouched, both garrison
  soldiers leashed to their own posts at radius 14, the enemy brain starting
  in DEFEND with its attack position resolved from the zone, and
  `SetAiMode` switching it to ATTACK.
  Behaviour verified over a 7-minute match: in DEFEND the enemy built an army
  of 9 and sent **no wave at all** (max wave 0, nothing closer than 99 units to
  the player); ordered to ATTACK, waves formed immediately and grew to 31, and
  its army closed to 49.
- 2026-09-14: **the multiplayer screen is now two panels** (owner's call after
  playtesting step 9): `VBox/Connect` — Quick Play, Host Steam Lobby, Direct
  Connect (IP, Host, Join), Back — and `VBox/Room` — mission picker, map, mode
  row, player list, Add AI, Start, Leave, Invite. You pick *how to get into a
  game* first, and only choose what to play once you are in a lobby. The
  status line sits above both. `_show_connect(message)` / `_show_room(message)`
  own the swap; hosting, a Steam lobby opening and `connected_to_server` all
  move to the room, and Leave, cancel, a failed connection and disconnect all
  come back.
  The Start button is always on screen and simply greyed until it would work
  (`is_host and all_players_ready and can_start_match`) — hidden, it made a
  lobby where you had already picked a mission and added an AI look like it had
  no way to begin. `_ready` now calls `_refresh_player_list()`, without which
  nothing set the button's state until a network signal fired and Start sat
  there looking usable in an empty lobby.
  Verified in one process (panels swap on Host / Leave / Join, and every room
  control is parented to Room) and across two: the host moves to the room on
  Host, the client stays on Connect showing "Connecting to ..." and moves to
  the room on connect, where its mission and map pickers are read-only, Start
  is disabled and Add AI is hidden.
- 2026-09-14: **step 9 (multiplayer campaign) implemented**, awaiting playtest.
  `Network.set_scenario` / `scenario_changed` / `current_scenario()` mirror the
  host's mission choice to everyone the way the map is, and
  `Network.player_capacity()` returns the scenario's `human_slots` while one is
  chosen (so the lobby seats exactly the mission's seats and trims AI to fit).
  The lobby gained a mission picker above the map: "Skirmish" plus every
  mission **the host** has unlocked that seats more than one player
  (`ScenarioInfo.human_slots >= 2`) — a solo mission has nowhere for anyone
  else to sit, so it is never offered in multiplayer. The host's progress
  decides what the group can play. Opening the lobby also clears any scenario
  id left behind by a campaign mission played earlier in the session, which
  would otherwise be carried silently into a multiplayer match. Choosing one hides the map picker and the game-mode row (a mission
  brings its own) and Start loads the scenario's scene.
  Empty human seats are filled by an allied AI: `ScenarioSlot.fill_with_ai`
  (default on, turn it off for a seat that should stand empty),
  `Scenario.resolve_players` gives the seat an AI entry on the slot's own team
  named "<Slot> (AI)", and `Main._spawn_scenario_sides` starts a brain for it.
  An ally is **not** shifted by campaign difficulty — a harder campaign must
  not weaken your ally — while enemies still are.
  Scratch content for testing: `scenes/scenarios/coop_sandbox.tscn` +
  `resources/scenarios/coop_sandbox.tres` ("Two Lords", two human seats on
  Four Kingdoms against one AI), added as the tutorial campaign's second
  mission.
  Verified solo: the empty second seat became an allied AI on team 1 with its
  own base and brain, the enemy on team 2.
  Verified across two processes over ENet: the client joined, the host picked
  the mission and capacity became 2, the client was told which mission,
  both loaded it, **both machines resolved the same slot mapping**
  (slot 0 → host, slot 1 → client, slot 2 → AI), both humans on team 1 with
  the AI on team 2, the client read the host as an ally and could see the
  ally's 5 units through shared vision, and both had the quest with matching
  state.
  Verified in the lobby: with fresh progress the picker offers only Skirmish
  and Sandbox; after winning Sandbox, Two Lords appears; choosing a mission
  sets capacity from its human slots and hides the map/mode controls; choosing
  Skirmish restores them.
- 2026-09-14: **step 8 (campaign flow) implemented**, awaiting playtest.
  `Campaign` (resources/campaigns/*.tres: id, name, description, ordered
  `missions: Array[ScenarioInfo]`, `order`) with `unlocked_count()` — every
  mission up to and including the first unwon one is playable.
  `CampaignProgress` is static and writes `user://campaign_progress.cfg`:
  `is_completed`, `best_difficulty` (keeps the hardest ever won),
  `mark_completed`, `clear`. Progress is keyed by ScenarioInfo id alone, so
  moving a mission between campaigns keeps it.
  `CampaignMenu` (built in code, like MatchSettingsRow) is the mission select
  and the pre-mission briefing in one: mission list with completed marked and
  locked missions greyed but still listed, the selected mission's briefing
  title and text, a difficulty picker, a Ruler picker, Start and Back.
  `MainMenu._build_campaign_buttons` adds one button per campaign resource
  above Single Player, so adding a campaign is dropping a .tres into
  `resources/campaigns/` — no menu code to touch.
  Starting a mission sets `Network.campaign_difficulty`,
  `Network.current_scenario_id` and the chosen Ruler, then changes scene.
  `Main._rpc_game_over` writes the win down on each winner's own machine, so in
  co-op everyone who played it has it unlocked.
  `RulerPicker.selected_ruler()` added for callers that read the picker rather
  than following its signal.
  Verified headless: resources load; fresh progress → won on Hard → best stays
  Hard after an Easy win → saved to disk; the menu shows "Tutorial" above
  Single Player, opens, lists the mission and enables Start; starting it loads
  the scenario with difficulty in play (enemy scale 1.40) and 4 quest steps;
  winning shows "Victory!" and records completion on Hard.
  `resources/scenarios/sandbox.tres` + `resources/campaigns/campaign.tres` are
  scratch content so the menu has something to list; the real tutorial set and
  campaign arrive in step 10. The one campaign resource is named **Campaign**
  (owner's call, 2026-09-15): only its first mission is a tutorial, so a
  separate Tutorial entry would have been misleading. Renaming a campaign is
  safe — progress is keyed by mission id, not campaign id. The temporary `zz_sandbox_scenario.tres` MapInfo
  is gone — the Tutorial button is the way in now.
  The mission select lives in a full-rect CenterContainer
  (`MainMenu.CampaignCentre`). Centre anchors alone pin only a panel's
  top-left corner to the middle of the screen and let the rest run off the
  right and bottom edges, which is how the first version lost its Start and
  Back buttons — the same trap the quest panels hit. Measured: 612x442 centred
  in a 1152x679 viewport with every row on screen.
  **Any full-rect Control must set `mouse_filter = MOUSE_FILTER_IGNORE` and be
  hidden while unused.** Godot's default is STOP, so a screen-sized container
  swallows every click meant for what is behind it — with the campaign layer
  present but empty, the whole main menu stopped hovering and clicking. The
  same rule already applies to `QuestUi` and its containers in-match; the
  deliberate exception is the briefing shade, which blocks on purpose while a
  briefing is up. Verified by hovering and clicking every menu button, and the
  mission select's own list and buttons through the layer.
- 2026-09-14: **step 7 (tutorial support) implemented**, awaiting playtest.
  `TutorialInputCondition` waits on what the player does: select_units,
  move/attack/patrol orders, camera_move / camera_rotate / camera_zoom, hotkey,
  formation, control_group, build_placed, research_panel, research_bought,
  power_cast — with an optional `detail` filter (the key, the node name, the
  group number).
  Input happens on each player's machine, so `QuestRunner.report_input` relays
  a client's action to the host, which turns it into an ordinary
  `player_input` event; host-side ones (research bought, power cast) are
  notified directly. `Main.report_tutorial_input` is the single entry point,
  and is a no-op outside a scenario. Reports are placed *past* the chat and
  menu guards, so typing "b" into chat doesn't tick off "press B".
  `HighlightUiAction` + `QuestUi._set_highlight` draw a pulsing outline that
  follows a named HUD element each frame (minimap, action_panel, info_panel,
  idle_button, resources, research_button, quest_tracker) — following it,
  because the bottom bar is laid out per window size and panels move with the
  selection.
  `ScenarioModifiers.locked_hud` + `MatchRules.hud_allowed` lock parts of the
  HUD ("research", "build", "formations", "control_groups"), enforced in
  `ResearchPanel.toggle`, `PowerBar` (button hidden), `Hud.open_build_submenu`,
  `BuildingPlacement.on_construction_button_pressed`, `Main._set_formation_type`
  and both control-group paths. `SetUnlocksAction` gained `unlock_hud` /
  `lock_hud`, which is how a tutorial hands the game over one piece at a time.
  `MatchRules.assign` now **copies** a slot's modifiers instead of referencing
  them: a mid-mission unlock edits the copy, so it cannot write back into an
  authored resource (an external .tres is shared and cached, and the change
  would survive into the next attempt at the mission).
  Verified headless: locks refuse the research panel, the research button, the
  build submenu and formation changes, and releasing them restores all four; a
  highlight is created covering the minimap's rect and cleared again; the input
  condition ignores a wrong key, counts the right one twice and reports met.
  **Testing gotcha:** in headless the camera pans continuously on its own (no
  window focus, so the pan keys read as held), which legitimately fires
  `camera_move` within a second or two. Anything camera-driven cannot be timed
  in a headless test — drive those paths directly instead.
- 2026-09-14: the dialogue Continue button hangs under the whole box (an outer
  VBox holding the portrait/text row and then the button), not inside the text
  column — centred in the column it sits half a portrait's width to the right
  and reads as off-centre. Measured at 0.0px from the box centre.

## Useful project facts

- Godot 4.7 console binary:
  `C:\Users\craig\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe`
- AI players use synthetic positive peer ids (starting at 2) with `ai: true`
  in `Network.players`. Peer 0 is neutral (objective guards). Every
  `rpc_id(owner)` needs a `Network.can_rpc_to` guard.
- Order RPCs are split into `*_as(sender_id, ...)` so AI uses the same
  validation as humans.
- Headless test harness: a temp scene in `res://tests_tmp` that drives
  `Network.start_offline` + `add_ai_player`, then starts the match with
  `get_tree().change_scene_to_file(map)` — Main and everything under it
  resolve Main through `get_tree().current_scene`, so the map has to *be* the
  current scene before its `_ready` runs. Adding the map as a child of the
  harness and assigning `current_scene` afterwards is too late: the match
  loads but nothing works. Park the watcher under `get_tree().root` so the
  scene change doesn't free it. Delete the folder afterwards.
- **Headless runs are roughly 1x real time on this machine, whatever
  `Engine.time_scale` says.** The engine drops the extra physics steps it
  can't fit (raising `Engine.max_physics_steps_per_frame` barely helps with
  3 AIs on Four Kingdoms), so a run measured as "real seconds × time_scale"
  will report match minutes that never happened. Measure progress from an
  in-match clock — `AiPlayer.game_time` is the handy one — and budget about a
  minute of wall clock per match minute.
- Never put `##` comment lines inside .tscn property blocks — they silently
  break parsing.
- Don't add tooltips, labels or hint text unless the owner asks.
