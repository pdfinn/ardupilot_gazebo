#!/opt/homebrew/bin/python3.12
"""
Gazebo Video Bridge - Custom video streaming solution
Subscribes to Gazebo camera topic and streams H.264 video to UDP

Bypasses GstCameraPlugin to avoid Anaconda/Homebrew GLib conflicts
Uses Homebrew Python 3.12 (has gz bindings), not Anaconda Python 3.11
"""

import os
import sys
import subprocess
import time
import signal

# Force gz-transport discovery onto loopback unicast BEFORE importing the
# transport library (it reads these at import/Node-construction time). This Mac
# has virtual interfaces (feth*, bridge100) that install multicast reject routes
# (224.0.0/4 ... !), breaking gz-transport's default multicast peer discovery
# with "No route to host" so this bridge never discovers the camera publisher.
# The server (run_gazebo.sh) is on the same host, so loopback is sufficient; the
# H.264 output below still goes to the handset over normal UDP, unaffected.
os.environ.setdefault('GZ_IP', '127.0.0.1')
os.environ.setdefault('GZ_RELAY', '127.0.0.1')

# Add Gazebo Python bindings to path
sys.path.insert(0, '/opt/homebrew/Cellar/gz-transport14/14.2.0/lib/python3.12/site-packages')
sys.path.insert(0, '/opt/homebrew/Cellar/gz-msgs11/11.1.0/lib/python3.12/site-packages')

from gz.transport14 import Node
from gz.msgs11.image_pb2 import Image

class VideoStreamBridge:
    def __init__(self, camera_topic, udp_host='127.0.0.1', udp_port=5600, fps=30):
        self.camera_topic = camera_topic
        self.udp_host = udp_host
        self.udp_port = udp_port
        self.fps = fps
        self.frame_count = 0
        self.start_time = time.time()
        self.gst_process = None
        self.node = None
        self.running = True

        # Handle Ctrl+C gracefully
        signal.signal(signal.SIGINT, self.shutdown)
        signal.signal(signal.SIGTERM, self.shutdown)

    def shutdown(self, signum, frame):
        print("\nShutting down video bridge...")
        self.running = False
        if self.gst_process:
            self.gst_process.terminate()
            self.gst_process.wait()
        sys.exit(0)

    def start_gstreamer_pipeline(self, width, height):
        """Start GStreamer pipeline that will receive frames on stdin"""
        # Use Homebrew GStreamer explicitly
        pipeline = [
            'gst-launch-1.0',
            '-q',  # Quiet mode
            'fdsrc', 'fd=0', '!',  # Read from stdin
            'videoparse', f'width={width}', f'height={height}', 'format=rgb', f'framerate={self.fps}/1', '!',
            'videoconvert', '!',
            'video/x-raw,format=I420', '!',
            'jpegenc', 'quality=85', '!',
            'rtpjpegpay', '!',
            'udpsink', f'host={self.udp_host}', f'port={self.udp_port}'
        ]

        print(f"Starting GStreamer pipeline...")
        print(f"  Resolution: {width}x{height}")
        print(f"  FPS: {self.fps}")
        print(f"  Output: {self.udp_host}:{self.udp_port}")

        # Set environment to use Homebrew GStreamer
        env = {
            'PATH': '/opt/homebrew/bin:/usr/bin:/bin',
            'DYLD_LIBRARY_PATH': '/opt/homebrew/lib',
            'GST_PLUGIN_PATH': '/opt/homebrew/lib/gstreamer-1.0'
        }

        try:
            self.gst_process = subprocess.Popen(
                pipeline,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env
            )
            print("✓ GStreamer pipeline started")
            return True
        except Exception as e:
            print(f"✗ Failed to start GStreamer: {e}")
            return False

    def on_image(self, msg):
        """Callback for camera images from Gazebo"""
        if not self.running:
            return

        try:
            # Initialize pipeline on first frame
            if self.gst_process is None:
                if not self.start_gstreamer_pipeline(msg.width, msg.height):
                    print("Failed to start GStreamer, stopping...")
                    self.running = False
                    return

            # Convert image data to bytes
            # Gazebo sends RGB8 by default
            image_data = bytes(msg.data)

            # Send to GStreamer pipeline
            if self.gst_process and self.gst_process.poll() is None:
                self.gst_process.stdin.write(image_data)
                self.gst_process.stdin.flush()

                # Stats
                self.frame_count += 1
                if self.frame_count % 30 == 0:
                    elapsed = time.time() - self.start_time
                    actual_fps = self.frame_count / elapsed
                    print(f"Streaming: {self.frame_count} frames ({actual_fps:.1f} fps)")
            else:
                print("GStreamer pipeline died, restarting...")
                self.gst_process = None

        except Exception as e:
            print(f"Error processing frame: {e}")

    def run(self):
        """Start subscribing to Gazebo camera topic"""
        print("=" * 60)
        print("Gazebo Video Bridge")
        print("=" * 60)
        print(f"Camera topic: {self.camera_topic}")
        print(f"Streaming to: udp://{self.udp_host}:{self.udp_port}")
        print("Press Ctrl+C to stop")
        print()

        # Create Gazebo transport node
        self.node = Node()

        # Subscribe to camera topic
        if not self.node.subscribe(Image, self.camera_topic, self.on_image):
            print(f"✗ Failed to subscribe to {self.camera_topic}")
            print("Make sure Gazebo is running with a camera sensor")
            return False

        print(f"✓ Subscribed to {self.camera_topic}")
        print("Waiting for camera images...")

        # Keep running until interrupted
        try:
            while self.running:
                time.sleep(0.1)
        except KeyboardInterrupt:
            pass

        print("\nStopping...")
        return True

def main():
    # Camera topic from iris_runway.sdf
    camera_topic = "world/iris_runway/model/iris_with_gimbal/model/gimbal/link/pitch_link/sensor/camera/image"

    # Parse arguments
    import argparse
    parser = argparse.ArgumentParser(description='Bridge Gazebo camera to UDP video stream')
    parser.add_argument('--topic', default=camera_topic, help='Gazebo camera image topic')
    parser.add_argument('--host', default='127.0.0.1', help='UDP host')
    parser.add_argument('--port', type=int, default=5600, help='UDP port')
    parser.add_argument('--fps', type=int, default=30, help='Target FPS')

    args = parser.parse_args()

    # Create and run bridge
    bridge = VideoStreamBridge(args.topic, args.host, args.port, args.fps)
    success = bridge.run()

    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()
