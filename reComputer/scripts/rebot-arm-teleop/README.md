# reBot Arm LeRobot Teleoperation

This example starts a reBot Arm B601 follower controlled by a reBot Arm 102 leader with one command. It supports JetPack 6.1, JetPack 6.2, and JetPack 7.2.

JetPack 6 and JetPack 7.2 use different prebuilt Docker images and host launch scripts. The entrypoint detects the installed JetPack version, downloads the matching image, loads it into Docker, configures the serial/CAN devices, and starts `lerobot-teleoperate`.

## Hardware

- reBot Arm B601 follower with RobStride motors
- reBot Arm 102 leader with FashionStar servos
- PEAK-System USB-to-CAN adapter
- CH340/CH341 USB serial adapter

## Prerequisites

- NVIDIA Jetson running JetPack 6.1, 6.2, or 7.2
- Docker and NVIDIA Container Toolkit
- Internet access for the first run
- At least 15 GB free space for JetPack 6 or 30 GB for JetPack 7.2

Connect and power the leader, follower, CAN adapter, and serial adapter before starting.

## Run

```bash
reComputer run rebot-arm-teleop
```

The first run downloads a resumable image archive to `~/.cache/jetson-examples/rebot-arm-teleop/`. The JetPack 6 archive is about 2.28 GB, and the JetPack 7.2 archive is about 7.71 GB.

If multiple CH340/CH341 serial devices are connected, select the leader explicitly:

```bash
LEADER_PORT=/dev/ttyUSB1 reComputer run rebot-arm-teleop
```

Useful overrides include `FOLLOWER_PORT`, `BITRATE`, `TELEOP_FPS`, `TELEOP_DURATION`, `TELEOP_DISPLAY`, and `TELEOP_EXTRA_ARGS`.

If automatic detection is unavailable, the variant can be selected explicitly:

```bash
reComputer run rebot-arm-teleop jp6
reComputer run rebot-arm-teleop jp72
```

Only use `jp72` on JetPack 7.2.

To verify version selection, image download/loading, and script dispatch without configuring hardware, set `REBOT_DRY_RUN=1`.

## Clean

```bash
reComputer clean rebot-arm-teleop
```

This removes both teleoperation images and the downloaded cache.

## Download behavior

The original SharePoint sharing URLs use `?e=...`, which opens an interactive page. This example replaces that query with `?download=1` and preserves the SharePoint authentication cookie across redirects. Both URLs were verified with ranged backend downloads returning gzip data.
