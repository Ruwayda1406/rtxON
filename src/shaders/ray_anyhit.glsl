#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_EXT_nonuniform_qualifier : enable
#extension GL_EXT_scalar_block_layout : enable
#extension GL_GOOGLE_include_directive : enable
#include "../shared.h"
layout(location = SWS_LOC_PRIMARY_RAY) rayPayloadInEXT RayPayload PrimaryRay;
/*layout(set = SWS_MESHINFO_SET, binding = 0, std430) readonly buffer meshInfoBuffer {
	vec4 info[];
} meshInfoArray[];
*/

void main() {
	const uint objId = gl_InstanceCustomIndexEXT;
	PrimaryRay.accColor = vec4(1,0,0,0);
	// Is this a transparent part of the surface?  If so, ignore this hit
	/*if (PrimaryRay.accAlpha < 1.0)
	{
		//float n = 1.0 - PrimaryRay.accAlpha;
		float a = meshInfoArray[objId].info[0].w;
		PrimaryRay.accAlpha += a;
		PrimaryRay.accColor += meshInfoArray[objId].info[0].xyz*a;
	}*/
}