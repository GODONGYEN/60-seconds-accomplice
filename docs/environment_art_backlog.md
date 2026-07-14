# Environment Art Backlog

Items are unique and ordered by visual priority. `Evidence` refers to the committed 1280×720 screenshots, the additional 1024-wide native review, or the 1024×768 browser check described in `docs/visual_improvement_log.md`.

## Global visual problems

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| HIGH | Practical room lighting | Most rooms score 3–4/10 lighting; current contrast comes mainly from Player visibility | stronger focal hierarchy and material depth | M | HIGH: hidden-room leaks | visibility capture matrix and door open/closed test | Ready for isolated prototype |
| MEDIUM | Door/wall integration | Access doors retain the older flat style against reinforced wall art | clearer access hierarchy and doorway depth | M | MEDIUM: false opening silhouette | preserve door collision/state scenes | Backlog |

## Tiles

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| LOW | Exterior wall/fence edge variants | overview shows consistent but simple outer wall field | stronger facility exterior identity | S | LOW | no topology change | Backlog |
| LOW | Corporate/service border transitions | some connector cells intentionally use neutral floor | smoother material handoff without false path cues | M | MEDIUM | connector atlas/mask validation | Backlog |

## Lighting

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| HIGH | CCTV/Electrical/Research practical-light prototype | hero props read by pixels, not localized room light | cinematic focus and state readability | M | HIGH | zero wall leak, Web renderer, 3 resolutions | Candidate for cycle 3 |
| MEDIUM | Warm Guard Break contrast | Guard Break remains one of the least distinctive rooms | humanizes facility and improves progression | S | MEDIUM | practical-light prototype accepted first | Blocked by lighting foundation |

## Room dressing

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| MEDIUM | Staff Office / Guard Break | 5/10 storytelling; only core furniture silhouettes | controlled lived-in detail | M | MEDIUM: clutter and false collision | decals only on non-interactive cells | Backlog |
| MEDIUM | Reception corporate identity | desk reads, but no scanner/logo silhouette yet | stronger first interior impression | S | LOW | symbol atlas additions | Backlog |

## Hero assets

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| MEDIUM | Stateful CCTV/breaker panels | network shutdown currently changes gameplay object but not semantic room furniture | visible cause/effect and satisfaction | M | MEDIUM: state desync | presentation listeners only | Backlog |
| LOW | Vault stabilizer variation | Vault scores 9/10 but benches are static/repeated | richer climax | M | LOW | deterministic phase policy | Backlog |

## Environment animation

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| HIGH | Monitor/server/breaker micro-animation | environment animation remains 2/10 outside existing Core/laser | makes facility feel alive | M | MEDIUM: flashing/perf/pause | stable phase offsets, state listeners | Next after lighting decision |

## VFX

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| LOW | Extraction/Core state pulse review | current hero effects remain readable | small reward polish | S | MEDIUM: obscures silhouettes | full mission-state capture | Backlog |

## UI visual integration

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| LOW | Room label/HUD overlap | dim room labels can sit behind the 120 px HUD band | cleaner composition | S | LOW | responsive 1024/1280 capture | Backlog |

## Performance and QA

| Severity | Target | Evidence | Expected impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|---|
| MEDIUM | Browser frame-time baseline | payload and node counts are measured; FPS/frame time not yet instrumented | quantitative guardrail for lights/animation | M | LOW | production Pages build | Backlog |
| MEDIUM | Stateful visual screenshot matrix | static room centers captured; Ghost and online/offline comparisons are incomplete | safer stateful visual iteration | M | LOW | QA capture scene/state hooks | Backlog |
| MEDIUM | Systems-floor detail rhythm | repeated amber marks remain visible in Electrical and Server | stronger local variation without restoring noise | S | LOW | reduce density or add one restrained variant | Backlog |
