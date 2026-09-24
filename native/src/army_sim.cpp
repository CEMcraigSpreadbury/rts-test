#include "army_sim.h"

#include <cmath>
#include <cstring>

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace {
army::Vec2 to_sim(const Vector2 &v) { return { v.x, v.y }; }
} // namespace

void ArmySim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("step"), &ArmySim::step);
	ClassDB::bind_method(D_METHOD("get_tick_count"), &ArmySim::get_tick_count);
	ClassDB::bind_method(D_METHOD("get_version"), &ArmySim::get_version);

	ClassDB::bind_method(D_METHOD("configure_grid", "origin", "size", "cell"), &ArmySim::configure_grid);
	ClassDB::bind_method(D_METHOD("set_heightmap", "heights", "size", "origin", "spacing"), &ArmySim::set_heightmap);
	ClassDB::bind_method(D_METHOD("mark_walkable_polygons", "points", "starts"), &ArmySim::mark_walkable_polygons);
	ClassDB::bind_method(D_METHOD("set_blocker", "key", "outlines"), &ArmySim::set_blocker);
	ClassDB::bind_method(D_METHOD("clear_blocker", "key"), &ArmySim::clear_blocker);
	ClassDB::bind_method(D_METHOD("finish_grid"), &ArmySim::finish_grid);
	ClassDB::bind_method(D_METHOD("is_walkable", "point"), &ArmySim::is_walkable);
	ClassDB::bind_method(D_METHOD("height_at", "point"), &ArmySim::height_at);
	ClassDB::bind_method(D_METHOD("has_line_of_sight", "from", "to"), &ArmySim::has_line_of_sight);
	ClassDB::bind_method(D_METHOD("get_grid_info"), &ArmySim::get_grid_info);
	ClassDB::bind_method(D_METHOD("get_grid_cells"), &ArmySim::get_grid_cells);
	ClassDB::bind_method(D_METHOD("get_grid_debug_rgba"), &ArmySim::get_grid_debug_rgba);

	ClassDB::bind_method(D_METHOD("add_unit", "team", "position", "radius", "speed"), &ArmySim::add_unit);
	ClassDB::bind_method(D_METHOD("remove_unit", "id"), &ArmySim::remove_unit);
	ClassDB::bind_method(D_METHOD("get_unit_count"), &ArmySim::get_unit_count);
	ClassDB::bind_method(D_METHOD("get_unit_formation", "id"), &ArmySim::get_unit_formation);
	ClassDB::bind_method(D_METHOD("set_unit_motion", "id", "desired", "flags", "attack_target", "max_speed"), &ArmySim::set_unit_motion);
	ClassDB::bind_method(D_METHOD("set_unit_position", "id", "position"), &ArmySim::set_unit_position);
	ClassDB::bind_method(D_METHOD("get_moved_units"), &ArmySim::get_moved_units);
	ClassDB::bind_method(D_METHOD("get_wedged_units"), &ArmySim::get_wedged_units);
	ClassDB::bind_method(D_METHOD("get_unit_debug", "id"), &ArmySim::get_unit_debug);
	ClassDB::bind_method(D_METHOD("get_units_in_circle", "centre", "radius"), &ArmySim::get_units_in_circle);
	ClassDB::bind_method(D_METHOD("set_unit_vision", "id", "range"), &ArmySim::set_unit_vision);
	ClassDB::bind_method(D_METHOD("set_unit_team", "id", "team"), &ArmySim::set_unit_team);
	ClassDB::bind_method(D_METHOD("set_unit_cooldown", "id", "seconds"), &ArmySim::set_unit_cooldown);
	ClassDB::bind_method(D_METHOD("get_swings"), &ArmySim::get_swings);
	ClassDB::bind_method(D_METHOD("team_sees", "team", "point"), &ArmySim::team_sees);
	ClassDB::bind_method(D_METHOD("count_melee_attackers", "target", "radius", "exclude", "limit"), &ArmySim::count_melee_attackers);
	ClassDB::bind_method(D_METHOD("get_units_near", "centre", "radius", "not_team"), &ArmySim::get_units_near);
	BIND_ENUM_CONSTANT(MOTION_PINNED);
	BIND_ENUM_CONSTANT(MOTION_UNCLAMPED);
	BIND_ENUM_CONSTANT(MOTION_GHOST);
	BIND_ENUM_CONSTANT(MOTION_FOLLOW);
	BIND_ENUM_CONSTANT(MOTION_FIGHT);
	ClassDB::bind_method(D_METHOD("set_unit_combat", "id", "reach", "pick_radius", "ranged"), &ArmySim::set_unit_combat);
	ClassDB::bind_method(D_METHOD("get_fight_targets"), &ArmySim::get_fight_targets);
	ClassDB::bind_method(D_METHOD("order_attack", "formation", "target", "point", "engage_distance"), &ArmySim::order_attack);
	ClassDB::bind_method(D_METHOD("get_attacking_formations"), &ArmySim::get_attacking_formations);
	ClassDB::bind_method(D_METHOD("unit_died", "id"), &ArmySim::unit_died);

	ClassDB::bind_method(D_METHOD("form", "unit_ids", "front_centre", "facing", "trailing"), &ArmySim::form, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("release", "unit_id", "position"), &ArmySim::release);
	ClassDB::bind_method(D_METHOD("set_layout", "formation", "columns", "spacing", "loose"), &ArmySim::set_layout);
	ClassDB::bind_method(D_METHOD("set_speed", "formation", "speed"), &ArmySim::set_speed);
	ClassDB::bind_method(D_METHOD("get_formation_count"), &ArmySim::get_formation_count);
	ClassDB::bind_method(D_METHOD("get_formation_members", "formation"), &ArmySim::get_formation_members);
	ClassDB::bind_method(D_METHOD("get_formation_info", "formation"), &ArmySim::get_formation_info);
	ClassDB::bind_method(D_METHOD("queue_move", "formation", "destination", "face", "facing"), &ArmySim::queue_move);
	ClassDB::bind_method(D_METHOD("get_arrived_formations"), &ArmySim::get_arrived_formations);
	ClassDB::bind_method(D_METHOD("get_enemy_alerts"), &ArmySim::get_enemy_alerts);
	ClassDB::bind_method(D_METHOD("order_move", "formation", "destination", "face", "facing"), &ArmySim::order_move);
	ClassDB::bind_method(D_METHOD("order_hold", "formation"), &ArmySim::order_hold);
	ClassDB::bind_method(D_METHOD("get_formation_states", "min_members"), &ArmySim::get_formation_states);
	ClassDB::bind_method(D_METHOD("get_formation_path", "formation"), &ArmySim::get_formation_path);
	ClassDB::bind_method(D_METHOD("get_slot_targets", "min_members"), &ArmySim::get_slot_targets);
	ClassDB::bind_method(D_METHOD("get_path_stats"), &ArmySim::get_path_stats);

	ClassDB::bind_method(D_METHOD("get_profile"), &ArmySim::get_profile);
	ClassDB::bind_method(D_METHOD("get_profile_peaks"), &ArmySim::get_profile_peaks);
	ClassDB::bind_method(D_METHOD("reset_profile_peaks"), &ArmySim::reset_profile_peaks);
}

void ArmySim::step() {
	world_.tick();
	++tick_count_;
}

int ArmySim::get_tick_count() const {
	return tick_count_;
}

String ArmySim::get_version() const {
	return "ArmySim 0.6";
}

// ------------------------------------------------------------------ grid

void ArmySim::configure_grid(const Vector2 &origin, const Vector2 &size, float cell) {
	world_.grid.configure(to_sim(origin), int(std::ceil(size.x / cell)), int(std::ceil(size.y / cell)), cell);
	world_.configure_hash();
}

void ArmySim::set_heightmap(const PackedFloat32Array &heights, int size, const Vector2 &origin, float spacing) {
	if (size <= 0 || heights.size() < int64_t(size) * size) return;
	world_.grid.set_heightmap(heights.ptr(), size, to_sim(origin), spacing);
}

void ArmySim::mark_walkable_polygons(const PackedVector2Array &points, const PackedInt32Array &starts) {
	std::vector<army::Vec2> polygon;
	for (int64_t p = 0; p + 1 < starts.size(); ++p) {
		polygon.clear();
		for (int32_t i = starts[p]; i < starts[p + 1] && i < points.size(); ++i) polygon.push_back(to_sim(points[i]));
		world_.grid.mark_walkable(polygon.data(), int(polygon.size()));
	}
}

void ArmySim::set_blocker(int64_t key, const Array &outlines) {
	std::vector<std::vector<army::Vec2>> converted;
	for (int64_t o = 0; o < outlines.size(); ++o) {
		const PackedVector2Array outline = outlines[o];
		std::vector<army::Vec2> points;
		points.reserve(outline.size());
		for (int64_t i = 0; i < outline.size(); ++i) points.push_back(to_sim(outline[i]));
		converted.push_back(std::move(points));
	}
	world_.grid.set_blocker(key, converted);
}

void ArmySim::clear_blocker(int64_t key) {
	world_.grid.clear_blocker(key);
}

void ArmySim::finish_grid() {
	world_.grid.rebuild_regions();
}

bool ArmySim::is_walkable(const Vector2 &point) const {
	return world_.grid.walkable(to_sim(point));
}

float ArmySim::height_at(const Vector2 &point) const {
	return world_.grid.sample_height(to_sim(point));
}

bool ArmySim::has_line_of_sight(const Vector2 &from, const Vector2 &to) const {
	return world_.grid.line_of_sight(to_sim(from), to_sim(to));
}

Dictionary ArmySim::get_grid_info() const {
	Dictionary out;
	out["origin"] = Vector2(world_.grid.origin().x, world_.grid.origin().y);
	out["cols"] = world_.grid.cols();
	out["rows"] = world_.grid.rows();
	out["cell"] = world_.grid.cell_size();
	out["blockers"] = int64_t(world_.grid.blocker_count());
	return out;
}

PackedByteArray ArmySim::get_grid_cells() const {
	const std::vector<uint8_t> cells = world_.grid.debug_cells();
	PackedByteArray out;
	out.resize(int64_t(cells.size()));
	if (!cells.empty()) std::memcpy(out.ptrw(), cells.data(), cells.size());
	return out;
}

PackedByteArray ArmySim::get_grid_debug_rgba() const {
	static constexpr uint8_t kColours[3][4] = {
		{ 40, 90, 255, 110 }, // not walkable terrain
		{ 0, 0, 0, 0 }, // open
		{ 255, 40, 40, 150 }, // stamped
	};
	const std::vector<uint8_t> cells = world_.grid.debug_cells();
	PackedByteArray out;
	out.resize(int64_t(cells.size()) * 4);
	uint8_t *dst = out.ptrw();
	for (size_t i = 0; i < cells.size(); ++i) std::memcpy(dst + i * 4, kColours[cells[i]], 4);
	return out;
}

// ----------------------------------------------------------------- units

int ArmySim::add_unit(int team, const Vector2 &position, float radius, float speed) {
	return int(world_.add_unit(uint8_t(team), to_sim(position), radius, speed));
}

void ArmySim::remove_unit(int id) {
	if (id >= 0) world_.remove_unit(uint32_t(id));
}

int ArmySim::get_unit_count() const {
	return int(world_.units.live);
}

int ArmySim::get_unit_formation(int id) const {
	if (id < 0 || !world_.units.valid(uint32_t(id))) return -1;
	const uint32_t f = world_.units.formation[id];
	return f == army::kInvalidId ? -1 : int(f);
}

void ArmySim::set_unit_motion(int id, const Vector2 &desired, int flags, int attack_target, float max_speed) {
	if (id < 0) return;
	world_.set_unit_motion(uint32_t(id), to_sim(desired), uint8_t(flags),
			attack_target >= 0 ? uint32_t(attack_target) : army::kInvalidId, max_speed);
}

void ArmySim::set_unit_position(int id, const Vector2 &position) {
	if (id >= 0) world_.set_unit_position(uint32_t(id), to_sim(position));
}

PackedFloat32Array ArmySim::get_moved_units() const {
	const army::UnitStore &us = world_.units;
	PackedFloat32Array out;
	for (uint32_t u = 0; u < us.capacity(); ++u) {
		if (!us.alive[u] || !us.moved[u]) continue;
		const army::Vec2 p(us.pos_x[u], us.pos_y[u]);
		out.push_back(float(u));
		out.push_back(p.x);
		out.push_back(world_.grid.sample_height(p));
		out.push_back(p.y);
		out.push_back(us.vel_x[u]);
		out.push_back(us.vel_y[u]);
	}
	return out;
}

PackedInt32Array ArmySim::get_wedged_units() const {
	const army::UnitStore &us = world_.units;
	PackedInt32Array out;
	for (uint32_t u = 0; u < us.capacity(); ++u) {
		if (us.alive[u] && us.wedged[u]) out.push_back(int32_t(u));
	}
	return out;
}

void ArmySim::set_unit_vision(int id, float range) {
	if (id < 0 || !world_.units.valid(uint32_t(id))) return;
	world_.units.vision[id] = range;
	max_vision_ = std::max(max_vision_, range);
}

void ArmySim::set_unit_team(int id, int team) {
	if (id >= 0 && world_.units.valid(uint32_t(id))) world_.units.team[id] = uint8_t(team);
}

void ArmySim::set_unit_cooldown(int id, float seconds) {
	if (id >= 0 && world_.units.valid(uint32_t(id))) world_.units.cooldown[id] = std::max(seconds, 0.05f);
}

PackedInt32Array ArmySim::get_swings() const {
	const std::vector<uint32_t> &swings = world_.swings();
	PackedInt32Array out;
	out.resize(int64_t(swings.size()));
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < swings.size(); ++i) w[i] = int32_t(swings[i]);
	return out;
}

bool ArmySim::team_sees(int team, const Vector2 &point) const {
	const army::UnitStore &us = world_.units;
	if (!world_.hash.configured()) return false;
	bool seen = false;
	// The spatial hash holds the living (dead men turn ghost, see unit_died).
	world_.hash.query(point.x, point.y, max_vision_, [&](uint32_t u) {
		if (us.team[u] != team) return true;
		const float dx = us.pos_x[u] - point.x, dy = us.pos_y[u] - point.y, r = us.vision[u];
		if (dx * dx + dy * dy <= r * r) {
			seen = true;
			return false;
		}
		return true;
	});
	return seen;
}

PackedInt32Array ArmySim::get_units_near(const Vector2 &centre, float radius, int not_team) const {
	PackedInt32Array out;
	const army::UnitStore &us = world_.units;
	if (!world_.hash.configured()) return out;
	const float r2 = radius * radius;
	thread_local std::vector<std::pair<float, uint32_t>> found;
	found.clear();
	world_.hash.query(centre.x, centre.y, radius, [&](uint32_t u) {
		if (not_team >= 0 && us.team[u] == not_team) return true;
		const float dx = us.pos_x[u] - centre.x, dy = us.pos_y[u] - centre.y, d2 = dx * dx + dy * dy;
		if (d2 <= r2) found.emplace_back(d2, u);
		return true;
	});
	std::sort(found.begin(), found.end());
	out.resize(int64_t(found.size()));
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < found.size(); ++i) w[i] = int32_t(found[i].second);
	return out;
}

int ArmySim::count_melee_attackers(int target, float radius, int exclude, int limit) const {
	const army::UnitStore &us = world_.units;
	if (target < 0 || !us.valid(uint32_t(target)) || !world_.hash.configured()) return 0;
	const float tx = us.pos_x[target], ty = us.pos_y[target], r2 = radius * radius;
	int count = 0;
	world_.hash.query(tx, ty, radius, [&](uint32_t u) {
		if (int(u) == exclude || us.attack_target[u] != uint32_t(target) || us.ranged[u]) return true;
		const float dx = us.pos_x[u] - tx, dy = us.pos_y[u] - ty;
		if (dx * dx + dy * dy <= r2) ++count;
		return count < limit;
	});
	return count;
}

PackedInt32Array ArmySim::get_units_in_circle(const Vector2 &centre, float radius) const {
	PackedInt32Array out;
	const army::UnitStore &us = world_.units;
	for (uint32_t u = 0; u < us.capacity(); ++u) {
		if (!us.alive[u]) continue;
		const float dx = us.pos_x[u] - centre.x, dy = us.pos_y[u] - centre.y, r = radius + us.radius[u];
		if (dx * dx + dy * dy <= r * r) out.push_back(int32_t(u));
	}
	return out;
}

Dictionary ArmySim::get_unit_debug(int id) {
	Dictionary out;
	const army::UnitStore &us = world_.units;
	if (id < 0 || !us.valid(uint32_t(id))) return out;
	const army::Vec2 p(us.pos_x[id], us.pos_y[id]), t(us.target_x[id], us.target_y[id]);
	out["position"] = Vector2(p.x, p.y);
	out["place"] = Vector2(t.x, t.y);
	out["detour"] = int64_t(us.detour[id].size() - std::min<size_t>(us.detour[id].size(), us.detour_index[id]));
	out["pending"] = us.detour_pending[id] != 0;
	out["wedged"] = us.wedged[id] != 0;
	out["on_open"] = world_.grid.walkable(p);
	out["place_open"] = world_.grid.walkable(t);
	out["place_in_sight"] = world_.grid.line_of_sight(p, t);
	PackedVector2Array route;
	for (size_t i = us.detour_index[id]; i < us.detour[id].size(); ++i) route.push_back(Vector2(us.detour[id][i].x, us.detour[id][i].y));
	out["route"] = route;
	out["velocity"] = Vector2(us.vel_x[id], us.vel_y[id]);
	out["motion"] = int64_t(us.motion[id]);
	out["max_speed"] = us.max_speed[id];
	return out;
}

void ArmySim::set_unit_combat(int id, float reach, float pick_radius, bool ranged) {
	if (id >= 0) world_.set_unit_combat(uint32_t(id), reach, pick_radius, ranged);
}

PackedInt32Array ArmySim::get_fight_targets() const {
	const army::UnitStore &us = world_.units;
	PackedInt32Array out;
	for (uint32_t u = 0; u < us.capacity(); ++u) {
		if (!us.alive[u] || !(us.motion[u] & army::MotionFight)) continue;
		out.push_back(int32_t(u));
		out.push_back(us.fight_target[u] == army::kInvalidId ? -1 : int32_t(us.fight_target[u]));
	}
	return out;
}

void ArmySim::order_attack(int formation, int target, const Vector2 &point, float engage_distance) {
	if (formation < 0) return;
	world_.order_attack(uint32_t(formation), target >= 0 ? uint32_t(target) : army::kInvalidId, to_sim(point), engage_distance);
}

PackedFloat32Array ArmySim::get_attacking_formations() const {
	const army::FormationStore &fs = world_.formations;
	PackedFloat32Array out;
	for (uint32_t f = 0; f < fs.capacity(); ++f) {
		if (!fs.alive(f) || !(fs.flags[f] & army::FlagAttacking)) continue;
		out.push_back(float(f));
		out.push_back(fs.facing[f]);
		out.push_back(fs.engaged[f] ? 1.0f : 0.0f);
	}
	return out;
}

void ArmySim::unit_died(int id) {
	if (id >= 0) world_.unit_died(uint32_t(id));
}

// ------------------------------------------------------------ formations

int ArmySim::form(const PackedInt32Array &unit_ids, const Vector2 &front_centre, float facing, int trailing) {
	std::vector<uint32_t> ids;
	ids.reserve(unit_ids.size());
	for (int64_t i = 0; i < unit_ids.size(); ++i) {
		if (unit_ids[i] >= 0) ids.push_back(uint32_t(unit_ids[i]));
	}
	const uint32_t f = world_.form(ids, to_sim(front_centre), facing, uint16_t(std::max(0, trailing)));
	return f == army::kInvalidId ? -1 : int(f);
}

int ArmySim::release(int unit_id, const Vector2 &position) {
	if (unit_id < 0) return -1;
	const uint32_t f = world_.release(uint32_t(unit_id), to_sim(position));
	return f == army::kInvalidId ? -1 : int(f);
}

void ArmySim::set_layout(int formation, int columns, float spacing, bool loose) {
	if (formation >= 0) world_.set_layout(uint32_t(formation), uint16_t(std::max(1, columns)), spacing, loose);
}

void ArmySim::set_speed(int formation, float speed) {
	if (formation >= 0) world_.set_speed(uint32_t(formation), speed);
}

int ArmySim::get_formation_count() const {
	return int(world_.formations.live);
}

PackedInt32Array ArmySim::get_formation_members(int formation) const {
	PackedInt32Array out;
	if (formation < 0 || !world_.formations.alive(uint32_t(formation))) return out;
	for (uint32_t u : world_.formations.members[formation]) out.push_back(int32_t(u));
	return out;
}

Dictionary ArmySim::get_formation_info(int formation) const {
	Dictionary out;
	const army::FormationStore &fs = world_.formations;
	if (formation < 0 || !fs.alive(uint32_t(formation))) return out;
	out["position"] = Vector2(fs.pos_x[formation], fs.pos_y[formation]);
	out["facing"] = fs.facing[formation];
	out["moving"] = (fs.flags[formation] & army::FlagMoving) != 0;
	out["queued"] = int64_t(fs.queue[formation].size());
	return out;
}

void ArmySim::queue_move(int formation, const Vector2 &destination, bool face, float facing) {
	if (formation >= 0) world_.queue_move(uint32_t(formation), to_sim(destination), face, facing);
}

PackedInt32Array ArmySim::get_enemy_alerts() const {
	PackedInt32Array out;
	for (uint32_t f : world_.alerts()) out.push_back(int32_t(f));
	return out;
}

PackedInt32Array ArmySim::get_arrived_formations() const {
	PackedInt32Array out;
	for (uint32_t f : world_.arrived()) out.push_back(int32_t(f));
	return out;
}

void ArmySim::order_move(int formation, const Vector2 &destination, bool face, float facing) {
	if (formation >= 0) world_.order_move(uint32_t(formation), to_sim(destination), face, facing);
}

void ArmySim::order_hold(int formation) {
	if (formation >= 0) world_.order_hold(uint32_t(formation));
}

// -------------------------------------------------------------- readback

PackedFloat32Array ArmySim::get_formation_states(int min_members) const {
	const army::FormationStore &fs = world_.formations;
	PackedFloat32Array out;
	for (uint32_t f = 0; f < fs.capacity(); ++f) {
		if (!fs.alive(f) || int(fs.members[f].size()) < min_members) continue;
		const army::Vec2 p(fs.pos_x[f], fs.pos_y[f]);
		const float state[8] = { float(f), p.x, p.y, world_.grid.sample_height(p), fs.facing[f],
			float(fs.members[f].size()), (fs.flags[f] & army::FlagMoving) ? 1.0f : 0.0f, fs.speed[f] };
		for (float v : state) out.push_back(v);
	}
	return out;
}

PackedVector3Array ArmySim::get_formation_path(int formation) const {
	const army::FormationStore &fs = world_.formations;
	PackedVector3Array out;
	if (formation < 0 || !fs.alive(uint32_t(formation))) return out;
	const uint32_t f = uint32_t(formation);
	const army::Vec2 p(fs.pos_x[f], fs.pos_y[f]);
	out.push_back(Vector3(p.x, world_.grid.sample_height(p), p.y));
	if (!(fs.flags[f] & army::FlagMoving)) return out;
	for (size_t i = fs.path_index[f]; i < fs.path[f].size(); ++i) {
		const army::Vec2 w = fs.path[f][i];
		out.push_back(Vector3(w.x, world_.grid.sample_height(w), w.y));
	}
	return out;
}

PackedVector3Array ArmySim::get_slot_targets(int min_members) const {
	const army::FormationStore &fs = world_.formations;
	PackedVector3Array out;
	for (uint32_t f = 0; f < fs.capacity(); ++f) {
		if (!fs.alive(f) || int(fs.members[f].size()) < min_members) continue;
		for (uint32_t u : fs.members[f]) {
			const army::Vec2 t(world_.units.target_x[u], world_.units.target_y[u]);
			out.push_back(Vector3(t.x, world_.grid.sample_height(t), t.y));
		}
	}
	return out;
}

Dictionary ArmySim::get_path_stats() const {
	const army::PathStats stats = world_.path_stats();
	Dictionary out;
	out["searches"] = int64_t(stats.searches);
	out["expanded"] = int64_t(stats.expanded);
	out["deferred"] = int64_t(stats.deferred);
	return out;
}

// --------------------------------------------------------------- profile

Dictionary ArmySim::get_profile() const {
	Dictionary out;
	for (size_t i = 0; i < army::kZoneCount; ++i) {
		const auto zone = static_cast<army::Zone>(i);
		out[army::zone_name(zone)] = world_.profiler.last_ms(zone);
	}
	return out;
}

Dictionary ArmySim::get_profile_peaks() const {
	Dictionary out;
	for (size_t i = 0; i < army::kZoneCount; ++i) {
		const auto zone = static_cast<army::Zone>(i);
		out[army::zone_name(zone)] = world_.profiler.peak_ms(zone);
	}
	return out;
}

void ArmySim::reset_profile_peaks() {
	world_.profiler.reset_peaks();
}
