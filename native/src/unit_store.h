// Per-unit state, structure-of-arrays. A unit is an index into these arrays.
//
// Units are trained one at a time and die one at a time, so ids come from a
// free list rather than a bump allocator: a freed id is reused by the next
// unit to arrive. The arrays only grow at registration, never inside the tick.

#pragma once

#include <cstdint>
#include <vector>

#include "sim_math.h"

namespace army {

// What the unit's own logic says about it this tick (ArmySim.set_unit_motion).
enum UnitMotionFlag : uint8_t {
	// Stands its ground: not moved, not pushed (working, casting, stunned).
	// Still pushes others.
	MotionPinned = 1u << 0,
	// May step onto closed cells, to walk out of somewhere it got wedged.
	MotionUnclamped = 1u << 1,
	// Not a body at all any more (dead): neither moves nor pushes.
	MotionGhost = 1u << 2,
	// Holds its place in its formation: the sim steers it there itself, and
	// the velocity its own logic sent is ignored.
	MotionFollow = 1u << 3,
	// Fights from his place: the sim picks him a target in reach (see
	// World::update_fight_targets); he never leaves the place to chase.
	MotionFight = 1u << 4,
};

struct UnitStore {
	std::vector<float> pos_x, pos_y;
	std::vector<float> vel_x, vel_y;
	// Where this unit's place in its formation is, this tick.
	std::vector<float> target_x, target_y;
	// Where the unit's own logic wants to go this tick, in m/s.
	std::vector<float> desired_x, desired_y;
	std::vector<float> next_x, next_y; // steering back buffer
	std::vector<uint32_t> attack_target;
	std::vector<uint8_t> motion;
	// Top speed right now (buffs and slows included), for following its place.
	std::vector<float> max_speed;
	// Outputs of the last tick.
	std::vector<uint8_t> moved;
	std::vector<uint8_t> wedged;
	std::vector<uint8_t> in_hash;
	// A man whose place is out of sight behind something solid walks this way
	// round first (World::steer_follower); empty the rest of the time.
	std::vector<std::vector<Vec2>> detour;
	std::vector<uint16_t> detour_index;
	std::vector<uint8_t> detour_pending;

	// Combat, for men fighting from their places.
	std::vector<float> reach;       // how close an enemy must be to be hit
	std::vector<float> pick_radius; // how far he looks for one himself
	std::vector<uint8_t> ranged;
	std::vector<uint32_t> fight_target; // chosen last tick, or kInvalidId
	std::vector<uint16_t> attackers;    // how many chose this unit last tick
	// The enemy a melee man in an attacking block is going for, once his
	// block is in the fight (World::update_fight_targets); kInvalidId holds
	// his place instead.
	std::vector<uint32_t> seek_enemy;
	std::vector<float> radius;
	std::vector<float> speed;
	std::vector<float> vision; // how far he sees, for his side's sight
	// His blows, for a man fighting from his place (World::update_swings):
	// seconds between them, and time since the last.
	std::vector<float> cooldown;
	std::vector<float> swing_timer;
	std::vector<uint32_t> formation;
	std::vector<uint16_t> slot;
	std::vector<uint8_t> team;
	std::vector<uint8_t> alive;

	std::vector<uint32_t> free_ids;
	uint32_t live = 0;

	uint32_t capacity() const { return uint32_t(alive.size()); }
	bool valid(uint32_t id) const { return id < capacity() && alive[id]; }

	uint32_t add(uint8_t unit_team, Vec2 position, float unit_radius, float unit_speed) {
		if (free_ids.empty()) grow(capacity() == 0 ? 1024 : capacity() * 2);
		const uint32_t id = free_ids.back();
		free_ids.pop_back();
		pos_x[id] = position.x; pos_y[id] = position.y;
		vel_x[id] = 0.0f; vel_y[id] = 0.0f;
		target_x[id] = position.x; target_y[id] = position.y;
		desired_x[id] = 0.0f; desired_y[id] = 0.0f;
		next_x[id] = position.x; next_y[id] = position.y;
		attack_target[id] = kInvalidId;
		motion[id] = 0;
		max_speed[id] = unit_speed;
		moved[id] = 0;
		wedged[id] = 0;
		detour[id].clear();
		detour_index[id] = 0;
		detour_pending[id] = 0;
		reach[id] = 1.2f;
		pick_radius[id] = 6.0f;
		ranged[id] = 0;
		fight_target[id] = kInvalidId;
		attackers[id] = 0;
		seek_enemy[id] = kInvalidId;
		radius[id] = unit_radius;
		speed[id] = unit_speed;
		vision[id] = 0.0f;
		cooldown[id] = 1.0f;
		swing_timer[id] = 0.0f;
		formation[id] = kInvalidId;
		slot[id] = 0;
		team[id] = unit_team;
		alive[id] = 1;
		++live;
		return id;
	}

	void remove(uint32_t id) {
		if (!valid(id)) return;
		alive[id] = 0;
		formation[id] = kInvalidId;
		--live;
		free_ids.push_back(id);
	}

private:
	void grow(uint32_t new_capacity) {
		const uint32_t old = capacity();
		for (auto *v : { &pos_x, &pos_y, &vel_x, &vel_y, &target_x, &target_y, &desired_x, &desired_y, &next_x, &next_y, &radius, &speed, &max_speed, &vision, &cooldown, &swing_timer }) {
			v->resize(new_capacity, 0.0f);
		}
		attack_target.resize(new_capacity, kInvalidId);
		for (auto *v : { &motion, &moved, &wedged, &in_hash, &detour_pending }) v->resize(new_capacity, 0);
		detour.resize(new_capacity);
		detour_index.resize(new_capacity, 0);
		reach.resize(new_capacity, 1.2f);
		pick_radius.resize(new_capacity, 6.0f);
		ranged.resize(new_capacity, 0);
		fight_target.resize(new_capacity, kInvalidId);
		attackers.resize(new_capacity, 0);
		seek_enemy.resize(new_capacity, kInvalidId);
		formation.resize(new_capacity, kInvalidId);
		slot.resize(new_capacity, 0);
		team.resize(new_capacity, 0);
		alive.resize(new_capacity, 0);
		// Pushed high to low, so ids are handed out low first and the arrays
		// stay dense from the front.
		free_ids.reserve(new_capacity);
		for (uint32_t i = new_capacity; i-- > old;) free_ids.push_back(i);
	}
};

} // namespace army
