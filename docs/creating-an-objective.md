# Creating a new objective — exact steps

An Objective (`scripts/objective.gd` on `scenes/objective.tscn`) is a
self-contained, neutral (peer `0`) cluster of guard units + production
buildings that any player can capture by holding it uncontested for a set
duration. Unlike a normal building, it is **not** registered on any
`Faction`/`BuildingType` — it's placed directly in the map scene, fully
configured on the instance itself. Worked example: adding an "Orc Camp".

## 0. Duplicate the scene

Right-click `scenes/objective.tscn` → **Duplicate** (or **New Inherited
Scene** if you want future changes to the base Objective, like a new field,
to propagate automatically — inheriting is the safer default, same reasoning
as `docs/creating-a-unit.md` step 1). Save it as e.g.
`scenes/objectives/orc_camp.tscn`.

## 1. Populate Guards

Select the **Guards** node and instance whatever unit scenes should defend
this objective as its children (any existing unit works — a Soldier, an
Archer, or a brand-new one via `docs/creating-a-unit.md`). Position them
around the origin; exact placement doesn't matter much since
`Objective._ready()` immediately puts each one on a patrol loop.

Leave their **Owner Peer Id**/**Team Tint** at whatever's in the scene file —
`Objective._ready()` overwrites both to neutral (peer `0`, gray tint) on
`_ready()` regardless, so nothing needs setting here manually.

## 2. Populate Buildings

Select the **Buildings** node and instance whatever `ProductionBuilding`
scene(s) the capturing player should gain — a Barracks-equivalent, an
upgrade building, or several. See `docs/creating-a-building.md`'s
Variation D for what's specific to an Objective building (short version:
nothing — just place it here, `Objective._ready()` calls
`main.gd:register_objective_building()` on every child automatically).

Different objectives are meant to have completely different rosters (an "Orc
Camp" vs. an "Elven Hollow") — that's the whole point of Guards/Buildings
being plain hand-placed children instead of a shared `Faction` resource.

## 3. Size the capture zone and progress disc

Two things size this objective and are **not** kept in sync automatically —
set both by hand to match:

- **CaptureZone** → **CollisionShape3D** → **Shape** → **Radius**: this *is*
  the capture radius (the only source of truth — there's no separate
  exported capture-radius field on the script).
- **ProgressDisc** → **Mesh** → **Size**: a flat `PlaneMesh`, purely visual.
  Set both X and Y to roughly `2x` the CaptureZone radius above so the
  clockwise-fill disc visually lines up with the actual capture area (e.g.
  radius `5.0` → disc size `Vector2(10, 10)`, the values `objective.tscn`
  itself uses).

## 4. Set the root node's exported fields

Select the **Objective** root node:

- **Capture Duration** — seconds the zone must be held uncontested (attacking
  units present, zero living defenders, and no second attacking player also
  contesting it) before it flips ownership. Progress decays back down (never
  instantly resets) if that condition breaks.
- **Patrol Radius** — radius of the guards' square patrol loop around the
  objective's origin. Guards leash-break-off and return to this loop if
  dragged more than `patrol_radius * 2.5` away mid-fight (see
  `Unit.leash_origin`/`leash_radius` — this is the one piece of unit-level
  state an Objective pokes directly that a normal building never touches).

Pick **Patrol Radius** noticeably smaller than the **CaptureZone** radius
from step 3 — guards should be patrolling *inside* the area a capturing
player needs to stand in, not wandering past its edge.

## 5. Place it in the map

Drag the finished scene into `scenes/main.tscn` (or whatever map scene) as a
child of **Main**, positioned wherever the objective should sit — same as
placing any other scene (`PlayerSpawnPoint`, a `Gatherable`, etc.). Nothing
else needs registering; an Objective has no array/list anywhere else it must
be added to. Give it plenty of clearance from player spawn points and other
objectives so its capture zone and guard patrol loop don't overlap them.

## Verify

1. Run `main.tscn` directly — confirm the guards patrol the loop and the
   disc starts invisible (0% progress, no defenders/attackers present yet).
2. Approach with a single unit: guards should engage it, and if you retreat
   the damaged unit well outside the patrol loop, the guard should break off
   and return to patrolling instead of chasing indefinitely.
3. Kill every guard, move units into the zone, confirm the disc fills
   clockwise over **Capture Duration** seconds and decays back down if the
   zone is emptied or a second player's units also enter (contested).
4. On capture: confirm the buildings are immediately selectable/usable by the
   capturing player (production menu opens, queuing works — including on a
   client, not just the host) and any guard that survived the fight is now a
   selectable, player-controlled unit instead of still patrolling.
5. Undefend the captured objective and confirm a second player can retake it
   the same way.
6. Host + Join: confirm capture progress, guard ownership, and building
   ownership/tint all update identically on both the host and client screens
   (this depends on the Objective's own `MultiplayerSynchronizer` and the two
   `owner_peer_id`/`team_tint` sync properties every unit/building scene
   already carries — see `docs/creating-a-building.md` step 2 if a client's
   view ever looks stale after a capture).
