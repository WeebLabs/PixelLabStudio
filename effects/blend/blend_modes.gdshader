// Per-layer Photoshop-style blend modes that read the backdrop from the screen
// backbuffer. The active mode is chosen by the `blend_mode` uniform (== BlendMode.Mode).
//
// Only the destination-reading modes live here. Normal / Add / Subtract are handled by
// the native CanvasItemMaterial hardware blend (no backbuffer) and never select this
// shader — see effects/blend/blend_mode.gd.
//
// Pipeline facts (verified empirically on Mobile + Metal, Godot 4.6):
//   * Layer textures are PREMULTIPLIED alpha; the backbuffer is likewise premultiplied.
//   * Output is premultiplied with `blend_premul_alpha`, so compositing stays correct over
//     ANY backdrop alpha — the opaque editor window (Ad=1) AND a transparent stream/NDI
//     viewport (Ad<1).
//   * COLOR carries self_modulate, a gray (o,o,o,o) that encodes talk/blink * opacity. We
//     read only COLOR.a as this layer's coverage/opacity and ignore COLOR.rgb.
shader_type canvas_item;
render_mode blend_premul_alpha;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform int blend_mode = 0;

// --- Separable blend functions. Operate on STRAIGHT colors, component-wise.
//     d = backdrop (destination, below), s = source (this layer). ---

vec3 b_multiply(vec3 d, vec3 s) { return d * s; }
vec3 b_screen(vec3 d, vec3 s) { return d + s - d * s; }
vec3 b_darken(vec3 d, vec3 s) { return min(d, s); }
vec3 b_lighten(vec3 d, vec3 s) { return max(d, s); }
vec3 b_difference(vec3 d, vec3 s) { return abs(d - s); }
vec3 b_exclusion(vec3 d, vec3 s) { return d + s - 2.0 * d * s; }

vec3 b_color_dodge(vec3 d, vec3 s) {
	// d / (1 - s), guarded against divide-by-zero; s >= 1 burns to white where d > 0.
	vec3 dodged = min(vec3(1.0), d / max(vec3(1.0) - s, vec3(1e-4)));
	return mix(dodged, vec3(1.0), step(vec3(1.0), s));
}
vec3 b_color_burn(vec3 d, vec3 s) {
	// 1 - (1 - d) / s, guarded; s <= 0 burns to black where d < 1.
	vec3 burned = vec3(1.0) - min(vec3(1.0), (vec3(1.0) - d) / max(s, vec3(1e-4)));
	return mix(burned, vec3(0.0), step(s, vec3(0.0)));
}

// Hard Light is Overlay with the operands swapped: overlay(d,s) == hard_light(s,d).
vec3 b_hard_light(vec3 d, vec3 s) {
	vec3 lo = 2.0 * d * s;
	vec3 hi = vec3(1.0) - 2.0 * (vec3(1.0) - d) * (vec3(1.0) - s);
	return mix(lo, hi, step(vec3(0.5), s));
}
vec3 b_overlay(vec3 d, vec3 s) { return b_hard_light(s, d); }

vec3 b_soft_light(vec3 d, vec3 s) {
	// W3C soft-light. D(d) is the piecewise darkening curve applied when s > 0.5.
	vec3 dd = mix(sqrt(d), ((16.0 * d - 12.0) * d + 4.0) * d, step(d, vec3(0.25)));
	vec3 lo = d - (vec3(1.0) - 2.0 * s) * d * (vec3(1.0) - d);  // s <= 0.5
	vec3 hi = d + (2.0 * s - vec3(1.0)) * (dd - d);             // s > 0.5
	return mix(lo, hi, step(vec3(0.5), s));
}

// Dispatch on the uniform. Godot's shading language has no `switch`, so this is an
// if-chain; the branch is on a uniform (coherent across the draw) so it costs nothing.
// The cases match BlendMode.Mode values; Normal(0)/Add(7)/Subtract(13) never arrive here.
vec3 apply_blend(int mode, vec3 d, vec3 s) {
	if (mode == 1) return b_darken(d, s);
	if (mode == 2) return b_multiply(d, s);
	if (mode == 3) return b_color_burn(d, s);
	if (mode == 4) return b_lighten(d, s);
	if (mode == 5) return b_screen(d, s);
	if (mode == 6) return b_color_dodge(d, s);
	if (mode == 8) return b_overlay(d, s);
	if (mode == 9) return b_soft_light(d, s);
	if (mode == 10) return b_hard_light(d, s);
	if (mode == 11) return b_difference(d, s);
	if (mode == 12) return b_exclusion(d, s);
	return s;  // unreachable for shader-tier modes; safe passthrough
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);                      // premultiplied source
	float cov = src.a * COLOR.a;                          // coverage * opacity (self_modulate.a)
	vec3 cs = src.a > 0.0 ? src.rgb / src.a : vec3(0.0);  // straight source color

	vec4 scr = texture(screen_tex, SCREEN_UV);            // premultiplied backdrop
	float ad = scr.a;
	vec3 cd = ad > 0.0 ? scr.rgb / ad : vec3(0.0);        // straight backdrop color

	vec3 blended = apply_blend(blend_mode, cd, cs);
	// W3C blend-vs-backdrop-alpha: pure source where the backdrop is transparent,
	// the blended result where it is opaque, interpolated in between.
	vec3 cs_blend = (1.0 - ad) * cs + ad * blended;
	COLOR = vec4(cov * cs_blend, cov);                   // premultiplied; hardware does 'over'
}
