# CLAUDE.md

A cycling game for Bluetooth (FTMS) indoor bikes, first built on 2026-09-28
for a Decathlon Domyos Challenge Bike (2023). README.md has the overview, the
keys, how to run it and troubleshooting. This file is what a future session
needs to not break it.

## Public repo

Published at https://github.com/catatwo/bike-game under the MIT licence
(2026-09-29). Everything committed is public: no names, emails, addresses,
host names or machine details, in files or in commit messages. Commits go
under the `catatwo` GitHub no-reply address (set in this clone's git
config). The history was started afresh when it went public.

## Goals that must stay true

- **Turn on the bike and the screen, and ride.** No phone apps, no fiddling.
  So: the bridge reconnects to the bike by itself; in kiosk mode the computer
  boots into the game; pedalling in the menu starts a free ride (a setting);
  the screen sleeps when nobody rides and wakes when someone pedals.
- 🔴 **"Nobody's riding" means no pedalling and no keys, never "the bike is
  off".** A bike on mains power stays connected for hours, so the old
  connection-based sleep never fired on the maintainer's bike. Mid-ride, stopped
  for `WALK_AWAY` (5 min, paused or not) finishes and saves the ride (or
  drops one under a minute), shows the summary, and the summary sleeps after
  `SLEEP_AFTER`; waking from it goes to the menu. The build tests both with
  `--walk-away` / `--sleep-after`.
- **Keyboard only, no mouse.** Every screen works with arrows, Enter, Esc
  and Left/Right. The cursor is hidden and buttons ignore the mouse.
- **Sound**, through the first USB sound card in kiosk mode.
- **A range of routes and workouts**, beginner 10 minutes up to an hour, plus
  free ride. Cartoon/Tron style; graphics were never meant to be realistic.
- **Runs in Docker.** Keep the world cheap to draw: unshaded materials, few
  draw calls, chunked road.
- 🔴 **Linux only, by the maintainer's decision (2026-09-29).** No Android, iPad,
  Windows or macOS builds, and no F-Droid: an Android build and an iPad
  build were looked into and both dropped. Don't propose ports.
- 🔴 **Generic, so it can be published.** Nothing about one particular
  machine, network or person goes in this repo: no addresses, host names,
  Wi-Fi names, user names or disk images. A machine's own setup (how it's
  installed, deployed, what it's called) lives with that machine's config,
  outside this repo.

## Not built yet

`TODO.md` holds computer riders (bots) and achievements, with how they'd
work. The maintainer put both off (2026-09-29); achievements are meant to be the
very last thing built. Day and night was ruled out.

## The bike

Bluetooth FTMS: Indoor Bike Data, and the Control Point with simulation
(gradient) and target power (ERG). Tested only with the Domyos Challenge Bike
(2023), whose power is estimated from resistance, so it's approximate. Only
one app can hold a bike's Bluetooth connection at a time, so a phone app, or
another computer running this bridge, keeps the bridge from finding it.

## Rules and traps

- 🔴 **`xvfb-run` in a container needs `docker run --init`.** Without it,
  `xvfb-run` is PID 1, never gets Xvfb's ready signal, and hangs forever
  with no output (lost 10 minutes on 2026-09-28).
- 🔴 **Timers about the person run on real time; timers about the ride run
  on game time.** `--time-scale` speeds up rides for tests. The key-idle,
  pedal-to-start and sleep timers once used game time, so at 40x a free ride
  auto-started before the scripted keys arrived. `main.gd` divides by
  `Engine.time_scale` for those.
- 🔴 **Ride samples are interpolated to whole seconds** (`ride.gd`), because
  ghosts depend on them. Taking "the distance now" for every
  second a long frame skipped put the ghost up to a frame's distance ahead.
  `test_samples_are_exact_even_with_long_frames` fails on the old code.
- 🔴 **One world: every ride is a path along the island's roads** (`Island`,
  `scripts/island.gd`). Places and roads are laid out by hand (`PLACES`,
  `ROADS`: via points, rolling hills, walls); routes and free rides in
  `Catalog` are lists of legs (`"road"`, or `"-road"` backwards), each
  starting where the last ended. To add a route, add a path of existing
  roads; to reshape the island, change `PLACES`/`ROADS`. Changing either
  changes route ids' roads, so give a changed route a new id (old bests and
  ghosts would be raced on a different road otherwise). Route ids were all
  replaced when the island came in (2026-09-29).
- 🔴 **Riders follow a smooth curve, never straight pieces between points.**
  `Route.position_at` is a cubic B-spline through the 5 m points: straight
  pieces jolted the rider sideways at every point on a bend (the maintainer saw
  "shakes/wobbles"), and a curve *through* the points (Catmull-Rom) still
  steps its bend at each point. `heading_at` is the curve's own direction.
  `test_riding_is_smooth` measures the sideways pull at 30 km/h; keep it.
- 🔴 **Junctions are round plazas** (`Island.plaza_radius`, 12-24 m, big
  enough that the roads have come apart by the rim). Each road is drawn only
  out to where it meets a plaza (`join_radius`, 0.8 of it; `road_span`), and
  across the plaza there's a road from every road there to every other
  (`plaza_ways`), on exactly the curve `Island.path()` rides (`_across`,
  shaped like a circle's arc). `path()` then resamples the whole way 5 m
  apart (a route's distance is its point index), and the first leg starts
  at the join, not in the plaza's middle. 🔴 **Never fill a plaza with a
  disc again**: at 48 m across with nothing on it, the maintainer rode over
  it as "a big block of black hole". The plaza ways are lifted 1.5 cm apart
  so overlapping ones don't flicker. A turn right back the way it came
  is too tight for a plaza: route round it (Grand Tour, Quarry Walls and
  Mountain laps were changed for that). Meshes must wind clockwise seen
  from the front, or Godot culls them.
- 🔴 **Roaming lays out only the road ahead** (`Route.ROAM_AHEAD`, topped up
  by `keep_ahead()`, called every frame by the ride and the menu's
  backdrop), so a turn can be chosen: `next_turn()` / `choose_turn()` re-lay
  the way beyond the next place only. That's safe because `Island.path()`
  samples exactly every `STEP` m from the start (never stretched to fit),
  so identical legs give identical points; and a turn closes `TURN_CLOSES`
  m before the curve across the plaza (`legs[j].turn_s`), which already
  depends on the choice. `test_choosing_a_turn_keeps_the_road_ridden`.
  The world drops its gates when `route.changes` moves.
- **Segments** (`Island.SEGMENTS`, a stretch of one road one way) are found
  on any way by `Route._find_segments()`; `Ride` times them line to line
  and queues events; bests live in the saved rides (`segments`).
  `ride.segment_best/_kom` are as before the ride (XP), `..._now` include
  this ride's laps (the screen). Power records (`Ride.RECORD_SPANS`) are
  rolling averages over the per-second samples, saved as `powers`; the
  first ride only sets them (no bonus, no banner).
- **Workout targets**: steps are `[s, from, to, rpm]` (rpm 0: none).
  `Ride.smooth_power/_cadence` (a ~2 s average) are what's coloured and
  judged, never a single reading; each block settles for `Workout.SETTLE`
  s first; bands are `POWER_BAND` (10%) and `CADENCE_BAND` (5 rpm). The FTP
  test isn't judged. On an ERG bike the power is held for you, so cadence
  is the part the rider controls. `--demo-rpm` makes the made-up rider
  ignore cadence targets, to see "off target".
- **Free rides** are laps (`"loop"`: legs that end where they start) or
  roaming (`"roam"`: a road at random at each place, never one in `"avoid"`
  or steeper than `"max_grade"`; `Route.avoided()`). Roaming gets a new
  seed every ride (`main._start`); the spec's seed is only for the menu's
  backdrop and the tests. Pedalling in the menu starts `PEDAL_FREE_RIDE`.
- 🔴 **No water, by the maintainer's decision** ("leave the water, make the map
  only land", 2026-09-29): a sea and a lake were built and taken out. The
  land settles to `OUTSIDE` at the baked area's edge, far past the roads.
- **The land is baked once** (`Island.bake()`: road-side flats, a relaxed
  surface through the roads' heights, per-area hills from noise), saved by
  `tools/bake_island.gd` during the image build to `game/world/island.bin`
  (git-ignored) with a fingerprint of every input; a stale or missing file
  is baked at startup instead, with a warning. The land shader raises flat
  tiles from it as a texture. The road is drawn 0.3% nearer the camera so
  it never flickers into the land.
- **Rendering is OpenGL 3.3** (`--rendering-driver opengl3`, Compatibility
  renderer, set by `game/run.sh`). `GAME_RENDERER=vulkan` is the fallback
  (Mobile renderer). The image is x86-64 only.
- **The kiosk container runs cage on the screen directly**: `privileged`,
  `LIBSEAT_BACKEND=noop` (no logind or seatd inside), `WLR_LIBINPUT_NO_DEVICES=1`
  (start without a keyboard), `/run/udev` mounted read-only so libinput can
  find devices. It needs a machine with no desktop running (compose profile
  `kiosk`; `desktop` is the windowed one).
- **144 Hz in kiosk mode**: cage takes the monitor's preferred mode, which
  is often native@60 Hz on a monitor that does 144. `game/kiosk-client.sh`
  runs inside cage and switches each output to its fastest refresh at its
  preferred resolution (`wlr-randr`), then execs godot. `GAME_MODE` forces one.
- 🔴 **Only the menu's Exit button may power the computer off.** In kiosk mode
  it quits with status 10 (`EXIT_STATUS` in `main.gd`), and
  `kiosk-client.sh` powers off through the host's logind only on that status
  with `EXIT_ACTION=poweroff`. Ctrl+Q (0), a crash, or Docker stopping the
  game (a signal) must never power off: a deploy would shut the machine down.
  `tests/kiosk_client_test.sh` runs in the build, and the build presses Exit
  in both modes. Don't `exec godot` in the wrapper again: the status would be
  lost. Machine choices (poweroff or not) go in a `compose.override.yaml`,
  which git ignores.
- 🔴 **The bridge keeps asking the bike for control until it agrees**
  (`bikebridge.ride`: Request Control, then Start or Resume, every
  `CONTROL_RETRY` s), and asks again when the bike's Fitness Machine
  Status says reset, stopped or control lost, or a command is refused with
  "control not permitted". Asking once wasn't enough: switched on together
  with the computer, the bike refused while still starting up and only
  took commands after someone pressed play on it. A bike that never
  answers is treated as agreeing (as before). The game shows "asking it to
  take control" until it does. The tests in `test_bridge.py` fail on the
  old one-shot code.
- 🔴 **The bridge must disconnect the bike when it stops.** It's process 1 in
  its container, which the kernel sends no signal it has no handler for, so
  `main()` handles SIGTERM (Docker's stop) by cancelling itself, and
  `async with BleakClient` disconnects. Without that, Docker killed it 10 s
  later and BlueZ kept the connection with nothing using it: the bike
  doesn't advertise while connected, so no search found it again (bleak
  searches even when given an address). As a backstop, when a search finds
  nothing and a bike is remembered, `let_go_of()` asks BlueZ over D-Bus
  whether it's still connected and disconnects it. `test_bridge.Stopping`
  fails without the handler.
- **The bridge keeps retrying when there's no Bluetooth adapter** (state
  `no_adapter`, shown in the game) instead of crash-looping on BlueZ's D-Bus
  timeout.
- 🔴 **Each rider's own settings live in `Rider` (`riders/<n>/rider.cfg`),
  what the bike's users share in `Settings` (`settings.cfg`).** Weight, FTP,
  hill feel, colour, camera, last choice, history, bests and ghosts are the
  rider's; volumes, mute, graphics, FPS and pedal-to-start are everyone's.
  Don't put a personal setting back in `Settings`. `History.dir` follows the
  active rider (`main._use_rider`).
- 🔴 **Data from before riders becomes Rider 1's, once**: `Riders.load_all`
  does it only when `riders/` doesn't exist, moving `rides/` (a rename, not a
  copy) and taking the old personal keys from `settings.cfg`, whose next save
  drops them. `test_old_data_becomes_rider_1` covers it; keep it passing.
- **There is always a rider** (`Riders.remove` refuses the last one; an
  empty `riders/` gets "Rider 1"). Folders are numbered, not named, so a
  rename moves nothing. A freed number can be reused: its folder is gone.
- **"Who's riding?" shows only with more than one rider**, when the game
  starts and when it wakes. Pedalling there starts a free ride as the
  highlighted rider (`menu.picker_choice()`); never on the name or delete
  screens (`no_pedal`), where a ride would start mid-typing.
- 🔴 **XP is worked out once, when a ride is saved, and stored in its summary**
  (`xp`, `xp_parts`); a rider's level is the sum over their saved rides, never
  a separate counter, so it can't drift from the history. Effort XP is each
  second's (power / FTP)^2, capped at 1.5x FTP, against the FTP at the time:
  that's what makes it fair between riders (`test_xp_is_fair_across_riders`).
  Rides from before XP are estimated from average power (`Levels.estimate`).
  Changing a constant in `levels.gd` changes only future rides and estimates.
- **The FTP test is a workout built for the rider's FTP** (`Workout.ftp_test`,
  id `ftp-test`, not in `Catalog`). It ends when power stays under
  `TEST_GIVE_UP` of the target for `TEST_GIVE_UP_AFTER` s (`main._test_check`,
  on ride time); the answer is 75% of the best 60 s (`Workout.test_result`),
  and the rider chooses whether to use it. Intensity keys are off in it.
  `--demo-max=W` gives the made-up rider a ceiling so the test can be tried.
- **Whose ghost**: `menu.ghost_for(route)` picks, per rider and route, what
  was chosen with Left/Right, else your own best, else the fastest rider's.
  `ride.rival` carries it; the ghost bike, profile marker and minimap wear the
  other rider's colour. Beating another rider's best is `Levels.BEAT_RIVAL`.
- **The minimap is racing-game style** (`MiniMap`), the maintainer's choice
  ("NFS style where it is zoomed in a bit"): `SPAN` m tall round you,
  turned so your heading is up, redrawn every frame (it moves). It draws in
  island metres under `draw_set_transform`, so widths are pixels times
  `1 / scale`; labels, the ghost, north and your arrow are drawn upright
  after resetting it. A whole-island north-up map was tried first and
  called useless. It sits in its own square (`Hud.MAP_SIZE`) at the bottom
  right, as tall as the height profile beside it (the maintainer's layout).
- **Settings are saved when you leave the Settings screen (Esc)**, and on
  ride start (last choice) or camera change. A test that changes a setting
  and screenshots before Esc sees nothing on disk; that's expected.
- **Sounds are generated at image build** by `tools/make_sounds.py`; never
  commit WAVs. The music loops are rendered three times and the middle one
  kept, with its start faded in from the next loop's start, so the wrap has
  no click.
- **The Docker build is the test run**: import, `tests/run.gd`, then a few
  seconds each of a route, a workout and a free ride with `--demo`. Any
  `SCRIPT ERROR` fails the build. Keep it that way.
- **Screenshots are how the looks get checked.** `--screenshot=... --after=N`
  plus `--keys=...` drives whole journeys; README → Handy options.
