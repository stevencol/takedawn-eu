/*
 * glyphs.c - the game's button prompts drawn for the pad in use (BO-107).
 * See glyphs.h.
 */
#include "glyphs.h"

#ifdef BO3_HAVE_GLYPH_ART

#include "bo3_glyph_art.h"          /* made at build time by tools/glyphs/build.py */
#include "input/pad_glyphs.h"
#include "nv2a_texrep.h"

#include <stdio.h>

#define R(x, y, w, h) { (x), (y), (w), (h) }

/* "Buttons", 128x64 DXT5. The discs' own pixels are 28 wide from (1, 1); the
 * rectangles are the cells around them (tools/glyphs/draw.py LAYOUT). */
static const struct nv2a_texrep_rect k_sheet_all[] = {
    R(0, 0, 128, 64)
};
/* The later Xbox pads print A B X Y as the first Xbox pad does: the top row stays the game's own picture,
 * in place, untouched. (Valve's pads print them as light letters on dark buttons: they replace the whole sheet.) */
static const struct nv2a_texrep_rect k_sheet_lower[] = {
    R(0, 30, 62, 34),      /* the white and black buttons: L1, R1 */
    R(62, 29, 18, 35),     /* the L and R triggers: L2, R2 */
    R(80, 29, 48, 35)      /* the Start button and the word under it */
};
/* The original Xbox pad's discs when the face layout swaps them: only the top row is drawn over (the
 * white and black buttons, the triggers and Start stay the game's own). */
static const struct nv2a_texrep_rect k_sheet_top[] = {
    R(0, 0, 128, 29)
};
/* The same with the modern lower row: the top row, then what LOWER has. */
static const struct nv2a_texrep_rect k_sheet_top_lower[] = {
    R(0, 0, 128, 29),
    R(0, 30, 62, 34),
    R(62, 29, 18, 35),
    R(80, 29, 48, 35)
};
static const struct nv2a_texrep_rect k_single[] = {
    R(0, 0, 32, 32)
};

/* "dpad", 32x16: the triangles the d-pad prompt is drawn from (down and right, mirrored for up and left). */
static const struct nv2a_texrep_rect k_dpad_all[] = {
    R(0, 0, 32, 16)
};

#define ALL(img)   { (img), k_sheet_all, 1 }
#define LOWER(img) { (img), k_sheet_lower, 3 }
#define TOP(img)   { (img), k_sheet_top, 1 }
#define TOP_LOWER(img) { (img), k_sheet_top_lower, 4 }
#define ONE(img)   { (img), k_single, 1 }
#define DPAD(img)  { (img), k_dpad_all, 1 }
#define KEEP       { 0, 0, 0 }

/* variants[set - 1], set = xbox_glyph_set (pad_glyphs.h). The last five are the sets drawn for a pad read
 * by letter: the face layout (Input > Face buttons = Nintendo) makes the game's A the right-hand button,
 * so the prompts show what that button is (pad_glyphs.h has the table). */
static const struct nv2a_texrep_variant k_sheet[] = {
    ALL(bo3_glyph_playstation_buttons),
    ALL(bo3_glyph_nintendo_position_buttons),
    ALL(bo3_glyph_nintendo_label_buttons),
    ALL(bo3_glyph_steam_buttons),
    LOWER(bo3_glyph_xbox_modern_buttons),
    ALL(bo3_glyph_positional_buttons),
    ALL(bo3_glyph_positional_swapped_buttons),
    ALL(bo3_glyph_playstation5_buttons),
    ALL(bo3_glyph_keyboard_buttons),
    TOP(bo3_glyph_xbox_swapped_buttons),
    ALL(bo3_glyph_playstation_swapped_buttons),
    ALL(bo3_glyph_playstation5_swapped_buttons),
    ALL(bo3_glyph_steam_swapped_buttons),
    TOP_LOWER(bo3_glyph_xbox_modern_swapped_buttons)
};
static const struct nv2a_texrep_variant k_a[] = {
    ONE(bo3_glyph_playstation_a_button),
    ONE(bo3_glyph_nintendo_position_a_button),
    ONE(bo3_glyph_nintendo_label_a_button),
    ONE(bo3_glyph_steam_a_button),
    KEEP,
    ONE(bo3_glyph_positional_a_button),
    ONE(bo3_glyph_positional_swapped_a_button),
    ONE(bo3_glyph_playstation5_a_button),
    ONE(bo3_glyph_keyboard_a_button),
    ONE(bo3_glyph_xbox_swapped_a_button),
    ONE(bo3_glyph_playstation_swapped_a_button),
    ONE(bo3_glyph_playstation5_swapped_a_button),
    ONE(bo3_glyph_steam_swapped_a_button),
    ONE(bo3_glyph_xbox_modern_swapped_a_button)
};
static const struct nv2a_texrep_variant k_b[] = {
    ONE(bo3_glyph_playstation_b_button),
    ONE(bo3_glyph_nintendo_position_b_button),
    ONE(bo3_glyph_nintendo_label_b_button),
    ONE(bo3_glyph_steam_b_button),
    KEEP,
    ONE(bo3_glyph_positional_b_button),
    ONE(bo3_glyph_positional_swapped_b_button),
    ONE(bo3_glyph_playstation5_b_button),
    ONE(bo3_glyph_keyboard_b_button),
    ONE(bo3_glyph_xbox_swapped_b_button),
    ONE(bo3_glyph_playstation_swapped_b_button),
    ONE(bo3_glyph_playstation5_swapped_b_button),
    ONE(bo3_glyph_steam_swapped_b_button),
    ONE(bo3_glyph_xbox_modern_swapped_b_button)
};

/* Only the keyboard changes it: arrow keys in place of the triangles. */
static const struct nv2a_texrep_variant k_dpad[] = {
    KEEP, KEEP, KEEP, KEEP, KEEP, KEEP, KEEP, KEEP,
    DPAD(bo3_glyph_keyboard_dpad),
    KEEP, KEEP, KEEP, KEEP, KEEP
};

_Static_assert(XBOX_GLYPH_SET_PLAYSTATION == 1 && XBOX_GLYPH_SET_NINTENDO_POSITION == 2
               && XBOX_GLYPH_SET_NINTENDO_LABEL == 3 && XBOX_GLYPH_SET_STEAM == 4
               && XBOX_GLYPH_SET_XBOX_MODERN == 5 && XBOX_GLYPH_SET_POSITIONAL == 6
               && XBOX_GLYPH_SET_POSITIONAL_SWAPPED == 7 && XBOX_GLYPH_SET_PLAYSTATION5 == 8
               && XBOX_GLYPH_SET_KEYBOARD == 9 && XBOX_GLYPH_SET_XBOX_SWAPPED == 10
               && XBOX_GLYPH_SET_PLAYSTATION_SWAPPED == 11 && XBOX_GLYPH_SET_PLAYSTATION5_SWAPPED == 12
               && XBOX_GLYPH_SET_STEAM_SWAPPED == 13 && XBOX_GLYPH_SET_XBOX_MODERN_SWAPPED == 14
               && XBOX_GLYPH_SET_COUNT == 15,
               "the variant tables are in xbox_glyph_set order");

#define NV2A_DXT45 0x0Fu

/* Data/Global.txd of the NTSC-U disc (the hashes are nv2a_texrep_hash of the
 * DXT5 bytes, as RECOMP_DEBUG=texrep_dump prints them). Another disc's
 * textures hash differently and are left alone. */
static const struct nv2a_texrep_tex k_tex[] = {
    { "Buttons",  0x9181d035e5fbb70eull, NV2A_DXT45, 128, 64, k_sheet, sizeof k_sheet / sizeof k_sheet[0] },
    { "A_Button", 0xefb4a0ec2d843383ull, NV2A_DXT45, 32, 32, k_a, sizeof k_a / sizeof k_a[0] },
    { "B_Button", 0xc883b79bdaf9ba47ull, NV2A_DXT45, 32, 32, k_b, sizeof k_b / sizeof k_b[0] },
    { "dpad",     0x21d72a610f043563ull, NV2A_DXT45, 32, 16, k_dpad, sizeof k_dpad / sizeof k_dpad[0] },
};

static void on_set(int set)
{
    nv2a_texrep_set_variant(set);
}

void bo3_glyphs_init(void)
{
    nv2a_texrep_register(k_tex, sizeof k_tex / sizeof k_tex[0]);
    xbox_InputSetGlyphListener(on_set);
}

const struct nv2a_texrep_variant *bo3_glyphs_sheets(unsigned *n)
{
    *n = sizeof k_sheet / sizeof k_sheet[0];
    return k_sheet;
}

#else

void bo3_glyphs_init(void)
{
}

const struct nv2a_texrep_variant *bo3_glyphs_sheets(unsigned *n)
{
    *n = 0;
    return 0;
}

#endif
