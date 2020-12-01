#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require

#include "../shared.h"
#include "random.glsl"

layout(set = SWS_SCENE_AS_SET, binding = SWS_SCENE_AS_BINDING)            uniform accelerationStructureEXT Scene;
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

layout(location = SWS_LOC_PRIMARY_RAY) rayPayloadEXT RayPayload PrimaryRay;
layout(location = SWS_LOC_INDIRECT_RAY) rayPayloadInEXT IndirectRayPayload indirectRay;
layout(location = SWS_LOC_INDIRECT_RAY2) rayPayloadInEXT IndirectRayPayload indirectRay2;

hitAttributeEXT vec2 HitAttribs;
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
	//const vec2 uv = BaryLerp(v0.uv.xy, v1.uv.xy, v2.uv.xy, barycentrics);
	//closestHit.difColor = PrimaryRay.accColor.xyzw;
	closestHit.matColor = meshInfoArray[objId].info[0];

	closestHit.kd = meshInfoArray[objId].info[1].x;
	closestHit.ks = meshInfoArray[objId].info[1].y;
	closestHit.mat = int(meshInfoArray[objId].info[1].z);
	closestHit.emittance = vec3(meshInfoArray[objId].info[1].w);//just for now

	closestHit.pos = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;

	return closestHit;
}
vec3 shootRay(vec3 rayOrigin, vec3 rayDirection, float min, float max)
{
	const uint rayFlags = gl_RayFlagsOpaqueEXT;// gl_RayFlagsNoneEXT; ;// gl_RayFlagsOpaqueEXT;

	const uint cullMask = 0xFF;
	const uint stbRecordStride = 1;
	const float tmin = min;
	const float tmax = max;// Camera.nearFarFov.y;
	indirectRay2.rndSeed = indirectRay.rndSeed;
	traceRayEXT(Scene,
		rayFlags,
		cullMask,
		SWS_INDIRECT_HIT_SHADERS_IDX,
		stbRecordStride,
		SWS_INDIRECT_MISS_SHADERS_IDX,
		rayOrigin,
		tmin,
		rayDirection,
		tmax,
		SWS_LOC_INDIRECT_RAY2);

	indirectRay.rndSeed=indirectRay2.rndSeed;
	return indirectRay2.hitValue;

}

void main() {
	indirectRay.isMiss = false;
	if (indirectRay.rayDepth > MAX_PATH_DEPTH)
		indirectRay.hitValue = vec3(0);
	else
	{
		const uint objId = gl_InstanceCustomIndexEXT;
		ShadingData hit = getHitShadingData(objId);
		//https://en.wikipedia.org/wiki/Path_tracing
	    //https://www.scratchapixel.com/lessons/3d-basic-rendering/global-illumination-path-tracing/global-illumination-path-tracing-practical-implementation
		//vec3 directLightContrib = DiffuseShade(hit.pos, hit.normal, hit.matColor.xyz, hit.kd, hit.ks);
	    // Pick a random direction from here and keep going.
		vec3 tangent, bitangent;
		createCoordinateSystem(hit.normal, tangent, bitangent);
		//the newRay
		vec3 rayOrigin = hit.pos;
		vec3 rayDirection = samplingHemisphere(PrimaryRay.rndSeed, tangent, bitangent, hit.normal);

		// Probability of the newRay
		const float pdf = 1.0 / (2.0 * M_PI);

		vec3 albedo = hit.matColor.xyz;
		// Compute the BRDF for this ray (assuming Lambertian reflection)
		float cos_theta = dot(rayDirection, hit.normal);
		vec3 BRDF = albedo / M_PI;


		indirectRay.rayOrigin = rayOrigin;
		indirectRay.rayDir = rayDirection;
		vec3 incoming = hit.emittance;
		vec3 weight = indirectRay.weight;
		// Recursively trace reflected light sources.
		if (indirectRay.rayDepth + 1.0 < MAX_PATH_DEPTH)
		{
			indirectRay.weight *= (BRDF * cos_theta / pdf);
			indirectRay.rayDepth++;
			incoming = shootRay(indirectRay.rayOrigin, indirectRay.rayDir, 0.0001, 10000.0);
		}
		// Apply the Rendering Equation here.
		indirectRay.hitValue = hit.emittance + (incoming * weight);
	}
}