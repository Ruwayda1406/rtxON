#pragma once

#include "framework/vulkanapp.h"

struct RTAccelerationStructure {
    VkDeviceMemory                          memory;
    VkAccelerationStructureCreateInfoKHR    accelerationStructureInfo;
    VkAccelerationStructureKHR              accelerationStructure;
    VkDeviceAddress                         handle;
};
struct RTMesh {
	uint32_t                    numVertices;
	uint32_t                    numFaces;

	vulkanhelpers::Buffer       positions;
	vulkanhelpers::Buffer       attribs;
	vulkanhelpers::Buffer       indices;
	vulkanhelpers::Buffer       faces;

	RTAccelerationStructure     blas;
};
struct RTScene {
	Array<RTMesh>                   meshes;
	RTAccelerationStructure         topLevelAS;

	// shader resources stuff
	//Array<VkDescriptorBufferInfo>   matIDsBufferInfos;
	Array<VkDescriptorBufferInfo>   attribsBufferInfos;
	Array<VkDescriptorBufferInfo>   facesBufferInfos;
	//Array<VkDescriptorImageInfo>    texturesInfos;
};

class SBTHelper {
public:
    SBTHelper();
    ~SBTHelper() = default;

    void        Initialize(const uint32_t numHitGroups, const uint32_t numMissGroups, const uint32_t shaderHandleSize, const uint32_t shaderGroupAlignment);
    void        Destroy();
    void        SetRaygenStage(const VkPipelineShaderStageCreateInfo& stage);
    void        AddStageToHitGroup(const Array<VkPipelineShaderStageCreateInfo>& stages, const uint32_t groupIndex);
    void        AddStageToMissGroup(const VkPipelineShaderStageCreateInfo& stage, const uint32_t groupIndex);

    uint32_t    GetGroupsStride() const;
    uint32_t    GetNumGroups() const;
    uint32_t    GetRaygenOffset() const;
    uint32_t    GetRaygenSize() const;
    uint32_t    GetHitGroupsOffset() const;
    uint32_t    GetHitGroupsSize() const;
    uint32_t    GetMissGroupsOffset() const;
    uint32_t    GetMissGroupsSize() const;

    uint32_t                                    GetNumStages() const;
    const VkPipelineShaderStageCreateInfo*      GetStages() const;
    const VkRayTracingShaderGroupCreateInfoKHR* GetGroups() const;

    uint32_t    GetSBTSize() const;
    bool        CreateSBT(VkDevice device, VkPipeline rtPipeline);
    VkBuffer    GetSBTBuffer() const;

private:
    uint32_t                                    mShaderHandleSize;
    uint32_t                                    mShaderGroupAlignment;
    uint32_t                                    mNumHitGroups;
    uint32_t                                    mNumMissGroups;
    Array<uint32_t>                             mNumHitShaders;
    Array<uint32_t>                             mNumMissShaders;
    Array<VkPipelineShaderStageCreateInfo>      mStages;
    Array<VkRayTracingShaderGroupCreateInfoKHR> mGroups;
    vulkanhelpers::Buffer                       mSBTBuffer;
};


class RtxApp : public VulkanApp {
public:
    RtxApp();
    ~RtxApp();

protected:
    virtual void InitSettings() override;
    virtual void InitApp() override;
    virtual void FreeResources() override;
    virtual void FillCommandBuffer(VkCommandBuffer commandBuffer, const size_t imageIndex) override;
	void Update(const size_t, const float dt);
private:
    bool CreateAS(const VkAccelerationStructureTypeKHR type,
                  const uint32_t geometryCount,
                  const VkAccelerationStructureCreateGeometryTypeInfoKHR* geometries,
                  const uint32_t instanceCount,
                  RTAccelerationStructure& _as);
	void CreateCamera();
	void LoadSceneGeometry2();
	void LoadSceneGeometry();
    void CreateScene();
    void CreateDescriptorSetsLayouts();
    void CreateRaytracingPipelineAndSBT();
    void UpdateDescriptorSets();

private:
    VkPipeline                      mRTPipeline;
	VkPipelineLayout                mRTPipelineLayout;

    VkDescriptorPool                mRTDescriptorPool;
    //VkDescriptorSet          mRTDescriptorSet;
	//VkDescriptorSetLayout    mRTDescriptorSetsLayout;
	Array<VkDescriptorSet>          mRTDescriptorSets;
	Array<VkDescriptorSetLayout>    mRTDescriptorSetsLayouts;
    SBTHelper                       mSBT;
    RTScene                         mScene;
	// camera 
	struct Camera
{
	Recti   mViewport;
	float   mFov;
	float   mNear;
	float   mFar;
	vec3    mPosition;
	vec3    mLookAtPostion;
	vec3    mDirection;

	mat4    mProjection;
	mat4    mView;
	vec3    Up;

	Camera() : Up(0.0f, 1.0f, 0.0f)
		, mFov(45.0f)
		, mNear(0.1f)
		, mFar(100.0f)
		, mPosition(-1.0f, 2.5f, 7.0f) 
    {
		mLookAtPostion = mPosition + vec3(0, 0, -1);
		mDirection = glm::normalize(mLookAtPostion - mPosition);
	}
};
	Camera                          mCamera;
	vulkanhelpers::Buffer           mCameraBuffer;
};
