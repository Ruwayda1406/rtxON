#pragma once
#include <vector>
using std::vector;
#include <glm/glm.hpp>
using glm::vec3;
using glm::vec2;
using glm::vec4;

#include <string>
using std::string;
struct objMesh {
	int                    numVertices;
	int                    numFaces;
	vector<vec3> points;
	vector<vec3> normals;
	vector<vec2> texCoords;
	vector<vec4> tangents;
	vector<vec3> faces;
};
class ObjLoader
{
private:
	unsigned int faces;
	unsigned int vaoHandle;

	bool reCenterMesh, loadTex, genTang;

	void trimString(string & str);
	
	void generateAveragedNormals(
		const vector<vec3> & points,
		vector<vec3> & normals,
		const vector<vec3> & faces);
	void generateTangents(
		const vector<vec3> & points,
		const vector<vec3> & normals,
		const vector<int> & faces,
		const vector<vec2> & texCoords,
		vector<vec4> & tangents);
	void center(vector<vec3> &);

public:
    ~ObjLoader();
	ObjLoader(bool center, bool loadTc, bool genTangents);

	objMesh loadOBJ(const char * fileName);
};
