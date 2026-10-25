/*
 * mixer.h -- Burnout 3's side of the host mixer (BO-114, docs/mixer.md):
 * the buses, which of the disc's waves goes to which, the stream tags and
 * the presets. The mixing is the toolkit's (src/apu/apu_bus.h).
 */
#ifndef BO3_MIXER_H
#define BO3_MIXER_H

#include "apu_bus.h"

/* After the settings are read and xbox_path_init: the buses, the
 * classifier, the presets and the preset file (mixer.toml beside
 * settings.toml, or RECOMP_AUDIO_MIXER_FILE). With the mixer off this
 * registers names and nothing else. */
void bo3_mixer_init(const char *game_dir, const char *settings_path, const char *save_dir);

/* The pieces, for the unit test (tests/mixer). */
int  bo3_mixer_wave_bus(const char *file, const char *name);
int  bo3_mixer_read_dictionary(const char *path, const char *rel);
void bo3_mixer_load_table(const char *game_dir);
int  bo3_mixer_classify(const apu_bus_voice *v);
int  bo3_mixer_is_custom(const apu_bus_voice *v);   /* a custom-soundtrack stream (the leveller) */
int  bo3_mixer_preset_count(void);
const char *bo3_mixer_preset_name(int i);
const char *bo3_mixer_preset_about(int i);
const char *bo3_mixer_preset_toml(int i);

#endif /* BO3_MIXER_H */
