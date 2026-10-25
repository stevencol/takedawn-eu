package io.github.xenophobentx.takedawn;

import android.content.Context;
import android.content.SharedPreferences;

import java.io.File;
import java.io.RandomAccessFile;

/**
 * Which release's program runs: the North American (NTSC-U) or the European
 * (PAL) one. A build with both (BuildInfo.LIBS has two) carries one native
 * library for each, libmain_pal.so and libmain_ntsc.so, and a process loads
 * only one: the one of the disc in the app's files folder, read from the
 * region in the certificate of its default.xbe; before a disc is there, the
 * choice made on the setup page (CHOOSE), the first library by default. A
 * build with one library (BuildInfo.LIBS has one, "main") never asks.
 */
final class Region {
    private static final String PREFS = "region";
    private static final String KEY = "lib";

    private Region() {
    }

    /** True when this build carries both releases' programs. */
    static boolean both() {
        return BuildInfo.LIBS.length > 1;
    }

    /** The library name (without lib and .so) this process loads. */
    static String lib(Context c) {
        if (!both()) {
            return BuildInfo.LIBS[0];
        }
        String disc = ofDisc(GameActivity.filesDir(c));
        if (disc != null) {
            return disc;
        }
        SharedPreferences p = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String chosen = p.getString(KEY, null);
        for (String l : BuildInfo.LIBS) {
            if (l.equals(chosen)) {
                return l;
            }
        }
        return BuildInfo.LIBS[0];
    }

    /** The setup page's choice, for a device with no disc installed yet. */
    static void choose(Context c, String lib) {
        c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, lib).commit();
    }

    /** The other library, for the page's "change" button. */
    static String other(Context c) {
        String now = lib(c);
        return now.equals(BuildInfo.LIBS[0]) ? BuildInfo.LIBS[1] : BuildInfo.LIBS[0];
    }

    /** A person's name for a library: "Europe (PAL)" or "North America (NTSC-U)". */
    static String name(String lib) {
        return lib.endsWith("_ntsc") ? "North America (NTSC-U)" : "Europe (PAL)";
    }

    /** The manifest id the library was built with, for the data marker's check. */
    static String manifest(String lib) {
        for (int i = 0; i < BuildInfo.LIBS.length; i++) {
            if (BuildInfo.LIBS[i].equals(lib)) {
                return BuildInfo.MANIFESTS[i];
            }
        }
        return BuildInfo.MANIFESTS[0];
    }

    /**
     * The library of the disc installed under files/: the game region in its
     * default.xbe's certificate (1 North America, 4 Europe), or null when
     * there is no file, it is not an XBE, or no library fits.
     */
    static String ofDisc(File files) {
        File xbe = new File(new File(files, GameActivity.GAME_DIR), "default.xbe");
        if (!xbe.isFile()) {
            return null;
        }
        try (RandomAccessFile f = new RandomAccessFile(xbe, "r")) {
            byte[] h = new byte[0x120];
            f.readFully(h);
            if (h[0] != 'X' || h[1] != 'B' || h[2] != 'E' || h[3] != 'H') {
                return null;
            }
            long base = le32(h, 0x104);
            long cert = le32(h, 0x118);
            if (cert <= base) {
                return null;
            }
            f.seek(cert - base + 0xA0);
            byte[] r = new byte[4];
            f.readFully(r);
            long region = le32(r, 0);
            for (String l : BuildInfo.LIBS) {
                if ((region == 1 && l.endsWith("_ntsc")) || (region == 4 && l.endsWith("_pal"))) {
                    return l;
                }
            }
        } catch (Exception e) {
            // not readable: the choice below decides
        }
        return null;
    }

    private static long le32(byte[] b, int o) {
        return (b[o] & 0xFFL) | (b[o + 1] & 0xFFL) << 8 | (b[o + 2] & 0xFFL) << 16
                | (b[o + 3] & 0xFFL) << 24;
    }
}
