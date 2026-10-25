package com.stevencol.takedawn;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.widget.TextView;

import java.io.File;

/**
 * What the icon opens: the game, when the user's disc data is in place and
 * there is a graphics driver to run it on; otherwise a page that says what is
 * missing. The game is built from the user's own disc on their PC
 * (docs/android.md); nothing of it is in the repository, and the data is not
 * in the APK.
 */
public class StartActivity extends Activity {
    private boolean canStartAnyway;
    private String pageText;        // what the page says, for a bug report

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        File files = GameActivity.filesDir(this);
        File game = new File(files, GameActivity.GAME_DIR);
        // The directories exist from the first start on, so a file manager or
        // MTP shows where to copy to.
        game.mkdirs();
        GpuDriver.userDir(this).mkdirs();
        if (!dataComplete(this, files)) {
            // No data yet, a copy made by hand that is not checked, or an
            // install for another build: the setup page (SetupActivity).
            startActivity(new Intent(this, SetupActivity.class));
            finish();
            return;
        }
        // The legacy build is for devices without Vulkan 1.3: the processor
        // is what it runs on there, so no page asks first.
        if (!BuildInfo.LEGACY && !GpuDriver.usable(this)) {
            // No silent fall to the CPU rasteriser at a few frames a second.
            canStartAnyway = true;
            page("This device's graphics driver has Vulkan "
                    + GpuDriver.versionString(GpuDriver.systemVulkanVersion(this))
                    + ". The game needs Vulkan 1.3.\n\n"
                    + (GpuDriver.isAdreno()
                        ? "Open \"Takedawn: graphics driver\" from the launcher to load a"
                          + " Turnip driver file (.zip).\n\n"
                        : "There is no other driver for this GPU.\n\n")
                    + "Tap or press A to start anyway. The game then runs on the processor"
                    + " at a few frames per second.");
            return;
        }
        startGame();
    }

    /** The installer's marker is there and names this program's disc manifest. */
    static boolean dataComplete(android.content.Context c, File files) {
        File mark = new File(files, ".complete");
        if (!mark.isFile() || !new File(new File(files, GameActivity.GAME_DIR), "default.xbe").isFile()) {
            return false;
        }
        try (java.io.InputStream in = new java.io.FileInputStream(mark)) {
            String t = new String(GpuDriver.readAll(in), java.nio.charset.StandardCharsets.UTF_8);
            return t.contains(Region.manifest(Region.lib(c)));
        } catch (Exception e) {
            return false;
        }
    }

    private void startGame() {
        // A restart (RestartActivity) names the process it waited for; the
        // game checks again that it is gone before it opens the GPU.
        startActivity(new Intent(this, GameActivity.class).putExtra(RestartActivity.EXTRA_PID,
                getIntent().getIntExtra(RestartActivity.EXTRA_PID, 0)));
        finish();
    }

    private void page(String text) {
        TextView t = new TextView(this);
        t.setTextColor(Color.WHITE);
        t.setBackgroundColor(Color.BLACK);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        t.setGravity(Gravity.CENTER);
        t.setPadding(48, 48, 48, 48);
        t.setText(text);
        t.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (canStartAnyway) {
                    startGame();
                }
            }
        });
        // A bug report can be made from here too (ReportActivity; Y on a pad).
        pageText = text;
        setContentView(ReportActivity.withButton(this, t, text));
    }

    @Override
    public boolean onKeyUp(int code, KeyEvent e) {
        if (canStartAnyway && (code == KeyEvent.KEYCODE_BUTTON_A || code == KeyEvent.KEYCODE_ENTER
                || code == KeyEvent.KEYCODE_DPAD_CENTER)) {
            startGame();
            return true;
        }
        if (code == KeyEvent.KEYCODE_BUTTON_Y && pageText != null) {
            ReportActivity.open(this, pageText);
            return true;
        }
        return super.onKeyUp(code, e);
    }
}
