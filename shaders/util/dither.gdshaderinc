// Standard 4x4 Bayer dithering matrix, used by grass_wind.gdshader's
// "Dithered" alpha mode to fake a soft alpha cutout without real
// transparency sorting (dithered pixels are either fully opaque or fully
// discarded, so depth/shadows behave like a normal cutout material).
const float BAYER_4x4[16] = float[](
	0.0,  8.0,  2.0,  10.0,
	12.0, 4.0,  14.0, 6.0,
	3.0,  11.0, 1.0,  9.0,
	15.0, 7.0,  13.0, 5.0
);

float bayer4(vec2 frag_coord) {
	int x = int(frag_coord.x) % 4;
	int y = int(frag_coord.y) % 4;
	return BAYER_4x4[y * 4 + x] / 16.0;
}
