// Serveur statique du build web avec COOP/COEP (comme web/.htaccess).
// /api/* est relayé vers le backend PHP local (php -S) si API_PORT est défini.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const MIME = {
  '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.png': 'image/png', '.json': 'application/json',
};

export function serve(root, port, apiPort = 0) {
  const server = http.createServer((req, res) => {
    res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    res.setHeader('Cache-Control', 'no-cache');
    const url = new URL(req.url, 'http://x');
    if (apiPort && url.pathname.startsWith('/api')) {
      const proxied = http.request({ host: '127.0.0.1', port: apiPort, path: req.url,
        method: req.method, headers: req.headers }, (up) => {
        res.writeHead(up.statusCode, up.headers);
        up.pipe(res);
      });
      proxied.on('error', () => { res.writeHead(502); res.end(); });
      req.pipe(proxied);
      return;
    }
    let file = path.join(root, decodeURIComponent(url.pathname));
    if (file.endsWith('/')) file += 'index.html';
    fs.readFile(file, (err, data) => {
      if (err) { res.writeHead(404); res.end('404'); return; }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
      res.end(data);
    });
  });
  return new Promise((ok) => server.listen(port, () => ok(server)));
}
