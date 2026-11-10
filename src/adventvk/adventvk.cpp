#include "adventvk.h"

#include "vk-bootstrap/src/VkBootstrap.h"

#include "bridge_alloc.h"

#include <iostream>
#include <iomanip>

struct VkNativeData
{
    vkb::Instance instance;
    vkb::PhysicalDevice physical_device;
    vkb::Device device;
};

VkData setupVulkan(VkAllocationCallbacks* allocator, PFN_vkDebugUtilsMessengerCallbackEXT callback)
{
    adventvk::g_cb = allocator;

    vkb::InstanceBuilder builder;
    auto inst_ret = builder.set_app_name("adventz")
                    .request_validation_layers()
                    .set_debug_callback(callback)
                    .set_headless()
                    .require_api_version(1, 2)
                    .set_allocation_callbacks(allocator)
                    .build();
                

    if (!inst_ret)
    {
        std::cerr << "failed to create vulkan instance" << std::endl;
        return {};
    }

    VkNativeData* native_data = adventvk::create<VkNativeData>(VK_SYSTEM_ALLOCATION_SCOPE_INSTANCE);

    native_data->instance = inst_ret.value();

    vkb::PhysicalDeviceSelector selector(native_data->instance);
    auto phys_ret = selector.set_minimum_version(1, 2)
                    .select();

    if (!phys_ret)
    {
        std::cerr << "failed to select vulkan physical device" << std::endl;
        return {};
    }
                    
    native_data->physical_device = phys_ret.value();

    vkb::DeviceBuilder device_builder(phys_ret.value());
    auto dev_ret = device_builder.set_allocation_callbacks(allocator)
                    .build();
    
    if (!dev_ret)
    {
        std::cerr << "failed to create vulkan device" << std::endl;
        return {};
    }

    native_data->device = dev_ret.value();

    auto compute_queue_ret = native_data->device.get_queue(vkb::QueueType::compute);
    if (!compute_queue_ret)
    {
        std::cerr << "failed to get compute queue" << std::endl;
        return {};
    }

    uint32_t compute_family;
    auto compute_index = native_data->device.get_queue_index(vkb::QueueType::compute);
    if (compute_index)
        compute_family = compute_index.value();
    else
        compute_family = native_data->device.get_queue_index(vkb::QueueType::graphics).value();

    VkQueue compute_queue = compute_index.has_value() ? native_data->device.get_queue(vkb::QueueType::compute).value() : native_data->device.get_queue(vkb::QueueType::graphics).value();

    VkData data{
        .instance = native_data->instance.instance,
        .allocator = allocator,
        .physical_device = native_data->physical_device.physical_device,
        .device = native_data->device.device,
        .queue = compute_queue,
        .native_data = native_data
    };

    return data;
}

void releaseVulkan(VkData* data)
{
    VkNativeData* native_data = reinterpret_cast<VkNativeData*>(data->native_data);

    vkb::destroy_device(native_data->device);
    vkb::destroy_instance(native_data->instance);

    adventvk::destroy(native_data);
}
