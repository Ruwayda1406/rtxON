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


vec3 CalcRayDir(vec2 screenUV, float aspect) {
	vec3 u = Params.camSide.xyz;
	vec3 v = Params.camUp.xyz;

	const float planeWidth = tan(Params.camNearFarFov.z * 0.5f);

	u *= (planeWidth * aspect);
	v *= planeWidth;

	const vec3 rayDir = normalize(Params.camDir.xyz + (u * screenUV.x) - (v * screenUV.y));
	return rayDir;
}
/*
struct ColorInfo
{
	vec3 ambient;
	vec3 diffuse;
	vec3 specular;
};
ColorInfo phongModel(vec3 pos, vec3 normal, vec3 lightPos)
{
	ColorInfo vertex;
	vertex.ambient = material.ka * vec3(1.0);
	vec3 norm = normalize(normal);
	vec3 lightDir = normalize(lightPos - pos);

	float diff = max(dot(norm, lightDir), 0.0);
	vertex.diffuse = material.kd* diff * vec3(1.0);

	vec3 viewDir = normalize(eyePos - pos);
	vec3 H = normalize(lightDir + viewDir);

	float NdotH = max(dot(norm, H), 0.0);

	vertex.specular = vec3(0);
	if (NdotH > 0)
	{
		float spec = pow(NdotH, material.shininess);
		vertex.specular = material.ks* spec * vec3(1.0);
	}
	return vertex;
}*/
void main() {
	const vec2 curPixel = vec2(gl_LaunchIDEXT.xy);
	const vec2 bottomRight = vec2(gl_LaunchSizeEXT.xy - 1);

	const vec2 uv = (curPixel / bottomRight) * 2.0f - 1.0f;

	const float aspect = float(gl_LaunchSizeEXT.x) / float(gl_LaunchSizeEXT.y);

	vec3 origin = Params.camPos.xyz;
	vec3 direction = CalcRayDir(uv, aspect);


    const uint rayFlags =  gl_RayFlagsOpaqueEXT;
    const uint cullMask = 0xFF;
    const uint stbRecordStride = 1;
    const float tmin = 0.0f;
	const float tmax = Params.camNearFarFov.y;

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

	const vec3 hitColor = PrimaryRay.colorAndDist.rgb;
	const float hitDistance = PrimaryRay.colorAndDist.w;

	const vec3 hitPos = origin + direction * hitDistance;
	//phongModel(hitPos, hitNormal, lightPos)
	finalColor = hitColor;

	imageStore(ResultImage, ivec2(gl_LaunchIDEXT.xy), vec4(LinearToSrgb(finalColor), 1.0f));
}
