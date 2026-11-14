import { createServer } from 'node:http';

const port = Number(process.env.PORT ?? 3000);

createServer((_req, res) => {
  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ notes: [] }));
}).listen(port);
