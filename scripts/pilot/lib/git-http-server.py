#!/usr/bin/env python3
"""Minimal smart-HTTP Git server for the local pilot.

ArgoCD's repo-server uses go-git, which does NOT support the dumb HTTP protocol,
so a static file server is not enough. This gateway delegates every request to
`git http-backend` (the standard smart-HTTP CGI that ships with Git), giving a
fully local, dependency-free source that ArgoCD can clone and reconcile.

Usage: git-http-server.py <project-root> <port>
"""
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROJECT_ROOT = os.path.abspath(sys.argv[1])
PORT = int(sys.argv[2])
GIT_BACKEND = os.path.join(
    subprocess.check_output(["git", "--exec-path"]).decode().strip(),
    "git-http-backend",
)


class Handler(BaseHTTPRequestHandler):
    def _run(self):
        path = self.path
        query = ""
        if "?" in path:
            path, query = path.split("?", 1)

        env = dict(os.environ)
        env.update(
            GIT_PROJECT_ROOT=PROJECT_ROOT,
            GIT_HTTP_EXPORT_ALL="1",
            PATH_INFO=path,
            QUERY_STRING=query,
            REQUEST_METHOD=self.command,
            CONTENT_TYPE=self.headers.get("Content-Type", ""),
            REMOTE_USER="",
            REMOTE_ADDR=self.client_address[0],
        )
        length = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(length) if length else b""

        proc = subprocess.run(
            [GIT_BACKEND], input=body, env=env, capture_output=True
        )
        if proc.returncode != 0:
            self.send_error(500, "git-http-backend failed")
            sys.stderr.write(proc.stderr.decode(errors="replace"))
            return

        out = proc.stdout
        sep = b"\r\n\r\n" if b"\r\n\r\n" in out else b"\n\n"
        raw_headers, _, response_body = out.partition(sep)

        status = 200
        headers = []
        for line in raw_headers.replace(b"\r\n", b"\n").split(b"\n"):
            if not line:
                continue
            key, _, value = line.partition(b":")
            key = key.decode().strip()
            value = value.decode().strip()
            if key.lower() == "status":
                status = int(value.split()[0])
            else:
                headers.append((key, value))

        self.send_response(status)
        for key, value in headers:
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(response_body)))
        self.end_headers()
        self.wfile.write(response_body)

    do_GET = _run
    do_POST = _run

    def log_message(self, *args):  # keep the pilot output quiet
        pass


ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
