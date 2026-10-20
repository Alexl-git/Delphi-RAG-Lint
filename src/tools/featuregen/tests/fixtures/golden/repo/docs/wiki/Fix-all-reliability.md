# Fix all: owner freshness, busy guard, exception-class prefix (1.31.3-alpha)

Three fixes to the autofix path (CLI `lint --fix` / `--apply` and the IDE "Fix all in unit").

* **Library-root members no longer make an owner stale.** A `.dproj` member that lives under a
  registry library root (for example `ArrayHelper.pas`) is not owned by the project and is ignored
  by the multi-project rename freshness check. Before, the owner was permanently stale and every
  rename was dropped. The CLI now prints `autofix: nothing written -- N rename(s) dropped: <reason>`.
* **IDE wait cursor and single fix at a time.** While a fix job runs the Structure form shows the
  wait cursor; a second Fix all is refused instead of queued.
* **Exception classes keep their `E` prefix.** `EKeyViolation = class(EDatabaseError)` is no longer
  reported by `type-name-prefix` and is not renamed to `TEKeyViolation`.

See also [[Fix-all-in-unit]] and [[Fix-all-in-project]].
