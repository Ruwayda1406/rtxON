#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require

#include "../shared.h"
#include "random.glsl"

layout(set = SWS_SCENE_AS_SET, binding = SWS_SCENE_AS_BINDING)            uniform accelerationStructureEXT Scene;
layout(set = SWS_RESULT_IMAGE_SET, binding = SWS_RESULT_IMAGE_BINDING, rgba8) uniform image2D ResultImage;

layout(set = SWS_CAMDATA_SET, binding = SWS_CAMDATA_BINDING, std140)     uniform CameraData{
	CameraUniformParams Camera;
};

layout(set = SWS_UNIFORMPARAMS_SET, binding = SWS_UNIFORMPARAMS_BINDING, std140)     uniform AppData{
	UniformParams Params;
};

layout(location = SWS_LOC_PRIMARY_RAY) rayPayloadEXT RayPayload PrimaryRay;
vec3 CalcRayDir(vec2 pixel, float aspect) {

	vec3 w = Camera.dir.xyz;
	vec3 u = Camera.side.xyz;
	vec3 v = Camera.up.xyz;

	const float planeWidth = tan(Camera.nearFarFov.z* 0.5f);

	u *= (planeWidth * aspect);
	v *= planeWidth;

	const vec3 rayDir = normalize(w + (u * pixel.x) - (v * pixel.y));
	return rayDir;
}
vec3 shootColorRay(vec3 rayOrigin, vec3 rayDirection, float min, float max, uint rndSeed)
{
	const uint rayFlags = gl_RayFlagsNoOpaqueEXT;// gl_RayFlagsNoneEXT; ;// gl_RayFlagsOpaqueEXT;

	const uint cullMask = 0xFF;
	const uint stbRecordStride = 1;
	const float tmin = min;
	const float tmax = max;// Camera.nearFarFov.y;

	PrimaryRay.done = true;
	PrimaryRay.rayOrigin = rayOrigin.xyz;
	PrimaryRay.rayDir = rayDirection.xyz;
	PrimaryRay.color = vec3(0);
	PrimaryRay.attenuation = 1.f;
	PrimaryRay.accColor = vec4(0);

	vec3 hitValue = vec3(0);
	for (int i = 0; i < SWS_MAX_RECURSION; i++)
	{
		traceRayEXT(Scene,
			rayFlags,
			cullMask,
			SWS_PRIMARY_HIT_SHADERS_IDX,
			stbRecordStride,
			SWS_PRIMARY_MISS_SHADERS_IDX,
			rayOrigin,
			tmin,
			rayDirection,
			tmax,
			SWS_LOC_PRIMARY_RAY);

		hitValue += PrimaryRay.color * PrimaryRay.attenuation;

		if (PrimaryRay.done)
			break;

		rayOrigin = PrimaryRay.rayOrigin;
		rayDirection = PrimaryRay.rayDir;
		PrimaryRay.done = true;  // Will stop if a reflective material isn't hit
		PrimaryRay.accColor = vec4(0);
	}
	return hitValue;

}
vec3 getCosWeightedRandomDir(float r1, float r2, vec3 hitNormal)
{
	vec3 Nt, Nb;
	if (abs(hitNormal.x) > abs(hitNormal.y))
		Nt = normalize(vec3(hitNormal.z, 0, -hitNormal.x) / sqrt(hitNormal.x * hitNormal.x + hitNormal.z * hitNormal.z));
	else
		Nt = normalize(vec3(0, -hitNormal.z, hitNormal.y) / sqrt(hitNormal.y * hitNormal.y + hitNormal.z * hitNormal.z));
	Nb = cross(hitNormal, Nt);

	vec3 samp = uniformSampleHemisphere(r1, r2);
	vec3 giDir = vec3((samp.x * Nb.x + samp.y * hitNormal.x + samp.z * Nt.x),
		(samp.x * Nb.y + samp.y * hitNormal.y + samp.z * Nt.y),
		(samp.x * Nb.z + samp.y * hitNormal.z + samp.z * Nt.z));
	return normalize(giDir);
}
void main() {

	// First:: // Do diffuse shading at the primary hit
	// Initialize the random number
	uint rndSeed = tea(gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x + gl_LaunchIDEXT.x, int(Params.modeFrame.y));
	PrimaryRay.isIndirect = false;
	vec3 hitValues = vec3(0);
	int NBSAMPLES = 20;	// monte carlo antialiasing
	for (int smpl = 0; smpl < NBSAMPLES; smpl++)
	{
		float r1 = nextRand(rndSeed);
		float r2 = nextRand(rndSeed);
		// Subpixel jitter: send the ray through a different position inside the pixel
		// each time, to provide antialiasing.
		vec2 subpixel_jitter = int(Params.modeFrame.y) == 0 ? vec2(0.5f, 0.5f) : vec2(r1, r2);

		const vec2 uv = vec2(gl_LaunchIDEXT.xy) + subpixel_jitter;
		const vec2 pixel = uv / (gl_LaunchSizeEXT.xy - 1.0);
		const float aspect = float(gl_LaunchSizeEXT.x) / float(gl_LaunchSizeEXT.y);


		// Initialize a ray structure for our ray tracer
		//ray origin
		vec3 origin = Camera.pos.xyz;
		//ray direction;
		vec3 direction = CalcRayDir(pixel, aspect);
		vec3  hitValue = shootColorRay(origin, direction, 0.0001, 10000.0, rndSeed);
		hitValues += hitValue;

	}
	vec3 directLighting = hitValues / NBSAMPLES;
	vec3 color;
	if (PrimaryRay.isMiss == true)
	{
		color = directLighting;
	}
	else
	{
		vec3 hitNormal = PrimaryRay.normal;
		vec3 hitPos = PrimaryRay.pos;
		//Second:: global illumination indirect ray
		// Do indirect
		PrimaryRay.rndSeed = rndSeed;
		PrimaryRay.isIndirect = true;
		PrimaryRay.difColor = directLighting;

		// Pick random direction for global illumination indirect ray; shoot ray
		vec3 indirectLigthing = vec3(0);
		int MAX_GI_RAYS = 200;
		for (int smpl = 0; smpl < MAX_GI_RAYS; smpl++)
		{
			float r1 = nextRand(rndSeed);
			float r2 = nextRand(rndSeed);
			vec3 giDir = getCosWeightedRandomDir(r1, r2, hitNormal);
			vec3 giColor = shootColorRay(hitPos, giDir, 0.0001, 10000.0, rndSeed);
			// Accumulate properly weighted result into final color
			// Due to cosine-weighting, terms cancel, leaving simpler equation
			indirectLigthing += giColor;
		}
		color = directLighting * (indirectLigthing / float(MAX_GI_RAYS));
	}

	//Finally :::save the color ///////////////////////
	// Do accumulation over time
	/*if (int(Params.modeFrame.y) >= 0)
	{
		float a = 1.0f / float(Params.modeFrame.y + 1.0);
		vec3  old_color = imageLoad(ResultImage, ivec2(gl_LaunchIDEXT.xy)).xyz;
		imageStore(ResultImage, ivec2(gl_LaunchIDEXT.xy), vec4(mix(old_color, finalColor, a), 1.f));
	}
	else*/
	{
		//imageStore(ResultImage, ivec2(gl_LaunchIDEXT.xy), vec4((finalColor), 1.f));
		imageStore(ResultImage, ivec2(gl_LaunchIDEXT.xy), vec4(LinearToSrgb(color), 1.f));
	}
}
