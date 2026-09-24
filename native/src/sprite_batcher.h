// SpriteBatcher - draws every unit sprite of one sheet as a single MultiMesh.
//
// A unit keeps its AnimatedSprite3D for everything the game already does with
// it (clips, the attack-finished signal, tints and hit flashes, squash and
// lunge, stun pauses) but stops drawing it. Each frame this reads the state of
// every registered sprite and writes it, per sheet, into one instance buffer:
// the whole army costs a handful of draws instead of several per unit.

#pragma once

#include <godot_cpp/classes/animated_sprite3d.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/quad_mesh.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <unordered_map>
#include <vector>

class SpriteBatcher : public godot::Node3D {
	GDCLASS(SpriteBatcher, godot::Node3D)

protected:
	static void _bind_methods();

public:
	SpriteBatcher();

	// Called with (sheet: Texture2D, cell_uv: Vector2) the first time a sheet
	// is seen; returns the Material (with its next_pass chain) to draw it with.
	void set_material_factory(const godot::Callable &factory);
	// Draws `sprite` from now on (and hides it). `team` colours its silhouette.
	void add_sprite(godot::AnimatedSprite3D *sprite, const godot::Color &team);
	void remove_sprite(godot::AnimatedSprite3D *sprite);
	void set_team_color(godot::AnimatedSprite3D *sprite, const godot::Color &team);
	int get_sprite_count() const { return int(sprites_.size()); }
	// Off: sprites are still tracked (and pickable) but draw themselves.
	void set_drawing(bool drawing);
	bool is_drawing() const { return drawing_; }
	// The living unit whose sprite, as last drawn, the ray (from the camera,
	// `dir` normalised) meets first: {"collider", "position", "distance"}, or
	// empty. `right`/`up` are the camera's axes, which the sprites face.
	godot::Dictionary pick(const godot::Vector3 &from, const godot::Vector3 &dir, const godot::Vector3 &right, const godot::Vector3 &up) const;
	int get_batch_count() const { return int(batches_.size()); }

	void _process(double delta) override;

private:
	struct Entry {
		godot::ObjectID id;
		float team_packed = 0.0f;
	};
	// A sprite as last drawn, for pick(): its unit, centre and half size.
	struct Pickable {
		godot::ObjectID unit;
		godot::Vector3 centre;
		float half_w = 0.0f;
		float half_h = 0.0f;
	};
	struct Batch {
		godot::MultiMeshInstance3D *node = nullptr;
		godot::Ref<godot::MultiMesh> mesh;
		std::vector<float> data;
		int count = 0;
	};
	Batch &batch_for(const godot::Ref<godot::Texture2D> &sheet, const godot::Vector2 &cell_uv);

	godot::Callable factory_;
	godot::Ref<godot::QuadMesh> quad_;
	std::vector<Entry> sprites_;
	std::unordered_map<uint64_t, size_t> index_of_; // sprite instance id -> sprites_ index
	std::unordered_map<uint64_t, Batch> batches_;   // sheet instance id -> batch
	godot::PackedFloat32Array upload_;
	std::vector<Pickable> pickables_;
	bool drawing_ = true;
};
