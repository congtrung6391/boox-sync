package dev.booxsync.probe;

import android.app.Activity;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.View;

/**
 * Feasibility probe for the Mac -> Boox second display.
 * Draws a moving square (small dirty rect), a ticking clock and a frame counter, so we can see
 * how the e-ink panel behaves for partial updates from a sideloaded app. Also reports whether
 * any Onyx e-ink API is reachable without the Onyx SDK.
 */
public class MainActivity extends Activity {
    private static final String TAG = "BooxProbe";
    private ProbeView view;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        view = new ProbeView(this);
        setContentView(view);
        view.setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
    }

    @Override
    protected void onResume() {
        super.onResume();
        view.start();
    }

    @Override
    protected void onPause() {
        super.onPause();
        view.stop();
    }

    static class ProbeView extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Handler handler = new Handler(Looper.getMainLooper());
        private final String[] apiReport;
        private int frame;
        private long startMs;
        private boolean running;
        private final Rect square = new Rect();

        ProbeView(Context context) {
            super(context);
            setBackgroundColor(Color.WHITE);
            apiReport = probeApis();
            for (String line : apiReport) Log.i(TAG, line);
            dumpMethods("android.onyx.ViewUpdateHelper");
        }

        /** Lists the public API of a hidden Onyx framework class to logcat. */
        private static void dumpMethods(String className) {
            try {
                Class<?> c = Class.forName(className);
                for (java.lang.reflect.Method m : c.getDeclaredMethods()) {
                    StringBuilder sb = new StringBuilder("METHOD ").append(java.lang.reflect.Modifier.toString(m.getModifiers()))
                        .append(' ').append(m.getReturnType().getSimpleName()).append(' ').append(m.getName()).append('(');
                    Class<?>[] params = m.getParameterTypes();
                    for (int i = 0; i < params.length; i++) sb.append(i > 0 ? ", " : "").append(params[i].getSimpleName());
                    Log.i(TAG, sb.append(')').toString());
                }
            } catch (Throwable t) {
                Log.i(TAG, "dump failed: " + t);
            }
        }

        private static String[] probeApis() {
            String[] classes = {
                "com.onyx.android.sdk.api.device.epd.EpdController",
                "android.onyx.ViewUpdateHelper",
                "android.onyx.optimization.EACGlobalManager",
                "android.view.ViewRootImpl",
            };
            String[] lines = new String[classes.length];
            for (int i = 0; i < classes.length; i++) {
                try {
                    Class.forName(classes[i]);
                    lines[i] = "FOUND   " + classes[i];
                } catch (Throwable t) {
                    lines[i] = "missing " + classes[i];
                }
            }
            return lines;
        }

        void start() {
            running = true;
            startMs = System.currentTimeMillis();
            handler.post(tick);
        }

        void stop() {
            running = false;
            handler.removeCallbacks(tick);
        }

        private final Runnable tick = new Runnable() {
            @Override public void run() {
                if (!running) return;
                frame++;
                // Every 10th frame redraw everything, otherwise only the square and the counter.
                if (frame % 10 == 0) {
                    invalidate();
                } else {
                    int w = getWidth(), h = getHeight();
                    int size = Math.min(w, h) / 6;
                    int x = (frame * 37) % Math.max(1, w - size);
                    int y = h / 2 + (int) (Math.sin(frame / 3.0) * (h / 6.0));
                    Rect dirty = new Rect(square);
                    square.set(x, y, x + size, y + size);
                    dirty.union(square);
                    dirty.union(new Rect(0, 0, w, 260));
                    invalidate(dirty);
                }
                handler.postDelayed(this, 500);
            }
        };

        @Override
        protected void onDraw(Canvas canvas) {
            int w = getWidth(), h = getHeight();
            canvas.drawColor(Color.WHITE);

            paint.setColor(Color.BLACK);
            paint.setTextSize(56);
            canvas.drawText("BooxProbe  frame " + frame + "  " + w + "x" + h, 40, 90, paint);
            paint.setTextSize(40);
            long secs = (System.currentTimeMillis() - startMs) / 1000;
            canvas.drawText("running " + secs + " s, updates every 500 ms", 40, 160, paint);
            paint.setTextSize(32);
            canvas.drawText("Every 10th frame is a full redraw", 40, 215, paint);

            // Static reference content that should NOT flicker during partial updates.
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(3);
            for (int i = 0; i < 8; i++) canvas.drawRect(40 + i * 20, 300 + i * 20, w - 40 - i * 20, h - 40 - i * 20, paint);
            paint.setStyle(Paint.Style.FILL);

            // Moving square (the dirty-rect test).
            canvas.drawRect(square, paint);

            // Gray ramp, to see how greys render in the current refresh mode.
            for (int i = 0; i < 16; i++) {
                int g = i * 17;
                paint.setColor(Color.rgb(g, g, g));
                canvas.drawRect(w - 40 - 16 * 40 + i * 40, 240, w - 40 - 16 * 40 + (i + 1) * 40, 290, paint);
            }

            paint.setColor(Color.BLACK);
            paint.setTextSize(28);
            int y = h - 60;
            for (int i = apiReport.length - 1; i >= 0; i--) {
                canvas.drawText(apiReport[i], 60, y, paint);
                y -= 36;
            }
        }
    }
}
