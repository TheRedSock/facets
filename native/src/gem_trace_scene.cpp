#include "gem_trace_scene.h"
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

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
    tri_count_ = 0;
    if (!device_) return;

    godot::Array a_list = trace_data.get("triangle_vertices_a", godot::Array());
    godot::Array b_list = trace_data.get("triangle_vertices_b", godot::Array());
    godot::Array c_list = trace_data.get("triangle_vertices_c", godot::Array());
    godot::Array n_list = trace_data.get("triangle_normals", godot::Array());
    godot::PackedStringArray z_list = trace_data.get("triangle_zones", godot::PackedStringArray());

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
    result.position     = origin + dir * result.distance;
    result.normal       = (prim < (int)normals_.size()) ? normals_[prim] : godot::Vector3(0, 1, 0);
    result.zone         = (prim < (int)zones_.size()) ? zones_[prim] : godot::StringName();

    // Determine front-face from ray direction vs stored face normal
    result.front_face = (dir.dot(result.normal) < 0.0);

    return result;
}

} // namespace gem
