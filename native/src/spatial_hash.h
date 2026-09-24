// Uniform-grid neighbour lookup for units, rebuilt from scratch every tick with
// a counting sort. Cheaper and far more cache-friendly than keeping per-cell
// lists up to date, and the layout depends only on unit positions and ids,
// never on what last tick looked like.

#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace army {

class SpatialHash {
public:
	void configure(float min_x, float min_y, float max_x, float max_y, float cell) {
		min_x_ = min_x;
		min_y_ = min_y;
		cell_ = cell;
		inv_cell_ = 1.0f / cell;
		cols_ = std::max(1, int((max_x - min_x) * inv_cell_) + 1);
		rows_ = std::max(1, int((max_y - min_y) * inv_cell_) + 1);
		cell_start_.assign(size_t(cols_) * rows_ + 1, 0);
		counts_.assign(size_t(cols_) * rows_, 0);
	}

	bool configured() const { return cols_ > 0; }

	// Bins every unit with `include[i]` set.
	void rebuild(const float *px, const float *py, const uint8_t *include, uint32_t n) {
		const size_t cells = size_t(cols_) * rows_;
		std::fill(counts_.begin(), counts_.end(), 0u);
		cell_of_.resize(n);
		for (uint32_t i = 0; i < n; ++i) {
			if (!include[i]) {
				cell_of_[i] = -1;
				continue;
			}
			const int c = cell_index(px[i], py[i]);
			cell_of_[i] = c;
			++counts_[c];
		}
		uint32_t running = 0;
		for (size_t c = 0; c < cells; ++c) {
			cell_start_[c] = running;
			running += counts_[c];
		}
		cell_start_[cells] = running;
		cursor_.assign(cell_start_.begin(), cell_start_.end() - 1);
		entries_.resize(running);
		for (uint32_t i = 0; i < n; ++i) {
			const int c = cell_of_[i];
			if (c >= 0) entries_[cursor_[c]++] = i;
		}
	}

	// Calls fn(id) for every binned unit in the cells overlapping the square
	// of `radius` around (x, y); the caller does the exact distance test.
	// Templated so the callback inlines: this is the hottest call in the sim.
	template <typename Fn>
	void query(float x, float y, float radius, Fn &&fn) const {
		const int cx0 = cell_x(x - radius), cx1 = cell_x(x + radius);
		const int cy0 = cell_y(y - radius), cy1 = cell_y(y + radius);
		for (int cy = cy0; cy <= cy1; ++cy) {
			const size_t row = size_t(cy) * cols_;
			for (int cx = cx0; cx <= cx1; ++cx) {
				const size_t c = row + cx;
				for (uint32_t e = cell_start_[c]; e < cell_start_[c + 1]; ++e) {
					if (!fn(entries_[e])) return;
				}
			}
		}
	}

private:
	int cell_x(float x) const { return std::clamp(int(std::floor((x - min_x_) * inv_cell_)), 0, cols_ - 1); }
	int cell_y(float y) const { return std::clamp(int(std::floor((y - min_y_) * inv_cell_)), 0, rows_ - 1); }
	int cell_index(float x, float y) const { return cell_y(y) * cols_ + cell_x(x); }

	float min_x_ = 0.0f, min_y_ = 0.0f, cell_ = 1.0f, inv_cell_ = 1.0f;
	int cols_ = 0, rows_ = 0;
	std::vector<uint32_t> cell_start_, counts_, cursor_, entries_;
	std::vector<int> cell_of_;
};

} // namespace army
