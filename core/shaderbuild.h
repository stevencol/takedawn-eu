/*
 * shaderbuild.h - the shader pre-build: the game plays its reference scenes
 * by itself, headless, so the GPU backend compiles and lists the shaders and
 * pipelines they need before the player first meets them (BO-93).
 *
 * Nothing is shipped: the key list and everything compiled from it is made
 * here, on the player's machine, from the player's own disc. It is always a
 * choice: the installer offers it (ticked by default, it can be unticked), the
 * settings overlay has it as an action, the game itself never asks at its first
 * start; without it the game compiles each shader the
 * first time it is drawn, as before.
 *
 *   burnout3 --build-shaders [--cache-dir <dir>] [--scenes a,b] [--force]
 *                            [--status]
 *
 * runs the whole thing and prints its progress on stdout in the installer's
 * line protocol (docs/shader-prebuild.md). That process runs no title: it
 * starts this executable once per scene with --build-shaders-scene <name>.
 */
#ifndef BO3_SHADERBUILD_H
#define BO3_SHADERBUILD_H

#ifdef __cplusplus
extern "C" {
#endif

/* --build-shaders: argv from the first option after it. Returns the
 * process's exit status. Call after the enhancements layer is up (it names
 * the cache directory). */
int  bo3_shaderbuild_main(int argc, char **argv, const char *xbe_path);

/* --build-shaders-scene <name>: this process plays one scene. Before the
 * environment defaults: sets the variables of an unattended run (headless,
 * scratch saves, no sound, no rumble, the scripted pad). 0: no such scene. */
int  bo3_shaderbuild_scene_env(const char *scene);
/* After the runtime's set-up, before the title starts: the driver thread. */
void bo3_shaderbuild_scene_start(const char *xbe_path);

/* The running game's side (the settings overlay's action and the first
 * start's offer): a pre-build in a child process, its progress polled.
 * Call once the enhancements layer is up. */
void bo3_shaderbuild_host_init(int headless);

#ifdef __cplusplus
}
#endif

#endif /* BO3_SHADERBUILD_H */
