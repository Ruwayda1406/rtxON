#ifndef SHARED_H
#define SHARED_H

#define MAX_LIGHTS			 	10
#define MAX_PATH_DEPTH			10
#define MAX_PATH_TRACED			100
#define MAX_ANTIALIASING_ITER   5
//
#define SWS_PRIMARY_HIT_SHADERS_IDX      0
#define SWS_PRIMARY_MISS_SHADERS_IDX     0
#define SWS_INDIRECT_HIT_SHADERS_IDX     1
#define SWS_INDIRECT_MISS_SHADERS_IDX    1

#define SWS_SHADOW_HIT_SHADERS_IDX       2
#define SWS_SHADOW_MISS_SHADERS_IDX      2
///////////////////////////////////////////
// resource locations
#define SWS_SCENE_AS_SET                0
#define SWS_SCENE_AS_BINDING            0

#define SWS_RESULT_IMAGE_SET            0
#define SWS_RESULT_IMAGE_BINDING        1

#define SWS_CAMDATA_SET                 0
#define SWS_CAMDATA_BINDING             2

#define SWS_UNIFORMPARAMS_SET           0
#define SWS_UNIFORMPARAMS_BINDING       3

//////////////////////////////////////////
#define SWS_ATTRIBS_SET                 1
#define SWS_FACES_SET                   2
#define SWS_MESHINFO_SET                3
#define SWS_LIGHTS_SET                  4

#define SWS_NUM_SETS                    5
/////////////////////////////////////////
// cross-shader locations
#define SWS_LOC_PRIMARY_RAY             0
#define SWS_LOC_HIT_ATTRIBS             1
#define SWS_LOC_SHADOW_RAY              2
#define SWS_LOC_INDIRECT_RAY            3

#define SWS_MAX_RECURSION               5
//////////////////////////////////////////
struct RayPayload {
	uint rndSeed;// used in anyhit
	//vec4 accColor;
    vec3 hitValue;
	bool isMiss;
	vec3 matColor;
	// for recursion
	vec3 rayOrigin;
	vec3 rayDir;
	float attenuation;
	bool done;
};
struct IndirectRayPayload {
	vec3 hitNormal;
	vec3 hitPos;
	vec3 hitColor;
	vec3 hitValue;
	bool isMiss;
	uint rndSeed; // current random seed
	int rayDepth;
	vec3 weight;
	vec3 rayOrigin;
	vec3 rayDir;
};
struct ShadowRayPayload {
	bool isShadowed;
	float attenuation;
};
struct VertexAttribute {
    vec4 normal;
    vec4 uv;
};
struct LightTriangle {
	vec3 v0;
	vec3 v1;
	vec3 v2;
};
struct ShadingData {
	vec4 matColor;
	vec3 emittance;
	vec3 reflectance;
	vec3 normal;
	vec3 pos;
	int mat;
	float ks, kd;
};
// packed std140
struct CameraUniformParams {
    // Camera
    vec4 pos;
    vec4 dir;
    vec4 up;
    vec4 side;
	vec4 nearFarFov;
};
struct UniformParams {
	vec4 clearColor;
	// Lighting
	vec4 SunPos;
	vec4 LightInfo;
	vec4 modeFrame;
};

#endif // SHARED_H
