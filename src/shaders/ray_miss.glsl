#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require

#include "../shared.h"

layout(location = SWS_LOC_PRIMARY_RAY) rayPayloadInEXT RayPayload PrimaryRay;
layout(set = SWS_UNIFORMPARAMS_SET, binding = SWS_UNIFORMPARAMS_BINDING, std140)     uniform AppData{
	UniformParams Params;
};

void main() {
	//if (PrimaryRay.isTransparent)
	//	PrimaryRay.hitValue = PrimaryRay.accColor.xyz;
	//else
	PrimaryRay.hitValue = vec3(Params.clearColor);
	PrimaryRay.isMiss = true;
}