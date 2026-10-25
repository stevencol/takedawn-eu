/*
 * replay.c -- a RECOMP_ORACLE_CAP capture (the toolkit's apu_oracle_cap.c)
 * through the GP model as the title wires it (core/gp_image.c).
 *
 *   bo3_gp_replay <cap.bin> <out6.f32> [export.f32] [nolfe] [lfe=<hz>] [engine] [norev]
 *
 * The capture holds what reached the DSP stage of the build that made it:
 * the mixbins of every frame (BINS), the GP scratch memory and the title's
 * writes to it (SCRF, SCRD), its commands (DBEL), and the two return
 * voices' gains into their bins (VRET; in that build they played silence).
 * Here the voices play the model's export, as the VP does: mixed into the
 * bins of the next frame. out6: the six speaker feeds, float, interleaved
 * FL FR C LFE SL SR, clamped as the GP saturates them. export: bins 11, 17
 * and 18 of the export block, every frame. nolfe: without the encoder's
 * LFE low-pass (the GP stage alone); lfe=<hz>: with it at another corner.
 * engine: only bins 17 and 18 fed. norev: without the reverb program.
 */
#include "apu_gp.h"
#include "gp_image.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define PAGE 4096u
static uint8_t *s_scr;
static uint32_t s_pages;

static uint32_t rd(void *c, uint32_t off)
{
    uint32_t v = 0;
    (void)c;
    if (off + 4 <= s_pages * PAGE) memcpy(&v, s_scr + off, 4);
    return v;
}

static void wr(void *c, uint32_t off, const uint32_t *w, int n)
{
    (void)c;
    if (off + 4u * (uint32_t)n <= s_pages * PAGE) memcpy(s_scr + off, w, 4u * (size_t)n);
}

int main(int argc, char **argv)
{
    apu_gp_mem m = { rd, wr, NULL };
    static float bins[32][32], out[6][32], ret[32][32];
    FILE *f, *fo, *fe = NULL;
    uint32_t h[3], frames = 0;
    uint8_t *buf = NULL;
    size_t cap = 0;
    int nolfe = 0, engine = 0, have_ret = 0, lfe = -1, norev = 0, taken = 0;
    double cpu = 0;

    if (argc < 3) {
        fprintf(stderr, "usage: bo3_gp_replay <cap.bin> <out6.f32> [export.f32] [nolfe] [lfe=<hz>] [engine] [norev]\n");
        return 2;
    }
    for (int i = 3; i < argc; i++) {
        if (!strcmp(argv[i], "nolfe")) nolfe = 1;
        else if (!strncmp(argv[i], "lfe=", 4)) lfe = atoi(argv[i] + 4);
        else if (!strcmp(argv[i], "engine")) engine = 1;
        else if (!strcmp(argv[i], "norev")) norev = 1;
        else if (!fe) fe = fopen(argv[i], "wb");
    }
    f = fopen(argv[1], "rb");
    fo = fopen(argv[2], "wb");
    if (!f || !fo) { perror("open"); return 1; }
    bo3_gp_wire();
    if (norev) apu_gp_program(0, 0);
    if (nolfe) apu_gp_lfe_lowpass(0);
    else if (lfe >= 0) apu_gp_lfe_lowpass(lfe);

    while (fread(h, 4, 3, f) == 3) {
        if (h[2] > cap) { cap = h[2] + 4096; buf = (uint8_t *)realloc(buf, cap); }
        if (fread(buf, 1, h[2], f) != h[2]) break;
        if (!memcmp(&h[0], "SCRF", 4)) {
            uint32_t np;
            memcpy(&np, buf + 4, 4);
            s_scr = (uint8_t *)realloc(s_scr, (size_t)np * PAGE);
            memcpy(s_scr, buf + 8 + 4 * np, (size_t)np * PAGE);
            s_pages = np;
        } else if (!memcmp(&h[0], "SCRD", 4)) {
            for (uint32_t k = 0; k + 8 <= h[2]; k += 8) {
                uint32_t off;
                memcpy(&off, buf + k, 4);
                if (off + 4 <= s_pages * PAGE) memcpy(s_scr + off, buf + k + 4, 4);
            }
        } else if (!memcmp(&h[0], "DBEL", 4)) {
            /* The acknowledgement: the command, unless the frame before
             * this record already took it (below). */
            uint32_t cmd;
            memcpy(&cmd, buf, 4);
            if (!taken)
                apu_gp_command(&m, cmd, rd(NULL, 0x800), rd(NULL, 0x808), rd(NULL, 0x80C));
            taken = 0;
        } else if (!memcmp(&h[0], "VRET", 4)) {
            /* The voice as the VP mixes it: its 32 samples from its
             * buffer, here the export slot, into each of its bins. */
            uint32_t w[13], off;
            float g[8];
            memcpy(w, buf, sizeof w);
            memcpy(g, buf + sizeof w, sizeof g);
            if (!apu_gp_export_range(&off, NULL, NULL) || s_pages <= (off >> 12))
                continue;
            /* The export's page is where the capture's scratch table has
             * it: the buffer's offset in that page is its slot. */
            {
                uint32_t page_pa, slot;
                page_pa = w[2] & ~0xFFFu;
                slot = (off & ~0xFFFu) + (w[2] - page_pa);
                for (int b = 0; b < 8; b++) {
                    int bin = (int)(w[5 + b] & 0xFF);
                    if (g[b] == 0.0f) continue;
                    for (int i = 0; i < 32; i++) {
                        int32_t s = (int32_t)(rd(NULL, slot + 4u * (uint32_t)i) << 8) >> 8;
                        ret[bin][i] += g[b] * ((float)s / 8388608.0f);
                    }
                    have_ret = 1;
                }
            }
        } else if (!memcmp(&h[0], "BINS", 4)) {
            uint32_t mask, n = 0;
            clock_t t0;
            memcpy(&mask, buf, 4);
            memset(bins, 0, sizeof bins);
            for (int b = 0; b < 32; b++)
                if (mask & (1u << b)) {
                    if (!engine || b == 17 || b == 18)
                        memcpy(bins[b], buf + 4 + n * sizeof bins[0], sizeof bins[0]);
                    n++;
                }
            if (have_ret) {
                for (int b = 0; b < 32; b++)
                    for (int i = 0; i < 32; i++)
                        bins[b][i] += ret[b][i];
                memset(ret, 0, sizeof ret);
                have_ret = 0;
            }
            /* A command the title had posted before this frame: the GP
             * program takes it as the frame starts (the runtime does the
             * same; the doorbell is at scratch 0x810). */
            if (s_scr && !taken && rd(NULL, 0x810)) {
                apu_gp_command(&m, rd(NULL, 0x810), rd(NULL, 0x800), rd(NULL, 0x808), rd(NULL, 0x80C));
                taken = 1;
            }
            t0 = clock();
            if (s_scr)
                apu_gp_frame(&m, bins, out);
            else
                memset(out, 0, sizeof out);
            cpu += (double)(clock() - t0);
            for (int i = 0; i < 32; i++) {
                float s[6];
                for (int c = 0; c < 6; c++) {
                    float x = out[c][i];
                    s[c] = x > 1.0f ? 1.0f : x < -1.0f ? -1.0f : x;
                }
                fwrite(s, sizeof(float), 6, fo);
            }
            if (fe) {
                for (int i = 0; i < 32; i++) {
                    float s[3] = { bins[11][i], bins[17][i], bins[18][i] };
                    fwrite(s, sizeof(float), 3, fe);
                }
            }
            frames++;
        }
    }
    fclose(fo);
    if (fe) fclose(fe);
    fprintf(stderr, "%u frames, GP model %.2f us a frame\n", frames,
            frames ? cpu / CLOCKS_PER_SEC * 1e6 / frames : 0.0);
    return 0;
}
