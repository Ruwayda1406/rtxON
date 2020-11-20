#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require

#include "../shared_with_shaders.h"

layout(location = SWS_LOC_PRIMARY_RAY) rayPayloadInEXT RayPayload PrimaryRay;

void main() {
	const vec3 backgroundColor = vec3(0.2f, 0.2f, 0.2f);

	PrimaryRay.color = backgroundColor;
	PrimaryRay.normal = vec3(0.0f);
	PrimaryRay.dist = -1.0;
	PrimaryRay.objId = 0;
}