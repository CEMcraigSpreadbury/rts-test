// FigureBatcher - draws every unit that has a 3D figure (assets/art/Models/
// Units) as instances of one MultiMesh per figure type, beside SpriteBatcher.
//
// A figure is rigid: no skeleton, no baked animation. Its unit keeps its
// AnimatedSprite3D, hidden, for everything the game already does with it
// (clips and their signals, the lunge / recoil / knockback / squash tweens on
// its position and scale, hit flashes in its modulate, hitstop). Each frame
// this reads that state and turns it into a pose: the sprite's offset and
// squash carried over, plus a procedural hop, waddle, lean, swing, bob or
// topple for the clip that is playing. When a dying unit's node is freed its
// figure stays behind as a corpse, then sinks and fades.
//
// Per figure type there are three MultiMeshes: the near mesh, the far one
// (LOD1, picked per instance by camera distance), and a shadow-only one that
// casts every figure's shadow from the far mesh.

#pragma once

#include <godot_cpp/classes/animated_sprite3d.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/string_name.hpp>

#include <map>
#include <unordered_map>
#include <utility>
#include <vector>

class FigureBatcher : public godot::Node3D {
	GDCLASS(FigureBatcher, godot::Node3D)

protected:
	static void _bind_methods();

public:
	FigureBatcher();

	// Called with (mesh: Mesh, palette: Texture2D) the first time a figure
	// type is seen; returns the Material (with its next_pass chain) to draw it.
	void set_material_factory(const godot::Callable &factory);
	// Draws `unit` as its figure from now on. `sprite` is the unit's hidden
	// AnimatedSprite3D the pose is read from; `rest_position`/`rest_scale` are
	// the sprite's authored ones (its tweens are offsets from them);
	// `walk_speed` is the unit's move speed, for how high a slow walk hops.
	void add_figure(godot::Node3D *unit, godot::AnimatedSprite3D *sprite, const godot::Ref<godot::Mesh> &mesh,
			const godot::Ref<godot::Mesh> &lod1, const godot::Ref<godot::Texture2D> &palette, const godot::Color &team,
			const godot::Vector3 &rest_position, const godot::Vector3 &rest_scale, float walk_speed);
	// How a figure moves for what it carries (see Motion): its attack and
	// cast poses.
	void set_figure_motion(godot::Node3D *unit, int motion);
	// Another figure the unit is drawn as while its sprite plays `role`'s
	// clips (a villager's "build", "wood", "gold": see Unit._set_work_role),
	// in the same palette.
	void set_figure_variant(godot::Node3D *unit, const godot::StringName &role, const godot::Ref<godot::Mesh> &mesh,
			const godot::Ref<godot::Mesh> &lod1);
	// No longer drawn as a figure. A dying unit's figure stays as a corpse,
	// unless `leave_corpse` is off (it is going back to its sprite).
	void remove_figure(godot::Node3D *unit, bool leave_corpse = true);
	void set_team_color(godot::Node3D *unit, const godot::Color &team);
	bool has_figure(godot::Node3D *unit) const;
	int get_figure_count() const { return int(entries_.size()); }
	int get_corpse_count() const { return int(corpses_.size()); }
	// Beyond this far from the camera a figure draws its LOD1 mesh.
	void set_lod_distance(float distance) { lod_distance_ = distance; }
	float get_lod_distance() const { return lod_distance_; }
	void set_cast_shadows(bool cast);
	bool get_cast_shadows() const { return cast_shadows_; }
	// Off: poses are not worked out and nothing is drawn (headless runs).
	void set_drawing(bool drawing);
	bool is_drawing() const { return drawing_; }
	// The living figure the ray (from the camera, `dir` normalised) points
	// at, as last drawn: of those whose upright axis it passes within 0.3 m
	// of, the nearest to its axis. {"collider", "position", "distance"}, or
	// empty.
	godot::Dictionary pick(const godot::Vector3 &from, const godot::Vector3 &dir) const;
	// Instances drawn last frame: [near, far, shadow casters].
	godot::PackedInt32Array get_drawn_counts() const;

	void _process(double delta) override;

private:
	enum Clip { CLIP_IDLE, CLIP_WALK, CLIP_ATTACK, CLIP_GATHER, CLIP_CAST, CLIP_DEATH, CLIP_OTHER };
	// MOTION_MELEE swings (rear back, lean in); MOTION_BOW draws and looses
	// on the clip's release frame (Unit.SHOT_RELEASE_LEAD_FRAMES before its
	// end, when the arrow leaves); MOTION_MOUNTED rocks into a gallop
	// instead of hopping, lunges when it strikes and falls on its side.
	// MOTION_STOMP (monsters) strikes and falls like MOTION_MOUNTED but walks
	// in heavy stomps: up, over, down with a squash, a pause on the ground
	// (the figure is held back so it does not slide while the unit moves on
	// steadily), and emits `stomped` as it lands.
	// MOTION_ROLL (siege engines) never hops or breathes: it rumbles on its
	// wheels while moving (a small bob, rock and sway), kicks back on the
	// shot's release frame and settles, and tips over on its side when it
	// dies.
	enum Motion { MOTION_MELEE = 0, MOTION_BOW = 1, MOTION_MOUNTED = 2, MOTION_STOMP = 3, MOTION_ROLL = 4 };

	struct Batch {
		godot::MultiMeshInstance3D *node = nullptr;
		godot::Ref<godot::MultiMesh> mesh;
		std::vector<float> data;
		int count = 0;
	};
	struct Type {
		godot::Ref<godot::Mesh> mesh;
		godot::Ref<godot::Mesh> lod1;
		godot::Ref<godot::Texture2D> palette;
		float height = 1.0f;
		// How near its upright axis a click must pass to find it.
		float pick_radius = 0.3f;
		// Frustum test radii round its middle (drawn, casting a shadow), and
		// how much further than lod_distance_ it keeps its near mesh. All
		// grow with a big figure's bounds (see type_for); a man or a horse
		// keeps the defaults.
		float view_radius = 1.0f;
		float shadow_radius = 5.0f;
		float lod_scale = 1.0f;
		Batch near_batch;
		Batch far_batch;
		Batch shadow_batch;
	};
	struct Entry {
		godot::ObjectID unit;
		godot::ObjectID sprite;
		int type = 0;
		// The figure it is drawn as with no work role, and its role variants.
		int base_type = 0;
		std::vector<std::pair<godot::StringName, int>> variants;
		int motion = MOTION_MELEE;
		float team_packed = 0.0f;
		godot::Vector3 rest_position;
		godot::Vector3 rest_scale = godot::Vector3(1, 1, 1);
		float walk_speed = 3.0f;
		// Per unit, so a block hops close to, but not in, unison.
		float phase = 0.0f;
		float clock = 0.0f;
		float hop_phase = 0.0f;
		float walk_amount = 0.0f;
		float speed = 0.0f;
		// Ground velocity, smoothed (a stomp holds the figure back by it).
		godot::Vector3 velocity;
		// A stomp's cycles walked (0: standing), and whether it landed in
		// this frame's pose.
		float stomp = 0.0f;
		bool landed = false;
		// Seconds of its velocity the figure is drawn off the unit (behind
		// while it pauses on the ground, ahead as it lands).
		float hold = 0.0f;
		godot::Vector3 last_position;
		bool has_last_position = false;
		godot::StringName anim;
		Clip clip = CLIP_IDLE;
		float next_idle_hop = 0.0f;
		float idle_hop_age = 1.0f;
		bool had_overlay = false;
		bool dying = false;
		float death_age = 0.0f;
		bool topple_locked = false;
		godot::Vector3 topple_axis = godot::Vector3(1, 0, 0);
		godot::Transform3D last_world;
		bool was_drawn = false;
	};
	struct Corpse {
		int type = 0;
		godot::Transform3D world;
		float team_packed = 0.0f;
		float age = 0.0f;
		bool shown = true;
	};
	struct Pickable {
		godot::ObjectID unit;
		godot::Vector3 base;
		float height = 1.0f;
		float radius = 0.3f;
	};

	int type_for(const godot::Ref<godot::Mesh> &mesh, const godot::Ref<godot::Mesh> &lod1,
			const godot::Ref<godot::Texture2D> &palette);
	void make_batch(Batch &batch, const godot::Ref<godot::Mesh> &mesh, const godot::Ref<godot::Material> &material,
			int shadows);
	void erase_at(size_t i, bool leave_corpse);
	godot::Transform3D pose(Entry &e, godot::AnimatedSprite3D *sprite, float delta);
	static Clip clip_of(const godot::StringName &anim);
	static void write(Batch &b, const godot::Transform3D &xf, const float custom[4]);
	void upload(Batch &b);

	godot::Callable factory_;
	std::vector<Type> types_;
	std::map<std::pair<uint64_t, uint64_t>, int> type_of_;
	std::vector<Entry> entries_;
	std::unordered_map<uint64_t, size_t> index_of_; // unit instance id -> entries_ index
	std::vector<Corpse> corpses_;
	std::vector<Pickable> pickables_;
	godot::PackedFloat32Array upload_;
	float lod_distance_ = 20.0f;
	bool cast_shadows_ = true;
	bool drawing_ = true;
	uint32_t seed_ = 0x9e3779b9u;
	int drawn_near_ = 0;
	int drawn_far_ = 0;
	int drawn_shadow_ = 0;
};
