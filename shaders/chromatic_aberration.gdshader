shader_type canvas_item;

// Chromatic aberration: shifts the red and blue channels apart
// horizontally by a small amount, creating a "warped" synthwave
// look. The shift is scaled by the `intensity` uniform (0..1);
// at 0 the effect is invisible, at 1 the shift is the maximum
// (0.015 UV, ~15px on a 1000px screen).
//
// `screen_texture` is the rendered content behind this ColorRect.
// Reading it with the `hint_screen_texture` declaration lets the
// shader sample the screen at the current pixel's UV.

uniform float intensity : hint_range(0.0, 1.0) = 0.05;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

void fragment() {
	// Horizontal shift only -- vertical chromatic aberration is rare
	// and looks like a hardware glitch more than an aesthetic
	// choice. The 0.015 multiplier caps the max shift at a level
	// that reads as "stylized" rather than "broken".
	vec2 offset = vec2(intensity * 0.015, 0.0);

	// Sample each channel at a different UV to get the offset.
	float r = texture(screen_texture, SCREEN_UV + offset).r;
	float g = texture(screen_texture, SCREEN_UV).g;
	float b = texture(screen_texture, SCREEN_UV - offset).b;

	COLOR = vec4(r, g, b, 1.0);
}
