// Generate a random unsigned int from two unsigned int values, using 16 pairs
// of rounds of the Tiny Encryption Algorithm. See Zafar, Olano, and Curtis,
// "GPU Random Numbers via the Tiny Encryption Algorithm"
uint tea(uint val0, uint val1)
{
  uint v0 = val0;
  uint v1 = val1;
  uint s0 = 0;

  for(uint n = 0; n < 16; n++)
  {
    s0 += 0x9e3779b9;
    v0 += ((v1 << 4) + 0xa341316c) ^ (v1 + s0) ^ ((v1 >> 5) + 0xc8013ea4);
    v1 += ((v0 << 4) + 0xad90777d) ^ (v0 + s0) ^ ((v0 >> 5) + 0x7e95761e);
  }

  return v0;
}

// Generate a random unsigned int in [0, 2^24) given the previous RNG state
// using the Numerical Recipes linear congruential generator
uint lcg(inout uint prev)
{
  uint LCG_A = 1664525u;
  uint LCG_C = 1013904223u;
  prev       = (LCG_A * prev + LCG_C);
  return prev & 0x00FFFFFF;
}

// Generate a random float in [0, 1) given the previous RNG state
float nextRand(inout uint prev)
{
  return (float(lcg(prev)) / float(0x01000000));
}

//-------------------------------------------------------------------------------------------------
// Sampling
//-------------------------------------------------------------------------------------------------
#define M_PI 3.141592
// Randomly sampling around +Z
vec3 samplingHemisphere(inout uint seed, in vec3 x, in vec3 y, in vec3 z)
{

	float r1 = nextRand(seed);
	float r2 = nextRand(seed);
	float sq = sqrt(1.0 - r2);

	vec3 direction = vec3(cos(2 * M_PI * r1) * sq, sin(2 * M_PI * r1) * sq, sqrt(r2));
	direction = direction.x * x + direction.y * y + direction.z * z;

	return direction;
}

// Return the tangent and binormal from the incoming normal
void createCoordinateSystem(in vec3 N, out vec3 Nt, out vec3 Nb)
{
	if (abs(N.x) > abs(N.y))
		Nt = vec3(N.z, 0, -N.x) / sqrt(N.x * N.x + N.z * N.z);
	else
		Nt = vec3(0, -N.z, N.y) / sqrt(N.y * N.y + N.z * N.z);
	Nb = cross(N, Nt);
}
//---------------------------------------------------------
vec3 reflection(vec3 I, vec3 N)
{
	return I - 2.0 * dot(I, N) * N;
}

vec3 computeDiffuse(vec3 lightDir, vec3 normal, vec3 kd, vec3 ambient)
{
	// Lambertian
	float NdotL = max(dot(normal, lightDir), 0.0);
	//float NdotL = clamp(dot(normal, lightDir), 0.0, 1.0); // In range [0..1]
	return (ambient + (kd * NdotL));
}

vec3 computeSpecular(vec3 viewDir, vec3 lightDir, vec3 normal, vec3 ks, float shininess)
{
	// Compute specular only if not in shadow
	vec3        V = normalize(-viewDir);
	vec3        R = reflect(-lightDir, normal);
	float	VdotR = max(dot(V, R), 0.0);// clamp(dot(V, R), 0.0, 1.0); // In range [0..1]
	float       specular = pow(VdotR, shininess);
	return vec3(ks * specular);
}