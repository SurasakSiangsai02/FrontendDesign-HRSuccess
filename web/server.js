// Web server (no dependencies): static pages + /api proxy to the local API. Run: node --env-file=../.env server.js
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const { WEB_PORT, API_PORT } = process.env;
const ROOT = path.join(__dirname, 'public');
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml' };
const PAGES = { '/': 'index.html', '/dashboard': 'dashboard.html' };

http.createServer((req, res) => {
  const name = new URL(req.url, 'http://x').pathname;

  if (name.startsWith('/api/')) {
    const headers = { ...req.headers, 'x-forwarded-for': req.socket.remoteAddress };
    const up = http.request({ host: '127.0.0.1', port: API_PORT, path: req.url, method: req.method, headers }, (r) => {
      res.writeHead(r.statusCode, r.headers); r.pipe(res);
    });
    up.on('error', () => { res.writeHead(502, { 'Content-Type': 'application/json' }).end('{"error":"API ไม่ทำงาน"}'); });
    return req.pipe(up);
  }

  const file = path.join(ROOT, PAGES[name] || decodeURIComponent(name));
  if (!file.startsWith(ROOT + path.sep)) return res.writeHead(403).end();
  fs.readFile(file, (err, data) => {
    if (err) return res.writeHead(404).end('not found');
    const type = TYPES[path.extname(file)] || 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': type.startsWith('text') ? `${type}; charset=utf-8` : type }).end(data);
  });
}).listen(WEB_PORT, () => console.log(`Web http://localhost:${WEB_PORT}`));
