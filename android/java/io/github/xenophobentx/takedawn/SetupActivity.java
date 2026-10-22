package io.github.xenophobentx.takedawn;

import android.app.Activity;
import android.content.Intent;
import android.database.Cursor;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.provider.DocumentsContract;
import android.util.Log;
import android.util.TypedValue;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.File;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * The first start: the game's data from the player's own disc image.
 *
 * The app holds the program and none of the game's files. This page asks for
 * an image of the player's Burnout 3: Takedown disc (the release it was built for)
 * with the system's file picker, which needs no storage permission, and hands
 * the open file to the installer in the native library (the toolkit's
 * disc_install.c through install.c): every file is checked against the
 * disc's manifest while it is copied to
 *
 *   <files>/Burnout 3 Takedown/      and at the end    <files>/.complete
 *
 * The game folder of a disc that was extracted (the picker's "Choose game
 * folder"; ACTION_OPEN_DOCUMENT_TREE, BO-223) goes through the same
 * installer: a content:// tree has no file names, so the installer asks
 * openSource() below for each file by its path on the disc and reads it from
 * the descriptor that comes back. Same manifest check, same journal, same
 * messages; nothing is staged, so no second copy of the data is made.
 *
 * An install that was stopped goes on where it was when the same image (or
 * folder) is chosen again. A game folder copied there by hand (the way before this
 * page) is checked where it lies; nothing is copied then.
 *
 * In a process of its own (android:process=":setup"), as the bug report: the
 * native library is loaded here for the installer alone, and the game starts
 * in a fresh process afterwards.
 */
public class SetupActivity extends Activity {
    private static final int PICK = 1;
    private static final int PICK_TREE = 2;
    private LinearLayout box;
    private TextView status, detail;
    private ProgressBar bar;
    private Button pick, pickTree, cancel, start, driver;
    private volatile boolean running;
    private String root;
    /** The disc this build wants, from the native side; for the static advice texts. */
    private static String WANT = "the disc it was built for";
    private String[] about = { "Burnout 3: Takedown", "North America (NTSC-U) retail", "716",
            "2476107072", "3000000000", "" };

    private static native int nativeState(String root);
    private static native String nativeAbout();
    private static native void nativeCancel();
    private native String nativeInstall(int fd, String folder, String root);
    private native String nativeInstallTree(String root);

    // The picked document tree, read by the installer through openSource().
    private Uri tree;
    private boolean fromTree;
    /** The size of the file openSource() returned a descriptor of (read by the native side). */
    @SuppressWarnings("unused")
    private volatile long srcSize;
    private String treeBase;
    private final Map<String, Map<String, Entry>> listings = new HashMap<>();

    private static final class Entry {
        String id;
        boolean dir;
        long size;
    }

    /** Called by the installer, on its thread. */
    @SuppressWarnings("unused")
    private void onProgress(final double fraction, final String file) {
        runOnUiThread(new Runnable() {
            @Override public void run() {
                bar.setProgress((int) (fraction * 1000));
                detail.setText(String.format("%.0f %%   %s", fraction * 100, file));
            }
        });
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        root = GameActivity.filesDir(this).getAbsolutePath();
        ScrollView sv = new ScrollView(this);
        sv.setBackgroundColor(Color.BLACK);
        box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(64, 40, 64, 40);
        sv.addView(box);
        setContentView(sv);

        text("Takedawn: the game's data", 22, Color.WHITE);
        status = text("", 15, 0xFFD0D0D0);
        bar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        bar.setMax(1000);
        bar.setVisibility(View.GONE);
        box.addView(bar);
        detail = text("", 13, 0xFF909090);
        pick = button("Choose your Burnout 3: Takedown disc image", new View.OnClickListener() {
            @Override public void onClick(View v) {
                Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType("*/*");
                try {
                    startActivityForResult(i, PICK);
                } catch (Exception e) {
                    status.setText("This device has no file picker (" + e.getMessage() + ").\n\n"
                            + "Copy the unpacked disc (the folder with default.xbe in it) to\n"
                            + root + "/" + GameActivity.GAME_DIR + "\nand open the app again:"
                            + " the files are then checked where they are.");
                }
            }
        });
        pickTree = button("Choose game folder\u2026 (a disc already extracted to a folder)",
                new View.OnClickListener() {
            @Override public void onClick(View v) {
                Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
                try {
                    startActivityForResult(i, PICK_TREE);
                } catch (Exception e) {
                    status.setText("This device cannot choose a folder (" + e.getMessage() + ").\n\n"
                            + "Choose the disc image instead, or copy the folder with default.xbe"
                            + " in it to\n" + root + "/" + GameActivity.GAME_DIR
                            + "\nand open the app again: the files are then checked where they are.");
                }
            }
        });
        cancel = button("Cancel", new View.OnClickListener() {
            @Override public void onClick(View v) {
                nativeCancel();
                detail.setText("Stopping after the file in hand…");
            }
        });
        start = button("Start the game", new View.OnClickListener() {
            @Override public void onClick(View v) {
                startActivity(new Intent(SetupActivity.this, StartActivity.class));
                finish();
            }
        });
        driver = button("", new View.OnClickListener() {
            @Override public void onClick(View v) {
                startActivity(new Intent(SetupActivity.this, DriverActivity.class));
            }
        });
        text("The graphics driver is chosen automatically.", 13, 0xFF909090);
        text("Nothing of the game is in this app: its files come from your own disc. Make an"
                + " image of it (an .iso from the Xbox or a PC drive that reads Xbox discs)"
                + " and put the file on this device or its SD card, or choose the folder the"
                + " disc was extracted to (the one with default.xbe in it). The image or"
                + " folder is only read.",
                13, 0xFF909090);
        button("Licences", new View.OnClickListener() {
            @Override public void onClick(View v) {
                startActivity(new Intent(SetupActivity.this, LicensesActivity.class));
            }
        });
        int st;
        try {
            System.loadLibrary("SDL2");
            System.loadLibrary("main");
            about = nativeAbout().split("\n", -1);
            WANT = about[1];
            st = nativeState(root);
        } catch (Throwable e) {
            Log.e(GameActivity.TAG, "setup: " + e);
            show(false, false, false);
            status.setText("The program's library could not be loaded (" + e + ").");
            return;
        }
        handle(st);
        // From adb, for a test or a device without a file picker:
        //   am start -n <package>/.SetupActivity --es image <an image under the app's files folder>
        String image = getIntent().getStringExtra("image");
        if (image != null && st != 1 && st != 3) {
            try {
                File f = new File(image).getCanonicalFile();
                if (!f.getPath().startsWith(new File(root).getCanonicalPath() + "/")) {
                    throw new Exception("only a file under " + root + " is read this way");
                }
                run(ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY), null);
            } catch (Exception e) {
                status.setText(image + " could not be opened: " + e.getMessage());
            }
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (driver != null) {
            driver.setText("Graphics driver: " + GpuDriver.describe(this, GpuDriver.choice(this))
                    + "   (change\u2026)");
        }
    }

    private void handle(int st) {
        double gb = Long.parseLong(about[3]) / 1e9;
        if (st == 1) {
            show(false, false, true);
            status.setText("The game's data is installed and checked (" + about[2] + " files).");
        } else if (st == 3) {
            status.setText("There are game files in the app's folder from an earlier copy. They"
                    + " are checked now, where they are (" + String.format("%.1f", gb)
                    + " GB, a minute or two); nothing is copied.");
            run(null, new File(root, GameActivity.GAME_DIR).getAbsolutePath());
        } else {
            boolean begun = new File(root, "install.journal").isFile();
            show(true, false, false);
            status.setText((st == 2 ? "The data here was installed for another build of the"
                        + " game and has to be installed again.\n\n" : "")
                    + (begun ? "An install was begun and not finished. Choose the same image"
                        + " or folder again: the files already copied are kept.\n\n" : "")
                    + "The game needs the files of " + about[0] + ", " + about[1] + ": "
                    + about[2] + " files, " + String.format("%.2f", gb) + " GB, and "
                    + String.format("%.1f", Long.parseLong(about[4]) / 1e9) + " GB free here ("
                    + String.format("%.1f", new File(root).getUsableSpace() / 1e9)
                    + " GB is free now).");
            pick.requestFocus();
        }
    }

    private TextView text(String s, int sp, int color) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextColor(color);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setPadding(0, 12, 0, 12);
        box.addView(t);
        return t;
    }

    private Button button(String label, View.OnClickListener l) {
        Button b = new Button(this);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        b.setOnClickListener(l);
        box.addView(b);
        return b;
    }

    private void show(boolean p, boolean c, boolean s) {
        pick.setVisibility(p ? View.VISIBLE : View.GONE);
        pickTree.setVisibility(p ? View.VISIBLE : View.GONE);
        cancel.setVisibility(c ? View.VISIBLE : View.GONE);
        start.setVisibility(s ? View.VISIBLE : View.GONE);
        bar.setVisibility(c ? View.VISIBLE : View.GONE);
        if (s) {
            start.requestFocus();
        }
    }

    /** What to do about each of the installer's answers, after its own sentence. */
    private String advice(String code) {
        if (fromTree) {
            String f = adviceFolder(code);
            if (f != null) {
                return f;
            }
        }
        return adviceImage(code);
    }

    /** The same answers for a chosen folder; null where the image's words fit. */
    private static String adviceFolder(String code) {
        switch (code) {
        case "no-xbe":
        case "wrong-game":
            return "Choose the folder of Burnout 3: Takedown (the one with default.xbe in it).";
        case "truncated-image":
        case "damaged-source":
            return "The folder is incomplete or not a clean copy of the disc. Extract the disc"
                    + " again, or copy the folder to the device again, and choose it once"
                    + " more: the files already checked are kept.";
        case "disk-full":
            return "Free some space on the device and choose the folder again: the files"
                    + " already copied are kept.";
        case "source-unreadable":
        case "no-source":
            return "A file of the folder could not be read. If it is on an SD card or a network"
                    + " place, copy the folder to the device and choose it there.";
        case "cancelled":
            return "Stopped. Choose the same folder again to go on: the files already copied"
                    + " are kept.";
        default:
            return null;
        }
    }

    private static String adviceImage(String code) {
        switch (code) {
        case "not-xbox-image":
            return "Choose the image of the game disc itself: one file, about 7 GB (a full"
                    + " disc image) or 2.5 GB (an .xiso).";
        case "xbox360-disc":
            return "That is an Xbox 360 disc. The game wanted here is the one for the first Xbox.";
        case "no-xbe":
        case "wrong-game":
            return "Choose the image of Burnout 3: Takedown.";
        case "wrong-version":
            return "The default.xbe on this disc is not the exact file this build needs ("
                    + WANT + "): every byte of it is checked.\n\n"
                    + "Most often it is a modified copy. Softmods, hard-disk loaders and"
                    + " trainers patch a few bytes of default.xbe and keep the original beside"
                    + " it, as default.bak or default.xbe.bak. If the folder has one: move the"
                    + " patched default.xbe out of the folder, rename default.bak to"
                    + " default.xbe, and choose the folder again.\n\n"
                    + "If it is the disc of another region or the demo, it needs the build"
                    + " made for that disc; this one is for " + WANT + ".";
        case "truncated-image":
        case "damaged-source":
            return "The image is incomplete or not a clean copy of the disc. Make it again,"
                    + " or copy it to the device again, and choose it once more: the files"
                    + " already checked are kept.";
        case "disk-full":
            return "Free some space on the device and choose the image again: the files"
                    + " already copied are kept.";
        case "no-permission":
        case "write-failed":
            return "The app's own folder could not be written. Check the device's storage and"
                    + " try again.";
        case "source-unreadable":
        case "no-source":
            return "The file could not be read. If it is on an SD card or a network place,"
                    + " copy it to the device and choose it there.";
        case "cancelled":
            return "Stopped. Choose the same image again to go on: the files already copied"
                    + " are kept.";
        default:
            return "";
        }
    }

    private void run(final ParcelFileDescriptor pfd, final String folder) {
        run(pfd, folder, false);
    }

    private void run(final ParcelFileDescriptor pfd, final String folder, final boolean asTree) {
        running = true;
        fromTree = asTree;
        show(false, true, false);
        bar.setProgress(0);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        new Thread(new Runnable() {
            @Override public void run() {
                String res;
                try {
                    res = asTree ? nativeInstallTree(root)
                            : nativeInstall(pfd != null ? pfd.getFd() : -1, folder, root);
                } catch (Throwable e) {
                    res = "internal\n" + e + "\n0 0 0 0";
                }
                try {
                    if (pfd != null) {
                        pfd.close();
                    }
                } catch (Exception e) {
                    // read only: nothing to lose
                }
                final String[] r = res.split("\n", -1);
                Log.i(GameActivity.TAG, "setup: " + r[0] + ": " + (r.length > 1 ? r[1] : "")
                        + " (" + (r.length > 2 ? r[2] : "") + ")");
                runOnUiThread(new Runnable() {
                    @Override public void run() {
                        running = false;
                        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                        detail.setText("");
                        if ("ok".equals(r[0])) {
                            show(false, false, true);
                            status.setText("The game's data is installed and checked ("
                                    + about[2] + " files).");
                        } else {
                            show(true, false, false);
                            String said = r.length > 1 ? r[1] : r[0];
                            // The installer's sentence for a wrong executable reads as if
                            // the region were refused; say first what is usually the cause.
                            status.setText("wrong-version".equals(r[0])
                                    ? advice(r[0]) + "\n\nDetails: " + said
                                    : said + "\n\n" + advice(r[0]));
                            pick.requestFocus();
                        }
                    }
                });
            }
        }, "install").start();
    }

    @Override
    protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request == PICK_TREE) {
            if (result == RESULT_OK && data != null && data.getData() != null) {
                tree = data.getData();
                treeBase = null;
                listings.clear();
                status.setText("Checking the folder and copying the game's data. The device may"
                        + " be left alone; the screen stays on.");
                run(null, null, true);
            }
            return;
        }
        if (request != PICK || result != RESULT_OK || data == null || data.getData() == null) {
            return;
        }
        Uri u = data.getData();
        try {
            ParcelFileDescriptor pfd = getContentResolver().openFileDescriptor(u, "r");
            if (pfd == null) {
                throw new Exception("no file behind it");
            }
            status.setText("Checking the disc and copying the game's data. The device may be"
                    + " left alone; the screen stays on.");
            run(pfd, null);
        } catch (Exception e) {
            status.setText("The file could not be opened: " + e.getMessage() + "\n\n"
                    + advice("source-unreadable"));
        }
    }

    /** The children of a directory of the tree, by lower-case name; cached. */
    private Map<String, Entry> list(String docId) {
        Map<String, Entry> m = listings.get(docId);
        if (m != null) {
            return m;
        }
        m = new HashMap<>();
        Uri kids = DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId);
        Cursor q = null;
        try {
            q = getContentResolver().query(kids, new String[] {
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE }, null, null, null);
            while (q != null && q.moveToNext()) {
                Entry e = new Entry();
                e.id = q.getString(0);
                e.dir = DocumentsContract.Document.MIME_TYPE_DIR.equals(q.getString(2));
                e.size = q.isNull(3) ? -1 : q.getLong(3);
                String name = q.getString(1);
                if (name != null) {
                    m.put(name.toLowerCase(Locale.ROOT), e);
                }
            }
        } catch (Exception e) {
            Log.w(GameActivity.TAG, "setup: listing " + docId + ": " + e);
        } finally {
            if (q != null) {
                q.close();
            }
        }
        listings.put(docId, m);
        return m;
    }

    /**
     * The directory of the tree that holds default.xbe: the tree's own, or one
     * level below it (a disc extracted into a folder of its own name).
     */
    private String base() {
        if (treeBase == null) {
            String rootId = DocumentsContract.getTreeDocumentId(tree);
            treeBase = rootId;
            if (!list(rootId).containsKey("default.xbe")) {
                for (Entry e : list(rootId).values()) {
                    if (e.dir && list(e.id).containsKey("default.xbe")) {
                        treeBase = e.id;
                        break;
                    }
                }
            }
        }
        return treeBase;
    }

    /**
     * Called by the installer, on its thread: the file at `rel` (as on the
     * disc, forward slashes; any case) as a descriptor to read, whose size is
     * left in srcSize. -1: the tree has no such file. -2: it has and cannot be
     * read.
     */
    @SuppressWarnings("unused")
    private int openSource(String rel) {
        Entry e = null;
        String dir = base();
        String[] parts = rel.split("/");
        for (int i = 0; i < parts.length; i++) {
            e = list(dir).get(parts[i].toLowerCase(Locale.ROOT));
            if (e == null || (e.dir != (i < parts.length - 1))) {
                return -1;
            }
            dir = e.id;
        }
        if (e == null) {
            return -1;
        }
        try {
            ParcelFileDescriptor pfd = getContentResolver().openFileDescriptor(
                    DocumentsContract.buildDocumentUriUsingTree(tree, e.id), "r");
            if (pfd == null) {
                return -2;
            }
            long size = pfd.getStatSize();
            srcSize = size >= 0 ? size : e.size;
            return pfd.detachFd();
        } catch (Exception ex) {
            Log.w(GameActivity.TAG, "setup: " + rel + ": " + ex);
            return -2;
        }
    }

    @Override
    public void onBackPressed() {
        if (running) {
            nativeCancel();
            detail.setText("Stopping after the file in hand…");
        } else {
            super.onBackPressed();
        }
    }
}
