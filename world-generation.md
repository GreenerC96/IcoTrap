# World generation

How wind is generated. The icosahedron, the tiles, and what wind is are defined in [rules.md](rules.md).

Generation is deterministic for a given seed, tile layout, and sort order.

## Where wind starts

Wind starts on every pentagon and every corner tile. Those seeds are handled in sort order. A seed that was already given wind is skipped.

**Pentagon.** Picks 1 or 2 different neighbours, with equal chance of either count. It may point at any of its five neighbours.

**Corner triangle.** Picks exactly 1 neighbour. It may not point at another corner tile, so it only blows outward from the vertex, not around the ring of five.

## How a target is chosen

Whenever wind picks a next tile, it uses this order:

1. A tile that does not already have its own outgoing wind, and is not forbidden.
2. A tile that is not forbidden, even if it already has outgoing wind.
3. Any remaining option, including a forbidden one.

Forbidden means “do not blow straight back at the tile this wind came from,” when such a tile exists. Among tiles in the same priority group, the choice is random from the seed.

## How wind spreads

After the seeds, wind moves outward in waves.

1. Collect every tile that some assigned tile points at and that does not yet have its own wind.
2. Process that wave in sort order.
3. Each of those tiles records every tile currently pointing at it as an incoming source.
4. It may send wind to any neighbour or any opposite, except it avoids sending wind back to its sources when another choice exists.
5. It picks one target with the priority above.

If that target is an **opposite** (a jump across a corner, not an edge neighbour), wind also branches:

- The two neighbours on the edges that meet at that corner are the branch candidates.
- One of them is chosen with the same priority, skipping the source and the opposite already chosen.
- That side tile is not a second arrow on the current tile. It becomes its own wind tile, with the current tile as its source, and then it picks its own outgoing target.
- If the branch also jumps to an opposite, it can branch again the same way.
- Branches are assigned before the next wave. If a wave is empty but a branch is still waiting, generation continues from that branch.

## What a tile sends

- A pentagon seed sends to 1 or 2 neighbours.
- Every other tile that receives wind sends to exactly 1 tile.
- The extra branch from an opposite jump is a separate tile downstream, not a second target on the jumper.
- Wind may merge into a tile that already has outgoing wind. It only points back at its own source when every other option is gone.
- Several tiles may point at the same tile. That tile keeps all of them as incoming sources and still chooses only one outgoing target.
