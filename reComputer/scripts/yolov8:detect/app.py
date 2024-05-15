from flask import Flask, render_template, Response
import cv2 as cv
from ultralytics import YOLO
import numpy


class JetsonExampleYoloV8:

    def __init__(self):
        self.app = Flask(__name__)
        self.cap = cv.VideoCapture(0)
        assert self.cap.isOpened(), "Error reading video file"
        
        print("prepare yolo model")
        self.model = YOLO("/usr/src/ultralytics/yolov8n.pt")
        print("done")
        self.setup_routes()

    def setup_routes(self):
        @self.app.route('/')
        def index():
            return render_template("index.html")
        
        @self.app.route('/video-feed')
        def video_feed():
            return Response(self.gen_frames(),mimetype='multipart/x-mixed-replace; boundary=frame')

    def gen_frames(self):
        while True:
            ret0, frame= self.cap.read()
            
            if not ret0:break

            results = self.model.predict(frame, show=False)
            annotated_frame = results[0].plot()

            ret1, buffer = cv.imencode('.jpg',annotated_frame)
            frame = buffer.tobytes()
            yield  (b'--frame\r\n' b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')

    def run(self):
        self.app.run()


if __name__=='__main__':
    yolo = JetsonExampleYoloV8()
    yolo.run()
