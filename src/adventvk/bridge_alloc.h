#pragma once

#include <vulkan/vulkan.h>

#include <cassert>
#include <cstddef>
#include <limits>
#include <new>
#include <utility>

namespace adventvk {

    inline const VkAllocationCallbacks* g_cb = nullptr;

    inline void* vk_alloc(std::size_t size, std::size_t align, VkSystemAllocationScope scope = VK_SYSTEM_ALLOCATION_SCOPE_OBJECT)
    {
        assert(g_cb && "bridge_init not called");
        return g_cb->pfnAllocation(g_cb->pUserData, size, align, scope);
    }

    inline void* vk_realloc(void* p, std::size_t size, std::size_t align, VkSystemAllocationScope scope = VK_SYSTEM_ALLOCATION_SCOPE_OBJECT)
    {
        return g_cb->pfnReallocation(g_cb->pUserData, p, size, align, scope);
    }

    inline void vk_free(void* p)
    {
        if (p)
            g_cb->pfnFree(g_cb->pUserData, p);
    }

    template <class T, class... Args>
    T* create(VkSystemAllocationScope scope, Args&&... args)
    {
        void* mem = vk_alloc(sizeof(T), alignof(T), scope);
        if (!mem)
            return nullptr;
        try
        {
            return new (mem) T(std::forward<Args>(args)...);
        }
        catch (...) 
        {
            vk_free(mem);
            throw;
        }
    }

    template <class T>
    void destroy(T* p)
    {
        if (!p) return;
        p->~T();
        vk_free(p);
    }

    template<class T>
    struct VkStlAllocator
    {
        using value_type = T;
        VkSystemAllocationScope scope = VK_SYSTEM_ALLOCATION_SCOPE_OBJECT;

        VkStlAllocator() = default;
        template<class U>
        VkStlAllocator(const VkStlAllocator<U>& other) noexcept : scope(other.scope) {}

        T* allocate(std::size_t n)
        {
            if (n > std::numeric_limits<std::size_t>::max() / sizeof(T))
                throw std::bad_array_new_length();
            void* p = vk_alloc(n * sizeof(T), alignof(T), scope);
            if (!p)
                throw std::bad_alloc();
            return static_cast<T*>(p);
        }

        void deallocate(T* p, std::size_t) noexcept { vk_free(p); }

        template<class U> bool operator==(const VkStlAllocator<U>&) const noexcept { return true; }
        template<class U> bool operator!=(const VkStlAllocator<U>&) const noexcept { return false; }
    };

}
