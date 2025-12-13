from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import json

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)
        query = {k: v[0] if len(v) == 1 else v for k, v in query.items()}

        if path == '/':
            self.respond(200, 'Hello from Python!')
        elif path == '/something':
            result = {'route': path, 'query': query}
            if query.get('json') == 'true':
                self.respond(200, json.dumps(result), 'application/json')
            else:
                self.respond(200, f"Route: {path}, Query: {query}")
        else:
            self.respond(404, 'Not Found')

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path == '/something':
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode()
            result = {'route': parsed.path, 'body': json.loads(body) if body else {}}
            self.respond(200, json.dumps(result), 'application/json')
        else:
            self.respond(404, 'Not Found')

    def respond(self, code, body, content_type='text/plain'):
        self.send_response(code)
        self.send_header('Content-Type', content_type)
        self.end_headers()
        self.wfile.write(body.encode())

HTTPServer(('', 3001), Handler).serve_forever()

