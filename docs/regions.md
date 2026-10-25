# Other releases (PAL)

The port is written against the North American (NTSC-U) `default.xbe`:
`config/patches.json`, `config/seed_functions.json`, `config/spin_waits.json`
and the hand-written code in `core` name the game's functions and globals
by their addresses in that executable. The European (PAL) retail executable is
the same program compiled again: the same size, the same title id, about 900
bytes more code spread through `.text`, and so every function and global a
little further on, by an amount that changes along the image (from +0 at the
start of `.text` to +0x3C0 in `.data`, with steps in between).

A build for another release translates those addresses; it does not fork the
configuration.

## How it works

- `tools/region/addrmap.py build US.xbe OTHER.xbe` aligns the two executables
  instruction by instruction (and the initialized data word by word) and
  writes `build/region/map.json`: every matched instruction, and every address
  an instruction holds paired with the one the same instruction holds in the
  other build. For NTSC-U → PAL: 98.9% of the instructions and 99.7% of the
  data words match. `addrmap.py lookup map.json 0x4D5370 ...` asks it.
- `tools/region/region.py export` collects every US address the project uses
  (the three config files, each `GA(...)` and each `sub_XXXXXXXX` in
  `core`), looks each up in the map and writes
  `config/region/<build>.json`. It refuses an address it does not know for
  certain: an instruction must be a matched instruction, data must be
  referenced by the code or an aligned data word. What it cannot place goes
  in that file's `overrides`, by hand, with a note. `review` lists the
  addresses placed from a neighbour (fields inside a struct).
- `regen.sh` runs `tools/region/region.py apply` first. It knows the release
  by the SHA-256 of `default.xbe`; for NTSC-U it changes nothing, for another
  release it writes the translated config files into `build/xr/region/` and
  feeds them to the recompiler, and writes `core/recomp/gen/region_map.h`,
  which `core/guest_addr.h` includes.

Only a maintainer with both executables runs `addrmap.py` and `export`. A
build for PAL needs only the PAL disc: the committed table is enough.

## In the code

A guest address in `core` is written `GA(0x4D5370)`: the literal alone,
without an offset (`GA(0x73A1D0u) + 0x10u`). For NTSC-U `GA(x)` is `x`; for
another release `region_map.h` defines one `GA_<literal>` per spelling. A
generated function called or wrapped by name (`sub_001D2879`, and
`sub_X_gen` in `recomp_manual.c`) keeps its US name in the source; the header
renames it.

After adding an address: run `export` again, so the table has it. `apply`
stops with the address when it does not.

## The disc

`tools/install/supported.json` lists the supported executables;
`config/disc/<build>.manifest` the files of each disc. The PAL disc has its
text and speech in English, Dutch, Spanish and Swedish (`Data/Global??.bin`,
`Head??.bin`, the radio DJ in `Tracks/**/S_DJ*.xwb` rather than `E_DJ*`).
The overlay's fonts, sprites and sounds are the same bytes in both releases.

The PAL manifest was made from an extracted folder, not a disc image; make it
again with `tools/release/make_manifest.py` from an image when there is one.

## Both releases at once

One program is built for one release (its addresses are compile-time), so a
machine that plays either disc carries two:

- `BO3_GEN_DIR` (CMake, and the same variable for `regen.sh`, with `BO3_XBE`
  and `BO3_XR_OUT`) names the folder of the generated C. The usual
  `core/recomp/gen` is the one of before; a second release goes in
  `core/recomp/gen.ntsc-u` (git-ignored) from its own default.xbe.
- `-DBO3_EXE_SUFFIX=-pal-retail` / `-ntsc-u-retail` names the programs
  `burnout3-pal-retail` and `burnout3-ntsc-u-retail`, side by side in `bin/`.
  Started on the other release's disc, either one reads the region in the
  certificate of that `default.xbe` (1 North America, 4 Europe) and starts
  the other (`[REGION]` in the log); a program without its id in its name
  (`burnout3`) hands nothing over.
- Android: `BO3_ANDROID_GEN2=<the second tree> tools/android/build-apk.sh`
  builds both and packs `libmain_pal.so` and `libmain_ntsc.so`; the app loads
  the one of the disc under its files folder (`Region.java`), and before a
  disc is there the setup page has a button to say which release it is.
  A build without `BO3_ANDROID_GEN2` is the one `libmain.so` of before.

## Known differences to check

- Language: the runtime reports English (`XC_LANGUAGE` 1) and NTSC-M 60 Hz,
  as an NTSC-U console. The PAL build then takes `GlobalEn.bin`.
- Speed units: the km/h patch follows the language index; a PAL English game
  already shows miles, as the UK release does.
- `sub_0017A720` (PAL `sub_0017AA60`) is compiled with other registers in the
  PAL build; its patch site is placed by hand.
