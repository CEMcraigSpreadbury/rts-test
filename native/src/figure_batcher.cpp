#include "figure_batcher.h"

#include <algorithm>
#include <cmath>
#include <cstring>

#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/sprite_frames.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/plane.hpp>
#include <godot_cpp/variant/typed_array.hpp>

using namespace godot;

namespace {
// Per instance: 12 transform + 4 custom. INSTANCE_CUSTOM is
//   .x team colour packed as 0xRRGGBB
//   .y the sprite's modulate up to 1 (status tints), packed the same way
//   .z hit flash, 0..1 (the part of the modulate over 1)
//   .w how much of it shows, 0..1 (a corpse fades); negative for a dying
//      figure or a corpse, which get no see-through silhouette
// No per-instance COLOR: a MultiMesh's colour is multiplied into the mesh's
// own vertex colours, which carry the baked occlusion and shine.
constexpr int kStride = 16;

constexpr float kPi = 3.14159265358979f;
// Walking: hops a second (each a half turn of hop_phase), how high, the
// side-to-side roll and forward lean that go with them, and the squash on
// landing. At most this much of a hop's length later than the first unit of
// a block to set off, so a block hops close to, but not in, unison.
constexpr float kHopsPerSecond = 3.3f;
constexpr float kHopHeight = 0.075f;
constexpr float kWaddle = 0.10f;
constexpr float kWalkLean = 0.09f;
constexpr float kLandSquash = 0.08f;
constexpr float kHopStretch = 0.045f;
constexpr float kMaxStagger = 0.55f;
// Standing: a slow sway and breath, and now and then a tiny hop.
constexpr float kIdleSway = 0.022f;
constexpr float kIdleBreath = 0.012f;
constexpr float kIdleHopHeight = 0.035f;
constexpr float kIdleHopTime = 0.3f;
constexpr float kIdleHopEveryMin = 5.0f;
constexpr float kIdleHopEveryMax = 12.0f;
// Radians of lean per metre the sprite has been pushed (lunge, recoil).
constexpr float kShoveLean = 1.4f;
// Death: how long it takes to go over, how far (radians), and how far it is
// lifted as it goes so it lies on the ground rather than in it. A corpse
// holds, then sinks this far as it fades.
constexpr float kToppleTime = 0.45f;
constexpr float kToppleAngle = 1.45f;
constexpr float kToppleLift = 0.13f;
constexpr float kCorpseHold = 2.5f;
constexpr float kCorpseFade = 2.0f;
constexpr float kCorpseSink = 0.45f;
// Picking: how near a figure's upright axis a click must pass to find it,
// at least, and at most (a horse is longer than it is wide). A figure bigger
// than a horse (a beast, a monster) may reach kPickRadiusBig of its larger
// footprint side instead, up to kPickRadiusHuge.
constexpr float kPickRadius = 0.3f;
constexpr float kPickRadiusMax = 0.5f;
constexpr float kPickRadiusBig = 0.3f;
constexpr float kPickRadiusHuge = 2.5f;
// Galloping: strides a second at full speed, how far it rocks nose to tail,
// how high it bobs. Striking: how far it rears, then lunges.
constexpr float kGallopsPerSecond = 2.4f;
constexpr float kGallopRock = 0.11f;
constexpr float kGallopBob = 0.05f;
constexpr float kMountRear = 0.22f;
constexpr float kMountLunge = 0.16f;
// Stomping (monsters): stomps a second at full speed (slower when slower),
// the share of each spent in the air (the rest is the pause on the ground),
// how high it lifts, how far it tips nose up then down over the air, how it
// stretches in the air and squashes as it lands.
constexpr float kStompsPerSecond = 1.1f;
constexpr float kStompAir = 0.55f;
constexpr float kStompHeight = 0.22f;
constexpr float kStompRear = 0.07f;
constexpr float kStompStretch = 0.03f;
constexpr float kStompSquash = 0.09f;
// Rolling (siege engines): rumbles a second at full speed, the bob, nose
// rock and side sway on the wheels; the shot's kick back (metres, and nose
// up) and how long it takes to settle as a share of what is left of the
// clip; how far it tips over when it dies and how far it is lifted as it
// goes (it is wide).
constexpr float kRollRumblesPerSecond = 2.6f;
constexpr float kRollBob = 0.018f;
constexpr float kRollRock = 0.014f;
constexpr float kRollSway = 0.012f;
constexpr float kRollRecoil = 0.30f;
constexpr float kRollRecoilPitch = 0.07f;
constexpr float kRollToppleAngle = 1.2f;
constexpr float kRollToppleLift = 0.55f;
// Frustum test radii round a figure's middle: drawn, and casting a shadow
// into view.
// At least; a figure whose bounds reach further from its middle gets that
// (plus its height twice over for a long evening shadow).
constexpr float kViewRadius = 1.0f;
constexpr float kShadowRadius = 5.0f;
// Figures taller than this keep their near mesh proportionally further out.
constexpr float kLodHeight = 2.0f;
// Unit.SHOT_RELEASE_LEAD_FRAMES: the shot leaves this many frames before an
// attack clip ends.
constexpr float kReleaseLeadFrames = 2.0f;

float pack_rgb(const Color &c) {
	const int r = int(Math::clamp(c.r, 0.0f, 1.0f) * 255.0f + 0.5f);
	const int g = int(Math::clamp(c.g, 0.0f, 1.0f) * 255.0f + 0.5f);
	const int b = int(Math::clamp(c.b, 0.0f, 1.0f) * 255.0f + 0.5f);
	return float((r << 16) | (g << 8) | b);
}

float smooth(float a, float b, float x) {
	const float t = Math::clamp((x - a) / (b - a), 0.0f, 1.0f);
	return t * t * (3.0f - 2.0f * t);
}

float move_toward(float from, float to, float step) {
	return from < to ? std::min(from + step, to) : std::max(from - step, to);
}

uint32_t next_random(uint32_t &state) {
	state = state * 1664525u + 1013904223u;
	return state;
}

float random01(uint32_t &state) {
	return float(next_random(state) >> 8) / float(1u << 24);
}
} // namespace

void FigureBatcher::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_material_factory", "factory"), &FigureBatcher::set_material_factory);
	ClassDB::bind_method(D_METHOD("add_figure", "unit", "sprite", "mesh", "lod1", "palette", "team", "rest_position",
								 "rest_scale", "walk_speed"),
			&FigureBatcher::add_figure);
	ClassDB::bind_method(D_METHOD("remove_figure", "unit", "leave_corpse"), &FigureBatcher::remove_figure, DEFVAL(true));
	ClassDB::bind_method(D_METHOD("set_figure_motion", "unit", "motion"), &FigureBatcher::set_figure_motion);
	ClassDB::bind_method(D_METHOD("set_figure_variant", "unit", "role", "mesh", "lod1"), &FigureBatcher::set_figure_variant);
	ClassDB::bind_method(D_METHOD("set_team_color", "unit", "team"), &FigureBatcher::set_team_color);
	ClassDB::bind_method(D_METHOD("has_figure", "unit"), &FigureBatcher::has_figure);
	ClassDB::bind_method(D_METHOD("get_figure_count"), &FigureBatcher::get_figure_count);
	ClassDB::bind_method(D_METHOD("get_corpse_count"), &FigureBatcher::get_corpse_count);
	ClassDB::bind_method(D_METHOD("set_lod_distance", "distance"), &FigureBatcher::set_lod_distance);
	ClassDB::bind_method(D_METHOD("get_lod_distance"), &FigureBatcher::get_lod_distance);
	ClassDB::bind_method(D_METHOD("set_cast_shadows", "cast"), &FigureBatcher::set_cast_shadows);
	ClassDB::bind_method(D_METHOD("get_cast_shadows"), &FigureBatcher::get_cast_shadows);
	ClassDB::bind_method(D_METHOD("set_drawing", "drawing"), &FigureBatcher::set_drawing);
	ClassDB::bind_method(D_METHOD("is_drawing"), &FigureBatcher::is_drawing);
	ClassDB::bind_method(D_METHOD("pick", "from", "dir"), &FigureBatcher::pick);
	ClassDB::bind_method(D_METHOD("get_drawn_counts"), &FigureBatcher::get_drawn_counts);
	// A stomping figure in view landed (the nearest to the camera, at most
	// one a frame).
	ADD_SIGNAL(MethodInfo("stomped", PropertyInfo(Variant::VECTOR3, "position")));
}

FigureBatcher::FigureBatcher() {
	set_process(true);
}

void FigureBatcher::set_material_factory(const Callable &factory) {
	factory_ = factory;
}

void FigureBatcher::make_batch(Batch &b, const Ref<Mesh> &mesh, const Ref<Material> &material, int shadows) {
	b.mesh.instantiate();
	b.mesh->set_transform_format(MultiMesh::TRANSFORM_3D);
	b.mesh->set_use_colors(false);
	b.mesh->set_use_custom_data(true);
	b.mesh->set_mesh(mesh);
	b.node = memnew(MultiMeshInstance3D);
	b.node->set_multimesh(b.mesh);
	// Instances are culled here, against the camera, so the node's own bounds
	// are the whole map.
	b.node->set_custom_aabb(AABB(Vector3(-2048, -256, -2048), Vector3(4096, 512, 4096)));
	b.node->set_cast_shadows_setting(GeometryInstance3D::ShadowCastingSetting(shadows));
	if (material.is_valid()) b.node->set_material_override(material);
	add_child(b.node);
}

int FigureBatcher::type_for(const Ref<Mesh> &mesh, const Ref<Mesh> &lod1, const Ref<Texture2D> &palette) {
	const std::pair<uint64_t, uint64_t> key(mesh->get_instance_id(), palette.is_valid() ? palette->get_instance_id() : 0);
	const auto it = type_of_.find(key);
	if (it != type_of_.end()) return it->second;
	types_.emplace_back();
	Type &t = types_.back();
	t.mesh = mesh;
	t.lod1 = lod1.is_valid() ? lod1 : mesh;
	t.palette = palette;
	t.height = mesh->get_aabb().get_end().y;
	const Vector3 extent = mesh->get_aabb().get_size();
	const float footprint = std::max(extent.x, extent.z);
	const float pick_max = Math::clamp(kPickRadiusBig * footprint, kPickRadiusMax, kPickRadiusHuge);
	t.pick_radius = Math::clamp(0.35f * footprint, kPickRadius, pick_max);
	// Middle is drawn at half the height over the unit's origin (see
	// _process); the furthest corner of the bounds from there.
	const AABB box = mesh->get_aabb();
	const Vector3 middle(0.0f, t.height * 0.5f, 0.0f);
	float reach = 0.0f;
	for (int i = 0; i < 8; ++i) reach = std::max(reach, (box.get_endpoint(i) - middle).length());
	t.view_radius = std::max(kViewRadius, reach);
	t.shadow_radius = std::max(kShadowRadius, reach + 2.0f * t.height);
	t.lod_scale = std::max(1.0f, t.height / kLodHeight);
	Ref<Material> material;
	if (factory_.is_valid()) material = factory_.call(mesh, palette);
	make_batch(t.near_batch, t.mesh, material, GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
	make_batch(t.far_batch, t.lod1, material, GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
	make_batch(t.shadow_batch, t.lod1, material, GeometryInstance3D::SHADOW_CASTING_SETTING_SHADOWS_ONLY);
	const int index = int(types_.size()) - 1;
	type_of_[key] = index;
	return index;
}

void FigureBatcher::add_figure(Node3D *unit, AnimatedSprite3D *sprite, const Ref<Mesh> &mesh, const Ref<Mesh> &lod1,
		const Ref<Texture2D> &palette, const Color &team, const Vector3 &rest_position, const Vector3 &rest_scale,
		float walk_speed) {
	if (unit == nullptr || sprite == nullptr || mesh.is_null()) return;
	const uint64_t key = unit->get_instance_id();
	if (index_of_.count(key)) {
		set_team_color(unit, team);
		return;
	}
	Entry e;
	e.unit = ObjectID(key);
	e.sprite = ObjectID(sprite->get_instance_id());
	e.type = type_for(mesh, lod1, palette);
	e.base_type = e.type;
	e.team_packed = pack_rgb(team);
	e.rest_position = rest_position;
	e.rest_scale = Vector3(std::max(rest_scale.x, 1e-4f), std::max(rest_scale.y, 1e-4f), std::max(rest_scale.z, 1e-4f));
	e.walk_speed = std::max(walk_speed, 0.1f);
	e.phase = random01(seed_);
	e.clock = random01(seed_) * 10.0f;
	e.next_idle_hop = e.clock + kIdleHopEveryMin + random01(seed_) * (kIdleHopEveryMax - kIdleHopEveryMin);
	index_of_[key] = entries_.size();
	entries_.push_back(e);
}

void FigureBatcher::erase_at(size_t i, bool leave_corpse) {
	Entry &e = entries_[i];
	if (leave_corpse && e.dying) {
		Corpse c;
		c.type = e.type;
		c.world = e.last_world;
		c.team_packed = e.team_packed;
		c.shown = e.was_drawn;
		corpses_.push_back(c);
	}
	index_of_.erase(uint64_t(e.unit));
	if (i + 1 != entries_.size()) {
		entries_[i] = entries_.back();
		index_of_[uint64_t(entries_[i].unit)] = i;
	}
	entries_.pop_back();
}

void FigureBatcher::remove_figure(Node3D *unit, bool leave_corpse) {
	if (unit == nullptr) return;
	const auto it = index_of_.find(unit->get_instance_id());
	if (it == index_of_.end()) return;
	erase_at(it->second, leave_corpse);
}

void FigureBatcher::set_figure_motion(Node3D *unit, int motion) {
	if (unit == nullptr) return;
	const auto it = index_of_.find(unit->get_instance_id());
	if (it != index_of_.end()) entries_[it->second].motion = motion;
}

void FigureBatcher::set_figure_variant(Node3D *unit, const StringName &role, const Ref<Mesh> &mesh,
		const Ref<Mesh> &lod1) {
	if (unit == nullptr || mesh.is_null()) return;
	const auto it = index_of_.find(unit->get_instance_id());
	if (it == index_of_.end()) return;
	Entry &e = entries_[it->second];
	const int type = type_for(mesh, lod1, types_[size_t(e.base_type)].palette);
	for (auto &variant : e.variants) {
		if (variant.first == role) {
			variant.second = type;
			return;
		}
	}
	e.variants.emplace_back(role, type);
	// The clip may already be the role's: look again on the next pose.
	e.anim = StringName();
}

void FigureBatcher::set_team_color(Node3D *unit, const Color &team) {
	if (unit == nullptr) return;
	const auto it = index_of_.find(unit->get_instance_id());
	if (it != index_of_.end()) entries_[it->second].team_packed = pack_rgb(team);
}

bool FigureBatcher::has_figure(Node3D *unit) const {
	return unit != nullptr && index_of_.count(unit->get_instance_id()) > 0;
}

void FigureBatcher::set_cast_shadows(bool cast) {
	cast_shadows_ = cast;
}

void FigureBatcher::set_drawing(bool drawing) {
	drawing_ = drawing;
	if (!drawing_) {
		for (Type &t : types_) {
			t.near_batch.mesh->set_visible_instance_count(0);
			t.far_batch.mesh->set_visible_instance_count(0);
			t.shadow_batch.mesh->set_visible_instance_count(0);
		}
	}
}

PackedInt32Array FigureBatcher::get_drawn_counts() const {
	PackedInt32Array out;
	out.push_back(drawn_near_);
	out.push_back(drawn_far_);
	out.push_back(drawn_shadow_);
	return out;
}

FigureBatcher::Clip FigureBatcher::clip_of(const StringName &anim) {
	// Work roles prefix their clips ("wood_walk"), so only the ending counts.
	const String name = anim;
	if (name.ends_with("walk")) return CLIP_WALK;
	if (name.ends_with("idle")) return CLIP_IDLE;
	if (name.ends_with("attack")) return CLIP_ATTACK;
	if (name.ends_with("gather")) return CLIP_GATHER;
	if (name.ends_with("cast")) return CLIP_CAST;
	if (name.ends_with("death")) return CLIP_DEATH;
	return CLIP_OTHER;
}

// The figure's transform in its unit's space, from the sprite's state and the
// clip playing, composed onto the unit's own (interpolated) transform.
Transform3D FigureBatcher::pose(Entry &e, AnimatedSprite3D *sprite, float dt) {
	const StringName anim = sprite->get_animation();
	if (anim != e.anim) {
		e.anim = anim;
		e.clip = clip_of(anim);
		// A work role's clips are "<role>_<clip>": its variant, if it has one.
		e.type = e.base_type;
		if (!e.variants.empty()) {
			const String name = anim;
			const int split = name.find("_");
			if (split > 0) {
				const StringName role = name.substr(0, split);
				for (const auto &variant : e.variants) {
					if (variant.first == role) e.type = variant.second;
				}
			}
		}
	}
	// Hitstop freezes the sprite's clip; the figure freezes with it.
	const float run = sprite->get_speed_scale() > 0.0f ? 1.0f : 0.0f;
	const float step = dt * run;
	e.clock += step;

	float t = 0.0f;
	// Where in the clip a shot is loosed (see kReleaseLeadFrames).
	float release = 0.66f;
	Ref<SpriteFrames> frames = sprite->get_sprite_frames();
	if (frames.is_valid() && frames->has_animation(anim)) {
		const int count = std::max(int(frames->get_frame_count(anim)), 1);
		t = Math::clamp((float(sprite->get_frame()) + sprite->get_frame_progress()) / float(count), 0.0f, 1.0f);
		release = std::max(float(count) - kReleaseLeadFrames, 1.0f) / float(count);
	}

	// Dying: the death clip, or (as SpriteBatcher tells a corpse) the sprite
	// losing the overlay it had.
	const bool overlay = sprite->get_material_overlay().is_valid();
	e.had_overlay = e.had_overlay || overlay;
	if (e.clip == CLIP_DEATH || (e.had_overlay && !overlay)) e.dying = true;

	Vector3 offset = sprite->get_position() - e.rest_position;
	// An archer's swing still lunges its sprite forward (Unit.play_attack_lunge);
	// a figure drawing a bow keeps its feet instead.
	const bool drawing_bow = e.motion == MOTION_BOW && e.clip == CLIP_ATTACK;
	if (drawing_bow) offset.z *= 0.2f;
	// A siege engine keeps its wheels on the ground (it kicks back by itself).
	if (e.motion == MOTION_ROLL && e.clip == CLIP_ATTACK) offset.z = 0.0f;
	const Vector3 sprite_scale = sprite->get_scale();
	Vector3 squash(sprite_scale.x / e.rest_scale.x, sprite_scale.y / e.rest_scale.y, sprite_scale.z / e.rest_scale.z);

	float hop = 0.0f;
	float pitch = 0.0f;
	float roll = 0.0f;
	float twist = 0.0f;
	float stretch = 1.0f;

	// Walking: hop, waddle and lean. A hop under way when the walk stops
	// still lands.
	const bool walking = e.clip == CLIP_WALK && !e.dying;
	e.walk_amount = move_toward(e.walk_amount, walking ? 1.0f : 0.0f, dt * 6.0f);
	if (walking && e.hop_phase == 0.0f) {
		e.hop_phase = -e.phase * kMaxStagger * kPi;
	}
	const bool stomper = e.motion == MOTION_STOMP;
	const bool roller = e.motion == MOTION_ROLL;
	const bool mounted = e.motion == MOTION_MOUNTED || stomper;
	e.landed = false;
	e.hold = 0.0f;
	if (stomper && (walking || e.stomp > 0.0f)) {
		const float pace = kStompsPerSecond * Math::clamp(e.speed / e.walk_speed, 0.45f, 1.15f);
		// From standing it lifts straight away.
		if (e.stomp <= 0.0f) e.stomp = 1e-4f;
		const float before = e.stomp;
		e.stomp += step * pace;
		if (!e.dying && std::floor(before - kStompAir) != std::floor(e.stomp - kStompAir)) e.landed = true;
		const float u = e.stomp - std::floor(e.stomp);
		// Stopped: finish the stomp in the air and the squash after it.
		if (!walking && u >= kStompAir + (1.0f - kStompAir) * 0.5f) {
			e.stomp = 0.0f;
		} else {
			if (u < kStompAir) {
				const float a = u / kStompAir;
				const float s = std::sin(kPi * a);
				hop += kStompHeight * s;
				pitch += -kStompRear * std::sin(2.0f * kPi * a);
				stretch *= 1.0f + kStompStretch * s;
			} else {
				const float g = (u - kStompAir) / (1.0f - kStompAir);
				stretch *= 1.0f - kStompSquash * (1.0f - smooth(0.0f, 0.45f, g)) - 0.03f * smooth(0.7f, 1.0f, g);
				pitch += 0.04f * (1.0f - smooth(0.0f, 0.5f, g));
			}
			// The unit moves on steadily; the figure covers a stride in the
			// air and holds still on the ground. Where it should be, less
			// where the unit is, centred over the cycle, in seconds of its
			// velocity (see _process).
			const float travelled = u < kStompAir ? smooth(0.0f, 1.0f, u / kStompAir) : 1.0f;
			e.hold = (travelled - u - 0.5f * (1.0f - kStompAir)) / pace * e.walk_amount;
		}
	}
	if (roller) {
		// On its wheels: a quick small rumble while it moves, no hop.
		const float amp = Math::clamp(e.speed / e.walk_speed, 0.3f, 1.1f) * e.walk_amount;
		const float a = (e.clock * kRollRumblesPerSecond + e.phase) * 2.0f * kPi;
		hop += kRollBob * amp * (0.5f + 0.5f * std::sin(a * 2.0f));
		pitch += kRollRock * amp * std::sin(a + 0.7f);
		roll += kRollSway * amp * std::sin(a * 0.5f);
		e.hop_phase = 0.0f;
	}
	if (!stomper && !roller && (walking || e.hop_phase > 0.0f || e.hop_phase < 0.0f)) {
		const float before = e.hop_phase;
		// A gallop's stride quickens with the horse's pace.
		const float pace = mounted ? kGallopsPerSecond * Math::clamp(e.speed / e.walk_speed, 0.45f, 1.15f)
				: kHopsPerSecond;
		e.hop_phase += step * pace * kPi;
		if (!walking) {
			if (before <= 0.0f || std::floor(before / kPi) != std::floor(e.hop_phase / kPi)) e.hop_phase = 0.0f;
		}
	}
	if (e.hop_phase > 0.0f && mounted) {
		// A rocking-horse gallop: nose down and up once a stride, the body
		// bobbing twice, a slight roll.
		const float amp = Math::clamp(e.speed / e.walk_speed, 0.35f, 1.1f);
		const float s = std::sin(e.hop_phase);
		pitch += kGallopRock * amp * std::sin(e.hop_phase * 2.0f) * e.walk_amount;
		hop += kGallopBob * amp * std::fabs(s);
		roll += 0.03f * s * e.walk_amount;
	} else if (e.hop_phase > 0.0f) {
		const float s = std::sin(e.hop_phase);
		const float lift = std::fabs(s);
		const float amp = Math::clamp(e.speed / e.walk_speed, 0.35f, 1.1f);
		hop += kHopHeight * amp * lift;
		roll += s * kWaddle * e.walk_amount;
		const float land = std::pow(1.0f - lift, 6.0f);
		stretch *= 1.0f + (kHopStretch * lift - kLandSquash * land) * amp;
	}
	if (!roller) pitch += (mounted ? 0.03f : kWalkLean) * e.walk_amount;

	// Standing: sway, breathe, and now and then a tiny hop.
	const float still = 1.0f - e.walk_amount;
	if (!e.dying && !roller && (e.clip == CLIP_IDLE || e.clip == CLIP_OTHER)) {
		roll += kIdleSway * std::sin(e.clock * 1.6f + e.phase * 6.283f) * still;
		stretch *= 1.0f + kIdleBreath * std::sin(e.clock * 2.2f + e.phase * 4.0f) * still;
		if (e.clock >= e.next_idle_hop && still >= 1.0f) {
			e.idle_hop_age = 0.0f;
			e.next_idle_hop = e.clock + kIdleHopEveryMin + random01(seed_) * (kIdleHopEveryMax - kIdleHopEveryMin);
		}
	}
	if (e.idle_hop_age < kIdleHopTime) {
		e.idle_hop_age += step;
		const float k = std::min(e.idle_hop_age / kIdleHopTime, 1.0f);
		const float s = std::sin(kPi * k);
		hop += kIdleHopHeight * s;
		stretch *= 1.0f + 0.04f * s - 0.06f * std::pow(1.0f - s, 6.0f) * (k > 0.5f ? 1.0f : 0.0f);
	}

	switch (e.clip) {
		case CLIP_ATTACK: {
			if (roller) {
				// Still until the shot leaves, then a sharp kick back, nose
				// up, easing home over the rest of the clip.
				const float after = Math::clamp((t - release) / std::max(1.0f - release, 0.05f), 0.0f, 1.0f);
				const float kick = t < release ? 0.0f
						: smooth(0.0f, 0.12f, after) * (1.0f - smooth(0.12f, 1.0f, after));
				offset.z -= kRollRecoil * kick;
				pitch -= kRollRecoilPitch * kick;
				hop += 0.02f * kick;
				break;
			}
			if (mounted) {
				// Rear up, then lunge forward through the blow.
				const float rear = smooth(0.0f, 0.25f, t) * (1.0f - smooth(0.25f, 0.45f, t));
				const float lunge = smooth(0.25f, 0.45f, t) * (1.0f - smooth(0.5f, 1.0f, t));
				pitch += -kMountRear * rear + kMountLunge * lunge;
				hop += 0.05f * rear;
				break;
			}
			if (e.motion == MOTION_BOW) {
				// Draw: turn the bow shoulder to the target and lean back
				// into the pull, rising a little; loose on the release frame
				// with a small forward kick, then ease back square.
				const float draw = smooth(0.0f, release, t);
				const float after = Math::clamp((t - release) / std::max(1.0f - release, 0.05f), 0.0f, 1.0f);
				const float hold = t < release ? draw : 1.0f - smooth(0.0f, 1.0f, after);
				const float kick = t < release ? 0.0f : std::sin(kPi * std::min(after * 1.6f, 1.0f));
				twist += -0.42f * hold;
				pitch += -0.10f * hold + 0.12f * kick;
				stretch *= 1.0f + 0.035f * hold;
				hop += 0.018f * kick;
				break;
			}
			// Rear back and turn the sword arm away, then lean in and turn
			// through the blow, then settle.
			const float wind = smooth(0.0f, 0.15f, t) * (1.0f - smooth(0.15f, 0.32f, t));
			const float strike = smooth(0.15f, 0.32f, t) * (1.0f - smooth(0.4f, 1.0f, t));
			pitch += -0.16f * wind + 0.30f * strike;
			twist += -0.38f * wind + 0.32f * strike;
			hop += 0.025f * strike;
		} break;
		case CLIP_GATHER: {
			// A rhythmic bob into the work.
			const float pulse = 0.5f - 0.5f * std::cos(2.0f * kPi * t);
			pitch += 0.22f * pulse;
			hop += 0.02f * std::max(0.0f, std::sin(2.0f * kPi * t));
		} break;
		case CLIP_CAST: {
			const float s = std::sin(kPi * t);
			hop += 0.06f * s;
			pitch -= 0.14f * s;
			stretch *= 1.0f + 0.08f * s;
			twist += 0.25f * std::sin(2.0f * kPi * t) * s;
		} break;
		default:
			break;
	}

	// Shoved (lunge, recoil): lean the way it is pushed.
	if (!e.dying && !drawing_bow && !roller) {
		pitch += Math::clamp(offset.z * kShoveLean, -0.3f, 0.4f);
		roll += Math::clamp(-offset.x * kShoveLean, -0.3f, 0.3f);
	}

	Basis basis = Basis(Vector3(0, 1, 0), twist) * Basis::from_euler(Vector3(pitch, 0.0f, roll));
	float lift = 0.0f;
	if (e.dying) {
		e.death_age += dt;
		// Over the way the killing blow threw it, once that is known (the
		// knockback is on the sprite), else backward off its facing.
		const Vector3 flat(offset.x, 0.0f, offset.z);
		if (!e.topple_locked && (flat.length() > 0.03f || e.death_age > 0.15f)) {
			Vector3 away = flat.length() > 0.03f ? flat.normalized() : Vector3(0, 0, -1);
			// A horse goes over on its side, whichever side the blow came from.
			if (mounted || roller) away = Vector3(away.x >= 0.0f ? 1.0f : -1.0f, 0.0f, 0.0f);
			e.topple_axis = Vector3(0, 1, 0).cross(away).normalized();
			e.topple_locked = true;
		}
		const float k = std::min(e.death_age / kToppleTime, 1.0f);
		const float fall = (1.0f - (1.0f - k) * (1.0f - k)) * (roller ? kRollToppleAngle : kToppleAngle);
		basis = Basis(e.topple_axis, fall) * basis;
		lift = std::sin(fall) * (roller ? kRollToppleLift : kToppleLift * (mounted ? 1.8f : 1.0f));
	}
	const float xz = 1.0f / std::sqrt(std::max(stretch, 0.2f));
	basis = basis * Basis::from_scale(Vector3(squash.x * xz, squash.y * stretch, squash.z * xz));
	return Transform3D(basis, offset + Vector3(0.0f, hop + lift, 0.0f));
}

void FigureBatcher::write(Batch &b, const Transform3D &xf, const float custom[4]) {
	const size_t at = size_t(b.count) * kStride;
	if (b.data.size() < at + kStride) b.data.resize(std::max(b.data.size() * 2, at + kStride));
	float *d = b.data.data() + at;
	const Basis &m = xf.basis;
	d[0] = m.rows[0][0]; d[1] = m.rows[0][1]; d[2] = m.rows[0][2]; d[3] = xf.origin.x;
	d[4] = m.rows[1][0]; d[5] = m.rows[1][1]; d[6] = m.rows[1][2]; d[7] = xf.origin.y;
	d[8] = m.rows[2][0]; d[9] = m.rows[2][1]; d[10] = m.rows[2][2]; d[11] = xf.origin.z;
	d[12] = custom[0]; d[13] = custom[1]; d[14] = custom[2]; d[15] = custom[3];
	++b.count;
}

void FigureBatcher::upload(Batch &b) {
	// Capacity only ever grows (doubling) and the drawn count is set apart,
	// as SpriteBatcher does: resizing a MultiMesh reallocates it.
	int capacity = b.mesh->get_instance_count();
	if (capacity < b.count) {
		capacity = std::max(b.count, std::max(64, capacity * 2));
		b.mesh->set_instance_count(capacity);
	}
	b.mesh->set_visible_instance_count(b.count);
	if (b.count == 0) return;
	upload_.resize(int64_t(capacity) * kStride);
	float *dst = upload_.ptrw();
	std::memcpy(dst, b.data.data(), sizeof(float) * size_t(b.count) * kStride);
	std::memset(dst + size_t(b.count) * kStride, 0, sizeof(float) * size_t(capacity - b.count) * kStride);
	b.mesh->set_buffer(upload_);
}

// Figures stand closer together than their outlines are wide on screen: a
// click on a back-rank figure's belt also crosses the front-rank figure's
// helmet. So of the figures the ray passes within kPickRadius of, the one
// whose upright axis it passes closest to is the one meant.
Dictionary FigureBatcher::pick(const Vector3 &from, const Vector3 &dir) const {
	Dictionary hit;
	float best_miss = 1.0f;
	float best_t = 0.0f;
	const Pickable *found = nullptr;
	const float flat = dir.x * dir.x + dir.z * dir.z;
	for (const Pickable &p : pickables_) {
		// Where the ray comes nearest the axis, seen from above...
		const float ox = from.x - p.base.x, oz = from.z - p.base.z;
		float t = flat > 1e-8f ? -(ox * dir.x + oz * dir.z) / flat : 0.0f;
		// ...kept to the figure's height.
		const float y = from.y + dir.y * t - p.base.y;
		if (std::fabs(dir.y) > 1e-6f) {
			if (y > p.height) t = (p.base.y + p.height - from.y) / dir.y;
			else if (y < 0.0f) t = (p.base.y - from.y) / dir.y;
		}
		if (t <= 0.0f) continue;
		const float hx = from.x + dir.x * t - p.base.x, hz = from.z + dir.z * t - p.base.z;
		const float miss = std::sqrt(hx * hx + hz * hz) / p.radius;
		if (miss < best_miss) {
			best_miss = miss;
			best_t = t;
			found = &p;
		}
	}
	if (found == nullptr) return hit;
	Object *unit = ObjectDB::get_instance(found->unit);
	if (unit == nullptr) return hit;
	hit["collider"] = unit;
	hit["position"] = from + dir * best_t;
	hit["distance"] = best_t;
	return hit;
}

void FigureBatcher::_process(double delta) {
	const float dt = float(delta);
	for (Type &t : types_) {
		t.near_batch.count = 0;
		t.far_batch.count = 0;
		t.shadow_batch.count = 0;
	}
	pickables_.clear();
	drawn_near_ = drawn_far_ = drawn_shadow_ = 0;

	Camera3D *camera = nullptr;
	Viewport *viewport = get_viewport();
	if (viewport != nullptr) camera = viewport->get_camera_3d();
	std::vector<Plane> planes;
	Vector3 eye;
	if (camera != nullptr && drawing_) {
		const TypedArray<Plane> frustum = camera->get_frustum();
		for (int64_t i = 0; i < frustum.size(); ++i) planes.push_back(frustum[i]);
		eye = camera->get_global_transform().origin;
	}
	// Godot's frustum planes face out of the frustum.
	auto in_view = [&planes](const Vector3 &p, float radius) {
		for (const Plane &plane : planes) {
			if (plane.distance_to(p) > radius) return false;
		}
		return true;
	};

	float stomp_distance = 1e31f;
	Vector3 stomp_at;
	for (size_t i = 0; i < entries_.size();) {
		Entry &e = entries_[i];
		Node3D *unit = Object::cast_to<Node3D>(ObjectDB::get_instance(e.unit));
		AnimatedSprite3D *sprite = Object::cast_to<AnimatedSprite3D>(ObjectDB::get_instance(e.sprite));
		if (unit == nullptr || sprite == nullptr) {
			// Freed without being removed: a dying one leaves its corpse.
			erase_at(i, true);
			continue;
		}
		++i;
		if (!drawing_) continue;
		const Transform3D unit_xf = unit->get_global_transform_interpolated();
		if (e.has_last_position && dt > 0.0f) {
			const Vector3 moved = unit_xf.origin - e.last_position;
			const float speed = Vector3(moved.x, 0.0f, moved.z).length() / dt;
			e.speed += (speed - e.speed) * std::min(1.0f, dt * 10.0f);
			const Vector3 velocity(moved.x / dt, 0.0f, moved.z / dt);
			e.velocity += (velocity - e.velocity) * std::min(1.0f, dt * 8.0f);
		}
		e.last_position = unit_xf.origin;
		e.has_last_position = true;
		Transform3D world = unit_xf * pose(e, sprite, dt);
		world.origin += e.velocity * e.hold;
		e.last_world = world;
		// Hidden by fog of war (or by the unit itself): not drawn, not picked.
		e.was_drawn = unit->is_visible_in_tree();
		if (!e.was_drawn) continue;

		Type &type = types_[size_t(e.type)];
		if (!e.dying) pickables_.push_back({ e.unit, unit_xf.origin, type.height, type.pick_radius });
		const Vector3 middle = world.origin + Vector3(0.0f, type.height * 0.5f, 0.0f);
		const float custom[4] = { e.team_packed, pack_rgb(sprite->get_modulate()),
			Math::clamp(std::max(sprite->get_modulate().r, std::max(sprite->get_modulate().g, sprite->get_modulate().b)) - 1.0f, 0.0f, 1.0f),
			e.dying ? -1.0f : 1.0f };
		if (cast_shadows_ && in_view(middle, type.shadow_radius)) write(type.shadow_batch, world, custom);
		if (!in_view(middle, type.view_radius)) continue;
		const float eye_distance = camera != nullptr ? eye.distance_to(world.origin) : 0.0f;
		if (e.landed && camera != nullptr && eye_distance < stomp_distance) {
			stomp_distance = eye_distance;
			stomp_at = world.origin;
		}
		const bool far = camera != nullptr && eye_distance > lod_distance_ * type.lod_scale;
		write(far ? type.far_batch : type.near_batch, world, custom);
	}
	if (stomp_distance < 1e30f) emit_signal("stomped", stomp_at);

	for (size_t i = 0; i < corpses_.size();) {
		Corpse &c = corpses_[i];
		c.age += dt;
		if (c.age >= kCorpseHold + kCorpseFade) {
			corpses_[i] = corpses_.back();
			corpses_.pop_back();
			continue;
		}
		++i;
		if (!drawing_ || !c.shown) continue;
		const float k = Math::clamp((c.age - kCorpseHold) / kCorpseFade, 0.0f, 1.0f);
		Transform3D world = c.world;
		world.origin.y -= kCorpseSink * k * k;
		Type &type = types_[size_t(c.type)];
		const float custom[4] = { c.team_packed, pack_rgb(Color(1, 1, 1)), 0.0f, -std::max(1.0f - k, 0.001f) };
		const Vector3 middle = world.origin + Vector3(0.0f, 0.3f, 0.0f);
		if (cast_shadows_ && k < 0.5f && in_view(middle, type.shadow_radius)) write(type.shadow_batch, world, custom);
		if (!in_view(middle, type.view_radius)) continue;
		const bool far = camera != nullptr && eye.distance_to(world.origin) > lod_distance_ * type.lod_scale;
		write(far ? type.far_batch : type.near_batch, world, custom);
	}

	if (!drawing_) return;
	for (Type &t : types_) {
		drawn_near_ += t.near_batch.count;
		drawn_far_ += t.far_batch.count;
		drawn_shadow_ += t.shadow_batch.count;
		upload(t.near_batch);
		upload(t.far_batch);
		upload(t.shadow_batch);
	}
}
