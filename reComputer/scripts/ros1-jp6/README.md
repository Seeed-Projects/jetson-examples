# Jetson-Example: Run ROS 1 Noetic on NVIDIA Jetson

This example downloads a prebuilt ROS 1 Noetic Docker archive from a public OneDrive/SharePoint link, loads it into Docker as:

```sh
ros:noetic
```

Archive size: about **1.27 GB**

Supported JetPack/L4T versions:
- JetPack 6.2 -> L4T 36.4.0
- JetPack 6.2.1 -> L4T 36.4.3
- JetPack 6.1 -> L4T 36.4.4

## Getting Started

PyPI (recommended):

```sh
pip install jetson-examples
```

GitHub (developer):

```sh
git clone https://github.com/Seeed-Projects/jetson-examples
cd jetson-examples
pip install .
```

## Usage

Launch an interactive shell in the container:

```sh
reComputer run ros1-jp6
```

The example will:

1. Download the Docker archive from SharePoint if it is not cached
2. Run `docker load -i` to import the image
3. Start the container with Jetson-friendly Docker flags

The SharePoint share link is a normal `:u:/...` public link. The downloader automatically appends `download=1`, so you do not need to manually rewrite the URL.

Cache location:

```sh
~/.cache/jetson-examples/ros1-jp6/ros-noetic-jp6.tar
```

## Verify The Image

Only prepare the image and skip container startup:

```sh
ROS1_JP6_SKIP_RUN=1 reComputer run ros1-jp6
```

Run a non-interactive ROS smoke test:

```sh
ROS1_JP6_COMMAND='source /opt/ros/noetic/setup.bash && rosversion -d' reComputer run ros1-jp6
```

## Export With docker save

After the image is loaded locally, save it back to a tar archive:

```sh
ROS1_JP6_SKIP_RUN=1 \
ROS1_JP6_SAVE_PATH=/tmp/ros-noetic-jp6.tar \
reComputer run ros1-jp6
```

This is equivalent to:

```sh
docker save -o /tmp/ros-noetic-jp6.tar ros:noetic
```

## Environment Variables

You can override the default behavior with these variables:

```sh
ROS1_JP6_SHARE_URL
ROS1_JP6_ARCHIVE_NAME
ROS1_JP6_CACHE_DIR
ROS1_JP6_IMAGE
ROS1_JP6_CONTAINER_NAME
ROS1_JP6_COMMAND
ROS1_JP6_SKIP_RUN
ROS1_JP6_SAVE_PATH
```

## Cleanup

Only remove the container:

```sh
reComputer clean ros1-jp6
```

The local image cache and the downloaded archive are kept.
