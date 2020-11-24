#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_EXT_nonuniform_qualifier : enable
#extension GL_EXT_scalar_block_layout : enable
#extension GL_GOOGLE_include_directive : enable
#include "../shared.h"
layout(location = SWS_LOC_PRIMARY_RAY) rayPayloadInEXT RayPayload PrimaryRay;
layout(set = SWS_MESHINFO_SET, binding = 0, std430) readonly buffer meshInfoBuffer {
	vec4 info[];
} meshInfoArray[];


void main() {
	const uint objId = gl_InstanceCustomIndexEXT;
	// Is this a transparent part of the surface?  If so, ignore this hit
	//if (accAlpha >=1.0)
	//	ignoreIntersectionEXT();

	//PrimaryRay.accAlpha += meshInfoArray[objId].info[0].w;
	//PrimaryRay.accColor += meshInfoArray[objId].info[0].rgb;
}