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
	const uint rayFlags = gl_RayFlagsOpaqueEXT;// gl_RayFlagsNoneEXT; ;// gl_RayFlagsOpaqueEXT;

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
	PrimaryRay.rndSeed = rndSeed;

	vec3 hitValue = vec3(0);
	for (int i = 0; i < SWS_MAX_RECURSION; i++)//for reflective material 
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
void main() {
	int mode = int(Params.modeFrame.x);
	float deltaTime = Params.modeFrame.y;

	////////////////////  directLighting ///////////////////////////////////////
	// First:: Do diffuse shading at the primary hit
	uint rndSeed = tea(gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x + gl_LaunchIDEXT.x, int(deltaTime));
	
	vec3 color;
	PrimaryRay.isIndirect = false;
	// monte carlo antialiasing
	vec3 hitValues = vec3(0);
	for (int smpl = 0; smpl < max_antialiasing_iter; smpl++)
	{
		float r1 = nextRand(rndSeed);
		float r2 = nextRand(rndSeed);
		// Subpixel jitter: send the ray through a different position inside the pixel
		// each time, to provide antialiasing.
		const vec2 uv = vec2(gl_LaunchIDEXT.xy) + vec2(r1, r2);
		const vec2 pixel = uv / (gl_LaunchSizeEXT.xy - 1.0);
		const float aspect = float(gl_LaunchSizeEXT.x) / float(gl_LaunchSizeEXT.y);


		// Initialize a ray structure for our ray tracer
		vec3 origin = Camera.pos.xyz;
		vec3 direction = CalcRayDir(pixel, aspect);
		vec3  hitValue = shootColorRay(origin, direction, 0.0001, 10000.0, rndSeed);
		hitValues += hitValue;

	}
	vec3 directLighting = hitValues / max_antialiasing_iter;
	color = directLighting;
		
	
	if(mode==2)  /////////////////////// indirectLigthing ///////////////////////////////////////
	{
		PrimaryRay.rndSeed = rndSeed;
		PrimaryRay.isIndirect = true;
		const vec2 uv = vec2(gl_LaunchIDEXT.xy);
		const vec2 pixel = uv / (gl_LaunchSizeEXT.xy - 1.0);
		const float aspect = float(gl_LaunchSizeEXT.x) / float(gl_LaunchSizeEXT.y);


		// Initialize a ray structure for our ray tracer
		vec3 origin = Camera.pos.xyz;
		vec3 direction = CalcRayDir(pixel, aspect);
		vec3 pathsColor = vec3(0);
		int hits = 0;
		////////////////// path tracing ////////////////////////
		for (int p = 0; p < MAX_PATHS; p++)
		{
			PrimaryRay.weight = vec3(0);
			PrimaryRay.rayDepth = 0;
			PrimaryRay.rayOrigin = origin.xyz;
			PrimaryRay.rayDir = direction.xyz;
			vec3 curWeight = vec3(1);
			for (; PrimaryRay.rayDepth < MaxRayDepth; PrimaryRay.rayDepth++)
			{
				vec3 value = shootColorRay(PrimaryRay.rayOrigin, PrimaryRay.rayDir, 0.0001, 10000.0, rndSeed);
				pathsColor += value * curWeight;
				curWeight *= PrimaryRay.weight;
			}
		}
		/////////////////////////////////////////////////////////////////////
		color *= pathsColor / float(MAX_PATHS);
	}
	imageStore(ResultImage, ivec2(gl_LaunchIDEXT.xy), vec4(color, 1.f));
}

/*
const vec2 pixelCenter = vec2(gl_LaunchIDEXT.xy) + vec2(0.5);
  const vec2 inUV        = pixelCenter / vec2(gl_LaunchSizeEXT.xy);
  vec2       d           = inUV * 2.0 - 1.0;

  vec4 origin    = cam.viewInverse * vec4(0, 0, 0, 1);
  vec4 target    = cam.projInverse * vec4(d.x, d.y, 1, 1);
  vec4 direction = cam.viewInverse * vec4(normalize(target.xyz), 0);
*/