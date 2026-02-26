# Phase 02: Poller Backend Consistency

This phase fixes the `register_fd` contract inconsistency across the three poller backends (Poll, Linux epoll, and kqueue). Currently, the Poll fallback backend correctly updates an existing fd registration, but Linux always uses `EPOLL_CTL_ADD` (which fails with EEXIST on re-register) and kqueue only adds filters without removing previous ones. This makes the same API call sequence behave differently by platform. By the end of this phase, all three backends will support idempotent re-registration semantics.

## Tasks

- [x] **BUG-003: Standardize Linux poller register_fd to update existing registrations.** In `src/termisu/event/poller/linux.cr` at line ~60, `register_fd` always uses `EPOLL_CTL_ADD`. If the same fd is registered again (e.g., with different event flags), this fails with `EEXIST`. Fix by:
  - Try `EPOLL_CTL_ADD` first
  - If result < 0 and `Errno.value == Errno::EEXIST`, retry with `EPOLL_CTL_MOD` using the same event struct
  - This makes the operation idempotent: re-registering with different flags updates the registration
  - Keep the error raising for any other errno (not EEXIST)
  - **Done:** Added EEXIST→EPOLL_CTL_MOD fallback in `register_fd`. Added two new specs verifying idempotent re-registration and unregister/re-register. All 1079 tests pass, ameba clean.

- [x] **BUG-003: Standardize kqueue poller register_fd to replace previous filters.** In `src/termisu/event/poller/kqueue.cr` at line ~63, `register_fd` adds read/write filters with `EV_ADD` but never removes previous filters for the same fd. On re-registration, filters accumulate instead of being replaced. Fix by:
  - Before adding new filters, explicitly delete any existing filters for this fd using `EV_DELETE` for both EVFILT_READ and EVFILT_WRITE
  - Use a "delete then add" pattern: apply EV_DELETE changes first (ignore ENOENT errors), then apply EV_ADD changes for the requested events
  - Or track which filters are active per fd and only apply the delta
  - The goal: calling `register_fd(fd, events)` twice with different events should result in only the second set of filters being active
  - **Done:** Added "delete then add" pattern in `register_fd`. When the fd is already in `@registered_fds`, both EVFILT_READ and EVFILT_WRITE are deleted (with `ignore_errors: true` to handle ENOENT) before applying the new filters. This follows the same pattern already used by `unregister_fd`. All 1079 tests pass, ameba clean. Note: kqueue-specific behavior can only be verified on macOS/FreeBSD.

- [ ] **BUG-003: Add backend-specific specs verifying idempotent register_fd behavior.** In the spec files for each poller (`spec/termisu/event/poller/...`), add tests that verify:
  - Registering fd for READ events, then registering same fd for READ|WRITE events, succeeds
  - The second registration updates the event mask (doesn't fail with EEXIST on Linux, doesn't accumulate filters on kqueue)
  - Unregistering and re-registering the same fd works
  - Use the poller interface directly and verify behavior matches the documentation

- [ ] **Run `bin/hace spec` and `bin/hace ameba` to verify all changes pass tests and linting.** Focus on the poller specs to confirm cross-platform consistency.
