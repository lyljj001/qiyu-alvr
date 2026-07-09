package alvr.client;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.BatteryManager;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.Window;
import android.view.WindowManager;

import androidx.annotation.NonNull;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.util.LinkedList;
import java.util.concurrent.Semaphore;

public class VRActivity extends Activity {
    // NOTE: native libraries are loaded DEFENSIVELY inside onCreate(), not in a
    // static block. A static-block load that fails (missing/ABI-mismatched .so,
    // Rust static-init panic) would throw before onCreate even runs, producing a
    // silent flash-crash with no logs. Loading in onCreate lets us catch it.

    final static String TAG = "VRActivity";
    private static final String LOG_FILE_NAME = "alvr_runtime.log";

    class RenderingCallbacks implements SurfaceHolder.Callback {
        @Override
        public void surfaceCreated(@NonNull final SurfaceHolder holder) {
            mScreenSurface = holder.getSurface();
            maybeResume();
        }

        @Override
        public void surfaceChanged(@NonNull SurfaceHolder holder, int _fmt, int _w, int _h) {
            maybePause();
            mScreenSurface = holder.getSurface();
            maybeResume();
        }

        @Override
        public void surfaceDestroyed(@NonNull SurfaceHolder holder) {
            maybePause();
            mScreenSurface = null;
        }
    }

    final BroadcastReceiver mBatInfoReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context ctxt, Intent intent) {
            onBatteryChangedNative(intent.getIntExtra(BatteryManager.EXTRA_LEVEL, 0),
                    intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0);
        }
    };

    boolean mResumed = false;
    Handler mRenderingHandler;
    HandlerThread mRenderingHandlerThread;
    Surface mScreenSurface;

    // Cache method references for performance reasons
    final Runnable mRenderRunnable = this::render;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // 1) Surface any crash from the PREVIOUS run. The C++ logger writes to our
        //    private dir; on the next launch we read the tail and show it on-screen.
        //    No USB / wireless-debug / file-manager needed.
        maybeShowPreviousCrash();

        // 2) Load native libs defensively. alvr_client_core (Rust) first, then our
        //    native_lib which depends on it. Any failure is caught and shown.
        try {
            System.loadLibrary("alvr_client_core");
            System.loadLibrary("native_lib");
        } catch (Throwable t) {
            showErrorDialog("Native library load failed:\n\n" + Log.getStackTraceString(t), true);
            return;
        }

        // 3) Point the C++ file logger at our private, always-writable directory.
        setLogFilePath(new File(getFilesDir(), LOG_FILE_NAME).getAbsolutePath());

        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        requestWindowFeature(Window.FEATURE_NO_TITLE);

        setContentView(R.layout.activity_main);
        SurfaceView surfaceView = findViewById(R.id.surfaceview);

        mRenderingHandlerThread = new HandlerThread("Rendering thread");
        mRenderingHandlerThread.start();
        mRenderingHandler = new Handler(mRenderingHandlerThread.getLooper());
        mRenderingHandler.post(this::initializeNative);

        SurfaceHolder holder = surfaceView.getHolder();
        holder.addCallback(new RenderingCallbacks());

        this.registerReceiver(this.mBatInfoReceiver, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        Semaphore sem = new Semaphore(1);
        try {
            sem.acquire();
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
        mRenderingHandler.post(() -> {
            Log.i(TAG, "Destroying vrapi state.");
            destroyNative();
            sem.release();
        });
        mRenderingHandlerThread.quitSafely();
        try {
            // Wait until destroyNative() is finished. Can't use Thread.join here, because
            // the posted lambda might not run, so wait on an object instead.
            sem.acquire();
            sem.release();
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();

        mResumed = true;
        maybeResume();
    }

    void maybeResume() {
        if (mResumed && mScreenSurface != null) {
            mRenderingHandler.post(() -> {
                onResumeNative(mScreenSurface);

                // bootstrap the rendering loop
                mRenderingHandler.post(mRenderRunnable);
            });
        }
    }

    @Override
    protected void onPause() {
        maybePause();
        mResumed = false;

        super.onPause();
    }

    void maybePause() {
        // the check (mResumed && mScreenSurface != null) is intended: either mResumed or
        // mScreenSurface != null will be false after this method returns.
        if (mResumed && mScreenSurface != null) {
            mRenderingHandler.post(this::onPauseNative);
        }
    }

    private void render() {
        if (mResumed && mScreenSurface != null) {
            renderNative();

            mRenderingHandler.removeCallbacks(mRenderRunnable);
            mRenderingHandler.postDelayed(mRenderRunnable, 2);
        }
    }

    native void initializeNative();

    native void destroyNative();

    native void onResumeNative(Surface screenSurface);

    native void onPauseNative();

    native void onStreamStartNative();

    native void onStreamStopNative();

    native void renderNative();

    native void onBatteryChangedNative(int battery, boolean plugged);

    native void setLogFilePath(String path);

    @SuppressWarnings("unused")
    public void onStreamStart() {
        mRenderingHandler.post(this::onStreamStartNative);
    }

    @SuppressWarnings("unused")
    public void onStreamStop() {
        mRenderingHandler.post(this::onStreamStopNative);
    }

    // ---- On-device crash surfacing (no USB / wireless-debug needed) ---------

    private File crashLogFile() {
        return new File(getFilesDir(), LOG_FILE_NAME);
    }

    private void maybeShowPreviousCrash() {
        File f = crashLogFile();
        if (!f.exists() || f.length() == 0) return;
        // Scan the recent tail for a clean-exit marker. If the previous run did
        // NOT exit cleanly (crashed anywhere: lib load, init, render), surface it.
        String scan = readTail(f, 500);
        if (scan == null) return;
        if (scan.toLowerCase().contains("clean exit")) return; // previous run exited fine
        String tail = readTail(f, 200);
        showErrorDialog("Previous run did not exit cleanly. Last log:\n\n"
                + (tail != null ? tail : scan), false);
    }

    private String readTail(File f, int lines) {
        try {
            BufferedReader br = new BufferedReader(new FileReader(f));
            LinkedList<String> queue = new LinkedList<>();
            String line;
            while ((line = br.readLine()) != null) {
                queue.add(line);
                if (queue.size() > lines) queue.removeFirst();
            }
            br.close();
            StringBuilder sb = new StringBuilder();
            for (String l : queue) sb.append(l).append("\n");
            return sb.toString();
        } catch (IOException e) {
            return null;
        }
    }

    private void showErrorDialog(String msg, boolean finishOnDismiss) {
        // Best-effort: also drop a copy where a headset file-manager can reach it,
        // in case the VR compositor hides this Android dialog.
        try {
            File dump = new File(Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS), "alvr_crash.txt");
            try (FileWriter w = new FileWriter(dump, true)) {
                w.write(msg);
                w.write("\n\n");
            }
        } catch (IOException ignored) {
            // scoped storage may block this on some API levels; ignore.
        }

        AlertDialog.Builder b = new AlertDialog.Builder(this)
                .setTitle("ALVR Qiyu - debug info")
                .setMessage(msg)
                .setPositiveButton("OK", (d, w) -> {
                    d.dismiss();
                    if (finishOnDismiss) finish();
                });
        // Run on the main looper in case we're on the rendering thread.
        runOnUiThread(b::show);
    }
}
