/*
 * tutorial.c - A or START leaves a training film (Takedown, Crash and the
 * rest: TrD_xxx.xmv for Race / Road Rage, TrC_xxx.xmv for Crash, one per
 * language), which the title shows before a mode's first event (once that
 * event has been played, the film does not come again). It shows them from
 * a front-end page (sub_000871D0, object 0x55CB88) that leaves on A or START
 * only when its "skippable" byte (+0xC) is set, and the state that plays
 * these films (sub_0006BC40) enters the page with it clear: the call of
 * sub_00086F70 at 0x6BFA3 pushes 0, where the title's other film pages push 1.
 *
 * One mark, "tut_film" (0x6BF9B, after that `push 0`): the byte becomes 1.
 * The page then asks for the press as it does for any film: sub_00017790
 * (A newly down on a pad) and sub_000179D0 (START); a button held from the
 * menu does not count. The leave is the page's own, the state a finished
 * film reaches. The films play as in the original until then.
 */
#include <stdint.h>
#include <stddef.h>

#include "recomp_types.h"
#include "controls.h"
#include "platform/recomp_patch.h"

#ifndef RECOMP_CPU_STRUCT
extern RECOMP_TLS uint32_t g_esp;
#endif
extern ptrdiff_t g_xbox_mem_offset;

#define TU_M32(va) (*(uint32_t *)((uintptr_t)g_xbox_mem_offset + (uint32_t)(va)))

static void tu_film(void)
{
    if (g_xbox_mem_offset && TU_M32(g_esp) == 0)
        TU_M32(g_esp) = 1;
}

void bo3_tutorial_start(void)
{
    recomp_patch_on_mark("tut_film", tu_film);
}
