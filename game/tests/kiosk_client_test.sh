#!/bin/sh
# Tests for kiosk-client.sh's Exit handling, with stand-ins for godot,
# dbus-send, sleep and wlr-randr: only the Exit button's status (10) with
# EXIT_ACTION=poweroff may ask logind to power off.
#
#   sh game/tests/kiosk_client_test.sh [path to kiosk-client.sh]
set -u
client=${1:-$(dirname "$0")/../kiosk-client.sh}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
log=$tmp/calls
fake() { printf '#!/bin/sh\n%s\n' "$2" > "$tmp/bin/$1"; chmod +x "$tmp/bin/$1"; }
fake godot 'exit "$FAKE_GODOT"'
fake dbus-send "echo \"dbus-send \$*\" >> $log; exit \"\$FAKE_DBUS\""
fake sleep "echo \"sleep \$*\" >> $log"
fake wlr-randr 'exit 0'

failed=0
# run <godot status> <EXIT_ACTION> <dbus-send status> <want status> <want calls> <what>
run() {
    : > "$log"
    PATH="$tmp/bin:$PATH" FAKE_GODOT=$1 EXIT_ACTION=$2 FAKE_DBUS=$3 \
        sh "$client" --path /game > /dev/null 2>&1
    got=$?
    calls=$(tr '\n' ';' < "$log")
    if [ "$got" = "$4" ] && [ "$calls" = "$5" ]; then
        echo "ok    $6"
    else
        echo "FAIL  $6: status $got (want $4), calls '$calls' (want '$5')"
        failed=1
    fi
}

off="dbus-send --system --print-reply --reply-timeout=15000 --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.PowerOff boolean:false;sleep infinity;"
run 10 poweroff 0 0 "$off" "Exit powers off, then holds the screen"
run 10 quit 0 10 "" "Exit without poweroff just ends the game"
run 10 "" 0 10 "" "EXIT_ACTION unset: no poweroff"
run 0 poweroff 0 0 "" "Ctrl+Q (status 0) never powers off"
run 143 poweroff 0 143 "" "Docker stopping the game never powers off"
run 1 poweroff 0 1 "" "a crash never powers off"
run 10 poweroff 1 10 "dbus-send --system --print-reply --reply-timeout=15000 --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.PowerOff boolean:false;" \
    "poweroff refused: the game ends, so Docker brings it back"
exit "$failed"
