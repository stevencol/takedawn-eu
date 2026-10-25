/*
 * hirefresh.h - pictures between the simulation's steps (hirefresh.c).
 */
#ifndef BO3_HIREFRESH_H
#define BO3_HIREFRESH_H

typedef void (*bo3_hirefresh_fn)(void);

/* The wraps of recomp/recomp_manual.c; each runs the title's body as
 * shipped unless graphics.high_refresh is in force (hirefresh.c). */

/* sub_000165F0, CB3Game::Update: the blends of the last picture put back,
 * then the steps up to the frame's flip time (0 allowed). */
void bo3_update(bo3_hirefresh_fn title_fn);

/* sub_001E15E0, RenderWare's _rwFrameSyncDirty: the LTMs of what moved
 * taken, and blended in place between the last two steps. */
void bo3_frame_sync_dirty(bo3_hirefresh_fn title_fn);

/* sub_001DD280, RwFrameGetLTM: the frames the pipelines draw taken, and
 * blended, while a picture is drawn. */
void bo3_frame_get_ltm(bo3_hirefresh_fn title_fn);

/* sub_000303D0, the vehicles' draw: each vehicle's matrix blended for the
 * call. */
void bo3_draw_vehicle(bo3_hirefresh_fn title_fn);

/* sub_000535E0, the HUD's update: its time follows the picture's time. */
void bo3_hud_update(bo3_hirefresh_fn title_fn);

/* sub_00167940, a player's cameras once a frame: once a step instead. */
void bo3_player_frame(bo3_hirefresh_fn title_fn);

/* sub_00038200, the sparks' history pushed once a picture, and
 * sub_000367C0, a spark system's streaks drawn from it: both at the
 * picture's time on the race clock. */
void bo3_spark_history(bo3_hirefresh_fn title_fn);

/* sub_0013EF40, the race audio manager: once a step. */
void bo3_race_audio(bo3_hirefresh_fn title_fn);

/* sub_00188750, the effects clock (the race-end flash): gains the steps'
 * time only; the flash drawn at the picture's time. */
void bo3_fx_clock(bo3_hirefresh_fn title_fn);
void bo3_spark_draw(bo3_hirefresh_fn title_fn);

/* sub_00350DB0, D3D's swap: counted, so the frame being built knows which
 * edge of the toolkit's flip grid it will flip at. */
void bo3_swap(bo3_hirefresh_fn title_fn);

#endif
