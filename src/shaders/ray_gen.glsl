#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require

#include "../shared_with_shaders.h"

layout(set = SWS_SCENE_AS_SET, binding = SWS_SCENE_AS_BINDING)            uniform accelerationStructureEXT Scene;
layout(set = SWS_RESULT_IMAGE_SET, binding = SWS_RESULT_IMAGE_BINDING, rgba8) uniform image2D ResultImage;

layout(set = SWS_CAMDATA_SET, binding = SWS_CAMDATA_BINDING, std140)     uniform AppData{
	UniformParams Params;
};

layout(location = SWS_LOC_PRIMARY_RAY) rayPayloadEXT RayPayload PrimaryRay;


vec3 CalcRayDir(vec2 pixel, float aspect) {

	vec3 u = Params.camSide.xyz;
	vec3 v = Params.camUp.xyz;

	const float planeWidth = tan(Params.camFov* 0.5f);

	u *= (planeWidth * aspect);
	v *= planeWidth;

	const vec3 rayDir = normalize(Params.camDir.xyz + (u * pixel.x) - (v * pixel.y));
	return rayDir;
}
void main() {
	//auto u = double(i) / (image_width - 1);
	//auto v = double(j) / (image_height - 1);
	const vec2 pixel = gl_LaunchIDEXT.xy / (gl_LaunchSizeEXT.xy - 1.0);
	const float aspect = float(gl_LaunchSizeEXT.x) / float(gl_LaunchSizeEXT.y);

	// Initialize a ray structure for our ray tracer
	//ray origin
	vec3 origin = Params.camPos.xyz;
	//ray direction;
	vec3 direction = CalcRayDir(pixel, aspect);

	const uint rayFlags = gl_RayFlagsOpaqueEXT;
	const uint cullMask = 0xFF;
	const uint stbRecordStride = 1;
	const float tmin = 0.0f;
	const float tmax = Params.camFar;

	vec3 finalColor = vec3(0.0f);
	//for (int i = 0; i < SWS_MAX_RECURSION; ++i) {
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
		const float hitDistance = PrimaryRay.dist;
		
		if (hitDistance < 0.0f) {// if hit background - quit
			finalColor += hitColor;
			//break;
		}
		else {
			const vec3 hitNormal = PrimaryRay.normal;
			const vec3 hitPos = origin + direction * hitDistance;
			// Point light
			const vec3 toLight = normalize(Params.lightPos-vec3(0));
			float dotNL = max(dot(hitNormal, toLight), 0.2);
			finalColor = hitColor * dotNL;
		}
	//}

	imageStore(ResultImage, ivec2(gl_LaunchIDEXT.xy), vec4(LinearToSrgb(finalColor), 1.0f));
}


/*
*/