#include "world.h"

#include <algorithm>
#include <cmath>

namespace army {

namespace {
constexpr float kPi = 3.14159265358979323846f;

// Shortest signed angular difference, in (-pi, pi].
float angle_delta(float from, float to) {
	float d = to - from;
	while (d > kPi) d -= 2.0f * kPi;
	while (d < -kPi) d += 2.0f * kPi;
	return d;
}

// A lone unit turns on the spot; only a block needs to wheel.
constexpr float kLoneTurnRate = 12.0f;
constexpr uint16_t kMaxDefaultColumns = 12;
} // namespace

void World::tick() {
	profiler.begin_tick();
	arrived_.clear();
	alerts_.clear();
	swings_.clear();
	{
		ARMY_PROFILE_ZONE(profiler, Zone::Tick);
		{
			ARMY_PROFILE_ZONE(profiler, Zone::Pathfinding);
			update_paths();
		}
		{
			ARMY_PROFILE_ZONE(profiler, Zone::FormationMotion);
			update_formation_motion();
		}
		{
			ARMY_PROFILE_ZONE(profiler, Zone::SlotTargets);
			update_slot_targets();
		}
		{
			ARMY_PROFILE_ZONE(profiler, Zone::SpatialHash);
			rebuild_spatial_hash();
		}
		{
			ARMY_PROFILE_ZONE(profiler, Zone::Combat);
			update_fight_targets();
			update_swings();
			update_alerts();
		}
		{
			ARMY_PROFILE_ZONE(profiler, Zone::Steering);
			update_steering();
		}
	}
	profiler.end_tick();
	++tick_index_;
}

// ------------------------------------------------------------------ units

uint32_t World::add_unit(uint8_t team, Vec2 position, float radius, float speed) {
	const uint32_t u = units.add(team, position, radius, speed);
	const uint32_t f = new_formation(team, position, 0.0f);
	formations.members[f].push_back(u);
	units.formation[u] = f;
	units.slot[u] = 0;
	rebuild_slots(f);
	resolve_speed(f);
	return u;
}

void World::remove_unit(uint32_t u) {
	if (!units.valid(u)) return;
	detach(u);
	units.remove(u);
}

// ------------------------------------------------------------- formations

uint32_t World::new_formation(uint8_t team, Vec2 pos, float facing) {
	FormationStore &fs = formations;
	if (fs.free_ids.empty()) {
		const uint32_t old = fs.capacity();
		const uint32_t cap = old == 0 ? 1024 : old * 2;
		for (auto *v : { &fs.pos_x, &fs.pos_y, &fs.vel_x, &fs.vel_y, &fs.facing, &fs.final_facing,
					 &fs.dest_x, &fs.dest_y, &fs.speed_override, &fs.speed, &fs.spacing }) {
			v->resize(cap, 0.0f);
		}
		fs.flags.resize(cap, 0);
		fs.team.resize(cap, 0);
		fs.columns.resize(cap, 1);
		fs.loose.resize(cap, 0);
		fs.trailing.resize(cap, 0);
		fs.queue.resize(cap);
		fs.target_unit.resize(cap, kInvalidId);
		fs.target_x.resize(cap, 0.0f);
		fs.target_y.resize(cap, 0.0f);
		fs.engage_distance.resize(cap, 0.0f);
		fs.engaged.resize(cap, 0);
		fs.local_slots.resize(cap);
		fs.members.resize(cap);
		fs.path.resize(cap);
		fs.path_index.resize(cap, 0);
		fs.repath.resize(cap, 0);
		for (uint32_t i = cap; i-- > old;) fs.free_ids.push_back(i);
	}
	const uint32_t f = fs.free_ids.back();
	fs.free_ids.pop_back();
	fs.pos_x[f] = pos.x; fs.pos_y[f] = pos.y;
	fs.vel_x[f] = 0.0f; fs.vel_y[f] = 0.0f;
	fs.facing[f] = facing;
	fs.final_facing[f] = facing;
	fs.dest_x[f] = pos.x; fs.dest_y[f] = pos.y;
	fs.speed_override[f] = -1.0f;
	fs.speed[f] = 0.0f;
	fs.flags[f] = FlagAlive;
	fs.team[f] = team;
	fs.columns[f] = 1;
	fs.spacing[f] = kDefaultSpacing;
	fs.loose[f] = 0;
	fs.trailing[f] = 0;
	fs.queue[f].clear();
	fs.target_unit[f] = kInvalidId;
	fs.engage_distance[f] = 0.0f;
	fs.engaged[f] = 0;
	fs.local_slots[f].clear();
	fs.members[f].clear();
	fs.path[f].clear();
	fs.path_index[f] = 0;
	fs.repath[f] = 0;
	++fs.live;
	return f;
}

void World::end_formation(uint32_t f) {
	if (!formations.alive(f)) return;
	formations.flags[f] = 0;
	formations.members[f].clear();
	formations.path[f].clear();
	formations.local_slots[f].clear();
	formations.queue[f].clear();
	formations.repath[f] = 0;
	formations.free_ids.push_back(f);
	--formations.live;
}

// Takes `u` out of whatever formation it is in. The units behind it close up
// one place, so a block keeps its order; a formation left empty ends.
void World::detach(uint32_t u) {
	const uint32_t f = units.formation[u];
	units.formation[u] = kInvalidId;
	if (!formations.alive(f)) return;
	auto &members = formations.members[f];
	auto it = std::find(members.begin(), members.end(), u);
	if (it == members.end()) return;
	if (size_t(it - members.begin()) >= members.size() - formations.trailing[f] && formations.trailing[f] > 0) {
		--formations.trailing[f];
	}
	members.erase(it);
	if (members.empty()) {
		end_formation(f);
		return;
	}
	for (size_t i = 0; i < members.size(); ++i) units.slot[members[i]] = uint16_t(i);
	rebuild_slots(f);
	resolve_speed(f);
}

uint32_t World::form(const std::vector<uint32_t> &unit_ids, Vec2 front_centre, float facing, uint16_t trailing) {
	std::vector<uint32_t> joining;
	joining.reserve(unit_ids.size());
	for (uint32_t u : unit_ids) {
		if (units.valid(u) && std::find(joining.begin(), joining.end(), u) == joining.end()) joining.push_back(u);
	}
	if (joining.empty()) return kInvalidId;
	for (uint32_t u : joining) detach(u);
	const uint32_t f = new_formation(units.team[joining[0]], front_centre, facing);
	formations.members[f] = joining;
	for (size_t i = 0; i < joining.size(); ++i) {
		units.formation[joining[i]] = f;
		units.slot[joining[i]] = uint16_t(i);
	}
	const uint16_t n = uint16_t(joining.size());
	formations.trailing[f] = std::min<uint16_t>(trailing, uint16_t(n - 1));
	formations.columns[f] = std::clamp<uint16_t>(uint16_t(std::ceil(std::sqrt(float(n)))), 1, kMaxDefaultColumns);
	rebuild_slots(f);
	resolve_speed(f);
	return f;
}

uint32_t World::release(uint32_t u, Vec2 position) {
	if (!units.valid(u)) return kInvalidId;
	return form({ u }, position, formations.alive(units.formation[u]) ? formations.facing[units.formation[u]] : 0.0f);
}

void World::set_layout(uint32_t f, uint16_t columns, float spacing, bool loose) {
	if (!formations.alive(f)) return;
	formations.columns[f] = std::max<uint16_t>(1, columns);
	formations.spacing[f] = spacing > 0.0f ? spacing : kDefaultSpacing;
	formations.loose[f] = loose ? 1 : 0;
	rebuild_slots(f);
}

void World::set_speed(uint32_t f, float speed) {
	if (!formations.alive(f)) return;
	formations.speed_override[f] = speed;
	resolve_speed(f);
}

// Ranks of up to `columns`, each rank holding an even share of what is left
// and centred on the front's centre line, so a partial rear rank sits in the
// middle rather than off to one side.
void World::rebuild_slots(uint32_t f) {
	FormationStore &fs = formations;
	const auto &members = fs.members[f];
	const int total = int(members.size());
	const int trailing = std::min(int(fs.trailing[f]), std::max(0, total - 1));
	const int n = total - trailing;
	auto &slots = fs.local_slots[f];
	slots.clear();
	if (total == 0) return;
	const int columns = std::clamp(int(fs.columns[f]), 1, n);
	const float spacing = fs.spacing[f];
	const int rows = (n + columns - 1) / columns;
	int placed = 0;
	for (int row = 0; row < rows; ++row) {
		const int remaining = n - placed;
		const int rows_left = rows - row;
		const int in_row = std::clamp((remaining + rows_left - 1) / rows_left, 1, columns);
		for (int col = 0; col < in_row; ++col) {
			Vec2 place((float(col) - float(in_row - 1) * 0.5f) * spacing, -float(row) * spacing);
			if (fs.loose[f]) {
				// Fixed per unit, so a loose block does not shimmer: without it
				// Loose reads as a sparse grid.
				const uint32_t h = (members[placed] * 2654435761u) ^ 0x9e3779b9u;
				place.x += (float((h >> 8) & 0xFF) / 255.0f - 0.5f) * 2.0f * kLooseJitter;
				place.y += (float((h >> 16) & 0xFF) / 255.0f - 0.5f) * 2.0f * kLooseJitter;
			}
			slots.push_back(place);
			++placed;
		}
	}
	// Officers ride behind the rear rank on the centre line, spread sideways
	// if a block somehow has several.
	const float rear = -float(std::max(0, rows - 1)) * spacing - kOfficerStandoff;
	for (int i = 0; i < trailing; ++i) {
		slots.push_back({ (float(i) - float(trailing - 1) * 0.5f) * spacing, rear });
	}
}

void World::resolve_speed(uint32_t f) {
	float speed = formations.speed_override[f];
	if (speed < 0.0f) {
		speed = 1e30f;
		for (uint32_t u : formations.members[f]) speed = std::min(speed, units.speed[u]);
		if (speed > 1e29f) speed = 0.0f;
	}
	formations.speed[f] = speed;
}

// The rear rank becomes the front: the ranked members are renumbered back to
// front and the block's front moves to where its rear stood, so a block sent
// the other way turns about instead of marching through itself.
void World::turn_about(uint32_t f, float new_facing) {
	FormationStore &fs = formations;
	auto &members = fs.members[f];
	const int trailing = fs.trailing[f];
	const int n = int(members.size()) - trailing;
	if (n < 2) return;
	const int columns = std::clamp(int(fs.columns[f]), 1, n);
	const int rows = (n + columns - 1) / columns;
	const float depth = float(rows - 1) * fs.spacing[f];
	const float c = std::cos(fs.facing[f]), s = std::sin(fs.facing[f]);
	fs.pos_x[f] -= c * depth;
	fs.pos_y[f] -= s * depth;
	std::reverse(members.begin(), members.begin() + n);
	for (size_t i = 0; i < members.size(); ++i) units.slot[members[i]] = uint16_t(i);
	fs.facing[f] = new_facing;
	rebuild_slots(f);
}

void World::queue_move(uint32_t f, Vec2 destination, bool has_facing, float facing) {
	if (!formations.alive(f)) return;
	if (!(formations.flags[f] & FlagMoving) && formations.queue[f].empty()) {
		order_move(f, destination, has_facing, facing);
		return;
	}
	formations.queue[f].push_back({ destination, facing, has_facing });
}

void World::order_move(uint32_t f, Vec2 destination, bool has_facing, float facing) {
	if (!formations.alive(f)) return;
	formations.queue[f].clear();
	formations.flags[f] &= ~FlagAttacking;
	if (has_facing && formations.members[f].size() > 1 &&
			std::fabs(angle_delta(formations.facing[f], facing)) > kTurnAboutAngle) {
		turn_about(f, facing);
	}
	formations.dest_x[f] = destination.x;
	formations.dest_y[f] = destination.y;
	formations.flags[f] |= FlagMoving;
	if (has_facing) {
		formations.flags[f] |= FlagFinalFacing;
		formations.final_facing[f] = facing;
	} else {
		formations.flags[f] &= ~FlagFinalFacing;
	}
	// Planned in the path stage, never here: a burst of orders in one frame
	// must not become a burst of searches inside the order handler.
	formations.repath[f] = 1;
}

void World::set_unit_combat(uint32_t u, float reach, float pick_radius, bool ranged) {
	if (!units.valid(u)) return;
	units.reach[u] = reach;
	units.pick_radius[u] = pick_radius;
	units.ranged[u] = ranged ? 1 : 0;
}

void World::order_attack(uint32_t f, uint32_t target_unit, Vec2 point, float engage_distance) {
	if (!formations.alive(f)) return;
	FormationStore &fs = formations;
	fs.queue[f].clear();
	fs.target_unit[f] = units.valid(target_unit) ? target_unit : kInvalidId;
	const Vec2 at = fs.target_unit[f] != kInvalidId ? Vec2(units.pos_x[target_unit], units.pos_y[target_unit]) : point;
	fs.target_x[f] = at.x;
	fs.target_y[f] = at.y;
	fs.engage_distance[f] = engage_distance;
	fs.engaged[f] = 0;
	fs.flags[f] |= FlagAttacking | FlagMoving;
	fs.flags[f] &= ~FlagFinalFacing;
	// Aim the route at the line the front rank should stop on.
	const Vec2 pos(fs.pos_x[f], fs.pos_y[f]);
	Vec2 dir = at - pos;
	const float d = length(dir);
	dir = d > 1e-3f ? dir * (1.0f / d) : Vec2(std::cos(fs.facing[f]), std::sin(fs.facing[f]));
	const Vec2 stop = d > engage_distance ? at - dir * engage_distance : pos;
	fs.dest_x[f] = stop.x;
	fs.dest_y[f] = stop.y;
	fs.repath[f] = 1;
}

// The rearmost man of the ranks steps into the fallen man's place — a gap
// in the front is filled from behind, and the block closes up by one — and
// the fallen man stays a corpse, no longer part of anything.
void World::unit_died(uint32_t u) {
	if (!units.valid(u)) return;
	const uint32_t f = units.formation[u];
	units.motion[u] = MotionGhost;
	units.fight_target[u] = kInvalidId;
	units.detour[u].clear();
	if (!formations.alive(f)) return;
	auto &members = formations.members[f];
	const auto it = std::find(members.begin(), members.end(), u);
	if (it == members.end()) return;
	const size_t k = size_t(it - members.begin());
	const size_t ranked = members.size() - formations.trailing[f];
	if (k < ranked && ranked > 1) {
		const size_t rear = ranked - 1;
		members[k] = members[rear];
		units.slot[members[k]] = uint16_t(k);
		members.erase(members.begin() + rear);
	} else {
		if (k >= ranked && formations.trailing[f] > 0) --formations.trailing[f];
		members.erase(it);
	}
	units.formation[u] = kInvalidId;
	if (members.empty()) {
		end_formation(f);
		return;
	}
	for (size_t i = 0; i < members.size(); ++i) units.slot[members[i]] = uint16_t(i);
	rebuild_slots(f);
}

void World::update_alerts() {
	FormationStore &fs = formations;
	for (uint32_t f = 0; f < fs.capacity(); ++f) {
		if (!fs.alive(f) || (tick_index_ + f) % kAlertTicks != 0) continue;
		bool following = false;
		for (uint32_t u : fs.members[f]) {
			if (units.motion[u] & MotionFollow) { following = true; break; }
		}
		if (!following) continue;
		// Its edge: the far corner of its layout, roughly.
		const float extent = float(std::max<size_t>(fs.columns[f], fs.members[f].size() / std::max<uint16_t>(1, fs.columns[f]))) * fs.spacing[f];
		if (nearest_enemy({ fs.pos_x[f], fs.pos_y[f] }, fs.team[f], extent + kAlertRadius) != kInvalidId) {
			alerts_.push_back(f);
		}
	}
}

uint32_t World::nearest_enemy(Vec2 at, uint8_t team, float radius) const {
	uint32_t best = kInvalidId;
	float best_d = radius * radius;
	hash.query(at.x, at.y, radius, [&](uint32_t o) {
		if (units.team[o] == team || (units.motion[o] & MotionGhost)) return true;
		const float d = dist_sq(at, { units.pos_x[o], units.pos_y[o] });
		if (d < best_d) { best_d = d; best = o; }
		return true;
	});
	return best;
}

bool World::attack_position(uint32_t f, Vec2 &out) {
	FormationStore &fs = formations;
	uint32_t t = fs.target_unit[f];
	if (t == kInvalidId) {
		out = Vec2(fs.target_x[f], fs.target_y[f]);
		return true;
	}
	if (!is_body(t)) {
		// Its enemy fell: the nearest one near the block, if any.
		t = nearest_enemy({ fs.pos_x[f], fs.pos_y[f] }, fs.team[f], kRetargetRadius);
		fs.target_unit[f] = t;
		if (t == kInvalidId) return false;
		fs.repath[f] = 1;
	}
	out = Vec2(units.pos_x[t], units.pos_y[t]);
	fs.target_x[f] = out.x;
	fs.target_y[f] = out.y;
	return true;
}

// Every man fighting from his place gets the nearest enemy he can hit — or,
// for a ranged man, the nearest he can see (his block's ordered enemy at his
// full reach) — made a little less attractive for every man already on it.
// He keeps a target while it stays in reach, so blows are not spread thin.
// Every man fighting from his place strikes his fight target each time his
// cooldown comes round; with nobody in reach he stays ready, so the first
// blow lands the moment someone steps in. The blow itself (damage, charges,
// the swing) is the game's to settle: this only says when.
void World::update_swings() {
	const uint32_t n = units.capacity();
	for (uint32_t u = 0; u < n; ++u) {
		if (!units.alive[u] || !(units.motion[u] & MotionFight) || (units.motion[u] & MotionGhost)) continue;
		const uint32_t t = units.fight_target[u];
		float &timer = units.swing_timer[u];
		timer += kTickDt;
		if (t == kInvalidId) {
			timer = std::min(timer, units.cooldown[u]);
			continue;
		}
		if (timer < units.cooldown[u]) continue;
		timer = 0.0f;
		swings_.push_back(u);
		swings_.push_back(t);
	}
}

void World::update_fight_targets() {
	const uint32_t n = units.capacity();
	std::vector<uint16_t> &attackers = units.attackers;
	std::vector<uint16_t> &counts = attacker_counts_;
	counts.assign(n, 0);
	for (uint32_t u = 0; u < n; ++u) {
		if (!units.alive[u] || !(units.motion[u] & MotionFight) || (units.motion[u] & MotionGhost)) {
			units.fight_target[u] = kInvalidId;
			units.seek_enemy[u] = kInvalidId;
			continue;
		}
		const Vec2 pos(units.pos_x[u], units.pos_y[u]);
		const float reach = units.reach[u];
		const bool ranged = units.ranged[u] != 0;
		uint32_t t = units.fight_target[u];
		if (t != kInvalidId && (!is_body(t) || !is_enemy(u, t) ||
					dist_sq(pos, { units.pos_x[t], units.pos_y[t] }) > (reach + kReachSlack) * (reach + kReachSlack))) {
			t = kInvalidId;
		}
		if (t == kInvalidId && (!ranged || (tick_index_ + u) % kRangedRetargetTicks == 0)) {
			// The block's own enemy first, if he can reach it.
			const uint32_t f = units.formation[u];
			if (formations.alive(f) && (formations.flags[f] & FlagAttacking)) {
				const uint32_t ordered = formations.target_unit[f];
				if (ordered != kInvalidId && is_body(ordered) &&
						dist_sq(pos, { units.pos_x[ordered], units.pos_y[ordered] }) <= reach * reach) {
					t = ordered;
				}
			}
			if (t == kInvalidId) {
				const float radius = ranged ? std::min(reach, units.pick_radius[u]) : reach;
				const float penalty = ranged ? kRangedCrowdPenalty : kMeleeCrowdPenalty;
				float best = 1e30f;
				const uint8_t team = units.team[u];
				hash.query(pos.x, pos.y, radius, [&](uint32_t o) {
					if (units.team[o] == team || (units.motion[o] & MotionGhost)) return true;
					const float d = std::sqrt(dist_sq(pos, { units.pos_x[o], units.pos_y[o] }));
					if (d > radius) return true;
					const float score = d + float(attackers[o]) * penalty;
					if (score < best) { best = score; t = o; }
					return true;
				});
			}
		}
		units.fight_target[u] = t;
		if (t != kInvalidId) ++counts[t];

		// Melee in an attacking block that is in the fight: go for someone.
		uint32_t seek = kInvalidId;
		const uint32_t f = units.formation[u];
		if (!ranged && formations.alive(f) && (formations.flags[f] & FlagAttacking) && formations.engaged[f]) {
			if (t != kInvalidId) {
				seek = t;
			} else {
				seek = units.seek_enemy[u];
				const bool stale = seek == kInvalidId || !is_body(seek) || !is_enemy(u, seek) ||
						dist_sq(pos, { units.pos_x[seek], units.pos_y[seek] }) > kEngageSeekRadius * kEngageSeekRadius;
				if (stale) seek = kInvalidId;
				if (seek == kInvalidId || (tick_index_ + u) % kSeekTicks == 0) {
					// The nearest enemy, made less attractive by those already on
					// him, so the rear flows round to the free sides.
					float best = 1e30f;
					const uint8_t team = units.team[u];
					uint32_t pick = seek;
					hash.query(pos.x, pos.y, kEngageSeekRadius, [&](uint32_t o) {
						if (units.team[o] == team || (units.motion[o] & MotionGhost)) return true;
						const float d = std::sqrt(dist_sq(pos, { units.pos_x[o], units.pos_y[o] }));
						if (d > kEngageSeekRadius) return true;
						const float score = d + float(attackers[o]) * kMeleeCrowdPenalty;
						if (score < best) { best = score; pick = o; }
						return true;
					});
					seek = pick;
				}
			}
		}
		units.seek_enemy[u] = seek;
	}
	attackers.swap(counts);
	// A block with any man in reach of an enemy is in contact.
	for (uint32_t f = 0; f < formations.capacity(); ++f) {
		if (!formations.alive(f)) continue;
		uint8_t engaged = 0;
		for (uint32_t m : formations.members[f]) {
			if (units.fight_target[m] != kInvalidId && !units.ranged[m]) { engaged = 1; break; }
		}
		formations.engaged[f] = engaged;
	}
}

void World::order_hold(uint32_t f) {
	if (!formations.alive(f)) return;
	formations.flags[f] &= ~(FlagMoving | FlagAttacking);
	formations.path[f].clear();
	formations.repath[f] = 0;
}

// ------------------------------------------------------------ tick stages

// How far (cells) the block's route should keep from anything solid: half its
// frontage, so its flanks clear what its front centre passes. None for a
// lone man.
uint8_t World::block_clearance(uint32_t f) const {
	const FormationStore &fs = formations;
	const int ranked = int(fs.members[f].size()) - int(fs.trailing[f]);
	if (ranked <= 1) return 0;
	const int columns = std::clamp(int(fs.columns[f]), 1, ranked);
	const float half = float(columns - 1) * fs.spacing[f] * 0.5f + 0.5f;
	return uint8_t(std::clamp(int(std::ceil(half / grid.cell_size())), 1, NavGrid::kClearanceCap));
}

// One search runs at a time, and all of them together get kTickExpansionBudget
// cells a tick: a long search carries on next tick, and the formations queued
// behind it wait (holding still) until it is their turn.
void World::update_paths() {
	path_stats_ = {};
	FormationStore &fs = formations;
	const uint32_t cap = fs.capacity();
	if (cap == 0 || !grid.configured()) return;
	uint32_t spent = 0;

	auto finish = [&](uint32_t f) {
		fs.path[f] = grid.path_result();
		fs.path_index[f] = 0;
		// Nowhere reachable at all: stand still rather than walk into it, and
		// say the order is over so nothing waits on it forever.
		if (fs.path[f].empty() && (fs.flags[f] & FlagMoving) && !(fs.flags[f] & FlagAttacking)) {
			fs.flags[f] &= ~FlagMoving;
			arrived_.push_back(f);
		}
	};

	// A search already under way whose formation was re-ordered or ended in
	// the meantime is dropped; its new order is queued like any other.
	if (searching_ != kInvalidId && (!fs.alive(searching_) || fs.repath[searching_])) {
		grid.cancel_path();
		searching_ = kInvalidId;
	}
	if (searching_ != kInvalidId) {
		uint32_t expanded = 0;
		const auto status = grid.continue_path(kTickExpansionBudget, expanded);
		spent += expanded;
		path_stats_.expanded += expanded;
		if (status == NavGrid::SearchStatus::Running) {
			for (uint32_t f = 0; f < cap; ++f) path_stats_.deferred += (fs.alive(f) && fs.repath[f]) ? 1 : 0;
			return;
		}
		finish(searching_);
		searching_ = kInvalidId;
	}

	for (uint32_t k = 0; k < cap; ++k) {
		const uint32_t f = (path_cursor_ + k) % cap;
		if (!fs.alive(f) || !fs.repath[f]) continue;
		if (spent >= kTickExpansionBudget || searching_ != kInvalidId) {
			if (path_stats_.deferred == 0) path_cursor_ = f;
			++path_stats_.deferred;
			continue;
		}
		fs.repath[f] = 0;
		++path_stats_.searches;
		if (grid.begin_path({ fs.pos_x[f], fs.pos_y[f] }, { fs.dest_x[f], fs.dest_y[f] }, kMaxExpansions,
					block_clearance(f)) == NavGrid::SearchStatus::Done) {
			finish(f);
			continue;
		}
		uint32_t expanded = 0;
		const auto status = grid.continue_path(kTickExpansionBudget - spent, expanded);
		spent += expanded;
		path_stats_.expanded += expanded;
		if (status == NavGrid::SearchStatus::Done) {
			finish(f);
		} else {
			searching_ = f;
			// Its old route is stale; hold until the new one is ready.
			fs.path[f].clear();
		}
	}
	if (path_stats_.deferred == 0) path_cursor_ = 0;
}

// Ported from Very War's BattleWorld::update_formation_motion: the block heads
// for its next route point at its men's full pace, speeding up and slowing
// down at kAcceleration, and faces the way it is going, wheeling at kTurnRate.
// Nothing waits for stragglers — the men run to catch it up, which is what
// makes a block pull its men along behind it.
void World::update_formation_motion() {
	FormationStore &fs = formations;
	const float dt = kTickDt;
	for (uint32_t f = 0; f < fs.capacity(); ++f) {
		if (!fs.alive(f)) continue;
		const auto &members = fs.members[f];
		const bool lone = members.size() <= 1;

		int following = 0;
		for (uint32_t u : members) following += (units.motion[u] & MotionFollow) ? 1 : 0;
		if (following == 0) {
			// Nobody is holding their place (a lone unit about its own
			// business, a block pulled into a fight): a lone formation simply
			// stands where its unit is, ready for the next order; a block
			// waits for its men.
			if (lone) {
				fs.pos_x[f] = units.pos_x[members[0]];
				fs.pos_y[f] = units.pos_y[members[0]];
			}
			fs.vel_x[f] = 0.0f;
			fs.vel_y[f] = 0.0f;
			continue;
		}

		Vec2 pos(fs.pos_x[f], fs.pos_y[f]);
		Vec2 desired_dir(0.0f, 0.0f);
		bool moving = false;

		// Going for an enemy: follow it as it moves, stop once in contact
		// (or at shooting distance), and face it.
		bool attacking = (fs.flags[f] & FlagAttacking) != 0;
		Vec2 enemy_at;
		if (attacking) {
			if (!attack_position(f, enemy_at)) {
				fs.flags[f] &= ~(FlagAttacking | FlagMoving);
				fs.path[f].clear();
				arrived_.push_back(f);
				attacking = false;
			} else {
				const float gap = length(enemy_at - pos);
				const bool in_range = fs.engaged[f] || gap <= fs.engage_distance[f] + kStopDistance;
				if (in_range) {
					fs.flags[f] &= ~FlagMoving;
					fs.path[f].clear();
				} else if (!(fs.flags[f] & FlagMoving) ||
						((tick_index_ + f) % kPursuitTicks == 0 &&
								dist_sq(enemy_at, { fs.dest_x[f], fs.dest_y[f] }) > (fs.engage_distance[f] + kPursuitDrift) * (fs.engage_distance[f] + kPursuitDrift))) {
					// Out of reach again, or its enemy has moved on: after it.
					const Vec2 dir = (enemy_at - pos) * (1.0f / std::max(gap, 1e-3f));
					const Vec2 stop = enemy_at - dir * fs.engage_distance[f];
					fs.dest_x[f] = stop.x;
					fs.dest_y[f] = stop.y;
					fs.flags[f] |= FlagMoving;
					fs.repath[f] = 1;
				}
			}
		}

		// Waiting for a route: hold still until the path stage gets to it.
		if ((fs.flags[f] & FlagMoving) && !fs.repath[f] && f != searching_) {
			auto &path = fs.path[f];
			uint32_t &index = fs.path_index[f];
			while (index + 1 < path.size() && dist_sq(pos, path[index]) < kWaypointReach * kWaypointReach) ++index;
			// The last point is passed at Very War's 2 m on a move; an attack
			// goes all the way in, or the front rank stops out of reach.
			const float last_reach = (attacking || lone) ? kStopDistance : kWaypointReach;
			if (index + 1 == path.size() && dist_sq(pos, path[index]) < last_reach * last_reach) ++index;
			if (index < path.size()) {
				const Vec2 wp = path[index];
				const float d = length(wp - pos);
				if (d > kStopDistance) {
					desired_dir = (wp - pos) * (1.0f / d);
					moving = true;
				}
			}
			if (!moving && attacking) {
				path.clear();
				fs.flags[f] &= ~FlagMoving;
			} else if (!moving) {
				path.clear();
				if (!fs.queue[f].empty()) {
					// On to the next queued leg.
					const Waypoint next = fs.queue[f].front();
					fs.queue[f].erase(fs.queue[f].begin());
					auto rest = std::move(fs.queue[f]);
					order_move(f, next.dest, next.has_facing, next.facing);
					fs.queue[f] = std::move(rest);
				} else {
					fs.flags[f] &= ~FlagMoving;
					arrived_.push_back(f);
				}
			}
		}

		// Uphill is slower, which is what keeps high ground worth holding.
		float speed = fs.speed[f];
		speed *= clampf(1.0f - grid.sample_slope(pos) * 0.45f, 0.45f, 1.0f);

		Vec2 vel(fs.vel_x[f], fs.vel_y[f]);
		const Vec2 desired_vel = desired_dir * (moving ? speed : 0.0f);
		Vec2 delta = desired_vel - vel;
		const float max_dv = kAcceleration * dt;
		const float dl = length(delta);
		if (dl > max_dv) delta = delta * (max_dv / dl);
		vel += delta;
		pos += vel * dt;
		fs.vel_x[f] = vel.x; fs.vel_y[f] = vel.y;
		fs.pos_x[f] = pos.x; fs.pos_y[f] = pos.y;

		// Faces the way it is going; once there, the way it was told to face;
		// its enemy, once close.
		float want = fs.facing[f];
		const float enemy_sq = attacking ? length_sq(enemy_at - pos) : 0.0f;
		if (attacking && enemy_sq <= kFaceEnemyMinDistance * kFaceEnemyMinDistance) {
			// Up against it: hold the front it has.
		} else if (attacking && (!moving || enemy_sq < 400.0f)) {
			want = std::atan2(enemy_at.y - pos.y, enemy_at.x - pos.x);
		} else if (moving && length_sq(vel) > 0.04f) want = std::atan2(vel.y, vel.x);
		else if (!moving && (fs.flags[f] & FlagFinalFacing)) want = fs.final_facing[f];
		const float turn = (lone ? kLoneTurnRate : kTurnRate) * dt;
		fs.facing[f] += clampf(angle_delta(fs.facing[f], want), -turn, turn);
	}
}

void World::configure_hash() {
	const Vec2 o = grid.origin();
	const float w = float(grid.cols()) * grid.cell_size(), h = float(grid.rows()) * grid.cell_size();
	// About the separation radius: a query then touches 2x2 or 3x3 cells.
	hash.configure(o.x, o.y, o.x + w, o.y + h, 1.1f);
}

void World::set_unit_motion(uint32_t u, Vec2 desired, uint8_t motion, uint32_t attack_target, float max_speed) {
	if (!units.valid(u)) return;
	units.max_speed[u] = max_speed;
	units.desired_x[u] = desired.x;
	units.desired_y[u] = desired.y;
	units.motion[u] = motion;
	units.attack_target[u] = attack_target;
}

void World::set_unit_position(uint32_t u, Vec2 position) {
	if (!units.valid(u)) return;
	units.pos_x[u] = position.x;
	units.pos_y[u] = position.y;
}

void World::rebuild_spatial_hash() {
	if (!hash.configured()) return;
	const uint32_t n = units.capacity();
	for (uint32_t u = 0; u < n; ++u) units.in_hash[u] = units.alive[u] && !(units.motion[u] & MotionGhost);
	hash.rebuild(units.pos_x.data(), units.pos_y.data(), units.in_hash.data(), n);
}

namespace {
// Tried either side, in turn, when a step runs into something: a unit slides
// along an edge or round a trunk instead of stopping dead (as
// Unit.EDGE_SLIDE_ANGLES). Past 45 degrees counts as wedged.
constexpr float kSlideAngles[3] = { 3.14159265f / 6.0f, 3.14159265f / 3.0f, 3.14159265f * 0.47f };
constexpr float kWedgedAngle = 3.14159265f / 4.0f;
} // namespace

Vec2 World::clamp_step(Vec2 pos, Vec2 step, bool &wedged, bool follower) const {
	wedged = false;
	const Vec2 next = pos + step;
	// Only a unit already on open ground is held to it: one that is not
	// (spawned or shoved onto something) is free to walk back off.
	if (!grid.configured() || !grid.walkable(pos) || grid.walkable(next)) return next;
	// The grid's walls run along its axes, so the natural slide is along one:
	// keep whichever part of the step still goes somewhere open. This is what
	// walks a man down the face of a trunk and round its corner, where a
	// turned step pressed him into the face at every angle.
	const float len = length(step);
	const Vec2 along_x(pos.x + step.x, pos.y), along_y(pos.x, pos.y + step.y);
	const bool x_open = std::fabs(step.x) > 1e-5f && grid.walkable(along_x);
	const bool y_open = std::fabs(step.y) > 1e-5f && grid.walkable(along_y);
	if (x_open || y_open) {
		const bool use_x = x_open && (!y_open || std::fabs(step.x) >= std::fabs(step.y));
		// Progress the way he wanted to go, not just distance moved: shuffling
		// sideways along a face while pressing into it is still being stuck.
		const float kept = use_x ? step.x * step.x : step.y * step.y;
		wedged = kept < len * len * 0.3f;
		return use_x ? along_x : along_y;
	}
	for (float angle : kSlideAngles) {
		const float c = std::cos(angle), s = std::sin(angle);
		for (float side : { 1.0f, -1.0f }) {
			const float sn = s * side;
			// Turned, and shortened to how much of it still goes the intended way.
			const Vec2 turned((step.x * c - step.y * sn) * c, (step.x * sn + step.y * c) * c);
			if (grid.walkable(pos + turned)) {
				wedged = angle > kWedgedAngle;
				return pos + turned;
			}
		}
	}
	// Boxed into a corner every way it wants to go. A man following his place
	// steps back toward the middle of his cell, off the edge, so his next try
	// (or his detour) starts from open ground. Anyone else stays put and reads
	// as wedged every tick: Unit._track_blocked times that to let it walk out,
	// and a step back would keep resetting the clock.
	wedged = true;
	if (!follower) return pos;
	const Vec2 centre = grid.cell_center(grid.cell_x(pos.x), grid.cell_y(pos.y));
	const Vec2 back = centre - pos;
	const float back_len = length(back);
	const float step_len = length(step);
	if (back_len > 1e-4f) return pos + back * (std::min(step_len, back_len) / back_len);
	return pos;
}

// Every body at once: the velocity its own logic asked for, plus separation
// from whoever it is pressed against, kept on open ground. Reads positions
// only from this tick's start and writes to the back buffer, so the order
// units are visited in never changes the result.
void World::update_steering() {
	const float dt = kTickDt;
	const float sep = kSeparationDistance;
	const uint32_t n = units.capacity();
	plan_detours();
	for (uint32_t u = 0; u < n; ++u) {
		const bool was_wedged = units.wedged[u] != 0;
		units.moved[u] = 0;
		units.wedged[u] = 0;
		const float px = units.pos_x[u], py = units.pos_y[u];
		units.next_x[u] = px;
		units.next_y[u] = py;
		if (!units.alive[u] || (units.motion[u] & (MotionPinned | MotionGhost))) {
			units.vel_x[u] = 0.0f;
			units.vel_y[u] = 0.0f;
			continue;
		}

		if (units.motion[u] & MotionFollow) {
			steer_follower(u, dt, was_wedged);
			continue;
		}
		units.detour[u].clear();

		Vec2 push(0.0f, 0.0f);
		int seen = 0;
		const uint8_t team = units.team[u];
		const uint32_t my_target = units.attack_target[u];
		hash.query(px, py, sep, [&](uint32_t other) {
			if (other == u) return true;
			const float dx = px - units.pos_x[other], dy = py - units.pos_y[other];
			const float d_sq = dx * dx + dy * dy;
			if (d_sq >= sep * sep) return true;
			// An enemy attacking this unit does not shove it: every attacker
			// round a mobbed target would sum into one push and bulldoze it
			// across the field. A pair fighting each other push both ways.
			if (units.team[other] != team && units.attack_target[other] == u && my_target != other) return true;
			const float d = std::sqrt(d_sq);
			Vec2 away;
			if (d < 0.01f) {
				// Stacked exactly: part along a fixed angle per unit.
				const float angle = float(u % 6283) * 0.001f;
				away = Vec2(std::cos(angle), std::sin(angle));
			} else {
				away = Vec2(dx / d, dy / d);
			}
			push += away * ((1.0f - d / sep) * kSeparationSpeed);
			return ++seen < kMaxNeighbours;
		});
		const float push_len = length(push);
		if (push_len > kSeparationMaxSpeed) push = push * (kSeparationMaxSpeed / push_len);

		const Vec2 vel(units.desired_x[u] + push.x, units.desired_y[u] + push.y);
		units.vel_x[u] = vel.x;
		units.vel_y[u] = vel.y;
		if (std::fabs(vel.x) < 0.01f && std::fabs(vel.y) < 0.01f) continue;
		bool wedged = false;
		const Vec2 pos(px, py);
		const Vec2 next = (units.motion[u] & MotionUnclamped) ? pos + vel * dt : clamp_step(pos, vel * dt, wedged);
		units.next_x[u] = next.x;
		units.next_y[u] = next.y;
		units.wedged[u] = wedged ? 1 : 0;
		units.moved[u] = (next.x != px || next.y != py) ? 1 : 0;
	}
	units.pos_x.swap(units.next_x);
	units.pos_y.swap(units.next_y);
}

namespace {
Vec2 truncated(Vec2 v, float max_len) {
	const float l2 = length_sq(v);
	if (l2 <= max_len * max_len || l2 < 1e-12f) return v;
	return v * (max_len / std::sqrt(l2));
}
Vec2 normalized(Vec2 v) {
	const float l2 = length_sq(v);
	return l2 < 1e-12f ? Vec2(0.0f, 0.0f) : v * (1.0f / std::sqrt(l2));
}
} // namespace

// Ported from Very War's BattleWorld::update_steering. A man seeks his place
// (easing off inside kArriveRadius), is pushed off whoever is closer than
// kFollowSeparationRadius (inverse square, enemies harder), drifts a little
// toward and along with the friends round him, and changes velocity no faster
// than kAcceleration — so a block flows after its front rather than snapping
// into rank. On top of Very War: kept off closed ground, as every unit is.
// Men whose places went out of sight get their way round, as many as this
// tick's budget allows; the rest keep their request for the next tick.
void World::plan_detours() {
	uint32_t spent = 0;
	size_t done = 0;
	for (; done < detour_requests_.size() && spent < kDetourTickBudget; ++done) {
		const uint32_t u = detour_requests_[done];
		units.detour_pending[u] = 0;
		if (!units.valid(u) || !(units.motion[u] & MotionFollow)) continue;
		uint32_t expanded = 0;
		auto &route = units.detour[u];
		grid.find_detour({ units.pos_x[u], units.pos_y[u] }, { units.target_x[u], units.target_y[u] },
				kDetourMaxExpansions, route, expanded);
		units.detour_index[u] = 0;
		spent += expanded;
	}
	detour_requests_.erase(detour_requests_.begin(), detour_requests_.begin() + done);
}

void World::steer_follower(uint32_t u, float dt, bool was_wedged) {
	const Vec2 pos(units.pos_x[u], units.pos_y[u]);
	Vec2 vel(units.vel_x[u], units.vel_y[u]);
	const float speed = units.max_speed[u];

	// Where he is heading: his place, or — when something solid stands in the
	// way — the next point of his way round it, until his place is in sight.
	// In his block's fight, the enemy he is going for, just short of his reach.
	Vec2 place(units.target_x[u], units.target_y[u]);
	const uint32_t foe = units.seek_enemy[u];
	if (foe != kInvalidId && is_body(foe)) {
		const Vec2 at(units.pos_x[foe], units.pos_y[foe]);
		const Vec2 back = pos - at;
		const float d = length(back);
		const float stand = units.reach[u] * kEngageStandOff;
		place = d > 1e-3f ? at + back * (stand / d) : pos;
	}
	Vec2 goal = place;
	bool detouring = false;
	const float place_dist = length(place - pos);
	auto &route = units.detour[u];
	Vec2 way_out;
	if (grid.configured() && !grid.walkable(pos) && grid.nearest_open(pos, kPlaceSnapRadius, way_out)) {
		// Standing inside something (a building put down on top of him, a
		// shove into a trunk): walk straight out to the nearest open ground
		// first. Nothing holds a man there, so he can.
		route.clear();
		goal = way_out;
		detouring = true;
	} else if (!route.empty()) {
		// The route is a chain of cells. Find the one he is in (a little
		// either side of where he was), head for the next, and — so he walks
		// straight lines rather than a staircase — for the furthest of the next
		// few he can see outright. From inside a cell of the chain the way to
		// the next is always open: the search never cuts a corner.
		uint16_t &i = units.detour_index[u];
		const int cx = grid.cell_x(pos.x), cy = grid.cell_y(pos.y);
		int on = -1;
		const size_t from = i > 2 ? i - 2 : 0;
		for (size_t k = from; k < route.size() && k < size_t(i) + 8; ++k) {
			if (grid.cell_x(route[k].x) == cx && grid.cell_y(route[k].y) == cy) on = int(k);
		}
		if (on >= 0) i = uint16_t(on + 1);
		for (size_t k = size_t(i) + 1; k < route.size() && k <= size_t(i) + 6; ++k) {
			if (!grid.line_of_sight(pos, route[k])) break;
			i = uint16_t(k);
		}
		const bool in_sight = (tick_index_ + u) % 4 == 0 && grid.line_of_sight(pos, place);
		if (i >= route.size() || in_sight) {
			route.clear();
		} else if (on < 0 && !grid.line_of_sight(pos, route[i])) {
			// Shoved off the chain somewhere it cannot see: plan again from
			// where he is, and meanwhile stand in the middle of his own cell.
			if (!units.detour_pending[u]) {
				units.detour_pending[u] = 1;
				detour_requests_.push_back(u);
			}
			goal = grid.cell_center(cx, cy);
			detouring = true;
		} else {
			goal = route[i];
			detouring = true;
		}
	} else if (place_dist > kDetourMinDistance && !units.detour_pending[u] &&
			(was_wedged || (tick_index_ + u) % kSightCheckTicks == 0) && !grid.line_of_sight(pos, place)) {
		units.detour_pending[u] = 1;
		detour_requests_.push_back(u);
	}

	const Vec2 to_slot(goal.x - pos.x, goal.y - pos.y);
	const float slot_dist = length(to_slot);
	Vec2 seek(0.0f, 0.0f);
	if (slot_dist > 1e-4f) {
		// Only the place itself is eased into; a detour point is walked through.
		const float ramp = (!detouring && slot_dist < kArriveRadius) ? slot_dist / kArriveRadius : 1.0f;
		seek = to_slot * ((speed * ramp) / slot_dist);
	}

	Vec2 separation(0.0f, 0.0f), cohesion(0.0f, 0.0f), alignment(0.0f, 0.0f), enemy_push(0.0f, 0.0f);
	int friendly_seen = 0, seen = 0;
	const uint8_t team = units.team[u];
	const float r_sq = kFollowSeparationRadius * kFollowSeparationRadius;
	float friend_r = kFollowSeparationRadius;
	const uint32_t own = units.formation[u];
	if (formations.alive(own) && formations.members[own].size() > 1) {
		friend_r = clampf(formations.spacing[own] * kSeparationSpacingFraction, kMinSeparationRadius, kFollowSeparationRadius);
	}
	const float friend_r_sq = friend_r * friend_r;
	hash.query(pos.x, pos.y, kFollowSeparationRadius, [&](uint32_t other) {
		if (other == u) return true;
		const float dx = pos.x - units.pos_x[other], dy = pos.y - units.pos_y[other];
		const float d_sq = dx * dx + dy * dy;
		if (d_sq >= r_sq || d_sq < 1e-6f) return true;
		++seen;
		const float inv = 1.0f / d_sq;
		if (units.team[other] == team) {
			if (d_sq >= friend_r_sq) return true;
			separation += Vec2(dx * inv, dy * inv);
			cohesion += Vec2(units.pos_x[other], units.pos_y[other]);
			alignment += Vec2(units.vel_x[other], units.vel_y[other]);
			++friendly_seen;
		} else {
			enemy_push += Vec2(dx * inv * kEnemyPushScale, dy * inv * kEnemyPushScale);
		}
		return seen < kMaxNeighbours;
	});

	Vec2 steer = seek * kSeekWeight;
	// Finding his way round something he often has to file through a gap one
	// man wide, which full separation (up to four times his pace) would never
	// let a crowd do: they would shove each other off it. So only a light push
	// while detouring; back in the open, Very War's full press applies.
	steer += truncated(separation, speed * (detouring ? kDetourSeparationScale : 2.0f)) * kFollowSeparationWeight;
	steer += truncated(enemy_push, speed * 2.0f) * kEnemyPressureWeight;
	const float urgency = speed > 0.0f ? clampf(length(seek) / speed, 0.0f, 1.0f) : 0.0f;
	// Not while finding his way round something: the friends he would drift
	// toward and keep pace with are on the far side of it. And only while he
	// has somewhere to go — on his place, a constant tug toward his friends'
	// middle just pulls the edge men in and out of it.
	if (friendly_seen > 0 && !detouring) {
		const float inv_n = 1.0f / float(friendly_seen);
		steer += normalized(cohesion * inv_n - pos) * (speed * kCohesionWeight * urgency);
		steer += (alignment * inv_n - vel) * (kAlignmentWeight * urgency);
	}
	const float response = kSettleResponse + (kResponse - kSettleResponse) * urgency;
	vel += truncated((steer - vel) * response, kAcceleration) * dt;
	vel = truncated(vel, speed * kOverspeed);

	bool wedged = false;
	const Vec2 step = vel * dt;
	const Vec2 next = clamp_step(pos, step, wedged, true);
	// Slid along or stopped by something solid: carry on with the velocity it
	// actually had, not one pressing into the wall.
	if (next.x != pos.x + step.x || next.y != pos.y + step.y) vel = (next - pos) * (1.0f / dt);
	units.vel_x[u] = vel.x;
	units.vel_y[u] = vel.y;
	units.next_x[u] = next.x;
	units.next_y[u] = next.y;
	units.wedged[u] = wedged ? 1 : 0;
	units.moved[u] = (next.x != pos.x || next.y != pos.y) ? 1 : 0;
}

// Every member's place this tick, from the formation's position and facing.
// Cheaper to redo for everyone every tick than to track who needs it.
void World::update_slot_targets() {
	FormationStore &fs = formations;
	for (uint32_t f = 0; f < fs.capacity(); ++f) {
		if (!fs.alive(f)) continue;
		const float c = std::cos(fs.facing[f]), s = std::sin(fs.facing[f]);
		const float ox = fs.pos_x[f], oy = fs.pos_y[f];
		const auto &members = fs.members[f];
		const auto &slots = fs.local_slots[f];
		for (size_t i = 0; i < members.size() && i < slots.size(); ++i) {
			// Local +y is forward (cos, sin), local +x is right (sin, -cos).
			// The obvious-looking (x*c - y*s, x*s + y*c) is the wrong basis
			// here: it lays every block out as a column.
			const Vec2 l = slots[i];
			Vec2 place(ox + l.x * s + l.y * c, oy - l.x * c + l.y * s);
			// A place on a tree or a building corner moves to the nearest
			// open ground, rather than sending its man into the trunk.
			if (grid.configured() && !grid.walkable(place)) {
				Vec2 open_place;
				if (grid.nearest_open(place, kPlaceSnapRadius, open_place)) place = open_place;
			}
			units.target_x[members[i]] = place.x;
			units.target_y[members[i]] = place.y;
		}
	}
}

} // namespace army
