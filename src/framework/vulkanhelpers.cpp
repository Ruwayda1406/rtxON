#include "vulkanhelpers.h"
#include <string>
#include <vector>
#include <fstream>
#include <cstring> // for memcpy

namespace vulkanhelpers {

void Initialize(VkPhysicalDevice physicalDevice, VkDevice device, VkCommandPool commandPool, VkQueue transferQueue) {
    __details::sPhysDevice = physicalDevice;
    __details::sDevice = device;
    __details::sCommandPool = commandPool;
    __details::sTransferQueue = transferQueue;

    vkGetPhysicalDeviceMemoryProperties(physicalDevice, &__details::sPhysicalDeviceMemoryProperties);
}

uint32_t GetMemoryType(VkMemoryRequirements& memoryRequiriments, VkMemoryPropertyFlags memoryProperties) {
    uint32_t result = 0;
    for (uint32_t memoryTypeIndex = 0; memoryTypeIndex < VK_MAX_MEMORY_TYPES; ++memoryTypeIndex) {
        if (memoryRequiriments.memoryTypeBits & (1 << memoryTypeIndex)) {
            if ((__details::sPhysicalDeviceMemoryProperties.memoryTypes[memoryTypeIndex].propertyFlags & memoryProperties) == memoryProperties) {
                result = memoryTypeIndex;
                break;
            }
        }
    }
    return result;
}

void ImageBarrier(VkCommandBuffer commandBuffer,
                  VkImage image,
                  VkImageSubresourceRange& subresourceRange,
                  VkAccessFlags srcAccessMask,
                  VkAccessFlags dstAccessMask,
                  VkImageLayout oldLayout,
                  VkImageLayout newLayout) {

    VkImageMemoryBarrier imageMemoryBarrier;
    imageMemoryBarrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    imageMemoryBarrier.pNext = nullptr;
    imageMemoryBarrier.srcAccessMask = srcAccessMask;
    imageMemoryBarrier.dstAccessMask = dstAccessMask;
    imageMemoryBarrier.oldLayout = oldLayout;
    imageMemoryBarrier.newLayout = newLayout;
    imageMemoryBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    imageMemoryBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    imageMemoryBarrier.image = image;
    imageMemoryBarrier.subresourceRange = subresourceRange;

    vkCmdPipelineBarrier(commandBuffer,
                         VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
                         VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
                         0, 0, nullptr, 0, nullptr, 1,
                         &imageMemoryBarrier);
}



Buffer::Buffer()
    : mBuffer(VK_NULL_HANDLE)
    , mMemory(VK_NULL_HANDLE)
    , mSize(0)
{
}
Buffer::~Buffer() {
    this->Destroy();
}

VkResult Buffer::Create(VkDeviceSize size, VkBufferUsageFlags usage, VkMemoryPropertyFlags memoryProperties) {
    VkResult result = VK_SUCCESS;

    VkBufferCreateInfo bufferCreateInfo;
    bufferCreateInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bufferCreateInfo.pNext = nullptr;
    bufferCreateInfo.flags = 0;
    bufferCreateInfo.size = size;
    bufferCreateInfo.usage = usage;
    bufferCreateInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    bufferCreateInfo.queueFamilyIndexCount = 0;
    bufferCreateInfo.pQueueFamilyIndices = nullptr;

    mSize = size;

    result = vkCreateBuffer(__details::sDevice, &bufferCreateInfo, nullptr, &mBuffer);
    if (VK_SUCCESS == result) {
        VkMemoryRequirements memoryRequirements;
        vkGetBufferMemoryRequirements(__details::sDevice, mBuffer, &memoryRequirements);

        VkMemoryAllocateInfo memoryAllocateInfo;
        memoryAllocateInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        memoryAllocateInfo.pNext = nullptr;
        memoryAllocateInfo.allocationSize = memoryRequirements.size;
        memoryAllocateInfo.memoryTypeIndex = GetMemoryType(memoryRequirements, memoryProperties);

        VkMemoryAllocateFlagsInfo allocationFlags = {};
        allocationFlags.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO;
        allocationFlags.flags = VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT;
        if ((usage & VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT) == VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT) {
            memoryAllocateInfo.pNext = &allocationFlags;
        }

        result = vkAllocateMemory(__details::sDevice, &memoryAllocateInfo, nullptr, &mMemory);
        if (VK_SUCCESS != result) {
            vkDestroyBuffer(__details::sDevice, mBuffer, nullptr);
            mBuffer = VK_NULL_HANDLE;
            mMemory = VK_NULL_HANDLE;
        } else {
            result = vkBindBufferMemory(__details::sDevice, mBuffer, mMemory, 0);
            if (VK_SUCCESS != result) {
                vkDestroyBuffer(__details::sDevice, mBuffer, nullptr);
                vkFreeMemory(__details::sDevice, mMemory, nullptr);
                mBuffer = VK_NULL_HANDLE;
                mMemory = VK_NULL_HANDLE;
            }
        }
    }

    return result;
}

void Buffer::Destroy() {
    if (mBuffer) {
        vkDestroyBuffer(__details::sDevice, mBuffer, nullptr);
        mBuffer = VK_NULL_HANDLE;
    }
    if (mMemory) {
        vkFreeMemory(__details::sDevice, mMemory, nullptr);
        mMemory = VK_NULL_HANDLE;
    }
}

void* Buffer::Map(VkDeviceSize size, VkDeviceSize offset) const {
    void* mem = nullptr;

    if (size > mSize) {
        size = mSize;
    }

    VkResult result = vkMapMemory(__details::sDevice, mMemory, offset, size, 0, &mem);
   if (VK_SUCCESS != result) {
        mem = nullptr;
    }

    return mem;
}
void Buffer::Unmap() const {
    vkUnmapMemory(__details::sDevice, mMemory);
}

bool Buffer::UploadData(const void* data, VkDeviceSize size, VkDeviceSize offset) const {
    bool result = false;

    void* mem = this->Map(size, offset);
    if (mem) {
        std::memcpy(mem, data, size);
        this->Unmap();
    }
    return true;
}

// getters
VkBuffer Buffer::GetBuffer() const {
    return mBuffer;
}

VkDeviceSize Buffer::GetSize() const {
    return mSize;
}



Image::Image()
    : mFormat(VK_FORMAT_B8G8R8A8_UNORM)
    , mImage(VK_NULL_HANDLE)
    , mMemory(VK_NULL_HANDLE)
    , mImageView(VK_NULL_HANDLE)
    , mSampler(VK_NULL_HANDLE)
{

}
Image::~Image() {
    this->Destroy();
}

VkResult Image::Create(VkImageType imageType,
                       VkFormat format,
                       VkExtent3D extent,
                       VkImageTiling tiling,
                       VkImageUsageFlags usage,
                       VkMemoryPropertyFlags memoryProperties) {
    VkResult result = VK_SUCCESS;

    mFormat = format;

    VkImageCreateInfo imageCreateInfo = {};
    imageCreateInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    imageCreateInfo.imageType = imageType;
    imageCreateInfo.format = format;
    imageCreateInfo.extent = extent;
    imageCreateInfo.mipLevels = 1;
    imageCreateInfo.arrayLayers = 1;
    imageCreateInfo.samples = VK_SAMPLE_COUNT_1_BIT;
    imageCreateInfo.tiling = tiling;
    imageCreateInfo.usage = usage;
    imageCreateInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    imageCreateInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    result = vkCreateImage(__details::sDevice, &imageCreateInfo, nullptr, &mImage);
    if (VK_SUCCESS == result) {
        VkMemoryRequirements memoryRequirements = {};
        vkGetImageMemoryRequirements(__details::sDevice, mImage, &memoryRequirements);

        VkMemoryAllocateInfo memoryAllocateInfo = {};
        memoryAllocateInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        memoryAllocateInfo.allocationSize = memoryRequirements.size;
        memoryAllocateInfo.memoryTypeIndex = GetMemoryType(memoryRequirements, memoryProperties);

        result = vkAllocateMemory(__details::sDevice, &memoryAllocateInfo, nullptr, &mMemory);
        if (VK_SUCCESS != result) {
            vkDestroyImage(__details::sDevice, mImage, nullptr);
            mImage = VK_NULL_HANDLE;
            mMemory = VK_NULL_HANDLE;
        } else {
            result = vkBindImageMemory(__details::sDevice, mImage, mMemory, 0);
            if (VK_SUCCESS != result) {
                vkDestroyImage(__details::sDevice, mImage, nullptr);
                vkFreeMemory(__details::sDevice, mMemory, nullptr);
                mImage = VK_NULL_HANDLE;
                mMemory = VK_NULL_HANDLE;
            }
        }
    }

    return result;
}

void Image::Destroy() {
    if (mSampler) {
        vkDestroySampler(__details::sDevice, mSampler, nullptr);
        mSampler = VK_NULL_HANDLE;
    }
    if (mImageView) {
        vkDestroyImageView(__details::sDevice, mImageView, nullptr);
        mImageView = VK_NULL_HANDLE;
    }
    if (mMemory) {
        vkFreeMemory(__details::sDevice, mMemory, nullptr);
        mMemory = VK_NULL_HANDLE;
    }
    if (mImage) {
        vkDestroyImage(__details::sDevice, mImage, nullptr);
        mImage = VK_NULL_HANDLE;
    }
}

VkResult Image::CreateImageView(VkImageViewType viewType, VkFormat format, VkImageSubresourceRange subresourceRange) {
    VkImageViewCreateInfo imageViewCreateInfo;
    imageViewCreateInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    imageViewCreateInfo.pNext = nullptr;
    imageViewCreateInfo.viewType = viewType;
    imageViewCreateInfo.format = format;
    imageViewCreateInfo.subresourceRange = subresourceRange;
    imageViewCreateInfo.image = mImage;
    imageViewCreateInfo.flags = 0;
    imageViewCreateInfo.components = { VK_COMPONENT_SWIZZLE_R, VK_COMPONENT_SWIZZLE_G, VK_COMPONENT_SWIZZLE_B, VK_COMPONENT_SWIZZLE_A };

    return vkCreateImageView(__details::sDevice, &imageViewCreateInfo, nullptr, &mImageView);
}

// getters
VkFormat Image::GetFormat() const {
    return mFormat;
}

VkImage Image::GetImage() const {
    return mImage;
}

VkImageView Image::GetImageView() const {
    return mImageView;
}

VkSampler Image::GetSampler() const {
    return mSampler;
}



Shader::Shader()
    : mModule(VK_NULL_HANDLE)
{
}
Shader::~Shader() {
    this->Destroy();
}

bool Shader::LoadFromFile(const char* fileName) {
    bool result = false;

    std::ifstream file(fileName, std::ios::in | std::ios::binary);
    if (file) {
        file.seekg(0, std::ios::end);
        const size_t fileSize = file.tellg();
        file.seekg(0, std::ios::beg);

        std::vector<char> bytecode(fileSize);
        bytecode.assign((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());

        VkShaderModuleCreateInfo shaderModuleCreateInfo;
        shaderModuleCreateInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
        shaderModuleCreateInfo.pNext = nullptr;
        shaderModuleCreateInfo.codeSize = bytecode.size();
        shaderModuleCreateInfo.pCode = reinterpret_cast<uint32_t*>(bytecode.data());
        shaderModuleCreateInfo.flags = 0;

        const VkResult error = vkCreateShaderModule(__details::sDevice, &shaderModuleCreateInfo, nullptr, &mModule);
        result = (VK_SUCCESS == error);
    }

    return result;
}

void Shader::Destroy() {
    if (mModule) {
        vkDestroyShaderModule(__details::sDevice, mModule, nullptr);
        mModule = VK_NULL_HANDLE;
    }
}

VkPipelineShaderStageCreateInfo Shader::GetShaderStage(VkShaderStageFlagBits stage) {
    return VkPipelineShaderStageCreateInfo {
        /*sType*/ VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        /*pNext*/ nullptr,
        /*flags*/ 0,
        /*stage*/ stage,
        /*module*/ mModule,
        /*pName*/ "main",
        /*pSpecializationInfo*/ nullptr
    };
}



VkDeviceOrHostAddressKHR GetBufferDeviceAddress(const vulkanhelpers::Buffer& buffer) {
    VkBufferDeviceAddressInfoKHR info = {
        VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
        nullptr,
        buffer.GetBuffer()
    };

    VkDeviceOrHostAddressKHR result;
    result.deviceAddress = vkGetBufferDeviceAddressKHR(vulkanhelpers::__details::sDevice, &info);

    return result;
}

VkDeviceOrHostAddressConstKHR GetBufferDeviceAddressConst(const vulkanhelpers::Buffer& buffer) {
    VkDeviceOrHostAddressKHR address = GetBufferDeviceAddress(buffer);

    VkDeviceOrHostAddressConstKHR result;
    result.deviceAddress = address.deviceAddress;

    return result;
}

} // namespace vulkanhelpers
