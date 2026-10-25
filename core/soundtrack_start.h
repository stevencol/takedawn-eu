/*
 * soundtrack_start.h - the decisions of "custom music at start" (BO-230),
 * apart from the guest and the settings so a unit test can run them
 * (tests/start). soundtrack.c feeds them the title's chosen source
 * (manager+0x568: 0 EA GAMES TRAX, n the soundtrack n-1) at each start of
 * the title's music, and does what they say.
 */
#ifndef BO3_SOUNDTRACK_START_H
#define BO3_SOUNDTRACK_START_H

#include <stdint.h>

/* The soundtrack to start on, as an index, or -1 for EA GAMES TRAX (nothing
 * to switch). n: the soundtracks the folder has; key_set: the player has
 * chosen something before (audio.custom_music_soundtrack is in the file);
 * name: that choice ("" is EA GAMES TRAX); found: the index of the soundtrack
 * of that name, or -1. Nothing chosen yet, or a name the folder no longer
 * has: the first. */
static inline int bo3_start_target(int n, int key_set, const char *name, int found)
{
    if (n < 1)
        return -1;
    if (!key_set)
        return 0;
    if (!name || !name[0])
        return -1;
    return found >= 0 && found < n ? found : 0;
}

/* BO-243: a folder held back while a soundtrack of the old one was the
 * title's music is put in place: that soundtrack becomes the new folder's
 * one of the same name (found, or -1), else its first; -1 (EA GAMES TRAX)
 * when the new folder has none. The same rule as the start switch's for a
 * name the folder lacks, so the music after the switch and the music at the
 * next start agree. */
static inline int bo3_held_target(int n, int found)
{
    return bo3_start_target(n, 1, "-", found);
}

typedef struct bo3_start_state {
    int     pending;                  /* the start switch is still to be done */
    int32_t seen;                     /* the chosen source as the last start saw it */
} bo3_start_state;

typedef enum {
    BO3_START_NOTHING,                /* leave the title as it is */
    BO3_START_SWITCH,                 /* set the chosen source to *source */
    BO3_START_EA,                     /* the start switch was due: EA GAMES TRAX was the last choice */
    BO3_START_REMEMBER                /* the player chose *source in the title's screen */
} bo3_start_action;

/* One start of the title's music, with `cur` the chosen source it holds.
 * `target` is asked only when the switch is due (it reads the settings).
 * The switch is due once, while the title is still on its boot source (0)
 * and nothing was seen to change; a change seen first is the player's own
 * choice and ends the wait. */
static inline bo3_start_action bo3_start_step(bo3_start_state *st, int32_t cur, int (*target)(void),
                                              int32_t *source)
{
    if (st->pending && cur == 0 && st->seen == 0) {
        int t = target ? target() : -1;
        st->pending = 0;
        if (t < 0)
            return BO3_START_EA;
        st->seen = *source = t + 1;
        return BO3_START_SWITCH;
    }
    if (cur != st->seen) {
        st->seen = *source = cur;
        st->pending = 0;
        return BO3_START_REMEMBER;
    }
    return BO3_START_NOTHING;
}

#endif /* BO3_SOUNDTRACK_START_H */
