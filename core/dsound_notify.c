/*
 * dsound_notify.c - DirectSound's voice-done list kept sound (BO-173).
 *
 * The title's DirectSound (XDK library, DSOUND section) finishes a voice in
 * two halves. The APU interrupt (sub_002F8DE5 -> sub_002F8CC8 -> the
 * voice-done handler sub_002F8644) takes the voice off the hardware list
 * and puts its entry at voice+0x54 on the end of the core's done list
 * (core+0x4A0) with sub_002FAAEF(1), then queues the core's DPC. The DPC
 * (sub_002F8CA1 -> sub_002F8C05 -> sub_002F8531) empties that list:
 *
 *     while ((e = unlink(head->Flink)) != head)      sub_002F3F40
 *         CONTAINING_VOICE(e)->vtbl[6]();            0x2FC1B1 here
 *
 * The insert has no "already on the list" check. On the console it needs
 * none: the DPC runs as soon as the interrupt returns, before the thread it
 * interrupted takes another step, so no thread can play the voice again
 * while its entry still waits. Here the DPC waited for the timer thread's
 * next pass (up to 10 ms, longer while a thread held the one-CPU gate),
 * and in that window the title can restart the voice and the APU can finish
 * it again. The second insert of an entry that is already the list's last
 * leaves it pointing at itself while the head still points at it; unlink
 * then never takes it off, and the DPC calls 0x2FC1B1 on it forever at
 * DISPATCH_LEVEL, with no kernel call in the loop. Every thread that raises
 * waits on the gate behind it: the Deck's freeze after ~13 minutes (the hang
 * report's kernel-timer thread in sub_002F8531, guest-main in
 * pthread_mutex_lock under KeRaiseIrqlToDpcLevel).
 *
 * So the second "voice done" for a voice whose first one is still on the
 * list does not insert it again (sub_002FAAEF(0): the hardware side is done
 * as before, the notification already queued stands for both). That is
 * what the console's order would have produced: one DPC call for the voice.
 *
 * The toolkit now wakes the timer thread for a queued DPC where the console
 * would run it (kernel_hal.c, BO-173), which shrinks that window from
 * milliseconds to microseconds; it does not close it (a thread can still
 * take the gate first). So this stays, counted (exit line, hang report),
 * never logged from the interrupt.
 *
 * The free path (sub_002FACCB -> sub_002FAAEF(0)) does not unlink a queued
 * done entry either, and is left as the title has it: with the DPC run
 * before PASSIVE code goes on, the list is empty whenever the title frees a
 * voice outside DirectSound's DISPATCH-level lock, and inside it the console
 * behaves the same as here.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "dsound_notify.h"
#include "kernel.h"                     /* InterlockedIncrement */
#include "xbox_crash.h"
#include "recomp_types.h"

#define VOICE_CORE        0x08u   /* the CMcpxCore the voice belongs to */
#define VOICE_DONE_ENTRY  0x54u   /* LIST_ENTRY on the core's done list */
#define CORE_DONE_LIST    0x4A0u  /* LIST_ENTRY head */
#define WALK_MAX          4096u   /* far more voices than the APU has (256) */

/* Whether the voice's done entry is on its core's done list now. The
 * interrupt's caller holds the one-CPU gate, so nothing edits the list
 * meanwhile. */
static int done_entry_queued(uint32_t voice)
{
    uint32_t core, head, entry, node, n;

    if (!voice)
        return 0;
    core = MEM32(voice + VOICE_CORE);
    if (!core)
        return 0;
    entry = voice + VOICE_DONE_ENTRY;
    node = MEM32(entry);
    if (node == 0 || node == entry)
        return 0;               /* never queued, or taken off (self-linked) */
    head = core + CORE_DONE_LIST;
    for (node = MEM32(head), n = 0; node && node != head && n < WALK_MAX;
         node = MEM32(node), n++)
        if (node == entry)
            return 1;
    return 0;
}

/* Counted, never printed here: this runs inside the APU interrupt, at
 * device IRQL with the one-CPU gate held, where a write to the log can
 * block on the pipe. Read at exit and in a hang report. */
static volatile LONG s_coalesced, s_twice;
static int s_off = -1;

static void dsound_notify_report(void)
{
    if (s_coalesced || s_twice)
        fprintf(stderr, "[DSOUND] voice done again while its done entry"
                " still waited for the DPC: %ld kept single, %ld queued twice"
                " (BO3_DSOUND_GUARD=0) (BO-173)\n",
                (long)s_coalesced, (long)s_twice);
}

static void dsound_notify_note(void)
{
    xbox_crash_printf("  DirectSound done list (BO-173): %ld second inserts"
                      " kept single, %ld queued twice (guard %s)\n",
                      (long)s_coalesced, (long)s_twice,
                      s_off > 0 ? "off" : "on");
}

void bo3_dsound_notify_init(void)
{
    const char *e = getenv("BO3_DSOUND_GUARD");

    s_off = e && e[0] == '0';           /* a test: the title's own insert */
    xbox_crash_add_note(dsound_notify_note);
    atexit(dsound_notify_report);
}

void bo3_dsound_voice_done(bo3_dsound_fn title_fn)
{
    uint32_t voice = g_ecx;

    /* thiscall: ecx the voice, [esp+4] "queue the notification". */
    if (MEM32(g_esp + 4) && done_entry_queued(voice)) {
        if (s_off > 0) {
            InterlockedIncrement(&s_twice);
        } else {
            InterlockedIncrement(&s_coalesced);
            MEM32(g_esp + 4) = 0;
        }
    }
    title_fn();
}
