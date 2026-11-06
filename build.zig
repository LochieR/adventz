const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    const adventvk = b.addLibrary(.{
        .name = "adventvk",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libcpp = true
        })
    });
    adventvk.root_module.addCSourceFiles(.{
        .root = b.path("src/adventvk"),
        .files = &.{
            "VkBootstrap.cpp",
            "adventvk.cpp",
        },
        .language = .cpp,
        .flags = &.{ "-std=c++20" }
    });
    adventvk.root_module.addIncludePath(b.path("src/adventvk"));
    adventvk.root_module.addIncludePath(b.path("src/adventvk/include"));
    linkVulkan(b, adventvk.root_module);

    const adventvk_h = b.addTranslateC(.{
        .root_source_file = b.path("src/adventvk/include/adventvk.h"),
        .target = target,
        .optimize = optimize,
    });
    
    adventvk_h.addSystemIncludePath(.{ .cwd_relative = vulkanIncludeDir(b) });
    const adventvk_mod = adventvk_h.createModule();
    adventvk_mod.linkLibrary(adventvk);

    const exe = b.addExecutable(.{
        .name = "adventz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/adventz/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "adventvk", .module = adventvk_mod },
            },
        }),
    });
    linkVulkan(b, exe.root_module);

    exe.root_module.linkLibrary(adventvk);

    // `zig build shaders` compiles only the shaders; normal builds do it too.
    const shaders_step = b.step("shaders", "Compile Slang shaders");
    addShaders(b, shaders_step, buildShadergen(b));
    exe.step.dependOn(shaders_step);
    b.getInstallStep().dependOn(shaders_step);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
}

/// Builds the shadergen submodule as a release-mode host tool (equivalent of
/// its CMake Release config: -O2 + MC_RELEASE), so it can run during the build.
fn buildShadergen(b: *std.Build) *std.Build.Step.Compile {
    const sdk = shadergenSdkDir(b);
    const lib_dir = b.pathJoin(&.{ sdk, "lib" });

    const shadergen = b.addExecutable(.{
        .name = "shadergen",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .ReleaseFast,
            .link_libcpp = true,
        }),
    });
    const mod = shadergen.root_module;
    mod.addCSourceFiles(.{
        .root = b.path("shadergen"),
        .files = &.{ "main.cpp", "cli.cpp", "SlangCompiler.cpp", "ReflectionGenerator.cpp" },
        .language = .cpp,
        .flags = &.{"-std=c++23"},
    });
    mod.addCMacro("MC_RELEASE", "1");
    mod.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "include" }) });
    mod.addLibraryPath(.{ .cwd_relative = lib_dir });
    // slang is a shared library, so the loader needs the SDK lib dir at runtime.
    mod.addRPath(.{ .cwd_relative = lib_dir });
    for ([_][]const u8{ "slang", "spirv-cross-core", "spirv-cross-glsl", "spirv-cross-reflect" }) |lib| {
        mod.linkSystemLibrary(lib, .{});
    }
    return shadergen;
}

/// Vulkan SDK used by shadergen (needs slang + spirv-cross, which Homebrew's
/// Vulkan packages don't ship). Same default as shadergen's CMakeLists.
fn shadergenSdkDir(b: *std.Build) []const u8 {
    if (b.graph.environ_map.get("VULKAN_SDK")) |sdk| return sdk;
    const home = b.graph.environ_map.get("HOME") orelse "";
    return b.pathJoin(&.{ home, "VulkanSDK/1.4.328.1/macOS" });
}

/// Generated Zig files are copied into the source tree here so main.zig can
/// @import them and ZLS can see them.
const shaders_out_dir = "src/adventz/shaders";

fn addShaders(b: *std.Build, step: *std.Build.Step, shadergen: *std.Build.Step.Compile) void {
    const io = b.graph.io;
    // Copies into the source tree; only rewrites files whose contents changed.
    const update_src = b.addUpdateSourceFiles();
    step.dependOn(&update_src.step);
    var copied_types_file = false;
    
    b.dependOnDirectoryContents(b.path("shaders"));
    var dir = b.root.openDir(io, "shaders", .{ .iterate = true }) catch |err|
        std.debug.panic("failed to open shaders/: {t}", .{err});
    defer dir.close(io);

    var it = dir.iterate();
    while (it.next(io) catch |err| std.debug.panic("failed to read shaders/: {t}", .{err})) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".slang"))
            continue;

        const stem = entry.name[0 .. entry.name.len - ".slang".len];
        const out_name = b.fmt("{s}.slang.zig", .{stem});

        const cmd = b.addRunArtifact(shadergen);
        cmd.addArg("--embed-spv");
        cmd.addArg("--target-env");
        cmd.addArg("vulkan1.2");
        cmd.addArg("--output-lang");
        cmd.addArg("zig");
        cmd.addFileArg(b.path(b.fmt("shaders/{s}", .{entry.name})));
        cmd.addArg("-o");
        const generated = cmd.addOutputFileArg(out_name);
        update_src.addCopyFileToSource(generated, b.fmt("{s}/{s}", .{ shaders_out_dir, out_name }));

        // shadergen also writes shadergen.zig (the shared types the generated
        // file imports) next to its output. It's identical for every shader, so
        // copy it from the first one.
        if (!copied_types_file) {
            update_src.addCopyFileToSource(
                generated.dirname().path(b, "shadergen.zig"),
                shaders_out_dir ++ "/shadergen.zig",
            );
            copied_types_file = true;
        }
    }
}

/// Directory containing vulkan/vulkan.h: the LunarG SDK when VULKAN_SDK is set,
/// otherwise Homebrew's include dir on macOS or /usr/include elsewhere.
fn vulkanIncludeDir(b: *std.Build) []const u8 {
    if (b.graph.environ_map.get("VULKAN_SDK")) |sdk| return b.pathJoin(&.{ sdk, "include" });
    if (b.graph.host.result.os.tag == .macos) {
        const prefix = b.graph.environ_map.get("HOMEBREW_PREFIX") orelse "/opt/homebrew";
        return b.pathJoin(&.{ prefix, "include" });
    }
    return "/usr/include";
}

/// Adds Vulkan headers and the Vulkan loader to a module. Uses the LunarG SDK
/// pointed to by VULKAN_SDK when set (required on Windows); otherwise falls back
/// to the system paths (e.g. the vulkan-headers/libvulkan-dev packages on Linux).
fn linkVulkan(b: *std.Build, module: *std.Build.Module) void {
    const os_tag = module.resolved_target.?.result.os.tag;

    if (b.graph.environ_map.get("VULKAN_SDK")) |sdk| {
        module.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "Include" }) });
        module.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "include" }) });

        const lib_dir = b.pathJoin(&.{ sdk, if (os_tag == .windows) "Lib" else "lib" });
        module.addLibraryPath(.{ .cwd_relative = lib_dir });
        // The SDK loader isn't installed system-wide on macOS, so let the
        // executable find libvulkan.dylib (which then finds MoltenVK) at runtime.
        if (os_tag == .macos) module.addRPath(.{ .cwd_relative = lib_dir });
    } else if (os_tag == .windows) {
        std.debug.panic("VULKAN_SDK is not set; install the LunarG Vulkan SDK", .{});
    } else if (os_tag == .macos) {
        // Homebrew: brew install vulkan-headers vulkan-loader molten-vk
        const prefix = b.graph.environ_map.get("HOMEBREW_PREFIX") orelse "/opt/homebrew";
        module.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ prefix, "include" }) });
        module.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ prefix, "lib" }) });
        module.addRPath(.{ .cwd_relative = b.pathJoin(&.{ prefix, "lib" }) });
    }

    switch (os_tag) {
        .windows => module.linkSystemLibrary("vulkan-1", .{}),
        else => module.linkSystemLibrary("vulkan", .{}),
    }
}
