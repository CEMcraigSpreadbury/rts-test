#include "sprite_batcher.h"

#include <cstring>

#include <godot_cpp/classes/atlas_texture.hpp>
#include <godot_cpp/classes/sprite_frames.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace {
// Per instance: 12 transform + 4 colour + 4 custom.
constexpr int kStride = 20;

float pack_team(const Color &c) {
	const int r = int(c.r * 255.0f + 0.5f), g = int(c.g * 255.0f + 0.5f), b = int(c.b * 255.0f + 0.5f);
	return float((r << 16) | (g << 8) | b);
}
} // namespace

void SpriteBatcher::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_material_factory", "factory"), &SpriteBatcher::set_material_factory);
	ClassDB::bind_method(D_METHOD("add_sprite", "sprite", "team"), &SpriteBatcher::add_sprite);
	ClassDB::bind_method(D_METHOD("remove_sprite", "sprite"), &SpriteBatcher::remove_sprite);
	ClassDB::bind_method(D_METHOD("set_team_color", "sprite", "team"), &SpriteBatcher::set_team_color);
	ClassDB::bind_method(D_METHOD("get_sprite_count"), &SpriteBatcher::get_sprite_count);
	ClassDB::bind_method(D_METHOD("get_batch_count"), &SpriteBatcher::get_batch_count);
	ClassDB::bind_method(D_METHOD("set_drawing", "drawing"), &SpriteBatcher::set_drawing);
	ClassDB::bind_method(D_METHOD("is_drawing"), &SpriteBatcher::is_drawing);
	ClassDB::bind_method(D_METHOD("pick", "from", "dir", "right", "up"), &SpriteBatcher::pick);
}

SpriteBatcher::SpriteBatcher() {
	quad_.instantiate();
	quad_->set_size(Vector2(1, 1));
	set_process(true);
}

void SpriteBatcher::set_material_factory(const Callable &factory) {
	factory_ = factory;
}

void SpriteBatcher::add_sprite(AnimatedSprite3D *sprite, const Color &team) {
	if (sprite == nullptr) return;
	const uint64_t key = sprite->get_instance_id();
	if (index_of_.count(key)) {
		set_team_color(sprite, team);
		return;
	}
	index_of_[key] = sprites_.size();
	sprites_.push_back({ ObjectID(key), pack_team(team) });
	// Still animates (clips, signals and all); just never drawn itself.
	if (drawing_) sprite->set_visible(false);
}

void SpriteBatcher::remove_sprite(AnimatedSprite3D *sprite) {
	if (sprite == nullptr) return;
	const auto it = index_of_.find(sprite->get_instance_id());
	if (it == index_of_.end()) return;
	const size_t i = it->second;
	index_of_.erase(it);
	if (i + 1 != sprites_.size()) {
		sprites_[i] = sprites_.back();
		index_of_[uint64_t(sprites_[i].id)] = i;
	}
	sprites_.pop_back();
}

void SpriteBatcher::set_team_color(AnimatedSprite3D *sprite, const Color &team) {
	if (sprite == nullptr) return;
	const auto it = index_of_.find(sprite->get_instance_id());
	if (it != index_of_.end()) sprites_[it->second].team_packed = pack_team(team);
}

void SpriteBatcher::set_drawing(bool drawing) {
	drawing_ = drawing;
	if (!drawing_) {
		for (auto &kv : batches_) kv.second.mesh->set_visible_instance_count(0);
	}
	for (const Entry &e : sprites_) {
		AnimatedSprite3D *sprite = Object::cast_to<AnimatedSprite3D>(ObjectDB::get_instance(e.id));
		if (sprite != nullptr) sprite->set_visible(!drawing_);
	}
}

// Picking against the drawn quad, narrowed to roughly the figure: a cell is
// mostly empty space around the unit standing in its middle.
namespace {
constexpr float kPickWidth = 0.3f;  // of the cell's width, each side of centre
constexpr float kPickHeight = 0.45f; // of the cell's height, above and below
} // namespace

Dictionary SpriteBatcher::pick(const Vector3 &from, const Vector3 &dir, const Vector3 &right, const Vector3 &up) const {
	Dictionary hit;
	// The sprites face the camera, so each lies in a plane square to its back axis.
	const Vector3 normal = right.cross(up).normalized();
	const float facing = dir.dot(normal);
	if (Math::abs(facing) < 1e-4f) return hit;
	float best = 1e30f;
	const Pickable *found = nullptr;
	for (const Pickable &p : pickables_) {
		const float t = (p.centre - from).dot(normal) / facing;
		if (t <= 0.0f || t >= best) continue;
		const Vector3 local = from + dir * t - p.centre;
		if (Math::abs(local.dot(right)) > p.half_w || Math::abs(local.dot(up)) > p.half_h) continue;
		best = t;
		found = &p;
	}
	if (found == nullptr) return hit;
	Object *unit = ObjectDB::get_instance(found->unit);
	if (unit == nullptr) return hit;
	hit["collider"] = unit;
	hit["position"] = from + dir * best;
	hit["distance"] = best;
	return hit;
}

SpriteBatcher::Batch &SpriteBatcher::batch_for(const Ref<Texture2D> &sheet, const Vector2 &cell_uv) {
	const uint64_t key = sheet->get_instance_id();
	auto it = batches_.find(key);
	if (it != batches_.end()) return it->second;
	Batch &b = batches_[key];
	b.mesh.instantiate();
	b.mesh->set_transform_format(MultiMesh::TRANSFORM_3D);
	b.mesh->set_use_colors(true);
	b.mesh->set_use_custom_data(true);
	b.mesh->set_mesh(quad_);
	b.node = memnew(MultiMeshInstance3D);
	b.node->set_multimesh(b.mesh);
	// Billboarded in the shader, so culling by instance bounds would be
	// wrong; the whole map is one box.
	b.node->set_custom_aabb(AABB(Vector3(-2048, -256, -2048), Vector3(4096, 512, 4096)));
	b.node->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_ON);
	if (factory_.is_valid()) {
		Ref<Material> material = factory_.call(sheet, cell_uv);
		if (material.is_valid()) b.node->set_material_override(material);
	}
	add_child(b.node);
	return b;
}

void SpriteBatcher::_process(double delta) {
	(void)delta;
	for (auto &kv : batches_) kv.second.count = 0;
	pickables_.clear();

	for (size_t i = 0; i < sprites_.size();) {
		AnimatedSprite3D *sprite = Object::cast_to<AnimatedSprite3D>(ObjectDB::get_instance(sprites_[i].id));
		if (sprite == nullptr) {
			// Freed without being removed: drop it.
			index_of_.erase(uint64_t(sprites_[i].id));
			if (i + 1 != sprites_.size()) {
				sprites_[i] = sprites_.back();
				index_of_[uint64_t(sprites_[i].id)] = i;
			}
			sprites_.pop_back();
			continue;
		}
		const Entry entry = sprites_[i];
		++i;
		// The sprite itself is hidden; its unit's visibility (fog of war,
		// off-screen culling by the unit) is what counts — past any sprite it
		// hangs off (a siege crew rides on its machine's sprite).
		Node *up = sprite->get_parent();
		while (up != nullptr && Object::cast_to<AnimatedSprite3D>(up) != nullptr) up = up->get_parent();
		Node3D *owner = Object::cast_to<Node3D>(up);
		if (owner != nullptr && !owner->is_visible_in_tree()) continue;
		Ref<SpriteFrames> frames = sprite->get_sprite_frames();
		if (frames.is_null()) continue;
		const StringName anim = sprite->get_animation();
		if (!frames->has_animation(anim)) continue;
		Ref<AtlasTexture> atlas = frames->get_frame_texture(anim, sprite->get_frame());
		if (atlas.is_null()) continue;
		Ref<Texture2D> sheet = atlas->get_atlas();
		if (sheet.is_null()) continue;
		const Rect2 region = atlas->get_region();
		const Vector2 sheet_size = sheet->get_size();
		if (region.size.x <= 0.0f || region.size.y <= 0.0f || sheet_size.x <= 0.0f) continue;

		const Transform3D xf = sprite->get_global_transform();
		const float px = sprite->get_pixel_size();
		const float sx = xf.basis.get_column(0).length() * region.size.x * px;
		const float sy = xf.basis.get_column(1).length() * region.size.y * px;
		const Vector3 o = xf.origin;
		// Corpses lose their overlay (no silhouette, no night lift), and can't
		// be picked.
		const bool corpse = sprite->get_material_overlay().is_null();
		if (!corpse && owner != nullptr) {
			pickables_.push_back({ ObjectID(owner->get_instance_id()), o, sx * kPickWidth, sy * kPickHeight });
		}
		if (!drawing_) continue;

		Batch &b = batch_for(sheet, Vector2(region.size.x / sheet_size.x, region.size.y / sheet_size.y));
		const size_t at = size_t(b.count) * kStride;
		if (b.data.size() < at + kStride) b.data.resize(std::max(b.data.size() * 2, at + kStride));
		float *d = b.data.data() + at;

		// Row-major basis and origin, as MultiMesh buffers want them.
		d[0] = sx; d[1] = 0.0f; d[2] = 0.0f; d[3] = o.x;
		d[4] = 0.0f; d[5] = sy; d[6] = 0.0f; d[7] = o.y;
		d[8] = 0.0f; d[9] = 0.0f; d[10] = 1.0f; d[11] = o.z;
		const Color m = sprite->get_modulate();
		d[12] = m.r; d[13] = m.g; d[14] = m.b; d[15] = m.a;
		d[16] = region.position.x / region.size.x;
		d[17] = region.position.y / region.size.y;
		d[18] = sprite->is_flipped_h() ? 1.0f : 0.0f;
		d[19] = corpse ? -1.0f : entry.team_packed;
		++b.count;
	}

	if (!drawing_) return;
	for (auto &kv : batches_) {
		Batch &b = kv.second;
		// Resizing a MultiMesh reallocates it, and what is drawn changes all the
		// time (units come into and out of sight), so capacity only ever grows,
		// doubling, and the drawn count is set separately.
		int capacity = b.mesh->get_instance_count();
		if (capacity < b.count) {
			capacity = std::max(b.count, std::max(64, capacity * 2));
			b.mesh->set_instance_count(capacity);
		}
		b.mesh->set_visible_instance_count(b.count);
		if (b.count == 0) continue;
		upload_.resize(int64_t(capacity) * kStride);
		float *dst = upload_.ptrw();
		std::memcpy(dst, b.data.data(), sizeof(float) * size_t(b.count) * kStride);
		std::memset(dst + size_t(b.count) * kStride, 0, sizeof(float) * size_t(capacity - b.count) * kStride);
		b.mesh->set_buffer(upload_);
	}
}
