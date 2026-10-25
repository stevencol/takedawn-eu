/*
 * soundbank.c - a sound bank that did not load (BO-218, GitHub #17).
 *
 * sub_001F65A0(dict) counts the waves of a RenderWare Audio wave dictionary:
 * the length of the circular list at dict + 0xC (sub_001FE1C0: next at +4,
 * the walk ends back at the head). The title's bank cache (sub_001C9C80 ->
 * sub_001C9660; at race start it loads sound\identN.awd, the EA GAMES TRAX
 * pop-up's sounds) takes every load status other than "still reading" as
 * done, an error too (sub_001F70C0's 0x2000, 0x300, 0x500: the switch at
 * 0x1C9714), keeps what the request left as the dictionary (NULL, or the
 * header buffer when the header read failed) and counts its waves at once
 * (sub_001C9840). A list that is no list has a NULL link, and the walk
 * follows 0 -> 0 for ever: the main thread spins in sub_001FE1C0, nothing
 * flips, the hang report names sub_001F65A0 <- sub_001C9840 <- sub_001C9660
 * <- sub_001C9C80 <- sub_001543B0. The console would fault on the NULL page
 * instead. The cache's unload path (sub_001C98A0) already skips a NULL
 * dictionary, so a count of 0 is a state the title's code knows.
 *
 * So the list is checked before the title's walk: a NULL dictionary or a
 * NULL link counts as no waves (the bank's sounds stay silent, the race goes
 * on), said in the log. A sound list goes through the title's own code
 * unchanged.
 */
#include "soundbank.h"

#include <stdio.h>

#include "recomp_types.h"

#define WALK_MAX 0x10000u   /* far more waves than any bank has */

void bo3_wave_dict_count(bo3_soundbank_fn title_fn)
{
    uint32_t dict = MEM32(g_esp + 4), head, node, n;
    static int said;

    if (dict) {
        head = dict + 0xC;
        node = MEM32(head + 4);
        for (n = 0; node && node != head && n < WALK_MAX; n++)
            node = MEM32(node + 4);
        if (node == head) {
            title_fn();
            return;
        }
    }
    if (said < 4) {
        said++;
        fprintf(stderr, "[SOUND] a sound bank did not load (wave dictionary 0x%08X is no list):"
                        " its sounds stay silent\n", (unsigned)dict);
    }
    /* cdecl, as the title's body: the argument slot left at dict + 0xC,
     * the count in eax, ret. */
    MEM32(g_esp + 4) = dict + 0xC;
    g_eax = 0;
    g_esp += 4;
}
