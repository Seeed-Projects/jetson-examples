FROM ultralytics/ultralytics:latest-jetson

WORKDIR /usr/src/ultralytics
COPY . /usr/src/ultralytics

RUN pip install --no-cache-dir flask

CMD ["python3", "app.py"]

