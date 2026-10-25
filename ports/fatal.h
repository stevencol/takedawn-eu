/*
 * fatal.h - a start-up failure the player can see.
 *
 * A release build has no terminal, so a game that cannot start used to print
 * to stderr and end: the player saw the window close (or nothing at all).
 * bo3_fatal says it in a message box as well, where one can be shown.
 */
#ifndef BO3_FATAL_H
#define BO3_FATAL_H

/* Whether a message box may be shown now: not in a headless or unattended
 * run (RECOMP_HEADLESS, TAKEDAWN_NO_SETUP: a box would wait for a click that
 * nobody gives) and, on Linux, not without a display. */
int bo3_fatal_box_wanted(void);

/* The box alone (SDL_ShowSimpleMessageBox; the Win32 one on Windows). */
void bo3_fatal_box(const char *title, const char *fmt, ...);

/* The text to stderr ("title: text") and, where wanted, the box. */
void bo3_fatal(const char *title, const char *fmt, ...);

#endif
