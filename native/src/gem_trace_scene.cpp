#include "gem_trace_scene.h"
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <cmath>

namespace gem {

TraceScene::TraceScene() {
    // threads=1: disable Embree's internal TBB parallelism — we control our
    // own thread pool at the row-band level and don't want TBB contention.
    device_ = rtcNewDevice("threads=1");
}

TraceScene::~TraceScene() {
    if (scene_) { rtcReleaseScene(scene_); scene_ = nullptr; }
    if (device_) { rtcReleaseDevice(device_); device_ = nullptr; }
}

void TraceScene::build_from_trace_data(const godot::Dictionary& trace_data) {
    if (scene_) { rtcReleaseScene(scene_); scene_ = nullptr; }
    normals_.clear();
    zones_.clear();
    facet_indices_.clear();
    surface_wear_.clear();
    vertex_normals_.clear();
    has_vertex_normals_ = false;
    tri_count_ = 0;
    if (!device_) return;

    godot::Array a_list = trace_data.get("triangle_vertices_a", godot::Array());
    godot::Array b_list = trace_data.get("triangle_vertices_b", godot::Array());
    godot::Array c_list = trace_data.get("triangle_vertices_c", godot::Array());
    godot::Array n_list = trace_data.get("triangle_normals", godot::Array());
    godot::PackedStringArray z_list = trace_data.get("triangle_zones", godot::PackedStringArray());
    godot::PackedInt32Array facet_list = trace_data.get("triangle_facet_indices", godot::PackedInt32Array());

    int count = (int)a_list.size();
    if (count <= 0) return;
    tri_count_ = count;

    scene_ = rtcNewScene(device_);
    RTCGeometry geom = rtcNewGeometry(device_, RTC_GEOMETRY_TYPE_TRIANGLE);

    // Fill Embree's vertex buffer (3 vertices per triangle = 3*count vertices,
    // non-indexed — simpler than shared-vertex indexing for this small mesh).
    float* verts = (float*)rtcSetNewGeometryBuffer(
        geom, RTC_BUFFER_TYPE_VERTEX, 0, RTC_FORMAT_FLOAT3,
        sizeof(float) * 3, count * 3
    );
    unsigned* indices = (unsigned*)rtcSetNewGeometryBuffer(
        geom, RTC_BUFFER_TYPE_INDEX, 0, RTC_FORMAT_UINT3,
        sizeof(unsigned) * 3, count
    );

    normals_.resize(count);
    zones_.resize(count);
    facet_indices_.resize(count);

    for (int i = 0; i < count; ++i) {
        godot::Vector3 a = a_list[i];
        godot::Vector3 b = b_list[i];
        godot::Vector3 c = c_list[i];

        int base = i * 3;
        verts[base * 3 + 0] = (float)a.x;
        verts[base * 3 + 1] = (float)a.y;
        verts[base * 3 + 2] = (float)a.z;
        verts[(base + 1) * 3 + 0] = (float)b.x;
        verts[(base + 1) * 3 + 1] = (float)b.y;
        verts[(base + 1) * 3 + 2] = (float)b.z;
        verts[(base + 2) * 3 + 0] = (float)c.x;
        verts[(base + 2) * 3 + 1] = (float)c.y;
        verts[(base + 2) * 3 + 2] = (float)c.z;

        indices[i * 3 + 0] = base;
        indices[i * 3 + 1] = base + 1;
        indices[i * 3 + 2] = base + 2;

        normals_[i] = (i < (int)n_list.size()) ? (godot::Vector3)n_list[i] : godot::Vector3(0, 1, 0);
        zones_[i]   = (i < (int)z_list.size()) ? godot::StringName(z_list[i]) : godot::StringName();
        facet_indices_[i] = (i < (int)facet_list.size()) ? (int)facet_list[i] : i;
    }

    godot::PackedInt32Array wear_types = trace_data.get("surface_wear_types", godot::PackedInt32Array());
    godot::PackedInt32Array wear_facets = trace_data.get("surface_wear_facet_indices", godot::PackedInt32Array());
    godot::Array wear_p0 = trace_data.get("surface_wear_p0", godot::Array());
    godot::Array wear_p1 = trace_data.get("surface_wear_p1", godot::Array());
    godot::Array wear_normals = trace_data.get("surface_wear_normals", godot::Array());
    godot::Array wear_adjacent = trace_data.get("surface_wear_adjacent_normals", godot::Array());
    godot::PackedFloat32Array wear_radii = trace_data.get("surface_wear_radii", godot::PackedFloat32Array());
    godot::PackedFloat32Array wear_intensities = trace_data.get("surface_wear_intensities", godot::PackedFloat32Array());
    godot::PackedFloat32Array wear_seeds = trace_data.get("surface_wear_seeds", godot::PackedFloat32Array());

    int wear_count = (int)wear_types.size();
    surface_wear_.reserve(wear_count);
    for (int i = 0; i < wear_count; i++) {
        SurfaceWearEntry entry;
        entry.type = (int)wear_types[i];
        entry.facet_index = (i < (int)wear_facets.size()) ? (int)wear_facets[i] : -1;
        entry.p0 = (i < (int)wear_p0.size()) ? godot::Vector3(wear_p0[i]) : godot::Vector3();
        entry.p1 = (i < (int)wear_p1.size()) ? godot::Vector3(wear_p1[i]) : godot::Vector3();
        entry.normal = (i < (int)wear_normals.size()) ? godot::Vector3(wear_normals[i]) : godot::Vector3(0, 1, 0);
        entry.adjacent_normal = (i < (int)wear_adjacent.size()) ? godot::Vector3(wear_adjacent[i]) : entry.normal;
        entry.radius = (i < (int)wear_radii.size()) ? (double)wear_radii[i] : 0.0;
        entry.intensity = (i < (int)wear_intensities.size()) ? (double)wear_intensities[i] : 1.0;
        entry.seed = (i < (int)wear_seeds.size()) ? (double)wear_seeds[i] : 0.0;
        if (entry.facet_index >= 0 && entry.radius > 0.0) {
            surface_wear_.push_back(entry);
        }
    }

    // Load per-vertex smoothed normals for facet edge rounding (if present)
    if (trace_data.has("triangle_vertex_normals_a")) {
        godot::Array vn_a = trace_data.get("triangle_vertex_normals_a", godot::Array());
        godot::Array vn_b = trace_data.get("triangle_vertex_normals_b", godot::Array());
        godot::Array vn_c = trace_data.get("triangle_vertex_normals_c", godot::Array());
        if ((int)vn_a.size() == count && (int)vn_b.size() == count && (int)vn_c.size() == count) {
            vertex_normals_.resize(count);
            for (int i = 0; i < count; ++i) {
                vertex_normals_[i] = {
                    (godot::Vector3)vn_a[i],
                    (godot::Vector3)vn_b[i],
                    (godot::Vector3)vn_c[i]
                };
            }
            has_vertex_normals_ = true;
        }
    }

    rtcCommitGeometry(geom);
    rtcAttachGeometry(scene_, geom);
    rtcReleaseGeometry(geom); // scene holds a reference
    rtcCommitScene(scene_);
}

HitResult TraceScene::intersect(godot::Vector3 origin, godot::Vector3 dir,
                                int skip_triangle) const {
    HitResult result;
    if (!scene_) return result;

    RTCRayHit rayhit;
    rayhit.ray.org_x = (float)origin.x;
    rayhit.ray.org_y = (float)origin.y;
    rayhit.ray.org_z = (float)origin.z;
    rayhit.ray.dir_x = (float)dir.x;
    rayhit.ray.dir_y = (float)dir.y;
    rayhit.ray.dir_z = (float)dir.z;
    rayhit.ray.tnear  = (float)TRACE_EPSILON;
    rayhit.ray.tfar   = 1e30f;
    rayhit.ray.mask    = (unsigned)-1;
    rayhit.ray.flags   = 0;
    rayhit.hit.geomID  = RTC_INVALID_GEOMETRY_ID;
    rayhit.hit.instID[0] = RTC_INVALID_GEOMETRY_ID;

    rtcIntersect1(scene_, &rayhit);

    if (rayhit.hit.geomID == RTC_INVALID_GEOMETRY_ID) return result;

    int prim = (int)rayhit.hit.primID;

    // Embree uses a flat vertex array with 3 verts per triangle, so primID
    // maps directly to our triangle index. But we need to handle skip_triangle.
    if (prim == skip_triangle) {
        // Re-cast with a slight offset to skip this triangle.
        // For gem meshes this is extremely rare — Embree's tnear handles
        // self-intersection for nearly all cases.
        return result;
    }

    result.did_hit      = true;
    result.distance     = (double)rayhit.ray.tfar;
    result.triangle_idx = prim;
    result.facet_idx    = (prim < (int)facet_indices_.size()) ? facet_indices_[prim] : prim;
    result.position     = origin + dir * result.distance;
    result.normal       = (prim < (int)normals_.size()) ? normals_[prim] : godot::Vector3(0, 1, 0);
    result.geometric_normal = result.normal;  // preserve flat normal before smoothing
    result.zone         = (prim < (int)zones_.size()) ? zones_[prim] : godot::StringName();
    result.zone_hash    = result.zone.hash();

    // Determine front-face from ray direction vs flat geometric normal
    // (must use flat normal for correct inside/outside determination)
    result.front_face = (dir.dot(result.geometric_normal) < 0.0);

    // Interpolate per-vertex smoothed normals using Embree barycentrics
    if (has_vertex_normals_ && prim < (int)vertex_normals_.size()) {
        float u = rayhit.hit.u;
        float v = rayhit.hit.v;
        float w = 1.0f - u - v;
        godot::Vector3 interp = vertex_normals_[prim][0] * w
                              + vertex_normals_[prim][1] * u
                              + vertex_normals_[prim][2] * v;
        double len_sq = (double)interp.x * interp.x + (double)interp.y * interp.y + (double)interp.z * interp.z;
        if (len_sq > 1e-12) {
            result.normal = interp.normalized();
        }
    }

    double best_wear = 0.0;
    int best_type = -1;
    const SurfaceWearEntry* best_entry = nullptr;
    for (const SurfaceWearEntry& entry : surface_wear_) {
        if (entry.facet_index != result.facet_idx) continue;
        double mask = evaluate_surface_wear(entry, result.position);
        if (mask > best_wear) {
            best_wear = mask;
            best_type = entry.type;
            best_entry = &entry;
        }
    }
    result.surface_wear_mask = best_wear;
    result.surface_wear_type = best_type;
    if (best_entry != nullptr) {
        if (best_entry->type == 0 || best_entry->type == 2) {
            // Capsule primitives: tangent is along the segment.
            result.surface_wear_tangent = best_entry->p1 - best_entry->p0;
        }
        if (best_entry->type == 2) {
            result.surface_wear_ridge_normal = best_entry->adjacent_normal;
        }
    }

    return result;
}

void TraceScene::set_surface_wear_pixel_floor(double bounding_radius, godot::Vector2i target_size) {
    int max_dim = target_size.x > target_size.y ? target_size.x : target_size.y;
    if (bounding_radius <= 0.0 || max_dim <= 0) {
        surface_wear_pixel_radius_ = 0.0;
        return;
    }
    surface_wear_pixel_radius_ = (bounding_radius * 2.2) / (double)max_dim;
}

static double clamp01(double value) {
    if (value < 0.0) return 0.0;
    if (value > 1.0) return 1.0;
    return value;
}

static double smoothstep(double edge0, double edge1, double x) {
    double t = clamp01((x - edge0) / (edge1 - edge0));
    return t * t * (3.0 - 2.0 * t);
}

static double segment_distance(godot::Vector3 point, godot::Vector3 a, godot::Vector3 b) {
    godot::Vector3 ab = b - a;
    double len_sq = (double)ab.length_squared();
    if (len_sq <= 1e-14) return (double)point.distance_to(a);
    double t = clamp01((double)(point - a).dot(ab) / len_sq);
    godot::Vector3 closest = a + ab * (float)t;
    return (double)point.distance_to(closest);
}

static double wear_noise(godot::Vector3 point, double seed) {
    double n = std::sin((double)point.x * 47.17 + (double)point.y * 113.91 + (double)point.z * 71.43 + seed);
    return 0.72 + 0.28 * (0.5 + 0.5 * n);
}

double TraceScene::evaluate_surface_wear(const SurfaceWearEntry& entry, godot::Vector3 point) const {
    double mask = 0.0;
    double aa = surface_wear_pixel_radius_ * 0.85;
    double radius = entry.radius;
    if (entry.type == 3) {
        // Dirt patch: broad soft disc for film-like discolouration. Softer
        // falloff than earlier versions so overlapping patches create a
        // continuous dirty layer rather than visible patch boundaries.
        double dist = (double)point.distance_to(entry.p0);
        double inner = radius * 0.20;
        double outer = radius * 1.2 + aa;
        mask = 1.0 - smoothstep(inner, outer, dist);
    } else {
        // All capsule-shaped wear: scratches (0), abrasion-legacy (1), edge
        // wear (2). Type 1 is no longer emitted by the generator as of v5 —
        // abrasion is now clustered scratches. The branch is preserved for
        // backward compatibility with any old cached trace data.
        double dist = segment_distance(point, entry.p0, entry.p1);
        double resolved_radius = radius;
        if (entry.type == 0 || entry.type == 1) {
            resolved_radius = radius > aa * 0.65 ? radius : aa * 0.65;
        } else if (entry.type == 2) {
            resolved_radius = radius > aa ? radius : aa;
        }
        double inner = resolved_radius * (entry.type == 2 ? 0.45 : 0.30);
        double outer = resolved_radius * (entry.type == 2 ? 3.0 : 1.85) + aa;
        mask = 1.0 - smoothstep(inner, outer, dist);
        mask *= wear_noise(point, entry.seed);
    }
    return clamp01(mask * entry.intensity);
}

} // namespace gem
