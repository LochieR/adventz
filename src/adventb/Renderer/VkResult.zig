//! Zig error handling for `VkResult`.
//!
//! Negative `VkResult` codes become members of `VkError`; non-negative codes
//! are successes (some carrying extra status, see `Status`).
//!
//!     try VkResult.check(vkCreateShaderModule(...));
//!     const status = try VkResult.checkStatus(vkWaitForFences(...));

const std = @import("std");
const vk = @import("adventvk");

pub const VkError = error{
    OutOfHostMemory,
    OutOfDeviceMemory,
    InitializationFailed,
    DeviceLost,
    MemoryMapFailed,
    LayerNotPresent,
    ExtensionNotPresent,
    FeatureNotPresent,
    IncompatibleDriver,
    TooManyObjects,
    FormatNotSupported,
    FragmentedPool,
    Unknown,
    ValidationFailed,
    OutOfPoolMemory,
    InvalidExternalHandle,
    Fragmentation,
    InvalidOpaqueCaptureAddress,
    NotPermitted,
    SurfaceLost,
    NativeWindowInUse,
    OutOfDate,
    IncompatibleDisplay,
    InvalidShader,
    ImageUsageNotSupported,
    VideoPictureLayoutNotSupported,
    VideoProfileOperationNotSupported,
    VideoProfileFormatNotSupported,
    VideoProfileCodecNotSupported,
    VideoStdVersionNotSupported,
    InvalidDrmFormatModifierPlaneLayout,
    FullScreenExclusiveModeLost,
    InvalidVideoStdParameters,
    CompressionExhausted,
    NotEnoughSpace,
};

/// Non-error (>= 0) result codes.
pub const Status = enum(c_int) {
    success = vk.VK_SUCCESS,
    not_ready = vk.VK_NOT_READY,
    timeout = vk.VK_TIMEOUT,
    event_set = vk.VK_EVENT_SET,
    event_reset = vk.VK_EVENT_RESET,
    incomplete = vk.VK_INCOMPLETE,
    pipeline_compile_required = vk.VK_PIPELINE_COMPILE_REQUIRED,
    suboptimal = vk.VK_SUBOPTIMAL_KHR,
    thread_idle = vk.VK_THREAD_IDLE_KHR,
    thread_done = vk.VK_THREAD_DONE_KHR,
    operation_deferred = vk.VK_OPERATION_DEFERRED_KHR,
    operation_not_deferred = vk.VK_OPERATION_NOT_DEFERRED_KHR,
    incompatible_shader_binary = vk.VK_INCOMPATIBLE_SHADER_BINARY_EXT,
    pipeline_binary_missing = vk.VK_PIPELINE_BINARY_MISSING_KHR,
    _,
};

/// Returns an error for negative results; any non-negative result is treated as success.
pub fn check(result: vk.VkResult) VkError!void {
    if (result < 0) return toError(result);
}

/// Like `check`, but hands back the non-error status (e.g. `.timeout`, `.not_ready`).
pub fn checkStatus(result: vk.VkResult) VkError!Status {
    if (result < 0) return toError(result);
    return @enumFromInt(result);
}

/// Maps a negative `VkResult` to its `VkError`. Unrecognised codes map to `error.Unknown`.
pub fn toError(result: vk.VkResult) VkError {
    std.debug.assert(result < 0);
    return switch (result) {
        vk.VK_ERROR_OUT_OF_HOST_MEMORY => error.OutOfHostMemory,
        vk.VK_ERROR_OUT_OF_DEVICE_MEMORY => error.OutOfDeviceMemory,
        vk.VK_ERROR_INITIALIZATION_FAILED => error.InitializationFailed,
        vk.VK_ERROR_DEVICE_LOST => error.DeviceLost,
        vk.VK_ERROR_MEMORY_MAP_FAILED => error.MemoryMapFailed,
        vk.VK_ERROR_LAYER_NOT_PRESENT => error.LayerNotPresent,
        vk.VK_ERROR_EXTENSION_NOT_PRESENT => error.ExtensionNotPresent,
        vk.VK_ERROR_FEATURE_NOT_PRESENT => error.FeatureNotPresent,
        vk.VK_ERROR_INCOMPATIBLE_DRIVER => error.IncompatibleDriver,
        vk.VK_ERROR_TOO_MANY_OBJECTS => error.TooManyObjects,
        vk.VK_ERROR_FORMAT_NOT_SUPPORTED => error.FormatNotSupported,
        vk.VK_ERROR_FRAGMENTED_POOL => error.FragmentedPool,
        vk.VK_ERROR_UNKNOWN => error.Unknown,
        vk.VK_ERROR_VALIDATION_FAILED => error.ValidationFailed,
        vk.VK_ERROR_OUT_OF_POOL_MEMORY => error.OutOfPoolMemory,
        vk.VK_ERROR_INVALID_EXTERNAL_HANDLE => error.InvalidExternalHandle,
        vk.VK_ERROR_FRAGMENTATION => error.Fragmentation,
        vk.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS => error.InvalidOpaqueCaptureAddress,
        vk.VK_ERROR_NOT_PERMITTED => error.NotPermitted,
        vk.VK_ERROR_SURFACE_LOST_KHR => error.SurfaceLost,
        vk.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => error.NativeWindowInUse,
        vk.VK_ERROR_OUT_OF_DATE_KHR => error.OutOfDate,
        vk.VK_ERROR_INCOMPATIBLE_DISPLAY_KHR => error.IncompatibleDisplay,
        vk.VK_ERROR_INVALID_SHADER_NV => error.InvalidShader,
        vk.VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR => error.ImageUsageNotSupported,
        vk.VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR => error.VideoPictureLayoutNotSupported,
        vk.VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR => error.VideoProfileOperationNotSupported,
        vk.VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR => error.VideoProfileFormatNotSupported,
        vk.VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR => error.VideoProfileCodecNotSupported,
        vk.VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR => error.VideoStdVersionNotSupported,
        vk.VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT => error.InvalidDrmFormatModifierPlaneLayout,
        vk.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => error.FullScreenExclusiveModeLost,
        vk.VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR => error.InvalidVideoStdParameters,
        vk.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => error.CompressionExhausted,
        vk.VK_ERROR_NOT_ENOUGH_SPACE_KHR => error.NotEnoughSpace,
        else => error.Unknown,
    };
}
