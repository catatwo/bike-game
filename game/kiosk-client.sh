#!/bin/sh
# Runs inside cage, as its one client: put each screen on its fastest refresh
# rate at its native resolution, then run the game with the arguments given.
# Monitors advertise native@60 Hz as "preferred" even when they do 144 Hz, and
# cage takes the preferred mode. GAME_MODE=1920x1080@120 forces a mode.
#
# EXIT_ACTION=poweroff: the menu's Exit button (exit status 10, EXIT_STATUS in
# main.gd) shuts the computer down, through the host's logind on the system
# D-Bus (the socket must be mounted). Anything else, a crash, Ctrl+Q or Docker
# stopping the game, never powers off: the game just ends, and Docker starts
# it again.
set -u
EXIT_STATUS=10

best_modes() {
    # From wlr-randr's listing: "<output> <resolution> <fastest Hz at it>".
    awk '
        /^[^ ]/ { out = $1; next }
        / px, .* Hz/ {
            res = $1; hz = $3 + 0
            if ($0 ~ /preferred/) pref[out] = res
            if (hz > best[out, res]) { best[out, res] = hz; text[out, res] = $3 }
        }
        END { for (o in pref) print o, pref[o], text[o, pref[o]] }'
}

if command -v wlr-randr >/dev/null 2>&1; then
    if [ -n "${GAME_MODE:-}" ]; then
        for out in $(wlr-randr | awk '/^[^ ]/ {print $1}'); do
            wlr-randr --output "$out" --mode "$GAME_MODE" \
                && echo "bike-game: $out at $GAME_MODE"
        done
    else
        wlr-randr | best_modes | while read -r out res hz; do
            wlr-randr --output "$out" --mode "${res}@${hz}Hz" \
                && echo "bike-game: $out at $res, $hz Hz"
        done
    fi
fi
godot "$@"
status=$?
if [ "$status" = "$EXIT_STATUS" ] && [ "${EXIT_ACTION:-quit}" = poweroff ]; then
    echo "bike-game: Exit: powering the computer off"
    if dbus-send --system --print-reply --reply-timeout=15000 \
        --dest=org.freedesktop.login1 /org/freedesktop/login1 \
        org.freedesktop.login1.Manager.PowerOff boolean:false >/dev/null; then
        # Keep the screen black until the power goes. Ending here would let
        # Docker start the game again while the computer shuts down.
        exec sleep infinity
    fi
    echo "bike-game: couldn't power off (is /run/dbus/system_bus_socket mounted?)" >&2
fi
exit "$status"
