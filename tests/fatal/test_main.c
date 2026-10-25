/* When bo3_fatal may show a message box (adapters/platform/fatal.c). */
#include "fatal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#  define SETENV(k, v) _putenv_s(k, v)
#  define UNSETENV(k) _putenv_s(k, "")
#else
#  define SETENV(k, v) setenv(k, v, 1)
#  define UNSETENV(k) unsetenv(k)
#endif

static int s_fail;
#define CHECK(c, ...) do { if (!(c)) { s_fail++; fprintf(stderr, "FAIL line %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

int main(void)
{
    UNSETENV("RECOMP_HEADLESS");
    UNSETENV("TAKEDAWN_NO_SETUP");
#if defined(__linux__) && !defined(__ANDROID__)
    SETENV("DISPLAY", ":0");
#endif
    CHECK(bo3_fatal_box_wanted(), "a plain start with a display may show the box");

    SETENV("RECOMP_HEADLESS", "1");
    CHECK(!bo3_fatal_box_wanted(), "RECOMP_HEADLESS=1: no box");
    SETENV("RECOMP_HEADLESS", "0");
    CHECK(bo3_fatal_box_wanted(), "RECOMP_HEADLESS=0 is off");
    UNSETENV("RECOMP_HEADLESS");

    SETENV("TAKEDAWN_NO_SETUP", "1");
    CHECK(!bo3_fatal_box_wanted(), "TAKEDAWN_NO_SETUP=1: no box");
    UNSETENV("TAKEDAWN_NO_SETUP");

#if defined(__linux__) && !defined(__ANDROID__)
    UNSETENV("DISPLAY");
    UNSETENV("WAYLAND_DISPLAY");
    CHECK(!bo3_fatal_box_wanted(), "Linux without a display: no box");
#endif

    /* Headless: text to stderr, returns at once (a box would block here). */
    SETENV("RECOMP_HEADLESS", "1");
    bo3_fatal("Takedawn cannot start", "test %d", 1);
    bo3_fatal_box("Takedawn cannot start", "test %d", 2);

    if (s_fail) {
        fprintf(stderr, "%d failed\n", s_fail);
        return 1;
    }
    printf("fatal: ok\n");
    return 0;
}
