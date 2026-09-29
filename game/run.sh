#!/bin/sh
# Start the game.
#   BIKE_GAME_MODE=kiosk  run its own compositor (cage) straight on the screen,
#                         on a computer with no desktop. Sound goes to the first
#                         USB sound card; AUDIO_CARD=<number> picks another.
#                         EXIT_ACTION=poweroff makes the menu's Exit shut the
#                         computer down (kiosk-client.sh).
#   otherwise             a window in the desktop's Wayland session.
#   GAME_RENDERER=gl|vulkan   gl (the default) is the Compatibility renderer on
#                             OpenGL; vulkan is the Mobile renderer.
# Anything after the image name goes to the game, e.g. -- --demo=200.
set -eu

case "${GAME_RENDERER:-gl}" in
    gl) driver="--rendering-driver opengl3" ;;
    vulkan) driver="--rendering-method mobile --rendering-driver vulkan" ;;
    *) echo "GAME_RENDERER must be gl or vulkan" >&2; exit 1 ;;
esac

if [ "${BIKE_GAME_MODE:-window}" = kiosk ]; then
    card="${AUDIO_CARD:-}"
    cards="${ASOUND_CARDS:-/proc/asound/cards}"  # overridable for tests
    if [ -z "$card" ] && [ -r "$cards" ]; then
        card=$(awk '/USB-Audio/ && $1 ~ /^[0-9]+$/ { print $1; exit }' "$cards")
    fi
    if [ -n "$card" ]; then
        printf 'defaults.pcm.card %s\ndefaults.ctl.card %s\n' "$card" "$card" > /etc/asound.conf
        echo "bike-game: sound on card $card"
    else
        echo "bike-game: no USB sound card found, using the default"
    fi
    export XDG_RUNTIME_DIR=/run/bike-game
    mkdir -p -m 700 "$XDG_RUNTIME_DIR"
    # No logind or seatd in the container: open the screen and keyboard
    # directly, and start even before a keyboard is plugged in.
    export LIBSEAT_BACKEND="${LIBSEAT_BACKEND:-noop}"
    export WLR_LIBINPUT_NO_DEVICES=1
    # shellcheck disable=SC2086  # $driver is several words on purpose
    # The client script sets each screen's fastest refresh rate, then runs godot.
    exec cage -d -- bike-game-kiosk-client --path /game --display-driver wayland \
        --audio-driver ALSA $driver "$@"
fi

# shellcheck disable=SC2086
exec godot --path /game --display-driver wayland $driver "$@"
