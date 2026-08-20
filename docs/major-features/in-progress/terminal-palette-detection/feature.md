# Terminal palette detection and OSC observation

Status: proposed; Eio scheduling and lifetime boundary settled; remaining
review gates are listed below.

This feature makes terminal palette discovery a renderer-owned capability. It
also exposes the raw OSC observation needed by diagnostics and demos. The
feature is the planned foundation for the OCaml port of
[`vendor/opentui/packages/examples/src/terminal.ts`](../../../../vendor/opentui/packages/examples/src/terminal.ts).

No implementation is part of this record. The API names marked provisional may
change during review, but the reference semantics and ownership invariants in
this document are the behavior this feature is intended to preserve.

## Purpose

The current OCaml port has the useful low-level pieces: it can build palette
queries, parse complete OSC responses, normalize a palette, and route framed
input responses through `Renderer.handle_input`. It does not yet provide the
renderer-level operation that the reference exposes as `getPalette`.

Consequently, a caller cannot currently do all of the following without
reimplementing transport logic outside Core:

- probe whether OSC palette queries are supported;
- issue palette and special-color queries with the reference timeouts;
- observe the raw OSC stream without installing a competing input listener;
- cache and project results for different requested palette sizes;
- invalidate a result safely while a query is still in flight; or
- publish the discovered palette to the native renderer when ANSI256 mapping
  needs it.

The terminal demo must be a consumer of those capabilities, not another owner
of stdin framing, query output, timers, or terminal-specific multiplexing
rules.

## Reference correspondence

| Reference source | OCaml correspondence | Responsibility |
| --- | --- | --- |
| [`terminal-palette.ts`](../../../../vendor/opentui/packages/core/src/lib/terminal-palette.ts) | `packages/opentui-core/src/lib/terminal_palette.ml` and a renderer-owned detection session | Preserve query syntax, response parsing, timeout asymmetry, support probing, and normalization. |
| [`renderer.ts`](../../../../vendor/opentui/packages/core/src/renderer.ts) palette fields and methods | `packages/opentui-core/src/renderer.ml` and `.mli` | Own cache, request coalescing, generation invalidation, lifecycle, and native synchronization. |
| `renderer.ts` `subscribeOsc` and stdin response dispatch | `Renderer_events` plus `Renderer.handle_input` | Fan out each complete OSC response before specialized handlers consume it. |
| `renderer.ts` theme-mode handling | `packages/opentui-core/src/renderer_theme_mode.ml` | Allow theme and palette detectors to observe the same OSC 10/11 response. |
| `renderer.ts` native palette publication | `packages/opentui-raw` checked ABI and the vendored Zig export | Keep the native ANSI256 lookup table synchronized with the detected RGB palette. |
| [`terminal.ts`](../../../../vendor/opentui/packages/examples/src/terminal.ts) | An OCaml terminal demo | Exercise only the public renderer API, including raw OSC diagnostics and special colors. |

The active upstream behavior is defined by the reference implementation and
its palette tests, especially
[`renderer.palette.test.ts`](../../../../vendor/opentui/packages/core/src/tests/renderer.palette.test.ts).
The OCaml implementation may use different internal modules and scheduling
primitives, but it must not silently change the observable detection contract.

## Design principles and ownership

The ownership graph is:

```text
stdin parser
    │ complete framed Response
    ▼
Renderer.handle_input
    ├── raw OSC event source
    ├── palette detection session
    ├── theme-mode detector
    └── capability/pixel handlers

Renderer-owned output queue
    └── palette, theme, and capability queries
```

- `Stdin_parser` remains responsible only for framing. A palette detector does
  not attach a second fd reader or parse arbitrary chunks from the terminal.
- `Renderer` owns the session registry, timers, cache, waiter completion,
  output ordering, and teardown. A session is not process-global.
- `Lib.Terminal_palette` owns response parsing and query construction. It is
  transport-neutral and testable with strings and an injected clock.
- The renderer-facing subsystem is Eio-native. `opentui-core` already depends
  on Eio and exposes Eio runtime concepts elsewhere, so palette continuation
  scheduling does not introduce a generic runtime abstraction solely for
  hypothetical portability. The parser/session kernel remains independent of
  Eio scheduling.
- Raw OSC subscribers receive the complete framed OSC payload before the
  renderer's specialized sequence handlers run. This ordering is observable:
  both palette detection and theme-mode detection must see OSC 10/11.
- All renderer-owned query bytes use the renderer's existing serialized raw
  output path. The demo never writes directly to stdout and never installs a
  competing stdin handler.
- Native palette synchronization is a synchronous, checked raw binding. Core
  retains the logical discovery result; native code remains authoritative for
  the lookup table used while rendering.

## Proposed public API

The exact names are provisional. The public API has two layers over the same
renderer-owned request. `request_palette` is the nonblocking registration
primitive: it returns a waiter immediately and reports completion through a
typed, always-deferred callback. `get_palette` is the Eio direct-style operation
used by ordinary application fibers. It registers the same waiter and suspends
the calling fiber until that waiter completes.

```ocaml
type palette_snapshot = Lib.Terminal_palette.snapshot

type palette_detection_status =
  | Idle
  | Detecting
  | Cached

type palette_waiter

val request_palette :
  t ->
  ?size:int ->
  ?timeout_ms:int ->
  on_result:((palette_snapshot, Error.t) result -> unit) ->
  unit ->
  (palette_waiter, Error.t) result

val get_palette :
  t ->
  ?size:int ->
  ?timeout_ms:int ->
  unit ->
  (palette_snapshot, Error.t) result

val cancel_palette_waiter :
  t -> palette_waiter -> (unit, Error.t) result

val palette_detection_status :
  t -> (palette_detection_status, Error.t) result
val clear_palette_cache : t -> (unit, Error.t) result

val on_osc :
  t -> (string -> unit) -> (Event_subscription.t, Error.t) result

val on_palette :
  t -> (palette_snapshot -> unit) -> (Event_subscription.t, Error.t) result
val once_palette :
  t -> (palette_snapshot -> unit) -> (Event_subscription.t, Error.t) result
val prepend_palette :
  t -> (palette_snapshot -> unit) -> (Event_subscription.t, Error.t) result

val on_palette_error :
  t -> (Error.t -> unit) -> (Event_subscription.t, Error.t) result
val once_palette_error :
  t -> (Error.t -> unit) -> (Event_subscription.t, Error.t) result
val prepend_palette_error :
  t -> (Error.t -> unit) -> (Event_subscription.t, Error.t) result
```

The proposal deliberately separates the existing normalized
`Renderer.palette` value from the raw snapshot returned by discovery and
carried by `on_palette`. The normalized value is the renderer's current
ANSI-oriented rendering state; the snapshot preserves null palette entries and
all special-color fields so diagnostics can distinguish “not reported” from an
actual color. The existing normalized `Renderer_events` palette channel is
replaced rather than retained under the ambiguous `on_palette` name. If a
normalized rendering-state event is later required, it must use an explicit
name such as `on_render_palette_change`.

`Terminal_palette.snapshot` is opaque at the renderer boundary. Accessors
return immutable logical values or defensive copies; the mutable parser array
is never shared with callers or with the cache. This prevents one demo widget
from corrupting a later cache hit while retaining an efficient array internally
for native projection.

The request contract is:

- `size` is a positive value no greater than 256; the default is 16.
- `timeout_ms` must be non-negative and is the hard timeout for each post-probe
  query session; the
  reference default is 5000 ms. The fixed 300 ms support probe is independent,
  so total wall time can exceed `timeout_ms` by the probe window.
- a request may join an existing detection whose size covers it or be fulfilled
  from a cached projection;
- its callback runs at most once with either the completed snapshot or a
  structured deferred `Error.t`; waiter cancellation prevents a later callback
  without cancelling renderer work;
- the callback is always deferred. It never runs on the dynamic call stack of
  `request_palette`, including for cache hits, non-TTY results, and results that
  are already available from a shared detection;
- accepted completions are delivered FIFO in a later renderer-owner dispatch
  turn, after the cache, status, generation, and native state associated with
  that completion have been committed;
- a closed renderer rejects new requests. Closing a renderer with accepted
  waiters completes each uncancelled waiter once with `Error.Closed` through the
  same deferred path, so `get_palette` cannot remain suspended;
- a cache hit is observable as `Cached` before its deferred callback runs; and
- request validation failures are returned by `request_palette`. Failures after
  it returns—including capability-wait, query-output, timer/session, and
  required follow-up failures—complete that request with `Error.t`. Unsupported
  and non-TTY terminals, timeouts with partial data, and malformed responses
  remain successful snapshots with null fields. Request-owned failures are not
  also emitted as palette-error events. Detached native refresh work uses
  `on_palette_error` instead of leaving an internal request unresolved or
  converting its failure into an all-null snapshot.

Every accepted request requires the renderer's Eio owner dispatcher. A
renderer constructed without that application-owned lifetime returns
`Error.Missing_async_lifetime` before accepting a waiter. A fresh TTY detection
additionally requires a clock; without one it returns `Error.Unsupported`.
Cached and known non-TTY results do not require elapsed-time scheduling, but
they still cross the owner dispatcher and remain deferred.

A first request on a known non-TTY renderer enters `Detecting` before returning
its waiter, then commits and caches the all-null snapshot in the later owner
turn that queues completion. This matches the reference async state transition
without allocating a timer or writing output. Later requests observe the
result as an ordinary `Cached` hit.

`get_palette` allocates one Eio promise, calls `request_palette`, and awaits the
promise. It does not own detection or change callback order. If its fiber is
cancelled, it cancels only its waiter and re-raises the Eio cancellation; the
shared renderer detection continues. Thus a cache hit cannot make
`get_palette` return before the registration turn has completed, and ordinary
application code gets the same usage flow as upstream `await
renderer.getPalette(...)`.

The direct-style operation crosses at least one Eio scheduling boundary for
every result returned to an ordinary application fiber. If `request_palette`
rejects admission synchronously—for validation, closed renderer, missing
runtime, missing clock, or wrong owner domain—`get_palette` performs an
`Eio.Fiber.yield` before returning that structured error. This preserves the
upstream rule that an early throw from the async `getPalette` body is observed
as a later Promise rejection. The callback registration primitive retains
synchronous admission errors because its return value says whether a waiter
was accepted.

Renderer event, observation, and waiter callbacks are synchronous owner
callbacks. They must not suspend either the terminal-input dispatch fiber or
the continuation-driver fiber. Code running in one of those callbacks uses
`request_palette` and returns; it must not call `get_palette` directly. This
distinction is necessary because Eio suspends the current fiber, whereas
JavaScript `await` returns control to a process-wide event loop. The callback
primitive preserves upstream progress without forking each event callback or
weakening event ordering. The renderer tracks synchronous callback depth and
`get_palette` returns a dedicated structured callback-context error in that
context, rather than allowing a request to wait for work driven by the fiber it
suspended. This forbidden-context error is necessarily immediate because
yielding from that callback is the invalid operation being prevented.

`on_osc` is an observation API, not an input-ownership API. Subscription
callbacks are synchronous in the renderer owner context, use the ordinary
subscription cancellation rules, and receive the complete OSC frame as a
string. The renderer does not retain subscriber-owned data after the callback.
It has a dedicated exception boundary: an exception from one observer is
recorded, remaining raw observers still run, and palette/theme internal
handlers still receive the frame. Internal state changes are committed before
any palette event or waiter continuation is delivered. Theme notifications run
before palette notifications, palette events run before request continuations,
and independent waiter continuations cannot starve one another. After the
complete dispatch batch, the first callback exception and its backtrace are
reported to the application callback-failure supervisor. This preserves
ordinary callback failure visibility without killing the terminal-input fiber
or allowing a diagnostic observer or palette consumer to starve protocol
handling. The supervisor initiates the orderly renderer-close and dispatcher
flush path before re-raising the saved exception from the application control
fiber.

`clear_palette_cache` invalidates future cache use but does not erase the
currently published normalized/native palette. A new request is required to
replace that state, matching the reference's invalidation behavior.

`palette_detection_status` gives `Detecting` precedence over `Cached`: an
outstanding detection reports `Detecting` even when an older cache entry exists.
Otherwise, any cache entry, including a memoized projection, reports `Cached`.
It describes renderer work, not an individual waiter, so cancelling a waiter
does not change the status. As upstream, requests still waiting for the
XTVERSION capability window report `Idle`; the status changes to `Detecting`
only when support probing begins.

## Detection semantics

### Support probe

Every fresh detection begins with the reference OSC4 support probe:

```text
ESC ] 4;0;? BEL
```

The probe has a 300 ms deadline. A matching OSC4 response establishes support;
silence or an unsupported terminal produces an all-null snapshot, which is
still a successful cached result rather than an exception. The probe is not
reused as a permanent process-global capability flag: a fresh detection after
cache invalidation probes again.

### Palette and special-color queries

After support is established, palette entries and special colors are queried
concurrently as two independent sessions. Each session has its own response
buffer, pending values, idle timer, and early-completion rule. The requested
palette indices are `0` through `size - 1`. The special query preserves the
reference fields and index mapping:

| OSC index | Snapshot field |
| ---: | --- |
| 10 | `default_foreground` |
| 11 | `default_background` |
| 12 | `cursor_color` |
| 13 | `mouse_foreground` |
| 14 | `mouse_background` |
| 15 | `tek_foreground` |
| 16 | `tek_background` |
| 17 | `highlight_background` |
| 19 | `highlight_foreground` |

Each post-probe session has two completion rules:

- its hard timeout starts when that session is issued; and
- the idle timeout, default 300 ms or the `OTUI_PALETTE_IDLE_TIMEOUT_MS`
  environment setting, bounds a silent response period.

The support probe always uses its own fixed 300 ms deadline. It is not
shortened by `timeout_ms`.

The reference's timeout asymmetry is intentional and must be preserved:

- any complete OSC frame delivered by the shared raw-OSC source resets the
  palette query's idle timer, even if the frame is unrelated to a requested
  palette index or special color;
- the special-color query resets its idle timer only when a recognized special
  field—OSC 10 through 17 or 19—is actually updated. Under tmux, early
  completion requires only the queried OSC 10, 11, and 12 fields, but an
  unsolicited recognized OSC 13 through 17 or 19 response still updates the
  snapshot and resets the idle timer. This is a reference quirk.

Non-OSC input—keys, mouse events, paste, CSI responses, and other parser
traffic—is not delivered to this detector and does not reset either idle
timer. This preserves the reference's OSC-source boundary while still making
unrelated OSC traffic an observable reset for the palette session.

The query completes early when all requested values are present. On timeout,
already parsed values are retained and missing values remain `None`; the
result is not discarded merely because the terminal omitted part of the
response.

The parser's response buffer is bounded. If a detector buffer exceeds 8192
bytes, it is trimmed to the most recent 4096 bytes before further scanning.
This prevents a noisy or malformed terminal response from growing renderer
state without changing the normal framed-input path.

The recognized color payloads remain the reference forms: `rgb:` components
and six-digit `#rrggbb`. An `rgba:` response is preserved for raw diagnostics
but is not treated as a parsed color; the demo may report that it saw an
unparsed response.

### Multiplexers and remote terminals

The query builder follows the reference's terminal transport rules:

- for a terminal name containing `tmux` whose version compares below `3.6`
  using the reference's lexicographic `localeCompare` rule, OSC4 is wrapped
  in tmux DCS passthrough;
- special-color queries under tmux use indices 10, 11, and 12 and are not
  wrapped;
- when the multiplexer is exactly `tmux` and the terminal name is not exactly
  `tmux` with a known non-empty version, palette detection waits for the
  XTVERSION capability window before deciding how to encode the query; and
- remote mode does not independently bypass that wait. The exact capability
  predicate, rather than a remote/local shortcut, determines the behavior.

The lexicographic version comparison and the different `includes("tmux")`
versus exact-name predicates are reference quirks. They are specified here for
parity; changing either to numeric comparison or one unified predicate would
be a deliberate API divergence requiring separate review.

The renderer uses the existing `Terminal_capabilities` snapshot and its
capability-detection lifecycle. It does not infer multiplexer behavior from
the demo or from process environment strings. Cache lookup, the post-XTVERSION
re-check, and session registration happen without suspension in the renderer
owner context, so two callers cannot both start a detector after observing an
empty cache.

## Cache, concurrency, and invalidation

The cache is keyed by palette size and stores raw snapshots. A request for a
size already covered by the smallest cached size greater than or equal to the
requested size is fulfilled by projection and that projection is memoized.
Special colors are copied unchanged by projection.

In-flight requests follow the reference coalescing rules:

- a request whose size is less than or equal to an in-flight detection joins
  it. Its own `timeout_ms` does not become a personal deadline; the detector
  starter's timeout controls that shared result;
- a larger request does not cause the current detector to restart; it waits for
  the current result and then starts the missing larger detection with its own
  timeout if no newly cached result covers it. Time spent waiting for the first
  detector does not consume the follow-up detector's timeout; and
- concurrent callers each receive one completion, even when they share a
  detector or a projected cache entry.

If the active detector fails, every uncancelled request waiting on that
detector—including larger requests that had not yet started their follow-up—is
completed with the same structured error. No follow-up detector starts from a
failed prerequisite. This matches rejection propagation through the reference
shared Promise.

Waiters resume in registration order. When several larger waiters remain after
a detector completes, the first waiter not covered by the cache starts the next
detector; later waiters either join it or remain queued according to the same
size rule. This preserves the reference Promise-continuation ordering without
allowing two detectors to start in the owner context.

`cancel_palette_waiter` is deliberately waiter-local. It marks that waiter
cancelled and suppresses its queued or future continuation, but it never aborts
the XTVERSION capability wait, support probe, palette query, special-color
query, or a detector shared by other callers. The renderer operation exists as
soon as the first request is accepted, even if it has not advanced past the
capability preflight. When every waiter cancels during that preflight, its
eventual resolution still starts detection and may populate the cache, emit
`on_palette`, synchronize native state, and transition the renderer to
`Cached`. Only renderer teardown disposes the preflight continuation, detector
sessions, and timers. This is the OCaml equivalent of abandoning an upstream
Promise without changing the renderer work behind it.

Cancellation remains valid for an accepted waiter after renderer close and is
idempotent after readiness, delivery, or an earlier cancellation. It therefore
wins cleanly against a queued `Error Error.Closed` completion and does not
return `Error.Closed` merely because the owning renderer has begun teardown.
Owner mismatch and wrong-domain use still return their structured errors.

`clear_palette_cache` advances a generation, clears cached entries, and
invalidates the projection map. A result from an older generation may still
repopulate the cache for the detector that produced it, but it must not emit a
stale palette event or publish stale native state after invalidation. If a
theme change clears the cache while a detection is in flight, the reference
refresh may join that still-in-flight detection; the old-generation result
then repopulates the cache but fails the detector generation guards for event
emission and native publication. The detached refresh captured the generation
after the clear, however, so its continuation still requests a repaint when
the joined operation settles. This somewhat surprising split behavior is part
of the parity contract and needs an explicit race test.

Renderer destruction applies the same generation guard, disposes detector
timers and subscriptions, and prevents further output or publication. Before
the renderer releases its Eio dispatcher lease, every accepted uncancelled
waiter is moved to the deferred completion queue with `Error Error.Closed`.
Cancelled waiters remain silent. The vendored reference cleanup only removes
timers and subscriptions; when destruction catches an actively suspended
query, it does not necessarily resolve its Promise. Deferred
`Error Error.Closed` is therefore an intentional stronger OCaml liveness
guarantee rather than result-value parity: every accepted OCaml request settles
or is explicitly cancelled.

### Palette event channel

`on_palette` matches the reference `PALETTE` event. Its payload is the raw
snapshot produced by a fresh detector completion, including null and partial
fields. It fires only for a fresh detection accepted into the current
generation, never for a cache hit or projection, and is deduplicated using the
reference signature over the normalized 256-entry palette plus default
foreground and background. Changes only to cursor, mouse, Tek, or highlight
colors therefore do not emit this event or advance the native epoch.

The event is suppressed for results from an invalidated generation. Cache
publication and native synchronization remain internal renderer work; a
subscriber cannot prevent them by declining to observe an event. The
`on_palette` listener count is the only palette-subscriber count used by the
lazy theme/startup refresh policy. `on_osc` does not implicitly request a native
size-16 refresh. A separate lossless fresh-snapshot event is not part of this
feature: request callbacks observe their requested snapshot, while `on_osc`
provides lossless protocol diagnostics.

As in the reference, the emitted signature advances only when `on_palette`
actually has a listener and emits. An unobserved fresh detection does not
prevent the same palette from being delivered after a listener is later added
and a new detection completes.

`on_palette_error` reports failures from detached native-refresh work that has
no caller waiter. Request-owned failures are delivered only through that
waiter's result callback. The error channel does not turn unsupported
terminals, timeouts with partial data, or malformed responses into errors.

## Theme and native rendering integration

The existing theme-mode detector currently recognizes OSC10/11 but its query
must be emitted through the same renderer-owned output queue. Palette and theme
observers must receive each framed OSC response before either specialized
handler consumes it. Theme changes clear palette cache and trigger a fresh
palette request only when native synchronization is needed or the existing
raw-snapshot `on_palette` channel has a subscriber, matching the reference's
lazy refresh policy. `on_osc` subscribers do not change that predicate. A
detached refresh reports output/timer/session failures through
`on_palette_error`.

When the detected terminal uses ANSI256 color mapping and is not in RGB mode,
Core publishes a normalized 256-entry table to the native renderer after a
successful detection covers at least 16 palette entries. The normalized table
merges detected entries over the fallback ANSI256 table and includes the
detected default foreground/background. A smaller request schedules a fresh
size-16 detection when no cached size-16 result exists. Native synchronization
is skipped when the renderer does not need the table, preserving the
reference's `ansi256 && !rgb` gate.

Ordering is enforced by the single renderer owner context and the publish
generation guard, not by the native epoch. The epoch is a native-side
invalidation token whose incrementing and 32-bit wrap behavior must match the
reference; it forces native repaint/index-cache invalidation when the
normalized signature changes.

This requires a checked binding for the vendored native
`rendererSetPaletteState` export. The change crosses:

- `packages/opentui-raw/native/opentui_abi.h` and `raw_stubs.c`;
- the OCaml raw renderer binding and its `.mli`;
- the native ABI probe/build declarations; and
- Core's renderer state, signature, and generation handling.

The ABI must validate palette length and channel representation at the C
boundary. OCaml must pass temporary color storage only for the duration of the
synchronous call; native code must not retain an OCaml pointer.

## Demo contract

The OCaml terminal demo will match the reference's user-visible behavior
without owning transport details:

- request an initial 16-entry palette;
- accept a validated requested size from 1 through 256;
- `R` clears the cache and performs a fresh request;
- `C` clears the cache without issuing a request;
- display palette cells using the reference's `#000000` fallback for null
  entries;
- display all special colors, using `N/A` for unavailable special values;
- show theme, inferred background, RGB detection, cache status, and timing;
- show the last eight relevant raw OSC observations through `on_osc`, filtered
  to OSC4 index 0 and OSC10/11; and
- cancel subscriptions and outstanding waiters before renderer teardown.

The application harness must enable the capability-probe phase when running
this demo. It must not add a direct stdin listener or write escape sequences
outside the renderer output owner.

## Deliberate OCaml API differences

The following differences are intentional parts of the OCaml contract. Some
translate the implementation model without changing behavior; the observable
hardening and liveness differences are called out explicitly:

- JavaScript Promises become an Eio direct-style `get_palette` operation backed
  by a deferred callback plus waiter handle. The callback is never inline: even
  cache hits cross a later owner dispatch turn, so `get_palette` cannot resume
  during request registration and preserves the upstream Promise ordering
  relied on by higher-level consumers. Synchronous renderer callbacks use the
  nonblocking `request_palette` layer because suspending the terminal-input
  dispatch fiber would prevent it from processing the palette response.
- Node `stdin`/`stdout` streams become `Renderer.handle_input` and the existing
  serialized renderer output queue. This preserves ordering and makes Eio
  terminal ownership explicit.
- JavaScript exceptions at the API boundary become structured `Error.t`
  results. Callback exceptions are isolated long enough to finish the active
  batch, then retain fatal visibility through supervised application shutdown.
- OCaml validates `size` in the public API as `1 <= size <= 256`; the
  reference forwards arbitrary sizes to its detector. The bound prevents
  unrepresentable native state and is an intentional hardening divergence.
- OCaml rejects a negative `timeout_ms` with `Error.Invalid_argument`; the
  reference forwards it to its timer runtime. Zero remains valid. This is an
  intentional validation divergence rather than a timeout semantic to copy.
- The reference detector class is split into a parser/session module and a
  renderer coordinator. The split is an ownership improvement, not a change
  to query or timeout behavior.
- The reference has no per-request abort operation. `cancel_palette_waiter` is
  an additive callback-lifetime operation: it detaches only that waiter and does
  not cancel renderer detection, cache publication, events, or native state.
  It is idempotent and returns success after delivery or repeated cancellation.
- Reference OSC subscriber iteration can be interrupted by a throwing
  subscriber before later observers or specialized protocol handlers run.
  OCaml deliberately isolates each raw observer, finishes protocol handling,
  and sends the first exception to supervised application shutdown. This
  protects palette and theme progress while retaining failure visibility.
- Reference detector cleanup can leave an actively suspended Promise pending
  after renderer destruction. OCaml instead completes every accepted
  uncancelled waiter with `Error Error.Closed`, because detector resources and
  output are no longer usable once Core crosses its owner-lifetime boundary.
  This is an intentional stronger liveness guarantee.
- The reference rejects palette detection while explicitly suspended. The
  current OCaml renderer has no equivalent suspend lifecycle; until one is
  added, the feature must report this as a documented unsupported state rather
  than claiming full suspend parity.

These differences are not intended to add compatibility shims for obsolete
OCaml shapes. `Renderer.palette` remains the normalized rendering-state getter,
while `on_palette` is redesigned to carry the reference-shaped raw discovery
snapshot. No normalized event is retained under the same name.

## Non-goals

- Entering or leaving the alternate screen, enabling raw input, or otherwise
  taking terminal-session ownership from the Eio terminal-session boundary.
- A process-global palette cache or a second input reader.
- Guessing colors from terminal names when OSC detection is unavailable.
- Treating malformed or partial terminal responses as fatal renderer errors.
- Implementing the rest of `terminal.ts` (framebuffer drawing, ANSI comparison,
  or demo layout) before the Core capability is accepted.
- Porting the reference TypeScript class hierarchy or Promise lifecycle
  literally.

Non-TTY input or output is not an error. When the terminal-session owner marks
either side as non-TTY, the detector returns a cached all-null snapshot without
writing probe or query bytes. The TTY fact must be supplied by the terminal
owner; Core must not guess it from a process-global fd or from the demo.

## Verification plan

The implementation is complete only when these observable contracts have
evidence:

- parser tests cover valid RGB and `#rrggbb` responses, nulls, partial frames,
  buffer trimming, requested index limits, all special fields, and complete
  versus incomplete results;
- manual-clock session tests cover the 300 ms support probe, 5 s hard timeout,
  300 ms idle timeout, independent palette/special buffers and timers, probe
  versus query-timeout interaction, timeout asymmetry, early completion,
  unrelated-OSC versus non-OSC idle resets, unsolicited recognized tmux
  special-color resets, cancellation, and late input after disposal;
- renderer input/output tests prove raw OSC fanout ordering, one serialized
  query owner, tmux query selection, the exact XTVERSION-wait predicate for
  remote and local owners, theme/palette sharing, deferred callback delivery,
  FIFO completion ordering, `get_palette` registration-before-resumption,
  deferred direct-style validation, closed, missing-runtime, missing-clock, and
  wrong-domain errors,
  application-fiber cancellation detaching only its waiter, rejection of
  direct-style waiting from a synchronous renderer callback, dispatcher flush
  during renderer teardown, owner-domain enforcement, supervised callback
  failure with a reentrant later batch, theme-event/palette-event/request-callback order,
  and that a throwing raw OSC observer or palette consumer cannot prevent
  internal palette/theme handlers from running;
- cache tests prove exact hits, larger-cache projection, concurrent same and
  different sizes and timeouts, detector-timeout inheritance, follow-up
  requests, status transitions, reference-shaped deduplicated raw events,
  status precedence, zero query writes and no clock advancement on cache hits,
  clear-generation races (including theme-clear during an in-flight detection),
  subscriber-count refresh policy, the stale-detector/joined-refresh repaint,
  sole/shared/all-waiter cancellation, all-waiter cancellation during the
  XTVERSION preflight,
  continued publication after every waiter cancels, deferred request errors,
  detached-refresh errors, deferred `Error.Closed` completion for destruction
  during each active session phase, and destroy cleanup;
- environment tests prove `OTUI_PALETTE_IDLE_TIMEOUT_MS` is registered,
  parsed once by the environment store, and applied to both query sessions;
- non-TTY tests prove that a first request reports `Detecting` until its
  deferred all-null commit, that later requests report `Cached`, and that
  support, palette, and special queries produce no output; and
- native binding tests prove the ABI layout, palette length/channel conversion,
  normalized-256 publication threshold, epoch invalidation, closed-renderer
  behavior, and the ANSI256/RGB synchronization gate; and
- a terminal or PTY integration test, where the test environment permits it,
  proves that the demo displays real responses without direct transport hooks.

The host-level checks should remain black-box tests of renderer behavior. Pure
parser/session tests may use injected strings and a manual clock because those
are deterministic seams, not alternate production transports.

## Efficient OCaml implementation shape

Palette discovery is terminal-latency work, not a frame-hot-path service. The
implementation should optimize ownership clarity and bounded allocation before
introducing more scheduling machinery than the reference semantics require.

### Eio owner dispatcher and deferred continuations

The renderer owns one FIFO of ready palette waiter completions and one
`completion_drain_scheduled` bit. Enqueuing the first completion requests one
later owner turn; subsequent completions append to the same queue without
scheduling another wakeup. The drain detaches the current FIFO before invoking
user code, so reentrant requests append to a later batch. Waiters are marked
delivered before their callback runs. A cancelled waiter remains a cheap inert
entry if it was already queued.

The wakeup is supplied by an Eio-native owner dispatcher with the contract that
a submitted callback cannot run inline and runs on the renderer's owner domain.
It is separate from elapsed-time measurement: using a timer as an implicit
microtask queue would make Promise-like ordering depend on clock implementation
details. The standard runtime starts one persistent driver fiber on the
application's outer switch. A same-domain FIFO and `Eio.Condition` wake that
fiber only when work becomes available; it drains a detached batch before
waiting again. It does not fork a fiber for each waiter or completion batch.

Dispatcher creation records `Domain.self ()`. Lease acquisition, submission,
flush, and close compare the current domain explicitly and return a structured
wrong-domain error before touching mutable state. The renderer-facing palette
operations—including response handling that advances a palette session—apply
the same check and return `Error.Wrong_domain`. Eio fibers on the owner domain
may interleave at suspension points, but dispatcher and renderer mutations do
not suspend and therefore remain atomic with respect to one another.

The dispatcher is application-owned and must outlive every renderer lease. It
must not belong to `Renderer_scheduler`: application shutdown stops that
scheduler before closing the renderer, while accepted palette waiters still
need deferred `Error Error.Closed` delivery. Attaching a renderer acquires a
dispatcher lease. `Renderer.close` first makes the renderer unavailable,
cancels detector resources, enqueues closed results for accepted waiters, and
then releases the lease. The application flushes the continuation FIFO before
closing the dispatcher and its outer switch. Dispatcher shutdown rejects new
leases and submissions but cannot complete while a renderer lease or queued
batch remains.

The standard Eio renderer-construction path takes the owner dispatcher
explicitly and acquires its lease before returning the renderer. Low-level
renderer constructors may omit that application lifetime for headless parsing
and synchronous rendering, but palette requests on such a renderer fail with
`Error.Missing_async_lifetime`; they never install an implicit dispatcher.

The standard shutdown order is therefore:

1. stop `Renderer_scheduler` and other producers;
2. close the renderer, enqueueing accepted waiter completions;
3. await the dispatcher's Eio-promise-backed `flush` barrier;
4. close the dispatcher after its final lease is released; and
5. restore the terminal, then re-raise any supervised callback failure before
   releasing the outer application switch.

Shutdown performs the renderer-close and flush sequence inside an Eio
cancellation-protected region so cancellation cannot strand an accepted
waiter. `flush` becomes ready only when both the shared FIFO and every detached
in-progress batch are empty; callbacks that enqueue a later batch extend the
same barrier.

The persistent driver never terminates merely because a user callback raises.
It records the first exception and raw backtrace, finishes the current batch,
and reports it to a small application-owned failure supervisor shared with the
synchronous input/event callback boundaries. The supervisor stores the first
exception and raw backtrace, exposes a promise that wakes the application
control fiber, and retains the value for cleanup paths that were already in
progress when the failure occurred. The control fiber stops producers and
closes renderers while the driver continues accepting teardown completions and
draining subsequent batches. Cleanup always checks the supervisor after flush,
closes the dispatcher, restores the terminal, and then re-raises the saved
exception with its backtrace. Later callback failures may be retained for
diagnostics, but they do not replace the first propagated failure or starve
accepted waiters.

There is one persistent driver fiber, FIFO, condition, and flush barrier per
application dispatcher, not per waiter. Callback-style waiters allocate no
fiber, promise, timer, mutex, or condition variable. Each active direct-style
`get_palette` call adds exactly one Eio promise. Because renderer mutations are
owner-domain-local and individual operations do not suspend, queue mutation,
waiter state changes, cache lookup, and detector selection require no locks or
atomics.

### Waiters and shared detector state

A waiter contains an owner identity, monotonically increasing registration id,
requested size and timeout, callback, and mutable state:

```ocaml
type waiter_state =
  | Waiting
  | Ready of (palette_snapshot, Error.t) result
  | Cancelled
  | Delivered
```

Cancellation changes `Waiting` or `Ready` to `Cancelled` in constant time. It
does not remove list nodes from an active detector and therefore cannot make
shared-session mutation quadratic. Cancelled entries are discarded when the
detector partitions its waiter list or when the completion FIFO drains. Owner
identity makes passing a waiter to a different renderer a structured invalid
argument without structural or polymorphic comparison.

The renderer has at most one active detector, matching the reference. Its
record contains the requested size, starter timeout, cache generation, support
probe state, palette and special-color branches, and registered waiters. After
completion, one forward pass partitions waiters into covered completions and
larger pending requests. The first remaining waiter in registration order may
start the next detector; later waiters join or remain pending by size. This
implements Promise coalescing without one continuation chain or intermediate
closure per size relationship.

### Cache and snapshots

Because valid sizes are the closed range 1 through 256, the cache can be a
257-element `palette_snapshot option array`. Exact lookup is constant time;
finding the smallest covering entry is a bounded forward scan of at most 256
slots. A projected snapshot is memoized in its exact slot. This is simpler and
cheaper than a general map for the fixed domain.

Snapshots own their palette storage. The detector transfers or copies its
bounded result into an immutable snapshot once at completion; projections copy
only the requested prefix and share immutable special-color strings. Public
array accessors return a defensive copy, while indexed accessors avoid copying
for demos and ordinary consumers. Normalization writes directly into a fresh
256-entry `Rgba.t array` used for signature calculation and the synchronous
native call.

### Session state and timers

The support probe and the two post-probe branches are explicit state machines
driven by framed OSC input and clock callbacks. Each live branch owns one hard
timer and at most one idle timer. Resetting an idle timer cancels and replaces
that single token. The clock runtime may use a lightweight timer fiber, but the
palette layer creates no session fiber and keeps only a constant number of live
timer tokens independent of waiter count. Completion cancels all branch timers
before producing renderer effects.

Response storage is bounded to the documented 8192/4096 limits. A growable
buffer or byte window may be reused within one detector, but mutable storage is
never published in a snapshot. Parsing remains loop-based and typed; no regular
expression runtime, `Str`, `Obj`, polymorphic structural comparison, or catch-all
exception boundary is needed.

### Commit and notification order

An OSC owner turn has two phases. First, raw observers run under the dedicated
exception boundary and the palette and theme state machines consume the frame.
The renderer then commits cache, status, generation, normalized/native state,
and repaint effects without invoking user code. Second, it delivers theme
events and `on_palette`; request results are appended to the deferred
continuation FIFO and therefore run only in a later owner turn. Channel-level
callback exceptions are recorded so later internal work and independent waiter
continuations remain live, then the first exception is reported to the
application callback-failure supervisor for orderly shutdown and later
re-raising.

Detached native refresh uses the same detector and cache machinery but has no
waiter callback. Its failure is emitted once through `on_palette_error`. A
request-owned failure is queued only to that request's waiters, avoiding double
reporting and extra event allocation.

## Implementation phases and review gates

Implementation should be split so each semantic boundary can be reviewed:

1. **Parser/session kernel.** Extend `Lib.Terminal_palette` with support-probe,
   concurrent-query, timeout, tmux, and completion state without connecting a
   second stdin reader.
2. **Renderer coordinator and Eio dispatch.** Add the application-owned Eio
   dispatcher, domain checks, leases, flush barrier and callback-failure
   supervisor, raw OSC fanout, owner-deferred continuations, the direct-style
   operation, renderer-owned sessions, cache/projection, request coalescing,
   generation invalidation, status, lifecycle completion, and serialized query
   writes.
3. **Theme integration.** Emit the existing theme query through the renderer
   output owner and ensure palette/theme handlers share each framed response.
4. **Native synchronization.** Add and verify the checked palette-state ABI,
   then connect epoch-guarded ANSI256 publication.
5. **Demo port.** Rebuild `terminal.ts` against the high-level API only, with
   no demo-specific transport seam.

Before phase 1, review must settle the opaque snapshot accessors, the TTY fact
supplied by the terminal owner, and whether the renderer needs an explicit
suspend state for parity. Phase 2 creates the Eio dispatcher at the start of
the standard application's outer switch, before renderer construction, and
closes it during cleanup after renderer close and dispatch flush. Renderer
construction acquires the lease explicitly. The reference's lexicographic tmux
comparison and separate terminal-name predicates must also be either preserved
or recorded as intentional fixes. Before phase 4, review
must confirm that native synchronization is a release requirement rather than
an optional optimization; reference parity argues that it is required for the
full feature. The demo is not to be committed until its behavior has been
manually reviewed.

## Acceptance criteria

This record moves to `docs/major-features/implemented/terminal-palette-detection/`
only when:

- the renderer owns all palette query input/output, timing, caching, and
  teardown;
- the externally visible query, timeout, tmux, null-value, cache, and
  invalidation semantics match the reference tests;
- palette request callbacks are never inline and remain FIFO under coalescing;
  every ordinary-context `get_palette` result crosses an Eio scheduling
  boundary, cancellation detaches only its waiter, and renderer teardown cannot
  introduce a lost wakeup or hang;
- the application-owned Eio dispatcher outlives its renderer leases, flushes
  accepted and reentrantly enqueued completions before shutdown, enforces its
  owner domain, survives callback failure until supervised cleanup completes,
  and is independent of `Renderer_scheduler` lifetime;
- non-TTY and suspended-renderer behavior is either implemented and tested or
  explicitly recorded as a bounded API divergence;
- theme mode and raw OSC observers receive shared responses in the documented
  order;
- native ANSI256 palette state is synchronized with a checked, lifetime-safe
  ABI; and
- the OCaml terminal demo exercises the complete capability without reaching
  into parser internals or terminal file descriptors.
