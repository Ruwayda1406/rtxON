#include "ObjLoader.h"
 
#include "GLFW/glfw3.h" 

#define uint unsigned int

#include <iostream>
using std::cout;
using std::cerr;
using std::endl;
#include <fstream>
using std::ifstream;
#include <sstream>
using std::istringstream;

ObjLoader::~ObjLoader()
{
}

ObjLoader::ObjLoader( bool center, bool loadTc, bool genTangents) :
	reCenterMesh(center), loadTex(loadTc), genTang(genTangents)
{

}

objMesh ObjLoader::loadOBJ(const char * fileName) {

	objMesh mesh;

	int nFaces = 0;

	ifstream objStream(fileName, std::ios::in);

	if (!objStream) {
		cerr << "Unable to open OBJ file: " << fileName << endl;
		exit(1);
	}

	string line, token;
	vector<int> face;

	getline(objStream, line);
	while (!objStream.eof()) {
		trimString(line);
		if (line.length() > 0 && line.at(0) != '#') {
			istringstream lineStream(line);

			lineStream >> token;

			if (token == "v") {
				float x, y, z;
				lineStream >> x >> y >> z;
				mesh.points.push_back(vec3(x, y, z));
			}
			else if (token == "vt" && loadTex) {
				// Process texture coordinate
				float s, t;
				lineStream >> s >> t;
				mesh.texCoords.push_back(vec2(s, t));
			}
			else if (token == "vn") {
				float x, y, z;
				lineStream >> x >> y >> z;
				mesh.normals.push_back(vec3(x, y, z));
			}
			else if (token == "f") {
				nFaces++;

				// Process face
				face.clear();
				size_t slash1, slash2;
				//int point, texCoord, normal;
				while (lineStream.good()) {
					string vertString;
					lineStream >> vertString;
					int pIndex = -1, nIndex = -1, tcIndex = -1;

					slash1 = vertString.find("/");
					if (slash1 == string::npos) {
						pIndex = atoi(vertString.c_str()) - 1;
					}
					else {
						slash2 = vertString.find("/", slash1 + 1);
						pIndex = atoi(vertString.substr(0, slash1).c_str())
							- 1;
						if (slash2 > slash1 + 1) {
							tcIndex =
								atoi(vertString.substr(slash1 + 1, slash2).c_str())
								- 1;
						}
						nIndex =
							atoi(vertString.substr(slash2 + 1, vertString.length()).c_str())
							- 1;
					}
					if (pIndex == -1) {
						printf("Missing point index!!!");
					}
					else {
						face.push_back(pIndex);
					}

					if (loadTex && tcIndex != -1 && pIndex != tcIndex) {
						printf("Texture and point indices are not consistent.\n");
					}
					if (nIndex != -1 && nIndex != pIndex) {
						printf("Normal and point indices are not consistent.\n");
					}
				}
				// If number of edges in face is greater than 3,
				// decompose into triangles as a triangle fan.
				if (face.size() > 3) {
					int v0 = face[0];
					int v1 = face[1];
					int v2 = face[2];
					// First face
					mesh.faces.push_back(vec3(v0,v1,v2));
					for (GLuint i = 3; i < face.size(); i++) {
						v1 = v2;
						v2 = face[i];
						mesh.faces.push_back(vec3(v0, v1, v2));
					}
				}
				else {
					mesh.faces.push_back(vec3(face[0], face[1], face[2]));
				}
			}
		}
		getline(objStream, line);
	}

	objStream.close();

	if (mesh.normals.size() == 0) {
		generateAveragedNormals(mesh.points, mesh.normals, mesh.faces);
	}

	//vector<vec4> tangents;
	//if (genTang && mesh.texCoords.size() > 0) {
	//	generateTangents(mesh.points, mesh.normals, mesh.faces, mesh.texCoords, mesh.tangents);
	//}

	if (reCenterMesh) {
		center(mesh.points);
	}

	cout << "Loaded mesh from: " << fileName << endl;
	cout << " " << mesh.points.size() << " points" << endl;
	cout << " " << nFaces << " faces" << endl;
	cout << " " << mesh.faces.size() / 3 << " triangles." << endl;
	cout << " " << mesh.normals.size() << " normals" << endl;
//	cout << " " << mesh.tangents.size() << " tangents " << endl;
	cout << " " << mesh.texCoords.size() << " texture coordinates." << endl;

	return mesh;
}

void ObjLoader::center(vector<vec3> & points) {
	if (points.size() < 1) return;

	vec3 maxPoint = points[0];
	vec3 minPoint = points[0];

	// Find the AABB
	for (uint i = 0; i < points.size(); ++i) {
		vec3 & point = points[i];
		if (point.x > maxPoint.x) maxPoint.x = point.x;
		if (point.y > maxPoint.y) maxPoint.y = point.y;
		if (point.z > maxPoint.z) maxPoint.z = point.z;
		if (point.x < minPoint.x) minPoint.x = point.x;
		if (point.y < minPoint.y) minPoint.y = point.y;
		if (point.z < minPoint.z) minPoint.z = point.z;
	}

	// Center of the AABB
	vec3 center = vec3((maxPoint.x + minPoint.x) / 2.0f,
		(maxPoint.y + minPoint.y) / 2.0f,
		(maxPoint.z + minPoint.z) / 2.0f);

	// Translate center of the AABB to the origin
	for (uint i = 0; i < points.size(); ++i) {
		vec3 & point = points[i];
		point = point - center;
	}
}

void ObjLoader::generateAveragedNormals(
	const vector<vec3> & points,
	vector<vec3> & normals,
	const vector<vec3> & faces)
{
	for (uint i = 0; i < points.size(); i++) {
		normals.push_back(vec3(0.0f));
	}

	for (uint i = 0; i < faces.size(); i += 3) {
		const vec3 & p1 = points[faces[i].x];
		const vec3 & p2 = points[faces[i].y];
		const vec3 & p3 = points[faces[i].z];

		vec3 a = p2 - p1;
		vec3 b = p3 - p1;
		vec3 n = glm::normalize(glm::cross(a, b));

		normals[faces[i].x] += n;
		normals[faces[i].y] += n;
		normals[faces[i].z] += n;
	}

	for (uint i = 0; i < normals.size(); i++) {
		normals[i] = glm::normalize(normals[i]);
	}
}

void ObjLoader::generateTangents(
	const vector<vec3> & points,
	const vector<vec3> & normals,
	const vector<int> & faces,
	const vector<vec2> & texCoords,
	vector<vec4> & tangents)
{
	vector<vec3> tan1Accum;
	vector<vec3> tan2Accum;

	for (uint i = 0; i < points.size(); i++) {
		tan1Accum.push_back(vec3(0.0f));
		tan2Accum.push_back(vec3(0.0f));
		tangents.push_back(vec4(0.0f));
	}

	// Compute the tangent vector
	for (uint i = 0; i < faces.size(); i += 3)
	{
		const vec3 &p1 = points[faces[i]];
		const vec3 &p2 = points[faces[i + 1]];
		const vec3 &p3 = points[faces[i + 2]];

		const vec2 &tc1 = texCoords[faces[i]];
		const vec2 &tc2 = texCoords[faces[i + 1]];
		const vec2 &tc3 = texCoords[faces[i + 2]];

		vec3 q1 = p2 - p1;
		vec3 q2 = p3 - p1;
		float s1 = tc2.x - tc1.x, s2 = tc3.x - tc1.x;
		float t1 = tc2.y - tc1.y, t2 = tc3.y - tc1.y;
		float r = 1.0f / (s1 * t2 - s2 * t1);
		vec3 tan1((t2*q1.x - t1 * q2.x) * r,
			(t2*q1.y - t1 * q2.y) * r,
			(t2*q1.z - t1 * q2.z) * r);
		vec3 tan2((s1*q2.x - s2 * q1.x) * r,
			(s1*q2.y - s2 * q1.y) * r,
			(s1*q2.z - s2 * q1.z) * r);
		tan1Accum[faces[i]] += tan1;
		tan1Accum[faces[i + 1]] += tan1;
		tan1Accum[faces[i + 2]] += tan1;
		tan2Accum[faces[i]] += tan2;
		tan2Accum[faces[i + 1]] += tan2;
		tan2Accum[faces[i + 2]] += tan2;
	}

	for (uint i = 0; i < points.size(); ++i)
	{
		const vec3 &n = normals[i];
		vec3 &t1 = tan1Accum[i];
		vec3 &t2 = tan2Accum[i];

		// Gram-Schmidt orthogonalize
		tangents[i] = vec4(glm::normalize(t1 - (glm::dot(n, t1) * n)), 0.0f);
		// Store handedness in w
		tangents[i].w = (glm::dot(glm::cross(n, t1), t2) < 0.0f) ? -1.0f : 1.0f;
	}
	tan1Accum.clear();
	tan2Accum.clear();
}

void ObjLoader::trimString(string & str) {
	const char * whiteSpace = " \t\n\r";
	size_t location;
	location = str.find_first_not_of(whiteSpace);
	str.erase(0, location);
	location = str.find_last_not_of(whiteSpace);
	str.erase(location + 1);
}

