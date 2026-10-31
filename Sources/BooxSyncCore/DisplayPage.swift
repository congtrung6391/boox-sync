/// The page the Boox browser shows. One canvas at native pixel size; tiles arrive over a WebSocket.
public enum DisplayPage {
    public static let httpPort: UInt16 = 8765
    public static let webSocketPort: UInt16 = 8766

    public static let html = """
    <!doctype html>
    <html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
    <title>BooxSync display</title>
    <style>
      html,body{margin:0;height:100%;background:#fff;overflow:hidden}
      canvas{display:block;width:100vw;height:100vh}
    </style></head>
    <body><canvas id="c"></canvas>
    <script>
    const canvas = document.getElementById('c');
    const ctx = canvas.getContext('2d');
    let ws = null;
    let queue = Promise.resolve();

    function fit() {
      const d = window.devicePixelRatio || 1;
      // Even sizes keep tile math simple on the Mac side.
      canvas.width = Math.floor(window.innerWidth * d / 2) * 2;
      canvas.height = Math.floor(window.innerHeight * d / 2) * 2;
      ctx.fillStyle = '#fff';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
    }

    function status(text) {
      ctx.fillStyle = '#fff';
      ctx.fillRect(0, 0, 900, 90);
      ctx.fillStyle = '#000';
      ctx.font = '32px sans-serif';
      ctx.fillText(text, 20, 55);
    }

    function hello() {
      if (ws && ws.readyState === 1) {
        ws.send(JSON.stringify({type: 'hello', w: canvas.width, h: canvas.height, dpr: window.devicePixelRatio}));
      }
    }

    function connect() {
      if (ws && ws.readyState <= 1) return;
      ws = new WebSocket('ws://localhost:\(webSocketPort)');
      ws.binaryType = 'arraybuffer';
      ws.onopen = () => { status('Connected, waiting for the Mac...'); hello(); };
      ws.onmessage = (event) => {
        const view = new DataView(event.data);
        if (view.getUint8(0) !== 1) return;
        const x = view.getUint16(1), y = view.getUint16(3), w = view.getUint16(5), h = view.getUint16(7);
                const blob = new Blob([event.data.slice(9)], {type: 'image/png'});
        // Decode in order so overlapping tiles never swap.
        queue = queue.then(() => createImageBitmap(blob)).then((bitmap) => {
          ctx.drawImage(bitmap, x, y, w, h);
          bitmap.close();
          ws.send(JSON.stringify({type: 'ok', x, y, w, h}));
        }).catch((e) => { ws.send(JSON.stringify({type: 'fail', x, y, w, h, e: String(e)})); });
      };
      ws.onclose = () => { if (!document.hidden) { status('Disconnected, retrying...'); setTimeout(connect, 1000); } };
      ws.onerror = () => { try { ws.close(); } catch (e) {} };
    }

    // A background tab must not keep reconnecting: the Mac serves only one client and the newest wins.
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) { if (ws) ws.close(); } else { connect(); }
    });
    window.addEventListener('resize', () => { fit(); hello(); });
    canvas.addEventListener('click', () => {
      if (document.documentElement.requestFullscreen) document.documentElement.requestFullscreen().catch(() => {});
    });
    fit();
    status('Starting...');
    connect();
    </script></body></html>
    """
}
