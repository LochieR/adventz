#pragma once

#include <vulkan/vulkan.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct VkData
{
    VkInstance instance;
    VkAllocationCallbacks* allocator;
    VkPhysicalDevice physical_device;
    VkDevice device;
    VkQueue queue;
    uint32_t queueFamily;
    
    void* native_data;
} VkData;

VkData setupVulkan(VkAllocationCallbacks* allocator, PFN_vkDebugUtilsMessengerCallbackEXT callback);
void releaseVulkan(VkData* data);

#ifdef __cplusplus
}
#endif
