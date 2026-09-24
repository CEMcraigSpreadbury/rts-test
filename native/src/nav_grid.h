// The movement grid: one walkability cell per 0.5 m of the playable map, plus
// the terrain heightmap.
//
// A cell is open when the terrain there is walkable (read once from the map's
// authored navmesh, which already leaves out deep water, cliffs and the border)
// and nothing solid has been stamped over it. Trees and buildings are stamped
// by key and unstamped by the same key, so placing or losing one is a handful of
// cells, never a rebake. Stamps are counted, so two footprints overlapping a
// cell and one of them going leaves it blocked.

#pragma once

#include <cstdint>
#include <unordered_map>
#include <vector>

#include "sim_math.h"

namespace army {

class NavGrid {
public:
	// Covers [origin, origin + cols * cell) on both axes.
	void configure(Vec2 origin, int cols, int rows, float cell);

	// size x size samples, one every `spacing` metres from `origin`, row-major
	// with rows along +y (world Z). Heights are sampled between samples.
	void set_heightmap(const float *heights, int size, Vec2 origin, float spacing);

	// Marks every cell whose centre lies inside the polygon as walkable terrain.
	void mark_walkable(const Vec2 *points, int count);

	// Blocks every cell whose centre lies inside any of the outlines, under
	// `key`. A key stamped again replaces its old footprint.
	void set_blocker(int64_t key, const std::vector<std::vector<Vec2>> &outlines);
	void clear_blocker(int64_t key);
	void clear_all_blockers();

	bool configured() const { return cols_ > 0; }
	int cols() const { return cols_; }
	int rows() const { return rows_; }
	float cell_size() const { return cell_; }
	Vec2 origin() const { return origin_; }
	size_t blocker_count() const { return stamps_.size(); }

	bool in_bounds(int cx, int cy) const { return cx >= 0 && cy >= 0 && cx < cols_ && cy < rows_; }
	int cell_x(float x) const { return int(std::floor((x - origin_.x) * inv_cell_)); }
	int cell_y(float y) const { return int(std::floor((y - origin_.y) * inv_cell_)); }
	int index(int cx, int cy) const { return cy * cols_ + cx; }
	Vec2 cell_center(int cx, int cy) const {
		return { origin_.x + (float(cx) + 0.5f) * cell_, origin_.y + (float(cy) + 0.5f) * cell_ };
	}

	bool open(int cx, int cy) const {
		if (!in_bounds(cx, cy)) return false;
		const int i = index(cx, cy);
		return terrain_[i] && blockers_[i] == 0;
	}
	bool walkable(Vec2 p) const { return open(cell_x(p.x), cell_y(p.y)); }

	// Every cell the segment crosses is open (Amanatides-Woo traversal, so a
	// line can never slip through a diagonal gap between two blocked cells).
	bool line_of_sight(Vec2 a, Vec2 b) const;

	// Nearest open cell centre to `p` within `max_radius` metres; `p` itself
	// when it is already open.
	bool nearest_open(Vec2 p, float max_radius, Vec2 &out) const;

	float sample_height(Vec2 p) const;
	// Rise over run, from the heightmap either side of `p`.
	float sample_slope(Vec2 p) const;

	// 0 = not walkable terrain, 1 = open, 2 = walkable terrain under a stamp.
	std::vector<uint8_t> debug_cells() const;

	// A route from `start` to `goal` as string-pulled waypoints, ending at the
	// goal (or, if it cannot be reached, as close to it as the search got).
	// A start or goal inside something solid slides to the nearest open cell.
	// Open ground in a straight line costs no search at all. Returns false
	// when the goal itself was not reached; `out` still holds the best route.
	// `expanded` reports the cells the search visited.
	bool find_path(Vec2 start, Vec2 goal, uint32_t max_expansions, std::vector<Vec2> &out, uint32_t &expanded);

	// The same search, spread over as many calls as it needs, so no single
	// tick ever pays for a long one. One search runs at a time. begin_path
	// may finish at once (straight line, or no route at all); otherwise call
	// continue_path each tick until it reports Done, then read the result.
	enum class SearchStatus { Running, Done };
	// `min_clearance` (cells): a block that wide or wider keeps at least that
	// far from anything solid where it can — narrower cells cost more, so a
	// block goes round a clump rather than through a gap its ranks do not fit,
	// and only squeezes through one when there is no other way.
	SearchStatus begin_path(Vec2 start, Vec2 goal, uint32_t max_expansions, uint8_t min_clearance = 0);
	SearchStatus continue_path(uint32_t budget, uint32_t &expanded);
	void cancel_path();
	bool searching() const { return main_.search.active; }
	const std::vector<Vec2> &path_result() const { return main_.result; }
	bool path_reached_goal() const { return main_.reached; }

	// A man's way round whatever stands between him and his place: a whole
	// search of at most `max_expansions` cells, done at once, which never
	// touches a block's route search in progress. Unlike a block's route it is
	// every cell of the way (from the one he stands in), not a few corners.
	// False if nothing was found.
	bool find_detour(Vec2 start, Vec2 goal, uint32_t max_expansions, std::vector<Vec2> &out, uint32_t &expanded);

	// Which connected region of open ground a cell belongs to (0 for a cell
	// that is not open). Two points in different regions have no route
	// between them, so a search that could never succeed is never started.
	// Stamping something can split a region without this noticing; that only
	// costs one search that runs out of budget.
	uint32_t region_of(int cx, int cy);

	// How far a cell is from anything solid, in cells (0 when it is solid
	// itself), up to kClearanceCap. Kept up to date lazily, only round what
	// changed.
	static constexpr int kClearanceCap = 16;
	float clearance_cells(int cx, int cy);
	// Labels every region afresh. Done once the map's grid and its initial
	// stamps are in, so the first order of the match does not pay for it.
	void rebuild_regions() { relabel_regions(); }

private:
	template <typename Fn>
	void for_cells_inside(const Vec2 *points, int count, Fn &&fn) const;

	int cols_ = 0, rows_ = 0;
	float cell_ = 0.5f, inv_cell_ = 2.0f;
	Vec2 origin_;
	std::vector<uint8_t> terrain_;
	std::vector<uint16_t> blockers_;
	std::unordered_map<int64_t, std::vector<uint32_t>> stamps_;

	struct Node {
		uint32_t g = 0, f = 0;
		int32_t parent = -1;
		uint32_t stamp = 0; // which search last touched this node, so none are ever cleared
		uint8_t closed = 0;
	};
	void simplify(const std::vector<Vec2> &raw, std::vector<Vec2> &out) const;
	void relabel_regions();
	// Chamfer distances (2 a side, 3 a diagonal) in `clearance_`, recomputed
	// inside the window, reading its surroundings as they stand.
	void compute_clearance(int x0, int y0, int x1, int y1);
	void mark_clearance_dirty(const std::vector<uint32_t> &cells);
	void refresh_clearance();
	uint8_t clearance_units(int cx, int cy) const;
	// The segment's cells all have at least `min_units` clearance.
	bool line_clear(Vec2 a, Vec2 b, uint8_t min_units) const;
	std::vector<uint8_t> clearance_;
	bool clearance_full_ = true;
	bool clearance_window_ = false;
	int clr_x0_ = 0, clr_y0_ = 0, clr_x1_ = 0, clr_y1_ = 0;
	uint32_t new_region();
	uint32_t find_region(uint32_t label);
	void join_regions(uint32_t a, uint32_t b);
	void reopen_cells(const std::vector<uint32_t> &cells);
	// Nearest open cell centre to `p` in `region`, within `max_radius` metres.
	bool nearest_in_region(Vec2 p, uint32_t region, float max_radius, Vec2 &out);
	uint32_t heuristic(int cx, int cy) const;

	struct Search {
		bool active = false;
		Vec2 start, goal;
		int gx = 0, gy = 0;
		int32_t goal_idx = 0;
		int32_t best_cell = 0;
		uint32_t best_h = 0;
		uint32_t expanded = 0;
		uint32_t max_expansions = 0;
		uint8_t min_clearance = 0; // in chamfer units (2 per cell)
	};


	// Raw label per cell, and a union-find over labels so regions joined by a
	// felled tree merge without relabelling the map.
	std::vector<uint32_t> region_parent_;
	std::vector<uint32_t> regions_;
	std::vector<int32_t> flood_;
	bool regions_dirty_ = true;
	// Everything one search needs. The block-route search (spread over ticks)
	// and a man's detour (done at once) each have their own, so a detour never
	// disturbs a route still being searched. ctx_ is whichever is running.
	struct SearchContext {
		std::vector<Node> nodes;
		std::vector<std::pair<uint32_t, int32_t>> open;
		std::vector<Vec2> raw;
		uint32_t stamp = 0;
		Search search;
		std::vector<Vec2> result;
		bool reached = false;
	};
	SearchContext main_;
	SearchContext local_;
	SearchContext *ctx_ = &main_;

	std::vector<float> heights_;
	int height_size_ = 0;
	Vec2 height_origin_;
	float height_spacing_ = 1.0f, inv_height_spacing_ = 1.0f;
};

} // namespace army
