# Rules

## World

The world is a faceted icosahedron.

- It has 12 vertices and 20 triangular faces.
- One vertex is the north pole (`+Y`). The opposite vertex is the south pole (`-Y`).
- North is marked red. South is marked cyan.
- `frequency` (1–8) splits every face into a triangular grid. Points stay on the flat face. They are not pushed back onto a smooth sphere.
- `gap` (0–0.4) pulls each tile’s corners in toward its own center, leaving a gap between tiles.
- `radius` scales the whole shape.
- `direction_seed` chooses both which vertices become pentagons and how wind is generated. The same seed always rebuilds the same world.

## Tiles

Every face is a tile. Tiles are created in a fixed order and named `Tile0`, `Tile1`, and so on. That order is the sort order used whenever a choice would otherwise be arbitrary.

Each tile stores:

- **Neighbours** — one tile per edge. Two tiles are neighbours when they share an edge from before the gap inset.
- **Opposites** — corner links. Only triangle tiles have them. A pentagon has none.
- **Wind out** — the tile or tiles this tile sends wind to.
- **Wind in** — the tiles that send wind to this tile.

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
- A triangle that still touches an original icosahedron vertex is a **corner tile**. Corner tiles are the five triangles around a vertex that was not turned into a pentagon.

#### Pentagon

A pentagon replaces the five triangles around an original icosahedron vertex.

- `pentagon_vertex_count` (0–12) is how many of the 12 vertices are replaced.
- Which vertices are chosen is a shuffle driven by `direction_seed`.
- The five triangles are removed. Their outer edges become the pentagon’s five corners.
- The pentagon is wound so its face points outward.
- It has 5 neighbours and no opposites.
- It is not a corner tile. The triangles it replaced are gone, so that vertex no longer has corner tiles.

## Wind

Wind is a direction on each reached tile: usually one outgoing tile, sometimes two on a pentagon. It does not have to reach every tile. A tile that never receives a direction has no wind.

How wind is generated is defined in [world-generation.md](world-generation.md).

## Selection colors

Right-clicking a tile shows its links:

- neighbours in green,
- opposites in yellow,
- wind targets in red.

Hovering a tile turns it white. Wind leaving a tile is drawn in black, from the tile center toward the target. Wind entering a tile is drawn in white, from the source to the center.
