# Creating a new objective — exact steps

An Objective (`scripts/objective.gd` on `scenes/objective.tscn`) is a
self-contained, neutral (peer `0`) cluster of guard units + production
buildings that any player can capture once its guards are dead, by standing
combat units on it — Conquest-style: an owned point's flag is lowered to
neutral, then the capturer's flag is raised. Its buildings can never be
damaged or targeted. Unlike a normal building, it is **not** registered on any
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

On **each** guard instance, explicitly set **Owner Peer Id** to `0` and
**Team Tint** to a neutral gray (e.g. `Color(0.5, 0.5, 0.5)`) in the
Inspector — do this even though `Objective._ready()` sets both again at
runtime. Godot readies a scene bottom-up in sibling declaration order, so if
some other node (fog of war, in particular) happens to be declared before
this Objective under the map's root, that node's own `_ready()` can run
*before* `Objective._ready()` gets a chance to correct a guard's ownership —
seeing its uncorrected scene-file default (`owner_peer_id` normally defaults
to `1`, the same id as the real host) for that one frame is enough to
permanently mark the objective as "explored"/visible on sight, since fog of
war's explored memory only ever accumulates, never un-stamps. Baking the
neutral values directly into the scene file is what actually prevents that —
the runtime correction alone only fixes every frame *after* the first.

## 2. Populate Buildings

Select the **Buildings** node and instance whatever `ProductionBuilding`
scene(s) the capturing player should gain — a Barracks-equivalent, an
upgrade building, or several. See `docs/creating-a-building.md`'s
Variation D for what's specific to an Objective building (short version:
nothing — just place it here, `Objective._ready()` calls
`main.gd:register_objective_building()` on every child automatically).

Same as step 1: explicitly set **Owner Peer Id** to `0` on each building
instance too, for the same fog-of-war-ready-order reason.

Different objectives are meant to have completely different rosters (an "Orc
Camp" vs. an "Elven Hollow") — that's the whole point of Guards/Buildings
being plain hand-placed children instead of a shared `Faction` resource.

## Purely decorative scenery

Any imported model or prop placed near an objective purely for looks (no
`Unit`/`ProductionBuilding` script attached — a watchtower, ruins, rocks)
is invisible to fog of war by default; it isn't a unit, building, or
gatherable, so nothing ever hides it. Add **`fog_static_props`** to the
node's **Groups** (Node dock → Groups tab) to have it hidden until explored,
same "remembered once seen" rule buildings use.

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

- **Stage Duration** — seconds one combat unit takes to lower a flag to
  neutral, or to raise one to full (so 2x this to flip an enemy point).
  Workers never count.
- **Capture Speed Per Extra Unit** / **Max Capture Speed** — each extra
  combat unit adds to the speed multiplier, up to the cap (defaults: 1 unit
  1x, 2 units 1.5x, 3+ units 2x). With opposing units on the point it's a
  tug-of-war by head count: whoever outnumbers moves the flag at the speed
  of the difference; equal numbers (or two+ challengers at once) freeze it
  as **Contested**. A contested or draining point pays no Favour.
- **Guard Respawn Delay** / **Guard Respawn Health** — a neutral point with
  every guard dead and nobody standing on it respawns its original guards
  after this many seconds, at this fraction of their health.
- **Wander Radius** — radius the guards wander within around the
  objective's origin. Guards leash-break-off and return if dragged more than
  `wander_radius * 2.5` away mid-fight (see
  `Unit.leash_origin`/`leash_radius` — this is the one piece of unit-level
  state an Objective pokes directly that a normal building never touches).
- **Favour Per Second** — paid to the owner while the point is held
  (default `1`; a map's centre point is set to `2`). Favour is the Conquest
  score and is never spent.

Pick **Wander Radius** noticeably smaller than the **CaptureZone** radius
from step 3 — guards should be wandering *inside* the area a capturing
player needs to stand in, not past its edge.

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
3. Kill every guard, move one combat unit into the zone, confirm the disc
   fills clockwise in your colour over **Stage Duration** seconds (faster
   with more units) and sinks back down if the zone is emptied. A villager
   alone does nothing.
4. On capture: confirm the buildings are immediately selectable/usable by the
   capturing player (production menu opens, queuing works — including on a
   client, not just the host).
5. Bring a second player's units onto the owned point: the owner's flag
   lowers, the point goes neutral (anything queued is refunded to the old
   owner), then fills in the attacker's colour. Equal numbers freeze it.
6. Leave a neutral point empty for **Guard Respawn Delay** seconds and
   confirm its guards come back at reduced health.
7. Host + Join: confirm capture progress, guard ownership, and building
   ownership/tint all update identically on both the host and client screens
   (this depends on the Objective's own `MultiplayerSynchronizer` and the two
   `owner_peer_id`/`team_tint` sync properties every unit/building scene
   already carries — see `docs/creating-a-building.md` step 2 if a client's
   view ever looks stale after a capture).
