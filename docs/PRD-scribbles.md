# PRD — Shared scribbles & party report

Status: ready-for-agent
Slice: collaborative scribble layer + party report for the OSM Party Kit
Date: 2026-07-04

## Problem Statement

A mapping-party organizer runs the Party Kit from one laptop and shares the
URL with the room. Everyone can ask the map questions ("parks with no
benches") and see answers, but the experience is solitary: each mapper works
in their own browser with no shared canvas. There is no lightweight,
fun way for the room to point at things together — "I'm taking this block",
"look at this gap", "fixed!" — without leaving the app for a chat tool. An
earlier README draft promised richer collaboration (a live-updating fix
counter, an auto notepad, an end-of-party summary), but those depended on
live re-fetch/re-bake pipelines and always-on external endpoints, which are
too complex and too fragile for a laptop on party wifi.

## Solution

A **dumb, shared scribble layer** over the party map, plus a **party report**
that renders what the room drew.

- Any mapper can draw **freehand lines** and drop **emoji stamps**
  (📍 ✅ ❓ ⚠️) directly on the map. Everyone in the room sees everyone's
  scribbles within a few seconds.
- Each mapper is a self-declared **(color, handle)** identity — no accounts,
  no login. Captured once in a first-load modal, editable later.
- The laptop running `serve.py` is the hub (it is already the data host and
  QR-code focal point). Scribbles sync over the LAN the room is already on —
  no external service, no internet dependency beyond map tiles.
- A **party pad** (a shared etherpad on pad.riseup.net) link is generated
  once at build time; the first person to open it creates the pad.
- A **party report** page renders every scribble on the map, lists
  contributors by handle, and prints to PDF — the shareable artifact that the
  killed "summary" feature was reaching for.

Explicitly dropped this slice: SliceOSM (Geofabrik extracts only now), any
live data re-fetch / minutely rebuild, hashtag-based progress tracking, a
live fix counter, and free-text map labels.

## User Stories

1. As a party organizer, I want to run the Kit from one laptop and have the
   room join over the LAN, so that I do not need to host this anywhere.
2. As a mapper, I want to be prompted once on first load to pick a color and
   type a handle, so that my scribbles are identifiable as mine.
3. As a mapper, I want to draw freehand lines on the map, so that I can circle
   an area or trace a route I care about.
4. As a mapper, I want to drop an emoji stamp at a point, so that I can mark
   "here" (📍), "fixed" (✅), "question" (❓) or "problem" (⚠️) legibly.
5. As a mapper, I want everyone else's scribbles to appear on my map within a
   few seconds, so that we are drawing on one shared canvas.
6. As a mapper, I want my scribbles rendered in my chosen color, so that the
   room can tell who drew what at a glance.
7. As a mapper, I want to see who drew a scribble (its handle), so that I can
   attribute a mark to a person.
8. As a mapper, I want to undo my own last scribble, so that I can correct a
   mistake without touching anyone else's work.
9. As a mapper, I want my identity to persist across reloads, so that I am not
   re-prompted every time the page refreshes.
10. As a mapper, I want to change my color or handle later, so that I can fix
    a typo or resolve a color clash with someone else.
11. As a mapper, I want to toggle draw mode off, so that I can pan and zoom the
    map normally without leaving stray marks.
12. As a mapper, I want to switch between the pen and an emoji stamp, so that I
    can choose what kind of mark to leave.
13. As a mapper on a phone, I want drawing to work with touch, so that I can
    scribble without a mouse.
14. As the room, I want a shared party pad, so that we can jot ideas and notes
    alongside the map.
15. As a mapper, I want the pad link surfaced in the share panel, so that I can
    find it without asking the organizer.
16. As a party organizer, I want a report page that shows every scribble on
    the map, so that we can review what the room worked on.
17. As a party organizer, I want the report to list contributors by handle with
    their color and scribble count, so that I can credit who took part.
18. As a party organizer, I want the report to show when scribbling started and
    ended, so that the summary has a time span.
19. As a party organizer, I want a LAN-local link to the report HTML and a
    print/save-to-PDF button, so that I can share it after the party.
20. As a mapper, I want a stamp/line I erase to disappear for everyone, so that
    the shared canvas stays in sync.
21. As someone opening the Kit on a plain static host (no serve.py), I want the
    draw tools to be hidden, so that I am not offered a feature that cannot
    sync.
22. As a savvy mapper, I want to point the build at any Geofabrik extract URL,
    so that I can run a party for my own region.

## Implementation Decisions

### Data source (subtraction)

- SliceOSM support is removed. The build fetches a single **Geofabrik
  extract** named by `extract_url` in `region.json`. A savvy mapper who wants
  a smaller/custom PBF can swap the URL; that is sufficient flexibility for an
  MVP. This removes an always-on external dependency from the build path.

### Scribble as the shared primitive

- A **scribble** is the single shared primitive. Two kinds:
  - a **line**: a freehand path, `pts` = 2..2000 `[lng, lat]` points.
  - a **stamp**: an emoji at a point, `g` = the glyph, `pts` = exactly one
    `[lng, lat]` point.
- One reducer, one erase mechanism, one identity model cover both. The ✅
  stamp is the manual "I fixed this" marker — no separate fix-marking feature
  is built.

### Sync model — append-only JSONL over the LAN

- `serve.py` (already extended with Range support for DuckDB-WASM) gains one
  endpoint: `POST /api/scribble`. It validates the body and appends exactly
  one JSON line to `party/scribbles.jsonl`. Writes are serialized with a lock.
- Clients **poll** `party/scribbles.jsonl` every ~3s (served `no-store`) and
  reduce it to the current canvas. Chosen over SSE/websockets because polling
  a static file is the dumbest thing that works on stdlib `http.server` and is
  robust to clients joining/leaving. Polling pauses when the tab is hidden.
- **Erase is a tombstone line** (`{"t":"e","id":...}`), never a rewrite of the
  file. The append-only file is simultaneously the shared state, the sync
  protocol, and the report input.
- **Capability probe**: `GET /api/ping` returns 204 on `serve.py`, 404 on a
  plain static host. The web app hides all draw tools when the probe fails, so
  static hosting degrades to read-only (query + view scribbles baked into a
  report, no drawing).

### API contract — the scribble message

Posted body and stored line (server stamps `ts`):

```
line  : { "t":"s", "id":<hex8>, "c":<color>, "h":<handle>, "pts":[[lng,lat],...] }
stamp : { "t":"s", "id":<hex8>, "c":<color>, "h":<handle>, "g":<emoji>, "pts":[[lng,lat]] }
erase : { "t":"e", "id":<hex8> }
stored: <one of the above> + { "ts":<unix seconds, server-assigned> }
```

Server-side validation (`valid_scribble`, the trust boundary):
- `id`: string, ≤ 32 chars.
- `t":"e"`: accepted as-is (tombstone).
- `t":"s"`: `c` string ≤ 16 chars; `h` optional string ≤ 24 chars; `pts` a
  list of `[num, num]` pairs, length 1 with a `g` present else 2..2000.
- Request body capped at 64 KB; oversize → 413, malformed/invalid → 400,
  success → 204.

### Identity — self-declared (color, handle)

- A mapper is a `(color, handle)` pair in `localStorage`; there are no
  accounts. Color is the primary visual identity; handle names it.
- Captured in a **first-load modal** (shown only where `/api/ping` succeeds and
  no handle is yet stored): an 8-swatch color palette plus a handle text
  field. Editable afterward from a header identity control.
- Color assignment is **pick-your-own**, seeded to a random palette entry.
  Accepted tradeoff: two mappers may pick the same color; the handle
  disambiguates, and clashes are resolved socially. (An earlier option to keep
  purely-random assignment was rejected because it gave no way to resolve
  collisions and no name.)
- The handle is the only free text in the system, and it is identity, not map
  content — this is what keeps free-text-on-the-map out of scope.

### Modules

- **Scribble reducer** (`web/scribbles.js`, new deep module): pure functions
  shared by the app and the report.
  - `parseScribbles(text) -> strokes[]`: fold the append-only JSONL into the
    set of live scribbles; last write per `id` wins, `t:"e"` removes, bad or
    half-written trailing lines are skipped.
  - `toFeatures(strokes) -> { lines, stamps }`: split live scribbles into a
    line FeatureCollection and a stamp (point) FeatureCollection carrying
    `c`, `h`, and (stamps) `g`.
  - This module is extracted specifically to end the current duplication of
    the reduce logic between the app and the report, and because it holds the
    correctness-critical rules (last-write-wins, tombstones) in a form that is
    pure and unit-testable.
- **Scribble validator** (`valid_scribble` in `serve.py`, deep-ish): pure
  predicate, the POST trust boundary described above.
- **Scribble transport** (thin, in `serve.py` + client): the POST handler with
  locked append, and the client's post/poll loop. I/O-bound; verified live.
- **Draw interaction** (thin, client): pointer/touch handling on the MapLibre
  canvas — pen drags build a line, an emoji tool taps drop a stamp; draw mode
  disables map drag-pan. DOM/map-bound; verified live.
- **Party pad** (`build.sh`): generate a `pad.riseup.net` URL once into
  `web/party.json`, keep it across rebuilds (delete to reset). Surfaced in the
  share panel and the report.
- **Report** (`web/report.html`): reads the same JSONL through the same
  reducer, renders lines + stamps, fits bounds, lists contributors grouped by
  handle (color swatch + count), shows the scribble time span, and prints to
  PDF.
- **Docker run path** (`Dockerfile`): packages an already-built Kit and runs
  `serve.py` on port 8765. The build pipeline still runs outside Docker; the
  container is only the lightweight party server.

### Rendering

- Lines: a MapLibre line layer, `line-color` from the scribble's `c`.
- Stamps: a colored circle (identity ring, `circle-color` = `c`) with the
  emoji rendered as a symbol/text layer on top.
- The app additionally has a draft layer showing the in-progress line while a
  pen stroke is being drawn.

## Testing Decisions

Good tests here assert **external behavior**, not implementation details: feed
inputs, assert outputs, never reach into private state. Per the developer's
decision, only the two pure modules are unit-tested this slice; the transport,
draw interaction, and report rendering are verified live in a real browser
(the project's established practice — headless-Chrome screenshots and DuckDB
baseline matching).

- **Scribble reducer** (`parseScribbles`, `toFeatures`): table-driven cases —
  a single line; last-write-wins when an `id` is re-posted; a tombstone
  removing an existing stroke; a tombstone for an unknown `id` (no-op); a
  half-written trailing line skipped without dropping earlier valid lines; a
  stamp (has `g`, one point) routed to `stamps` while a line routes to
  `lines`; empty input → empty canvas.
- **Scribble validator** (`valid_scribble`): valid line, valid stamp, valid
  tombstone accepted; rejected — missing/oversize `id`, non-string `c`,
  oversize `h`, a line with < 2 points, a stamp with ≠ 1 point, malformed
  `pts` entries, wrong `t`.
- Prior art: the project already verifies the web app end-to-end with headless
  Chrome against DuckDB baselines; the live-verification half of this slice
  follows that pattern (draw a scribble, confirm it renders and syncs to a
  second client, confirm the report shows it).

## Out of Scope

- SliceOSM / area-sized slicing (removed; Geofabrik extracts only).
- Any live data refresh: minutely re-fetch, re-clip, re-bake, hot-swap.
- Hashtag-seeded edit tracking and any live "fixes made" counter.
- Hashtag changeset listing and animated replay in the report.
- Free-text labels on the map (fonts, sizing, wrapping, i18n of user content).
- Accounts, authentication, or server-side identity — identity is
  localStorage-only.
- Scribble editing/moving after creation (only create + erase-own).
- Snapping scribbles to OSM features, shape tools, or per-scribble threads.
- Conflict resolution beyond last-write-wins by `id`.

## Further Notes

- The whole design leans on one property: the room is already on a shared LAN
  with the laptop as hub, so "shared state" needs no new infrastructure — just
  one append-only file and a poll loop.
- Guardrail on truthfulness: the README must not re-promise the killed
  features. The pitch should describe exactly what ships — ask the map, draw
  together, get a report — and nothing more.
- Colour-clash is a known, accepted rough edge; if it bites in practice, the
  cheapest next step is a "this color is taken" hint in the identity modal,
  not automatic assignment.
- `party/` and `web/party.json` are gitignored (per-party runtime state).
