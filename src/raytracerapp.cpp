#include "raytracerapp.h"

#include "shared.h"
#define TINYOBJLOADER_IMPLEMENTATION
#include "tiny_obj_loader.h"

static const String sShadersFolder = "_data/shaders/";
static const String sScenesFolder = "_data/scenes/";

static vec4 backgroundColor = vec4(0.7 , 0.8 , 1.0,1.0);
static vec4 planeColor = vec4(0.7 , 0.8 , 0.5,1.0);
static int mode = 1;
static int lightType = 9;
static const float sMoveSpeed = 2.0f;
static const float sRotateSpeed = 0.25f;

RayTracerApp::RayTracerApp()
    : VulkanApp()
    , mRTPipelineLayout(VK_NULL_HANDLE)
    , mRTPipeline(VK_NULL_HANDLE)
    , mRTDescriptorPool(VK_NULL_HANDLE)
	, mLMBDown(false)
	, mWKeyDown(false)
	, mAKeyDown(false)
	, mSKeyDown(false)
	, mDKeyDown(false)
	, mRightKeyDown(false)
	, mLeftKeyDown(false)
	, mDownKeyDown(false)
	, mUpKeyDown(false)
{
	

}
RayTracerApp::~RayTracerApp() {

}

void RayTracerApp::InitSettings() {
    mSettings.name = "RayTracer";
    mSettings.enableValidation = true;
    mSettings.supportRaytracing = true;
    mSettings.supportDescriptorIndexing = true;
}

void RayTracerApp::InitApp() {

	this->LoadSceneGeometries();
    this->CreateScene();
	this->CreateCamera();
    this->CreateDescriptorSetsLayouts();
    this->CreateRaytracingPipelineAndSBT();
    this->UpdateDescriptorSets();
}
void RayTracerApp::updateUniformParams(const float deltaTime) {
	// update values
	if (mWKeyDown) {
		mLight.move(vec3(0.01, 0, 0));
	}
	if (mSKeyDown) {
		mLight.move(vec3(-0.01, 0, 0));
	}
	if (mRightKeyDown || mLeftKeyDown || mDownKeyDown || mUpKeyDown){
		vec2 moveDelta(0.0f, 0.0f);
		if (mUpKeyDown) {
			moveDelta.y += 1.0f;
		}
		if (mDownKeyDown) {
			moveDelta.y -= 1.0f;
		}
		if (mLeftKeyDown) {
			moveDelta.x -= 1.0f;
		}
		if (mRightKeyDown) {
			moveDelta.x += 1.0f;
		}

		moveDelta *= sMoveSpeed * deltaTime;
		mCamera.Move(moveDelta.x, moveDelta.y);
	}
	//////////////////////////////////////////////////////////
	// copy camera data to gpu
	CameraUniformParams* cameraParams = reinterpret_cast<CameraUniformParams*>(mCameraBuffer.Map());
	cameraParams->pos = vec4(mCamera.GetPosition(), 0.0f);
	cameraParams->dir = vec4(mCamera.GetDirection(), 0.0f);
	cameraParams->up = vec4(mCamera.GetUp(), 0.0f);
	cameraParams->side = vec4(mCamera.GetSide(), 0.0f);
	cameraParams->nearFarFov = vec4(mCamera.GetNearPlane(), mCamera.GetFarPlane(), Deg2Rad(mCamera.GetFovY()), 0.0f);
	mCameraBuffer.Unmap();

	// copy others data to gpu
	UniformParams* params = reinterpret_cast<UniformParams*>(mUniformParamsBuffer.Map());
	params->clearColor = backgroundColor;
	for (int i = 0; i < mLight.size; i++)
	{
		params->LightSource[i] = mLight.LightSource[i];
	}
	params->LightInfo = vec4(mLight.size, mLight.ShadowAttenuation, lightType,0);
	params->modeFrame= vec4(mode,floor(deltaTime*10.0),0.0,0.0);
	mUniformParamsBuffer.Unmap();
}
void RayTracerApp::FreeResources() {

	for (RTMesh& mesh : mScene.meshes) {
		vkDestroyAccelerationStructureKHR(mDevice, mesh.blas.accelerationStructure, nullptr);
		vkFreeMemory(mDevice, mesh.blas.memory, nullptr);
	}
	mScene.meshes.clear();

	if (mScene.topLevelAS.accelerationStructure) {
		vkDestroyAccelerationStructureKHR(mDevice, mScene.topLevelAS.accelerationStructure, nullptr);
		mScene.topLevelAS.accelerationStructure = VK_NULL_HANDLE;
	}
	if (mScene.topLevelAS.memory) {
		vkFreeMemory(mDevice, mScene.topLevelAS.memory, nullptr);
		mScene.topLevelAS.memory = VK_NULL_HANDLE;
	}

    if (mRTDescriptorPool) {
        vkDestroyDescriptorPool(mDevice, mRTDescriptorPool, nullptr);
        mRTDescriptorPool = VK_NULL_HANDLE;
    }

    mShaderBindingTable.Destroy();

    if (mRTPipeline) {
        vkDestroyPipeline(mDevice, mRTPipeline, nullptr);
        mRTPipeline = VK_NULL_HANDLE;
    }

    if (mRTPipelineLayout) {
        vkDestroyPipelineLayout(mDevice, mRTPipelineLayout, nullptr);
        mRTPipelineLayout = VK_NULL_HANDLE;
    }

	for (VkDescriptorSetLayout& dsl : mRTDescriptorSetsLayouts) {
		vkDestroyDescriptorSetLayout(mDevice, dsl, nullptr);
	}
	mRTDescriptorSetsLayouts.clear();
   
}

void RayTracerApp::FillCommandBuffer(VkCommandBuffer commandBuffer, const size_t imageIndex) {
    vkCmdBindPipeline(commandBuffer,
                      VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR,
                      mRTPipeline);

	vkCmdBindDescriptorSets(commandBuffer,
		VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR,
		mRTPipelineLayout, 0,
		static_cast<uint32_t>(mRTDescriptorSets.size()), mRTDescriptorSets.data(),
		0, 0);

    VkStridedBufferRegionKHR raygenSBT = {
        mShaderBindingTable.GetSBTBuffer(),
        mShaderBindingTable.GetRaygenOffset(),
        mShaderBindingTable.GetGroupsStride(),
        mShaderBindingTable.GetRaygenSize()
    };

    VkStridedBufferRegionKHR hitSBT = {
        mShaderBindingTable.GetSBTBuffer(),
        mShaderBindingTable.GetHitGroupsOffset(),
        mShaderBindingTable.GetGroupsStride(),
        mShaderBindingTable.GetHitGroupsSize()
    };

    VkStridedBufferRegionKHR missSBT = {
        mShaderBindingTable.GetSBTBuffer(),
        mShaderBindingTable.GetMissGroupsOffset(),
        mShaderBindingTable.GetGroupsStride(),
        mShaderBindingTable.GetMissGroupsSize()
    };

    VkStridedBufferRegionKHR callableSBT = {};

   vkCmdTraceRaysKHR(commandBuffer, &raygenSBT, &missSBT, &hitSBT, &callableSBT, mSettings.resolutionX, mSettings.resolutionY, 1u);
}

void RayTracerApp::OnKey(const int key, const int scancode, const int action, const int mods)
{
	if (GLFW_RELEASE == action) {
		switch (key) {
		case GLFW_KEY_1: mode = 1; break;
		case GLFW_KEY_2: mode = 2; break;
		case GLFW_KEY_0: lightType = 0; break;
		case GLFW_KEY_9: lightType = 9; break;
		case GLFW_KEY_W: mWKeyDown = false; break;
		case GLFW_KEY_A: mAKeyDown = false; break;
		case GLFW_KEY_S: mSKeyDown = false; break;
		case GLFW_KEY_D: mDKeyDown = false; break;
		case GLFW_KEY_RIGHT: mRightKeyDown = false; break;
		case GLFW_KEY_LEFT: mLeftKeyDown = false; break;
		case GLFW_KEY_DOWN: mDownKeyDown = false; break;
		case GLFW_KEY_UP: mUpKeyDown = false; break;

		}
	}
	else if (GLFW_PRESS == action) {
		switch (key) {
		case GLFW_KEY_W: mWKeyDown = true; break;
		case GLFW_KEY_A: mAKeyDown = true; break;
		case GLFW_KEY_S: mSKeyDown = true; break;
		case GLFW_KEY_D: mDKeyDown = true; break;
		case GLFW_KEY_RIGHT: mRightKeyDown = true; break;
		case GLFW_KEY_LEFT: mLeftKeyDown = true; break;
		case GLFW_KEY_DOWN: mDownKeyDown = true; break;
		case GLFW_KEY_UP: mUpKeyDown = true; break;
		}
	}

}

void RayTracerApp::OnMouseMove(const float x, const float y) {
	vec2 newPos(x, y);
	vec2 delta = mCursorPos - newPos;

	if (mLMBDown) {
		mCamera.Rotate(delta.x * sRotateSpeed, delta.y * sRotateSpeed);
	}

	mCursorPos = newPos;
}

void RayTracerApp::OnMouseButton(const int button, const int action, const int mods) {
	if (0 == button && GLFW_PRESS == action) {
		mLMBDown = true;
	}
	else if (0 == button && GLFW_RELEASE == action) {
		mLMBDown = false;
	}
}

void RayTracerApp::Update(const size_t, const float deltaTime) {
    // Update FPS text
    String frameStats = ToString(mFPSMeter.GetFPS(), 1) + " FPS (" + ToString(mFPSMeter.GetFrameTime(), 1) + " ms)";
    String fullTitle = mSettings.name + "  " + frameStats;
    glfwSetWindowTitle(mWindow, fullTitle.c_str());
    /////////////////
	this->updateUniformParams(deltaTime);
}


void RayTracerApp::CreateCamera() {
   VkResult error = mCameraBuffer.Create(sizeof(CameraUniformParams), VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | VK_BUFFER_USAGE_RAY_TRACING_BIT_KHR, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
	CHECK_VK_ERROR(error, "mCameraBuffer.Create");

	mCamera.SetViewport({ 0, 0, static_cast<int>(mSettings.resolutionX), static_cast<int>(mSettings.resolutionY) });
	mCamera.SetViewPlanes(0.1f, 1000.0f);
	mCamera.SetFovY(45.0f);
	mCamera.LookAt(vec3(-5.0f, 3.0f, 10.0f), vec3(-5.0f, 3.0f, 9.0f));

	/////////////////////////////////////////
	error = mUniformParamsBuffer.Create(sizeof(UniformParams), VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | VK_BUFFER_USAGE_RAY_TRACING_BIT_KHR, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
	CHECK_VK_ERROR(error, "mUniformParamsBuffer.Create");
}
bool RayTracerApp::CreateAS(const VkAccelerationStructureTypeKHR type,
                      const uint32_t geometryCount,
                      const VkAccelerationStructureCreateGeometryTypeInfoKHR* geometries,
                      const uint32_t instanceCount,
                      RTAccelerationStructure& _as) {

    VkAccelerationStructureCreateInfoKHR& accelerationStructureInfo = _as.accelerationStructureInfo;
    accelerationStructureInfo = {};
    accelerationStructureInfo.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_CREATE_INFO_KHR;
    accelerationStructureInfo.type = type;
    accelerationStructureInfo.flags = VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR;
    accelerationStructureInfo.maxGeometryCount = geometryCount;
    accelerationStructureInfo.pGeometryInfos = geometries;
	accelerationStructureInfo.pNext = nullptr;
	accelerationStructureInfo.compactedSize = 0;
    VkResult error = vkCreateAccelerationStructureKHR(mDevice, &accelerationStructureInfo, nullptr, &_as.accelerationStructure);
    if (VK_SUCCESS != error) {
        CHECK_VK_ERROR(error, "vkCreateAccelerationStructureKHR");
        return false;
    }
	
    VkAccelerationStructureMemoryRequirementsInfoKHR memoryRequirementsInfo = {};
    memoryRequirementsInfo.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_MEMORY_REQUIREMENTS_INFO_KHR;
    memoryRequirementsInfo.type = VK_ACCELERATION_STRUCTURE_MEMORY_REQUIREMENTS_TYPE_OBJECT_KHR;
    memoryRequirementsInfo.buildType = VK_ACCELERATION_STRUCTURE_BUILD_TYPE_DEVICE_KHR;
    memoryRequirementsInfo.accelerationStructure = _as.accelerationStructure;

    VkMemoryRequirements2 memoryRequirements = {};
    memoryRequirements.sType = VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2;
    vkGetAccelerationStructureMemoryRequirementsKHR(mDevice, &memoryRequirementsInfo, &memoryRequirements);

    VkMemoryAllocateInfo memoryAllocateInfo = {};
    memoryAllocateInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    memoryAllocateInfo.allocationSize = memoryRequirements.memoryRequirements.size;
    memoryAllocateInfo.memoryTypeIndex = vulkanhelpers::GetMemoryType(memoryRequirements.memoryRequirements, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

    error = vkAllocateMemory(mDevice, &memoryAllocateInfo, nullptr, &_as.memory);
    if (VK_SUCCESS != error) {
        CHECK_VK_ERROR(error, "vkAllocateMemory for AS");
        return false;
    }

    VkBindAccelerationStructureMemoryInfoKHR bindInfo = {};
    bindInfo.sType = VK_STRUCTURE_TYPE_BIND_ACCELERATION_STRUCTURE_MEMORY_INFO_KHR;
    bindInfo.accelerationStructure = _as.accelerationStructure;
    bindInfo.memory = _as.memory;

    error = vkBindAccelerationStructureMemoryKHR(mDevice, 1, &bindInfo);
    if (VK_SUCCESS != error) {
        CHECK_VK_ERROR(error, "vkBindAccelerationStructureMemoryKHR");
        return false;
    }

    VkAccelerationStructureDeviceAddressInfoKHR addressInfo = {
        VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR,
        nullptr,
        _as.accelerationStructure
    };

    _as.handle = vkGetAccelerationStructureDeviceAddressKHR(mDevice, &addressInfo);
	
    return true;
}
void RayTracerApp::LoadSceneGeometries() {

//	mLight.LightPositions.clear();
	mScene.meshes.clear(); 
	LoadSceneGeometry(sScenesFolder + "fake_whitted.obj");

	//LoadSceneGeometry(sScenesFolder + "bs_ears.obj");
	// prepare shader resources infos
	const size_t numMeshes = mScene.meshes.size();
	mScene.meshInfoBufferInfos.resize(numMeshes);
	mScene.attribsBufferInfos.resize(numMeshes);
	mScene.facesBufferInfos.resize(numMeshes);
	for (size_t i = 0; i < numMeshes; ++i) {
		const RTMesh& mesh = mScene.meshes[i];
		VkDescriptorBufferInfo& meshInfo = mScene.meshInfoBufferInfos[i];
		VkDescriptorBufferInfo& attribsInfo = mScene.attribsBufferInfos[i];
		VkDescriptorBufferInfo& facesInfo = mScene.facesBufferInfos[i];

		attribsInfo.buffer = mesh.attribs.GetBuffer();
		attribsInfo.offset = 0;
		attribsInfo.range = mesh.attribs.GetSize();

		facesInfo.buffer = mesh.faces.GetBuffer();
		facesInfo.offset = 0;
		facesInfo.range = mesh.faces.GetSize();

		meshInfo.buffer = mesh.infos.GetBuffer();
		meshInfo.offset = 0;
		meshInfo.range = mesh.infos.GetSize();
	}
}
void RayTracerApp::LoadSceneGeometry(String fileName) {
	tinyobj::attrib_t attrib;
	std::vector<tinyobj::shape_t> shapes;
	std::vector<tinyobj::material_t> materials;
	String warn, error;

	String baseDir = fileName;
	const size_t slash = baseDir.find_last_of('/');
	if (slash != String::npos) {
		baseDir.erase(slash);
	}

	const bool result = tinyobj::LoadObj(&attrib, &shapes, &materials, &warn, &error, fileName.c_str(), baseDir.c_str(), true);
	if (result) {
		int currentMeshNumer = 0;// mScene.meshes.size();
		mScene.meshes.resize(currentMeshNumer+shapes.size());

		int meshIdx = currentMeshNumer;
		for (size_t shapeIdx = 0; shapeIdx < shapes.size(); ++shapeIdx) {
			RTMesh& mesh = mScene.meshes[meshIdx++];
			const tinyobj::shape_t& shape = shapes[shapeIdx];

			const size_t numFaces = shape.mesh.num_face_vertices.size();
			const size_t numVertices = numFaces * 3;

			mesh.numVertices = static_cast<uint32_t>(numVertices);
			mesh.numFaces = static_cast<uint32_t>(numFaces);


			const size_t positionsBufferSize = numVertices * sizeof(vec3);
			const size_t indicesBufferSize = numFaces * 3 * sizeof(uint32_t);
			const size_t facesBufferSize = numFaces * 4 * sizeof(uint32_t);
			const size_t attribsBufferSize = numVertices * sizeof(VertexAttribute);
			const size_t meshInfosBufferSize = 2 * sizeof(vec4);

			VkResult error = mesh.positions.Create(positionsBufferSize, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_RAY_TRACING_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
			CHECK_VK_ERROR(error, "mesh.positions.Create");

			error = mesh.indices.Create(indicesBufferSize, VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_RAY_TRACING_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
			CHECK_VK_ERROR(error, "mesh.indices.Create");

			error = mesh.faces.Create(facesBufferSize, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_RAY_TRACING_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
			CHECK_VK_ERROR(error, "mesh.faces.Create");

			error = mesh.attribs.Create(attribsBufferSize, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_RAY_TRACING_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
			CHECK_VK_ERROR(error, "mesh.attribs.Create");

			error = mesh.infos.Create(meshInfosBufferSize, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_RAY_TRACING_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
			CHECK_VK_ERROR(error, "mesh.infos.Create");

			vec3* positions = reinterpret_cast<vec3*>(mesh.positions.Map());
			VertexAttribute* attribs = reinterpret_cast<VertexAttribute*>(mesh.attribs.Map());
			uint32_t* indices = reinterpret_cast<uint32_t*>(mesh.indices.Map());
			uint32_t* faces = reinterpret_cast<uint32_t*>(mesh.faces.Map());
			vec4* infos = reinterpret_cast<vec4*>(mesh.infos.Map());

			size_t vIdx = 0;
			for (size_t f = 0; f < numFaces; ++f) {
				assert(shape.mesh.num_face_vertices[f] == 3);
				for (size_t j = 0; j < 3; ++j, ++vIdx) {
					const tinyobj::index_t& i = shape.mesh.indices[vIdx];

					vec3& pos = positions[vIdx];
					vec4& normal = attribs[vIdx].normal;
					vec4& uv = attribs[vIdx].uv;

					pos.x = attrib.vertices[3 * i.vertex_index + 0];
					pos.y = attrib.vertices[3 * i.vertex_index + 1];
					pos.z = attrib.vertices[3 * i.vertex_index + 2];
					normal.x = attrib.normals[3 * i.normal_index + 0];
					normal.y = attrib.normals[3 * i.normal_index + 1];
					normal.z = attrib.normals[3 * i.normal_index + 2];
					uv.x = attrib.texcoords[2 * i.texcoord_index + 0];
					uv.y = attrib.texcoords[2 * i.texcoord_index + 1];
				}

				const uint32_t a = static_cast<uint32_t>(3 * f + 0);
				const uint32_t b = static_cast<uint32_t>(3 * f + 1);
				const uint32_t c = static_cast<uint32_t>(3 * f + 2);
				indices[a] = a;
				indices[b] = b;
				indices[c] = c;

				faces[4 * f + 0] = a;
				faces[4 * f + 1] = b;
				faces[4 * f + 2] = c;
			}

			vec4& colorInfo = infos[0];//random rgb color
			vec4& matInfo = infos[1];	// mat diffuse , specular
			if (shape.name == "Plane")
			{
				colorInfo.x = planeColor.r;
				colorInfo.y = planeColor.g;
				colorInfo.z = planeColor.b;
				colorInfo.w = 1.0;// alpha 

				matInfo.x = 0.2;
				matInfo.y = 0.2;
				matInfo.z = 0.0;
				matInfo.w = 0.0;
			}
			else if (shape.name == "Mirror")
			{
				colorInfo.x = 1.0;
				colorInfo.y = 1.0;
				colorInfo.z = 1.0;
				colorInfo.w = 1.0;// alpha 

				matInfo.x = 0.5;
				matInfo.y = 0.5;
				matInfo.z = 3.0;//reflect
				matInfo.w = 0.0;
			}
			else
			{
				matInfo.x = getRandomFloat(0.3, 0.1);
				matInfo.y = getRandomFloat(0.3, 0.1);
				matInfo.z = 0.0;
				matInfo.w = 0.0;
				

				if (shape.name == "Light")
				{
					colorInfo.x = 1;
					colorInfo.y = 1;
					colorInfo.z = 1;
					colorInfo.w = 1;// alpha 
					matInfo.w = 0.0;
				}
				else
				{
					colorInfo.x = getRandomFloat(0.5, 1.0);
					colorInfo.y = getRandomFloat(0.5, 1.0);
					colorInfo.z = getRandomFloat(0.5, 1.0);
					colorInfo.w = 1.0;
				}
				
			}
			//
			


			mesh.indices.Unmap();
			mesh.attribs.Unmap();
			mesh.positions.Unmap();
			mesh.faces.Unmap();
			mesh.infos.Unmap();
		}
	}
}
void RayTracerApp::CreateScene() {
	const VkTransformMatrixKHR transform = {
	1.0f, 0.0f, 0.0f, 0.0f,
	0.0f, 1.0f, 0.0f, 0.0f,
	0.0f, 0.0f, 1.0f, 0.0f,
	};

	const size_t numMeshes = mScene.meshes.size();

	Array<VkAccelerationStructureCreateGeometryTypeInfoKHR> geometryInfos(numMeshes, VkAccelerationStructureCreateGeometryTypeInfoKHR{});
	Array<VkAccelerationStructureGeometryKHR> geometries(numMeshes, VkAccelerationStructureGeometryKHR{});
	Array<VkAccelerationStructureInstanceKHR> instances(numMeshes, VkAccelerationStructureInstanceKHR{});

	for (size_t i = 0; i < numMeshes; ++i) {
		RTMesh& mesh = mScene.meshes[i];

		VkAccelerationStructureCreateGeometryTypeInfoKHR& geometryInfo = geometryInfos[i];
		VkAccelerationStructureGeometryKHR& geometry = geometries[i];

		geometryInfo.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_CREATE_GEOMETRY_TYPE_INFO_KHR;
		geometryInfo.geometryType = VK_GEOMETRY_TYPE_TRIANGLES_KHR;
		geometryInfo.maxPrimitiveCount = mesh.numFaces;
		geometryInfo.indexType = VK_INDEX_TYPE_UINT32;
		geometryInfo.maxVertexCount = mesh.numVertices;
		geometryInfo.vertexFormat = VK_FORMAT_R32G32B32_SFLOAT;
		geometryInfo.allowsTransforms = VK_FALSE;

		geometry.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR;
		geometry.flags = VK_GEOMETRY_OPAQUE_BIT_KHR;
		geometry.geometryType = geometryInfo.geometryType;
		geometry.geometry.triangles.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR;
		geometry.geometry.triangles.vertexData = vulkanhelpers::GetBufferDeviceAddressConst(mesh.positions);
		geometry.geometry.triangles.vertexStride = sizeof(vec3);
		geometry.geometry.triangles.vertexFormat = geometryInfo.vertexFormat;
		geometry.geometry.triangles.indexData = vulkanhelpers::GetBufferDeviceAddressConst(mesh.indices);
		geometry.geometry.triangles.indexType = geometryInfo.indexType;

		// here we create our bottom-level acceleration structure for our mesh
		this->CreateAS(VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR, 1, &geometryInfo, 0, mesh.blas);


		VkAccelerationStructureInstanceKHR& instance = instances[i];
		instance.transform = transform;
		instance.instanceCustomIndex = static_cast<uint32_t>(i);
		instance.mask = 0xff;
		instance.instanceShaderBindingTableRecordOffset = 0;
		instance.flags = VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR;
		instance.accelerationStructureReference = mesh.blas.handle;
	}

	// create instances for our meshes
	vulkanhelpers::Buffer instancesBuffer;
	VkResult error = instancesBuffer.Create(instances.size() * sizeof(VkAccelerationStructureInstanceKHR), VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | VK_BUFFER_USAGE_RAY_TRACING_BIT_KHR, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
	CHECK_VK_ERROR(error, "instancesBuffer.Create");

	if (!instancesBuffer.UploadData(instances.data(), instancesBuffer.GetSize())) {
		assert(false && "Failed to upload instances buffer");
	}

    // and here we create out top-level acceleration structure that'll represent our scene
    VkAccelerationStructureCreateGeometryTypeInfoKHR tlasGeoInfo = {};
    tlasGeoInfo.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_CREATE_GEOMETRY_TYPE_INFO_KHR;
    tlasGeoInfo.geometryType = VK_GEOMETRY_TYPE_INSTANCES_KHR;
	tlasGeoInfo.maxPrimitiveCount = static_cast<uint32_t>(instances.size());
    tlasGeoInfo.allowsTransforms = VK_TRUE;

    this->CreateAS(VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR, 1, &tlasGeoInfo, 1, mScene.topLevelAS);

    // now we have to build them
	VkAccelerationStructureMemoryRequirementsInfoKHR memoryRequirementsInfo = {};
	memoryRequirementsInfo.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_MEMORY_REQUIREMENTS_INFO_KHR;
	memoryRequirementsInfo.buildType = VK_ACCELERATION_STRUCTURE_BUILD_TYPE_DEVICE_KHR;

	VkDeviceSize maximumBlasSize = 0;
	for (const RTMesh& mesh : mScene.meshes) {
		memoryRequirementsInfo.type = VK_ACCELERATION_STRUCTURE_MEMORY_REQUIREMENTS_TYPE_BUILD_SCRATCH_KHR;
		memoryRequirementsInfo.accelerationStructure = mesh.blas.accelerationStructure;

		VkMemoryRequirements2 memReqBLAS = {};
		memReqBLAS.sType = VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2;
		vkGetAccelerationStructureMemoryRequirementsKHR(mDevice, &memoryRequirementsInfo, &memReqBLAS);

		maximumBlasSize = Max(maximumBlasSize, memReqBLAS.memoryRequirements.size);
	}

    VkMemoryRequirements2 memReqTLAS = {};
    memReqTLAS.sType = VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2;
    memoryRequirementsInfo.type = VK_ACCELERATION_STRUCTURE_MEMORY_REQUIREMENTS_TYPE_BUILD_SCRATCH_KHR;
    memoryRequirementsInfo.accelerationStructure = mScene.topLevelAS.accelerationStructure;
    vkGetAccelerationStructureMemoryRequirementsKHR(mDevice, &memoryRequirementsInfo, &memReqTLAS);

    const VkDeviceSize scratchBufferSize = Max(maximumBlasSize, memReqTLAS.memoryRequirements.size);

    vulkanhelpers::Buffer scratchBuffer;
    error = scratchBuffer.Create(scratchBufferSize, VK_BUFFER_USAGE_RAY_TRACING_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    CHECK_VK_ERROR(error, "scratchBuffer.Create");

    VkCommandBufferAllocateInfo commandBufferAllocateInfo = {};
    commandBufferAllocateInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    commandBufferAllocateInfo.commandPool = mCommandPool;
    commandBufferAllocateInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    commandBufferAllocateInfo.commandBufferCount = 1;

    VkCommandBuffer commandBuffer = VK_NULL_HANDLE;
    error = vkAllocateCommandBuffers(mDevice, &commandBufferAllocateInfo, &commandBuffer);
    CHECK_VK_ERROR(error, "vkAllocateCommandBuffers");

    VkCommandBufferBeginInfo beginInfo = {};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(commandBuffer, &beginInfo);

    VkMemoryBarrier memoryBarrier = {};
    memoryBarrier.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
    memoryBarrier.srcAccessMask = VK_ACCESS_ACCELERATION_STRUCTURE_WRITE_BIT_KHR;
    memoryBarrier.dstAccessMask = VK_ACCESS_ACCELERATION_STRUCTURE_READ_BIT_KHR;

    // build bottom-level ASs
	// build bottom-level ASs
	for (size_t i = 0; i < numMeshes; ++i) {
		VkAccelerationStructureGeometryKHR* geometryPtr = &geometries[i];

		VkAccelerationStructureBuildGeometryInfoKHR buildInfo = {};
		buildInfo.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR;
		buildInfo.type = mScene.meshes[i].blas.accelerationStructureInfo.type;
		buildInfo.flags = mScene.meshes[i].blas.accelerationStructureInfo.flags;
		buildInfo.update = VK_FALSE;
		buildInfo.srcAccelerationStructure = VK_NULL_HANDLE;
		buildInfo.dstAccelerationStructure = mScene.meshes[i].blas.accelerationStructure;
		buildInfo.geometryArrayOfPointers = VK_FALSE;
		buildInfo.geometryCount = mScene.meshes[i].blas.accelerationStructureInfo.maxGeometryCount;
		buildInfo.ppGeometries = &geometryPtr;
		buildInfo.scratchData = vulkanhelpers::GetBufferDeviceAddress(scratchBuffer);

		VkAccelerationStructureBuildOffsetInfoKHR offsetInfo;
		offsetInfo.primitiveCount = geometryInfos[i].maxPrimitiveCount;
		offsetInfo.primitiveOffset = 0;
		offsetInfo.firstVertex = 0;
		offsetInfo.transformOffset = 0;

		VkAccelerationStructureBuildOffsetInfoKHR* offsets[1] = { &offsetInfo };

		vkCmdBuildAccelerationStructureKHR(commandBuffer, 1, &buildInfo, offsets);

		vkCmdPipelineBarrier(commandBuffer,
			VK_PIPELINE_STAGE_ACCELERATION_STRUCTURE_BUILD_BIT_KHR,
			VK_PIPELINE_STAGE_ACCELERATION_STRUCTURE_BUILD_BIT_KHR,
			0, 1, &memoryBarrier, 0, nullptr, 0, nullptr);
	}

    // build top-level AS
    VkAccelerationStructureGeometryKHR topLevelGeometry = {};
    topLevelGeometry.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR;
    topLevelGeometry.flags = VK_GEOMETRY_OPAQUE_BIT_KHR;
    topLevelGeometry.geometryType = VK_GEOMETRY_TYPE_INSTANCES_KHR;
    topLevelGeometry.geometry.instances.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR;
    topLevelGeometry.geometry.instances.arrayOfPointers = VK_FALSE;
    topLevelGeometry.geometry.instances.data.deviceAddress = vulkanhelpers::GetBufferDeviceAddress(instancesBuffer).deviceAddress;

    VkAccelerationStructureGeometryKHR* geometryPtr = &topLevelGeometry;

    VkAccelerationStructureBuildGeometryInfoKHR buildInfo = {};
    buildInfo.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR;
    buildInfo.type = mScene.topLevelAS.accelerationStructureInfo.type;
    buildInfo.flags = mScene.topLevelAS.accelerationStructureInfo.flags;
    buildInfo.update = VK_FALSE;
    buildInfo.srcAccelerationStructure = VK_NULL_HANDLE;
    buildInfo.dstAccelerationStructure = mScene.topLevelAS.accelerationStructure;
    buildInfo.geometryArrayOfPointers = VK_FALSE;
    buildInfo.geometryCount = 1;
    buildInfo.ppGeometries = &geometryPtr;
    buildInfo.scratchData = vulkanhelpers::GetBufferDeviceAddress(scratchBuffer);

    VkAccelerationStructureBuildOffsetInfoKHR offsetInfo;
    offsetInfo.primitiveCount = tlasGeoInfo.maxPrimitiveCount;
    offsetInfo.primitiveOffset = 0;
    offsetInfo.firstVertex = 0;
    offsetInfo.transformOffset = 0;

    VkAccelerationStructureBuildOffsetInfoKHR* offsets[1] = { &offsetInfo };

    vkCmdBuildAccelerationStructureKHR(commandBuffer, 1, &buildInfo, offsets);

    vkCmdPipelineBarrier(commandBuffer,
                         VK_PIPELINE_STAGE_ACCELERATION_STRUCTURE_BUILD_BIT_KHR,
                         VK_PIPELINE_STAGE_ACCELERATION_STRUCTURE_BUILD_BIT_KHR,
                         0, 1, &memoryBarrier, 0, nullptr, 0, nullptr);

    vkEndCommandBuffer(commandBuffer);

    VkSubmitInfo submitInfo = {};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &commandBuffer;

    vkQueueSubmit(mGraphicsQueue, 1, &submitInfo, VK_NULL_HANDLE);
    error = vkQueueWaitIdle(mGraphicsQueue);
    CHECK_VK_ERROR(error, "vkQueueWaitIdle");
    vkFreeCommandBuffers(mDevice, mCommandPool, 1, &commandBuffer);
}

void RayTracerApp::CreateDescriptorSetsLayouts() {
	const uint32_t numMeshes = static_cast<uint32_t>(mScene.meshes.size());
	mRTDescriptorSetsLayouts.resize(SWS_NUM_SETS);
    // First set:
    //  binding 0  ->  AS
    //  binding 1  ->  output image
	//  binding 2  ->  Camera data
	//  binding 3  ->  uniform data

    VkDescriptorSetLayoutBinding accelerationStructureLayoutBinding;
	accelerationStructureLayoutBinding.binding =  SWS_SCENE_AS_BINDING;
    accelerationStructureLayoutBinding.descriptorType = VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR;
    accelerationStructureLayoutBinding.descriptorCount = 1;
    accelerationStructureLayoutBinding.stageFlags = VK_SHADER_STAGE_RAYGEN_BIT_KHR| VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR;
    accelerationStructureLayoutBinding.pImmutableSamplers = nullptr;

    VkDescriptorSetLayoutBinding resultImageLayoutBinding;
	resultImageLayoutBinding.binding =  SWS_RESULT_IMAGE_BINDING;
    resultImageLayoutBinding.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    resultImageLayoutBinding.descriptorCount = 1;
    resultImageLayoutBinding.stageFlags = VK_SHADER_STAGE_RAYGEN_BIT_KHR;
    resultImageLayoutBinding.pImmutableSamplers = nullptr;

	VkDescriptorSetLayoutBinding camdataBufferBinding;
	camdataBufferBinding.binding = SWS_CAMDATA_BINDING;
	camdataBufferBinding.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
	camdataBufferBinding.descriptorCount = 1;
	camdataBufferBinding.stageFlags = VK_SHADER_STAGE_ALL;
	camdataBufferBinding.pImmutableSamplers = nullptr;

	VkDescriptorSetLayoutBinding uniformParamsBinding;
	uniformParamsBinding.binding = SWS_UNIFORMPARAMS_BINDING;
	uniformParamsBinding.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
	uniformParamsBinding.descriptorCount = 1;
	uniformParamsBinding.stageFlags = VK_SHADER_STAGE_ALL;
	uniformParamsBinding.pImmutableSamplers = nullptr;

	std::vector<VkDescriptorSetLayoutBinding> bindings({
		accelerationStructureLayoutBinding,
		resultImageLayoutBinding,
		camdataBufferBinding,
		uniformParamsBinding
		});

    VkDescriptorSetLayoutCreateInfo layoutInfo;
	layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
	layoutInfo.pNext = nullptr;
	layoutInfo.flags = 0;
	layoutInfo.bindingCount = static_cast<uint32_t>(bindings.size());
	layoutInfo.pBindings = bindings.data();

    VkResult error = vkCreateDescriptorSetLayout(mDevice, &layoutInfo, nullptr, &mRTDescriptorSetsLayouts[SWS_SCENE_AS_SET]);
	CHECK_VK_ERROR(error, "vkCreateDescriptorSetLayout");
	// Second set:
//  binding 0 .. N  ->  per-face material IDs for our meshes  (N = num meshes)

	const VkDescriptorBindingFlags flag = VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT;

	VkDescriptorSetLayoutBindingFlagsCreateInfo bindingFlags;
	bindingFlags.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO;
	bindingFlags.pNext = nullptr;
	bindingFlags.pBindingFlags = &flag;
	bindingFlags.bindingCount = 1;

	VkDescriptorSetLayoutBinding ssboBinding;
	ssboBinding.binding = 0;
	ssboBinding.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
	ssboBinding.descriptorCount = numMeshes;
	ssboBinding.stageFlags = VK_SHADER_STAGE_ALL;
	ssboBinding.pImmutableSamplers = nullptr;

	VkDescriptorSetLayoutCreateInfo set1LayoutInfo;
	set1LayoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
	set1LayoutInfo.pNext = &bindingFlags;
	set1LayoutInfo.flags = 0;
	set1LayoutInfo.bindingCount = 1;
	set1LayoutInfo.pBindings = &ssboBinding;

	// 2 set:
	//  binding 0 .. N  ->  vertex attributes for our meshes  (N = num meshes)
	//   (re-using second's set info)

	error = vkCreateDescriptorSetLayout(mDevice, &set1LayoutInfo, nullptr, &mRTDescriptorSetsLayouts[SWS_ATTRIBS_SET]);
	CHECK_VK_ERROR(error, L"vkCreateDescriptorSetLayout");

	// 3 set:
	//  binding 0 .. N  ->  faces info (indices) for our meshes  (N = num meshes)
	//   (re-using second's set info)

	error = vkCreateDescriptorSetLayout(mDevice, &set1LayoutInfo, nullptr, &mRTDescriptorSetsLayouts[SWS_FACES_SET]);
	CHECK_VK_ERROR(error, L"vkCreateDescriptorSetLayout");


	error = vkCreateDescriptorSetLayout(mDevice, &set1LayoutInfo, nullptr, &mRTDescriptorSetsLayouts[SWS_MESHINFO_SET]);
	CHECK_VK_ERROR(error, L"vkCreateDescriptorSetLayout");


}

void RayTracerApp::CreateRaytracingPipelineAndSBT() {
	VkPipelineLayoutCreateInfo pipelineLayoutCreateInfo = {};
	pipelineLayoutCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
	pipelineLayoutCreateInfo.setLayoutCount = SWS_NUM_SETS;
	pipelineLayoutCreateInfo.pSetLayouts = mRTDescriptorSetsLayouts.data();

	VkResult error = vkCreatePipelineLayout(mDevice, &pipelineLayoutCreateInfo, nullptr, &mRTPipelineLayout);
	CHECK_VK_ERROR(error, "vkCreatePipelineLayout");

	vulkanhelpers::Shader rayGenShader, rayChitShader, rayMissShader, rayAhitShader, shadowMiss, indirectChitShader, indirectMissShader;
    rayGenShader.LoadFromFile((sShadersFolder + "ray_gen.bin").c_str());
    rayChitShader.LoadFromFile((sShadersFolder + "ray_chit.bin").c_str());
    rayAhitShader.LoadFromFile((sShadersFolder + "ray_anyhit.bin").c_str());
	rayMissShader.LoadFromFile((sShadersFolder + "ray_miss.bin").c_str());
	shadowMiss.LoadFromFile((sShadersFolder + "shadow_ray_miss.bin").c_str());
	indirectChitShader.LoadFromFile((sShadersFolder + "indirect_ray_chit.bin").c_str());
	indirectMissShader.LoadFromFile((sShadersFolder + "indirect_ray_miss.bin").c_str());


    mShaderBindingTable.Initialize(2,3, mRTProps.shaderGroupHandleSize, mRTProps.shaderGroupBaseAlignment);
    mShaderBindingTable.SetRaygenStage(rayGenShader.GetShaderStage(VK_SHADER_STAGE_RAYGEN_BIT_KHR));

	mShaderBindingTable.AddStageToHitGroup({ rayChitShader.GetShaderStage(VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR), rayAhitShader.GetShaderStage(VK_SHADER_STAGE_ANY_HIT_BIT_KHR) }, SWS_PRIMARY_HIT_SHADERS_IDX);
	mShaderBindingTable.AddStageToHitGroup({ indirectChitShader.GetShaderStage(VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR) }, SWS_INDIRECT_HIT_SHADERS_IDX);

	mShaderBindingTable.AddStageToMissGroup(rayMissShader.GetShaderStage(VK_SHADER_STAGE_MISS_BIT_KHR), SWS_PRIMARY_MISS_SHADERS_IDX);
	mShaderBindingTable.AddStageToMissGroup(indirectMissShader.GetShaderStage(VK_SHADER_STAGE_MISS_BIT_KHR), SWS_INDIRECT_MISS_SHADERS_IDX);
	mShaderBindingTable.AddStageToMissGroup(shadowMiss.GetShaderStage(VK_SHADER_STAGE_MISS_BIT_KHR), SWS_SHADOW_MISS_SHADERS_IDX);


    VkRayTracingPipelineCreateInfoKHR rayPipelineInfo = {};
    rayPipelineInfo.sType = VK_STRUCTURE_TYPE_RAY_TRACING_PIPELINE_CREATE_INFO_KHR;
    rayPipelineInfo.stageCount = mShaderBindingTable.GetNumStages();
    rayPipelineInfo.pStages = mShaderBindingTable.GetStages();
    rayPipelineInfo.groupCount = mShaderBindingTable.GetNumGroups(); // 1-raygen, n-miss, n-(hit[+anyhit+intersect])
    rayPipelineInfo.pGroups = mShaderBindingTable.GetGroups();
    rayPipelineInfo.maxRecursionDepth = 1;
    rayPipelineInfo.layout = mRTPipelineLayout;
    rayPipelineInfo.libraries.sType = VK_STRUCTURE_TYPE_PIPELINE_LIBRARY_CREATE_INFO_KHR;

    error = vkCreateRayTracingPipelinesKHR(mDevice, VK_NULL_HANDLE, 1, &rayPipelineInfo, VK_NULL_HANDLE, &mRTPipeline);
    CHECK_VK_ERROR(error, "vkCreateRayTracingPipelinesKHR");

    mShaderBindingTable.CreateSBT(mDevice, mRTPipeline);
}

void RayTracerApp::UpdateDescriptorSets() {
	const uint32_t numMeshes = static_cast<uint32_t>(mScene.meshes.size());
    std::vector<VkDescriptorPoolSize> poolSizes({
        { VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR, 1 },       // top-level AS
        { VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1 },                    // output image
		 { VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 2 },                   //  Camera uniform & general uniform
	    { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, numMeshes * 3 },       // vertex attribs+faces+infos for each mesh
																	
		});

    VkDescriptorPoolCreateInfo descriptorPoolCreateInfo;
    descriptorPoolCreateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    descriptorPoolCreateInfo.pNext = nullptr;
    descriptorPoolCreateInfo.flags = 0;
	descriptorPoolCreateInfo.maxSets =  SWS_NUM_SETS;
    descriptorPoolCreateInfo.poolSizeCount = static_cast<uint32_t>(poolSizes.size());
    descriptorPoolCreateInfo.pPoolSizes = poolSizes.data();

    VkResult error = vkCreateDescriptorPool(mDevice, &descriptorPoolCreateInfo, nullptr, &mRTDescriptorPool);
    CHECK_VK_ERROR(error, "vkCreateDescriptorPool");

	mRTDescriptorSets.resize(SWS_NUM_SETS);

	Array<uint32_t> variableDescriptorCounts({
		1,
		numMeshes,      // vertex attribs for each mesh
		numMeshes,      // faces buffer for each mesh
		numMeshes,      // infos buffer for each mesh
		});

	VkDescriptorSetVariableDescriptorCountAllocateInfo variableDescriptorCountInfo;
	variableDescriptorCountInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO;
	variableDescriptorCountInfo.pNext = nullptr;
	variableDescriptorCountInfo.descriptorSetCount = SWS_NUM_SETS;
	variableDescriptorCountInfo.pDescriptorCounts = variableDescriptorCounts.data(); // actual number of descriptors

	VkDescriptorSetAllocateInfo descriptorSetAllocateInfo;
	descriptorSetAllocateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
	descriptorSetAllocateInfo.pNext = &variableDescriptorCountInfo;
	descriptorSetAllocateInfo.descriptorPool = mRTDescriptorPool;
	descriptorSetAllocateInfo.descriptorSetCount = SWS_NUM_SETS;
	descriptorSetAllocateInfo.pSetLayouts = mRTDescriptorSetsLayouts.data();

	error = vkAllocateDescriptorSets(mDevice, &descriptorSetAllocateInfo, mRTDescriptorSets.data());
    CHECK_VK_ERROR(error, "vkAllocateDescriptorSets");

    ///////////////////////////////////////////////////////////

    VkWriteDescriptorSetAccelerationStructureKHR descriptorAccelerationStructureInfo;
    descriptorAccelerationStructureInfo.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR;
    descriptorAccelerationStructureInfo.pNext = nullptr;
    descriptorAccelerationStructureInfo.accelerationStructureCount = 1;
    descriptorAccelerationStructureInfo.pAccelerationStructures = &mScene.topLevelAS.accelerationStructure;

    VkWriteDescriptorSet accelerationStructureWrite;
    accelerationStructureWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    accelerationStructureWrite.pNext = &descriptorAccelerationStructureInfo; // Notice that pNext is assigned here!
	accelerationStructureWrite.dstSet = mRTDescriptorSets[SWS_SCENE_AS_SET];
	accelerationStructureWrite.dstBinding = SWS_SCENE_AS_BINDING;
    accelerationStructureWrite.dstArrayElement = 0;
    accelerationStructureWrite.descriptorCount = 1;
    accelerationStructureWrite.descriptorType = VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR;
    accelerationStructureWrite.pImageInfo = nullptr;
    accelerationStructureWrite.pBufferInfo = nullptr;
    accelerationStructureWrite.pTexelBufferView = nullptr;

    ///////////////////////////////////////////////////////////

    VkDescriptorImageInfo descriptorOutputImageInfo;
    descriptorOutputImageInfo.sampler = VK_NULL_HANDLE;
    descriptorOutputImageInfo.imageView = mOffscreenImage.GetImageView();
    descriptorOutputImageInfo.imageLayout = VK_IMAGE_LAYOUT_GENERAL;

    VkWriteDescriptorSet resultImageWrite;
    resultImageWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    resultImageWrite.pNext = nullptr;
	resultImageWrite.dstSet = mRTDescriptorSets[SWS_RESULT_IMAGE_SET];
	resultImageWrite.dstBinding = SWS_RESULT_IMAGE_BINDING;
    resultImageWrite.dstArrayElement = 0;
    resultImageWrite.descriptorCount = 1;
    resultImageWrite.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    resultImageWrite.pImageInfo = &descriptorOutputImageInfo;
    resultImageWrite.pBufferInfo = nullptr;
    resultImageWrite.pTexelBufferView = nullptr;
	///////////////////////////////////////////////////////////

	VkWriteDescriptorSet attribsBufferWrite;
	attribsBufferWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
	attribsBufferWrite.pNext = nullptr;
	attribsBufferWrite.dstSet = mRTDescriptorSets[SWS_ATTRIBS_SET];
	attribsBufferWrite.dstBinding = 0;
	attribsBufferWrite.dstArrayElement = 0;
	attribsBufferWrite.descriptorCount = numMeshes;
	attribsBufferWrite.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
	attribsBufferWrite.pImageInfo = nullptr;
	attribsBufferWrite.pBufferInfo = mScene.attribsBufferInfos.data();
	attribsBufferWrite.pTexelBufferView = nullptr;
	///////////////////////////////////////////////////////////
	VkWriteDescriptorSet facesBufferWrite;
	facesBufferWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
	facesBufferWrite.pNext = nullptr;
	facesBufferWrite.dstSet = mRTDescriptorSets[SWS_FACES_SET];
	facesBufferWrite.dstBinding = 0;
	facesBufferWrite.dstArrayElement = 0;
	facesBufferWrite.descriptorCount = numMeshes;
	facesBufferWrite.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
	facesBufferWrite.pImageInfo = nullptr;
	facesBufferWrite.pBufferInfo = mScene.facesBufferInfos.data();
	facesBufferWrite.pTexelBufferView = nullptr;

	/////////////////////////////////////////////////////////// 
	VkWriteDescriptorSet meshInfoBufferWrite;
	meshInfoBufferWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
	meshInfoBufferWrite.pNext = nullptr;
	meshInfoBufferWrite.dstSet = mRTDescriptorSets[SWS_MESHINFO_SET];
	meshInfoBufferWrite.dstBinding = 0;
	meshInfoBufferWrite.dstArrayElement = 0;
	meshInfoBufferWrite.descriptorCount = numMeshes;
	meshInfoBufferWrite.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
	meshInfoBufferWrite.pImageInfo = nullptr;
	meshInfoBufferWrite.pBufferInfo = mScene.meshInfoBufferInfos.data();
	meshInfoBufferWrite.pTexelBufferView = nullptr;

	/////////////////////////////////////////////////////////// 
	VkDescriptorBufferInfo camdataBufferInfo;
	camdataBufferInfo.buffer = mCameraBuffer.GetBuffer();
	camdataBufferInfo.offset = 0;
	camdataBufferInfo.range = mCameraBuffer.GetSize();

	VkWriteDescriptorSet camdataBufferWrite;
	camdataBufferWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
	camdataBufferWrite.pNext = nullptr;
	camdataBufferWrite.dstSet = mRTDescriptorSets[SWS_CAMDATA_SET];
	camdataBufferWrite.dstBinding = SWS_CAMDATA_BINDING;
	camdataBufferWrite.dstArrayElement = 0;
	camdataBufferWrite.descriptorCount = 1;
	camdataBufferWrite.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
	camdataBufferWrite.pImageInfo = nullptr;
	camdataBufferWrite.pBufferInfo = &camdataBufferInfo;
	camdataBufferWrite.pTexelBufferView = nullptr;
	/////////////////////////////////////////////////////////// 
	VkDescriptorBufferInfo uniformParamsBufferInfo;
	uniformParamsBufferInfo.buffer = mUniformParamsBuffer.GetBuffer();
	uniformParamsBufferInfo.offset = 0;
	uniformParamsBufferInfo.range = mUniformParamsBuffer.GetSize();

	VkWriteDescriptorSet uniformParamsBufferWrite;
	uniformParamsBufferWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
	uniformParamsBufferWrite.pNext = nullptr;
	uniformParamsBufferWrite.dstSet = mRTDescriptorSets[SWS_UNIFORMPARAMS_SET];
	uniformParamsBufferWrite.dstBinding = SWS_UNIFORMPARAMS_BINDING;
	uniformParamsBufferWrite.dstArrayElement = 0;
	uniformParamsBufferWrite.descriptorCount = 1;
	uniformParamsBufferWrite.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
	uniformParamsBufferWrite.pImageInfo = nullptr;
	uniformParamsBufferWrite.pBufferInfo = &uniformParamsBufferInfo;
	uniformParamsBufferWrite.pTexelBufferView = nullptr;
	///////////////////////////////////////////////////////////

    Array<VkWriteDescriptorSet> descriptorWrites({
        accelerationStructureWrite,
        resultImageWrite,
		//
	   attribsBufferWrite,
	   //
	   facesBufferWrite,
	   //
	   meshInfoBufferWrite,
	   //
	   camdataBufferWrite,
	   //
	   uniformParamsBufferWrite,
    });

    vkUpdateDescriptorSets(mDevice, static_cast<uint32_t>(descriptorWrites.size()), descriptorWrites.data(), 0, VK_NULL_HANDLE);
}


///////////////////////////// SBT Helper class/////////////////////////////////////////////////

static uint32_t AlignUp(const uint32_t value, const uint32_t align) {
    return (value + align - 1) & ~(align - 1);
}

SBTHelper::SBTHelper()
    : mShaderHandleSize(0u)
    , mShaderGroupAlignment(0u)
    , mNumHitGroups(0u)
    , mNumMissGroups(0u) {
}

void SBTHelper::Initialize(const uint32_t numHitGroups, const uint32_t numMissGroups, const uint32_t shaderHandleSize, const uint32_t shaderGroupAlignment) {
    mShaderHandleSize = shaderHandleSize;
    mShaderGroupAlignment = shaderGroupAlignment;
    mNumHitGroups = numHitGroups;
    mNumMissGroups = numMissGroups;

    mNumHitShaders.resize(numHitGroups, 0u);
    mNumMissShaders.resize(numMissGroups, 0u);

    mStages.clear();
    mGroups.clear();
}

void SBTHelper::Destroy() {
    mNumHitShaders.clear();
    mNumMissShaders.clear();
    mStages.clear();
    mGroups.clear();

    mSBTBuffer.Destroy();
}

void SBTHelper::SetRaygenStage(const VkPipelineShaderStageCreateInfo& stage) {
    // this shader stage should go first!
    assert(mStages.empty());
    mStages.push_back(stage);

    VkRayTracingShaderGroupCreateInfoKHR groupInfo = {};
    groupInfo.sType = VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR;
    groupInfo.type = VK_RAY_TRACING_SHADER_GROUP_TYPE_GENERAL_KHR;
    groupInfo.generalShader = 0;
    groupInfo.closestHitShader = VK_SHADER_UNUSED_KHR;
    groupInfo.anyHitShader = VK_SHADER_UNUSED_KHR;
    groupInfo.intersectionShader = VK_SHADER_UNUSED_KHR;
    mGroups.push_back(groupInfo); // group 0 is always for raygen
}

void SBTHelper::AddStageToHitGroup(const Array<VkPipelineShaderStageCreateInfo>& stages, const uint32_t groupIndex) {
    // raygen stage should go first!
    assert(!mStages.empty());

    assert(groupIndex < mNumHitShaders.size());
    assert(!stages.empty() && stages.size() <= 3);// only 3 hit shaders per group (intersection, any-hit and closest-hit)
    assert(mNumHitShaders[groupIndex] == 0);

    uint32_t offset = 1; // there's always raygen shader

    for (uint32_t i = 0; i <= groupIndex; ++i) {
        offset += mNumHitShaders[i];
    }

    auto itStage = mStages.begin() + offset;
    mStages.insert(itStage, stages.begin(), stages.end());

    VkRayTracingShaderGroupCreateInfoKHR groupInfo = {};
    groupInfo.sType = VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR;
    groupInfo.type = VK_RAY_TRACING_SHADER_GROUP_TYPE_TRIANGLES_HIT_GROUP_KHR;
    groupInfo.generalShader = VK_SHADER_UNUSED_KHR;
    groupInfo.closestHitShader = VK_SHADER_UNUSED_KHR;
    groupInfo.anyHitShader = VK_SHADER_UNUSED_KHR;
    groupInfo.intersectionShader = VK_SHADER_UNUSED_KHR;

    for (size_t i = 0; i < stages.size(); i++) {
        const VkPipelineShaderStageCreateInfo& stageInfo = stages[i];
        const uint32_t shaderIdx = static_cast<uint32_t>(offset + i);

        if (stageInfo.stage == VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR) {
            groupInfo.closestHitShader = shaderIdx;
        } else if (stageInfo.stage == VK_SHADER_STAGE_ANY_HIT_BIT_KHR) {
            groupInfo.anyHitShader = shaderIdx;
        }
    };

    mGroups.insert((mGroups.begin() + 1 + groupIndex), groupInfo);

    mNumHitShaders[groupIndex] += static_cast<uint32_t>(stages.size());
}

void SBTHelper::AddStageToMissGroup(const VkPipelineShaderStageCreateInfo& stage, const uint32_t groupIndex) {
    // raygen stage should go first!
    assert(!mStages.empty());

    assert(groupIndex < mNumMissShaders.size());
    assert(mNumMissShaders[groupIndex] == 0); // only 1 miss shader per group

    uint32_t offset = 1; // there's always raygen shader

    // now skip all hit shaders
    for (const uint32_t numHitShader : mNumHitShaders) {
        offset += numHitShader;
    }

    for (uint32_t i = 0; i <= groupIndex; ++i) {
        offset += mNumMissShaders[i];
    }

    mStages.insert(mStages.begin() + offset, stage);

    // group create info 
    VkRayTracingShaderGroupCreateInfoKHR groupInfo = {};
    groupInfo.sType = VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR;
    groupInfo.type = VK_RAY_TRACING_SHADER_GROUP_TYPE_GENERAL_KHR;
    groupInfo.generalShader = offset;
    groupInfo.closestHitShader = VK_SHADER_UNUSED_KHR;
    groupInfo.anyHitShader = VK_SHADER_UNUSED_KHR;
    groupInfo.intersectionShader = VK_SHADER_UNUSED_KHR;

    // group 0 is always for raygen, then go hit shaders
    mGroups.insert((mGroups.begin() + (groupIndex + 1 + mNumHitGroups)), groupInfo);

    mNumMissShaders[groupIndex]++;
}

uint32_t SBTHelper::GetGroupsStride() const {
    return mShaderGroupAlignment;
}

uint32_t SBTHelper::GetNumGroups() const {
    return 1 + mNumHitGroups + mNumMissGroups;
}

uint32_t SBTHelper::GetRaygenOffset() const {
    return 0;
}

uint32_t SBTHelper::GetRaygenSize() const {
    return mShaderGroupAlignment;
}

uint32_t SBTHelper::GetHitGroupsOffset() const {
    return this->GetRaygenOffset() + this->GetRaygenSize();
}

uint32_t SBTHelper::GetHitGroupsSize() const {
    return mNumHitGroups * mShaderGroupAlignment;
}

uint32_t SBTHelper::GetMissGroupsOffset() const {
    return this->GetHitGroupsOffset() + this->GetHitGroupsSize();
}

uint32_t SBTHelper::GetMissGroupsSize() const {
    return mNumMissGroups * mShaderGroupAlignment;
}

uint32_t SBTHelper::GetNumStages() const {
    return static_cast<uint32_t>(mStages.size());
}

const VkPipelineShaderStageCreateInfo* SBTHelper::GetStages() const {
    return mStages.data();
}

const VkRayTracingShaderGroupCreateInfoKHR* SBTHelper::GetGroups() const {
    return mGroups.data();
}

uint32_t SBTHelper::GetSBTSize() const {
    return this->GetNumGroups() * mShaderGroupAlignment;
}

bool SBTHelper::CreateSBT(VkDevice device, VkPipeline rtPipeline) {
    const size_t sbtSize = this->GetSBTSize();

    VkResult error = mSBTBuffer.Create(sbtSize, VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_RAY_TRACING_BIT_KHR, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    CHECK_VK_ERROR(error, "mSBT.Create");

    if (VK_SUCCESS != error) {
        return false;
    }

    // get shader group handles
    Array<uint8_t> groupHandles(this->GetNumGroups() * mShaderHandleSize);
    error = vkGetRayTracingShaderGroupHandlesKHR(device, rtPipeline, 0, this->GetNumGroups(), groupHandles.size(), groupHandles.data());
    CHECK_VK_ERROR(error, L"vkGetRayTracingShaderGroupHandlesKHR");

    // now we fill our SBT
    uint8_t* mem = static_cast<uint8_t*>(mSBTBuffer.Map());
    for (size_t i = 0; i < this->GetNumGroups(); ++i) {
        memcpy(mem, groupHandles.data() + i * mShaderHandleSize, mShaderHandleSize);
        mem += mShaderGroupAlignment;
    }
    mSBTBuffer.Unmap();

    return (VK_SUCCESS == error);
}

VkBuffer SBTHelper::GetSBTBuffer() const {
    return mSBTBuffer.GetBuffer();
}

///////////////////////////// end SBTHelper ///////////////////////////////////////