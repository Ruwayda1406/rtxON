#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_EXT_nonuniform_qualifier : enable
#extension GL_EXT_scalar_block_layout : enable
#extension GL_GOOGLE_include_directive : enable
#include "../shared.h"

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

hitAttributeEXT vec2 HitAttribs;


vec3 computeDiffuse(vec3 lightDir, vec3 normal, vec3 kd, vec3 ka)
{
	// Lambertian
	float NdotL = clamp(dot(normal, lightDir), 0.0, 1.0); // In range [0..1]
	vec3  c = kd * NdotL;
	c += ka;

	return c;
}

vec3 computeSpecular(vec3 viewDir, vec3 lightDir, vec3 normal, vec3 ks, float shininess)
{
	vec3        V = normalize(-viewDir);
	vec3        R = reflect(-lightDir, normal);
	float	VdotR = clamp(dot(V, R), 0.0, 1.0); // In range [0..1]
	float       specular = pow(VdotR, shininess);
	return vec3(ks * specular);
}
vec3 DiffuseShade(vec3 pos, vec3 normal, vec3 difColor, float kd, float ks)
{
	vec3 hitValues = vec3(0);
	for (int i = 0; i < Params.LightInfo.x; i++)//SoftShadows
	{
		// Get information about this light; access your framework’s scene structs
		vec3 lightIntensity = vec3(Params.LightSource[i].w);
		vec3 lightPos = Params.LightSource[i].xyz;
		float distToLight = length(lightPos - vec3(0));
		vec3 dirToLight = normalize(lightPos - vec3(0));

		vec3  diffuse = computeDiffuse(dirToLight, normal, vec3(kd), difColor);
		// Specular
		vec3 specular = computeSpecular(gl_WorldRayDirectionEXT, dirToLight, normal, vec3(ks), 100.0);
		

		hitValues += vec3(Params.LightSource[i].w * (diffuse + specular));
	}
	vec3 finalcolor = hitValues / Params.LightInfo.x;


	return finalcolor;
}
ShadingData getHitShadingData(uint objId)
{
	ShadingData hit;
	// Indices of the triangle
	const uvec4 face = FacesArray[nonuniformEXT(gl_InstanceCustomIndexEXT)].Faces[gl_PrimitiveID];

	VertexAttribute v0 = AttribsArray[nonuniformEXT(gl_InstanceCustomIndexEXT)].VertexAttribs[int(face.x)];
	VertexAttribute v1 = AttribsArray[nonuniformEXT(gl_InstanceCustomIndexEXT)].VertexAttribs[int(face.y)];
	VertexAttribute v2 = AttribsArray[nonuniformEXT(gl_InstanceCustomIndexEXT)].VertexAttribs[int(face.z)];

	const vec3 barycentrics = vec3(1.0f - HitAttribs.x - HitAttribs.y, HitAttribs.x, HitAttribs.y);

	// Computing the normal at hit position
	hit.normal = normalize(BaryLerp(v0.normal.xyz, v1.normal.xyz, v2.normal.xyz, barycentrics));
	//const vec2 uv = BaryLerp(v0.uv.xy, v1.uv.xy, v2.uv.xy, barycentrics);
	hit.difColor = meshInfoArray[objId].info[0].xyzw;
	hit.kd = meshInfoArray[objId].info[1].x;
	hit.ks = meshInfoArray[objId].info[1].y;
	hit.mat = int(meshInfoArray[objId].info[1].z);

	hit.pos = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;

	return hit;
}
void main() {
	// Is this a transparent part of the surface?  If so, ignore this hit
	if (PrimaryRay.accColor.w < 1.0)
	{
		const uint objId = gl_InstanceCustomIndexEXT;
		ShadingData hit = getHitShadingData(objId);
		vec4 hitColor = vec4( DiffuseShade(hit.pos, hit.normal, hit.difColor.xyz, hit.kd, hit.ks), hit.difColor.w);

		// Front-to-back compositing
		PrimaryRay.accColor = (1.0 - PrimaryRay.accColor.w) * hitColor + PrimaryRay.accColor;
		if (hitColor.w < 1.0)
		{
			ignoreIntersectionEXT();
		}
	}
}