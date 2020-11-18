#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require

#include "../shared_with_shaders.h"

layout(location = 0) rayPayloadInEXT vec3 ResultColor;

void main() {
    const vec3 backgroundColor = vec3(0.412f, 0.796f, 1.0f);
    ResultColor = backgroundColor;
}
