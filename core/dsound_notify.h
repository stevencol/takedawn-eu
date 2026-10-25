/*
 * dsound_notify.h - DirectSound's voice-done list kept sound (BO-173,
 * dsound_notify.c).
 */
#ifndef BO3_DSOUND_NOTIFY_H
#define BO3_DSOUND_NOTIFY_H

typedef void (*bo3_dsound_fn)(void);

/* sub_002FAAEF (wrapped in recomp/recomp_manual.c), DirectSound's "voice
 * done": a voice whose done notification is still queued is not queued
 * again. */
void bo3_dsound_voice_done(bo3_dsound_fn title_fn);

/* BO3_DSOUND_GUARD, the exit line and the hang report's line; before the
 * title starts. */
void bo3_dsound_notify_init(void);

#endif
