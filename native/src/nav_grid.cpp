#include "nav_grid.h"

#include <algorithm>

namespace army {

void NavGrid::configure(Vec2 origin, int cols, int rows, float cell) {
	origin_ = origin;
	cols_ = std::max(1, cols);
	rows_ = std::max(1, rows);
	cell_ = cell;
	inv_cell_ = 1.0f / cell;
	terrain_.assign(size_t(cols_) * rows_, 0);
	blockers_.assign(size_t(cols_) * rows_, 0);
	stamps_.clear();
	regions_dirty_ = true;
	clearance_full_ = true;
}

void NavGrid::set_heightmap(const float *heights, int size, Vec2 origin, float spacing) {
	heights_.assign(heights, heights + size_t(size) * size);
	height_size_ = size;
	height_origin_ = origin;
	height_spacing_ = spacing;
	inv_height_spacing_ = 1.0f / spacing;
}

// Calls fn(cell index) for every cell whose centre is inside the polygon
// (even-odd rule, so any simple outline works, convex or not).
template <typename Fn>
void NavGrid::for_cells_inside(const Vec2 *points, int count, Fn &&fn) const {
	if (count < 3 || cols_ == 0) return;
	Vec2 lo = points[0], hi = points[0];
	for (int i = 1; i < count; ++i) {
		lo.x = std::min(lo.x, points[i].x); lo.y = std::min(lo.y, points[i].y);
		hi.x = std::max(hi.x, points[i].x); hi.y = std::max(hi.y, points[i].y);
	}
	const int x0 = std::max(0, cell_x(lo.x)), x1 = std::min(cols_ - 1, cell_x(hi.x));
	const int y0 = std::max(0, cell_y(lo.y)), y1 = std::min(rows_ - 1, cell_y(hi.y));
	for (int cy = y0; cy <= y1; ++cy) {
		for (int cx = x0; cx <= x1; ++cx) {
			const Vec2 c = cell_center(cx, cy);
			bool inside = false;
			for (int i = 0, j = count - 1; i < count; j = i++) {
				const Vec2 a = points[i], b = points[j];
				if ((a.y > c.y) != (b.y > c.y) &&
						c.x < (b.x - a.x) * (c.y - a.y) / (b.y - a.y) + a.x) {
					inside = !inside;
				}
			}
			if (inside) fn(uint32_t(index(cx, cy)));
		}
	}
}

void NavGrid::mark_walkable(const Vec2 *points, int count) {
	for_cells_inside(points, count, [&](uint32_t i) { terrain_[i] = 1; });
	regions_dirty_ = true;
	clearance_full_ = true;
}

void NavGrid::set_blocker(int64_t key, const std::vector<std::vector<Vec2>> &outlines) {
	clear_blocker(key);
	std::vector<uint32_t> cells;
	for (const auto &outline : outlines) {
		for_cells_inside(outline.data(), int(outline.size()), [&](uint32_t i) { cells.push_back(i); });
	}
	// Outlines of one body can overlap (a building's several shapes); a cell
	// counts once per key so clearing the key restores it exactly.
	std::sort(cells.begin(), cells.end());
	cells.erase(std::unique(cells.begin(), cells.end()), cells.end());
	for (uint32_t i : cells) ++blockers_[i];
	mark_clearance_dirty(cells);
	stamps_[key] = std::move(cells);
}

void NavGrid::clear_blocker(int64_t key) {
	auto it = stamps_.find(key);
	if (it == stamps_.end()) return;
	for (uint32_t i : it->second) {
		if (blockers_[i] > 0) --blockers_[i];
	}
	reopen_cells(it->second);
	mark_clearance_dirty(it->second);
	stamps_.erase(it);
}

void NavGrid::clear_all_blockers() {
	std::fill(blockers_.begin(), blockers_.end(), uint16_t(0));
	stamps_.clear();
	regions_dirty_ = true;
	clearance_full_ = true;
}

bool NavGrid::line_of_sight(Vec2 a, Vec2 b) const {
	int cx = cell_x(a.x), cy = cell_y(a.y);
	const int ex = cell_x(b.x), ey = cell_y(b.y);
	if (!open(cx, cy)) return false;

	const float dx = b.x - a.x, dy = b.y - a.y;
	const int step_x = dx > 0 ? 1 : (dx < 0 ? -1 : 0);
	const int step_y = dy > 0 ? 1 : (dy < 0 ? -1 : 0);

	constexpr float kHuge = 1e30f;
	const float t_delta_x = step_x ? std::fabs(cell_ / dx) : kHuge;
	const float t_delta_y = step_y ? std::fabs(cell_ / dy) : kHuge;
	float t_max_x = kHuge, t_max_y = kHuge;
	if (step_x) t_max_x = (origin_.x + float(cx + (step_x > 0)) * cell_ - a.x) / dx;
	if (step_y) t_max_y = (origin_.y + float(cy + (step_y > 0)) * cell_ - a.y) / dy;

	// A degenerate ray must still terminate.
	const int max_steps = std::abs(ex - cx) + std::abs(ey - cy) + 2;
	for (int i = 0; i < max_steps; ++i) {
		if (cx == ex && cy == ey) return true;
		if (t_max_x < t_max_y) { t_max_x += t_delta_x; cx += step_x; }
		else { t_max_y += t_delta_y; cy += step_y; }
		if (!open(cx, cy)) return false;
	}
	return cx == ex && cy == ey;
}

bool NavGrid::nearest_open(Vec2 p, float max_radius, Vec2 &out) const {
	const int px = cell_x(p.x), py = cell_y(p.y);
	if (open(px, py)) { out = p; return true; }
	const int max_ring = int(std::ceil(max_radius * inv_cell_));
	// Rings of growing Chebyshev radius; within a ring, keep the truly closest.
	for (int r = 1; r <= max_ring; ++r) {
		float best = 1e30f;
		bool found = false;
		for (int oy = -r; oy <= r; ++oy) {
			for (int ox = -r; ox <= r; ++ox) {
				if (std::max(std::abs(ox), std::abs(oy)) != r) continue;
				if (!open(px + ox, py + oy)) continue;
				const Vec2 c = cell_center(px + ox, py + oy);
				const float d = dist_sq(c, p);
				if (d < best) { best = d; out = c; found = true; }
			}
		}
		if (found) return true;
	}
	return false;
}

float NavGrid::sample_height(Vec2 p) const {
	if (height_size_ == 0) return 0.0f;
	const float fx = (p.x - height_origin_.x) * inv_height_spacing_;
	const float fy = (p.y - height_origin_.y) * inv_height_spacing_;
	const int last = height_size_ - 1;
	const int x0 = std::clamp(int(std::floor(fx)), 0, last), y0 = std::clamp(int(std::floor(fy)), 0, last);
	const int x1 = std::min(x0 + 1, last), y1 = std::min(y0 + 1, last);
	const float tx = clampf(fx - float(x0), 0.0f, 1.0f), ty = clampf(fy - float(y0), 0.0f, 1.0f);
	const float h00 = heights_[size_t(y0) * height_size_ + x0], h10 = heights_[size_t(y0) * height_size_ + x1];
	const float h01 = heights_[size_t(y1) * height_size_ + x0], h11 = heights_[size_t(y1) * height_size_ + x1];
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), ty);
}

float NavGrid::sample_slope(Vec2 p) const {
	const float d = height_spacing_;
	const float hx = sample_height({ p.x + d, p.y }) - sample_height({ p.x - d, p.y });
	const float hy = sample_height({ p.x, p.y + d }) - sample_height({ p.x, p.y - d });
	return std::sqrt(hx * hx + hy * hy) / (2.0f * d);
}

std::vector<uint8_t> NavGrid::debug_cells() const {
	std::vector<uint8_t> out(terrain_.size());
	for (size_t i = 0; i < out.size(); ++i) {
		out[i] = !terrain_[i] ? 0 : (blockers_[i] ? 2 : 1);
	}
	return out;
}

// Eight-connected, octile heuristic (admissible against these step costs, so
// the route is optimal), lazy decrease-key. Costs are in sixteenths so the
// whole search stays integer.
namespace {
constexpr int kNbrDx[8] = { 1, -1, 0, 0, 1, 1, -1, -1 };
constexpr int kNbrDy[8] = { 0, 0, 1, -1, 1, -1, 1, -1 };
constexpr uint32_t kStepCost[8] = { 16, 16, 16, 16, 23, 23, 23, 23 };
// How far a start or goal inside something solid may slide to open ground.
constexpr float kSnapRadius = 12.0f;
// How far an unreachable goal may move to the nearest ground the start can
// actually reach (the far bank of a river, the edge of a walled-in yard).
constexpr float kRegionSnapRadius = 60.0f;
// Inflates the heuristic so the search heads for the goal rather than fanning
// out; routes can come out a little longer than the shortest, which the
// string-pulling mostly takes back.
constexpr uint32_t kHeuristicWeightNum = 3, kHeuristicWeightDen = 2;
} // namespace

// ------------------------------------------------------------------ clearance

void NavGrid::mark_clearance_dirty(const std::vector<uint32_t> &cells) {
	if (cells.empty() || clearance_full_) return;
	int x0 = cols_, y0 = rows_, x1 = -1, y1 = -1;
	for (uint32_t i : cells) {
		const int cx = int(i) % cols_, cy = int(i) / cols_;
		x0 = std::min(x0, cx); y0 = std::min(y0, cy);
		x1 = std::max(x1, cx); y1 = std::max(y1, cy);
	}
	// A change reaches as far as the cap, so everything within it recomputes.
	x0 -= kClearanceCap; y0 -= kClearanceCap; x1 += kClearanceCap; y1 += kClearanceCap;
	if (!clearance_window_) {
		clr_x0_ = x0; clr_y0_ = y0; clr_x1_ = x1; clr_y1_ = y1;
		clearance_window_ = true;
	} else {
		clr_x0_ = std::min(clr_x0_, x0); clr_y0_ = std::min(clr_y0_, y0);
		clr_x1_ = std::max(clr_x1_, x1); clr_y1_ = std::max(clr_y1_, y1);
	}
}

void NavGrid::refresh_clearance() {
	if (clearance_full_) {
		clearance_.assign(size_t(cols_) * rows_, 0);
		compute_clearance(0, 0, cols_ - 1, rows_ - 1);
		clearance_full_ = false;
		clearance_window_ = false;
	} else if (clearance_window_) {
		compute_clearance(clr_x0_, clr_y0_, clr_x1_, clr_y1_);
		clearance_window_ = false;
	}
}

void NavGrid::compute_clearance(int x0, int y0, int x1, int y1) {
	x0 = std::max(0, x0); y0 = std::max(0, y0);
	x1 = std::min(cols_ - 1, x1); y1 = std::min(rows_ - 1, y1);
	const uint8_t cap = uint8_t(kClearanceCap * 2);
	for (int cy = y0; cy <= y1; ++cy) {
		for (int cx = x0; cx <= x1; ++cx) clearance_[index(cx, cy)] = open(cx, cy) ? cap : 0;
	}
	// Off the map counts as solid.
	auto at = [&](int cx, int cy) -> int { return in_bounds(cx, cy) ? clearance_[index(cx, cy)] : 0; };
	for (int cy = y0; cy <= y1; ++cy) {
		for (int cx = x0; cx <= x1; ++cx) {
			uint8_t &c = clearance_[index(cx, cy)];
			if (c == 0) continue;
			int best = c;
			best = std::min(best, at(cx - 1, cy) + 2);
			best = std::min(best, at(cx - 1, cy - 1) + 3);
			best = std::min(best, at(cx, cy - 1) + 2);
			best = std::min(best, at(cx + 1, cy - 1) + 3);
			c = uint8_t(best);
		}
	}
	for (int cy = y1; cy >= y0; --cy) {
		for (int cx = x1; cx >= x0; --cx) {
			uint8_t &c = clearance_[index(cx, cy)];
			if (c == 0) continue;
			int best = c;
			best = std::min(best, at(cx + 1, cy) + 2);
			best = std::min(best, at(cx + 1, cy + 1) + 3);
			best = std::min(best, at(cx, cy + 1) + 2);
			best = std::min(best, at(cx - 1, cy + 1) + 3);
			c = uint8_t(best);
		}
	}
}

uint8_t NavGrid::clearance_units(int cx, int cy) const {
	return in_bounds(cx, cy) && !clearance_.empty() ? clearance_[index(cx, cy)] : 0;
}

float NavGrid::clearance_cells(int cx, int cy) {
	refresh_clearance();
	return float(clearance_units(cx, cy)) * 0.5f;
}

bool NavGrid::line_clear(Vec2 a, Vec2 b, uint8_t min_units) const {
	int cx = cell_x(a.x), cy = cell_y(a.y);
	const int ex = cell_x(b.x), ey = cell_y(b.y);
	if (clearance_units(cx, cy) < min_units) return false;
	const float dx = b.x - a.x, dy = b.y - a.y;
	const int step_x = dx > 0 ? 1 : (dx < 0 ? -1 : 0);
	const int step_y = dy > 0 ? 1 : (dy < 0 ? -1 : 0);
	constexpr float kHuge = 1e30f;
	const float t_delta_x = step_x ? std::fabs(cell_ / dx) : kHuge;
	const float t_delta_y = step_y ? std::fabs(cell_ / dy) : kHuge;
	float t_max_x = kHuge, t_max_y = kHuge;
	if (step_x) t_max_x = (origin_.x + float(cx + (step_x > 0)) * cell_ - a.x) / dx;
	if (step_y) t_max_y = (origin_.y + float(cy + (step_y > 0)) * cell_ - a.y) / dy;
	const int max_steps = std::abs(ex - cx) + std::abs(ey - cy) + 2;
	for (int i = 0; i < max_steps; ++i) {
		if (cx == ex && cy == ey) return true;
		if (t_max_x < t_max_y) { t_max_x += t_delta_x; cx += step_x; }
		else { t_max_y += t_delta_y; cy += step_y; }
		if (clearance_units(cx, cy) < min_units) return false;
	}
	return cx == ex && cy == ey;
}

uint32_t NavGrid::find_region(uint32_t label) {
	while (region_parent_[label] != label) {
		region_parent_[label] = region_parent_[region_parent_[label]];
		label = region_parent_[label];
	}
	return label;
}

void NavGrid::join_regions(uint32_t a, uint32_t b) {
	a = find_region(a);
	b = find_region(b);
	if (a != b) region_parent_[std::max(a, b)] = std::min(a, b);
}

uint32_t NavGrid::region_of(int cx, int cy) {
	if (!open(cx, cy)) return 0;
	if (regions_dirty_) relabel_regions();
	const uint32_t raw = regions_[index(cx, cy)];
	return raw ? find_region(raw) : 0;
}

// 4-connected flood fill. That matches the search exactly: it only takes a
// diagonal step when both cells beside it are open, so anything it can reach
// is 4-connected too. Only needed when the terrain itself changes; stamps
// coming and going are handled incrementally (see set_blocker, clear_blocker).
void NavGrid::relabel_regions() {
	regions_dirty_ = false;
	regions_.assign(size_t(cols_) * rows_, 0);
	region_parent_.assign(1, 0);
	for (int start = 0; start < cols_ * rows_; ++start) {
		if (regions_[start] || !terrain_[start] || blockers_[start]) continue;
		const uint32_t label = new_region();
		regions_[start] = label;
		flood_.clear();
		flood_.push_back(start);
		while (!flood_.empty()) {
			const int32_t i = flood_.back();
			flood_.pop_back();
			const int cx = i % cols_, cy = i / cols_;
			const int nbr[4][2] = { { cx + 1, cy }, { cx - 1, cy }, { cx, cy + 1 }, { cx, cy - 1 } };
			for (const auto &n : nbr) {
				if (!open(n[0], n[1])) continue;
				const int32_t j = index(n[0], n[1]);
				if (regions_[j]) continue;
				regions_[j] = label;
				flood_.push_back(j);
			}
		}
	}
}

uint32_t NavGrid::new_region() {
	const uint32_t label = uint32_t(region_parent_.size());
	region_parent_.push_back(label);
	return label;
}

// Cells a stamp has just released can only join regions together, never split
// one, so each reopened cell takes its neighbours' region and merges any
// different ones it now connects. Cheap, where a relabel of the whole map is
// milliseconds — and trees are felled all match long.
void NavGrid::reopen_cells(const std::vector<uint32_t> &cells) {
	if (regions_dirty_) return; // the coming relabel sees them anyway
	for (uint32_t i : cells) {
		if (!terrain_[i] || blockers_[i]) continue;
		if (regions_[i] == 0) regions_[i] = new_region();
	}
	for (uint32_t i : cells) {
		if (!terrain_[i] || blockers_[i]) continue;
		const int cx = int(i) % cols_, cy = int(i) / cols_;
		const int nbr[4][2] = { { cx + 1, cy }, { cx - 1, cy }, { cx, cy + 1 }, { cx, cy - 1 } };
		for (const auto &n : nbr) {
			if (!open(n[0], n[1])) continue;
			const uint32_t other = regions_[index(n[0], n[1])];
			if (other) join_regions(regions_[i], other);
		}
	}
}

bool NavGrid::nearest_in_region(Vec2 p, uint32_t region, float max_radius, Vec2 &out) {
	const int px = cell_x(p.x), py = cell_y(p.y);
	if (region_of(px, py) == region) { out = p; return true; }
	const int max_ring = int(std::ceil(max_radius * inv_cell_));
	for (int r = 1; r <= max_ring; ++r) {
		float best = 1e30f;
		bool found = false;
		for (int oy = -r; oy <= r; ++oy) {
			// Only the ring's edge: the whole row at the top and bottom, the
			// two end cells in between.
			const int step = (oy == -r || oy == r) ? 1 : 2 * r;
			for (int ox = -r; ox <= r; ox += step) {
				if (region_of(px + ox, py + oy) != region) continue;
				const Vec2 c = cell_center(px + ox, py + oy);
				const float d = dist_sq(c, p);
				if (d < best) { best = d; out = c; found = true; }
			}
		}
		if (found) return true;
	}
	return false;
}

uint32_t NavGrid::heuristic(int cx, int cy) const {
	const int dx = std::abs(cx - ctx_->search.gx), dy = std::abs(cy - ctx_->search.gy);
	const int lo = std::min(dx, dy), hi = std::max(dx, dy);
	return uint32_t(16 * (hi - lo) + 23 * lo) * kHeuristicWeightNum / kHeuristicWeightDen;
}

namespace {
bool heap_less(const std::pair<uint32_t, int32_t> &a, const std::pair<uint32_t, int32_t> &b) {
	return a.first > b.first;
}
} // namespace

NavGrid::SearchStatus NavGrid::begin_path(Vec2 start, Vec2 goal, uint32_t max_expansions, uint8_t min_clearance) {
	ctx_->search.active = false;
	ctx_->result.clear();
	ctx_->reached = false;
	Vec2 s, g;
	if (!nearest_open(start, kSnapRadius, s) || !nearest_open(goal, kSnapRadius, g)) return SearchStatus::Done;
	// A goal the start cannot reach becomes the nearest point it can, so the
	// search always has a goal it can get to and never exhausts itself
	// proving there is none.
	const uint32_t home = region_of(cell_x(s.x), cell_y(s.y));
	if (region_of(cell_x(g.x), cell_y(g.y)) != home && !nearest_in_region(g, home, kRegionSnapRadius, g)) {
		return SearchStatus::Done;
	}
	// Open ground in a straight line needs no search at all — for a block,
	// ground wide enough for it (or as wide as its two ends allow).
	uint8_t need = 0;
	if (min_clearance > 0) {
		refresh_clearance();
		need = uint8_t(std::min<int>(min_clearance * 2, std::min(clearance_units(cell_x(s.x), cell_y(s.y)),
				clearance_units(cell_x(g.x), cell_y(g.y)))));
	}
	if (need > 0 ? line_clear(s, g, need) : line_of_sight(s, g)) {
		ctx_->result.push_back(g);
		ctx_->reached = true;
		return SearchStatus::Done;
	}

	const size_t cells = size_t(cols_) * rows_;
	if (ctx_->nodes.size() != cells) {
		ctx_->nodes.assign(cells, Node{});
		ctx_->stamp = 0;
	}
	if (++ctx_->stamp == 0) { // wrapped: every stamp is now ambiguous
		for (Node &n : ctx_->nodes) n.stamp = 0;
		ctx_->stamp = 1;
	}

	ctx_->search = Search{};
	ctx_->search.active = true;
	ctx_->search.start = s;
	ctx_->search.goal = g;
	ctx_->search.gx = cell_x(g.x);
	ctx_->search.gy = cell_y(g.y);
	ctx_->search.goal_idx = index(ctx_->search.gx, ctx_->search.gy);
	ctx_->search.max_expansions = max_expansions;
	ctx_->search.min_clearance = uint8_t(std::min<int>(min_clearance * 2, 255));
	const int sx = cell_x(s.x), sy = cell_y(s.y);
	const int32_t start_idx = index(sx, sy);
	ctx_->search.best_cell = start_idx;
	ctx_->search.best_h = heuristic(sx, sy);
	ctx_->open.clear();
	ctx_->nodes[start_idx] = Node{ 0, ctx_->search.best_h, -1, ctx_->stamp, 0 };
	ctx_->open.emplace_back(ctx_->search.best_h, start_idx);
	return SearchStatus::Running;
}

NavGrid::SearchStatus NavGrid::continue_path(uint32_t budget, uint32_t &expanded) {
	expanded = 0;
	if (!ctx_->search.active) return SearchStatus::Done;
	bool found = false;
	while (!ctx_->open.empty() && expanded < budget && ctx_->search.expanded < ctx_->search.max_expansions) {
		std::pop_heap(ctx_->open.begin(), ctx_->open.end(), heap_less);
		const int32_t cell = ctx_->open.back().second;
		ctx_->open.pop_back();
		Node &n = ctx_->nodes[cell];
		if (n.stamp != ctx_->stamp || n.closed) continue; // stale heap entry
		n.closed = 1;
		++expanded;
		++ctx_->search.expanded;
		if (cell == ctx_->search.goal_idx) { found = true; break; }

		const int cx = cell % cols_, cy = cell / cols_;
		// The closest cell reached, so a goal it runs out of budget for still
		// gets a route toward it rather than none.
		const uint32_t h = heuristic(cx, cy);
		if (h < ctx_->search.best_h) { ctx_->search.best_h = h; ctx_->search.best_cell = cell; }

		for (int i = 0; i < 8; ++i) {
			const int nx = cx + kNbrDx[i], ny = cy + kNbrDy[i];
			if (!open(nx, ny)) continue;
			// No cutting a corner between two blocked cells.
			if (i >= 4 && (!open(cx + kNbrDx[i], cy) || !open(cx, cy + kNbrDy[i]))) continue;
			const int32_t ni = index(nx, ny);
			uint32_t tentative = n.g + kStepCost[i];
			// Tight for this block: the tighter, the dearer.
			const uint8_t need = ctx_->search.min_clearance;
			if (need > 0) {
				const uint8_t have = clearance_units(nx, ny);
				if (have < need) tentative += kStepCost[i] * uint32_t(need - have);
			}
			Node &nn = ctx_->nodes[ni];
			if (nn.stamp != ctx_->stamp) {
				nn = Node{ tentative, tentative + heuristic(nx, ny), cell, ctx_->stamp, 0 };
				ctx_->open.emplace_back(nn.f, ni);
				std::push_heap(ctx_->open.begin(), ctx_->open.end(), heap_less);
			} else if (!nn.closed && tentative < nn.g) {
				nn.g = tentative;
				nn.parent = cell;
				nn.f = tentative + heuristic(nx, ny);
				ctx_->open.emplace_back(nn.f, ni);
				std::push_heap(ctx_->open.begin(), ctx_->open.end(), heap_less);
			}
		}
	}
	const bool exhausted = ctx_->open.empty() || ctx_->search.expanded >= ctx_->search.max_expansions;
	if (!found && !exhausted) return SearchStatus::Running;

	ctx_->search.active = false;
	ctx_->raw.clear();
	ctx_->raw.push_back(ctx_->search.start);
	const size_t first = ctx_->raw.size();
	for (int32_t cur = found ? ctx_->search.goal_idx : ctx_->search.best_cell; cur >= 0;) {
		ctx_->raw.push_back(cell_center(cur % cols_, cur / cols_));
		const Node &n = ctx_->nodes[cur];
		if (n.stamp != ctx_->stamp) break;
		cur = n.parent;
	}
	std::reverse(ctx_->raw.begin() + first, ctx_->raw.end());
	// Aim at the real destination, not the centre of its cell.
	if (found) ctx_->raw.back() = ctx_->search.goal;
	if (ctx_ == &local_) {
		// A detour keeps every cell (from the one the man stands in), so he
		// can always tell where on it he is and step on to the next.
		ctx_->result.assign(ctx_->raw.begin() + 1, ctx_->raw.end());
	} else {
		simplify(ctx_->raw, ctx_->result);
	}
	ctx_->reached = found;
	return SearchStatus::Done;
}

void NavGrid::cancel_path() {
	ctx_->search.active = false;
}

bool NavGrid::find_detour(Vec2 start, Vec2 goal, uint32_t max_expansions, std::vector<Vec2> &out, uint32_t &expanded) {
	ctx_ = &local_;
	expanded = 0;
	if (begin_path(start, goal, max_expansions) == SearchStatus::Running) {
		continue_path(max_expansions, expanded);
	}
	out = local_.result;
	const bool found = !out.empty();
	ctx_ = &main_;
	return found;
}

bool NavGrid::find_path(Vec2 start, Vec2 goal, uint32_t max_expansions, std::vector<Vec2> &out, uint32_t &expanded) {
	expanded = 0;
	if (begin_path(start, goal, max_expansions) == SearchStatus::Running) {
		continue_path(max_expansions, expanded);
	}
	out = ctx_->result;
	return ctx_->reached;
}

// A grid route is a staircase; following it literally makes a block wobble.
// Keeps only the points where the route has to turn. raw[0] is the start and
// is not emitted.
void NavGrid::simplify(const std::vector<Vec2> &raw, std::vector<Vec2> &out) const {
	out.clear();
	if (raw.size() < 2) return;
	const uint8_t need = ctx_->search.min_clearance;
	size_t anchor = 0;
	// The tightest the raw route itself gets since the anchor: a shortcut may
	// be that tight but no tighter, so a block never cuts back through a gap
	// its route went round.
	int tightest = need;
	for (size_t i = 2; i < raw.size(); ++i) {
		if (need > 0) {
			tightest = std::min<int>(tightest, clearance_units(cell_x(raw[i - 1].x), cell_y(raw[i - 1].y)));
		}
		const bool clear = need > 0 ? line_clear(raw[anchor], raw[i], uint8_t(std::min<int>(tightest, need)))
									: line_of_sight(raw[anchor], raw[i]);
		if (!clear) {
			out.push_back(raw[i - 1]);
			anchor = i - 1;
			tightest = need;
		}
	}
	out.push_back(raw.back());
}

} // namespace army
