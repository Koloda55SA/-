// Локальная страница выгрузки данных из Firebase (см. README.md).
// Запуск: node migration/server.mjs <папка для выгрузки>
// Открыть: http://localhost:8766 — войти администратором и нажать «Выгрузить».
// Сервер слушает только этот компьютер (127.0.0.1) и сохраняет присланные
// страницей части выгрузки в указанную папку.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(process.argv[2] || path.join(here, 'out'));
const PORT = Number(process.env.PORT || 8766);
const page = path.join(here, 'export.html');
const allowedOrigins = [`http://localhost:${PORT}`, `http://127.0.0.1:${PORT}`];

fs.mkdirSync(outDir, { recursive: true });

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');

  if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/export.html')) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    fs.createReadStream(page).pipe(res);
    return;
  }

  if (req.method === 'POST' && url.pathname === '/save') {
    // Принимаем только со своей страницы.
    if (!allowedOrigins.includes(req.headers.origin || '')) {
      res.writeHead(403);
      res.end();
      return;
    }
    const name = url.searchParams.get('name') || '';
    if (!/^[a-z][a-z0-9-]{0,40}$/.test(name)) {
      res.writeHead(400);
      res.end();
      return;
    }
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => {
      const body = Buffer.concat(chunks);
      fs.writeFileSync(path.join(outDir, name + '.json'), body);
      console.log(`сохранено: ${name}.json (${Math.round(body.length / 1024)} КБ)`);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end('{"ok":true}');
    });
    return;
  }

  res.writeHead(404);
  res.end();
}).listen(PORT, '127.0.0.1', () => {
  console.log(`Страница выгрузки: http://localhost:${PORT}`);
  console.log(`Папка выгрузки:    ${outDir}`);
});
