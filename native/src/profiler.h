// Per-part timing for the sim. A single "sim: 4 ms" is useless for tuning, so
// every stage of the tick is timed on its own and read back by PerfStats.

#pragma once

#include <array>
#include <chrono>
#include <cstdint>

namespace army {

// A fixed enum rather than string keys, so starting and stopping a timer inside
// the tick is an array index, not a hash lookup.
enum class Zone : uint8_t {
	Tick = 0,
	Commands,
	Pathfinding,
	FormationMotion,
	SlotTargets,
	SpatialHash,
	Steering,
	Contact,
	Combat,
	Readback,
	Count,
};

inline constexpr size_t kZoneCount = static_cast<size_t>(Zone::Count);

inline const char *zone_name(Zone z) {
	switch (z) {
		case Zone::Tick: return "tick";
		case Zone::Commands: return "commands";
		case Zone::Pathfinding: return "pathfinding";
		case Zone::FormationMotion: return "formation motion";
		case Zone::SlotTargets: return "slot targets";
		case Zone::SpatialHash: return "spatial hash";
		case Zone::Steering: return "steering";
		case Zone::Contact: return "contact";
		case Zone::Combat: return "combat";
		case Zone::Readback: return "readback";
		default: return "unknown";
	}
}

class Profiler {
public:
	using Clock = std::chrono::steady_clock;

	void begin_tick() { current_.fill(0.0); }

	void end_tick() {
		for (size_t i = 0; i < kZoneCount; ++i) {
			last_[i] = current_[i];
			if (current_[i] > peak_[i]) peak_[i] = current_[i];
		}
		++ticks_;
	}

	void add(Zone zone, double ms) { current_[static_cast<size_t>(zone)] += ms; }

	double last_ms(Zone zone) const { return last_[static_cast<size_t>(zone)]; }
	double peak_ms(Zone zone) const { return peak_[static_cast<size_t>(zone)]; }
	uint64_t ticks() const { return ticks_; }
	void reset_peaks() { peak_.fill(0.0); }

private:
	std::array<double, kZoneCount> current_{};
	std::array<double, kZoneCount> last_{};
	std::array<double, kZoneCount> peak_{};
	uint64_t ticks_ = 0;
};

// Adds the scope's duration to a zone on exit, so repeated scopes for one zone
// within a tick sum.
class ScopedZone {
public:
	ScopedZone(Profiler &profiler, Zone zone) :
			profiler_(profiler), zone_(zone), start_(Profiler::Clock::now()) {}
	~ScopedZone() {
		profiler_.add(zone_, std::chrono::duration<double, std::milli>(Profiler::Clock::now() - start_).count());
	}
	ScopedZone(const ScopedZone &) = delete;
	ScopedZone &operator=(const ScopedZone &) = delete;

private:
	Profiler &profiler_;
	Zone zone_;
	Profiler::Clock::time_point start_;
};

#define ARMY_CONCAT_INNER(a, b) a##b
#define ARMY_CONCAT(a, b) ARMY_CONCAT_INNER(a, b)
#if ARMY_PROFILING
#define ARMY_PROFILE_ZONE(profiler, zone) ::army::ScopedZone ARMY_CONCAT(army_zone_, __LINE__)((profiler), (zone))
#else
#define ARMY_PROFILE_ZONE(profiler, zone) ((void)0)
#endif

} // namespace army
