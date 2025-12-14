const http = require('http');
const url = require('url');

const server = http.createServer((req, res) => {
  const parsed = url.parse(req.url, true);
  const path = parsed.pathname;
  const query = parsed.query;

  if (req.method === 'GET' && path === '/') {
    res.end('Hello from JavaScript!');
  }
  else if (req.method === 'GET' && path === '/something') {
    const result = { route: path, query };
    if (query.json === 'true') {
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify(result));
    } else {
      res.end(`Route: ${path}, Query: ${JSON.stringify(query)}`);
    }
  }
  else if (req.method === 'POST' && path === '/something') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ route: path, body: JSON.parse(body || '{}') }));
    });
  }
  else {
    res.statusCode = 404;
    res.end('Not Found');
  }
});

server.listen(3000, () => console.log('JS server running on :3000'));

