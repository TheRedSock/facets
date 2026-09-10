// Compact, smooth coefficient fields. No mesh, texture, or density raster.
struct VolumeField { vec4 center_absorption; vec4 radius_scatter; vec4 rotation; ivec4 spectrum_profile; };
layout(set = 0, binding = 7, std430) readonly buffer VolumeFields { VolumeField volume_fields[]; };
const int MAX_VOLUME_FIELDS = 16;

// A field restricted to a ray: density=max(0,height-speed²(t-closest)²)^3.
// t is in stone units. Clipped endpoints delimit its exact finite support.
struct FieldChord { float closest; float speed2; float height; float begin; float end; int profile; };
FieldChord field_chord(VolumeField f, vec3 pos_mm, vec3 velocity_mm, float distance) {
	vec4 inverse_rotation = quat_conj(f.rotation);
	vec3 origin = quat_rot(inverse_rotation, pos_mm - f.center_absorption.xyz) / f.radius_scatter.xyz;
	vec3 velocity = quat_rot(inverse_rotation, velocity_mm) / f.radius_scatter.xyz;
	if(f.spectrum_profile.z==1) {
		// The first two slots hold affine z(t) for a planar transition.
		float a=velocity.z==0.0?0.0:(-1.0-origin.z)/velocity.z;
		float b=velocity.z==0.0?0.0:(1.0-origin.z)/velocity.z;
		return FieldChord(origin.z,velocity.z,0.0,max(0.0,min(a,b)),min(distance,max(a,b)),1);
	}
	float speed2 = dot(velocity, velocity);
	float closest = -dot(origin, velocity) / speed2;
	vec3 perpendicular = origin + velocity * closest;
	float height = 1.0 - dot(perpendicular, perpendicular);
	float span = sqrt(max(0.0, height) / speed2);
	return FieldChord(closest, speed2, max(0.0, height), max(0.0, closest - span), min(distance, closest + span),0);
}

float chord_density(FieldChord chord, float t) {
	if(chord.profile==1) {
		float u=clamp(0.5*(chord.closest+chord.speed2*t+1.0),0.0,1.0);
		return u*u*u*(10.0+u*(-15.0+6.0*u));
	}
	float offset = t - chord.closest;
	float value = max(0.0, chord.height - chord.speed2 * offset * offset);
	return value * value * value;
}

float chord_column(FieldChord chord, float distance) {
	float plateau=0.0;
	if(chord.profile==1) {
		if(chord.speed2==0.0) return distance*chord_density(chord,0.0);
		float high=(1.0-chord.closest)/chord.speed2;
		plateau=chord.speed2>0.0?distance-clamp(high,0.0,distance):clamp(high,0.0,distance);
	}
	float end = min(distance, chord.end);
	if (end <= chord.begin) { return plateau; }
	float midpoint = (chord.begin + end) * 0.5;
	float half_length = (end - chord.begin) * 0.5;
	float inner = half_length * 0.3399810435848563;
	float outer = half_length * 0.8611363115940526;
	return plateau+half_length * (0.6521451548625461 * (chord_density(chord, midpoint - inner) + chord_density(chord, midpoint + inner))
		+ 0.3478548451374538 * (chord_density(chord, midpoint - outer) + chord_density(chord, midpoint + outer)));
}

// Returns (additional absorption column in stone units, scattering optical depth).
vec2 field_columns(Stone st, vec3 pos, vec3 dir, float distance) {
	vec2 result = vec2(0.0);
	for (int index = 0; index < st.ranges0.w; index++) {
		VolumeField field = volume_fields[st.ranges0.z + index];
		FieldChord chord = field_chord(field, pos * st.sell_b_size.w, dir * st.sell_b_size.w, distance);
		result += chord_column(chord, distance) * vec2(field.center_absorption.w, field.radius_scatter.w * st.sell_b_size.w);
	}
	return result;
}

float scattering_depth(Stone st, vec3 pos, vec3 dir, float distance) {
	return st.scatter_zone.x * st.sell_b_size.w * distance + field_columns(st, pos, dir, distance).y;
}

// Invert integrated scattering depth, with analytic coefficients cached per ray.
// This avoids null-collision loops in sparse dense bands. Homogeneous paths keep
// their constant-time inverse. Positive quadrature gives a monotone CDF.
float scatter_distance(Stone st, vec3 pos, vec3 dir, float distance, float tau) {
	float base = st.scatter_zone.x * st.sell_b_size.w;
	if (st.ranges0.w == 0) { return base > 0.0 ? tau / base : INF; }
	FieldChord chords[MAX_VOLUME_FIELDS];
	float coefficients[MAX_VOLUME_FIELDS];
	float depth = base * distance;
	for (int index = 0; index < st.ranges0.w; index++) {
		VolumeField field = volume_fields[st.ranges0.z + index];
		chords[index] = field_chord(field, pos * st.sell_b_size.w, dir * st.sell_b_size.w, distance);
		coefficients[index] = field.radius_scatter.w * st.sell_b_size.w;
		depth += coefficients[index] * chord_column(chords[index], distance);
	}
	if (tau >= depth) { return INF; }
	float low = 0.0, high = distance;
	float t = distance * tau / depth;
	for (int iteration = 0; iteration < 32; iteration++) {
		float at_t = base * t;
		float density = base;
		for (int index = 0; index < st.ranges0.w; index++) {
			at_t += coefficients[index] * chord_column(chords[index], t);
			density += coefficients[index] * chord_density(chords[index], t);
		}
		float error = at_t - tau;
		if (abs(error) < 2e-6 * max(1.0, tau)) { return t; }
		if (error > 0.0) { high = t; } else { low = t; }
		float candidate = t - error / max(density, 1e-20);
		// Force bracket contraction when Newton would barely move or leave it.
		float margin = (high - low) * 0.05;
		t = candidate > low + margin && candidate < high - margin ? candidate : (low + high) * 0.5;
	}
	return (low + high) * 0.5;
}
