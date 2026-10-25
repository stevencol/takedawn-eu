/* bo3_gp: sound/DSP/B3XboxFx.bin as wired for the APU's GP model
 * (core/gp_image.c, BO-119), against the routing measured on the GP
 * stage with the title's race state:
 *
 *   bin  0..5   their own speaker, +1          6..9   FL FR SL SR, +1
 *       19..23  FL FR SL SR C, +1          25, 13..16  FL FR SL SR C, -1
 *       24      LFE, +0.5
 *       10, 11, 12, 17, 18, 26..31  no speaker
 *
 * and the return path: bins 17 and 18 after the distortion in slots 6 and 7
 * of the block at GP scratch 0xB000, which the title's voices 68 and 69
 * play. The state area is filled as the title has it in a race (the b0
 * words of the eleven sends, the distortion's parameters). No game data.
 */
#include "apu_gp.h"
#include "gp_image.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(cond, ...) \
    do { if (!(cond)) { printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

enum { FL, FR, C, LFE, SL, SR };
#define STATE 0x3410u

static uint32_t scr[0x4000];
static uint32_t rd(void *c, uint32_t off) { (void)c; return off / 4 < 0x4000 ? scr[off / 4] : 0; }
static void wr(void *c, uint32_t off, const uint32_t *w, int n)
{
    (void)c;
    if (off / 4 + (uint32_t)n <= 0x4000) memcpy(&scr[off / 4], w, 4u * (size_t)n);
}

int main(void)
{
    static const apu_gp_mem mem = { rd, wr, NULL };
    static const struct { int spk; float gain; } want[32] = {
        { FL, 1 }, { FR, 1 }, { C, 1 }, { LFE, 1 }, { SL, 1 }, { SR, 1 },
        { FL, 1 }, { FR, 1 }, { SL, 1 }, { SR, 1 },
        { -1, 0 }, { -1, 0 }, { -1, 0 },
        { FR, -1 }, { SL, -1 }, { SR, -1 }, { C, -1 },
        { -1, 0 }, { -1, 0 },
        { FL, 1 }, { FR, 1 }, { SL, 1 }, { SR, 1 }, { C, 1 }, { LFE, 0.5f },
        { FL, -1 },
        { -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 }, { -1, 0 },
    };
    /* The sends' b0 words at their scratch offsets, as the title has them
     * from the first frames on, and the distortions' parameters in a race. */
    static const struct { uint32_t off, b0; } eq[] = {
        { 0x3638, 0x800000 }, { 0x36D4, 0x800000 }, { 0x3770, 0x800000 }, { 0x380C, 0x800000 },
        { 0x38A8, 0x800000 }, { 0x3944, 0x7FFFFF }, { 0x39E0, 0x7FFFFF }, { 0x3A7C, 0x7FFFFF },
        { 0x3B18, 0x7FFFFF }, { 0x3BB4, 0x7FFFFF }, { 0x3C50, 0x400000 },
    };
    static const uint32_t drive[9] = { 0x7FFFFF, 0x1FFFFF, 0, 0x7FFFFF, 0x3FFFFF, 0, 0x1FFFFF, 0, 0x7FFFFF };
    static float bins[32][32], out[6][32];
    uint32_t off, bytes;
    int first;

    bo3_gp_wire();
    apu_gp_lfe_lowpass(0);              /* the GP stage alone */
    for (unsigned k = 0; k < sizeof eq / sizeof eq[0]; k++)
        scr[eq[k].off / 4] = eq[k].b0;
    /* The LFE send keeps the image's default set, a flat one half. */
    scr[0x3C54 / 4] = 0xAD7746; scr[0x3C58 / 4] = 0x23434C;
    scr[0x3C5C / 4] = 0x5288B9; scr[0x3C60 / 4] = 0xDCBCB3;
    for (int k = 0; k < 9; k++) {
        scr[(0x34E4 + 4 * k) / 4] = drive[k];
        scr[(0x3540 + 4 * k) / 4] = drive[k];
    }
    /* DirectSound's first command: the whole state area. */
    apu_gp_command(&mem, 3, 0, STATE, 0x9E1);

    for (int b = 0; b < 32; b++) {
        float in[32];
        memset(bins, 0, sizeof bins);
        for (int i = 0; i < 32; i++)
            bins[b][i] = in[i] = 0.05f * (float)sin(0.3 * i + b);
        apu_gp_frame(&mem, bins, out);
        CHECK(apu_gp_bin_speaker(b) == want[b].spk, "bin %d: wired to speaker %d, measured %d",
              b, apu_gp_bin_speaker(b), want[b].spk);
        for (int s = 0; s < 6; s++) {
            double err = 0;
            for (int i = 0; i < 32; i++)
                err = fmax(err, fabs(out[s][i] - (s == want[b].spk ? want[b].gain * in[i] : 0.0f)));
            CHECK(err < 2e-6, "bin %d on speaker %d: off by %g", b, s, err);
        }
    }

    /* The return path. */
    CHECK(apu_gp_export_range(&off, &bytes, &first) && off == 0xB000 && bytes == 0xA00 && first == 11,
          "the export block");
    memset(bins, 0, sizeof bins);
    for (int i = 0; i < 32; i++) {
        bins[17][i] = 0.01f * (float)(i - 16);          /* clips from +-0.125 */
        bins[18][i] = -0.01f * (float)(i - 16);
    }
    apu_gp_frame(&mem, bins, out);
    for (int i = 0; i < 32; i++) {
        double x = 0.08 * (i - 16), w = x > 1 ? 1 : x < -1 ? -1 : x;
        double e17 = (double)((int32_t)(scr[(0xB300 / 4) + i] << 8) >> 8) / 8388608.0;
        double e18 = (double)((int32_t)(scr[(0xB380 / 4) + i] << 8) >> 8) / 8388608.0;
        CHECK(fabs(e17 - w) < 1e-5 && fabs(e18 + w) < 1e-5,
              "sample %d: the slots hold %g and %g, want +-%g", i, e17, e18, w);
    }

    if (failures) {
        printf("bo3_gp: %d checks FAILED\n", failures);
        return 1;
    }
    printf("bo3_gp: the image's routing, gains, polarity and return slots ok\n");
    return 0;
}
