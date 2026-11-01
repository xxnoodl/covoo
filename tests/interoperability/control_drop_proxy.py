"""Loopback-only test proxy: close one TLS connection after a capture trigger."""
import argparse
from pathlib import Path
import select
import socket
import socketserver
import threading
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target-port', type=int, required=True)
    parser.add_argument('--port-file', type=Path, required=True)
    parser.add_argument('--trigger', type=Path, required=True)
    args = parser.parse_args()
    dropped = threading.Event()

    class Forwarder(socketserver.BaseRequestHandler):
        def handle(self):
            with socket.create_connection(('127.0.0.1', args.target_port), timeout=5) as remote:
                remote.settimeout(5)
                triggered_at = None
                while True:
                    if not dropped.is_set() and args.trigger.exists():
                        if triggered_at is None:
                            triggered_at = time.monotonic()
                        if time.monotonic() - triggered_at >= 0.25:
                            dropped.set()
                            return
                    readable, _, _ = select.select([self.request, remote], [], [], 0.02)
                    for source in readable:
                        try:
                            data = source.recv(65536)
                            if not data:
                                return
                            (remote if source is self.request else self.request).sendall(data)
                        except OSError:
                            return

    class Server(socketserver.ThreadingTCPServer):
        daemon_threads = True

    with Server(('127.0.0.1', 0), Forwarder) as server:
        args.port_file.write_text(str(server.server_address[1]), encoding='ascii')
        server.serve_forever()


if __name__ == '__main__':
    main()
