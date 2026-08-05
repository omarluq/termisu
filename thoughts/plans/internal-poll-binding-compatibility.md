# Internal Poll Binding Compatibility Plan

## Goal

Stop patching global `LibC` for `poll(2)` support so Termisu can coexist with shards like `systemd.cr` that define the same missing bindings.

## Context

- Current collision points:
  - `src/termisu/event/poller/poll.cr`
  - `src/termisu/reader.cr`
- Both files currently reopen `lib LibC` and define:
  - `Pollfd`
  - `NfdsT`
  - `poll`
  - `POLL*` constants
- This creates shard-to-shard compile conflicts when another dependency patches `LibC` too.

## Design Decision

Use a **Termisu-private poll binding namespace** instead of global `LibC` patching.

Preferred namespace:

- `Termisu::System::Poll`

Why:

- avoids cross-shard symbol collisions
- needs no consumer flags or compile-time coordination
- keeps runtime behavior unchanged
- centralizes poll fallback support in one place

## Implementation Checklist

### Phase 1: Add shared internal binding

- [ ] Create shared binding file
- [ ] Use a Termisu-private namespace
- [ ] Define `Pollfd`
- [ ] Define `NfdsT`
- [ ] Define `poll`
- [ ] Define `POLLIN`, `POLLOUT`, `POLLERR`, `POLLHUP`, `POLLNVAL`
- [ ] Preserve platform-specific `NfdsT` sizing

### Phase 2: Migrate fallback poller

- [ ] Update `src/termisu/event/poller/poll.cr`
- [ ] Require the new shared binding file
- [ ] Replace `LibC::Pollfd`
- [ ] Replace `LibC::NfdsT`
- [ ] Replace `LibC.poll`
- [ ] Replace `LibC::POLL*`
- [ ] Remove inline `lib LibC` poll declarations

### Phase 3: Migrate reader fallback

- [ ] Update `src/termisu/reader.cr`
- [ ] Require the new shared binding file
- [ ] Replace `LibC::Pollfd`
- [ ] Replace `LibC::NfdsT`
- [ ] Replace `LibC.poll`
- [ ] Replace `LibC::POLL*`
- [ ] Remove inline `lib LibC` poll declarations

### Phase 4: Cleanup verification

- [ ] Search for remaining `fun poll`
- [ ] Search for remaining `struct Pollfd`
- [ ] Search for remaining `alias NfdsT`
- [ ] Confirm only the internal binding owns poll support

### Phase 5: Validation

- [ ] Run focused checks for `Reader`
- [ ] Run focused checks for fallback `Poller::Poll`
- [ ] Run relevant specs
- [ ] Run broader checks if focused validation passes

## Patch Plan

### New file

Create:

- `src/termisu/system/poll.cr`

Add:

- Termisu-private binding namespace
- `Pollfd` struct
- platform-correct `NfdsT`
- `poll` function binding
- `POLL*` constants used by reader and fallback poller

### File: `src/termisu/event/poller/poll.cr`

Planned edits:

- add require for shared poll binding
- remove local `lib LibC` poll patch block
- replace all poll-specific `LibC` references with the internal namespace

Watchpoints:

- typed arrays of pollfds
- `uninitialized` locals
- event-mask translation helpers
- preserving existing timeout and error behavior

### File: `src/termisu/reader.cr`

Planned edits:

- add require for shared poll binding
- remove local `lib LibC` poll patch block
- replace poll-specific `LibC` references in `check_fd_readable_poll`

Watchpoints:

- keep select-based path unchanged
- keep EINTR behavior unchanged
- keep current readable/error semantics unchanged

## Validation Notes

This is a **compatibility refactor**, not a behavior change.

Expected unchanged behavior:

- same poll timeout semantics
- same fd readability semantics
- same error handling
- same platform-specific ABI for `NfdsT`

## Risks

- namespace choice may affect readability if too close to `LibC`
- accidental behavior drift if only some `POLL*` references are migrated
- incorrect `NfdsT` sizing would create ABI issues on BSD/Darwin vs Linux

## Suggested Commit Message

`internalize poll bindings to avoid LibC conflicts`

## Reference

- `src/termisu/event/poller/poll.cr`
- `src/termisu/reader.cr`
- LavinMQ PR: `cloudamqp/lavinmq#1589`
