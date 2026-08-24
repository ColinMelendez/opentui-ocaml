# Terminal suspend and resume

Status: research stub; no implementation has started.

This feature will add the renderer lifecycle needed to temporarily relinquish
terminal ownership and later restore the TUI. It is separate from pausing the
render loop and from palette detection. The immediate motivation is parity
with OpenTUI and support for OpenCode's `Ctrl-Z` terminal-suspend workflow.

## Purpose

A full-screen terminal application owns more than a render loop. It may own
the alternate screen, raw input mode, mouse tracking, keyboard protocols,
cursor state, terminal keepalives, and a serialized output path. A suspend
operation must make that ownership safe to hand back to the shell or another
foreground process. Resume must restore the terminal and repaint from the
retained UI state without requiring the application to be restarted.

This is a quality-of-life feature rather than a prerequisite for ordinary
rendering. It is nevertheless a meaningful compatibility gap for applications
that follow Unix job-control conventions or launch interactive external
commands.

## Reference correspondence

| Reference behavior | Expected OCaml responsibility |
| --- | --- |
| `vendor/opentui/packages/core/src/renderer.ts` `suspend()` | Core renderer lifecycle: stop rendering, flush owned output, disable terminal-facing features, and enter a suspended control state. |
| `vendor/opentui/packages/core/src/renderer.ts` `resume()` | Core renderer lifecycle: restore input/output ownership, recover dimensions and protocol state as needed, restore the previous control state, and force a complete repaint. |
| `vendor/opentui/packages/core/src/zig/renderer.zig` `performShutdownSequence()` | Native terminal cleanup: reset terminal modes, leave the alternate screen or clear the owned main-screen region, restore cursor state, and clean up graphics protocols. |
| OpenCode `terminal.suspend` | Application policy: register `SIGCONT` to resume, suspend the renderer, and send `SIGTSTP` to the foreground process group. |

The reference renderer's `suspend()` is more than `pause()`: `pause()` stops
render scheduling, while `suspend()` temporarily gives up terminal ownership.
OpenCode's signal handlers are application code; the renderer does not decide
when the process should be stopped.

## Known reference behavior

The reference currently does the following on suspend:

- remembers the prior renderer control state;
- stops the render loop and invalidates scheduled frames;
- flushes pending split-footer output before changing terminal state;
- disables mouse input, keyboard protocols, input listeners, and keepalives;
- pauses or resets parser state according to any incomplete protocol response;
- cancels pending theme refresh work;
- resets native terminal state and leaves the alternate screen, or clears the
  renderer-owned main-screen region according to `clearOnShutdown`;
- restores non-raw stdin mode and pauses stdin.

On resume it:

- restores raw mode and input listeners;
- drains already-buffered input safely;
- re-establishes terminal setup and native renderer state;
- restores mouse and keyboard features that were enabled before suspension;
- handles screen-mode changes and pending pixel-resolution queries;
- forces a full repaint;
- restores the previous control state and restarts continuous rendering only
  when that was the prior state.

The transition must remain correct when the terminal is resized while the
process is stopped. Pending output must not interleave with shell output, and
the next frame must use the current terminal dimensions.

## OpenCode usage

OpenCode v2 exposes a hidden `terminal.suspend` command bound to `Ctrl-Z` on
POSIX systems. Its handler registers a one-shot `SIGCONT` callback that calls
`renderer.resume()`, calls `renderer.suspend()`, and then sends `SIGTSTP` to
the process group. The shell can then run commands normally; `fg` resumes the
OpenCode process and triggers the renderer restoration path.

The binding is disabled on native Windows, where POSIX job-control signals are
not available. The OCaml API should not pretend that process suspension is
portable; terminal lifecycle operations and application signal policy should
remain separate.

## Current OCaml gap

`opentui-core` currently has no renderer-wide suspend/resume lifecycle. The
palette implementation therefore documents the reference's
"palette detection is rejected while explicitly suspended" rule as an
unreachable state rather than adding a palette-only flag. A future renderer
suspend state must become authoritative for palette queries, theme refresh,
capability queries, input parsing, output delivery, and renderer scheduling.

## Design questions to resolve

- Should `Renderer.suspend` and `Renderer.resume` be synchronous state
  transitions, result-bearing operations, or an application-owned lifecycle
  service around the renderer?
- Which terminal cleanup belongs to native Raw and which belongs to the Eio
  terminal session and output owner?
- How are in-flight palette, theme, capability, pixel-resolution, and other
  deferred requests completed when suspension interrupts their terminal I/O?
- Are requests cancelled, paused for resume, or completed with a structured
  `Suspended` error?
- How are feed-backed output, captured stdout, scrollback, and split-footer
  state flushed and restored without shell-output interleaving?
- What is the behavior for repeated, nested, or invalid suspend/resume calls?
- Which dimensions and terminal capabilities must be re-queried after a
  `SIGCONT`, and which responses can safely be preserved across suspension?
- Should Core expose only terminal ownership transitions while an application
  helper provides POSIX signal integration and external-command execution?

## Non-goals for the initial design

- Implementing POSIX signal handling inside portable Core.
- Replacing `pause`, `stop`, or `destroy` with a compatibility alias.
- Making palette detection independently track a second suspension flag.
- Promising suspend/resume semantics on platforms without equivalent terminal
  job control.

## Initial acceptance criteria

The eventual implementation should demonstrate, at minimum:

- terminal modes, raw input, mouse/keyboard protocols, and cursor state are
  restored after a suspend/resume cycle;
- no render frame or terminal query is emitted while ownership is suspended;
- the prior render control state is restored, including live rendering;
- a resize while suspended produces a correct full repaint after resume;
- pending output is flushed or completed before suspension and cannot
  interleave with shell output;
- every interrupted deferred operation has an explicit structured completion
  path;
- palette/theme/capability services obey the authoritative renderer lifecycle
  state;
- application-level `SIGTSTP`/`SIGCONT` integration can be built without
  reaching into Raw internals.
