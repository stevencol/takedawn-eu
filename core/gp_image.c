/*
 * gp_image.c -- sound/DSP/B3XboxFx.bin for the APU's GP model (gp_image.h).
 *
 * All of this is read off the image as DirectSound has it in GP scratch
 * memory at run time (the GP program at scratch 0, the effects' code from
 * 0x818, their state blocks from 0x3410, the effect table at 0x5B94), and
 * agrees with the measured behaviour of the GP stage.
 *
 * The state area. DirectSound's first command loads 0x9E1 words from
 * scratch 0x3410; later commands reload parts of it when the title moves a
 * parameter. Blocks, by word index (scratch offset = 0x3410 + 4 * index);
 * every block has its flags at +4 and its input / output addresses from +5
 * (a mixbin is X:0x1400 + 0x20 * bin, a speaker X:0xC00 + 0x20 * speaker,
 * speakers in the order FL FR C LFE SL SR):
 *
 *     0x000  mixer (36 words of code)                       not modelled
 *     0x02E  distortion, in place on bin 17 (player engine)
 *     0x045  distortion, in place on bin 18 (player exhaust)
 *     0x05C  a 124-word effect on bin 26 -> centre          never fed
 *     0x083  IIR2  25 -> FL      0x0AA  IIR2  13 -> FR
 *     0x0D1  IIR2  14 -> SL      0x0F8  IIR2  15 -> SR
 *     0x11F  IIR2  16 -> C       0x146  IIR2  19 -> FL
 *     0x16D  IIR2  20 -> FR      0x194  IIR2  21 -> SL
 *     0x1BB  IIR2  22 -> SR      0x1E2  IIR2  23 -> C
 *     0x209  IIR2  24 -> LFE
 *     0x230  mixer                                          not modelled
 *     0x25E  I3DL2 reverb, bin 11 -> FL FR SL SR (wet only)
 *     ...    crosstalk (bins 6..9), four more 124-word effects (27..30)
 *
 * RenderWare's driver sends a positioned sound to six of those IIR2
 * inputs, one a speaker, and picks 19..23 or 25/13..16 for each: the
 * title keeps the first set's b0 at +1 and the second's at -1, so the
 * second set is the same speaker with the polarity turned. 24 stays at the
 * image's default, a flat one half.
 *
 * The player's engine and exhaust (2D sounds) go to bins 17 and 18 and to
 * no speaker from there. The distortion runs on each in place, and the GP
 * program (scratch words 0x12..0x19: "0x280 words from X:0x1560 to
 * scratch 0xB000") copies bins 11..30 out every frame. The title's two
 * looping voices 68 and 69 have their 32-sample buffers on the bin 17 and
 * bin 18 slots of that copy (scratch 0xB300 and 0xB380) and send them,
 * with volumes the title moves, to FL FR C LFE SL SR and the reverb: that
 * is how the engine reaches the speakers.
 *
 * The reverb runs as the image's own code (apu_gp_program). Not modelled:
 * the crosstalk pair filters of bins 6..9 and the effects on 26..30 (never
 * fed by the title).
 */
#include "gp_image.h"
#include "apu_gp.h"

enum { FL, FR, C, LFE, SL, SR };

void bo3_gp_wire(void)
{
    static const struct { int bin, spk; unsigned st; } eq[] = {
        { 25, FL, 0x083 }, { 13, FR, 0x0AA }, { 14, SL, 0x0D1 }, { 15, SR, 0x0F8 },
        { 16, C, 0x11F },  { 19, FL, 0x146 }, { 20, FR, 0x16D }, { 21, SL, 0x194 },
        { 22, SR, 0x1BB }, { 23, C, 0x1E2 },  { 24, LFE, 0x209 },
    };

    apu_gp_reset();
    /* The speaker bins themselves. */
    for (int b = 0; b < 6; b++)
        apu_gp_direct(b, b, 1.0f);
    /* The crosstalk bins reach their own corner at unity (plus a low
     * shelf and a cross feed that are not modelled); the title never
     * feeds them. */
    apu_gp_direct(6, FL, 1.0f);
    apu_gp_direct(7, FR, 1.0f);
    apu_gp_direct(8, SL, 1.0f);
    apu_gp_direct(9, SR, 1.0f);
    for (unsigned k = 0; k < sizeof eq / sizeof eq[0]; k++)
        apu_gp_eq(eq[k].bin, eq[k].spk, eq[k].st);
    apu_gp_drive(17, 0x02E);
    apu_gp_drive(18, 0x045);
    apu_gp_export(11, 20, 0xB000);
    /* The I3DL2 reverb (mixbin 11 to FL FR SL SR, wet only) runs as the
     * image's own code: 1211 words at scratch 0x1790, its delay lines in
     * GP scratch from 0xCA00 (0x5CC60 bytes), its state at word 0x25E. */
    apu_gp_program(0x1790, 0x4BB);
    /* After the GP the console's AC-3 encoder band-limited the LFE. */
    apu_gp_lfe_lowpass(120);
}
