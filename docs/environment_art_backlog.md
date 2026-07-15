# Environment Art Backlog

Items are unique and ordered by visual priority. Completed work is retained here
as an audit trail. Evidence refers to the committed 15-room contact sheets and
the browser review described in `docs/visual_improvement_log.md`.

## Global visual problems

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| HIGH | Practical room lighting | 15 room-clipped painted recipes; no new gameplay-light nodes | stronger focal hierarchy and material depth | M | HIGH: hidden-room leaks | three-state capture matrix | **Complete** |
| MEDIUM | Door/wall integration | rank-specific reinforced frame, exact span, open/closed silhouette | clearer access hierarchy and doorway depth | M | MEDIUM: false opening silhouette | exact collision/occluder assertions | **Complete** |

## Tiles

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| LOW | Exterior wall/fence edge variants | overview shows consistent but simple outer wall field | stronger facility exterior identity | S | LOW | no topology change | Backlog |
| LOW | Corporate/service border transitions | some connector cells intentionally use neutral floor | smoother material handoff without false path cues | M | MEDIUM | connector atlas/mask validation | Backlog |

## Lighting

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| HIGH | CCTV/Electrical/Research practical-light prototype | clipped cyan/amber/violet pools retained actor priority | cinematic focus and state readability | M | HIGH | zero wall leak and Web renderer | **Complete** |
| MEDIUM | Warm Guard Break contrast | warm canteen hero and light recipe distinguish the room | humanizes facility and improves progression | S | MEDIUM | practical-light prototype | **Complete** |

## Room dressing

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| MEDIUM | Staff Office / Guard Break | unique 2×2 landmarks plus room signatures | controlled lived-in detail | M | MEDIUM: clutter and false collision | visual-only cells | **Complete** |
| MEDIUM | Reception corporate identity | scanner/logo hero and desk silhouette | stronger first interior impression | S | LOW | symbol atlas additions | **Complete** |

## Hero assets

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| MEDIUM | Stateful CCTV/breaker panels | explicit offline/alert/stolen/active tiles follow signals | visible cause/effect and satisfaction | M | MEDIUM: state desync | presentation listeners only | **Complete** |
| LOW | Vault stabilizer variation | stable-phase vault motion plus stolen-Core state | richer climax | M | LOW | deterministic phase policy | **Complete** |

## Environment animation

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| HIGH | Monitor/server/breaker micro-animation | 15 pause-safe 6 Hz room loops with stable phases | makes facility feel alive | M | MEDIUM: flashing/perf/pause | stable phase offsets, state listeners | **Complete** |

## VFX

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| LOW | Extraction/Core state pulse review | late-state matrix retains Core/extraction readability | small reward polish | S | MEDIUM: obscures silhouettes | full mission-state capture | **Complete** |

## UI visual integration

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| LOW | Room label/HUD overlap | facility camera reserves a 28 px world-space safe-top offset; 1024/1280 Web frames pass | cleaner composition | S | LOW | responsive 1024/1280 capture | **Complete** |

## Performance and QA

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| MEDIUM | Browser frame-time baseline | payload and node counts are measured; FPS/frame time not yet instrumented | quantitative guardrail for lights/animation | M | LOW | production Pages build | Backlog |
| MEDIUM | Stateful visual screenshot matrix | all 15 rooms captured clean, initial, and synthetic late state | safer stateful visual iteration | M | LOW | deterministic capture hooks | **Complete for art-state QA; real-play late capture remains** |
| MEDIUM | Systems-floor detail rhythm | sparse signatures and heroes replace the dominant repeated field | stronger local variation without restoring noise | S | LOW | seeded atlas variants | **Complete** |
