/* Custom music at start: the decisions (core/soundtrack_start.h, BO-230). */
#include <stdio.h>
#include <string.h>

#include "soundtrack_start.h"

static int fails, checks;
#define CHECK(c) do { checks++; if (!(c)) { fails++; printf("FAIL line %d: %s\n", __LINE__, #c); } } while (0)

static int s_target;
static int s_asked;
static int target(void) { s_asked++; return s_target; }

int main(void)
{
    bo3_start_state st;
    int32_t src = -9;

    /* Which soundtrack. */
    CHECK(bo3_start_target(0, 0, "", -1) == -1);                 /* no soundtracks: nothing */
    CHECK(bo3_start_target(0, 1, "A", 0) == -1);
    CHECK(bo3_start_target(3, 0, "", -1) == 0);                  /* nothing chosen yet: the first */
    CHECK(bo3_start_target(3, 0, NULL, -1) == 0);
    CHECK(bo3_start_target(3, 1, "", -1) == -1);                 /* EA GAMES TRAX chosen: no switch */
    CHECK(bo3_start_target(3, 1, NULL, -1) == -1);
    CHECK(bo3_start_target(3, 1, "Beta", 1) == 1);               /* found by name */
    CHECK(bo3_start_target(3, 1, "Gone", -1) == 0);              /* the name is gone: the first */
    CHECK(bo3_start_target(3, 1, "Odd", 7) == 0);                /* an index past the list: the first */
    /* BO-243: a held-back folder put in place; and the next start with the
     * name the player had remembered gives the same soundtrack. */
    CHECK(bo3_held_target(3, 2) == 2);                           /* the same name */
    CHECK(bo3_held_target(3, -1) == 0);                          /* not in it: the first */
    CHECK(bo3_held_target(0, -1) == -1);                         /* no music in it: EA GAMES TRAX */
    CHECK(bo3_held_target(2, -1) == bo3_start_target(2, 1, "Techno Pick", -1));
    CHECK(bo3_held_target(3, 2) == bo3_start_target(3, 1, "Techno Pick", 2));

    /* The first start: the switch is due once. */
    memset(&st, 0, sizeof st); st.pending = 1; s_target = 1; s_asked = 0;
    CHECK(bo3_start_step(&st, 0, target, &src) == BO3_START_SWITCH && src == 2 && s_asked == 1);
    CHECK(st.pending == 0 && st.seen == 2);
    /* The title now holds 2: the next starts change nothing, and ask nothing. */
    CHECK(bo3_start_step(&st, 2, target, &src) == BO3_START_NOTHING && s_asked == 1);
    CHECK(bo3_start_step(&st, 2, target, &src) == BO3_START_NOTHING);
    /* The player confirms EA GAMES TRAX, then soundtrack 3. */
    CHECK(bo3_start_step(&st, 0, target, &src) == BO3_START_REMEMBER && src == 0 && st.seen == 0);
    CHECK(bo3_start_step(&st, 0, target, &src) == BO3_START_NOTHING);   /* not switched again */
    CHECK(bo3_start_step(&st, 3, target, &src) == BO3_START_REMEMBER && src == 3);
    CHECK(s_asked == 1);

    /* EA GAMES TRAX was the last choice: no switch, and it is not asked twice. */
    memset(&st, 0, sizeof st); st.pending = 1; s_target = -1; s_asked = 0;
    CHECK(bo3_start_step(&st, 0, target, &src) == BO3_START_EA && st.pending == 0 && st.seen == 0);
    CHECK(bo3_start_step(&st, 0, target, &src) == BO3_START_NOTHING && s_asked == 1);
    CHECK(bo3_start_step(&st, 2, target, &src) == BO3_START_REMEMBER && src == 2);

    /* Off, or no folder: never pending, nothing but the player's own choice. */
    memset(&st, 0, sizeof st); s_asked = 0;
    CHECK(bo3_start_step(&st, 0, target, &src) == BO3_START_NOTHING && s_asked == 0);
    CHECK(bo3_start_step(&st, 0, target, &src) == BO3_START_NOTHING);

    /* The player chooses before the switch is due (a slow scan): theirs wins. */
    memset(&st, 0, sizeof st); st.pending = 1; s_target = 0; s_asked = 0;
    CHECK(bo3_start_step(&st, 2, target, &src) == BO3_START_REMEMBER && src == 2 && st.pending == 0);
    CHECK(bo3_start_step(&st, 0, target, &src) == BO3_START_REMEMBER && src == 0);
    CHECK(s_asked == 0);

    printf("start: %d checks, %d failed\n", checks, fails);
    return fails != 0;
}
