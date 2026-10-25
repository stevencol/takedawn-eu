package com.stevencol.takedawn;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.Arrays;
import java.util.Comparator;

/**
 * "Licences": the notices and licence texts that ship in the APK, as plain
 * text (assets/licenses/, put there by tools/android/build-apk.sh from the
 * release set tools/release/common.sh copy_licenses makes, plus the texts of
 * the Android-only parts: Mesa Turnip, libadrenotools). A list of the files;
 * one opens in a scrolling view. Back goes from the text to the list.
 *
 * Reached from the setup page and from "Takedawn: graphics driver".
 */
public class LicensesActivity extends Activity {
    private static final String DIR = "licenses";
    private String open;        // the file shown, or null for the list

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        open = state != null ? state.getString("open") : null;
        build();
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        if (open != null) {
            out.putString("open", open);
        }
    }

    /** The files, the overview and the source note first, the rest by name. */
    private String[] files() {
        String[] names;
        try {
            names = getAssets().list(DIR);
        } catch (Exception e) {
            names = null;
        }
        if (names == null) {
            return new String[0];
        }
        Arrays.sort(names, new Comparator<String>() {
            @Override public int compare(String a, String b) {
                int ra = rank(a), rb = rank(b);
                return ra != rb ? ra - rb : a.compareToIgnoreCase(b);
            }
        });
        return names;
    }

    private static int rank(String n) {
        return n.equals("THIRD_PARTY.txt") ? 0 : n.equals("SOURCE.txt") ? 1 : 2;
    }

    private String read(String name) {
        try (InputStream in = getAssets().open(DIR + "/" + name)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[16384];
            int n;
            while ((n = in.read(buf)) > 0) {
                out.write(buf, 0, n);
            }
            return new String(out.toByteArray(), java.nio.charset.StandardCharsets.UTF_8);
        } catch (Exception e) {
            return "This file could not be read (" + e + ").";
        }
    }

    private void build() {
        ScrollView sv = new ScrollView(this);
        sv.setBackgroundColor(Color.BLACK);
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(64, 40, 64, 40);
        sv.addView(box);
        setContentView(sv);
        if (open != null) {
            text(box, open, 18, Color.WHITE, false);
            text(box, read(open), 13, 0xFFD0D0D0, true);
            Button back = button(box, "Back to the list", new View.OnClickListener() {
                @Override public void onClick(View v) { show(null); }
            });
            sv.setFocusable(true);
            sv.requestFocus();      // the pad's d-pad scrolls the text
            back.setFocusable(true);
            return;
        }
        text(box, "Licences", 22, Color.WHITE, false);
        text(box, "Takedawn is free software and holds the work of other people. These are"
                + " the notices and licence texts that come in this app.", 14, 0xFFB0B0B0, false);
        String[] names = files();
        if (names.length == 0) {
            text(box, "This build has no licence texts in it (a development build). A release"
                    + " APK carries them.", 14, 0xFFF0C85A, false);
        }
        Button first = null;
        for (final String n : names) {
            Button b = button(box, label(n), new View.OnClickListener() {
                @Override public void onClick(View v) { show(n); }
            });
            if (first == null) {
                first = b;
            }
        }
        button(box, "Close", new View.OnClickListener() {
            @Override public void onClick(View v) { finish(); }
        });
        if (first != null) {
            first.requestFocus();
        }
    }

    private static String label(String n) {
        if (n.equals("THIRD_PARTY.txt")) {
            return "Third-party notices (start here)";
        }
        if (n.equals("SOURCE.txt")) {
            return "Where the source of this build is";
        }
        return n;
    }

    private void show(String name) {
        open = name;
        build();
    }

    @Override
    public void onBackPressed() {
        if (open != null) {
            show(null);
        } else {
            super.onBackPressed();
        }
    }

    private void text(LinearLayout box, String s, int sp, int color, boolean mono) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextColor(color);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setPadding(0, 10, 0, 10);
        if (mono) {
            t.setTypeface(Typeface.MONOSPACE);
        }
        box.addView(t);
    }

    private Button button(LinearLayout box, String label, View.OnClickListener l) {
        Button b = new Button(this);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        b.setGravity(android.view.Gravity.START | android.view.Gravity.CENTER_VERTICAL);
        b.setOnClickListener(l);
        box.addView(b);
        return b;
    }
}
