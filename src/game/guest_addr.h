/* Guest addresses of the release being built.
 *
 * The hand-written code names the title's globals and functions by their
 * addresses in the North American default.xbe: GA(0x4D5370), sub_001D2879.
 * Another release has the same globals and functions a little further on.
 * regen.sh writes recomp/gen/region_map.h for the default.xbe it translates
 * (tools/region/region.py apply): for NTSC-U it is empty and GA(x) is x; for
 * another release it defines GA_<literal> and sub_<US> as that release's
 * addresses and names, from config/region/<build>.json.
 *
 * GA() takes the literal alone, spelled as it is, without an offset:
 * GA(0x73A1D0u) + 0x10u, not GA(0x73A1D0u + 0x10u).
 */
#ifndef BO3_GUEST_ADDR_H
#define BO3_GUEST_ADDR_H

#if defined(__has_include)
#  if __has_include("recomp/gen/region_map.h")
#    include "recomp/gen/region_map.h"
#  endif
#endif

#ifndef GA
#  define GA(x) (x)
#endif
/* The SHA-256 of the default.xbe the build was translated from. */
#ifndef BO3_XBE_SHA256
#  define BO3_XBE_SHA256 "9f497acd82adb8edfb72cc31aeeb35010b45d32b13a3f1fc6540717ff24d13f9"
#endif

#endif
