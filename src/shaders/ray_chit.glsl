#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require

#include "../shared_with_shaders.h"

layout(set = SWS_ATTRIBS_SET, binding = 0, std430) readonly buffer AttribsBuffer {
	VertexAttribute VertexAttribs[];
} AttribsArray[];

layout(set = SWS_FACES_SET, binding = 0, std430) readonly buffer FacesBuffer {
	ivec3 Faces[];
} FacesArray[];

layout(location = SWS_LOC_PRIMARY_RAY) rayPayloadInEXT RayPayload PrimaryRay;

hitAttributeEXT vec2 HitAttribs;

void main() {
	
	// Object of this instance
	const uint objId = gl_InstanceCustomIndexEXT;// scnDesc.i[gl_InstanceID].objId;

	// Indices of the triangle
	const ivec3 face = FacesArray[nonuniformEXT(objId)].Faces[gl_PrimitiveID];

	// Vertex of the triangle
	VertexAttribute v0 = AttribsArray[nonuniformEXT(objId)].VertexAttribs[face.x];
	VertexAttribute v1 = AttribsArray[nonuniformEXT(objId)].VertexAttribs[face.y];
	VertexAttribute v2 = AttribsArray[nonuniformEXT(objId)].VertexAttribs[face.z];

	const vec3 barycentrics = vec3(1.0f - HitAttribs.x - HitAttribs.y, HitAttribs.x, HitAttribs.y);

	// Computing the normal at hit position
	const vec3 normal = normalize(BaryLerp(v0.normal.xyz, v1.normal.xyz, v2.normal.xyz, barycentrics));
	//const vec2 uv = BaryLerp(v0.uv.xy, v1.uv.xy, v2.uv.xy, barycentrics);
	// interpolate our vertex attribs
	//vec3 worldPos = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;

	// Computing the coordinates of the hit position
	//vec3 worldPos = v0.pos * barycentrics.x + v1.pos * barycentrics.y + v2.pos * barycentrics.z;
	// Transforming the position to world space
	//worldPos = vec3(scnDesc.i[gl_InstanceID].transfo * vec4(worldPos, 1.0));

	const vec3 texel = vec3(1, 0, 0);
	PrimaryRay.color = texel;
	PrimaryRay.normal = normal;
	PrimaryRay.dist = gl_HitTEXT;
	PrimaryRay.objId = int(objId);
	//PrimaryRay.hitValue = vec3(lightIntensity * (diffuse + specular));
}

