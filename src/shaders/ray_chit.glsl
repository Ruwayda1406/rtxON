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

layout(location = SWS_LOC_PRIMARY_RAY) rayPayloadInEXT RayPayload PrimaryRay;
layout(location = SWS_LOC_SHADOW_RAY)  rayPayloadEXT ShadowRayPayload ShadowRay;

hitAttributeEXT vec2 HitAttribs;


vec3 computeDiffuse(vec3 lightDir, vec3 normal, vec3 kd, vec3 ambient)
{
	// Lambertian
	float NdotL = max(dot(normal, lightDir), 0.0);
	//float NdotL = clamp(dot(normal, lightDir), 0.0, 1.0); // In range [0..1]
	return (ambient + (kd * NdotL));
}

vec3 computeSpecular(vec3 viewDir, vec3 lightDir, vec3 normal, vec3 ks, float shininess)
{
	// Compute specular only if not in shadow
	vec3        V = normalize(-viewDir);
	vec3        R = reflect(-lightDir, normal);
	float	VdotR = max(dot(V, R), 0.0);// clamp(dot(V, R), 0.0, 1.0); // In range [0..1]
	float       specular = pow(VdotR, shininess);
	return vec3(ks * specular);
}
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
vec3 DiffuseShade(vec3 HitPosition, vec3 HitNormal, vec3 HitMatColor, float kd, float ks)
{
	// Get information about this light; access your framework’s scene structs
	int LightCount = int(Params.LightInfo.x);
	int LightType = int(Params.LightInfo.z);
	float ShadowAttenuation = Params.LightInfo.y;
	vec3 hitValues = vec3(0);
	for (int i = 0; i < Params.LightInfo.x; i++)//SoftShadows
	{

		

		vec3 lightPos = Params.LightSource[i].xyz;
		vec3 dirToLight;
		float distToLight, lightIntensity;
		if (LightType == 0)// Point light
		{
			dirToLight = normalize(lightPos - HitPosition);
			distToLight = length(lightPos - HitPosition);
			lightIntensity = Params.LightSource[i].w / (distToLight * distToLight);
		}
		else  // Directional light
		{
			dirToLight = normalize(lightPos - vec3(0)); 
			distToLight = 10000;
			lightIntensity = 1.0;
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

			bool isShadowed = shootShadowRay(shadowRayOrigin, dirToLight, 0.001, distToLight);
			if (isShadowed)
			{
				attenuation = 0.3;
				specular = vec3(0);
			}
			else
			{
				attenuation = 1.0;
				specular = computeSpecular(gl_WorldRayDirectionEXT, dirToLight, HitNormal, vec3(ks), 100.0);
			}
		}

		hitValues += vec3(attenuation * lightIntensity * (diffuse + specular));
	}

	vec3 finalcolor = hitValues / float(LightCount);
	return finalcolor;
}
vec3 getRefractionNormal(vec3 I, vec3 N)
{
	//https://www.scratchapixel.com/lessons/3d-basic-rendering/introduction-to-shading/reflection-refraction-fresnel
	float cosi = clamp(-1, 1, dot(I, N));//NdotD

	vec3 refrNormal;
	if (cosi < 0)
	{
		refrNormal = N;
	}
	else {
		refrNormal = -N;
	}
	return refrNormal;
}
float getRefractionEta(vec3 I, vec3 N, float k)//ior=index of refraction 
{
	float cosi = clamp(-1, 1, dot(I, N));
	float refrEta;
	if (cosi < 0)
	{
		refrEta = k;
	}
	else { 
		refrEta = 1.0/k;
	}
	return refrEta;
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
		vec3 rayDir = reflect(gl_WorldRayDirectionEXT, hit.normal);
		PrimaryRay.attenuation *= hit.ks;
		PrimaryRay.done = false;
		PrimaryRay.rayOrigin = origin;
		PrimaryRay.rayDir = rayDir;
	}
	else if (hit.mat == 2)
	{
		float k_glass = 1.5;
		float NdotD = dot(hit.normal, gl_WorldRayDirectionEXT);
		float cosi = clamp(-1, 1, NdotD);

		vec3 refrNormal = getRefractionNormal(gl_WorldRayDirectionEXT, hit.normal);
		float refrEta = getRefractionEta(gl_WorldRayDirectionEXT, hit.normal, k_glass);

		vec3 origin = hit.pos;
		vec3 rayDir = refract(gl_WorldRayDirectionEXT, refrNormal, refrEta);
		PrimaryRay.done = false;
		PrimaryRay.rayOrigin = origin;
		PrimaryRay.rayDir = rayDir;
	}
}
/*
vec3 reflection(vec3 I, vec3 N)
{
	return I - 2.0 * dot(I, N) * N;
}


vec3 refract(vec3 I, vec3 N, float eta)
{
	float cosi=dot(N, I);
    float k = 1 - eta * eta * (1 - cosi * cosi);
	return k < 0 ? 0 : eta * I + (eta * cosi - sqrtf(k)) * n;
}
*/