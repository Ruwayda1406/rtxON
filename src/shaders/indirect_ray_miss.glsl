
#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require

#include "../shared.h"

layout(location = SWS_LOC_INDIRECT_RAY) rayPayloadInEXT IndirectRayPayload indirectRay;
layout(set = SWS_UNIFORMPARAMS_SET, binding = SWS_UNIFORMPARAMS_BINDING, std140)     uniform AppData{
	UniformParams Params;
};

void main() {
	indirectRay.hitValue = vec3(Params.clearColor);
	if (indirectRay.rayDepth > 0) //not the first iteration 
	{
		indirectRay.hitValue = vec3(0.0);  // No contribution from environment
		
	}
	indirectRay.rayDepth = MAX_PATH_DEPTH;
}