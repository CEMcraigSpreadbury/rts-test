class_name Formation
extends RefCounted

## Lightweight, host-side-only formation shape data: which units belong to
## the group and which named shape their move-order slots should be arranged
## into. This does NOT cache world positions or try to persist across
## multiple orders — main.gd builds a fresh Formation each time a move order
## is issued (see _formation_positions) and throws it away once slots are
## computed. What "persists" is only the shape *choice* itself
## (main.gd's current_formation_type), which stays selected across orders
## until the player picks a different one.

enum Type { BOX, LINE, STAGGERED }

const DEFAULT_TYPE: Formation.Type = Type.BOX

## Spacing between adjacent slots. Wider than it looks like it needs to be on
## paper: each unit's NavigationAgent3D avoidance radius is 0.45 (unit.gd),
## so at a tighter spacing adjacent slots leave almost no slack for avoidance
## to negotiate, and the group jostles into whatever gap opens up instead of
## settling into its exact assigned slot.
const SPACING: float = 2.0

## Box: roughly square grid, front rank arrives exactly at the target. This
## is a cap on how wide any single row is allowed to get, not a fixed row
## width — _box_slots sizes each formation's actual width off its own unit
## count (via ceil(sqrt(n))) so small groups still form a compact square
## instead of a fixed-width grid with a lopsided leftover row, and this only
## kicks in to stop very large groups getting absurdly wide.
const BOX_COLUMNS: int = 4
## Line: single (or, once a selection is large, a few-rank) wide line —
## capped so a huge selection doesn't produce one absurdly wide rank.
const LINE_MAX_PER_RANK: int = 12
## Staggered/Column: narrow 2-wide column for threading chokepoints, with
## alternating rows offset sideways so it marches in a genuine zigzag.
const STAGGERED_COLUMNS: int = 2

var units: Array[Unit] = []
var type: Formation.Type = DEFAULT_TYPE

func _init(formation_units: Array[Unit] = [], formation_type: Formation.Type = DEFAULT_TYPE) -> void:
	units = formation_units
	type = formation_type

## Display name for the HUD formation indicator (see main.gd's
## formation_label/_set_formation_type).
static func type_name(formation_type: Formation.Type) -> String:
	match formation_type:
		Type.LINE:
			return "Line"
		Type.STAGGERED:
			return "Staggered"
		_:
			return "Box"

## Returns one world-space slot per member of `units`, in the same order as
## `units` (NOT the final per-unit assignment — main.gd's
## _assign_slots_to_units still does nearest-slot pairing on top of this so
## units don't needlessly cross paths to swap places with each other).
## `forward` is the group's direction of travel (target - centroid,
## normalized) and `right` is perpendicular to it — both flattened to the XZ
## plane by the caller.
func get_slot_positions(target_pos: Vector3, forward: Vector3, right: Vector3) -> Array[Vector3]:
	match type:
		Type.LINE:
			return _line_slots(target_pos, forward, right)
		Type.STAGGERED:
			return _staggered_slots(target_pos, forward, right)
		_:
			return _box_slots(target_pos, forward, right)

## Sizes the grid's width off this formation's own unit count (roughly
## sqrt(n), capped at BOX_COLUMNS) rather than always using a fixed column
## count, then distributes units evenly across however many rows that width
## implies — each row is centered on its own actual unit count instead of
## left-aligned within a fixed-width grid. Without this, counts that aren't
## an exact multiple of the column count (e.g. 6 units at a fixed width of
## 4) produce a full front rank plus a short trailing rank left-aligned to
## columns 0-1 with columns 2-3 sitting empty — reads as broken from a
## top-down camera instead of a coherent block.
func _box_slots(target_pos: Vector3, forward: Vector3, right: Vector3) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var n: int = units.size()
	var columns: int = clampi(ceili(sqrt(n)), 1, BOX_COLUMNS)
	var rows: int = ceili(float(n) / columns)

	var index := 0
	for row in rows:
		var remaining: int = n - index
		var remaining_rows: int = rows - row
		## How many units land in this row: spread what's left evenly over
		## the rows still to come (capped at the grid's width) so a partial
		## final row still comes out balanced instead of front-loaded.
		var row_count: int = clampi(ceili(float(remaining) / remaining_rows), 1, columns)
		for col in row_count:
			var col_offset: float = (col - (row_count - 1) / 2.0) * SPACING
			var row_offset: float = row * SPACING
			slots.append(target_pos + right * col_offset - forward * row_offset)
			index += 1
	return slots

func _line_slots(target_pos: Vector3, forward: Vector3, right: Vector3) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var columns: int = clampi(units.size(), 1, LINE_MAX_PER_RANK)
	for i in units.size():
		var col: int = i % columns
		var rank: int = i / columns
		var col_offset: float = (col - (columns - 1) / 2.0) * SPACING
		var rank_offset: float = rank * SPACING
		slots.append(target_pos + right * col_offset - forward * rank_offset)
	return slots

func _staggered_slots(target_pos: Vector3, forward: Vector3, right: Vector3) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	for i in units.size():
		var col: int = i % STAGGERED_COLUMNS
		var row: int = i / STAGGERED_COLUMNS
		## Alternates sideways every row (not just offsetting the odd ones) so
		## the column actually zigzags left-right-left rather than only ever
		## nudging one direction, which would just be a brick offset.
		var stagger: float = (SPACING * 0.5) * (1.0 if row % 2 == 1 else -1.0)
		var col_offset: float = (col - (STAGGERED_COLUMNS - 1) / 2.0) * SPACING + stagger
		var row_offset: float = row * SPACING
		slots.append(target_pos + right * col_offset - forward * row_offset)
	return slots
