import http from 'node:http';
// 応答までの遅延（ms）。① は 0（遅延なし）、② と ③ は 300 で動かす
const delay = Number(process.env.DELAY_MS ?? 300);
const server = http.createServer((req, res) => {
  setTimeout(() => {
    res.writeHead(200, { 'content-type': 'text/plain' });
    res.end(`ok ${req.url}`);
  }, delay);
});
server.listen(3000, '127.0.0.1', () => console.log(`mock listening on 3000 (delay ${delay}ms)`));
