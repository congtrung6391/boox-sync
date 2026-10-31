package dev.booxsync.display;

import android.app.Activity;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.view.WindowManager;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.Arrays;
import java.util.zip.Inflater;

/**
 * Shows tiles sent by the Mac over an adb-forwarded socket (the Boox as a second display).
 *
 * Protocol (big endian):
 *   device -> Mac, once after connect:  "BXH1" u16 width u16 height
 *   Mac -> device, repeated:            'T' u16 x u16 y u16 w u16 h u32 length payload
 *   payload = raw DEFLATE of w*h gray bytes (0 = black, 255 = white)
 */
public class MainActivity extends Activity {
    static final String TAG = "BooxDisplay";
    static final int PORT = 7788;

    private TileView view;
    private volatile boolean running;
    private Thread serverThread;
    private volatile ServerSocket serverSocket;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        view = new TileView(this);
        setContentView(view);
        view.setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
    }

    @Override
    protected void onResume() {
        super.onResume();
        running = true;
        serverThread = new Thread(this::serve, "booxdisplay-server");
        serverThread.start();
    }

    @Override
    protected void onPause() {
        super.onPause();
        running = false;
        try {
            if (serverSocket != null) serverSocket.close();
        } catch (Exception ignored) {
        }
    }

    private void serve() {
        try (ServerSocket server = new ServerSocket(PORT, 1, InetAddress.getByName("127.0.0.1"))) {
            serverSocket = server;
            server.setReuseAddress(true);
            while (running) {
                try (Socket client = server.accept()) {
                    client.setTcpNoDelay(true);
                    handle(client);
                } catch (Exception e) {
                    if (running) Log.w(TAG, "client ended: " + e);
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "server failed: " + e);
        }
    }

    private void handle(Socket client) throws Exception {
        DataInputStream in = new DataInputStream(new java.io.BufferedInputStream(client.getInputStream(), 1 << 16));
        DataOutputStream out = new DataOutputStream(client.getOutputStream());

        while (view.getWidth() == 0 && running) Thread.sleep(50);
        out.writeBytes("BXH1");
        out.writeShort(view.getWidth());
        out.writeShort(view.getHeight());
        out.flush();
        view.ensureBitmap();
        Log.i(TAG, "client connected, view " + view.getWidth() + "x" + view.getHeight());

        Inflater inflater = new Inflater(true);
        while (running) {
            int type = in.read();
            if (type < 0) return;
            if (type != 'T') throw new IllegalStateException("unknown message " + type);
            int x = in.readUnsignedShort(), y = in.readUnsignedShort();
            int w = in.readUnsignedShort(), h = in.readUnsignedShort();
            int length = in.readInt();
            byte[] payload = new byte[length];
            in.readFully(payload);

            byte[] gray = new byte[w * h];
            inflater.reset();
            inflater.setInput(payload);
            int n = 0;
            while (n < gray.length) {
                int got = inflater.inflate(gray, n, gray.length - n);
                if (got == 0 && (inflater.finished() || inflater.needsInput())) break;
                n += got;
            }
            if (n != gray.length) {
                Log.w(TAG, "short tile " + n + "/" + gray.length);
                Arrays.fill(gray, n, gray.length, (byte) 0xFF);
            }
            view.applyTile(x, y, w, h, gray);
        }
    }

    static class TileView extends View {
        private Bitmap bitmap;
        private final Object lock = new Object();
        private final Paint paint = new Paint();

        TileView(Context context) {
            super(context);
            setBackgroundColor(Color.WHITE);
        }

        void ensureBitmap() {
            synchronized (lock) {
                if (bitmap == null || bitmap.getWidth() != getWidth() || bitmap.getHeight() != getHeight()) {
                    bitmap = Bitmap.createBitmap(getWidth(), getHeight(), Bitmap.Config.ARGB_8888);
                    bitmap.eraseColor(Color.WHITE);
                }
            }
        }

        void applyTile(int x, int y, int w, int h, byte[] gray) {
            int[] pixels = new int[w * h];
            for (int i = 0; i < pixels.length; i++) {
                int g = gray[i] & 0xFF;
                pixels[i] = 0xFF000000 | (g << 16) | (g << 8) | g;
            }
            synchronized (lock) {
                if (bitmap == null) return;
                int cw = Math.min(w, bitmap.getWidth() - x), ch = Math.min(h, bitmap.getHeight() - y);
                if (cw <= 0 || ch <= 0) return;
                bitmap.setPixels(pixels, 0, w, x, y, cw, ch);
            }
            postInvalidate(x, y, x + w, y + h);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            synchronized (lock) {
                if (bitmap != null) canvas.drawBitmap(bitmap, 0, 0, paint);
            }
        }
    }
}
