#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require
#extension GL_ARB_shader_clock : enable

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
layout(location = SWS_LOC_INDIRECT_RAY) rayPayloadEXT IndirectRayPayload indirectRay;
vec3 CalcRayDir(vec2 pixel, float aspect) {

	pixel.x *= aspect* tan(Camera.nearFarFov.z / 2.0f);
	pixel.y *= tan(Camera.nearFarFov.z / 2.0f);

	const vec3 rayDir = normalize(Camera.dir.xyz + (Camera.side.xyz * pixel.x) - (Camera.up.xyz * pixel.y));
	return rayDir;
}
vec3 shootColorRay(vec3 rayOrigin, vec3 rayDirection, float min, float max)
{
	const uint rayFlags = gl_RayFlagsNoOpaqueEXT;// gl_RayFlagsNoneEXT; ;// gl_RayFlagsOpaqueEXT;

	const uint cullMask = 0xFF;
	const uint stbRecordStride = 1;
	const float tmin = min;
	const float tmax = max;// Camera.nearFarFov.y;

	//PrimaryRay.isTransparent = false;
	PrimaryRay.done = true;
	PrimaryRay.rayOrigin = rayOrigin.xyz;
	PrimaryRay.rayDir = rayDirection.xyz;
	PrimaryRay.hitValue = vec3(0);
	PrimaryRay.attenuation = 1.f;
	//PrimaryRay.accColor = vec4(0);
	

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

		hitValue += PrimaryRay.hitValue * PrimaryRay.attenuation;
		if (PrimaryRay.done)
			break;
		
		rayOrigin = PrimaryRay.rayOrigin;
		rayDirection = PrimaryRay.rayDir;
		PrimaryRay.done = true;  // Will stop if a reflective material isn't hit
		//PrimaryRay.accColor = vec4(0);
		//PrimaryRay.isTransparent = false;
	}
	return hitValue;

}
vec3 raytracer(uint rndSeed)
{

	// Do diffuse shading at the primary hit
	// monte carlo antialiasing
	vec3 hitValues = vec3(0);
	for (int smpl = 0; smpl < MAX_ANTIALIASING_ITER; smpl++)
	{
		float r1 = nextRand(rndSeed);
		float r2 = nextRand(rndSeed);
		// Subpixel jitter: send the ray through a different position inside the pixel
		// each time, to provide antialiasing.
		const vec2 uv = vec2(gl_LaunchIDEXT.xy) +vec2(r1, r2);
		const vec2 pixel = uv / (gl_LaunchSizeEXT.xy - 1.0);
		const float aspect = float(gl_LaunchSizeEXT.x) / float(gl_LaunchSizeEXT.y);


		// Initialize a ray structure for our ray tracer
		vec3 origin = Camera.pos.xyz;
		vec3 direction = CalcRayDir(pixel, aspect);

		PrimaryRay.rndSeed = rndSeed;
		hitValues += shootColorRay(origin, direction, 0.0001, 10000.0);
		rndSeed = PrimaryRay.rndSeed;

	}
	return ( hitValues / float(MAX_ANTIALIASING_ITER));
}
vec3 pathtracerLoop(vec3 origin,vec3 direction)
{
	////////////////// path tracing ////////////////////////
	const uint rayFlags = gl_RayFlagsOpaqueEXT;// gl_RayFlagsNoneEXT; 

	const uint cullMask = 0xFF;
	const uint stbRecordStride = 1;
	const float tmin = 0.001;
	const float tmax = 1000.0;
	vec3 hitValues = vec3(0);
	for (int p = 0; p < MAX_PATH_TRACED; p++)
	{

		vec3 rayOrigin = origin.xyz;
		vec3 rayDirection = direction.xyz;
		indirectRay.weight = vec3(0);
		indirectRay.rayDepth = 0;
		indirectRay.hitValue = vec3(0);
		vec3 curWeight = vec3(1);
		for (; indirectRay.rayDepth < MAX_PATH_DEPTH; indirectRay.rayDepth++)
		{

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

			hitValues += indirectRay.hitValue *curWeight;
			curWeight *= indirectRay.weight;
			rayOrigin = indirectRay.rayOrigin;
			rayDirection = indirectRay.rayDir;
		}

	}

	return (hitValues / float(MAX_PATH_TRACED));
}
vec3 pathtracer(uint rndSeed)
{
	// monte carlo antialiasing
	vec3 hitValues = vec3(0);
	for (int smpl = 0; smpl < MAX_ANTIALIASING_ITER; smpl++)
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

		indirectRay.rndSeed = rndSeed;
		hitValues += pathtracerLoop(origin, direction);
		rndSeed = indirectRay.rndSeed;

	}
	return (hitValues / float(MAX_ANTIALIASING_ITER));
}
void main() {
	int mode = int(Params.modeFrame.x);
	float deltaTime = Params.modeFrame.y;
	// Initialize the random number
	uint rndSeed = tea(gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x + gl_LaunchIDEXT.x, int(clockARB()));


	vec3 color = vec3(0.3);


	if (mode == 1)
	{
		color = raytracer(rndSeed);
	}
	else if (mode == 2)
	{
		color = pathtracer(rndSeed);
	}

	// Do accumulation over time
	if (deltaTime > 0)
	{
		float a = 1.0f / float(deltaTime + 1);
		vec3  old_color = imageLoad(ResultImage, ivec2(gl_LaunchIDEXT.xy)).xyz;
		imageStore(ResultImage, ivec2(gl_LaunchIDEXT.xy), vec4(mix(old_color, color, a), 1.f));
	}
	else
	{
		// First frame, replace the value in the buffer
		imageStore(ResultImage, ivec2(gl_LaunchIDEXT.xy), vec4(color, 1.f));
	}
}