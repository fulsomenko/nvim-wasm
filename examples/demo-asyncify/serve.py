#!/usr/bin/env python3
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
import pathlib
import functools

if __name__ == "__main__":
    root = pathlib.Path(__file__).parent
    print(f"Serving {root} on http://localhost:8765 (no COOP/COEP required)")
    handler = functools.partial(SimpleHTTPRequestHandler, directory=str(root))
    server = ThreadingHTTPServer(("", 8765), handler)
    server.serve_forever()
