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
void main() {

	// Initialize the random number
	uint seed = tea(gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x + gl_LaunchIDEXT.x, int(Params.modeFrame.y));
	vec3 hitValues = vec3(0);

	int NBSAMPLES = 20;	// monte carlo antialiasing
	for (int smpl = 0; smpl < NBSAMPLES; smpl++)
	{
		float r1 = rnd(seed);
		float r2 = rnd(seed);
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

		const uint rayFlags = gl_RayFlagsOpaqueEXT;

		const uint cullMask = 0xFF;
		const uint stbRecordStride = 1;
		const float tmin = 0.001;
		const float tmax = Camera.nearFarFov.y;


		vec3 finalColor = vec3(0.0f);
		traceRayEXT(Scene,
			rayFlags,
			cullMask,
			SWS_PRIMARY_HIT_SHADERS_IDX,
			stbRecordStride,
			SWS_PRIMARY_MISS_SHADERS_IDX,
			origin,
			tmin,
			direction,
			tmax,
			SWS_LOC_PRIMARY_RAY);

		const vec3 hitColor = PrimaryRay.color;
		hitValues += hitColor;
	}
	vec3 finalColor = hitValues / NBSAMPLES;


	imageStore(ResultImage, ivec2(gl_LaunchIDEXT.xy), vec4(finalColor, 1.0f));
}
