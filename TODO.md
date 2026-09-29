# To do

Ideas not built yet, kept here so they aren't lost. Nothing in the game
depends on them.

## Computer riders (bots)

Made-up riders on the road with you, each at a set power, moved by the same
rider physics as you (`rider_physics.gd`), so slower uphill and faster down,
as you'd be at that power.

- **Looks:** drawn like the ghost bike but solid, each in its own colour,
  with a name over its head ("PACER 180 W"), riding beside you in the lane.
  Dots on the minimap and on the height profile.
- **On screen:** "3rd of 5, 40 m behind Pacer 180" in the top-right panel;
  a banner when you pass one or one passes you.
- **Routes:** an optional pack, picked with Left/Right on the route like
  whose ghost ("Pack: 120 / 150 / 180 / 220 W", or easy / steady / hard
  from the rider's FTP). A placing at the finish ("2nd of 5") and a little
  XP for each one beaten.
- **Free rides:** one pacer beside you: steady at a share of your FTP, or a
  "wheel" that matches your speed.
- **Workouts:** none; the bike holds the power there.
- **Feel:** some variation in their power (a pack surges and eases), strong
  ones fading a little on long climbs. Seeded, so the same pack can be
  raced again.
- **Open questions:** packs as fixed watts or as shares of each rider's FTP;
  which kind of free-ride pacer, or both.

## Achievements

The last thing to build, once everything else is done. Per rider, shown on
their own screen and announced when earned (with XP):

- Distance: first 10 km, 100 km, 500 km, 1000 km in total.
- Climbing: Everest's height (8,849 m) in total; the summit in one ride.
- Routes: every route finished; every route at Advanced level.
- Segments: a best on every segment; King of the Mountain on one, on all.
- Workouts: the FTP test; ten workouts; a workout 90% on target.
- Habits: 3, 7 and 30 days in a row; an hour in one ride.
- Power: records over every span (5 s, 1, 5 and 20 min).
