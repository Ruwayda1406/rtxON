#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require

#include "../shared.h"

layout(location = SWS_LOC_INDIRECT_RAY) rayPayloadInEXT IndirectRayPayload indirectRay;
void main() {

	indirectRay.color = vec3(0);
}