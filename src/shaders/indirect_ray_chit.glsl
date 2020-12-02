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

layout(location = SWS_LOC_INDIRECT_RAY) rayPayloadInEXT IndirectRayPayload indirectRay;
//layout(location = SWS_LOC_INDIRECT_RAY2) rayPayloadInEXT IndirectRayPayload indirectRay2;

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
vec3 shootRay(vec3 rayOrigin, vec3 rayDirection, int depth)
{

	const uint rayFlags = gl_RayFlagsOpaqueEXT;
	const uint cullMask = 0xFF;
	const uint stbRecordStride = 1;
	const float tmin = 0.001;
	const float tmax = 100000000.0;
	indirectRay.rayDepth = depth;
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
		SWS_LOC_INDIRECT_RAY);

	return indirectRay.hitValue;

}
void DiffuseBRDF(vec3 rayOrigin, ShadingData hit)
{
	//https://en.wikipedia.org/wiki/Path_tracing
		//https://www.scratchapixel.com/lessons/3d-basic-rendering/global-illumination-path-tracing/global-illumination-path-tracing-practical-implementation
		//vec3 directLightContrib = DiffuseShade(hit.pos, hit.normal, hit.matColor.xyz, hit.kd, hit.ks);
		// Pick a random direction from here and keep going.
	vec3 tangent, bitangent;
	createCoordinateSystem(hit.normal, tangent, bitangent);
	//the newRay Direction
	vec3 rayDirection = samplingHemisphere(indirectRay.rndSeed, tangent, bitangent, hit.normal);

	// Probability of the newRay (cosine distributed)
	const float p = 1.0 / (2.0*M_PI);
	// Compute the BRDF for this ray (assuming Lambertian reflection)
	vec3 BRDF = hit.matColor.xyz / M_PI; 
	float cos_theta = dot(rayDirection, hit.normal);
	vec3 weight = (BRDF * cos_theta / p);


	indirectRay.rayOrigin = rayOrigin;
	indirectRay.rayDir = rayDirection;
	indirectRay.weight = weight;
	indirectRay.hitValue = hit.emittance;

	vec3 incoming = hit.emittance;
	// Recursively trace reflected light sources.
	if (indirectRay.rayDepth < MAX_PATH_DEPTH)
	{	
		incoming = shootRay(indirectRay.rayOrigin, indirectRay.rayDir, indirectRay.rayDepth+1);
	}
	// Apply the Rendering Equation here.
	indirectRay.hitValue = hit.emittance + (incoming * weight);
}
void main() {
	indirectRay.isMiss = false;
	if (indirectRay.rayDepth >= MAX_PATH_DEPTH) {
		indirectRay.hitValue = vec3(0.001);
		return;
	}
	else
	{
		// Russian roulette: starting at depth MAX_PATH_DEPTH, each recursive step will stop with a probability of 0.1
		const uint objId = gl_InstanceCustomIndexEXT;
		ShadingData hit = getHitShadingData(objId);
		vec3 rayOrigin = hit.pos;
		// Add the emission, the L_e(x,w) part of the rendering equation, but scale it with the Russian Roulette
	    // probability weight.

		//if (hit.mat == 0)
		{
			// Diffuse BRDF - choose an outgoing direction with hemisphere sampling.
			DiffuseBRDF(rayOrigin,hit);
		}
		
		
	}
}