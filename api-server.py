#!/usr/bin/env python3
"""
Simple REST API for controlling Zoom recorder
"""

import http.server
import socketserver
import json
import os
import subprocess
import signal
from urllib.parse import parse_qs, urlparse

PORT = 8080
RECORDING_DIR = "/recordings"
recording_process = None

class ZoomRecorderHandler(http.server.BaseHTTPRequestHandler):
    
    def send_json(self, status, data):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())
    
    def do_GET(self):
        global recording_process
        
        parsed = urlparse(self.path)
        
        if parsed.path == '/status':
            self.send_json(200, {
                'recording': recording_process is not None and recording_process.poll() is None,
                'pid': recording_process.pid if recording_process else None
            })
        elif parsed.path == '/recordings':
            # List recordings
            try:
                files = os.listdir(RECORDING_DIR)
                self.send_json(200, {'recordings': files})
            except Exception as e:
                self.send_json(500, {'error': str(e)})
        else:
            self.send_json(404, {'error': 'Not found'})
    
    def do_POST(self):
        global recording_process
        
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        data = json.loads(body) if body else {}
        
        parsed = urlparse(self.path)
        
        if parsed.path == '/start-recording':
            if recording_process and recording_process.poll() is None:
                self.send_json(400, {'error': 'Already recording'})
                return
            
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            output = f"{RECORDING_DIR}/meeting_{timestamp}.mp4"
            
            cmd = [
                'ffmpeg', '-f', 'x11grab',
                '-framerate', '30',
                '-video_size', '1920x1080',
                '-i', ':99',
                '-c:v', 'libx264',
                '-preset', 'fast',
                '-crf', '23',
                '-pix_fmt', 'yuv420p',
                output
            ]
            
            recording_process = subprocess.Popen(cmd)
            self.send_json(200, {'status': 'recording', 'output': output, 'pid': recording_process.pid})
            
        elif parsed.path == '/stop-recording':
            if not recording_process or recording_process.poll() is not None:
                self.send_json(400, {'error': 'Not recording'})
                return
            
            recording_process.send_signal(signal.SIGINT)
            recording_process.wait()
            recording_process = None
            self.send_json(200, {'status': 'stopped'})
            
        elif parsed.path == '/join':
            meeting_url = data.get('meeting_url')
            password = data.get('password', '')
            
            # This would launch Zoom with the meeting URL
            # For now, just acknowledge
            self.send_json(200, {
                'status': 'launching_zoom',
                'meeting_url': meeting_url,
                'note': 'Zoom must be installed in container'
            })
            
        else:
            self.send_json(404, {'error': 'Not found'})
    
    def log_message(self, format, *args):
        print(f"[API] {format % args}")

if __name__ == '__main__':
    import datetime
    
    print(f"Starting Zoom Recorder API on port {PORT}...")
    with socketserver.TCPServer(("", PORT), ZoomRecorderHandler) as httpd:
        httpd.serve_forever()