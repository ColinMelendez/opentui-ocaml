# Audio streams

Status: in progress.

This feature defines the first audio boundary for the OCaml port: streaming
encoded audio into a native decoder and mixer, with demuxing, metadata,
buffering, reconnects, controls, statistics, and lifecycle events. It
corresponds primarily to the stream portion of the pinned reference
implementation in `vendor/opentui/packages/core/src/audio.ts` and
`vendor/opentui/packages/core/src/audio-stream`.

No OCaml audio module or audio ABI exists yet. This record is the design plan
that must precede implementation. It intentionally does not claim that the
whole reference `Audio` surface belongs in this first feature. Sound loading,
voices, capture, recording, taps, and device management need their own
contracts after the stream/native ownership boundary is stable.

## Purpose and scope

The feature provides a minimal audio-engine owner plus a typed
`AudioStream<M>` owner that can:

- share one native decoder/mixer engine with other streams without exposing the
  wider sound, voice, capture, or device APIs;
- connect to a byte source through an explicit connector;
- select or receive a demuxer for the source format and metadata framing;
- feed encoded bytes to a native MP3 or FLAC decoder without buffering the
  entire source in OCaml;
- apply bounded buffering and source backpressure;
- reconnect according to an explicit retry policy while preserving buffered
  playback where the native stream permits it;
- expose volume, pan, group, state, statistics, and close operations; and
- publish the event families specified by the event-system feature.

The generic stream remains independent of any HTTP library, but feature
completion includes a supported HTTP/URL connector in a separately packaged
platform integration. The core contract is implemented and tested first with
an in-process byte source; the HTTP integration then supplies the reference's
ordinary URL-radio path without coupling `opentui-core` to one transport
library. The feature does not include a general audio asset loader, the full
reference `Audio` mixer API, microphone capture, recording, audio taps,
mixer-only fallback, or device enumeration.

The stream is an application-owned Eio runtime component. The application
establishes a dedicated audio scope with its own Eio switch and monotonic
clock; `Stream.open_` receives those capabilities explicitly, and a stream may
derive child scopes for individual attempts. The audio scope is distinct from
the renderer's scope and clock. Audio does not depend on
`Renderer_scheduler`, acquire renderer live ownership, or drive renderer
frames. A UI owner may react to an audio event by requesting an ordinary
renderer frame, but that callback remains the UI owner's responsibility.

The demuxer, option validation, metadata parser, and event vocabulary must
remain usable without Eio so that their behavior can be tested and reasoned
about independently of fibers and I/O.

## Reference correspondence

| Reference source | Planned OCaml location | Responsibility |
| --- | --- | --- |
| `vendor/opentui/packages/core/src/audio.ts` stream types and `AudioStream` | `packages/opentui-core/src/audio.ml` | Minimal engine owner, stream owner, lifecycle, retry policy, controls, statistics, and typed events. |
| `vendor/opentui/packages/core/src/audio-stream/demuxer.ts` | `packages/opentui-core/src/audio_stream/demuxer.ml` | Generic demuxer and connector-selection contracts. |
| `vendor/opentui/packages/core/src/audio-stream/icy/demuxer.ts` | `packages/opentui-core/src/audio_stream/icy/demuxer.ml` | ICY interval framing and metadata block handling. |
| `vendor/opentui/packages/core/src/audio-stream/icy/metadata.ts` | `packages/opentui-core/src/audio_stream/icy/metadata.ml` | Bounded ICY metadata parsing. |
| `playStreamUrl` and its HTTP response policy in `vendor/opentui/packages/core/src/audio.ts` | separately packaged HTTP connector integration, location chosen with its transport dependency | HTTP/HTTPS validation, ICY negotiation, response classification, retry hints, and response-to-demuxer selection without adding an HTTP dependency to core. |
| selected native `audio.zig` stream functions | `packages/opentui-raw/audio.ml` and native ABI/stubs | Native engine, decoder, ring buffer, stream handle, and copied statistics. |
| `vendor/opentui/packages/core/src/tests/audio-stream.test.ts` | `packages/opentui-core/test/test_audio_stream.ml` | Black-box demuxer, lifecycle, backpressure, retry, control, and event tests. |
| `vendor/opentui/packages/examples/src/audio-streaming-demo.ts` | future OCaml streaming example | Validate the ordinary URL-radio workflow, replacement cancellation, metadata, telemetry, reconnect reporting, controls, and shutdown ownership. |

The source-map row also covers the portions of `audio.ts` needed to construct
and control a stream. It must not be read as a commitment to port every
audio-related class in that file at once.

### Practical reference usage

The streaming demo is the only non-test code consumer of `AudioStream`. It
opens HTTP radio URLs, opts into reconnect-on-end, reads initial metadata before
subscribing to updates, polls fresh stream statistics, changes volume, pan, and
group while live, replaces a pending or active stream, and disposes both stream
and engine during teardown. This makes a supported HTTP connector and
group-volume control part of a usable first stream feature rather than
unrelated future conveniences.

The demo's `AbortController` and connection-generation counter protect against
a stale asynchronous open winning after station replacement. Eio child switches
provide that ownership directly. The generic connector, custom demuxer, and
one-shot body entry paths otherwise appear mainly in documentation and tests;
they remain the correct core boundary because the URL implementation itself is
expressed through those contracts and the reference tests exercise their retry
and cleanup invariants extensively.

The same demo uses mixer-only fallback and a master tap for spectrum
visualization. Those operations enhance the presentation but do not affect
encoded stream ownership, buffering, demuxing, reconnect, or controls. They
remain in later mixer and visualization work, so the first OCaml streaming
example need not reproduce the spectrum panel to validate this feature.

## Assessment of the current implementation

The repository currently has no `audio`, `audio_stream`, demuxer, or audio
test module. The raw package's selected ABI deliberately excludes audio; its
ABI documentation names audio as outside the current boundary. The vendored
native build already contains the reference miniaudio dependency and imports
the reference audio implementation, but the local probe, header, stubs, and
OCaml bindings do not expose those functions.

The repository now has implemented Eio owner-domain clocks and a
`Renderer_scheduler`, plus the application-owned `Background` executor. Those
features do not change the audio ownership boundary or supply an audio source
connector, a retry owner, or a native audio handle. Audio uses its own
application-owned Eio switch and monotonic clock rather than borrowing the
renderer scheduler's scope. The stream scope owns producer scheduling and
event delivery; the renderer scheduler remains solely a renderer frame
driver. The event-system design already reserves `AudioStream<M>` as an owner
of typed metadata, reconnecting, ended, error, and disposed events. That
design is normative for this feature: producer scheduling may be deferred by
the audio runtime, but event delivery after scheduling uses the ordinary
owner-local typed channel contract.

There is therefore no partial implementation to preserve. The first work is
an ownership and ABI decision, followed by pure demuxer behavior and then the
Eio/native integration.

## Active design

### Relationship to renderer scheduling and Background

Audio is parallel to, rather than a consumer of, the renderer runtime. The
application owns an audio scope consisting of an Eio switch and monotonic
clock. Engine and stream fibers, source reads, retry delays, monitor sleeps,
and event delivery are bound to that scope. They do not use
`Renderer_scheduler.create`, `Renderer_scheduler.run`, renderer live counts,
or frame deltas. An application may compose the audio scope and renderer
scope under one larger lifetime, but neither scope owns the other.

`Background` is not part of the stream's normal data path. The following values
and operations remain on the audio owner domain and must not cross an executor
boundary:

- Eio sources and connector state;
- borrowed demuxer slices and their sink calls;
- native backpressure waits and the stream supervisor;
- raw/native engine and stream handles, native writes, and decoder state; and
- mutable lifecycle, generation, statistics, and event-delivery state.

Only a later, measured optimization may consider `Background`: it must use
copied, owned inputs and outputs for an isolated `Worker_safe` pure CPU phase.
Its completion must return to the audio owner scope and pass the current
stream/attempt generation before changing state. It must never move borrowed
slices, Eio resources, backpressure, native calls, or decoder state into the
executor, and it must not become an implicit audio scheduler.

The stream scope owns audio event delivery. If a listener needs to affect the
UI, it may notify an owner-domain UI callback; that callback may issue a normal
renderer request, while audio remains unaware of and does not drive the
renderer loop.

### Native ownership and the raw boundary

Audio decoding and mixing remain below `opentui-core`. The raw package owns
the native audio engine, stream handles, decoder worker, ring buffer, and
foreign lifetime. `opentui-core` owns a deliberately narrow `Audio.Engine.t`
around that raw engine and owns the source lifecycle for every stream opened
through it. This engine concept is required for shared mixer and group
semantics; it does not expose sounds, voices, capture, recording, devices, or
the rest of the reference `Audio` API.

The minimal core engine has explicit creation, playback start/stop, group
lookup and volume, and close operations. Matching the reference, creation is
stopped by default and opening a stream does not implicitly start playback. An
optional `auto_start` creation option defaults to false; if requested startup
fails, creation destroys the raw engine and returns the startup error. The
first feature starts only the native default playback path. Device selection
and the wider playback API remain separate designs.

Opening a stream obtains one engine claim and registers the stream as an
engine-owned child. Closing the engine first enters a closing state, rejects
new streams and controls, disposes and awaits all registered streams, and only
then destroys the raw engine. Stream terminal cleanup releases its claim
exactly once. Engine close is idempotent. An engine is application-scoped
rather than implicitly renderer-owned; a later runtime may own one as a
convenience by composition.

The application-owned audio switch bounds a stream's source and monitor
fibers, and its monotonic clock bounds monitor polling, retry backoff, and
event-delivery scheduling. The engine claim bounds the native handle; either
owner ending invokes the same idempotent stream disposal path. If a child
cannot release its native claim, engine close returns a structured aggregate
error and remains `closing`; it does not invalidate the child or destroy the
raw engine underneath it. A later close call retries the remaining cleanup.

Applications that replace a live source, such as the reference station-picker
demo, give each requested stream its own child switch. Replacing the selection
cancels and awaits the previous child switch before exposing the next stream.
Cancellation during `open_` cannot later publish a stale stream because the
switch and attempt generation jointly invalidate its source and native work.
This structured-concurrency composition replaces the reference demo's manual
`AbortController` plus connection-generation checks; it does not justify a
stream manager or mutable global current-stream registry in core.

Conceptually, the ownership surface is:

```ocaml
module Group : sig
  type t
end

module Engine : sig
  type t
  type options

  val create : options -> (t, Error.t) result
  val start : t -> (unit, Error.t) result
  val stop : t -> (unit, Error.t) result
  val is_started : t -> bool
  val default_group : t -> Group.t
  val group : t -> name:string -> (Group.t, Error.t) result
  val set_group_volume : t -> Group.t -> float -> (unit, Error.t) result
  val close : t -> (unit, Error.t) result
  val is_closed : t -> bool
end

module Stream : sig
  type 'metadata t
  type state
  type terminal =
    | Ended
    | Errored of Error.t
    | Disposed
  type stats
  type options
  type 'info connector

  val open_ :
    engine:Engine.t ->
    sw:Eio.Switch.t ->
    clock:_ Eio.Time.clock ->
    connector:'info connector ->
    options:options ->
    ('metadata t, Error.t) result

  val state : 'metadata t -> state
  val metadata : 'metadata t -> 'metadata option
  val get_stats : 'metadata t -> (stats, Error.t) result
  val set_volume : 'metadata t -> float -> (unit, Error.t) result
  val set_pan : 'metadata t -> float -> (unit, Error.t) result
  val set_group : 'metadata t -> Group.t -> (unit, Error.t) result
  val close : 'metadata t -> (unit, Error.t) result
  val await_closed : 'metadata t -> terminal
end
```

This is an ownership sketch rather than a final naming decision. The public
constructor cannot create an implicit engine or accept a raw engine handle.

At the core boundary, streams are therefore opened through or with an explicit
`Audio.Engine.t`; a raw engine handle is not exposed through the high-level
stream API. At the raw boundary, engine and stream handles are distinct
abstract types. Each stream token records its engine owner and generation, and
every raw operation validates both. Raw engine destruction reports `Busy`
while child stream handles remain, as a defensive check around the core
owner's orderly shutdown.

Groups are opaque engine-issued values rather than free integers. A group
records its engine owner and generation, repeated lookup of the same name on
one live engine returns the same value, and using it with another or stale
engine fails structurally. `default_group` exposes the engine-owned value that
corresponds to the reference's integer group `0`; callers never construct that
integer themselves. The minimal engine includes group-volume control so moving
a stream between groups has an observable routing effect, as in the reference
streaming demo. Master volume, voice routing, taps, mixer-only operation, and
the broader mixer-control surface remain outside this feature.

The selected ABI should expose only the engine and stream primitives required
by this feature:

- create, start, stop, and destroy the audio engine;
- create or look up a named group and set its volume;
- create, write, end, restart, and close a stream;
- set stream volume, pan, and group;
- read a copied stream-statistics record; and
- report native state and a stable error code.

The exact C names and integer layout are an ABI design task, not an invitation
to import the whole reference `audio.zig` API. The binding must make native
ownership explicit, keep handles opaque, and ensure that an OCaml stream
cannot outlive its engine. Generation-checked engine and stream tokens
distinguish stale handles after teardown. Restart updates the current stream's
native generation inside the same core owner; it does not leave the core stream
holding an invalid token.

Native writes may consume fewer bytes than supplied and may return zero while
the native buffer is full. Before returning a positive accepted count, the raw
call synchronously copies exactly that prefix into native-owned storage and
retains no pointer into OCaml memory. The OCaml owner retains the exact
unconsumed suffix and waits for capacity; it never silently drops or duplicates
encoded bytes. Native failures become structured stream errors with an
operation and state, rather than untyped exceptions escaping from an arbitrary
callback.

The raw ABI does not call back into OCaml for ordinary audio data. This keeps
foreign callbacks, decoder threads, and native buffers below the raw package.
The core runtime observes state through explicit operations and owns all Eio
coordination.

### Source and connector ownership

The core API should accept an explicit connector rather than baking a URL
client into `AudioStream`. Conceptually, one attempt has the following shape:

```text
connect(cancel, attempt) -> connection
connection = byte source + response information + close operation
```

The byte source is consumed by the stream's owner fiber. An Eio source or an
equivalent typed byte-reader abstraction is appropriate; a JavaScript
`ReadableStream` or an OCaml global queue is not. A connection is owned by one
attempt and is closed exactly once before a retry, disposal, or terminal
failure.

The connector receives an attempt number and cancellation capability. Attempt
numbering preserves the reference distinction: connector and terminal-error
contexts use a zero-based connection index within the current outage, while
retry-policy and `reconnecting` payloads use a one-based retry ordinal. Thus
the initial connection is connector attempt zero and the first accepted retry
is retry ordinal one. `max_retries` excludes the initial connection. The
consecutive ordinal resets only after the native monitor observes a new ready
generation; the total reconnect statistic never resets.

The connector must be able to stop when the stream is disposed, even while
blocked in a read or while retry backoff is pending. The supported HTTP
integration translates response headers, status, and `Retry-After` into the
connection information used by the generic policy, but the stream contract
does not depend on one HTTP library. That integration validates HTTP/HTTPS
URLs, requests ICY metadata unless explicitly overridden, validates or
explicitly ignores format-aware content types, classifies the reference's
retryable statuses, applies bounded `Retry-After` hints, lowercases copied
`icy-*` headers, and selects a fresh demuxer from every response. Redirected
response URLs and every reconnect response are revalidated before audio bytes
reach the native decoder.

Connector and source ownership stay in the audio scope. An Eio source, a
blocked read, and connection cleanup are not admissible `Background` work;
they require the stream supervisor's cancellation and generation rules.

Every attempt gets a fresh cancellation scope, byte-source ownership record,
demuxer, and native-write state. Reusing a demuxer across attempts would allow
partial metadata or framing from one connection to corrupt the next one.

### Demuxer contract

The generic demuxer is an incremental component with no clock, fiber, source,
or native dependency. It emits through a synchronous sink instead of returning
a list of borrowed slices. Its conceptual contract is:

```ocaml
type slice

type 'metadata output =
  | Audio of slice
  | Metadata of 'metadata option

module type DEMUXER = sig
  type metadata
  type t

  val initial_metadata : t -> metadata option
  val push :
    t ->
    input:slice ->
    emit:(metadata output -> (unit, 'sink_error) result) ->
    (unit, [ `Framing of Error.t | `Sink of 'sink_error ]) result
  val flush :
    t ->
    emit:(metadata output -> (unit, 'sink_error) result) ->
    (unit, [ `Framing of Error.t | `Sink of 'sink_error ]) result
  val abort : t -> reason:Error.t -> unit
end
```

This is a semantic sketch, not a final public signature. The concrete slice is
a read-only backing value plus offset and length; choosing `Bigarray`, `Bytes`,
or a Cstruct-compatible representation does not change its lifetime. An audio
slice is borrowed only for the duration of its `emit` call. The sink completely
consumes it before returning. In OCaml direct style the sink may suspend through
Eio effects while retaining the source backing value, but the demuxer itself
does not acquire Eio or perform I/O. Metadata values are owned and may outlive
the call.

Emission is sequential and non-reentrant. `push` and `flush` preserve output
order. `flush` either emits the complete tail or returns a framing error when
the source ends inside a metadata block. If the sink fails or cancellation
escapes while it is consuming an output, the attempt aborts the demuxer and may
not resume it. `abort` is idempotent and prevents later output. A retry creates
a fresh demuxer. Tests that need collected output use a sink that explicitly
copies audio bytes; production does not copy every slice merely to cross the
demux boundary.

A demuxer is not responsible for native backpressure. The stream-owned sink
processes each emitted audio slice before returning and retains its exact
unconsumed suffix when native writes are partial.

The borrowed slice is valid only for its sink call and is consumed on the
audio owner domain. A demuxer must not enqueue that slice, its backing input,
or a sink that retains it into `Background`; a future worker phase would first
copy the bytes into owned data and would be subject to the measured
`Worker_safe` restriction above.

The ICY demuxer must match the reference behavior:

- interval zero treats every non-empty input chunk as audio and emits no
  metadata;
- a positive interval splits audio at exact byte boundaries;
- the metadata-length byte represents a block length in multiples of sixteen;
- metadata blocks may span input chunks;
- a zero-length block resets the interval without emitting metadata;
- fields are parsed from the decoded, NUL-truncated `key='value';` form;
- malformed trailing text does not invent fields; and
- repeated metadata is not emitted when its parsed fields are unchanged.

Header selection copies lower-case `icy-*` response headers into the initial
metadata record. An invalid or absent interval follows the reference
selection policy; it does not cause the generic stream owner to guess a
different framing mode.

### Buffering and native flow control

The stream separates three states that are easy to conflate:

```text
source read -> demuxed encoded bytes -> native decoder/ring buffer -> playback
```

The native buffer has a finite capacity, startup threshold, and resume
threshold. The effective defaults must be recorded at the public integration
boundary rather than copied only from a low-level constructor. The initial
design mirrors the reference stream defaults: `capacity_ms = 2000`,
`startup_ms = 1000`, `resume_ms = 1000`, `max_probe_bytes = 1024 * 1024`,
volume `1`, pan `0`, and the owning engine's `default_group`. That opaque value
maps to native group `0`. Startup and resume are validated against capacity.
These values become part of the public contract once the native ABI is
selected; they must not diverge accidentally between the core option resolver
and the raw constructor.

Each attempt has a structured supervisor with two child fibers: a source pump
that connects, reads, demuxes, and writes, and a native monitor that starts as
soon as the native stream exists and remains active for the whole attempt. The
monitor polls copied native statistics through the supplied Eio clock, updates
the latest public snapshot, signals readiness and capacity changes, and reports
failed, cancelled, and ended native states to the supervisor. Raw calls remain
synchronous and confined to the stream's owning domain; supporting callers
from another domain requires an explicit handoff rather than relying on a
mutex for lifecycle ordering.

The monitor, capacity conditions, and native writes remain in this owner
domain. In particular, a zero-capacity wait is an audio-scope backpressure
wait, not a job that may be submitted to `Background`.

When a native write returns zero, the source pump waits on a
cancellation-aware capacity/state condition maintained by the monitor and then
retries the same suffix. It does not start an independent polling loop. A
terminal native transition wakes the same wait. Empty source chunks are
observable to the cancellation and progress machinery: they must yield before
the next read rather than causing an unbounded tight loop. No queue coalescing
or audio-byte replacement is allowed.

Native state transitions are therefore observed while connect, source read,
or capacity waiting is blocked, rather than only after source EOF. A decoder
failure, cancelled stream, or terminal native state cancels the source side of
the current attempt and follows the terminal native-failure path. Source end
invokes the native end operation but is not a terminal stream outcome until the
monitor observes that playback has drained and the native state is ended. The
`closed` completion preserves the distinction between input completion and
terminal stream lifecycle.

### Retry and lifecycle state machine

The core owner exposes states equivalent to:

```text
initializing -> buffering -> playing
      |            |          |
      +---------- reconnecting ----------+
                               |
                         ended / errored / disposed
```

The exact transition is driven by source connection, native statistics, end
of input, cancellation, and retry policy. A retry is a new attempt, not a
reset of the public stream identity.

The lifecycle invariants are:

- `open_` may suspend in direct Eio style and does not expose the stream until
  the monitor observes a new native ready generation or clean playback end;
- setup errors or cancellation are returned before the stream becomes
  externally exposed, while a clean setup-time end returns an already-ended
  stream and schedules its terminal event after exposure;
- after `open_` returns, its caller regains control before any setup metadata
  or already-ended terminal event is delivered, so subscribing in the
  immediate continuation cannot miss that notification;
- each attempt creates a fresh demuxer and source scope;
- cleanup aborts the demuxer, cancels/releases the source reader or iterator,
  and closes the connection exactly once;
- waits for optional close and cleanup callbacks are bounded after cooperative
  cancellation has been delivered;
- reconnect cleanup happens before the next connection attempt;
- every monitor notification carries the attempt/native generation and late
  notifications from an obsolete attempt are ignored;
- a retry can preserve native buffered playback when the native stream is
  still valid, but it must not append bytes to a closed or failed stream;
- terminal error, ended, and disposed are mutually exclusive final outcomes
  for an externally exposed stream;
- `dispose` is idempotent and wins races with pending connect, read, write,
  monitor sleep, backoff, and event delivery by invalidating the attempt
  generation before cancellation; and
- the `closed` completion is resolved exactly once after terminal cleanup.

The public `close` operation is the OCaml counterpart to reference `dispose`:
it invokes that idempotent disposal path and waits for the bounded cleanup it
owns. `await_closed` allows a caller to wait for natural end or terminal error
without initiating closure and returns the typed terminal outcome, including
the structured terminal error when present. Final state, statistics, and
metadata remain readable after natural completion.

The supervisor is the sole terminal arbiter. A native failure cancels a
blocked source read. Source EOF requests native end and waits for the monitor's
ended observation. A transport failure consults the latest native snapshot
before retrying so a decoder failure cannot be misclassified as a reconnectable
read failure. Among non-disposal outcomes, the first current-generation outcome
accepted by the supervisor determines the transition; later outcomes are
ignored.

Bounded cleanup requires the connector and byte source to cooperate with Eio
cancellation. The stream bounds how long it waits for optional close/cleanup
callbacks, but it does not claim that arbitrary non-cancellable foreign code
can be forcibly terminated. This limitation is part of the connector contract.

Retry options cover maximum retries, initial and maximum delay, backoff,
retry-on-end, and a policy callback. Matching the reference, the policy
callback runs only for classified `connect` and `read` failures. A demuxer
flush failure discovered at source end may be classified as a read failure.
Clean EOF uses `retry_on_end` without invoking the policy callback. Demuxer
push, native write, end, restart, decoder, and destroy failures are terminal
for this feature rather than silently broadening the retry vocabulary.

The policy sees the one-based retry ordinal, `max_retries`, phase, and a
structured error; it does not parse a human error string. Backoff and response
retry hints are capped and cancellation aware. Every accepted retry increments
the total reconnect statistic, including setup retries that occur before the
stream is externally exposed. Those completed setup retries are not replayed as
later `reconnecting` events.

### Events and scheduling

`AudioStream<M>` owns typed channels for metadata, reconnecting, ended, error,
and disposed. Their payloads contain named records, including attempt and
source context where applicable. Once a stream has been returned to its
caller, the `error` channel is terminal only: it is emitted exactly once for
the final `errored` outcome and is never used for a failed control, an
intermediate retryable failure, or an observer exception. Setup failure before
the stream is exposed is returned only from `open_`, so there is no inaccessible
stream on which to emit an error event. The `reconnecting` payload carries the
structured cause for an accepted retry. The channels use the event-system
design's owner-local snapshot and cancellation rules.

Metadata is also readable as the stream's latest owned value. A non-`None`
value discovered during setup is scheduled only after `open_` exposes the
stream. Once exposed, a transition to `None` is observable. Matching the
reference, at most one metadata notification may be pending: rapid accepted
changes coalesce and the scheduled callback receives the latest value. Demuxer
outputs are still processed in order, but listeners are not promised every
intermediate metadata value. A custom demuxer is responsible for emitting only
meaningful changes; the generic owner does not use polymorphic structural
comparison to guess metadata equality.

The exposure gate is a caller-turn guarantee, not merely an internal state
flag. Setup metadata and an already-ended terminal notification are queued
behind the first yield after `open_` returns. A caller can therefore read the
initial `metadata` snapshot and install observers in the immediate continuation
before either notification runs, matching the practical reference usage.

Metadata is untrusted transport text. The ICY parser preserves decoded values
and structural field names; it does not strip terminal controls, interpret
metadata URLs, or apply display policy. Documentation and examples must
sanitize values before rendering them to a terminal.

The stream owner schedules delivery through the audio Eio scope after a read,
demux, native state change, or cleanup transition; it never emits inline in
the middle of source ownership changes. This preserves the reference's
non-reentrant asynchronous event boundary without promising JavaScript
macrotask ordering. Once scheduled, channel emission is synchronous and typed.
The event source does not acquire Eio in its kernel, and event callbacks do not
own the native stream. A terminal event is delivered after terminal cleanup,
and `closed` resolves after that delivery attempt finishes. If a listener must
affect the UI, its owner-domain callback may request a normal renderer frame;
audio does not acquire renderer live ownership or drive the renderer loop.

Error reporting is a stream policy boundary. Connector, demuxer, native
operation, and cleanup failures are tagged with their phase and operation.
An observer exception is caught at the audio producer's explicit emission
boundary, reported to the configured diagnostic reporter, and does not change
stream state, trigger retry, emit `error` recursively, or prevent `closed` from
resolving. Because ordinary channel emission stops when an observer raises,
later observers in that emission snapshot are not invoked. An unobserved
terminal error is also sent to the diagnostic reporter. Plugin-style recovery
is not imported into audio: a stream either retries according to its explicit
policy or reaches one terminal outcome.

### Controls and statistics

Volume, pan, and group are stream-owned controls forwarded to the native
engine. The group control accepts only an opaque `Group.t` issued by the same
engine. Setters preserve native validation and return structured
`(unit, Error.t) result` failures. They do not emit the terminal `error` event
and do not silently mutate a cached OCaml value when the native operation
fails. This deliberately replaces the reference's Boolean-plus-nonterminal-
error-event control contract with one ordinary OCaml result.

Engine start, stop, group lookup, group-volume control, and close follow the
same OCaml rule: a recoverable failure is returned as structured data. Group
volume validates ownership and updates the native group only on success. The
minimal engine does not own a generic error channel. These engine failures are
not stream-terminal events and cannot change an already exposed stream to
`errored` unless the stream's own native monitor subsequently observes a
terminal stream failure.

`get_stats` returns a copied record containing at least bytes received,
frames decoded, frames played, buffer capacity, buffered frames, sample rate,
channels, underruns, native state, and error code. Reading statistics is
an explicit freshness point, as in the reference: it performs or requests an
immediate native snapshot through the stream's state owner, updates the copied
record, and submits any terminal observation to the same supervisor used by
the monitor. It does not itself close the stream, advance playback, or become a
second terminal arbiter; terminal cleanup is scheduled outside the getter's
call stack.

All public stream operations are confined to the Eio domain that owns the
audio scope. Fibers on that domain may interleave calls because every raw
operation is synchronous and the supervisor owns state transitions. A caller
from another domain must use a future explicit handoff API; cross-domain access
is not made safe merely by placing a mutex around the raw handle.

### Deliberate differences from the reference

The high-level streaming behavior preserves the reference's encoded-byte
ordering, buffering thresholds, retry numbering and backoff, ordered metadata
processing and latest-value event coalescing, control effects on success,
input-end versus playback-end distinction, and terminal event families. The
following differences are intentional and consumer-visible:

- The reference exposes streams as children of its broad `Audio` object. The
  first OCaml feature exposes a minimal explicit `Audio.Engine.t` plus an Eio
  switch, without prematurely adding sounds, voices, capture, or devices.
- The reference exposes engine groups as integer IDs. OCaml issues opaque
  engine-owned `Group.t` values and rejects a stale or cross-engine group
  structurally. Group lookup preserves the reference's name interning, and the
  minimal engine retains group-volume control because it is required to make
  stream routing useful without importing the wider voice API.
- The reference includes built-in body, URL/fetch, and generic source entry
  points on `Audio`. OCaml keeps one explicit connector-based core entry point
  and ships its supported HTTP/URL connector as a separate platform
  integration. URL consumers compose that connector rather than call a method
  that silently selects the process fetch implementation.
- A custom reference demuxer returns an iterable of borrowed `Uint8Array`
  views. An OCaml custom demuxer emits borrowed slices through a synchronous
  sink. Ordinary stream consumers see the same ordered metadata and audio;
  custom demuxer authors implement the different lifetime-safe interface.
- The reference uses Boolean returns or thrown setup errors plus asynchronous,
  nonterminal `error` events for failed engine and stream controls. OCaml engine
  and stream controls return structured results; the minimal engine has no
  generic error event, and a stream's `error` is reserved for its single
  terminal errored outcome. Ported consumers inspect each control result
  instead of listening for a control error event.
- The reference's readiness poll ends once the decoder becomes ready, after
  which a decoder failure may be discovered by a later write, drain, or
  `getStats` call. The OCaml monitor remains active for the whole attempt, so a
  terminal native failure can be reported earlier while source read or capacity
  waiting is blocked.
- JavaScript promises and `AbortSignal` become explicit Eio switch, clock, and
  cancellation ownership. The connector retains the reference attempt and
  cleanup semantics but is domain-confined. Replacing a stream cancels its
  child switch; consumers do not reproduce the reference demo's mutable
  generation and stale-promise checks.
- The reference `closed` promise resolves without a value after terminal event
  delivery. OCaml `await_closed` waits for the same cleanup boundary and
  returns a typed ended, errored, or disposed outcome; callers need not recover
  the terminal cause by coordinating a separate mutable event-side cache.
- A reference event-listener exception escapes its deferred JavaScript
  callback. OCaml catches observer exceptions only at the producer's scheduled
  emission boundary, stops the remaining observers in that snapshot, and sends
  the exception to diagnostics without changing stream lifecycle.

Stopped-by-default engine creation, explicit playback start/stop, copied-prefix
native writes, readiness-gated stream exposure, latest-value metadata
coalescing, `get_stats` as a fresh-observation point, and retry ordinals with
the reference's zero-based connector/one-based retry distinction intentionally
match the reference and are not porting differences.

## Planned implementation sequence

1. Freeze the selected native audio ABI and the minimal core engine ownership
   model. Establish the application-owned audio scope with its dedicated Eio
   switch and monotonic clock, explicitly separate from `Renderer_scheduler`
   and `Background`. Add stopped-by-default playback start/stop, opaque groups
   and group volume, generation-checked engine/stream handles, defensive busy
   close, state, stats, and stream-operation tests without exposing the wider
   `Audio` API.
2. Implement pure ICY metadata and demuxer modules, including fragmented
   input, zero intervals, repeated metadata, invalid tails, and flush errors.
   Keep these modules independent of Eio and `Background`; any borrowed slice
   remains valid only for its owner-domain sink call.
3. Implement an in-process fake connector and fake native engine/stream so the
   core engine lifetime, lifecycle, partial writes, zero-capacity waits,
   cancellation, controls, statistics, and retry policy can be tested without
   hardware. Run the fake source, supervisor, and native boundary in the audio
   scope rather than an executor worker.
4. Implement the Eio stream owner with fresh per-attempt scopes, a source pump,
   a whole-attempt native monitor, terminal arbitration, bounded cooperative
   cleanup, native backpressure, deferred event delivery, and idempotent
   disposal. Keep Eio sources, borrowed slices, capacity waits, the stream
   supervisor, and all raw/native operations on the audio owner domain.
5. Add typed terminal events, structured control results, diagnostic observer
   handling, the post-`open_` caller-turn gate, reference-compatible retry
   ordinals, and fresh `get_stats` observation through the supervisor. Deliver
   events from the audio scope; a UI owner callback may request a normal frame,
   but this feature must not acquire renderer live ownership or drive the
   renderer loop.
6. Add native MP3/FLAC integration fixtures and verify decoder/native state
   behavior. Keep decoder state, native handles, writes, and backpressure in
   the audio owner domain. Keep tests deterministic where possible and avoid
   requiring a physical audio device.
7. Add the separately packaged supported HTTP/URL connector with deterministic
   in-process-server tests for ICY negotiation, response validation, redirects,
   reconnect classification, retry hints, cancellation, and fresh demuxer
   selection. Only then consider the wider playback, capture, recorder, tap,
   mixer-only, and device features from `audio.ts`.
8. After the stream path is complete, benchmark any candidate CPU phase against
   the synchronous owner-domain path. Consider `Background` only if the
   measurements justify an isolated `Worker_safe` phase over copied, owned
   data, with completion returned to the audio scope and checked against the
   current generation. Do not move sources, borrowed slices, waits, the
   supervisor, native calls, or decoder state into the executor.

## Acceptance criteria

- the raw boundary keeps native audio handles, buffers, decoder threads, and
  callbacks below `opentui-raw`;
- audio is application-owned and runs in a dedicated Eio switch with its own
  monotonic clock; it does not depend on `Renderer_scheduler`, hold renderer
  live ownership, or drive renderer frames;
- Eio sources, borrowed demuxer slices, backpressure waits, the stream
  supervisor, raw/native handles and writes, and decoder state never cross the
  `Background` executor boundary;
- `Background` is considered only after measurement for copied, owned,
  isolated `Worker_safe` pure CPU work, and its completion returns to the audio
  owner scope before any stream state can change;
- the minimal core engine owns all streams opened through it, rejects new work
  while closing, disposes its children before raw teardown, and does not expose
  the wider playback/capture API;
- engine creation is stopped by default, opening a stream does not start it,
  optional auto-start failure cleans up construction, and start/stop controls
  return structured results;
- groups are opaque engine-owned values whose name lookup is stable and whose
  stale or cross-engine use fails structurally; the engine exposes its opaque
  default group, and group-volume changes return structured results and make
  stream group changes observably useful without exposing voices or master
  mixer controls;
- opening after engine close fails structurally, stream terminal cleanup
  releases its engine claim exactly once, and raw engine close defensively
  reports busy while a stream token remains;
- a failed child cleanup leaves the engine closing and retryable without
  invalidating that child or destroying the raw engine;
- demuxer output is ordered, incremental, ownership-safe, and lossless;
- borrowed audio output is consumed entirely inside its sink call, while test
  collectors make any required copies explicit;
- ICY framing and metadata behavior matches the reference for fragmented,
  empty, repeated, malformed, and truncated inputs;
- a successful native write copies exactly its accepted prefix before return,
  retains no OCaml pointer, and partial writes retain the exact unconsumed
  suffix; zero-capacity waits are cancellation-aware and driven by the attempt
  monitor;
- empty source chunks cannot cause a non-yielding read loop;
- each retry has a fresh source and demuxer, cleans the prior attempt exactly
  once, and follows structured retry policy;
- connector/error attempt indices, retry-policy/event ordinals, maximum retry
  counting, readiness reset, and total reconnect statistics match the pinned
  reference;
- native failure, source end, terminal error, and disposal have distinct,
  idempotent lifecycle paths;
- native failure is observed and cancels the attempt even while source read or
  capacity waiting is blocked, and obsolete monitor notifications cannot affect
  a later attempt;
- event delivery follows the event-system design, is owned by the audio stream
  scope, and is not re-entrant with unsafe source/native ownership transitions;
- a UI owner callback may request a normal renderer frame in response to audio,
  but audio never owns or drives the renderer loop;
- initial metadata becomes observable after setup, later clears are observable,
  and rapid metadata changes coalesce to the latest value as in the reference;
- `open_` returns control before queued setup metadata or an already-ended
  terminal event can run, so observers installed in its immediate continuation
  receive those notifications;
- ICY metadata remains untrusted, is preserved rather than display-sanitized by
  the stream, and is documented with a terminal-display sanitization
  requirement;
- setup failures return from `open_` without an event, and an exposed stream
  emits `error` only for its single terminal errored outcome; controls return
  structured results and observer failures go only to diagnostics;
- `open_` exposes a stream only after a ready generation or clean end, and a
  setup-time clean end is observable as an already-ended stream followed by its
  scheduled terminal event;
- controls and statistics reflect the native stream rather than an
  unverified OCaml cache, and `get_stats` submits fresh terminal observations
  to the supervisor without becoming a second terminal arbiter;
- replacing a stream by cancelling its child switch cannot expose a late stale
  result and requires no core stream manager;
- the generic stream can be tested without an HTTP client or physical audio
  device, while feature completion includes deterministic tests of the
  supported HTTP connector and later full-audio work retains a clear extension
  boundary; and
- taps, mixer-only fallback, loaded sounds, voices, capture, recording, and
  device selection remain explicitly outside this stream feature even though
  the reference radio demo uses some of them for visualization.
