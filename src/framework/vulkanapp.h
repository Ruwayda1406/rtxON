#include "vulkanhelpers.h"

#include "GLFW/glfw3.h"

#include "common.h"

struct AppSettings {
    std::string name;
    uint32_t    resolutionX;
    uint32_t    resolutionY;
    VkFormat    surfaceFormat;
    bool        enableValidation;
    bool        supportRaytracing;
    bool        supportDescriptorIndexing;
};

class VulkanApp {
public:
    VulkanApp();
    virtual ~VulkanApp();

    void    Run();

	

protected:
    bool    Initialize();
    void    Loop();
    void    Shutdown();

    void    InitializeSettings();
    bool    InitializeVulkan();
    bool    InitializeDevicesAndQueues();
    bool    InitializeSurface();
    bool    InitializeSwapchain();
    bool    InitializeFencesAndCommandPool();
    bool    InitializeOffscreenImage();
    bool    InitializeCommandBuffers();
    bool    InitializeSynchronization();
    void    FillCommandBuffers();

    //
    void    ProcessFrame(const float dt);
    void    FreeVulkan();

    // to be overriden by subclasses
    virtual void InitSettings();
    virtual void InitApp();
    virtual void FreeResources();
    virtual void FillCommandBuffer(VkCommandBuffer commandBuffer, const size_t imageIndex);

    virtual void OnMouseMove(const float x, const float y);
    virtual void OnMouseButton(const int button, const int action, const int mods);
    virtual void OnKey(const int key, const int scancode, const int action, const int mods);
    virtual void Update(const size_t imageIndex, const float dt);
protected:
	GLFWwindow* window;
    AppSettings             mSettings;
    GLFWwindow*             mWindow;

    VkInstance              mInstance;
    VkPhysicalDevice        mPhysicalDevice;
    VkDevice                mDevice;
    VkSurfaceFormatKHR      mSurfaceFormat;
    VkSurfaceKHR            mSurface;
    VkSwapchainKHR          mSwapchain;
    Array<VkImage>          mSwapchainImages;
    Array<VkImageView>      mSwapchainImageViews;
    Array<VkFence>          mWaitForFrameFences;
    VkCommandPool           mCommandPool;
    vulkanhelpers::Image    mOffscreenImage;
    Array<VkCommandBuffer>  mCommandBuffers;
    VkSemaphore             mSemaphoreImageAcquired;
    VkSemaphore             mSemaphoreRenderFinished;

    uint32_t                mGraphicsQueueFamilyIndex;
    uint32_t                mComputeQueueFamilyIndex;
    uint32_t                mTransferQueueFamilyIndex;
    VkQueue                 mGraphicsQueue;
    VkQueue                 mComputeQueue;
    VkQueue                 mTransferQueue;

    // RTX stuff
    VkPhysicalDeviceRayTracingPropertiesKHR mRTProps;
};
