# Campaign: The Unclaimed March

The campaign is three single-player missions played under Realm rules
(settlements, food and upkeep, Lords and their armies). The first mission is
the tutorial. It teaches the game one quest step at a time. The other two are
ordinary missions built on the same quest system.

This replaces the earlier tutorial set and the "Embers on the Border" missions.
Those were written for the pre-Realm rules (Houses, population caps, plain
capture points), and all of them have been deleted. The same goes for the
campaign-select screen and the lobby's co-op mission picker.

## Where things live

| What | Where |
|---|---|
| The campaign (name, mission order) | `resources/campaign.tres` (`Campaign`) |
| One entry per mission (id, name, scene, menu briefing) | `resources/scenarios/*.tres` (`ScenarioInfo`) |
| The missions themselves | `scenes/scenarios/m1_*.tscn`, `m2_*`, `m3_*` |
| Saved progress | `user://campaign.cfg` (`CampaignProgress`, keyed by mission id) |
| Mission select screen | `scripts/campaign_menu.gd`, opened by the main menu's Campaign button |

A mission is a map scene with a `Scenario` node added. That node holds
`Slots` (the sides), `Zones`, `Markers` and `Quests` (the `QuestStep`s). Open
one in the editor and use the **Scenario** dock to add sides, zones, markers,
steps, conditions and actions, validate the mission, and play it.

To add a fourth mission, make the scenario with the dock, fill in its
`ScenarioInfo`, and append it to `missions` in `resources/campaign.tres`.
Winning a mission unlocks the next one. The victory screen offers
"Next: <mission>" in single player.

## Realm rules in missions

`Scenario.realm_rules` (on by default) makes `MatchRules.realm()` true for the
mission. Everything Realm checks follows from that: settlements with garrisons
and building slots, food upkeep, Lords, no Houses or population cap, and the
Mill. Turn it off for a mission that should play by the older rules.

A mission does not get the skirmish starting purse. Give each side its gold,
wood and food in the slot's `starting_resources`. A side with a spawn point
gets the faction's Town Center and eight villagers unless the slot lists its
own.

Sides with no spawn point (`DEFENDERS`) are not charged upkeep, so scripted
waves never starve and rout on the march.

## Quest pieces added for Realm

- **SettlementsCondition**: counts settlements held right now. It can filter by
  node name as it stands in the map (`Objective6`), by race, and by minimum
  tier (Village, Town or City), and it can count another side's settlements
  instead of the players'.
- **RegimentsCondition**: counts regiments of at least `min_size` men,
  optionally of one unit type, and optionally only those in a Lord's army.
- **GatheredCondition**: counts resources the players' workers carried home
  since the step started. Spending doesn't undo it, and settlement income
  doesn't count.
- **EliminateSlotCondition.main_bases_only**: "burn their Town Center",
  whatever else of theirs is still standing.
- **HighlightUiAction** can also point at `unit_cards` (the regiment card
  strip) and `speed_controls`.

The quest tracker now sits under the single-player speed buttons instead of on
top of them.

## The missions

### 1. A Holding in the March (tutorial)

Map: Angel Crossing Realm, spawn 0. Building is locked until step 4, and the
build list opens up as the tutorial reaches each building. Research stays
locked throughout. Every instruction line pauses the game until Continue is
pressed.

1. Look over your holding: move the view and zoom.
2. Select your villagers.
3. Bring in 50 wood. The idle-villager button is highlighted.
4. Build a Mine on the marked gold. Building is unlocked here and the action
   panel is highlighted.
5. Bring in 30 gold.
6. Build a Mill.
7. Train two villagers.
8. Build a Barracks. The Barracks is unlocked here.
9. Have twelve soldiers.
10. Form a regiment (N). The card strip is highlighted.
11. Raise a Lord at the Town Center. The Crown sends 150 gold for him.
12. Bring the regiment into the Lord's army (J).
13. Take Brackenford (`Objective6`, a Human village down the slope west of
    the base). Afterwards the player is told to choose Occupy.
14. Build a Granary in Brackenford's slot. The closing lines lead into
    mission 2, then Victory.

### 2. Smoke over the Vale

Map: Aldmere Vale Realm, spawn 0. The mission starts by mustering a Lord and 12
soldiers beside the base. The Grimhold Raiders are a `DEFENDERS` side on
team 2.

- Take Hollin's Rest (`Objective8`, the Human village nearest the base).
- Once it is taken, four hidden timer steps send raids from `RaidCamp` to
  Hollin's Rest. They fire at +45 s, then every 3 minutes after that. Sizes
  are 5/2/0, 7/3/2, 9/4/3 and 12/5/4 warriors/raiders/druids, scaled by
  difficulty.
- Hold three settlements, with an optional step to hold a Town (raised to one, or taken as one).
- Take Grimhold (`Objective4`, a Beastmen Town) to win. Grimhold is revealed
  and marked when that step starts.

### 3. The Pretender

Map: Four Kingdoms Realm. The player is at spawn 0 and starts with the same
muster as mission 2. Lord Varric is an `ENEMY_AI` at spawn 2 (the opposite
corner), on Normal (campaign difficulty shifts it) and playing a full Realm
game. His Beastmen sellswords are a `DEFENDERS` side.

- Hold three settlements. Completing this brings 12 spearmen to the muster
  point.
- Optional: take the City at the map's centre (`Objective1`) for 300 wood and
  300 gold.
- Hidden: Beastmen waves leave `SellswordCamp` for the player's base at 9:00
  and at 14:00 (10/4/3, then 12/5/4).
- Burn Varric's Town Center to win. His base is revealed when this step
  starts, and he has a line for when six of your units reach his gates.

Losing your own Town Center loses any mission.

## Gotchas worth knowing

- Placed zones and markers only need the right x/z. `SpawnUnitsAction` snaps
  every spawn to the navmesh, so a marker at the wrong height is harmless.
- Settlement names are the map's node names (`Objective1`...). Inherited
  nodes can't be renamed in a mission, so the dialogue gives them their
  story names instead.
- Neutral settlement guards fight every side, scripted raiders included. Keep
  spawn markers well clear of settlements (RaidCamp is about 45 m from
  Grimhold).
- `QuestUi` must exist before `quests.setup()` runs (Main builds it first), or
  the opening line is lost.
- Headless runs play at about 1x real time whatever `Engine.time_scale` says.
  Anything camera-driven fires on its own in headless, so drive tutorial input
  directly in tests.
- Never put `##` comment lines inside `.tscn` property blocks.
