// Surfaces that get the ink outline (see shaders/post/outline.gdshader) write
// an id of their object into ROUGHNESS, so the outline pass can draw a line
// only where one object meets something else -- its silhouette as the camera
// sees it -- and never along the tiles or creases inside it. Ids sit in
// OUTLINE_ID_SLOTS steps of 2/255 from 0.6, below the 1.0 the ground writes.
//
// Each shader declares `v_outline_roughness` itself (a flat varying), sets it
// in vertex() with outline_roughness_for(), and writes it to ROUGHNESS.
//
// A building gives all its meshes one id (ProductionBuilding sets
// outline_id); anything else -- trees, rocks, deposits -- takes one from where
// it stands, so each tree in a forest MultiMesh is its own object.
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
instance uniform float outline_id = 0.0;
#endif

const float OUTLINE_ID_SLOTS = 48.0;

float outline_hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float outline_roughness_for(vec3 p_origin, float p_index) {
	float id = outline_hash(p_origin + p_index * vec3(1.31, 0.0, 2.77));
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	if (outline_id > 0.0) {
		id = fract(outline_id * 0.6180339);
	}
#endif
	return (153.0 + 2.0 * floor(id * OUTLINE_ID_SLOTS)) / 255.0;
}
