// ArmySim - the boundary between Godot and the native unit simulation.
//
// Deliberately narrow: GDScript submits orders and configuration, steps the sim
// once per physics tick, and reads results back in bulk. Nothing here is ever
// called once per unit per tick.

#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include "world.h"

class ArmySim : public godot::Node {
	GDCLASS(ArmySim, godot::Node)

protected:
	static void _bind_methods();

public:
	// The sim's fixed step. Matches physics/common/physics_ticks_per_second.
	static constexpr int kTickHz = 30;
	static constexpr float kTickDt = 1.0f / float(kTickHz);

	// Advances the sim by one fixed tick. Called from Main._physics_process so
	// its place in the frame is explicit rather than decided by tree order.
	void step();

	int get_tick_count() const;
	godot::String get_version() const;

	// ------------------------------------------------------------ grid
	// A grid of `cell`-metre cells covering `size` metres from `origin` (XZ).
	void configure_grid(const godot::Vector2 &origin, const godot::Vector2 &size, float cell);
	void set_heightmap(const godot::PackedFloat32Array &heights, int size, const godot::Vector2 &origin, float spacing);
	// Polygon p's corners are points[starts[p] .. starts[p + 1]).
	void mark_walkable_polygons(const godot::PackedVector2Array &points, const godot::PackedInt32Array &starts);
	// `outlines` is an Array of PackedVector2Array, in world XZ.
	void set_blocker(int64_t key, const godot::Array &outlines);
	void clear_blocker(int64_t key);
	// Call once the grid and its first stamps are in (see NavGrid::rebuild_regions).
	void finish_grid();
	bool is_walkable(const godot::Vector2 &point) const;
	float height_at(const godot::Vector2 &point) const;
	bool has_line_of_sight(const godot::Vector2 &from, const godot::Vector2 &to) const;
	// {origin, cols, rows, cell, blockers}
	godot::Dictionary get_grid_info() const;
	// One byte per cell, row-major: 0 not walkable terrain, 1 open, 2 stamped.
	godot::PackedByteArray get_grid_cells() const;
	// The same cells as RGBA8 for the debug overlay: unwalkable terrain blue,
	// stamped footprints red, open ground transparent.
	godot::PackedByteArray get_grid_debug_rgba() const;

	// ----------------------------------------------------------- units
	// A new unit arrives as a formation of one. Returns its id.
	int add_unit(int team, const godot::Vector2 &position, float radius, float speed);
	void remove_unit(int id);
	int get_unit_count() const;
	int get_unit_formation(int id) const;

	// What a unit's own logic wants this tick: a velocity in m/s (XZ), a mix
	// of MOTION_* flags, the sim id of the unit it is attacking (-1 for
	// none), and its top speed right now. With MOTION_FOLLOW the velocity is
	// ignored and the sim walks it to its place in its formation. Held until
	// the next call.
	void set_unit_motion(int id, const godot::Vector2 &desired, int flags, int attack_target, float max_speed);
	// Puts a unit somewhere directly (a teleport); movement never needs it.
	void set_unit_position(int id, const godot::Vector2 &position);
	// Six floats per unit that moved last tick: id, x, ground height, z, and
	// its velocity x, z.
	godot::PackedFloat32Array get_moved_units() const;
	// Units that could not go where they wanted last tick.
	godot::PackedInt32Array get_wedged_units() const;
	// Every unit whose body reaches into the circle (capture zones and the
	// like, now that units have no physics body to overlap an Area3D with).
	godot::PackedInt32Array get_units_in_circle(const godot::Vector2 &centre, float radius) const;
	// Sight: how far unit `id` sees, and whether any living unit of `team`
	// has `point` within its own sight (as of the last tick).
	void set_unit_vision(int id, float range);
	// A unit changing sides (captured, adopted by a scenario).
	void set_unit_team(int id, int team);
	// Seconds between a man's blows when he fights from his place, and the
	// blows due this tick (attacker, target pairs; see World::update_swings).
	void set_unit_cooldown(int id, float seconds);
	godot::PackedInt32Array get_swings() const;
	bool team_sees(int team, const godot::Vector2 &point) const;
	// How many melee men other than `exclude` are going for `target` (their
	// attack target as of the last tick) from within `radius` of it, counting
	// no further than `limit`.
	int count_melee_attackers(int target, float radius, int exclude, int limit) const;
	// The living units within `radius` of `centre`, nearest first (as of the
	// last tick). `not_team` >= 0 leaves that team's units out.
	godot::PackedInt32Array get_units_near(const godot::Vector2 &centre, float radius, int not_team) const;
	// One unit's steering state, for debugging: {position, place, detour
	// (cells left), pending, wedged, on_open, place_open, place_in_sight,
	// route, velocity, motion, max_speed}.
	godot::Dictionary get_unit_debug(int id);

	enum MotionFlag {
		MOTION_PINNED = army::MotionPinned,
		MOTION_UNCLAMPED = army::MotionUnclamped,
		MOTION_GHOST = army::MotionGhost,
		MOTION_FOLLOW = army::MotionFollow,
		MOTION_FIGHT = army::MotionFight,
	};

	// ---------------------------------------------------------- combat
	// How close an enemy must be for this unit to hit it, how far it looks
	// for one itself (its sight), and whether it shoots.
	void set_unit_combat(int id, float reach, float pick_radius, bool ranged);
	// Two ints per unit fighting from its place (MOTION_FIGHT): its id and
	// the id of the enemy it should hit, or -1 for none in reach.
	godot::PackedInt32Array get_fight_targets() const;
	// The block goes for enemy unit `target` (or, with -1, the fixed point —
	// a building), its front rank stopping `engage_distance` short.
	void order_attack(int formation, int target, const godot::Vector2 &point, float engage_distance);
	// Three floats per block on an attack order: id, facing, engaged (0/1).
	godot::PackedFloat32Array get_attacking_formations() const;
	// A unit has fallen: the rearmost man of its block steps into its place.
	void unit_died(int id);

	// ------------------------------------------------------ formations
	// Moves the units into a new formation, in slot order (front rank first,
	// left to right). `front_centre` and `facing` (radians, forward is
	// (cos, sin) in world XZ) place the block. The last `trailing` ids ride
	// behind the ranks (officers). Returns its id, or -1.
	int form(const godot::PackedInt32Array &unit_ids, const godot::Vector2 &front_centre, float facing, int trailing);
	// Puts the unit in a formation of one of its own at `position`.
	int release(int unit_id, const godot::Vector2 &position);
	void set_layout(int formation, int columns, float spacing, bool loose);
	// Walking pace in m/s; negative follows the slowest member.
	void set_speed(int formation, float speed);
	int get_formation_count() const;
	// Slot order: front rank first, officers last.
	godot::PackedInt32Array get_formation_members(int formation) const;
	// {position: Vector2, facing, moving, queued}
	godot::Dictionary get_formation_info(int formation) const;

	// ----------------------------------------------------------- orders
	// `face` turns the block to `facing` once it arrives.
	void order_move(int formation, const godot::Vector2 &destination, bool face, float facing);
	// Marched once everything already ordered is done (a shift-queued leg).
	void queue_move(int formation, const godot::Vector2 &destination, bool face, float facing);
	// Formations that finished their last leg during the last tick.
	godot::PackedInt32Array get_arrived_formations() const;
	// Blocks with an enemy near them, found during the last tick.
	godot::PackedInt32Array get_enemy_alerts() const;
	void order_hold(int formation);

	// -------------------------------------------------------- readback
	// Eight floats per formation of at least `min_members`:
	// id, x, y, ground height, facing, members, moving (0/1), speed.
	godot::PackedFloat32Array get_formation_states(int min_members) const;
	// The route still ahead of the formation, from where it stands, on the ground.
	godot::PackedVector3Array get_formation_path(int formation) const;
	// Every member's place this tick, on the ground, for formations of at
	// least `min_members`.
	godot::PackedVector3Array get_slot_targets(int min_members) const;
	// {searches, expanded, deferred} for the last tick.
	godot::Dictionary get_path_stats() const;

	// ---------------------------------------------------------- profile
	// Zone name -> milliseconds spent in the last tick.
	godot::Dictionary get_profile() const;
	// Zone name -> worst tick since the last reset.
	godot::Dictionary get_profile_peaks() const;
	void reset_profile_peaks();

private:
	army::World world_;
	float max_vision_ = 0.0f; // the longest sight set, bounding team_sees' search
	int tick_count_ = 0;
};

VARIANT_ENUM_CAST(ArmySim::MotionFlag);
