import http from 'node:http';
const server = http.createServer((req, res) => {
  setTimeout(() => {
    res.writeHead(200, { 'content-type': 'text/plain' });
    res.end(`ok ${req.url}`);
  }, 300);
});
server.listen(3000, '127.0.0.1', () => console.log('mock listening on 3000'));
