# Background CPU jobs

Status: in progress.

This feature defines the small Eio boundary used to keep expensive,
synchronous CPU work from blocking terminal input and rendering. It provides
one application-owned pool of reusable OCaml domains and a submission
operation whose completion handler resumes on the submitting Eio domain.

The first intended consumer is Tree-sitter highlighting. Large Markdown
parses and copied-pixel image decoding are possible later consumers when
benchmarks and native ownership permit them. This feature does not make the
renderer, retained tree, event system, or native handles safe for concurrent
mutation.

## Purpose

The renderer and input paths are deliberately synchronous. That keeps their
ordering and ownership understandable, but a parser or decoder that occupies
the renderer domain for several milliseconds can delay input and a requested
frame. Background jobs allow selected CPU-heavy computations to overlap the
normal Eio runtime while preserving the existing owner-local application path:

```text
submitting Eio domain
  -> capture an owned input snapshot
  -> submit CPU work

executor domain
  -> compute without renderer or native state
  -> return an owned result

submitting Eio domain
  -> resume completion handler
  -> validate consumer generation/lifetime
  -> update existing state
  -> use the existing render request and event flows
```

The expected improvement is responsiveness, not parallel rendering. Layout,
retained traversal, callbacks, native drawing, and presentation remain on one
renderer domain.

## Reference correspondence

| Reference source | Planned OCaml correspondence | Responsibility |
| --- | --- | --- |
| `vendor/opentui/packages/core/src/platform/worker.ts` | `packages/opentui-core/src/platform/eio_runtime/background.ml` | Replace the JavaScript/Node worker transport mechanism with reusable Eio executor domains. |
| `vendor/opentui/packages/core/src/lib/tree-sitter/parser.worker.ts` | `Background.submit` plus `Lib.Tree_sitter_client` | Run highlighting away from the renderer domain and return typed highlight data. The JavaScript worker protocol and WASM asset loader are not ported. |
| `vendor/opentui/packages/core/src/lib/tree-sitter/client.ts` and `renderables/Code.ts` | `Lib.Tree_sitter_client` and `Renderables.Code` | Own parser lookup, content snapshots, per-consumer generations, stale-result rejection, fallback, and application of highlights. |
| `vendor/opentui/packages/core/src/renderables/markdown-parser.ts` | `Renderables.Markdown_parser` | Remain a synchronous pure parser; a Markdown owner may submit sufficiently expensive parses through `Background`. |
| `vendor/opentui/packages/core/src/image.ts` | `Image` and `opentui-raw` | Remain renderer/native-domain code initially. A later audited pipeline may return copied pixels and metadata from a worker. |
| Eio 1.4 `Executor_pool` | `Platform.Eio_runtime.Background` | Supply reusable worker domains, structured switch lifetime, and a promise-backed return to the submitting fiber. |

The repository is locked to Eio 1.4. Its
[`Executor_pool`](https://ocaml.org/p/eio/1.4/doc/eio/Eio/Executor_pool/index.html)
is the underlying mechanism. Direct `Domain_manager.run` and a dedicated
long-lived parser domain are not part of the initial feature.

## Assessment of the current implementation

There is no background submission module today. Parser-backed renderables run
their work synchronously:

- `Lib.Tree_sitter_client.highlight_request` invokes the registered parser
  function in the caller;
- `Renderables.Code.refresh` parses, converts highlights, mutates its text
  buffer, and requests a render in one call;
- `Renderables.Markdown.set_content` parses and rebuilds retained children in
  one call; and
- `Image.load` performs path loading and native decode synchronously.

The current `Tree_sitter_client` generation belongs to the whole client. That
works only because requests are synchronous. Once work can overlap, one Code
renderable must not make another Code renderable's result stale. Generation
and latest-result policy therefore belong to the consuming Code/buffer, not to
one client-global counter.

The current runtime `Event_queue` and `Wakeup` are single-domain structures.
They remain unchanged and are not a completion transport for background jobs.

## Active design

### One explicit application owner

An application creates at most one `Background.t` for its ordinary CPU jobs.
It is created under the application Eio switch from the environment's domain
manager and is passed explicitly to parser or other feature owners that use
it. `Renderer`, `Render_context`, `Code`, and `Markdown` do not create private
executor pools.

The initial recommended configuration is one executor worker in addition to
the application's Eio domain. One worker is sufficient to move parsing out of
the input/render path and naturally limits concurrent CPU and GC pressure.
Applications may choose another positive count, but the total domain count
must not silently exceed `Domain.recommended_domain_count ()`.

`Background` has no hidden process-global instance. An application that does
not create or inject it continues to choose a synchronous feature path; the
module does not silently oversubscribe a single-core host.

### Submission contract

The planned public shape is conceptually:

```ocaml
module Background : sig
  type t

  type error =
    | Invalid_worker_count of int
    | Closed

  val create :
    sw:Eio.Switch.t ->
    domain_mgr:_ Eio.Domain_manager.t ->
    worker_count:int ->
    (t, error) result

  val submit :
    t ->
    sw:Eio.Switch.t ->
    work:(unit -> ('value, 'error) result) ->
    on_complete:(('value, 'error) result -> unit) ->
    (unit, error) result
end
```

The exact names may change during implementation, but these semantics are
normative:

- `submit` starts an owner-domain Eio fiber;
- that fiber calls `Eio.Executor_pool.submit` with CPU weight `1.0`;
- only `work` runs on an executor domain;
- after the executor result is available, the same owner-domain fiber invokes
  `on_complete`;
- the completion callback is never invoked from the executor domain; and
- submission does not run or mutate the renderer by itself.

CPU weight is not initially public configuration. Background jobs are selected
because they are CPU-heavy, so they consume one executor worker while running.
If later consumers have genuinely mixed I/O/CPU behavior, that work should
first be separated into Eio I/O and CPU phases rather than assigned an
arbitrary fractional weight.

The application switch owns the executor pool. The switch supplied to
`submit` owns the waiting fiber and completion callback. A consumer may use a
feature-specific child switch when its lifetime is shorter than the
application, but `Background` does not require a new switch per job.

### Data that may cross the boundary

`work` receives or closes over an owned snapshot that can be read safely on
another domain. Expected inputs include strings, bytes that are not mutated,
immutable records and variants, scalar options, and immutable parser
definitions. Expected results include copied highlight ranges, immutable
Markdown tokens, copied pixels and metadata, and structured feature errors.

Mutable temporaries may be created and used entirely by one worker job. Once a
result crosses back, the worker no longer mutates it. OCaml shared-heap values
do not require JavaScript-style serialization, but shared representation does
not make a mutable value domain-safe.

Worker closures must not capture or use:

- `Renderer.t`, `Render_context.t`, or `Renderable.t`;
- Yoga nodes, buffers, text buffers, event sources, callbacks, or selections;
- `Opentui_raw` handles or other foreign lifetime tokens;
- terminal paths, flows, descriptors, switches, or session state; or
- mutable application state that the submitting domain may access
  concurrently.

The OCaml type system does not prove this closure property. The module
documentation, consumer APIs, and integration tests make the ownership rule
explicit. Feature APIs should accept an immutable input value separately from
the owner-domain application callback so accidental renderer capture is easy
to identify in review.

### Completion and existing flows

An executor result resolves the waiting Eio operation and wakes the submitting
domain's normal scheduler. The resumed fiber invokes `on_complete` directly.
There is no new completion mailbox, renderer command queue, cross-domain event
variant, or change to `Platform.Eio_runtime.Wakeup`.

The completion callback may use normal owner-domain APIs. A Code completion,
for example, can validate its generation, convert highlights into styled text,
update its existing text buffer, and call `Renderable.request_render`. Any
ordinary component event remains a synchronous owner-local event emitted by
the component after it applies the result.

`Background` does not render immediately and does not define frame ordering.
A render request made by a completion follows the same coalescing and future
frame behavior as any other render request.

### Stale work and admission

`Background` is an execution mechanism, not a latest-value scheduler. It does
not know whether two jobs are related and therefore does not deduplicate,
cancel, or coalesce them globally.

Features driven by rapidly changing input own a small local admission policy:

```text
Idle
  -> submit latest snapshot
  -> Running

Running + new state
  -> replace one Pending snapshot

Running completion
  -> apply only if its generation is current
  -> submit Pending when present, otherwise return to Idle
```

This permits at most one running and one latest pending job for that feature
owner. Obsolete running work may finish, but its result is discarded. The
policy remains local because Code, Markdown, and Image have different notions
of identity, error fallback, and useful intermediate results.

Every asynchronous parser consumer owns a monotonically increasing generation
or version. The completion callback checks the generation and owner lifetime
before applying a result. Destroying or changing a renderable makes old
results harmless even when a CPU operation cannot be interrupted promptly.

### Errors and cancellation

Expected work failures use the worker function's typed result and are
delivered to `on_complete`. `Background` does not erase a
consumer error into a string or impose one error variant on unrelated
features.

An unexpected exception from `work` is not converted into a recoverable
feature error. It is re-raised by the owner-domain waiting fiber and follows
the surrounding Eio switch's failure policy. Completion-callback exceptions
likewise propagate from the owner-domain fiber. Eio cancellation exceptions
retain their cancellation meaning.

Cancelling the submission switch cancels the waiting fiber and prevents its
completion callback. It does not promise forcible termination of a pure CPU or
foreign operation already running on an executor. Correctness therefore
depends on lifetime/generation validation, not prompt physical cancellation.
A future parser may additionally poll a cooperative cancellation flag, but
that is not required by `Background`.

The application switch owns pool shutdown. Once that switch begins release,
`Background` rejects later submission; it does not synchronously wait on
arbitrary feature state or call feature callbacks during teardown.

## Initial consumers

### Tree-sitter and Code

Tree-sitter highlighting is the first required integration. Parser lookup and
request snapshot creation happen on the owner domain. The worker receives the
resolved parser operation, content, filetype, and any immutable parse options,
and returns typed highlight data or a typed parser error.

The parser function must be safe to invoke on an executor worker. A parser
that wraps mutable or foreign state must make that state job-local or provide
its own serialization; it cannot rely on `Tree_sitter_client`'s owner-domain
registry table for synchronization. Parser registration/removal and client
lifecycle remain owner-domain operations.

`Code` owns the generation and at-most-one-running/one-pending policy. Plain
text may be installed immediately according to `draw_unstyled_text`; the final
highlight result is applied only if the Code owner is alive and its generation
is still current. Two Code renderables sharing one client do not invalidate
each other's generations.

### Markdown

`Markdown_parser.parse` remains an ordinary synchronous function. Background
submission is considered only when measurements show that realistic large or
streaming documents materially delay the renderer domain. The Markdown owner
chooses the threshold and admission policy; `Background` does not inspect
content size.

The worker may return the immutable parsed block/inline representation. Child
renderable creation, stable-prefix reconciliation, destruction, layout, and
render requests all remain in the owner-domain completion callback.

### Images

Image loading is not an acceptance condition for the first implementation.
Eio path reads are I/O and should remain Eio operations rather than executor
jobs. Native decoding currently produces a foreign image handle whose registry
assumes serialized native entry, so that handle does not cross domains.

A later audited pipeline may perform a worker-safe decoder operation that
returns copied RGBA pixels and metadata. Native image construction, retention,
drawing, and destruction remain on the renderer domain unless the raw/native
ABI gains and documents a different thread-safety contract.

## Explicit non-goals

The initial feature does not provide:

- parallel rendering, layout, event dispatch, terminal I/O, or native calls;
- a general actor system, task graph, work-stealing API, or service registry;
- a cross-domain renderer mailbox or a replacement for `Event_queue`;
- domain-affinity assertions on renderer values;
- dedicated long-lived domains or parser-instance affinity;
- forced cancellation of running CPU or foreign work;
- global latest-job or priority policy;
- background timer callbacks or a frame scheduler; or
- automatic selection of work based on timing or content size.

These omissions are intentional. They keep the first boundary small enough to
audit and allow measured requirements to justify any later mechanism.

## Revisit conditions

The design should be revisited only when evidence requires a stronger
mechanism. Examples include:

- incremental Tree-sitter state must remain on one particular domain;
- more than one producer domain needs to send unsolicited messages to one
  renderer;
- executor queueing cannot express required priority or fairness;
- stale jobs consume enough CPU that cooperative cancellation is necessary;
- several independent renderers need isolated background capacity; or
- native image/parser APIs gain explicit cross-domain ownership contracts.

A dedicated parser domain, bounded cross-domain mailbox, owner-domain token,
or richer scheduler may then become justified. They are extensions to this
record, not assumptions hidden in the initial implementation.

## Performance evidence

Background execution is worthwhile only when it improves observable latency
after its scheduling and allocation overhead. Benchmarks should compare the
synchronous and background paths for representative content sizes and report:

- time spent in the CPU operation;
- submit-to-completion latency;
- owner-domain input/frame delay during the operation;
- allocation and major-GC behavior;
- obsolete work started and completed during burst updates; and
- time to initial unstyled output and final highlighted output for Code.

Tree-sitter fixtures should include small, medium, and large files plus a burst
of edits where only the final generation is applied. Markdown background work
is enabled only after similar measurements establish a useful threshold.

## Planned implementation sequence

1. Add `Platform.Eio_runtime.Background` around one application-owned
   `Eio.Executor_pool`, with explicit switch lifetime and structured creation
   errors.
2. Add black-box Eio tests proving that work runs on another domain, completion
   runs on the submitting domain, expected result errors are preserved, and
   cancellation suppresses completion.
3. Change Tree-sitter request identity from one client-global generation to
   per-Code/per-buffer generations.
4. Run Code highlighting through `Background` and implement one-running plus
   one-latest-pending admission with stale-result rejection.
5. Add integration tests covering two Code owners sharing one parser client,
   destruction during work, rapid content replacement, parser failure, and
   final render invalidation.
6. Benchmark Tree-sitter submission and establish the default worker-count
   guidance.
7. Evaluate large/streaming Markdown and copied-pixel image work separately;
   add them only with evidence and the documented ownership boundary.

## Acceptance criteria

- one application-owned background value reuses its executor domains and no
  consumer creates a private pool;
- default guidance reserves the submitting Eio domain and starts with one CPU
  worker rather than silently using every recommended domain;
- worker code runs on an executor domain and its completion callback runs on
  the submitting Eio domain;
- worker inputs and outputs are owned ordinary OCaml data and no renderer,
  renderable, Yoga, buffer, event, terminal, or native handle reaches worker
  code;
- expected feature failures remain typed results, while unexpected worker and
  completion exceptions follow the surrounding Eio failure policy;
- cancellation prevents a later owner callback without claiming that an
  already-running CPU operation was forcibly terminated;
- `Event_queue`, runtime `Wakeup`, event channels, renderer dispatch, and frame
  ordering are unchanged;
- Code owns per-consumer generations and at most one running plus one latest
  pending highlight request;
- two Code renderables sharing one Tree-sitter client cannot invalidate one
  another's results;
- stale or post-destruction results perform no mutation, emit no component
  event, and request no render;
- an accepted result is applied through existing owner-domain setters and
  requests a normal coalesced future frame;
- parser functions used by workers have an explicit worker-safety contract and
  never depend on concurrent access to the client registry;
- black-box tests prove execution-domain separation, result handoff,
  cancellation, staleness, shared-client independence, and lifecycle cleanup;
  and
- benchmarks record the responsiveness benefit and overhead before Markdown,
  image, additional workers, affinity, or mailbox mechanisms are enabled.
