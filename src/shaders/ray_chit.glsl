#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_nonuniform_qualifier : require

#include "../shared.h"
#include "random.glsl"

layout(set = SWS_SCENE_AS_SET, binding = SWS_SCENE_AS_BINDING)            uniform accelerationStructureEXT Scene;
layout(set = SWS_ATTRIBS_SET, binding = 0, std430) readonly buffer AttribsBuffer {
	VertexAttribute VertexAttribs[];
} AttribsArray[];

layout(set = SWS_FACES_SET, binding = 0, std430) readonly buffer FacesBuffer {
	uvec4 Faces[];
} FacesArray[];

layout(set = SWS_MESHINFO_SET, binding = 0, std430) readonly buffer meshInfoBuffer {
	vec4 info[];
} meshInfoArray[];

layout(set = SWS_CAMDATA_SET, binding = SWS_CAMDATA_BINDING, std140)     uniform CameraData{
	CameraUniformParams Camera;
};

layout(set = SWS_UNIFORMPARAMS_SET, binding = SWS_UNIFORMPARAMS_BINDING, std140)     uniform AppData{
	UniformParams Params;
};

layout(location = SWS_LOC_PRIMARY_RAY) rayPayloadInEXT RayPayload PrimaryRay;
layout(location = SWS_LOC_SHADOW_RAY)  rayPayloadEXT ShadowRayPayload ShadowRay;

hitAttributeEXT vec2 HitAttribs;


vec3 computeDiffuse(vec3 lightDir, vec3 normal, vec3 kd, vec3 ka)
{
	// Lambertian
	float dotNL = max(dot(normal, lightDir), 0.0);
	vec3  c = kd * dotNL;
	c += ka;

	return c;
}

vec3 computeSpecular(vec3 viewDir, vec3 lightDir, vec3 normal, vec3 ks, float shininess)
{
	vec3        V = normalize(-viewDir);
	vec3        R = reflect(-lightDir, normal);
	float       specular = pow(max(dot(V, R), 0.0), shininess);
	return vec3(ks * specular);
}
void main() {
	
	// Object of this instance
	const uint objId = gl_InstanceCustomIndexEXT;// scnDesc.i[gl_InstanceID].objId;

	// Indices of the triangle
	const uvec4 face = FacesArray[nonuniformEXT(gl_InstanceCustomIndexEXT)].Faces[gl_PrimitiveID];

	VertexAttribute v0 = AttribsArray[nonuniformEXT(gl_InstanceCustomIndexEXT)].VertexAttribs[int(face.x)];
	VertexAttribute v1 = AttribsArray[nonuniformEXT(gl_InstanceCustomIndexEXT)].VertexAttribs[int(face.y)];
	VertexAttribute v2 = AttribsArray[nonuniformEXT(gl_InstanceCustomIndexEXT)].VertexAttribs[int(face.z)];

	const vec3 barycentrics = vec3(1.0f - HitAttribs.x - HitAttribs.y, HitAttribs.x, HitAttribs.y);

	// Computing the normal at hit position
	const vec3 normal = normalize(BaryLerp(v0.normal.xyz, v1.normal.xyz, v2.normal.xyz, barycentrics));
	//const vec2 uv = BaryLerp(v0.uv.xy, v1.uv.xy, v2.uv.xy, barycentrics);
	const vec3 color = PrimaryRay.accColor.xyz;// meshInfoArray[objId].info[0].xyz;
	const float kd = meshInfoArray[objId].info[1].x;
	const float ks = meshInfoArray[objId].info[1].y;
	const int mat =int(meshInfoArray[objId].info[1].z);

	const vec3 hitPos = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;
	
	float attenuation = 1;
	float lightDistance = 100000.0;

	
	const uint shadowRayFlags = gl_RayFlagsOpaqueEXT | gl_RayFlagsTerminateOnFirstHitEXT| gl_RayFlagsSkipClosestHitShaderEXT;
	const uint cullMask = 0xFF;
	const uint stbRecordStride = 1;
	const float tmin = 0.001;
	const float tmax = lightDistance;

	vec3 hitValues = vec3(0);
	for (int i = 0; i < Params.LightInfo.x; i++)//SoftShadows
	{
		const vec3 toLight = normalize(Params.LightSource[i].xyz);
		vec3  diffuse = computeDiffuse(toLight, normal, vec3(kd), color);
		vec3  specular = vec3(0);
		const vec3 shadowRayOrigin = hitPos + normal * 0.001f;
		ShadowRay.isShadowed = true;
		traceRayEXT(Scene,
			shadowRayFlags,
			cullMask,
			0,
			stbRecordStride,
			SWS_SHADOW_MISS_SHADERS_IDX,
			shadowRayOrigin,
			0.0f,
			toLight,
			tmax,
			SWS_LOC_SHADOW_RAY);

		float lighting;
		if (ShadowRay.isShadowed)
		{
			attenuation = Params.LightInfo.y;
		}
		else
		{
			// Specular
			specular = computeSpecular(gl_WorldRayDirectionEXT, toLight, normal, vec3(ks), 100.0);
		}

		hitValues += vec3(Params.LightSource[i].w * attenuation * (diffuse + specular));
	}
	vec3 finalcolor = hitValues / Params.LightInfo.x;

	
	if (mat == 3)// Reflection
	{
		vec3 origin = hitPos;
		vec3 rayDir = reflect(gl_WorldRayDirectionEXT, normal);
		PrimaryRay.attenuation *= ks;
		PrimaryRay.done = false;
		PrimaryRay.rayOrigin = origin;
		PrimaryRay.rayDir = rayDir;
	}
	/*else if (mat == 2)
	{
		const float NdotD = dot(normal, gl_WorldRayDirectionEXT);

		vec3 refrNormal;
		float refrEta;
		const float kIceIndex = 1.0f / 1.31f;
		if (NdotD > 0.0f) {
			refrNormal = -normal;
			refrEta = 1.0f / kIceIndex;
		}
		else {
			refrNormal = normal;
			refrEta = kIceIndex;
		}

		vec3 origin = hitPos;
		vec3 rayDir = refract(gl_WorldRayDirectionEXT, refrNormal, refrEta);
		PrimaryRay.done = false;
		PrimaryRay.rayOrigin = origin;
		PrimaryRay.rayDir = rayDir;
	}*/
	PrimaryRay.color = finalcolor;
	//PrimaryRay.dist = gl_HitTEXT;
	//PrimaryRay.normal = normal;
	//PrimaryRay.isHit = true;
}

