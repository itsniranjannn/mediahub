"""Local media for the Online fixture (MEDIAHUB_FIXTURE_MEDIA), with HTTP Range support.

Serves <dir>/video.mp4 (a real video: Chromium decodes it like YouTube's and pauses it once
the app's window goes) and <dir>/audio.m4a (the stream the native hand-off plays).

    python tools/device/fixture_media_server.py <dir> [port=8765]
    adb reverse tcp:8765 tcp:8765        # the emulator's 127.0.0.1:8765 reaches this server

Make video.mp4 with `adb shell screenrecord` (H.264, video only) and audio.m4a as a long tone
(ExoPlayer sniffs the format, so MP3 data under that name is fine).
"""
import http.server
import os
import re
import sys


class Handler(http.server.SimpleHTTPRequestHandler):
    def send_head(self):
        path = self.translate_path(self.path.split('?')[0])
        if not os.path.isfile(path):
            self.send_error(404)
            return None
        size = os.path.getsize(path)
        ctype = 'video/mp4' if path.endswith('.mp4') else 'audio/mp4' if path.endswith('.m4a') else self.guess_type(path)
        f = open(path, 'rb')
        m = re.match(r'bytes=(\d*)-(\d*)', self.headers.get('Range', ''))
        if m:
            start = int(m.group(1) or 0)
            end = int(m.group(2)) if m.group(2) else size - 1
            end = min(end, size - 1)
            f.seek(start)
            self.send_response(206)
            self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
            self.send_header('Content-Length', str(end - start + 1))
            self._left = end - start + 1
        else:
            self.send_response(200)
            self.send_header('Content-Length', str(size))
            self._left = size
        self.send_header('Content-Type', ctype)
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        return f

    def copyfile(self, source, outputfile):
        left = self._left
        try:
            while left > 0:
                chunk = source.read(min(65536, left))
                if not chunk:
                    break
                outputfile.write(chunk)
                left -= len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, fmt, *args):
        sys.stderr.write('%s %s\n' % (self.log_date_time_string(), fmt % args))


if __name__ == '__main__':
    root = sys.argv[1] if len(sys.argv) > 1 else '.'
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8765
    os.chdir(root)
    http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()
