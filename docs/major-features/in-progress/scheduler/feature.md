# Renderer scheduler

Status: in progress.

This feature defines the Eio-owned timing and frame-driving boundary for one
renderer. It turns coalesced render requests and live-render ownership into
actual frame attempts, supplies cancel-safe owner-domain timers, and adapts an
Eio monotonic clock to the existing `Lib.Clock` capability.

The scheduler is intentionally separate from the
[`background`](../background/feature.md) CPU-job feature. Scheduler callbacks
and frames run on the renderer's Eio domain. Background work runs on reusable
executor domains and returns to an owner-domain handler before it may request
a frame.

## Purpose

The retained renderer records coalesced render requests and aggregate live
counts. The caller-run scheduler now consumes them through the Eio clock
adapter. The scheduler-dependent reference behavior covered here includes
scrollbar arrow repetition, ScrollBox edge auto-scroll, live-frame updates,
theme-query timeouts, and ordered post/console rendering. Animation remains
outside this feature and has no pre-render driver registry.

The scheduler closes those gaps without making `Renderer.render` asynchronous
or teaching pure renderables about Eio resources.

## Reference correspondence

| Reference source | Planned OCaml correspondence | Responsibility |
| --- | --- | --- |
| `vendor/opentui/packages/core/src/renderer.ts` render loop | `packages/opentui-core/src/platform/eio_runtime/renderer_scheduler.ml` | Consume render requests, drive live frames, measure frame deltas, and stop under structured Eio cancellation. |
| `vendor/opentui/packages/core/src/lib/clock.ts` | `packages/opentui-core/src/platform/eio_runtime/eio_clock.ml` and existing `src/lib/clock.ml` | Adapt Eio monotonic time and cancel-safe one-shot timers to the portable clock capability. |
| `vendor/opentui/packages/core/src/Renderable.ts` live propagation | existing `Renderable` and `Render_context` live-count state | Wake the scheduler on inactive-to-live transitions and continue frames while live ownership remains positive. |
| `vendor/opentui/packages/core/src/renderables/ScrollBar.ts` | `Renderables.Scroll_bar` | Schedule press-and-hold delay/repetition and cancel it on release, destruction, or loss of interaction. |
| `vendor/opentui/packages/core/src/renderables/ScrollBox.ts` | `Renderables.Scroll_box` and renderer selection routing | Acquire live ownership while edge auto-scroll is active and update from measured frame deltas. |
| `vendor/opentui/packages/core/src/renderer-theme-mode.ts` | existing `Renderer_theme_mode` | Use the Eio-backed injected clock for refresh and waiter timeouts. |
| `vendor/opentui/packages/core/src/post/effects.ts` | existing `Post.Effects` and renderer post-process callbacks | Receive measured deltas during frames while an explicit live owner keeps the loop active. |
| `vendor/opentui/packages/core/src/animation/Timeline.ts` | future animation engine | Attach to the same pre-render frame-driver seam described by the animation feature, without moving timeline evaluation into this module. |

## Current boundary

`Renderer.request_render` sets a coalesced Boolean in `Render_context`.
`Renderer.request_live` increments a live count and also records a render
request. `Renderer.render` is an explicit synchronous frame operation and
accepts a caller-supplied delta. Those remain useful portable primitives.

The scheduler now installs a private owner-local notification callback on the
context. The runtime `Wakeup` module remains paired with terminal
`Event_queue` and is deliberately single-domain; scheduler wakeups do not
overload terminal-event queue semantics.

`Renderer.create_with_clock` supplies an optional clock to both theme-mode
state and the render context. `Renderer.create` has no clock capability and
does not fabricate a manual clock whose time never advances. Deterministic
manual timing is explicit at construction, while real-system timing is
provided by `Eio_clock`.

## Active design

### Ownership

One scheduler belongs to one running renderer and one Eio switch. Its frame
loop, timer callbacks, render completion, renderable mutation, event emission,
and terminal-facing renderer calls all execute on the domain that created and
runs it.

The scheduler does not own the application's executor pool, terminal input
reader, terminal session, or output flow. An application composes those Eio
fibers under a surrounding switch. Cancellation of that switch stops the
scheduler and prevents later timer callbacks.

`Renderer.t`, `Render_context.t`, the retained tree, Yoga nodes, buffers, and
native handles remain single-domain values. Scheduler ownership is an
execution convention and API boundary, not a claim that these types become
synchronized.

### Portable scheduling capability

`Lib.Clock.t` remains the capability exposed to owner-local services and
renderables. The Eio adapter implements:

- `now` from `Eio.Time.Mono.now`, converting the returned `Mtime.t` timestamp
  to seconds relative to the adapter's creation timestamp;
- one-shot `schedule` by forking a timer fiber under the scheduler switch; and
- `cancel` by resolving a timer-local cancellation signal so a sleeping timer
  becomes inert promptly.

Each timer has one opaque `Lib.Clock.timer` identity. The external adapter
seam is limited to `Lib.Clock.fresh_timer` and `Lib.Clock.equal_timer`;
implementations do not depend on the identity representation. Cancellation is
idempotent. A callback is invoked at most once and only on the scheduler
domain. A callback that cancels itself or another timer is safe. Scheduler
shutdown cancels all outstanding timers before renderer-owned state is
destroyed.

The current manual clock remains the deterministic test implementation and
obeys the same callback and idempotent-cancellation contract. Repeating
behavior is composition: a callback schedules its next one-shot timer only if
its owner remains active. `Lib.Clock` does not gain a second interval type.

Normal `Render_context` values expose the renderer's optional `Lib.Clock.t`
capability through a typed accessor. A manually driven renderer may be created
with an explicit manual clock. A renderer without a clock reports the absence
structurally to code that requires scheduling; it does not manufacture a
manual clock whose time never advances.

### Render-request wakeup

The renderer context stores an optional owner-local wake callback installed by
the scheduler runtime. The callback contains no render operation. It only
increments or signals a scheduler revision.

The context invokes that wake callback when:

- a render request changes from absent to pending;
- live ownership changes from zero to positive; or
- live ownership reaches zero; or
- scheduler-facing state requires an immediate reconsideration of the loop.

Repeated requests while already pending remain coalesced and need not create
one wake per call. The scheduler uses a revision/predicate wait that cannot
lose a notification between checking renderer state and sleeping.

Installing and removing the callback are private renderer/runtime operations.
Ordinary consumers continue to call `Renderable.request_render`,
`Render_context.request_render`, or `Renderer.request_render`.

### Frame loop

The scheduler's caller-run operation has this contract:

```ocaml
val run :
  t ->
  (unit, error) result
```

The renderer and positive integer frame rate are bound by `create`; `run`
takes only the resulting scheduler. `create` rejects
`frames_per_second <= 0`.

The exact module split may use `Eio_clock` and `Renderer_scheduler`, but the
observable loop is:

1. Wait until a frame is pending, live ownership is positive, or cancellation
   occurs.
2. Measure elapsed monotonic time since the previous frame attempt.
3. Call `Renderer.render ~delta_time ~force:false` on the owner domain.
4. Preserve any render request made during that frame for a later attempt.
5. If live ownership remains positive, wait until the next frame deadline
   unless a new request requires an earlier permitted attempt.
6. If no live owner and no request remain, return to the state predicate wait.

The first active frame delta is exactly `0.0`. Later deltas are measured
between attempts, not between successful presentations. When the renderer is
idle, the scheduler clears its timing origin and deadline, so the first frame
after an idle period is also `0.0`. A skipped or failed native presentation
does not rewind time or replay updates.

The default target rate is 60 frames per second. Deadline calculation uses the
monotonic clock and advances from the previous target so work duration does
not accumulate as unbounded drift. If a frame overruns, the next attempt may
proceed immediately and the following target is advanced repeatedly to a
future deadline rather than running an unlimited catch-up burst.

An ordinary pending render may wake an idle scheduler immediately. During
continuous live rendering, requests remain coalesced into the next permitted
frame rather than bypassing pacing repeatedly. This preserves responsiveness
without allowing setter-heavy callbacks to create an unbounded render loop.

### Frame ordering

The scheduler does not move work out of `Renderer.render`. The existing frame
operation remains responsible for clearing the consumed request, lifecycle
passes, layout, retained drawing, post processes, console rendering, native
presentation, and successful frame notification. For each attempt the
ordering is:

```text
measure delta
-> retained render
-> post processes with the same delta
-> diagnostic console
-> native presentation
-> successful on_frame notification
```

Pre-render invalidations remain pending for the following attempt because
`Renderer.render` consumes only the request that caused the current frame.
The post-frame `on_frame` event is not used as a substitute animation clock.

### Live ownership

Live state remains reference-counted by the existing retained-tree boundary.
The scheduler observes the renderer's aggregate live count; it does not keep a
second registry of live renderables.

A feature acquires live ownership only while it requires frame deltas. It
releases that ownership on completion, cancellation, pointer release,
destruction, or failure. Repeated cleanup cannot drive the count below zero or
release another feature's ownership. Where balancing raw request/drop calls is
error-prone, a small idempotent live lease may be introduced by the owning
feature, but the scheduler itself does not become a general lease registry.

Scrollbar arrow repetition uses timers rather than live frames. Selection edge
auto-scroll uses live frames because speed depends on frame delta and current
pointer geometry. Post effects remain synchronous buffer operations and use
live ownership only when their state changes continuously.

### Errors and cancellation

Invalid frame rates, a renderer/Eio-clock mismatch, duplicate attachment, a
closed renderer, and renderer frame failures are structured scheduler errors
with `message` and `pp`. The renderer clock must be the cached capability
returned by `Eio_clock.lib_clock` for the clock supplied to `create`.
Expected cancellation from the surrounding switch exits without converting
the cancellation into a renderer failure.

Timer callbacks are owner-local extension points. Unexpected callback
exceptions follow the surrounding Eio switch's failure policy; the clock
adapter does not catch every exception and continue with corrupted owner
state. Feature callbacks that expose recoverable failures convert those at the
feature boundary before scheduling.

Timer cancellation races the Eio sleep against a timer-local cancellation
promise and checks both the timer's cancelled state and the adapter's closed
state before invoking the callback. Scheduler teardown signals waiters, closes
the Eio clock (cancelling its timers), removes the tokenized context wake
callback, and cancels the renderer-destruction subscription. No timer callback
may access a renderer after teardown. Renderer destruction remains idempotent
and closes the scheduler through that subscription.

## Consumer retrofits

### Theme queries

`Renderer_theme_mode` already owns its timers through injected `Lib.Clock`.
Creating a scheduled renderer supplies the Eio-backed clock, making refresh
and waiter timeouts real without changing theme parsing or callback ordering.

### Scrollbar repeat

On arrow down, ScrollBar performs the existing immediate half-viewport step,
schedules a 500 ms one-shot delay, performs the reference second half-step,
and then recursively schedules 200 ms one-shot repetitions at the reference
smaller step. Up, drag end, destruction, hiding, or replacement cancels the
current timer. Only ScrollBar state is captured, and the callback runs on its
renderer domain.

### Selection edge auto-scroll

ScrollBox records the latest selection pointer coordinates. Entering an edge
region acquires one live ownership and leaving it releases that ownership.
Its owner-local per-frame update computes direction and distance from current
geometry, applies delta-scaled scroll, and requests the normal next frame.
Selection completion, capture loss, resize invalidation, and destruction stop
auto-scroll idempotently.

### Post effects and live frames

Post-process callbacks remain synchronous and receive the measured frame delta
already accepted by `Renderer.render`. Installing a static post process only
requests one frame. A continuously changing effect explicitly acquires live
ownership for its active lifetime and releases it when paused, removed, or
destroyed. The scheduler never inspects effect types.

### Image path boundary

`Renderables.Image` does not submit image work to the scheduler or to the
background executor. When constructed with an explicit Eio switch, it performs
cooperative Path I/O in an owner-domain fiber and hands the bytes to the
synchronous Core image decoder on that same domain. Generation checks and
cancellation belong to the image owner; native handles, callbacks, drawing,
and close never cross domains. Consequently, a large decode can still occupy a
frame even though file I/O is asynchronous.

## Explicit non-goals

This feature does not provide:

- executor-domain CPU jobs or parser/image work admission;
- parallel rendering, layout, event dispatch, or native access;
- terminal input multiplexing or output ownership;
- a general task scheduler, actor runtime, or cross-domain mailbox;
- arbitrary wall-clock cron or calendar scheduling;
- hidden timers created by pure model modules;
- automatic animation registration; or
- compatibility shims for JavaScript timer identifiers and globals.

## Implementation sequence

1. **Complete:** add the Eio-backed `Lib.Clock` adapter with
   deterministic cancellation and owner-domain callback tests.
2. **Complete:** add the scheduler revision/wakeup and private
   render-context notification seam without changing terminal `Event_queue` or
   `Wakeup`.
3. **Complete:** add the caller-run paced frame loop and
   black-box tests for idle wake, coalescing, live frames, measured deltas,
   cancellation, errors, and teardown.
4. **Complete:** make scheduled renderer construction explicit
   while retaining explicit synchronous/manual construction for tests and
   embedding.
5. **Complete:** theme refresh and
   timed waiters use an Eio clock when the renderer is created with one; the
   no-clock renderer reports unsupported positive timed waits.
6. **Complete:** retrofit ScrollBar arrow repetition and cancellation.
7. **Complete:** retrofit ScrollBox selection edge auto-scroll through live
   frames, with an idempotent owner-local live contribution.
8. **Complete:** run post effects before the diagnostic console with
   renderer-supplied deltas expressed in seconds; post registration remains
   passive.
9. **Explicitly deferred:** animation has no pre-render driver registry or
   animation surface in this feature.

## Acceptance criteria

- one scheduler owns one renderer's Eio timing and frame loop on one domain;
- the Eio clock reports monotonic time and invokes each uncancelled one-shot
  callback at most once on the scheduler domain;
- timer cancellation and scheduler teardown are idempotent and prevent later
  callbacks from reaching destroyed owner state;
- render requests wake an idle loop without entering terminal `Event_queue`;
- repeated requests coalesce, requests made during a frame remain pending, and
  no notification is lost between predicate inspection and waiting;
- live ownership drives paced frames until the aggregate count returns to
  zero, after which the loop becomes idle without polling;
- the first active frame delta is zero; later deltas are finite, nonnegative,
  monotonic-attempt measurements and are shared by retained updates and post
  processes;
- skipped or failed presentation does not rewind time or replay a retained
  update;
- frame pacing avoids both cumulative work-duration drift and an unbounded
  catch-up burst after an overrun;
- explicit synchronous and manual-clock renderer use remains deterministic and
  does not claim an unadvanced hidden system clock;
- theme refresh and waiter timeouts use the Eio clock in scheduled operation;
- scrollbar hold delay/repetition and all release/destruction cancellation
  paths match the reference timing contract;
- selection edge auto-scroll owns exactly one live request while active and
  releases it on every completion and teardown path;
- continuously changing post effects use explicit live ownership, while
  static effects require only an ordinary render request;
- scheduler cancellation removes its wake hook before renderer teardown and
  returns through the documented structured/cancellation boundary;
- no background pool, worker job, native handle synchronization, or general
  service manager is introduced by this feature; and
- black-box Eio integration tests cover observable wake, pacing, cancellation,
  timer, live, destruction, and renderer-error behavior.
