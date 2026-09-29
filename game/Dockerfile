# The game: Godot, the project, its sounds, and a kiosk compositor (cage), so
# a computer with no desktop can run it straight on the screen. x86-64 only.

FROM python:3.13-slim AS sounds
COPY tools/make_sounds.py /make_sounds.py
RUN python /make_sounds.py /sounds

FROM debian:trixie-slim

# Godot loads these at run time: GL/Vulkan through Mesa, Wayland or X11 for
# the window, fontconfig, and ALSA or PulseAudio for sound. xvfb gives a
# virtual screen for screenshots.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip \
        libgl1 libegl1 libgles2 libgl1-mesa-dri libgbm1 libvulkan1 mesa-vulkan-drivers \
        libwayland-client0 libwayland-cursor0 libwayland-egl1 libxkbcommon0 \
        libx11-6 libxcursor1 libxext6 libxi6 libxinerama1 libxrandr2 libxrender1 \
        libfontconfig1 libasound2t64 libpulse0 libdbus-1-3 \
        cage wlr-randr xvfb xauth dbus-bin \
    && rm -rf /var/lib/apt/lists/*

# The engine binary, checked against Godot's published SHA-512 sums. It runs
# the project folder directly, so no export templates are needed.
ARG GODOT_VERSION=4.7.2
RUN set -eu; \
    [ "$(uname -m)" = x86_64 ] || { echo "x86-64 only, not $(uname -m)"; exit 1; }; \
    arch=x86_64; \
    zip="Godot_v${GODOT_VERSION}-stable_linux.${arch}.zip"; \
    base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"; \
    cd /tmp; \
    curl -fsSLO "$base/$zip"; \
    curl -fsSL "$base/SHA512-SUMS.txt" | grep " $zip\$" | sha512sum -c -; \
    unzip -q "$zip"; \
    install -m 755 "Godot_v${GODOT_VERSION}-stable_linux.${arch}" /usr/local/bin/godot; \
    rm -f /tmp/Godot_v*

# The island's land, worked out once (tools/bake_island.gd, a few seconds).
# Only the island's own files come in first, so this is redone only when the
# island changes. A script that fails to load would leave godot waiting
# forever, hence the timeout and the check that the file was written.
COPY game/project.godot /bake/project.godot
COPY game/scripts/island.gd /bake/scripts/island.gd
COPY game/tools/bake_island.gd /bake/tools/bake_island.gd
RUN set -eu; mkdir -m 1777 -p /tmp/home; export HOME=/tmp/home; \
    timeout 120 godot --headless --path /bake --import > /tmp/bake-import.log 2>&1 || true; \
    timeout 300 godot --headless --path /bake --script res://tools/bake_island.gd -- /bake/island.bin; \
    test -s /bake/island.bin

COPY game/ /game/
COPY --from=sounds /sounds/ /game/sounds/
RUN mkdir -p /game/world && cp /bake/island.bin /game/world/island.bin

# Import, then the tests, then a few seconds of each kind of ride with the
# demo rider: any script error stops the build.
ENV HOME=/tmp/home
RUN set -eu; mkdir -p -m 1777 /tmp/home /data; \
    export XDG_DATA_HOME=/tmp/build-data; \
    godot --headless --path /game --import > /tmp/import.log 2>&1 || true; \
    if grep -E "SCRIPT ERROR|Parse Error" /tmp/import.log; then exit 1; fi; \
    timeout 600 godot --headless --path /game --script res://tests/run.gd; \
    for ride in route:summit-climb workout:pyramid free:free-rolling; do \
        godot --headless --path /game -- --demo=200 --ride=$ride --quit-after=4 > /tmp/smoke.log 2>&1; \
        if grep -E "SCRIPT ERROR" /tmp/smoke.log; then exit 1; fi; \
    done; \
    # The menu's Exit (the last of six buttons, with no ride saved yet): status
    # 10 in kiosk mode, so the kiosk wrapper knows it was the button, and 0 on
    # a desktop.
    for mode in kiosk:10 window:0; do \
        s=0; XDG_DATA_HOME=/tmp/exit-${mode%:*} BIKE_GAME_MODE=${mode%:*} godot --headless --path /game -- \
            --keys=down,down,down,down,down,enter --quit-after=20 > /tmp/exit.log 2>&1 || s=$?; \
        [ "$s" = "${mode#*:}" ] || { echo "Exit in ${mode%:*} mode: status $s"; cat /tmp/exit.log; exit 1; }; \
    done; \
    # Walking away from a ride (no bike, so no pedalling) saves it.
    XDG_DATA_HOME=/tmp/walk godot --headless --path /game -- --ride=route:city-sprint \
        --elapsed=120 --walk-away=2 --sleep-after=2 --quit-after=8 > /tmp/walk.log 2>&1; \
    grep -q '"id": "city-sprint"' /tmp/walk/bike-game/riders/1/rides/index.json \
        || { echo "walking away didn't save the ride"; cat /tmp/walk.log; exit 1; }; \
    rm -rf /tmp/build-data /tmp/exit-* /tmp/walk

# Rides and settings live in /data/bike-game.
ENV XDG_DATA_HOME=/data
COPY game/run.sh /usr/local/bin/bike-game
COPY game/kiosk-client.sh /usr/local/bin/bike-game-kiosk-client
RUN sh /game/tests/kiosk_client_test.sh /usr/local/bin/bike-game-kiosk-client
ENTRYPOINT ["bike-game"]
