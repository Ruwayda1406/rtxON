#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_EXT_nonuniform_qualifier : enable
#extension GL_EXT_scalar_block_layout : enable
#extension GL_GOOGLE_include_directive : enable
#include "../shared.h"
#include "random.glsl"


layout(location = SWS_LOC_SHADOW_RAY) rayPayloadInEXT ShadowRayPayload ShadowRay;

hitAttributeEXT vec2 HitAttribs;

layout(set = SWS_ATTRIBS_SET, binding = 0, std430) readonly buffer AttribsBuffer {
	VertexAttribute VertexAttribs[];
} AttribsArray[];

layout(set = SWS_FACES_SET, binding = 0, std430) readonly buffer FacesBuffer {
	uvec4 Faces[];
} FacesArray[];

layout(set = SWS_MESHINFO_SET, binding = 0, std430) readonly buffer meshInfoBuffer {
	vec4 info[];
} meshInfoArray[];

layout(set = SWS_CAMDATA_SET, binding = SWS_CAMDATA_BINDING, std140)     uniform CameraData{
	CameraUniformParams Camera;
};

layout(set = SWS_UNIFORMPARAMS_SET, binding = SWS_UNIFORMPARAMS_BINDING, std140)     uniform AppData{
	UniformParams Params;
};

ShadingData getHitShadingData(uint objId)
{
	ShadingData closestHit;
	// Indices of the triangle
	const uvec4 face = FacesArray[nonuniformEXT(gl_InstanceCustomIndexEXT)].Faces[gl_PrimitiveID];

	VertexAttribute v0 = AttribsArray[nonuniformEXT(gl_InstanceCustomIndexEXT)].VertexAttribs[int(face.x)];
	VertexAttribute v1 = AttribsArray[nonuniformEXT(gl_InstanceCustomIndexEXT)].VertexAttribs[int(face.y)];
	VertexAttribute v2 = AttribsArray[nonuniformEXT(gl_InstanceCustomIndexEXT)].VertexAttribs[int(face.z)];

	const vec3 barycentrics = vec3(1.0f - HitAttribs.x - HitAttribs.y, HitAttribs.x, HitAttribs.y);

	// Computing the normal at hit position
	closestHit.normal = normalize(BaryLerp(v0.normal.xyz, v1.normal.xyz, v2.normal.xyz, barycentrics));
	closestHit.matColor = meshInfoArray[objId].info[0];

	closestHit.kd = meshInfoArray[objId].info[1].x;
	closestHit.ks = meshInfoArray[objId].info[1].y;
	closestHit.mat = int(meshInfoArray[objId].info[1].z);
	closestHit.emittance = vec3(meshInfoArray[objId].info[1].w);

	closestHit.pos = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;

	return closestHit;
}
void main() {
	const uint objId = gl_InstanceCustomIndexEXT;
	float ShadowAttenuation = Params.LightInfo.y;
	ShadingData hit = getHitShadingData(objId);
	if (hit.matColor.w < 1.0)
	{
		ShadowRay.attenuation = mix(1.0, ShadowAttenuation, hit.matColor.w);
		ignoreIntersectionEXT();
	}
	else
		ShadowRay.attenuation = ShadowAttenuation;

}