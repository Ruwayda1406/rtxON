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

layout(set = SWS_LIGHTS_SET, binding = 0, std430) readonly buffer lightsBuffer {
	LightTriangle lightTriangles[];
};

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
layout(location = SWS_LOC_SHADOW_RAY)  rayPayloadEXT ShadowRayPayload ShadowRay;

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
	closestHit.pos = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;
	closestHit.matColor = meshInfoArray[objId].info[0];

	closestHit.kd = meshInfoArray[objId].info[1].x;
	closestHit.ks = meshInfoArray[objId].info[1].y;
	closestHit.mat = int(meshInfoArray[objId].info[1].z);
	closestHit.emittance = vec3(meshInfoArray[objId].info[1].w);




	return closestHit;
}
bool shootShadowRay(vec3 shadowRayOrigin, vec3 dirToLight, float min, float distToLight)
{
	const uint shadowRayFlags = gl_RayFlagsNoOpaqueEXT | gl_RayFlagsSkipClosestHitShaderEXT;
	const uint cullMask = 0xFF;
	const uint stbRecordStride = 1;
	const float tmin = min;
	const float tmax = distToLight;
	ShadowRay.isShadowed = true;
	traceRayEXT(Scene,
		shadowRayFlags,
		cullMask,
		SWS_SHADOW_HIT_SHADERS_IDX,
		stbRecordStride,
		SWS_SHADOW_MISS_SHADERS_IDX,
		shadowRayOrigin,
		0.0f,
		dirToLight,
		tmax,
		SWS_LOC_SHADOW_RAY);
	return ShadowRay.isShadowed;

}
vec3 getLightPos(int LightType, inout uint seed)
{
	/*int useSun = int(Params.SunPos.w);
	if (useSun == 0)//random
	{
		int nLightTriangles = int(Params.LightInfo.z);
		float r0 = nextRand(seed)*nLightTriangles;
		int randomTriangleIdx = int(clamp(r0, 0, nLightTriangles));
		LightTriangle lightT = lightTriangles[randomTriangleIdx];
		return randomPointInTriangle(seed, lightT.v0, lightT.v1, lightT.v2);
	}
	else*/
	{
		
		if (LightType == 0)
			return Params.SunPos.xyz;;

		//softshadow
		float r1 = nextRand(seed);
		float r2 = nextRand(seed);
		float r3 = nextRand(seed);
		return Params.SunPos.xyz + vec3(r1, r2, r3);
	}
}
vec3 DiffuseShade(vec3 HitPosition, vec3 HitNormal, vec3 HitMatColor, float kd, float ks)
{

	int LightType = int(Params.LightInfo.x);
	uint seed = indirectRay.rndSeed;
	// Get information about this light; access your framework’s scene structs
	vec3 hitValues = vec3(0);
	vec3 lightPos = getLightPos(LightType, seed);
	float lightIntensity = 1.0;
	vec3 dirToLight = normalize(lightPos - vec3(0));
	float distToLight = 10000;

	// Diffuse
	vec3 diffuse = computeDiffuse(dirToLight, HitNormal, vec3(kd), HitMatColor);

	// Tracing shadow ray only if the light is visible from the surface
	vec3  specular = vec3(0);
	float attenuation = 1;
	float rayColor = 0.0;
	float LdotN = dot(HitNormal, dirToLight);
	if (LdotN > 0.0)
	{


		const vec3 shadowRayOrigin = HitPosition + HitNormal * 0.001f;

		ShadowRay.attenuation = attenuation;
		bool isShadowed = shootShadowRay(shadowRayOrigin, dirToLight, 0.001, distToLight);
		attenuation = ShadowRay.attenuation;

		if (isShadowed)
		{
			specular = vec3(0);
		}
		else
		{
			specular = computeSpecular(gl_WorldRayDirectionEXT, dirToLight, HitNormal, vec3(ks), 100.0);
		}
	}

	hitValues += vec3(attenuation * lightIntensity * (diffuse + specular));

	return hitValues;
}
vec3 shootRay(vec3 rayOrigin, vec3 rayDirection, int depth)
{

	const uint rayFlags = gl_RayFlagsOpaqueEXT;
	const uint cullMask = 0xFF;
	const uint stbRecordStride = 1;
	const float tmin = 0.001;
	const float tmax = 1000000.0;;
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
void DiffuseBRDF(ShadingData hit)
{
	if (hit.emittance.x == 1.0)
	{
		indirectRay.hitValue = hit.emittance;
		indirectRay.rayDepth = MAX_PATH_DEPTH;
		return;
	}

	//https://en.wikipedia.org/wiki/Path_tracing
	// Pick a random direction from here and keep going.
	vec3 tangent, bitangent;
	createCoordinateSystem(hit.normal, tangent, bitangent);
	//the newRay Direction
	vec3 rayOrigin = hit.pos+ hit.normal*0.0001;
	vec3 rayDirection = samplingHemisphere(indirectRay.rndSeed, tangent, bitangent, hit.normal);

	// Accumulate the material color.
	//const float cos_theta = max(0.0f, dot(rayDirection, hit.normal));
	const float cos_theta = dot(rayDirection, hit.normal);
	// Probability of the newRay (cosine distributed)
	const float pdf = 1.0 / (2.0*M_PI);
	// Compute the BRDF for this ray (assuming Lambertian reflection)
	const vec3 brdf = hit.matColor.xyz * (1.0 /M_PI);
	//vec3 weight = indirectRay.weight;

	indirectRay.weight *= (brdf / pdf) * cos_theta;
	///////////////////////////////////////////////
	indirectRay.rayOrigin = rayOrigin;
	indirectRay.rayDir = rayDirection;
	indirectRay.hitValue = hit.emittance;

	vec3 reflected = vec3(0);
	// Recursively trace reflected light sources.
	if (indirectRay.rayDepth < MAX_PATH_DEPTH)
	{	
		reflected = shootRay(indirectRay.rayOrigin, indirectRay.rayDir, indirectRay.rayDepth+1);
	}
	// Apply the Rendering Equation here.
	indirectRay.hitValue = (hit.emittance + (reflected * (brdf / pdf) * cos_theta));
}
void SpecularBRDF(ShadingData hit)
{

	if (hit.emittance.x == 1.0)
	{
		indirectRay.hitValue = hit.emittance;
		indirectRay.rayDepth = MAX_PATH_DEPTH;
		return;
	}
	//the newRay Direction
	vec3 rayOrigin = hit.pos + hit.normal*0.0001;
	vec3 rayDirection = reflection(gl_WorldRayDirectionEXT, hit.normal);

	float cos_theta = dot(rayDirection, hit.normal);
	// Probability of the newRay (cosine distributed)
	const float pdf = 1.0 / (2.0*M_PI);
	// Compute the BRDF for this ray (assuming Lambertian reflection)
	const vec3 brdf =  vec3(1.0 / M_PI);

	indirectRay.rayOrigin = rayOrigin;
	indirectRay.rayDir = rayDirection;
	indirectRay.weight *= (brdf / pdf) * cos_theta;
	indirectRay.hitValue = hit.emittance;

	vec3 reflected = vec3(0);
	// Recursively trace reflected light sources.
	if (indirectRay.rayDepth < MAX_PATH_DEPTH)
	{
		reflected = shootRay(indirectRay.rayOrigin, indirectRay.rayDir, indirectRay.rayDepth + 1);
	}
	// Apply the Rendering Equation here.
	indirectRay.hitValue = hit.emittance + (reflected *(brdf / pdf) * cos_theta);
}
void main() {
	indirectRay.isMiss = false;
	if (indirectRay.rayDepth >= MAX_PATH_DEPTH) {
		indirectRay.hitValue = vec3(0.001);
		return;
	}
	else
	{
		const uint objId = gl_InstanceCustomIndexEXT;
		ShadingData hit = getHitShadingData(objId);

		// Russian roulette: starting at depth 5, each recursive step will stop with a probability of 0.1
		float rrFactor = 1.0;
		if (indirectRay.rayDepth > MAX_PATH_DEPTH / 2.0) {
			const float rrStopProbability = 0.1;
			uint seed = indirectRay.rndSeed;
			float r = nextRand(seed);
			if (r <= rrStopProbability) {
				return;
			}
			rrFactor = 1.0 / (1.0 - rrStopProbability);
		}
		if (hit.mat == 3)
		{
			// Specular BRDF - one incoming direction & one outgoing direction, that is, the perfect reflection direction.
			SpecularBRDF(hit);
		}
		else //if (hit.mat == 0)
		{
			// Diffuse BRDF - choose an outgoing direction with hemisphere sampling.
			DiffuseBRDF(hit);
		}
		
		
	}
}