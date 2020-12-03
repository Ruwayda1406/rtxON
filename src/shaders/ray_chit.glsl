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

layout(location = SWS_LOC_PRIMARY_RAY) rayPayloadInEXT RayPayload PrimaryRay;
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
vec3 getLightPos(int LightType,inout uint seed)
{
	if (LightType == 0)//random
	{
		int nLightTriangles = int(Params.LightInfo.z);
		float r0 = nextRand(seed)*nLightTriangles;
		int randomTriangleIdx = int(clamp(r0, 0, nLightTriangles));
		LightTriangle lightT = lightTriangles[randomTriangleIdx];
		return randomPointInTriangle(seed, lightT.v0, lightT.v1, lightT.v2);
	}
	else
	{
		return lightTriangles[0].v0;
	}
}
vec3 DiffuseShade(vec3 HitPosition, vec3 HitNormal, vec3 HitMatColor, float kd, float ks)
{
	// Get information about this light; access your framework’s scene structs
	int LightType = int(Params.LightInfo.x);
	vec3 hitValues = vec3(0);


	for (int j = 0; j < MAX_LIGHTS; j++)//SoftShadows
	{
		vec3 lightPos = getLightPos(LightType,PrimaryRay.rndSeed);//Params.LightPos.xyz + vec3(r1, r2,r3);
		vec3 dirToLight;
		float distToLight;
		float lightIntensity = Params.LightInfo.w;
		//if (LightType == 0)// Point light
		{
		//	dirToLight = normalize(lightPos - HitPosition);
		//	distToLight = length(lightPos - HitPosition);
			//lightIntensity = lightIntensity / (distToLight * distToLight);
		}
		//else  // Directional light
		{
			dirToLight = normalize(lightPos); 
			distToLight = length(lightPos);
			//distToLight = 10000;
		}
		//====================================================================
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
	}

	vec3 finalcolor = hitValues / float(MAX_LIGHTS);
	return finalcolor;
}
void main() {

	PrimaryRay.isMiss = false;
	const uint objId = gl_InstanceCustomIndexEXT;
	ShadingData hit = getHitShadingData(objId);

	PrimaryRay.hitValue = DiffuseShade(hit.pos, hit.normal, hit.matColor.xyz, hit.kd, hit.ks);
	PrimaryRay.matColor = hit.matColor.xyz;
	if (hit.mat == 3)// Reflection
	{
		vec3 origin = hit.pos;
		vec3 rayDir = reflection(gl_WorldRayDirectionEXT, hit.normal);
		PrimaryRay.attenuation *= hit.ks;
		PrimaryRay.done = false;
		PrimaryRay.rayOrigin = origin;
		PrimaryRay.rayDir = rayDir;
	}
}