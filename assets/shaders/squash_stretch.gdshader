shader_type canvas_item;

// Squash & stretch, driven from GDScript by tweening `amount`.
// amount > 0 stretches (tall + thin), amount < 0 squashes (flat + wide).
// `pivot` is the local-space point that stays fixed — set to the sprite's
// bottom-centre so feet stay planted. `volume` blends in area preservation
// (0 = plain vertical scale, 1 = strict width compensation).
uniform float amount : hint_range(-0.6, 0.6) = 0.0;
uniform float volume : hint_range(0.0, 1.0) = 0.7;
uniform vec2 pivot = vec2(0.0, 32.0);

void vertex() {
	float sy = max(1.0 + amount, 0.05);
	float sx = mix(1.0, 1.0 / sy, volume);
	VERTEX = pivot + (VERTEX - pivot) * vec2(sx, sy);
}
