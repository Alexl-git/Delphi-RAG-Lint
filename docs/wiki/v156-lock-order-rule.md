# Lock order inversion rule (THR)

One rule, `lock-order-inversion`, finds the classic two-lock deadlock: one place takes lock A
and then lock B, another place takes B and then A. A thread at the first place and a thread at
the second can each hold one lock and wait for the other forever. The program hangs with no
exception and no log.

The rule is project-wide. It runs in `lint-all` only, because the two places are in different
routines and often in different units:

```
drag-lint lint-all --db <project.sqlite> --rule lock-order-inversion
```

It is ON by default, severity warning, category bug-patterns. Switch it with `--enable` /
`--disable` or in the configuration like any other rule.

## What is reported

Both places of an inversion get a finding:

* **directly** -- on the call that takes the second lock while the first is held:

  ```pascal
  procedure TBank.AThenB;
  begin
    FLockA.Enter;
    try
      FLockB.Enter;      // finding: FLockB taken while FLockA is held; BThenA takes them the other way
  ```

* **through a call** -- on the call of a routine that takes the second lock, itself or through
  the routines it calls (four calls deep at most):

  ```pascal
  procedure TVia.Outer;
  begin
    FLockE.Enter;
    try
      TakeF;             // finding: TakeF takes FLockF while FLockE is held; Reverse takes them the other way
  ```

The message names the two locks, the line where the first was taken, and the routine, file and
line of the opposite order. A place with several opposite places names the first one.

## Which locks count

The locks are the lock sites of the index: `TCriticalSection` (Enter / Acquire),
`TMonitor.Enter(Obj)`, `EnterCriticalSection`, read-write locks (BeginRead / BeginWrite),
`TMutex`, `TSpinLock`, `TThreadList.LockList`, and project classes that descend from a lock
class. A lock is compared across routines only when it is known exactly:

* a field of the routine's own object (`FLock`, `Self.FLock`),
* a unit-level variable,
* the object itself (`TMonitor.Enter(Self)`).

## What stays silent

* The same order everywhere.
* A lock that is a local variable, a parameter, a field of another object (`pOther.FLock`), a
  property or an expression (`FLocks[I]`): the rule cannot know that two routines mean the
  same lock.
* A try-enter (`TryEnter`, `TMonitor.Enter(Obj, Timeout)`): a failed try does not wait.
* A lock that is already held where it is taken again (re-entered).
* A read-write lock taken for reading at both places: readers do not block readers. One writer
  is enough for a finding.
* Two orders that both run under one common third lock: they cannot interleave.
* Two locks taken one after the other, the first released before the second is taken.

## Limits

* A field lock is assumed to belong to the same object in both places. Two objects of one
  class, each locking its own field, are reported as one lock.
* Source order stands in for control flow: a lock released in one branch of an `if` counts as
  released from that line on.
* A lock taken inside an anonymous method counts under the routine that declares it, although
  the body may run later on another thread.
* A lock taken and left by a pair of wrapper routines (`Lock` / `Unlock`) is seen as taken by
  the caller only through the call rule; the stretch it is held over in the caller is not
  known.
* `with` receivers are not followed, and `TMutex.WaitFor` is not counted as taking the mutex.
* Calls the index did not resolve (method pointers, events) are not followed.

## Reviewing a finding

Fix the order: take the two locks in one order everywhere, or replace them by one lock. When
the two places can never run at the same time (the same thread, start-up code), mark the line
with a `dl:ok lock-order-inversion` review that says why.
