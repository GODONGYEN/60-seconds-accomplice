# Visual Improvement Log

Baseline commit: `aa03362`
Implementation commit: `34bf403`

The baseline was imported, booted, tested (`790` assertions), Web-exported, served over local HTTP, and captured from eight authored room centers at 1280×720. Permanent comparison evidence is stored under `docs/screenshots/environment/`; the complete temporary set also included Server, Electrical, Research, and Laser Corridor.

Cycles 1 and 2 were reviewed as distinct hypotheses and screenshot comparisons but landed together in implementation commit `34bf403`; the shared before/after commit range below is intentional rather than a claim of one commit per subcycle.

## Visual Cycle 1

**Area:** Global Operation: Black Minute floor and wall foundation
**Commit before:** `aa03362`
**Commit after:** `34bf403`

**Screenshot evidence:** `before/yard_1280x720.png`, `after/yard_1280x720.png`, and `after/overview_1280x720.png`.

**Observed visual problem:** One base floor plus an overlay on every third cell covered 443 of 1,329 room-floor cells. Every room repeated the same diagonal checker rhythm, while two wall cells could not communicate top, face, base, or doorway depth.

**Art hypothesis:** Seven deterministic material families, two base variations, sparse family-specific overlays, and 16 walkable-neighbor wall masks would remove the global pattern and clarify room boundaries without moving one gameplay cell.

**Assets created:** 14 floor cells, 12 sparse overlays, 32 wall-mask cells, canonical palette/spec, review preview, and a visual-only Godot TileSet.

**Scene changes:** `Floor`, `FloorDetails`, and the new `WallArt` layer use the authored art TileSet. The original `Walls` layer remains collision/LOS authority and is rendered transparent.

**Lighting changes:** None. Pixel highlights simulate material response only; no light, shader, or particle node was added.

**Before assessment:** repetition 2/10; wall depth 2/10; exterior/interior contrast 3/10. The floor rhythm dominated every screenshot.

**After assessment:** repetition 7/10; wall depth 7/10; exterior/interior contrast 8/10. Yard, corporate, systems, research, vault, and service zones now form distinct value/color groups in the whole-map overview. The former global checker is gone, although amber systems-floor marks still repeat enough to merit a later density/variant pass.

**Gameplay readability:** Kept. Player/Guard silhouettes, extraction, access gates, cones, prompts, lasers, and the Core remain brighter and more saturated than decoration.

**Performance impact:** One additional visual TileMap layer, one generated mapping script, and one 512×320 RGBA runtime atlas (8 KiB PNG). Zero new gameplay bodies, lights, particles, shaders, or per-cell Nodes. Final Web PCK is 813,756 bytes versus the 799,688-byte baseline: +14,068 bytes (+1.8%). Source, processed, docs, tests, and tools remain export-excluded.

**Validation:** Asset rebuild deterministic; Godot import passed; collision/occlusion split asserted; all 798 tests passed. Native Compatibility captures were reviewed at 1280×720 and at a 1024-wide 16:9 internal render; a separate 1024×768 browser viewport verified the responsive frame. The automated capture tool does not yet stage every mission state, Ghost, doorway, or corridor transition; those remain explicit backlog coverage.

**Kept or reverted:** **Kept.** The initial research/vault draft repeated emissive marks on every tile; that sub-experiment was revised before acceptance so emissive marks now occur only on sparse variants/signature art.

**Remaining issues:** Dynamic doors still use the older flat visual language. Real practical lighting has not been authored.

**Next candidates:** Door frame consistency; room practical-light pass; outdoor edge/fence dressing.

## Visual Cycle 2

**Area:** Blueprint-aligned room identity and Chronos Vault climax
**Commit before:** `aa03362`
**Commit after:** `34bf403`

**Screenshot evidence:** `before/cctv_1280x720.png` versus `after/cctv_1280x720.png`; `before/vault_1280x720.png` versus `after/vault_1280x720.png`.

**Observed visual problem:** Fifteen named rooms differed mostly by labels and 19 generic top-row props. The 16 existing `internal_solid_rects` rendered as generic walls, so CCTV, Electrical, Server, Research, and Vault lacked functional silhouettes.

**Art hypothesis:** Mapping every existing solid ID to a purpose-built multi-cell motif would add room identity and controlled storytelling while preserving collision, navigation, LOS, stable IDs, and mission progression. A 3×3 circuit inlay would give the Core a clear climax without competing particles or lights.

**Assets created:** Reception desk, locker bank, office desk, break table, CCTV monitor bank, security desk, electrical cabinet, server rack, research bench, maintenance machine, and nine-tile vault circuit. Thirty-three semantic-solid atlas pieces are reused across 64 collision-aligned placements.

**Scene changes:** `PropsAbove` now uses exact blueprint solid rectangles. The former visual-only props on walkable cells were removed because they implied collision that did not exist.

**Lighting changes:** Controlled cyan, amber, and violet pixels establish material/room accents; actual visibility lighting is unchanged.

**Before assessment:** room identity 3/10; material readability 2/10; Vault climax 3/10.

**After assessment:** major-room identity 8–10/10; material readability 8/10; Vault climax 9/10. CCTV feeds, vertical breaker cabinets, server rack aisles, violet lab benches, maintenance machines, and the Core dais are recognizable without relying on room labels.

**Gameplay readability:** Kept. Tall props occupy only cells already solid in the blueprint. Keycards, terminals, door approaches, Guard patrol cells, lasers, the Core, and extraction were not moved.

**Performance impact:** Atlas-based cells only; zero extra scene Nodes per prop. No new collision or occlusion and no runtime random selection.

**Validation:** All 16 solid IDs and 64 covered cells are asserted; the vault signature is asserted cell-by-cell; the full physical no-Recall route still passes; 798/798 assertions pass.

**Kept or reverted:** **Kept.** It creates the largest room-identity gain at low regression cost.

**Remaining issues:** Staff Office and Guard Break Room need smaller storytelling props; CCTV/Server/Electrical state changes do not yet alter their environment art; ambient animation remains sparse.

**Next candidates:** Stateful monitor/breaker presentation; warm Guard Break practical light; door/access-level silhouette pass.

## Visual Cycle 3

**Area:** Macro depth and visibility-safe practical focus
**Commit before:** `2d26fe5`
**Commit after:** this environment-completion change

**Observed visual problem:** The full invisible wall field rendered as an
infinite repeated panel mass, while room identity still depended heavily on
Player/Guard illumination.

**Art hypothesis:** Restricting visible walls to the gameplay boundary plus a
two-cell deep ring, then adding room-clipped painted pools, would improve depth
and focal hierarchy without changing visibility authority.

**Result:** Kept. The original `Walls` layer remains collision/LOS authority.
One presentation node paints two restrained pools per room with no
`PointLight2D`, shadow, shader, particle, or hidden-room query. Large Yard and
Extraction spaces receive additional signatures while retaining Guard-cone and
navigation breathing room.

## Visual Cycle 4

**Area:** Deterministic room motion and mission-state feedback
**Commit before:** `2d26fe5`
**Commit after:** this environment-completion change

**Observed visual problem:** Core and lasers carried nearly all environmental
motion, and network shutdown/Core theft did not propagate into room dressing.

**Art hypothesis:** One fixed presentation clock with stable room phases could
make the facility feel alive without introducing frame-dependent gameplay.

**Result:** Kept. Fifteen rooms receive restrained two-frame motion at 6 Hz.
CCTV offline, laser offline, security alert, stolen Core, and extraction active
select explicit state tiles. Pause freezes the tick and reset returns tick and
state to zero; tests inspect both behaviors.

## Visual Cycle 5

**Area:** Fifteen-room identity, access doors, and complete evidence
**Commit before:** `2d26fe5`
**Commit after:** this environment-completion change

**Observed visual problem:** The least-authored rooms lacked a large identifying
silhouette, flat scaled doors did not match reinforced walls, and the capture
tool covered only part of the operation.

**Art hypothesis:** A unique two-cell hero per room, exact-span rank-specific
door geometry, and a 15-room × three-state capture matrix would create both the
visual result and a repeatable release gate.

**Result:** Kept after a second QA pass. The initial draft left Yard and
Extraction too empty and kept permanent Guard name labels; the accepted pass
adds large-room signatures, stronger clipped pools, a redesigned extraction
gate, safer room-label placement, and removes the redundant Guard training
labels. The committed contact sheets cover clean art, initial gameplay, and
synthetic late state. Synthetic late state is visual evidence, not a claim of a
played mission completion.

**Gameplay readability:** Preserved. No map cell, stable ID, patrol, access
rule, mission objective, or Recall contract changed. Door implementation now
uses per-instance exact shapes, but preserves the blueprint collision and
occlusion spans.

**Validation:** The authored pipeline registers 182 tiles across 15 room
profiles and 16 semantic solids. The full Godot harness passes 817 assertions.
The single-threaded Web export boots from local HTTP with zero browser
warnings/errors at both 1280×720 and 1024×768. The latter preserves the full
capture modal and HUD inside the letterboxed frame. The final PCK is 846,980
bytes: +33,224 bytes (+4.1%) over the preceding art build and +47,292 bytes
(+5.9%) over the original environment baseline.

## Visual Cycle 6

**Area:** Perceptual room identity correction

**Observed visual problem:** The prior two-cell marks satisfied the generated
metadata checklist but remained too small and too similar at gameplay zoom.
Room labels were disabled, so several spaces had neither a readable landmark nor
a secondary confirmation cue.

**Art hypothesis:** Replace every 64×32 mark with a 64×64 label-blind landmark,
give each room a concrete functional silhouette, move Security's landmark away
from its command desk, restore restrained room plaques, and slightly lift the
ambient value without touching gameplay geometry.

**Result:** Kept after native Godot clean-art and initial-gameplay capture review.
The atlas now contains fifteen distinct 2×2 landmarks: fence/floodlight, HELIX
scanner, workstations, open locker, situation map, CCTV wall, breakers, racks,
specimen pod, break-room furniture, laser emitters, vault portal, containment
ring, pipe manifold, and extraction runway. Labels are secondary; the landmark
must still read when captures hide them.

**Gameplay readability:** The visual TileSet still owns zero collision and zero
occlusion layers. All 60 landmark cells are validated against blueprint solids,
objects, and portals. The ambient lift improves floor/material separation while
leaving actors and interaction colors brighter than decoration.

**Validation:** The authored pipeline registers 212 unique cells in a 512×512
RGBA atlas. Asset regeneration/validation, Godot import/boot, 847 assertions,
and the 1280×720 three-state 15-room capture matrix pass. The single-threaded
Web export was served over local HTTP and reviewed at 1280×720 and 1024×768 with
zero browser warnings/errors. Every room therefore passes the explicit ten-point
gate in `visual_quality_scorecard.md`; future visual changes invalidate the
affected score until evidence is regenerated.
