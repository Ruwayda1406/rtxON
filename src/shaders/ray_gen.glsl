#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require

#include "../shared.h"

layout(set = SWS_SCENE_AS_SET, binding = SWS_SCENE_AS_BINDING)            uniform accelerationStructureEXT Scene;
layout(set = SWS_RESULT_IMAGE_SET, binding = SWS_RESULT_IMAGE_BINDING, rgba8) uniform image2D ResultImage;

layout(set = SWS_CAMDATA_SET, binding = SWS_CAMDATA_BINDING, std140)     uniform AppData{
	UniformParams Params;
};

layout(location = SWS_LOC_PRIMARY_RAY) rayPayloadEXT RayPayload PrimaryRay;

vec3 computeDiffuse( vec3 lightDir, vec3 normal, vec3 kd, vec3 ka)
{
	// Lambertian
	float dotNL = max(dot(normal, lightDir), 0.0);
	vec3  c = kd * dotNL;
	c += ka;

	return c;
}

vec3 computeSpecular(vec3 viewDir, vec3 lightDir, vec3 normal,vec3 ks,float shininess)
{
	const float kPi = 3.14159265;
	const float kShininess = max(shininess, 4.0);

	// Specular
	const float kEnergyConservation = (2.0 + kShininess) / (2.0 * kPi);
	vec3        V = normalize(-viewDir);
	vec3        R = reflect(-lightDir, normal);
	float       specular = kEnergyConservation * pow(max(dot(V, R), 0.0), kShininess);

	return vec3(ks * specular);
}

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
			finalColor = hitColor;
		}
		else {
			const vec3 hitNormal = PrimaryRay.normal;
			const vec3 hitPos = origin + direction * hitDistance;
			const vec3 lightDir = normalize(Params.lightPos - vec3(0));

			
			vec3  diffuse = computeDiffuse(lightDir, hitNormal, vec3(0.2, 0.2, 0.2), hitColor);
			vec3  specular = computeSpecular(direction, lightDir, hitNormal, vec3(0.2, 0.2, 0.2), 50.0);
			
			finalColor = diffuse + specular;
		}

	imageStore(ResultImage, ivec2(gl_LaunchIDEXT.xy), vec4((finalColor), 1.0f));
}
