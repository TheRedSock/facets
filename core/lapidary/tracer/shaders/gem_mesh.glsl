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

bool body_entry(Stone stone, vec3 origin, vec3 direction, out float distance, out int surface) {
	if (stone.ranges1.z == 0) { return hull_entry(stone.ranges0.x, stone.ranges0.y, origin, direction, distance, surface); }
	int triangle;
	bool hit = mesh_hit(stone.ranges1.z - 1, origin, direction, distance, triangle);
	surface = -1 - triangle;
	return hit;
}

vec3 body_normal(int surface) { return surface >= 0 ? planes[surface].n_d.xyz : mesh_normal(-1 - surface); }
