// The simulation proper: grid, units and formations, and the fixed order they
// are advanced in each tick. No Godot types in here; ArmySim is the boundary.
//
// Formations own the tactical truth. A formation is a position (the centre of
// its front rank), a facing, a layout, an order and a route; it is what gets
// ordered and what pathfinds. A unit only ever belongs to one formation and its
// only goal is its place in it. Every unit is always in a formation: a loose
// unit is simply a formation of one.

#pragma once

#include <cstdint>
#include <vector>

#include "nav_grid.h"
#include "profiler.h"
#include "sim_math.h"
#include "spatial_hash.h"
#include "unit_store.h"

namespace army {

enum FormationFlag : uint32_t {
	FlagAlive = 1u << 0,
	// Has somewhere to go: follows its route until it arrives.
	FlagMoving = 1u << 1,
	// Turns to `final_facing` once it arrives.
	FlagFinalFacing = 1u << 2,
	// Going for an enemy (World::order_attack) rather than a place.
	FlagAttacking = 1u << 3,
};

struct Waypoint {
	Vec2 dest;
	float facing = 0.0f;
	bool has_facing = false;
};

struct FormationStore {
	std::vector<float> pos_x, pos_y; // centre of the front rank
	std::vector<float> vel_x, vel_y;
	std::vector<float> facing; // radians; forward is (cos, sin) in world XZ
	std::vector<float> final_facing;
	std::vector<float> dest_x, dest_y;
	// Walking pace. Negative follows the slowest member.
	std::vector<float> speed_override;
	std::vector<float> speed; // resolved
	std::vector<uint32_t> flags;
	std::vector<uint8_t> team;

	// Layout: ranks of up to `columns`, `spacing` apart, rows balanced and
	// centred; `loose` roughens every place by a small fixed amount per unit.
	// The last `trailing` members are not in the ranks at all: they ride
	// behind the block (a regiment's officer).
	std::vector<uint16_t> columns;
	std::vector<float> spacing;
	std::vector<uint8_t> loose;
	std::vector<uint16_t> trailing;
	// Legs still to march after the current one (shift-queued orders).
	std::vector<std::vector<Waypoint>> queue;

	// An attack order: the enemy unit it is going for (kInvalidId for a fixed
	// point, a building), where that is, and how far short of it the front
	// rank stops (0 for melee: into contact).
	std::vector<uint32_t> target_unit;
	std::vector<float> target_x, target_y;
	std::vector<float> engage_distance;
	std::vector<uint8_t> engaged; // a man in it had someone in reach last tick
	// Each member's place relative to the front centre (x right, y forward),
	// rebuilt only when membership or layout changes.
	std::vector<std::vector<Vec2>> local_slots;

	// members[f][slot] is the unit standing in that slot.
	std::vector<std::vector<uint32_t>> members;

	std::vector<std::vector<Vec2>> path;
	std::vector<uint32_t> path_index;
	std::vector<uint8_t> repath;

	std::vector<uint32_t> free_ids;
	uint32_t live = 0;

	uint32_t capacity() const { return uint32_t(flags.size()); }
	bool alive(uint32_t f) const { return f < capacity() && (flags[f] & FlagAlive); }
};

struct PathStats {
	uint32_t searches = 0; // this tick
	uint32_t expanded = 0; // this tick
	uint32_t deferred = 0; // formations still waiting for a route
};

class World {
public:
	static constexpr float kTickDt = 1.0f / 30.0f;
	static constexpr float kDefaultSpacing = 1.3f;

	// ---- Block movement, ported from Very War (BattleWorld::update_formation_motion
	// and update_steering) so it feels the same: the block leads at its men's
	// full pace and they flow after it under bounded acceleration. ----
	// How fast a formation wheels. Bounded so a block turns as a manoeuvre
	// rather than snapping round.
	static constexpr float kTurnRate = 3.5f;
	// m/s^2, for the block and for every man following his place.
	static constexpr float kAcceleration = 30.0f;
	// A route point closer than this is passed.
	static constexpr float kWaypointReach = 2.0f;
	// The block stops heading for a point once this close to it.
	static constexpr float kStopDistance = 0.5f;
	// How hard a man closes the gap between the velocity he has and the one
	// he wants, per second: kSettleResponse on his place, rising to kResponse
	// with somewhere to go. Very War's is 1 throughout (a one-second lag),
	// which read as sluggish on the order and let a man arriving overshoot his
	// place and swing back. The stiffer answer only made a standing block
	// drift while neighbours kept pushing each other, which the separation
	// reach (see kSeparationSpacingFraction) and cohesion fading on the place
	// now stop.
	static constexpr float kResponse = 7.0f;
	static constexpr float kSettleResponse = 4.0f;
	// Men may run this much over their pace to catch their places up.
	static constexpr float kOverspeed = 1.3f;
	// How far friends push each other apart: this much of the block's spacing
	// (Very War's 1.1 of its 1.3), so men on their places — a spacing apart —
	// leave each other be; a lone man (or a loose block) keeps the full reach.
	// Enemies always push from kFollowSeparationRadius.
	static constexpr float kFollowSeparationRadius = 1.1f;
	static constexpr float kSeparationSpacingFraction = 0.8f;
	static constexpr float kMinSeparationRadius = 0.6f;
	static constexpr float kSeekWeight = 1.0f;
	static constexpr float kFollowSeparationWeight = 2.2f;
	static constexpr float kCohesionWeight = 0.25f;
	static constexpr float kAlignmentWeight = 0.35f;
	static constexpr float kEnemyPressureWeight = 1.4f;
	// Enemies push this much harder than friends, inside the sum: it is what
	// makes a contact line instead of two blocks merging.
	static constexpr float kEnemyPushScale = 1.6f;

	// ---- Getting round things (not in Very War, which has none) ----
	// A place that lands on something solid moves to open ground this near.
	static constexpr float kPlaceSnapRadius = 3.0f;
	// Men this close to their place never look for a way round.
	static constexpr float kDetourMinDistance = 1.0f;
	// How often (ticks) a man checks he can still see his place; a man who got
	// wedged checks at once.
	static constexpr uint32_t kSightCheckTicks = 8;
	// One detour search's cap, and all detour searches' cap per tick; men over
	// budget slide along the edge for a tick or two until their turn.
	static constexpr uint32_t kDetourMaxExpansions = 12000;
	static constexpr uint32_t kDetourTickBudget = 12000;
	// A detour point closer than this is passed.
	static constexpr float kDetourReach = 0.6f;
	// Separation's cap while detouring, as a multiple of pace (2 otherwise).
	static constexpr float kDetourSeparationScale = 0.3f;

	// ---- Fighting as a block ----
	// Where a block whose enemy died looks for the next one.
	static constexpr float kRetargetRadius = 10.0f;
	// Closer than this to its enemy a block stops turning to face it: with
	// the enemy right at its front, every shove would swing the whole block
	// (and every man's place) from side to side.
	static constexpr float kFaceEnemyMinDistance = 3.0f;
	// A pursued enemy that has moved this far from the route's end gets a new
	// route, checked every kPursuitTicks (staggered per formation).
	static constexpr float kPursuitDrift = 4.0f;
	static constexpr uint32_t kPursuitTicks = 15;
	// A man with a target keeps it while it stays this much past his reach.
	static constexpr float kReachSlack = 0.3f;
	// Ranged men look for a new target this often (ticks, staggered); melee
	// every tick, since theirs is a tiny search.
	static constexpr uint32_t kRangedRetargetTicks = 8;
	// Every other man already on a target makes it look this much further
	// away, which spreads a line's blows (melee) and volleys (ranged) along
	// the enemy instead of piling onto one — Unit.MELEE_CROWD_PENALTY and
	// RANGED_SPREAD_PENALTY.
	static constexpr float kMeleeCrowdPenalty = 1.0f;
	static constexpr float kRangedCrowdPenalty = 3.0f;
	// Once his block is in the fight, a melee man with nobody in reach goes
	// for the nearest enemy this close (checked every kSeekTicks, staggered):
	// the whole block closes on the enemy, and a wide one wraps round a
	// small one, instead of all but its front rank standing in their places.
	static constexpr float kEngageSeekRadius = 8.0f;
	static constexpr uint32_t kSeekTicks = 4;
	// A man going for an enemy stops this fraction of his reach short of him.
	static constexpr float kEngageStandOff = 0.75f;
	// A block checks every kAlertTicks (staggered) for an enemy within this
	// of its edge, so men who have stopped running their own scripts can be
	// woken to look for themselves (Unit.wake).
	static constexpr float kAlertRadius = 14.0f;
	static constexpr uint32_t kAlertTicks = 8;
	// Cells one search may visit before it settles for the closest it got.
	static constexpr uint32_t kMaxExpansions = 250000;
	// Cells the path stage may visit per tick, across all searches; a search
	// that needs more carries on next tick. ~2-3 ms.
	static constexpr uint32_t kTickExpansionBudget = 20000;

	// Separation, as Unit._separation_push had it: a linear push from anyone
	// closer than kSeparationDistance, kSeparationSpeed at full overlap,
	// capped at kSeparationMaxSpeed however many are pressing.
	static constexpr float kSeparationDistance = 0.85f;
	static constexpr float kSeparationSpeed = 3.0f;
	static constexpr float kSeparationMaxSpeed = 2.5f;
	// Neighbours one unit considers per tick. Bounds the work in a crush,
	// which is exactly when armies meet and the frame can least afford it.
	static constexpr int kMaxNeighbours = 12;
	// A unit following its place eases off inside this, instead of vibrating
	// round the exact point forever.
	static constexpr float kArriveRadius = 0.6f;
	// How far behind the rear rank an officer rides.
	static constexpr float kOfficerStandoff = 2.4f;
	// Most a Loose place is moved off its grid point, either way.
	static constexpr float kLooseJitter = 0.45f;
	// Sent further round than this, a block turns about rather than wheeling:
	// its rear rank becomes its front.
	static constexpr float kTurnAboutAngle = 2.3f;

	NavGrid grid;
	SpatialHash hash;
	UnitStore units;
	FormationStore formations;
	Profiler profiler;

	void tick();

	// ------------------------------------------------------------ units
	// A new unit arrives as a formation of one.
	uint32_t add_unit(uint8_t team, Vec2 position, float radius, float speed);
	void remove_unit(uint32_t u);

	// -------------------------------------------------------- formations
	// Moves the listed units into a new formation, in slot order, emptying
	// (and so ending) whatever formations they were in.
	uint32_t form(const std::vector<uint32_t> &unit_ids, Vec2 front_centre, float facing, uint16_t trailing = 0);
	// Takes `u` out of its formation into a formation of one of its own.
	uint32_t release(uint32_t u, Vec2 position);
	void set_layout(uint32_t f, uint16_t columns, float spacing, bool loose);
	void set_speed(uint32_t f, float speed);

	// Called once the grid is configured; sizes the spatial hash to match.
	void configure_hash();

	void set_unit_motion(uint32_t u, Vec2 desired, uint8_t motion, uint32_t attack_target, float max_speed);
	void set_unit_position(uint32_t u, Vec2 position);

	// Replaces whatever the formation was doing, queue included.
	// Goes for `target_unit` (or, with kInvalidId, the fixed `point`), its
	// front rank stopping `engage_distance` short. Follows a unit that moves,
	// stops once in contact, and takes the nearest enemy near it when the
	// target dies; runs out (an `arrived` event) when there is none.
	void order_attack(uint32_t f, uint32_t target_unit, Vec2 point, float engage_distance);
	// A man falls: the rearmost man of his block steps into his place, and he
	// stops being a body.
	void unit_died(uint32_t u);
	void set_unit_combat(uint32_t u, float reach, float pick_radius, bool ranged);

	void order_move(uint32_t f, Vec2 destination, bool has_facing, float facing);
	// Marched after everything already ordered; at once if it has nothing.
	void queue_move(uint32_t f, Vec2 destination, bool has_facing, float facing);
	void order_hold(uint32_t f);

	// Formations whose orders ran out (last leg reached) during the last tick.
	const std::vector<uint32_t> &arrived() const { return arrived_; }
	// Blocks with an enemy near them, found this tick.
	const std::vector<uint32_t> &alerts() const { return alerts_; }
	// This tick's blows: attacker, target, attacker, target...
	const std::vector<uint32_t> &swings() const { return swings_; }

	PathStats path_stats() const { return path_stats_; }

private:
	uint32_t new_formation(uint8_t team, Vec2 pos, float facing);
	void end_formation(uint32_t f);
	void detach(uint32_t u);
	void rebuild_slots(uint32_t f);
	void resolve_speed(uint32_t f);

	void update_paths();
	void update_formation_motion();
	void update_slot_targets();
	void rebuild_spatial_hash();
	void update_steering();
	// One man following his place (Very War's boids); writes his next position.
	void steer_follower(uint32_t u, float dt, bool was_wedged);
	void plan_detours();
	// Where a unit at `pos` stepping by `step` actually ends up, sliding along
	// anything closed rather than stopping dead at it.
	// `follower`: a man holding his place, who also steps back off a corner he
	// is boxed into (others keep a steady wedged signal for their own escape).
	Vec2 clamp_step(Vec2 pos, Vec2 step, bool &wedged, bool follower = false) const;

	void turn_about(uint32_t f, float new_facing);
	void update_fight_targets();
	void update_swings();
	bool is_enemy(uint32_t a, uint32_t b) const { return units.team[a] != units.team[b]; }
	bool is_body(uint32_t u) const { return units.valid(u) && !(units.motion[u] & MotionGhost); }
	uint32_t nearest_enemy(Vec2 at, uint8_t team, float radius) const;
	// Where an attacking block's enemy is now, retargeting if it died; false
	// when there is nothing left to fight.
	bool attack_position(uint32_t f, Vec2 &out);
	uint8_t block_clearance(uint32_t f) const;
	std::vector<uint32_t> arrived_;
	std::vector<uint32_t> alerts_;
	std::vector<uint32_t> swings_;
	void update_alerts();
	std::vector<uint32_t> detour_requests_;
	std::vector<uint16_t> attacker_counts_; // scratch for update_fight_targets
	PathStats path_stats_;
	uint32_t tick_index_ = 0;
	// Round-robin start for the path stage, so a formation deferred for
	// budget is first in line next tick.
	uint32_t path_cursor_ = 0;
	// The formation whose search is still running across ticks, if any.
	uint32_t searching_ = kInvalidId;
};

} // namespace army
