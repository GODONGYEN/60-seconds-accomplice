# Visual Quality Scorecard

Scoring is 0–10 and reflects the verified `34bf403` native Compatibility captures, not intended future art. Baseline overall foundation was **4.7/10**. The accepted two-cycle foundation is **7.0/10**: material and room identity improved substantially, while practical lighting and environment animation remain intentionally incomplete. Eight rooms received detailed 1280-wide captures; scores for Staff Office, Locker, Security, Guard Break, Maintenance, and Extraction are provisional overview reviews and should be refined by the next targeted capture matrix.

Abbreviations: `RI` room identity, `CO` composition, `FP` focal point, `LI` lighting, `CH` color harmony, `MR` material readability, `DE` depth, `PV` prop variety, `CC` controlled clutter, `ES` environmental storytelling, `GR` gameplay readability, `CS` character separation, `AN` animation, `VX` VFX restraint, `PX` pixel consistency, `PS` performance safety.

| Room | RI | CO | FP | LI | CH | MR | DE | PV | CC | ES | GR | CS | AN | VX | PX | PS |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| External Yard | 7 | 7 | 8 | 3 | 7 | 8 | 6 | 5 | 8 | 6 | 9 | 9 | 2 | 9 | 8 | 10 |
| Reception | 6 | 7 | 6 | 3 | 8 | 8 | 7 | 6 | 9 | 6 | 9 | 9 | 2 | 9 | 8 | 10 |
| Staff Office | 6 | 6 | 5 | 3 | 7 | 7 | 6 | 5 | 8 | 5 | 9 | 9 | 2 | 9 | 8 | 10 |
| Locker Room | 8 | 7 | 8 | 3 | 7 | 8 | 7 | 7 | 8 | 7 | 9 | 9 | 2 | 9 | 8 | 10 |
| Security Office | 7 | 7 | 7 | 3 | 8 | 8 | 7 | 7 | 8 | 7 | 9 | 9 | 2 | 9 | 8 | 10 |
| CCTV Control | 9 | 8 | 9 | 4 | 8 | 9 | 8 | 8 | 8 | 8 | 9 | 9 | 2 | 9 | 9 | 10 |
| Electrical | 9 | 8 | 8 | 4 | 8 | 9 | 8 | 8 | 8 | 8 | 9 | 9 | 2 | 9 | 9 | 10 |
| Server Room | 9 | 8 | 8 | 4 | 8 | 9 | 8 | 7 | 9 | 8 | 9 | 9 | 2 | 9 | 9 | 10 |
| Research Lab | 9 | 8 | 9 | 4 | 9 | 9 | 8 | 8 | 8 | 8 | 9 | 9 | 2 | 9 | 9 | 10 |
| Guard Break | 6 | 6 | 6 | 3 | 7 | 7 | 6 | 6 | 8 | 5 | 9 | 9 | 2 | 9 | 8 | 10 |
| Laser Corridor | 8 | 8 | 10 | 4 | 9 | 8 | 7 | 4 | 10 | 8 | 10 | 9 | 3 | 9 | 8 | 9 |
| Vault Antechamber | 7 | 7 | 7 | 3 | 8 | 8 | 7 | 4 | 10 | 6 | 9 | 9 | 2 | 9 | 8 | 10 |
| Chronos Vault | 10 | 9 | 10 | 6 | 10 | 9 | 9 | 8 | 8 | 9 | 10 | 9 | 5 | 9 | 9 | 9 |
| Maintenance | 8 | 7 | 8 | 3 | 7 | 8 | 7 | 8 | 8 | 7 | 9 | 9 | 2 | 9 | 8 | 10 |
| Extraction Route | 7 | 7 | 8 | 3 | 7 | 8 | 6 | 5 | 9 | 6 | 9 | 9 | 2 | 9 | 8 | 10 |

## Global comparison

| Category | Before | Current | Evidence |
|---|---:|---:|---|
| Tile repetition | 2 | 7 | 33.3% diagonal overlay replaced by ~6% seeded details; repeated amber systems marks remain visible |
| Wall consistency | 2 | 7 | 16 neighbor masks × 2 variants communicate cap, face, and walkable edge |
| Door consistency | 5 | 5 | Gameplay doors were deliberately unchanged and now need a matching frame pass |
| Palette consistency | 7 | 9 | One canonical navy/gunmetal/cyan/amber/red/violet palette drives every generated tile |
| Shadow consistency | 5 | 6 | Props have a shared lower contact edge; no new cast-light system yet |
| UI integration | 7 | 7 | HUD remained readable at 1280×720, a 1024-wide internal render, and a 1024×768 browser viewport; no UI styling change in this pass |
| Visual progression | 3 | 8 | Yard → corporate → systems → research → vault materials create a readable mission gradient |
| Vault climax | 3 | 9 | Violet room family, lab stabilizers, and 3×3 Core circuit create a unique endpoint |
| Exterior/interior contrast | 3 | 8 | rough desaturated Yard and brighter controlled interiors now separate immediately |
| Practical lighting | 2 | 3 | material highlights improved; authored room lights remain future work |
| Environment animation | 2 | 2 | existing Core/laser motion only; no unverified decorative motion was added |
| VFX restraint | 9 | 9 | no bloom, screen shader, new particles, or flashing added |

The lowest high-exposure areas are practical lighting, environment animation, and door consistency. They are the next-cycle candidates, in that order only after visibility-safe prototypes exist.
