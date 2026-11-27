extends RefCounted
## Set dressing of the Outer Ruins, in area space. The road runs from the entrance (z 8) to the
## shrine (z -30) between the arcades (|x| < 7.4), crossed twice by broken gate walls at
## z -8.9 and -18.5 whose passage stays open (|x| < 3.3). The centre lane is kept clear.
##
## The story it tells: a caravan bound for the shrine was caught on the road. Its first cart
## lies wrecked past the entrance where the survivors made camp; the husks by the first gate
## were those people. Beyond it the road has caved in and a column has come down across it.
## The last cart was dragged off the road near the shrine, and the brute's lair is ringed with
## what is left of everyone who went further.

const LAYOUT := [
	# Entrance stretch: cracked paving, a caved-in patch, the west arcade partly down.
	{"kind": "cracks", "at": Vector3(0.4, 0, 4.6), "size": Vector2(6.5, 4.0), "count": 5},
	{"kind": "sunken", "at": Vector3(3.4, 0, 1.4), "radius": 1.05},
	{"kind": "collapsed_wall", "at": Vector3(-6.45, 0, 5.4), "yaw": 90, "width": 3.0, "height": 1.5},
	{"kind": "rubble", "at": Vector3(6.3, 0, 6.2), "radius": 0.8, "count": 7},
	# The camp: a wrecked cart, the fire the survivors kept, their stores.
	{"kind": "cart", "at": Vector3(5.0, 0, -2.6), "yaw": 15, "broken": true},
	{"kind": "campfire", "at": Vector3(-4.6, 0, -4.6), "camp": true},
	{"kind": "barrels", "at": Vector3(-6.5, 0, -1.4), "count": 3},
	{"kind": "crates", "at": Vector3(6.3, 0, -6.6), "yaw": 80, "count": 3},
	{"kind": "bones", "at": Vector3(-1.6, 0, -6.9), "radius": 0.6, "count": 6, "skulls": 1},
	{"kind": "cracks", "at": Vector3(-1.0, 0, -4.2), "size": Vector2(5.0, 3.5), "count": 4},
	# First broken gate: spill at the foot of its walls.
	{"kind": "rubble", "at": Vector3(6.4, 0, -7.6), "radius": 0.9, "count": 9},
	{"kind": "rubble", "at": Vector3(-6.3, 0, -10.2), "radius": 0.8, "count": 8},
	{"kind": "rubble", "at": Vector3(2.75, 0, -8.0), "radius": 0.35, "count": 4, "collide": false},
	# Middle stretch: the road has caved in on the west side, a column lies across the east.
	{"kind": "sunken", "at": Vector3(-5.2, 0, -12.1), "radius": 1.3},
	{"kind": "fallen_column", "at": Vector3(4.3, 0, -14.3), "yaw": 30, "length": 3.4, "radius": 0.34},
	{"kind": "cracks", "at": Vector3(-0.5, 0, -13.6), "size": Vector2(8.0, 6.0), "count": 6},
	{"kind": "barrels", "at": Vector3(6.5, 0, -10.7), "count": 2},
	{"kind": "rubble", "at": Vector3(-6.4, 0, -17.2), "radius": 0.9, "count": 8},
	{"kind": "rubble", "at": Vector3(6.3, 0, -17.4), "radius": 0.8, "count": 7},
	# Last stretch: the second cart dragged aside, a watch fire, the lair.
	{"kind": "cart", "at": Vector3(-5.4, 0, -21.6), "yaw": -100, "broken": true},
	{"kind": "collapsed_wall", "at": Vector3(6.55, 0, -21.4), "yaw": -90, "width": 2.4, "height": 1.3},
	{"kind": "campfire", "at": Vector3(4.6, 0, -25.4)},
	{"kind": "bones", "at": Vector3(0.0, 0, -26.0), "radius": 1.7, "count": 18, "skulls": 3},
	{"kind": "bones", "at": Vector3(-2.6, 0, -24.4), "radius": 0.7, "count": 6, "skulls": 1},
	{"kind": "crates", "at": Vector3(-6.2, 0, -26.2), "yaw": 10, "count": 3},
	{"kind": "cracks", "at": Vector3(0.0, 0, -23.4), "size": Vector2(7.0, 6.0), "count": 5},
]
