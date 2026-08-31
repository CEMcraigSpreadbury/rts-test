# Creating a new building — exact steps

There is only **one** building script/scene pattern: `ProductionBuilding`
(`scripts/production_building.gd`, on `scenes/buildings/production_building.tscn`
and every other `*_building.tscn`). What a building "is" — Town Center,
Barracks, Blacksmith, or an Objective's guarded structure — is entirely
decided by the `@export` fields set on the instance in the Inspector, not by
different scripts. So "creating a new building" almost always means
**duplicating an existing building scene** and editing its fields, not
writing new code.

The one exception is a building with no production queue at all (a
Farm-equivalent) — see Variation C.

## 0. Duplicate an existing building scene

In the FileSystem dock, right-click the closest existing building to what you
want (e.g. `scenes/buildings/barracks_building.tscn` for a unit-producer,
`scenes/buildings/blacksmith_building.tscn` for an upgrade building) →
**Duplicate**, rename it, and swap in new meshes/textures. Keep the
`ProductionBuilding` script and the existing node structure intact:
`MeshInstance3D`, `CollisionShape3D`, `NavigationObstacle3D`, `DropoffPoint`
(only matters for a Town-Center-equivalent), `SpawnPoint`, `SelectAudioPlayer`,
`HealthBar` (`Background`/`Fill`), and the `MultiplayerSynchronizer`.

Set the root node's group to `["buildings"]` — fog of war, the minimap, and
several main.gd lookups all scan `get_tree().get_nodes_in_group("buildings")`
to find every building in the match. A building missing this group is
invisible to those systems even though it works otherwise.

## 1. Set the building's own fields (Inspector, root node)

These live on the building scene itself, not on `BuildingType` (see step 3) —
edit them directly so they're visible right next to what they affect:

- **Building Name** — shown in the info/action panel titles.
- **Costs** (`Array[ResourceCost]`) — what it costs to construct.
- **Max Health**, **Population Capacity** (0 unless this grants population
  room, like House/Town Center), **Is Main Base** (only true for a
  Town-Center-equivalent — losing all of these ends the game for that
  player), **Vision Range**, **Construction Sink Depth**.
- **Can Rally** — whether right-click while selected sets a rally point.
- **On Select Sound Effects**.
- **Producibles** (`Array[ProducibleItem]`) — see the variations below; this
  is the field that actually determines whether the building trains units,
  sells upgrades, both, or neither.

## 2. Add its `SceneReplicationConfig` entries

Every building needs the same synced properties so non-host peers see
correct health/queue/ownership state — this is the #1 thing that's easy to
forget and silently breaks the building for clients only (host-only testing
won't catch it). Select the `MultiplayerSynchronizer` node → **Replication**
→ confirm these properties are all present (copy the list from
`barracks_building.tscn` if in doubt), each `On Change` except `position`
(Always):

```
position                        (Always)
is_under_construction            (On Change)
construction_progress            (Always)
synced_queue_size                (On Change)
synced_time_remaining            (Always)
synced_current_item_name         (On Change)
health_fraction                  (Always)
synced_builder_count             (On Change)
synced_current_item_progress     (Always)
can_promote_monarch              (On Change)
owner_peer_id                    (On Change)
team_tint                        (On Change)
```

`synced_current_item_progress`/`can_promote_monarch` were missing from every
building except Town Center for a while — that's exactly the "production bar
doesn't fill on the client" class of bug this step exists to prevent. Do this
in the Inspector's Replication panel, not by hand-editing the `.tscn` text —
a stray `##` comment or malformed array literal inside a `.tscn` property
block silently breaks parsing.

## 3. Register it (only if it's a player-constructible building)

Skip this step entirely for Variation D (Objective buildings) below.

1. Open the relevant `Faction` resource (currently just
   `resources/factions/faction_one.tres` — see `docs/adding-a-faction.md` if
   you're building out a second faction again), expand **Building Types**,
   grow the array by one, and fill the new `BuildingType` entry: **Building
   Name**, **Scene** (your new `.tscn`), **Footprint Radius**, **Construction
   Time**. Leave **Costs** empty (it's only a fallback — the scene's own
   Costs from step 1 is authoritative).
2. For a Mine-equivalent that must snap onto a resource node, check
   **Requires Deposit** and point **Deposit Scene** at the matching deposit
   scene.
3. The building's position in the **Building Types** array decides its
   construction-menu hotkey (`BUILDING_HOTKEYS` in `main.gd`, currently
   Z X C V B N G in array order) — put it wherever in the list makes sense.

## Variation A — unit-production building (Barracks/Stables-style)

Add one `ProducibleItem` per unit to **Producibles**, each with:
- **Kind** → `Unit`
- **Item Name**, **Build Time**
- **Unit Scene** → the unit's `.tscn` (see `docs/creating-a-unit.md`)

Leave **Costs**/**Population Cost** on the `ProducibleItem` itself blank —
for `Kind: Unit` those are read from the unit scene's own `Costs`/
`Population Cost` instead (`ProducibleItem.get_costs()`), so balancing a
unit's price only ever needs editing in one place.

## Variation B — upgrade building (Blacksmith-style)

Add one `ProducibleItem` per upgrade tier, each with:
- **Kind** → `Upgrade`
- **Item Name**, **Build Time**, **Costs** (this time these ARE read
  directly off the item, since there's no unit scene to read them from)
- **Upgrade Category** → which `Unit.UnitCategory` this affects (Infantry/
  Archer/Cavalry)
- **Upgrade Stat** → `Weapon` or `Armor`
- **Upgrade Bonus** → the flat amount added (applied host-side via the
  `UnitUpgrades` autoload, picked up automatically by
  `Unit.take_damage()`/`_effective_attack_damage()` for every unit of that
  category the buying player owns, present and future)
- **Requires Upgrade** → for tier 2+, point this at the tier-1 item resource
  so it can't be bought out of order; leave null for the first tier in a line

Only one tier in a line is ever shown at once in the building's menu
(`main.gd:_producible_is_visible`) and `ProductionBuilding.enqueue()` refuses
buying a tier whose prerequisite isn't purchased yet or that's already
one-time-purchased — no extra wiring needed beyond setting these fields.

A `ProducibleItem` can instead (or additionally) set **Unlocks Monarch
Promotion** to true — see `main.gd:_on_building_item_completed` for that
effect's extension point if you need a genuinely new upgrade *kind* someday.

## Variation C — non-queue building (Farm-style)

Some buildings aren't `ProductionBuilding` at all — a Farm is just a
`Gatherable` (`scripts/gatherable.gd`) that villagers gather from directly,
with no construction queue or Producibles list. To make one of these:

1. Duplicate `scenes/resource_nodes/gold_deposit.tscn` or
   `scenes/buildings/farm_building.tscn` instead of a `ProductionBuilding`
   scene.
2. Set **Costs**, **Resource Type**, **Amount Remaining**, **Gather Range**.
3. Register it in a `Faction`'s **Building Types** the same as step 3 above —
   `BuildingType.scene` can point at a `Gatherable` just as well as a
   `ProductionBuilding`; `BuildingType.get_costs()` duck-types either.

## Variation D — Objective building (no Faction/BuildingType at all)

A building guarded by an Objective (see `scripts/objective.gd`,
`scenes/objective.tscn`) is **not** registered on any `Faction` or
`BuildingType` — it's a plain `ProductionBuilding` (or several) hand-placed
as a child of an `Objective` instance's `Buildings` node. It starts owned by
peer `0` (neutral) and only becomes usable by whichever player captures the
objective. To add one:

1. Open `scenes/objective.tscn` (or a duplicate of it for a new objective
   site), select **Buildings**, and instance your building scene as a child
   — same as instancing any other scene, no `BuildingType` resource needed.
2. Set its **Producibles** as in Variation A/B — captured buildings train
   units or sell upgrades exactly like a normal one, gated by whoever's
   `owner_peer_id` the Objective assigns on capture.
3. `Objective._ready()`/`_capture()` set `owner_peer_id`/`team_tint`
   directly, and `main.gd:register_objective_building()` wires up the
   `item_completed`/`destroyed` signal connections that normal (player-built)
   buildings only ever get via the placement spawn path — this connection is
   the one piece of plumbing a hand-placed building needs that a
   `BuildingType`-registered one gets automatically, and `Objective._ready()`
   already calls it for every child under **Buildings**, so no per-building
   setup is needed beyond placing it there.

## Verify

1. Run `main.tscn` directly — confirm the building appears/behaves as before
   for anything you didn't touch.
2. Host + Join with two windows. Confirm the new building shows up in the
   construction menu (Variation A/B/C) with the right hotkey/cost, or is
   captured correctly and its production menu opens for the capturer
   (Variation D).
3. Queue a unit or upgrade from **both** the host and a client window —
   confirm the progress bar actually fills on both, not just the host (the
   symptom of a missing `SceneReplicationConfig` entry from step 2).
4. Damage it to destroyed and confirm the sink/destroy visual and (if
   `Is Main Base`) game-over check both work.
