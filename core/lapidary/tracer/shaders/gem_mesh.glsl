// Procedural triangle backend. Node and triangle layouts match GemBvh.
struct GemTriangle { vec4 a; vec4 b; vec4 c; ivec4 meta; };
struct GemNode { vec4 low; vec4 high; ivec4 links; };
layout(set = 0, binding = 11, std430) readonly buffer Triangles { GemTriangle triangles[]; };
layout(set = 0, binding = 12, std430) readonly buffer Nodes { GemNode nodes[]; };

bool mesh_box(GemNode node, vec3 origin, vec3 direction, float closest) {
	float lo = T_EPS, hi = closest;
	for (int axis = 0; axis < 3; axis++) {
		if (abs(direction[axis]) < 1e-15) {
			if (origin[axis] < node.low[axis] || origin[axis] > node.high[axis]) { return false; }
		} else {
			float a = (node.low[axis] - origin[axis]) / direction[axis];
			float b = (node.high[axis] - origin[axis]) / direction[axis];
			lo = max(lo, min(a, b)); hi = min(hi, max(a, b));
			if (lo > hi) { return false; }
		}
	}
	return true;
}

float mesh_triangle(GemTriangle triangle, vec3 origin, vec3 direction) {
	vec3 ad = abs(direction);
	int kz = ad.x > ad.y ? (ad.x > ad.z ? 0 : 2) : (ad.y > ad.z ? 1 : 2);
	int kx = (kz + 1) % 3, ky = (kx + 1) % 3;
	if (direction[kz] < 0.0) { int swap = kx; kx = ky; ky = swap; }
	float sx = -direction[kx] / direction[kz], sy = -direction[ky] / direction[kz];
	vec3 a = triangle.a.xyz - origin, b = triangle.b.xyz - origin, c = triangle.c.xyz - origin;
	vec2 pa = vec2(a[kx] + sx * a[kz], a[ky] + sy * a[kz]);
	vec2 pb = vec2(b[kx] + sx * b[kz], b[ky] + sy * b[kz]);
	vec2 cp = vec2(c[kx] + sx * c[kz], c[ky] + sy * c[kz]);
	// Separate products prohibit asymmetric FMA contraction on shared edges.
	precise float ea = pb.x * cp.y - pb.y * cp.x;
	precise float eb = cp.x * pa.y - cp.y * pa.x;
	precise float ec = pa.x * pb.y - pa.y * pb.x;
	if ((ea < 0.0 || eb < 0.0 || ec < 0.0) && (ea > 0.0 || eb > 0.0 || ec > 0.0)) { return INF; }
	float determinant = ea + eb + ec;
	if (determinant == 0.0) { return INF; }
	return (ea * a[kz] + eb * b[kz] + ec * c[kz]) / (direction[kz] * determinant);
}

bool mesh_hit(int root, vec3 origin, vec3 direction, out float closest, out int triangle) {
	closest = INF; triangle = -1;
	int stack[64]; int pending = 1; stack[0] = root;
	while (pending > 0) {
		GemNode node = nodes[stack[--pending]];
		if (!mesh_box(node, origin, direction, closest)) { continue; }
		if (node.links.w == 0) {
			stack[pending++] = node.links.x;
			stack[pending++] = node.links.y;
		} else {
			for (int i = 0; i < node.links.w; i++) {
				int index = node.links.z + i;
				float distance = mesh_triangle(triangles[index], origin, direction);
				if (distance > T_EPS && distance < closest) { closest = distance; triangle = index; }
			}
		}
	}
	return triangle >= 0;
}

vec3 mesh_normal(int index) {
	GemTriangle triangle = triangles[index];
	return normalize(cross(triangle.b.xyz - triangle.a.xyz, triangle.c.xyz - triangle.a.xyz));
}

// A cabochon is the closed union of an upper ellipsoid, an elliptical
// girdle cylinder and a flat base. Surface IDs -1/-2/-3 identify these patches.
vec2 quadric_roots(float a, float b, float c) {
	float disc = b * b - 4.0 * a * c;
	if (a < 1e-20 || disc < 0.0) { return vec2(INF); }
	float q = -0.5 * (b + (b >= 0.0 ? 1.0 : -1.0) * sqrt(disc));
	if (abs(q) < 1e-30) { return vec2(-b / (2.0 * a)); }
	float first = q / a, second = c / q;
	return vec2(min(first, second), max(first, second));
}

bool cabochon_hit(vec4 shape, vec3 origin, vec3 direction, out float closest, out int surface) {
	closest = INF; surface = 0;
	vec3 o = origin / shape.xyz, d = direction / shape.xyz;
	vec2 roots = quadric_roots(dot(d, d), 2.0 * dot(o, d), dot(o, o) - 1.0);
	for (int i = 0; i < 2; i++) {
		float t = roots[i];
		if (t > T_EPS && t < closest && origin.z + direction.z * t >= 0.0) { closest = t; surface = -1; }
	}
	roots = quadric_roots(dot(d.xy, d.xy), 2.0 * dot(o.xy, d.xy), dot(o.xy, o.xy) - 1.0);
	for (int i = 0; i < 2; i++) {
		float t = roots[i], z = origin.z + direction.z * t;
		if (t > T_EPS && t < closest && z >= shape.w && z <= 0.0) { closest = t; surface = -2; }
	}
	if (abs(direction.z) > 1e-15) {
		float t = (shape.w - origin.z) / direction.z;
		vec2 p = o.xy + d.xy * t;
		if (t > T_EPS && t < closest && dot(p, p) <= 1.0) { closest = t; surface = -3; }
	}
	return surface != 0;
}

bool boundary_hit(Stone stone, vec3 origin, vec3 direction, out float distance, out int surface) {
	distance = INF; surface = -100;
	if (stone.ranges1.z == 0) {
		float enter = -INF, leave = INF; int enter_face = -1, leave_face = -1;
		for (int i = 0; i < stone.ranges0.y; i++) {
			int face = stone.ranges0.x + i;
			vec4 plane = planes[face].n_d;
			float projection = dot(plane.xyz, direction), gap = plane.w - dot(plane.xyz, origin);
			if (abs(projection) < 1e-9) { if (gap < 0.0) { return false; } continue; }
			float t = gap / projection;
			if (projection < 0.0 && t > enter) { enter = t; enter_face = face; }
			if (projection > 0.0 && t < leave) { leave = t; leave_face = face; }
			if (enter > leave) { return false; }
		}
		if (enter > T_EPS) { distance = enter; surface = enter_face; }
		else if (leave > T_EPS) { distance = leave; surface = leave_face; }
		return surface >= 0 && distance < INF * 0.5;
	}
	bool hit = false;
	if (stone.ranges0.y == -1) { hit = cabochon_hit(planes[stone.ranges0.x].n_d, origin, direction, distance, surface); }
	if (stone.ranges1.z > 0) {
		float mesh_distance; int triangle;
		if (mesh_hit(stone.ranges1.z - 1, origin, direction, mesh_distance, triangle) && mesh_distance < distance) {
			distance = mesh_distance; surface = triangle; hit = true;
		}
	}
	return hit;
}

vec3 boundary_normal(Stone stone, int surface, vec3 position) {
	if (stone.ranges1.z == 0) { return planes[surface].n_d.xyz; }
	if (surface >= 0) { return mesh_normal(surface); }
	if (surface == -3) { return vec3(0, 0, -1); }
	vec3 axes = planes[stone.ranges0.x].n_d.xyz;
	vec3 n = position / (axes * axes);
	if (surface == -2) { n.z = 0.0; }
	return normalize(n);
}

layout(set = 0, binding = 13, std430) readonly buffer Regions { int region_materials[]; };

int region_medium(Stone stone, uvec4 region_state) {
	if ((region_state.x & 1u) == 0u) { return -1; }
	for (int word = 3; word >= 0; word--) {
		if (region_state[word] != 0u) {
			int region = word * 32 + findMSB(region_state[word]);
			return region_materials[stone.ranges1.w + region];
		}
	}
	return -1;
}

uvec4 cross_region(Stone stone, uvec4 region_state, int triangle, vec3 position, vec3 direction) {
	int region = triangle < 0 || stone.ranges1.z == 0 ? 0 : triangles[triangle].meta.w;
	uint bit = 1u << uint(region % 32);
	if (dot(direction, boundary_normal(stone, triangle, position)) < 0.0) { region_state[region / 32] |= bit; }
	else { region_state[region / 32] &= ~bit; }
	return region_state;
}

// Skip mathematical boundaries that do not change the physical medium.
// Used for primary coverage and visibility; transport processes each raw event
// separately so a sampled volume collision preserves the correct region_state set.
bool physical_boundary(Stone stone, vec3 origin, vec3 direction, uvec4 region_state,
		out float distance, out int triangle, out uvec4 state_after) {
	distance = 0.0;
	state_after=region_state;
	for (int event = 0; event < 4096; event++) {
		float segment;
		if (!boundary_hit(stone, origin, direction, segment, triangle)) { return false; }
		uvec4 after = cross_region(stone, region_state, triangle, origin + direction * segment, direction);
		distance += segment;
		if (region_medium(stone, region_state) != region_medium(stone, after)) { state_after=after; return true; }
		region_state = after;
		origin += direction * (segment + T_EPS * 4.0);
		distance += T_EPS * 4.0;
	}
	return false;
}

bool physical_hit(Stone stone, vec3 origin, vec3 direction, uvec4 region_state,
		out float distance, out int triangle) {
	uvec4 state_after;
	return physical_boundary(stone,origin,direction,region_state,distance,triangle,state_after);
}

bool body_entry(Stone stone, vec3 origin, vec3 direction, out float distance, out int surface) {
	if (stone.ranges1.z == 0) { return hull_entry(stone.ranges0.x, stone.ranges0.y, origin, direction, distance, surface); }
	int triangle;
	bool hit = physical_hit(stone, origin, direction, uvec4(0u), distance, triangle);
	surface = -1 - triangle;
	return hit;
}

vec3 body_normal(Stone stone, int surface, vec3 position) { return stone.ranges1.z == 0 ? planes[surface].n_d.xyz : boundary_normal(stone, -1 - surface, position); }
