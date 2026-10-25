/* A start-up failure the player can see (fatal.h). */
#include "fatal.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#  include <windows.h>
#else
#  include <SDL.h>
#endif

static int env_set(const char *name)
{
    const char *v = getenv(name);

    return v && *v && strcmp(v, "0");
}

int bo3_fatal_box_wanted(void)
{
    if (env_set("RECOMP_HEADLESS") || env_set("TAKEDAWN_NO_SETUP"))
        return 0;
#if defined(__linux__) && !defined(__ANDROID__)
    {
        const char *x = getenv("DISPLAY"), *w = getenv("WAYLAND_DISPLAY");
        if (!(x && *x) && !(w && *w))
            return 0;
    }
#endif
    return 1;
}

static void box(const char *title, const char *text)
{
#if defined(_WIN32)
    /* Text in UTF-8 (the process's code page is, or the text is ASCII). */
    wchar_t wt[2400], wc[160];

    if (MultiByteToWideChar(CP_UTF8, 0, text, -1, wt, 2400)
            && MultiByteToWideChar(CP_UTF8, 0, title, -1, wc, 160))
        MessageBoxW(NULL, wt, wc, MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
    else
        MessageBoxA(NULL, text, title, MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
#else
    /* Works before SDL_Init and from the guest's thread (SDL hands the
     * Cocoa one to the main thread). */
    if (SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, title, text, NULL) != 0)
        fprintf(stderr, "[FATAL] no message box (%s)\n", SDL_GetError());
#endif
}

void bo3_fatal_box(const char *title, const char *fmt, ...)
{
    char text[2400];
    va_list ap;

    if (!bo3_fatal_box_wanted())
        return;
    va_start(ap, fmt);
    vsnprintf(text, sizeof text, fmt, ap);
    va_end(ap);
    box(title, text);
}

void bo3_fatal(const char *title, const char *fmt, ...)
{
    char text[2400];
    va_list ap;

    va_start(ap, fmt);
    vsnprintf(text, sizeof text, fmt, ap);
    va_end(ap);
    fprintf(stderr, "%s: %s\n", title, text);
    fflush(stderr);
    if (bo3_fatal_box_wanted())
        box(title, text);
}
