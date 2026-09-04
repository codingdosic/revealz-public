shader_type canvas_item;
## progress 0 = 전체 검정, 1 = 전체 투명. hole 반경이 중앙에서 바깥으로 커진다.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float softness : hint_range(0.0, 0.2) = 0.08;
uniform float aspect = 1.777;

void fragment() {
	if (progress <= 0.0001) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
		return;
	}
	vec2 p = UV - vec2(0.5);
	p.x *= aspect;
	float max_d = length(vec2(0.5 * aspect, 0.5));
	float d = length(p) / max_d;
	float hole = progress * (1.0 + softness * 2.5);
	float alpha = smoothstep(hole, hole + softness, d);
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
