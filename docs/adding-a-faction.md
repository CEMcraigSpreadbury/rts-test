# Adding a new faction — exact steps

Worked example: creating "Faction Three" with its own art. Follow these steps
in order, in the Godot editor unless a step says otherwise.

## 0. Prerequisites

Have your new faction's scenes ready first — you can't reference a scene from
a `Faction`/`BuildingType`/`ProducibleItem` resource until it exists:

- A starting building scene (Town-Center-equivalent) — copy
  `scenes/buildings/production_building.tscn`, swap in your new meshes/sprites,
  keep the `ProductionBuilding` script and node structure (collision shape,
  `NavigationObstacle3D`, etc.) intact.
- A starting unit scene (Villager-equivalent) — copy `scenes/units/unit.tscn`
  the same way, keeping the `Unit` script attached.
- Any other buildings (Barracks/House/Farm/Mine/Stables-equivalents) and
  combat units (Soldier/Archer/Spearman/Cavalry-equivalents) you want this
  faction to have. Reusing the existing building/unit scenes as-is is fine too
  (that's what Faction Two does today) — you don't have to replace everything
  at once.

If you're only reskinning meshes/textures on a duplicated scene, no script
changes are needed — all the gameplay stats (costs, damage type, HP, etc.)
are `@export` fields set per-scene in the Inspector.

## 1. Duplicate the faction resource

In the FileSystem dock:

1. Right-click `resources/factions/faction_two.tres` → **Duplicate**.
2. Rename the copy to `resources/factions/faction_three.tres`.

## 2. Edit the new `.tres`

Double-click `faction_three.tres` to open it in the Inspector.

1. **Faction Name** → e.g. `"Faction Three"`.
2. **Building Types** (array of `BuildingType`) — for each entry:
   - Expand it, set **Scene** to your new building's `.tscn`.
   - Set **Building Name**, **Footprint Radius**, **Construction Time** to match.
   - Leave **Costs** empty — actual costs live on the building scene itself
	 (see step 3), this array field is only a fallback.
   - For a Mine-equivalent, keep **Requires Deposit** checked and **Deposit
	 Scene** pointed at the correct deposit scene.
   - To add/remove a building slot entirely, resize the **Building Types**
	 array itself, then fill the new slot.
3. **Starting Building Scene** → your new Town-Center-equivalent scene.
4. **Starting Unit Scene** → your new Villager-equivalent scene.

## 3. Set costs/stats on the actual scenes

Costs and combat stats are edited on the building/unit scenes themselves, not
on the `Faction`/`BuildingType` resource:

- Open each building scene → select its root node → in the Inspector set
  **Costs** (`Array[ResourceCost]`) and, for a Farm-equivalent, the
  `Gatherable` costs.
- Open each unit scene → select its root node (`Unit` script) → set **Costs**,
  **Population Cost**, **Damage Type**, **Weak To**, HP, damage, range, speed,
  etc.
- For a Barracks/Stables-equivalent that produces units, select its root node
  and edit **Producibles** (`Array[ProducibleItem]`): each entry needs
  **Item Name**, **Build Time**, **Population Cost**, and **Unit Scene**
  pointed at the unit scene to spawn.

## 4. Register the faction in both scenes

The faction only becomes selectable once it's listed in **both** places, in
the same array order as every other faction (that shared index is what
`Network.players[peer_id]["faction_index"]` refers to):

1. Open `scenes/main.tscn`, select the **Main** node, find **Available
   Factions** in the Inspector, increase the array size by one, drag
   `faction_three.tres` into the new slot.
2. Open `scenes/lobby.tscn`, select the **Lobby** node, do the same under its
   **Available Factions** field.

Do this from the Inspector, not by hand-editing the `.tscn` text — a stray
`##` comment or malformed `Array[...]` literal inside a `.tscn` property block
silently breaks parsing.

## 5. Verify

1. Run `main.tscn` directly (bypassing the lobby) — it should default to
   `available_factions[0]` and behave exactly as before; nothing should be
   broken by adding a third entry.
2. Run the game normally: Host in one window, Join in another. In the lobby,
   confirm "Faction Three" now appears in the dropdown for both players.
3. Pick Faction Three, Start Game — confirm your new Town Center and two
   starting units spawn, the construction menu shows your new building
   roster with correct hotkeys/costs, and producing units from your new
   Barracks/Stables-equivalent works.
4. Pick different factions per player and confirm each sees only their own
   faction's building menu (not the other player's).

No script changes are required anywhere in this flow — `network_manager.gd`,
`lobby.gd`, and `main.gd` all resolve factions by array length/index already,
so a third `Faction` resource just shows up as another option.
