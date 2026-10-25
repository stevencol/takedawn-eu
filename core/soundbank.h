/*
 * soundbank.h - a sound bank that did not load (BO-218, soundbank.c).
 */
#ifndef BO3_SOUNDBANK_H
#define BO3_SOUNDBANK_H

typedef void (*bo3_soundbank_fn)(void);

/* sub_001F65A0 (wrapped in recomp/recomp_manual.c), the wave count of a
 * RenderWare Audio wave dictionary: 0 for one that is no list. */
void bo3_wave_dict_count(bo3_soundbank_fn title_fn);

#endif
