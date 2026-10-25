/*
 * hraudit.h - High refresh audit (BO-275), a debug aid: what a picture
 * between two steps changes in guest RAM, and who writes it (hraudit.c).
 * Off unless BO3_HRAUDIT_CTL is set; nothing changes when it is not.
 */
#ifndef BO3_HRAUDIT_H
#define BO3_HRAUDIT_H

/* bo3_update, after the last picture's blends are put back, before
 * anything else: ends a sample that the last picture began. */
void bo3_hraudit_begin(void);

/* bo3_update, High refresh active, right before the title's Update with
 * this many steps: may begin a sample (0 steps only). */
void bo3_hraudit_picture(int steps);

/* 1 while an audit cycle asked for the pictures to be drawn at the last
 * step (no blend), so a picture between steps draws what the one before
 * drew and only what it advances shows in the diff. */
int bo3_hraudit_noblend(void);

/* bo3_hud_update: the time the HUD's update was given, and after the
 * High refresh scaling (counted while a cycle runs). */
void bo3_hraudit_hud(float given, float scaled);

/* A counted call of a once-a-step wrap: kind 1 the race audio manager,
 * with the times the title's body ran for it. */
void bo3_hraudit_count(int kind, unsigned runs);

#endif
