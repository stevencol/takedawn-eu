package io.github.xenophobentx.takedawn;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.FeatureInfo;
import android.content.pm.PackageManager;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * Which Vulkan driver the game opens (docs/android.md, "The GPU driver").
 *
 * The game needs Vulkan 1.3. Where the device's own driver has it, that one
 * is used. Where it has not and the GPU is an Adreno (the Retroid Pocket 5's
 * stock driver stops at 1.1), the game loads Mesa's Turnip driver into its
 * own process through libadrenotools: no root, nothing outside the app.
 *
 *   1. A driver the user put into <files>/driver/: a .so, or a driver package
 *      as the Android emulators use (a .zip with meta.json naming the
 *      library). It is copied into the app's internal storage, because the
 *      dynamic linker loads nothing from shared storage. Always preferred.
 *   2. The Turnip driver the APK was built with (libvulkan_freedreno.so in
 *      the native library directory), when the device's driver is older than
 *      Vulkan 1.3 and the GPU is an Adreno.
 *   3. The device's own driver.
 *
 * RECOMP_ANDROID_DRIVER in env.txt overrides: "system" (3), "bundled" (2
 * whatever the device says), "user" (1).
 *
 * The player's own choice (DriverActivity, "Graphics driver") comes before
 * that order: "bundled", "system", or "custom", a driver package picked with
 * the system's file picker and kept in the app's internal storage
 * (<internal files>/driver-custom), where an update of the app leaves it.
 * "auto" (nothing chosen) is the order above.
 *
 * A start on any driver but the bundled one leaves a note (driver-trial.txt)
 * that the game removes once it has presented its first frames through
 * Vulkan. A start that finds the note still there knows the last one did not
 * get that far (the driver crashed, or lacks what the game needs, and the
 * game fell to its CPU rasteriser): it goes back to Automatic (fallback()),
 * says so, and stays there until the player chooses again. A driver that
 * gets past its first frames and loses the device later does the same
 * (GameActivity.graphicsDriverLost). No loop.
 *
 * Turnip drives Adreno GPUs only: on any other GPU (Mali, Xclipse) the
 * bundled driver, a package and the driver folder are never loaded, and
 * Automatic is the device's own driver.
 */
final class GpuDriver {
    static final String BUNDLED = "libvulkan_freedreno.so";
    private static final int VULKAN_1_3 = 0x403000;

    /** The directory and file name for the runtime, or null for the system's driver. */
    final String dir, name;
    /** One line for the log and the start page. */
    final String what;

    /** A driver on trial: the game is to say when it has shown frames with it. */
    boolean trial;
    /** Said to the player at this start (a fallback), or null. */
    String note;

    private GpuDriver(String dir, String name, String what) {
        this.dir = dir;
        this.name = name;
        this.what = what;
    }

    static final String PREFS = "driver";

    static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /** "auto", "bundled", "system" or "custom". */
    static String choice(Context c) {
        return prefs(c).getString("choice", "auto");
    }

    // commit(), not apply(): a choice made on the warning box or after a
    // lost device is followed at once by the process's end (the restart),
    // which an apply() still in flight does not survive.
    static void setChoice(Context c, String v) {
        prefs(c).edit().putString("choice", v).remove("note").commit();
        trialFile(c).delete();
    }

    /** The choice in a few words, for a row or a button. */
    static String describe(Context c, String ch) {
        int sys = systemVulkanVersion(c);
        java.util.Map<String, String> m = customMeta(c);
        if ("custom".equals(ch) && !m.isEmpty()) {
            return "package " + m.get("name");
        }
        if ("system".equals(ch)) {
            return "this device's driver (Vulkan " + versionString(sys) + ")";
        }
        if ("auto".equals(ch) && userFile(c) != null && isAdreno()) {
            return "the file in the driver folder (" + userFile(c).getName() + ")";
        }
        if (hasBundled(c) && isAdreno() && ("bundled".equals(ch) || sys < VULKAN_1_3)) {
            String mesa = prefs(c).getString("bundledMesa", null);
            return "built-in Turnip" + (mesa != null ? " (Mesa " + mesa + ")" : "");
        }
        return "this device's driver (Vulkan " + versionString(sys) + ")";
    }

    /** The next of the choices there are: in the app, the device's, the picked package. */
    static String nextChoice(Context c) {
        String ch = choice(c);
        boolean pkg = !customMeta(c).isEmpty();
        if (!isAdreno()) {
            return "auto";      // the device's own driver is the only one
        }
        if ("auto".equals(ch) || "bundled".equals(ch)) {
            return "system";
        }
        if ("system".equals(ch)) {
            return pkg ? "custom" : (hasBundled(c) ? "bundled" : "system");
        }
        return hasBundled(c) ? "bundled" : "system";
    }

    /**
     * Where a driver that failed goes back to: Automatic, unless a file in
     * the driver folder would be loaded again under Automatic; then the
     * bundled driver (on an Adreno) or the device's own.
     */
    static String fallback(Context c) {
        // Automatic would load the same driver again: a file in the driver
        // folder, or the device's own where it has Vulkan 1.3 (choose()).
        if (isAdreno() && (userFile(c) != null || systemVulkanVersion(c) >= VULKAN_1_3)) {
            return hasBundled(c) ? "bundled" : "system";
        }
        return "auto";
    }

    /** "Automatic", or what fallback() chose, for a note. */
    static String fallbackName(Context c, String to) {
        return "auto".equals(to) ? "Automatic" : describe(c, to);
    }

    /**
     * The driver that was chosen failed (no first frames, or a lost device
     * later): the choice goes back (fallback()) with a note for the driver
     * page. Returns the note.
     */
    static String dropFailed(Context c, String was, boolean lost) {
        String to = fallback(c);
        String note = lost
                ? (was.isEmpty() ? "The driver" : Character.toUpperCase(was.charAt(0))
                        + was.substring(1)) + " stopped working while the game ran. The game is back on "
                        + fallbackName(c, to) + "."
                : "The last start on " + was + " didn't get to the first frames. The game is"
                        + " back on " + fallbackName(c, to) + ".";
        prefs(c).edit().putString("choice", to).putString("note", note).commit();
        trialFile(c).delete();
        Log.i(GameActivity.TAG, "GPU driver: " + note);
        return note;
    }

    static File customDir(Context c) {
        return new File(c.getFilesDir(), "driver-custom");
    }

    static File trialFile(Context c) {
        return new File(c.getFilesDir(), "driver-trial.txt");
    }

    /** Written by the game when its Vulkan device is up: driver=, device=, vulkan=, mesa=. */
    static File infoFile(Context c) {
        return new File(c.getFilesDir(), "driver-active.txt");
    }

    static java.util.Map<String, String> readKeys(File f) {
        java.util.Map<String, String> m = new java.util.LinkedHashMap<>();
        if (f.isFile()) {
            try (InputStream in = new FileInputStream(f)) {
                for (String line : new String(readAll(in), StandardCharsets.UTF_8).split("\n")) {
                    int eq = line.indexOf('=');
                    if (eq > 0) {
                        m.put(line.substring(0, eq).trim(), line.substring(eq + 1).trim());
                    }
                }
            } catch (Exception e) {
                Log.e(GameActivity.TAG, f + ": " + e);
            }
        }
        return m;
    }

    /** The imported package's meta.txt (name, version, lib, source, sha256); empty if none. */
    static java.util.Map<String, String> customMeta(Context c) {
        java.util.Map<String, String> m = readKeys(new File(customDir(c), "meta.txt"));
        String lib = m.get("lib");
        if (lib == null || !new File(customDir(c), lib).isFile()) {
            m.clear();
        }
        return m;
    }

    static void removeCustom(Context c) {
        File[] old = customDir(c).listFiles();
        if (old != null) {
            for (File f : old) {
                f.delete();
            }
        }
        if ("custom".equals(choice(c))) {
            setChoice(c, "auto");
        }
    }

    /** arm64 shared object: ELF, 64-bit, little-endian, machine AArch64 (183), type DYN. */
    static void checkElf(File f) throws Exception {
        byte[] h = new byte[20];
        try (InputStream in = new FileInputStream(f)) {
            if (in.read(h) != h.length) {
                throw new Exception(f.getName() + " is too short to be a library");
            }
        }
        if (h[0] != 0x7f || h[1] != 'E' || h[2] != 'L' || h[3] != 'F') {
            throw new Exception(f.getName() + " is not a library (no ELF header)");
        }
        int machine = (h[18] & 0xff) | (h[19] & 0xff) << 8;
        if (h[4] != 2 || h[5] != 1 || machine != 183) {
            throw new Exception(f.getName() + " is not an arm64 library (class " + h[4]
                    + ", machine " + machine + "): a driver for this device is 64-bit ARM");
        }
        if ((((h[16] & 0xff) | (h[17] & 0xff) << 8)) != 3) {
            throw new Exception(f.getName() + " is not a shared library");
        }
        if (f.length() < 512 * 1024 || f.length() > 400L * 1024 * 1024) {
            throw new Exception(f.getName() + " is " + f.length() + " bytes: not the size of a"
                    + " Vulkan driver (0.5 to 400 MB)");
        }
    }

    private static String jsonString(String json, String key) {
        Matcher m = Pattern.compile("\"" + key + "\"\\s*:\\s*\"([^\"]*)\"").matcher(json);
        return m.find() ? m.group(1) : null;
    }

    /**
     * A driver the player picked: an adrenotools package (.zip: meta.json naming
     * the library, the library, its companions) or a bare .so. Unpacked beside
     * the present one, checked, and only then put in its place. Returns the
     * package's name; throws with a sentence for the player.
     */
    static String importPackage(Context c, InputStream in, String display) throws Exception {
        File tmp = new File(c.getFilesDir(), "driver-import");
        File[] old = tmp.listFiles();
        if (old != null) {
            for (File f : old) {
                f.delete();
            }
        }
        tmp.mkdirs();
        File pkg = new File(tmp, "package.bin");
        MessageDigest sha = MessageDigest.getInstance("SHA-256");
        long total = 0;
        try (OutputStream o = new FileOutputStream(pkg)) {
            byte[] b = new byte[65536];
            int n;
            while ((n = in.read(b)) > 0) {
                total += n;
                if (total > 512L * 1024 * 1024) {
                    throw new Exception("the file is over 512 MB: not a driver package");
                }
                sha.update(b, 0, n);
                o.write(b, 0, n);
            }
        }
        StringBuilder hex = new StringBuilder();
        for (byte x : sha.digest()) {
            hex.append(String.format("%02x", x));
        }
        byte[] head = new byte[4];
        try (InputStream h = new FileInputStream(pkg)) {
            if (h.read(head) != 4) {
                throw new Exception("the file is empty");
            }
        }
        String lib, name = display, version = "";
        if (head[0] == 'P' && head[1] == 'K') {
            String meta = null, only = null;
            int count = 0;
            try (ZipInputStream z = new ZipInputStream(new FileInputStream(pkg))) {
                ZipEntry e;
                while ((e = z.getNextEntry()) != null) {
                    String n = new File(e.getName()).getName();     // no paths out of the folder
                    if (e.isDirectory() || n.isEmpty()) {
                        continue;
                    }
                    if (n.equals("meta.json")) {
                        meta = new String(readAll(z), StandardCharsets.UTF_8);
                    } else if (n.endsWith(".so") || n.contains(".so.")) {
                        if (++count > 64) {
                            throw new Exception("more than 64 libraries in the package");
                        }
                        copy(z, new File(tmp, n));
                        only = n;
                    }
                }
            } catch (java.util.zip.ZipException e) {
                throw new Exception("the zip cannot be read (" + e.getMessage() + ")");
            }
            if (meta == null) {
                throw new Exception("no meta.json in the zip: not an adrenotools driver package");
            }
            lib = jsonString(meta, "libraryName");
            if (lib == null || lib.contains("/")) {
                throw new Exception("meta.json names no library (libraryName)");
            }
            if (!new File(tmp, lib).isFile()) {
                throw new Exception("meta.json names " + lib + ", which is not in the zip ("
                        + count + " libraries are)");
            }
            if (jsonString(meta, "name") != null) {
                name = jsonString(meta, "name");
            }
            if (jsonString(meta, "driverVersion") != null) {
                version = jsonString(meta, "driverVersion");
            }
        } else if (head[0] == 0x7f && head[1] == 'E') {
            lib = display.endsWith(".so") ? new File(display).getName() : "libvulkan_custom.so";
            if (!pkg.renameTo(new File(tmp, lib))) {
                throw new Exception("could not store the library");
            }
        } else {
            throw new Exception("neither a zip package nor a library");
        }
        checkElf(new File(tmp, lib));
        pkg.delete();
        try (OutputStream o = new FileOutputStream(new File(tmp, "meta.txt"))) {
            o.write(("name=" + name.replace('\n', ' ') + "\nversion=" + version.replace('\n', ' ')
                    + "\nlib=" + lib + "\nsource=" + display.replace('\n', ' ')
                    + "\nsha256=" + hex + "\n").getBytes(StandardCharsets.UTF_8));
        }
        // In place of the present one.
        File dir = customDir(c);
        File[] had = dir.listFiles();
        if (had != null) {
            for (File f : had) {
                f.delete();
            }
        }
        dir.delete();
        if (!tmp.renameTo(dir)) {
            throw new Exception("could not store the driver in the app's storage");
        }
        return name;
    }

    /** The Vulkan version of the device's own driver, as VK_MAKE_VERSION; 0 if none is declared. */
    static int systemVulkanVersion(Context c) {
        int best = 0;
        FeatureInfo[] features = c.getPackageManager().getSystemAvailableFeatures();
        if (features != null) {
            for (FeatureInfo f : features) {
                if (PackageManager.FEATURE_VULKAN_HARDWARE_VERSION.equals(f.name)) {
                    best = Math.max(best, f.version);
                }
            }
        }
        return best;
    }

    static String versionString(int v) {
        return v == 0 ? "none" : (v >> 22) + "." + ((v >> 12) & 0x3ff);
    }

    /** Qualcomm's kernel graphics driver: the GPU is an Adreno, which Turnip drives. */
    static boolean isAdreno() {
        return new File("/dev/kgsl-3d0").exists();
    }

    static boolean hasBundled(Context c) {
        return new File(c.getApplicationInfo().nativeLibraryDir, BUNDLED).isFile();
    }

    static File userDir(Context c) {
        return new File(GameActivity.filesDir(c), "driver");
    }

    /** The user's driver file in <files>/driver, the newest .so or .zip; null if there is none. */
    static File userFile(Context c) {
        File[] list = userDir(c).listFiles();
        File best = null;
        if (list != null) {
            for (File f : list) {
                String n = f.getName().toLowerCase();
                if (f.isFile() && (n.endsWith(".so") || n.endsWith(".zip"))
                        && (best == null || f.lastModified() > best.lastModified())) {
                    best = f;
                }
            }
        }
        return best;
    }

    /** True when the game has a Vulkan 1.3 driver to try. */
    static boolean usable(Context c) {
        return systemVulkanVersion(c) >= VULKAN_1_3 || userFile(c) != null
                || !customMeta(c).isEmpty() || (hasBundled(c) && isAdreno());
    }

    static GpuDriver choose(Context c, String override) {
        int sys = systemVulkanVersion(c);
        String sysWhat = "the device's own driver (Vulkan " + versionString(sys) + ")";
        if ("system".equals(override)) {
            return new GpuDriver(null, null, sysWhat + ", as env.txt asks");
        }
        String ch = override != null ? "auto" : choice(c);
        String note = null;
        File trial = trialFile(c);
        if (override == null && trial.isFile()) {
            // The last start, on a driver that is not the bundled one, did
            // not get to its first frames.
            String was = "";
            try (InputStream in = new FileInputStream(trial)) {
                was = new String(readAll(in), StandardCharsets.UTF_8).trim();
            } catch (Exception e) {
                was = "the chosen driver";
            }
            dropFailed(c, was, false);
            ch = choice(c);
            // The toast is two lines at most (Android 12 on); the whole
            // story is on the driver page.
            note = "The picked driver didn't start, so the game is back on "
                    + fallbackName(c, ch) + ".";
        }
        GpuDriver d = null;
        if ("custom".equals(ch) && isAdreno()) {
            java.util.Map<String, String> m = customMeta(c);
            if (!m.isEmpty()) {
                d = new GpuDriver(customDir(c).getAbsolutePath(), m.get("lib"),
                        "the chosen driver package " + m.get("name") + " (" + m.get("lib") + ")");
                d.trial = true;
            }
        } else if ("system".equals(ch)) {
            d = new GpuDriver(null, null, sysWhat + ", as chosen");
            d.trial = hasBundled(c) && isAdreno();
        } else if ("auto".equals(ch) && isAdreno()) {
            File user = userFile(c);
            if (user != null && !"bundled".equals(override)) {
                try {
                    File so = installUser(c, user);
                    d = new GpuDriver(so.getParent(), so.getName(),
                            "the user's driver " + user.getName() + " (" + so.getName() + ")");
                    d.trial = override == null;
                } catch (Exception e) {
                    Log.e(GameActivity.TAG, "driver " + user + ": " + e);
                }
            }
        }
        if (d == null) {
            // Automatic: the device's own driver wherever it has Vulkan 1.3,
            // so a phone of any make runs on what it ships with; the driver
            // the app came with only on an Adreno whose own driver is older
            // (the Retroid Pocket 5's stops at 1.1), or when chosen. A forced
            // "system" that is too old still gets Turnip from the override
            // "bundled". Never on a GPU that is not an Adreno (a choice of
            // "bundled" left from before is Automatic there).
            boolean wantBundled = "bundled".equals(override)
                    || (isAdreno() && !"system".equals(ch)
                        && ("bundled".equals(ch) || sys < VULKAN_1_3));
            if (wantBundled && hasBundled(c)) {
                d = new GpuDriver(c.getApplicationInfo().nativeLibraryDir, BUNDLED,
                        "the Mesa Turnip driver in the app (the device's own is Vulkan "
                        + versionString(sys) + ")");
            } else {
                d = new GpuDriver(null, null, sysWhat);
                // A device driver that does not reach the first frames sends
                // the next start to the bundled one (fallback()).
                d.trial = override == null && hasBundled(c) && isAdreno();
            }
        }
        d.note = note;
        return d;
    }

    /** Copies the .so (or the library a .zip package names) to <internal files>/driver. */
    private static File installUser(Context c, File src) throws Exception {
        File dir = new File(c.getFilesDir(), "driver");
        dir.mkdirs();
        File stamp = new File(dir, "source.txt");
        String id = src.getName() + " " + src.length() + " " + src.lastModified();
        String had = "";
        if (stamp.isFile()) {
            try (InputStream in = new FileInputStream(stamp)) {
                had = new String(readAll(in), StandardCharsets.UTF_8);
            }
        }
        String[] parts = had.split("\n");
        if (parts.length == 2 && parts[0].equals(id) && new File(dir, parts[1]).isFile()) {
            return new File(dir, parts[1]);      // the copy is this file's
        }
        File[] old = dir.listFiles();
        if (old != null) {
            for (File f : old) {
                f.delete();
            }
        }
        String lib;
        if (src.getName().toLowerCase().endsWith(".zip")) {
            lib = unzipDriver(src, dir);
        } else {
            lib = src.getName();
            try (InputStream in = new FileInputStream(src)) {
                copy(in, new File(dir, lib));
            }
        }
        try (OutputStream o = new FileOutputStream(stamp)) {
            o.write((id + "\n" + lib).getBytes(StandardCharsets.UTF_8));
        }
        return new File(dir, lib);
    }

    /** A driver package: meta.json's "libraryName", or the only .so in it. Returns the library's name. */
    private static String unzipDriver(File zip, File dir) throws Exception {
        String named = null, only = null;
        int count = 0;
        try (ZipInputStream z = new ZipInputStream(new FileInputStream(zip))) {
            ZipEntry e;
            while ((e = z.getNextEntry()) != null) {
                String n = new File(e.getName()).getName();     // no paths out of the folder
                if (e.isDirectory() || n.isEmpty()) {
                    continue;
                }
                if (n.equals("meta.json")) {
                    Matcher m = Pattern.compile("\"libraryName\"\\s*:\\s*\"([^\"/]+)\"")
                            .matcher(new String(readAll(z), StandardCharsets.UTF_8));
                    if (m.find()) {
                        named = m.group(1);
                    }
                } else if (n.endsWith(".so")) {
                    copy(z, new File(dir, n));
                    only = n;
                    count++;
                }
            }
        }
        if (named != null && new File(dir, named).isFile()) {
            return named;
        }
        if (count == 1) {
            return only;
        }
        throw new Exception("no meta.json naming a library, and " + count + " libraries in the package");
    }

    static byte[] readAll(InputStream in) throws Exception {
        java.io.ByteArrayOutputStream o = new java.io.ByteArrayOutputStream();
        byte[] b = new byte[65536];
        int n;
        while ((n = in.read(b)) > 0) {
            o.write(b, 0, n);
        }
        return o.toByteArray();
    }

    private static void copy(InputStream in, File to) throws Exception {
        try (OutputStream o = new FileOutputStream(to)) {
            byte[] b = new byte[65536];
            int n;
            while ((n = in.read(b)) > 0) {
                o.write(b, 0, n);
            }
        }
    }
}
