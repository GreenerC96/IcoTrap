# Rules

## World

The world is a faceted icosahedron.

- It has 12 vertices and 20 triangular faces.
- One vertex is the north pole (`+Y`). The opposite vertex is the south pole (`-Y`).
- `frequency` (2–8) splits every face into a triangular grid. Points stay on the flat face. They are not pushed back onto a smooth sphere.
- `gap` (0–0.4) pulls each tile’s corners in toward its own center, leaving a gap between tiles.
- `radius` scales the whole shape.
- `direction_seed` chooses how wind is generated and which pentagons become land before wind. The same seed always rebuilds the same world.
- `land_pentagon_count` (0–12, default 4) is how many pentagons are marked land before wind. Changing it rebuilds the world.

## Tiles

Every face is a tile. Tiles are created in a fixed order and named `Tile0`, `Tile1`, and so on. That order is the sort order used whenever a choice would otherwise be arbitrary.

Each tile stores:

- **Neighbours** — one tile per edge. Two tiles are neighbours when they share an edge from before the gap inset.
- **Opposites** — corner links. Only triangle tiles have them. A pentagon has none.
- **Terrain** — sea or land. New tiles start as sea.
- **Wind out** — the tile or tiles this tile sends wind to.
- **Wind in** — the tiles that send wind to this tile.

Sea tiles are blue. Land tiles are green. Hovering a tile turns it white.

### Neighbours

Neighbours follow the tile’s corners in order. Edge `i` runs from corner `i` to the next corner, and that edge’s neighbour is stored at the same index.

### Opposites

For each corner of a triangle, the opposite is another triangle that:

- shares that same corner,
- is not this tile,
- is not a pentagon,
- is not a neighbour of this tile,
- is not a neighbour of any neighbour of this tile.

If several tiles still qualify, the one with the lowest sort index is used.

On a normal 6-triangle vertex this is the tile straight across the corner: two steps around the vertex, past the two edge neighbours. A 5-triangle vertex has no such tile, so that corner has no opposite.

### Tile types

There are two types.

#### Triangle

The default tile. Each small triangle from the face subdivision is a triangle tile.

- 3 corners, 3 neighbours, 3 opposite slots.
- An opposite slot stays empty when that corner has no valid opposite.
- A triangle that still touches an original icosahedron vertex is a **corner tile**. Corner tiles are the five triangles around a vertex that was not turned into a pentagon. Every vertex is a pentagon, so the world has no corner tiles.

#### Pentagon

A pentagon replaces the five triangles around an original icosahedron vertex.

- All 12 vertices are replaced.
- The five triangles are removed. Their outer edges become the pentagon’s five corners.
- The pentagon is wound so its face points outward.
- It has 5 neighbours and no opposites.
- It is not a corner tile. The triangles it replaced are gone, so that vertex no longer has corner tiles.

## Wind

Wind is a direction on each reached tile: usually one outgoing tile, sometimes two on a pentagon. It does not have to reach every tile. A tile that never receives a direction has no wind.

How wind is generated is defined in [world-generation.md](world-generation.md).

Wind strands are a **visual only**. They read each tile’s wind out links and do not change generation, seeds, or tile data.

### WindStrand node

The World scene ([objects/icosahedron.tscn](objects/icosahedron.tscn)) has a child **WindStrand** node ([scripts/wind_strand.gd](scripts/wind_strand.gd)). Its exports are edited in the inspector (open that scene, or enable editable children on the World instance in Main). Strands spawn only while the game is running; the node does nothing in the editor except hold settings.

### Bursts and origins

On a timer (`interval_seconds`), the spawner picks several **origin** tiles that have at least one wind out target (`origins_per_burst`). Origins are chosen without replacement. Tiles that recently had a strand pass through them are deprioritized until `tile_strand_cooldown_seconds` has elapsed; if not enough “fresh” tiles exist, recently used ones are still picked. Cooldown memory is cleared when the world rebuilds. Burst randomness is independent of `direction_seed`.

From each origin, one strand is started for **each** wind out target (a pentagon with two targets starts two strands). Each strand walks forward along wind out links for up to `hop_count` hops after the first target. If a tile sends wind to more than one tile, the walk **splits** into separate strand paths, each with its own remaining hop budget. A path stops when hops run out or a tile has no wind out.

### Path shape

Each strand follows a smooth 3D path built from the tile sequence:

- **Control points** alternate lifted tile centroids and **bridges** between consecutive tiles. A bridge sits on the shared edge midpoint when the step is to a neighbour, or on the matching opposite corner on the source tile for an opposite jump, lifted along the blended outward normal of the two tiles. That keeps the path from cutting through tiles when crossing facets or pentagons.
- The control polyline is smoothed with a **Catmull-Rom** spline, resampled at `curve_samples_per_unit` per world unit. The ribbon uses arc length along that curve.

### Strand motion and look

Each strand is a short ribbon (`strand_length` in world units) that moves at constant `strand_speed` along the path:

1. **Extrude** — tail fixed at the origin; the head grows out to full length.
2. **Slide** — the full-length window travels toward the end of the path.
3. **Trail off** — head at the path end; the tail catches up until the strand is gone.

The mesh is a serpentine triangle strip (`wave_amplitude`, `wave_frequency`, `wave_speed`), unshaded and alpha-blended. Along the visible piece, alpha fades from transparent at the tail to `ribbon_color` alpha at the head. Width and height above the surface use `ribbon_width` and `surface_lift`.

Overlapping bursts are allowed. A world rebuild clears active strands and refreshes which tiles can spawn from.

