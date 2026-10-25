/*
 * pcmanifest.c - hands the shipped shader coverage manifests (graphics/, compiled
 * in by CMakeLists.txt) and the player's executable to the GPU backend's pipeline
 * cache (the toolkit's nv2a_pcache.h, BO-208).
 */
#include <stddef.h>

#include "d3d/nv2a_pcache.h"

extern const unsigned char bo3_pcm_vulkan[], bo3_pcm_metal[];
extern const size_t bo3_pcm_vulkan_size, bo3_pcm_metal_size;

void bo3_pcache_manifest_register(const char *xbe_path)
{
    if (bo3_pcm_vulkan_size)
        nv2a_pcache_set_manifest("vulkan", bo3_pcm_vulkan, bo3_pcm_vulkan_size);
    if (bo3_pcm_metal_size)
        nv2a_pcache_set_manifest("metal", bo3_pcm_metal, bo3_pcm_metal_size);
    nv2a_pcache_set_xbe(xbe_path);
}

/* A manifest is compiled in: the pre-build then needs no scene. */
int bo3_pcache_manifest_present(void)
{
    return bo3_pcm_vulkan_size > 64 || bo3_pcm_metal_size > 64;
}
