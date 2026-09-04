shader_type canvas_item;
render_mode unshaded;

uniform float tilt_x_deg = 0.0;
uniform float tilt_y_deg = 0.0;
uniform float focal_mul = 4.0;
uniform vec2 card_half_size = vec2(0.0, 0.0);
// 1 = Control (VERTEX 0..size). 0 = Sprite2D centered (VERTEX already around 0).
uniform float corner_origin = 0.0;
// 카드 로컬(중심 기준) 회전 피벗. 오픈 충격 시 먼 쪽 변/모서리.
uniform vec2 tilt_pivot = vec2(0.0, 0.0);
uniform float rarity_tier = 0.0;
uniform vec4 rarity_accent = vec4(0.45, 0.45, 0.5, 1.0);
// 1 = pack/chip rarity hint (wide glow). 0 = normal display outline only.
uniform float rarity_hint = 0.0;
uniform sampler2D holo_rainbow : hint_default_white, filter_linear, repeat_enable;
uniform sampler2D holo_distort : hint_default_white, filter_linear, repeat_enable;

varying vec2 v_uv_persp;
varying float v_inv_depth;

void vertex() {
	float ax = radians(tilt_x_deg);
	float ay = radians(tilt_y_deg);
	float cx = cos(ax);
	float sx = sin(ax);
	float cy = cos(ay);
	float sy = sin(ay);

	vec2 origin = vec2(0.0, 0.0);
	if (corner_origin > 0.5 && card_half_size.x > 0.5) {
		origin = card_half_size;
	}
	// 중심(또는 Control 코너→중심) 기준 좌표에서 tilt_pivot 주위로 회전.
	vec2 v = VERTEX - origin - tilt_pivot;

	float x1 = v.x * cy;
	float z1 = -v.x * sy;
	float y1 = v.y;

	float y2 = y1 * cx - z1 * sx;
	float z2 = y1 * sx + z1 * cx;
	float x2 = x1;

	// Constant focal — per-vertex abs(v.y) tears the quad into mismatched planes.
	float half_h = max(card_half_size.y, 1.0);
	float focal = half_h * focal_mul;
	float depth = focal - z2;
	if (depth < focal * 0.2) {
		depth = focal * 0.2;
	}
	float persp = focal / depth;

	VERTEX.x = x2 * persp + origin.x + tilt_pivot.x;
	VERTEX.y = y2 * persp + origin.y + tilt_pivot.y;

	v_inv_depth = 1.0 / depth;
	v_uv_persp = UV * v_inv_depth;
}

vec3 ygo_rgb_to_hsl(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float h = 0.0;
	float s = 0.0;
	float l = (mx + mn) * 0.5;
	float d = mx - mn;
	if (d > 0.0001) {
		s = l > 0.5 ? d / (2.0 - mx - mn) : d / (mx + mn);
		if (mx == c.r) {
			h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
		} else if (mx == c.g) {
			h = (c.b - c.r) / d + 2.0;
		} else {
			h = (c.r - c.g) / d + 4.0;
		}
		h /= 6.0;
	}
	return vec3(h, s, l);
}

float ygo_hue_to_rgb(float p, float q, float t) {
	if (t < 0.0) {
		t += 1.0;
	}
	if (t > 1.0) {
		t -= 1.0;
	}
	if (t < 1.0 / 6.0) {
		return p + (q - p) * 6.0 * t;
	}
	if (t < 0.5) {
		return q;
	}
	if (t < 2.0 / 3.0) {
		return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
	}
	return p;
}

vec3 ygo_hsl_to_rgb(vec3 hsl) {
	float h = hsl.x;
	float s = hsl.y;
	float l = hsl.z;
	if (s <= 0.0001) {
		return vec3(l);
	}
	float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
	float p = 2.0 * l - q;
	return vec3(
		ygo_hue_to_rgb(p, q, h + 1.0 / 3.0),
		ygo_hue_to_rgb(p, q, h),
		ygo_hue_to_rgb(p, q, h - 1.0 / 3.0)
	);
}

vec3 ygo_blend_color(vec3 top, vec3 bottom) {
	vec3 th = ygo_rgb_to_hsl(top);
	vec3 bh = ygo_rgb_to_hsl(bottom);
	return ygo_hsl_to_rgb(vec3(th.x, th.y, bh.z));
}

vec3 ygo_color_dodge(vec3 base_col, vec3 blend_col) {
	return min(vec3(1.0), base_col / max(vec3(1.0) - blend_col, vec3(0.004)));
}

float foil_weight_from_rgb(vec3 c) {
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float hsl_l = ygo_rgb_to_hsl(c).z;
	return clamp(max(lum, mix(lum, hsl_l, 0.75)), 0.0, 1.0);
}

void fragment() {
	vec2 uv = v_uv_persp / max(v_inv_depth, 0.0001);
	vec4 base = texture(TEXTURE, uv);
	vec3 rgb = base.rgb;
	vec3 accent = rarity_accent.rgb;
	vec2 tilt = vec2(tilt_y_deg, -tilt_x_deg) / 20.0;
	bool is_hint = rarity_hint > 0.5;

	// Face foil sheen — chip/in-game display only. Pack/chip hints skip this.
	if (base.a > 0.01 && rarity_tier > 0.5 && !is_hint) {
		if (rarity_tier < 1.5) {
			float foil_w = foil_weight_from_rgb(rgb);
			float foil_w_r = mix(0.68, 0.40, foil_w);
			float tilt_amt = clamp(length(tilt), 0.0, 1.0);
			vec2 foil_uv = uv + tilt * 0.02;
			float pattern = fract(
				(foil_uv.x + foil_uv.y) * 0.4
				+ TIME * 0.15
				+ (tilt.x + tilt.y) * 0.55
			);
			float wave = 0.5 + 0.5 * cos(6.28318 * pattern);
			vec3 silver = mix(vec3(0.62, 0.68, 0.78), vec3(0.92, 0.95, 1.0), wave);
			silver = mix(silver, accent, 0.62);
			float meso = sin((foil_uv.x + foil_uv.y) * 9.0 + TIME * 0.15 + tilt.x * 1.4 + tilt.y * 1.1);
			meso = meso * 0.5 + 0.5;
			meso = mix(1.0, meso, mix(0.04, 0.10, tilt_amt));
			float wave_a = sin(foil_uv.x * 22.0 + foil_uv.y * 14.0 + tilt.x * 2.0 + TIME * 0.15);
			float wave_b = sin(foil_uv.x * 17.0 - foil_uv.y * 19.0 + tilt.y * 2.0 - TIME * 0.15);
			float micro = wave_a * wave_b * 0.5 + 0.5;
			micro = mix(1.0, micro, mix(0.04, 0.12, tilt_amt));
			float mask_l = foil_w_r * meso * micro;
			mask_l = clamp(mask_l, 0.28, 0.78);
			vec3 foil = ygo_blend_color(silver, vec3(mask_l));
			float foil_amt = mix(0.56, 0.42, foil_w) * mix(0.88, 1.06, tilt_amt);
			vec3 dodged = ygo_color_dodge(rgb, foil * foil_amt);
			rgb = mix(rgb, dodged, mix(0.72, 0.84, tilt_amt));
			rgb += silver * wave * mix(0.05, 0.10, tilt_amt) * foil_w_r;
		} else if (rarity_tier < 2.5) {
			// Cyanilux holofoil: soft streaks (not blotches) + brighter rainbow lift.
			float foil_w = foil_weight_from_rgb(rgb);
			float tilt_amt = clamp(length(tilt), 0.0, 1.0);
			vec2 view = -tilt;
			vec3 dist = texture(holo_distort, uv * 1.55).rgb;
			vec2 holo_uv = view * 1.35 + (dist.rg - 0.5) * 0.28;
			holo_uv.x += (uv.x * 0.55 + uv.y * 0.35);
			float ca = cos(0.4);
			float sa = sin(0.4);
			holo_uv = vec2(holo_uv.x * ca - holo_uv.y * sa, holo_uv.x * sa + holo_uv.y * ca);
			vec3 rainbow = texture(holo_rainbow, vec2(fract(holo_uv.x * 0.7 + 0.5), 0.5)).rgb;
			rainbow = mix(rainbow, vec3(1.0), 0.12);
			rainbow = mix(rainbow, accent, 0.06);
			float mask = smoothstep(0.14, 0.72, foil_w);
			mask *= mix(0.55, 0.92, tilt_amt);
			vec3 lifted = clamp(rgb * 0.62 + rainbow * 0.78, 0.0, 1.0);
			rgb = mix(rgb, lifted, mask * 0.58);
			rgb += rainbow * mask * mix(0.10, 0.26, tilt_amt);
		} else {
			float foil_w = foil_weight_from_rgb(rgb);
			float tilt_amt = clamp(length(tilt), 0.0, 1.0);
			vec2 foil_uv = uv + tilt * 0.015;
			float pattern = fract(
				(foil_uv.x + foil_uv.y) * 0.4
				+ TIME * 0.15
				+ (tilt.x + tilt.y) * 0.3
			);
			vec3 rainbow = vec3(
				0.5 + 0.5 * cos(6.28318 * pattern),
				0.5 + 0.5 * cos(6.28318 * (pattern + 0.33)),
				0.5 + 0.5 * cos(6.28318 * (pattern + 0.67))
			);
			rainbow = mix(vec3(1.0), rainbow, 0.88);
			rainbow = mix(accent, rainbow, 0.62);
			float meso = sin((foil_uv.x + foil_uv.y) * 9.0 + TIME * 0.15 + tilt.x * 0.8 + tilt.y * 0.6);
			meso = meso * 0.5 + 0.5;
			meso = mix(1.0, meso, 0.07);
			float wave_a = sin(foil_uv.x * 22.0 + foil_uv.y * 14.0 + tilt.x * 1.2 + TIME * 0.15);
			float wave_b = sin(foil_uv.x * 17.0 - foil_uv.y * 19.0 + tilt.y * 1.4 - TIME * 0.15);
			float micro = wave_a * wave_b * 0.5 + 0.5;
			micro = mix(1.0, micro, 0.10 * (0.25 + 0.75 * tilt_amt));
			float mask_l = foil_w * meso * micro;
			mask_l = clamp(mask_l, 0.20, 0.83);
			vec3 foil = ygo_blend_color(rainbow, vec3(mask_l));
			float foil_amt = mix(0.56, 0.70, foil_w) * (0.78 + 0.22 * tilt_amt);
			vec3 dodged = ygo_color_dodge(rgb, foil * foil_amt);
			rgb = mix(rgb, dodged, 0.92);
		}
	}

	// Rarity outline. Glow/pulse only when rarity_hint > 0.5 (pack/chip hints).
	// 두께: width(코어) · glow_w(힌트 시 번짐) · strength
	if (base.a > 0.01 && rarity_tier > 0.5) {
		float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
		float width = 0.014;
		float glow_w = 0.070;
		float strength = 0.95;
		vec3 outline_col = accent;
		float tilt_amt = clamp(length(tilt), 0.0, 1.0);

		if (rarity_tier < 1.5) {
			width = 0.013;
			glow_w = 0.062;
			strength = is_hint ? 0.98 : 0.70;
			outline_col = accent;
		} else if (rarity_tier < 2.5) {
			width = 0.015;
			glow_w = 0.078;
			strength = is_hint ? 1.12 : 0.78;
			outline_col = accent;
		} else {
			width = 0.017;
			glow_w = 0.092;
			strength = is_hint ? 1.22 : 0.85;
			float ang = atan(uv.y - 0.5, uv.x - 0.5) / 6.28318 + TIME * 0.14;
			vec3 rainbow = vec3(
				0.5 + 0.5 * cos(6.28318 * ang),
				0.5 + 0.5 * cos(6.28318 * (ang + 0.33)),
				0.5 + 0.5 * cos(6.28318 * (ang + 0.67))
			);
			outline_col = mix(accent, rainbow, 0.58);
		}

		float core = 1.0 - smoothstep(0.0, width, edge);

		if (is_hint) {
			float pulse = 0.86 + 0.14 * (0.5 + 0.5 * sin(TIME * 2.4));
			float glow_soft = 1.0 - smoothstep(0.0, glow_w, edge);
			float glow_mid = 1.0 - smoothstep(0.0, glow_w * 0.55, edge);
			float glow = glow_soft * 0.60 + glow_mid * 0.50;
			float mask = clamp(core * 1.25 + glow, 0.0, 1.45) * strength * pulse;
			mask *= mix(0.92, 1.14, tilt_amt);
			mask = clamp(mask, 0.0, 1.0);
			rgb = mix(rgb, outline_col, mask * 0.82);
			rgb += outline_col * glow * mix(0.48, 0.68, tilt_amt) * pulse;
			rgb += outline_col * core * mix(0.48, 0.72, tilt_amt);
		} else {
			// Display: thin core rim only (no bloom / pulse).
			float mask = clamp(core, 0.0, 1.0) * strength;
			mask *= mix(0.92, 1.08, tilt_amt);
			rgb = mix(rgb, outline_col, mask * 0.85);
			rgb += outline_col * core * mix(0.22, 0.38, tilt_amt);
		}
	}

	// Alpha only — multiplying COLOR.rgb darkens art; root/modulate alpha still applies.
	COLOR = vec4(rgb, base.a * COLOR.a);
}
