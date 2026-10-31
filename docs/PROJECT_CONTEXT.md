# SafeCircle project context (read first)

## Purpose
Women and child safety, local community level. Two facts are hard to find when choosing a route: where concerns were recently reported, and where mobile signal is weak. SafeCircle shows them as two separate layers and uses both to compare real route geometry. It supports informed decisions; it does not guarantee safety.

## Pilot region
Delhi and Haryana. Fence = bounding box (south 27.60, west 74.40, north 30.95, east 77.65) in backend/app/region.py, to be replaced by exact state-boundary polygons. Data will exist only where collected; elsewhere "no data" = unknown.

## Evidence rules (configurable in backend/app/config.py)
- Report snaps to nearest road segment within 30 m.
- Same user + segment + category within 24 h counts once. Max 5 reports/user/day.
- Report weight 1.0 if the user was within 150 m, else 0.5.
- Concern score = sum(weight * 0.5^(age_days/30)).
- Amber at score >= 0.8. Red only if score >= 2.5 AND >= 3 distinct users AND moderator confirmation. Red lapses as evidence decays. Below amber = "no data" (unknown, never safe).

## Route score
R = wS*S + wN*N + wI*I + wD*D, each term 0-1, lower is better. S, N, I are length-weighted over segments. D = (t - tmin)/tmin capped at 1.
- Day weights (S,N,I,D) = 0.30, 0.20, 0.15, 0.35. Night = 0.45, 0.25, 0.20, 0.10.
- S: no_data 0.30, amber 0.55, red 0.90. N: good 0.10, weak 0.50, none 0.90, unmeasured -> 0.50 flagged unmeasured. I: from OSM baseline, unknown 0.50.
- Reference numbers (tests reproduce them): day A 0.236 / B 0.284; night A 0.324 / B 0.288; A3 flagged red: day A 0.281, night A 0.391.
- Decay table: reports on days 0,2,5,6 give 1.00, 1.95, 2.82, 3.76; day 66 -> 0.94 (amber); day 96 -> 0.47 (no data).

## Scope tiers
Tier 0 core: map layers, reporting + moderation, route comparison, Night Safety Mode, flag-changes-route, basic offline.
Tier 1: Journey Guard (server dead-man timer), BLE rotating-token evidence, SOS bundle, Safe Haven directory.
Tier 2 (design only): police integration, child/guardian flows, pgRouting safety-optimised routes, iOS parity.

## Platform limits (state openly in UI and docs)
- Android first: iOS cannot read cellular signal strength via public APIs and restricts background BLE.
- Ordinary apps cannot lock the power button or stop GPS being turned off. Use persistent notification, permission-change detection, escalation after missed check-ins.
- BLE tokens are unverified leads, never proof of presence, identity or guilt.
- SOS and alerts cannot be guaranteed to deliver.

## Design tokens (blue glass)
ink #1F1B55, body text #2A3F6E, accent #2E73B0, weak-signal navy #243F7F, amber #F5A83D, red #C62828, glass rgba(255,255,255,.55) + blur 18 + 1px rgba(255,255,255,.85) border, radius 24, pills 999. Background gradient 155deg #E3F4FA, #B0DCEB, #8FD0E8, #6EC0DC. Touch targets >= 48 dp. Design canvas: https://claude.ai/artifact/A6iyc4uH913KXjabJFXzrb

## Screen-2 targets (judging)
Working prototype/demo; architecture + sequence diagrams + ERD; calculations and simulation validation; itemised BOM; team roles; 75-day milestone chart; bottlenecks; risks. Pilot objectives: O1 5 routes signal walk-test (1 sample/100 m); O2 10 routes scored vs shortest route; O3 95% of 5 seeded duplicates caught; O4 flag changes recommendation on 3 routes; O5 offline route works on 3 phones in airplane mode; O6 usability 15 users, 80% name preferred route and why within 1 min.
