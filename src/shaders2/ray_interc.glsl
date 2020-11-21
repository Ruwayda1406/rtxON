#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require

#include "../shared.h"

layout(location = SWS_LOC_PRIMARY_RAY) rayPayloadInEXT RayPayload PrimaryRay;

layout(binding = 7, set = 1, scalar) buffer allSpheres_
{
  Sphere allSpheres[];
};


struct Ray
{
  vec3 origin;
  vec3 direction;
};

// Ray-Sphere intersection
// http://viclw17.github.io/2018/07/16/raytracing-ray-sphere-intersection/
float hitSphere(const Sphere s, const Ray r)
{
  vec3  oc           = r.origin - s.center;
  float a            = dot(r.direction, r.direction);
  float b            = 2.0 * dot(oc, r.direction);
  float c            = dot(oc, oc) - s.radius * s.radius;
  float discriminant = b * b - 4 * a * c;
  if(discriminant < 0)
  {
    return -1.0;
  }
  else
  {
    return (-b - sqrt(discriminant)) / (2.0 * a);
  }
}
void main()
{
  Ray ray;
  ray.origin    = gl_WorldRayOriginEXT;
  ray.direction = gl_WorldRayDirectionEXT;

  // Sphere data
  Sphere sphere = allSpheres[gl_PrimitiveID];

  //int   hitKind = gl_PrimitiveID % 2 == 0 ? KIND_SPHERE : KIND_CUBE;
  float tHit = hitSphere(sphere, ray);

  // Report hit point
  if(tHit > 0)
    reportIntersectionEXT(tHit, hitKind);
}
