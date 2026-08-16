> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** REFUTED ON ITS STATED TARGET 2026-08-16: the note measured DataCopy 8-of-8; DataCopy now reports 0 inherited-bare. The rule still fires on drag-lint own source (18) -- re-file from there if it is still wrong.

# `inherited-bare` fires on destructors and message handlers, where bare `inherited` is the ONLY correct form

Measured on DataCopy 2026-08-13: **8 of 8** findings were the canonical idiom.

    destructor TConfigurationService.Destroy;   uConfigurationService.pas:900
    destructor TErrorLogger.Destroy;            uMainZeissCopy.pas:4167
    destructor TDestinationIndex.Destroy;       uFileUtils.pas:539
    destructor TAlertGrouper.Destroy;           uAlertGrouper.pas:305
    destructor TShareProbeThread.Destroy;       uShareMonitor.pas:408
    destructor TShareMonitor.Destroy;           uShareMonitor.pas:508
    destructor TTransferThread.Destroy;         uTransferThread.pas:611
    procedure TfrmZeissCopy.RestoreWindow(var msg: TMessage);   uMainZeissCopy.pas:4113

## Why this is noise rather than a false positive

The rule's claim is TRUE -- these ARE bare `inherited` calls -- so they were
`allow`ed rather than marked as rule defects. But its message,
"verify it invokes the intended ancestor method", asks for a check that cannot
fail in these two contexts:

* **A destructor.** `inherited;` in `destructor Destroy` calls the ancestor
  `Destroy`. There is no other method it could resolve to, and omitting it leaks.
  Every Delphi destructor in existence ends this way.
* **A message handler** (`procedure X(var Msg: TMessage); message WM_...`). Bare
  `inherited` is the required form: it dispatches to the ancestor's handler for
  the same message. Writing the name explicitly is the unusual choice here.

So the rule can only ever produce a finding-per-destructor across any codebase.
On DataCopy that is 7 of its 15 files.

## Suggested fix

Skip when the enclosing routine is a `destructor`, or is a method carrying a
`message` directive.

**Note this is NOT trivially expressible in the .scm.** The current query is

    ((inherited) @warn (#match? @warn "(?i)^inherited\s*;?\s*$"))

and tree-sitter queries have no arbitrary-depth descendant operator, so the
enclosing routine cannot be reached from the `inherited` node by pattern alone
(the `inherited` sits inside the routine's statement block, not as a direct
child). Either:

1. add a post-filter in Delphi alongside the other query rules, keyed on the
   enclosing routine kind -- `EnclosingDefProc` already exists in
   `DRagLint.Diagnostics.AstChecks.pas` and answers exactly this; or
2. extend the rule JSON with a `skip_in` list the query runner applies.

Option 1 matches how `try-except-swallowed` and friends already work.

## Related

The same shape of question -- "the finding is true but the code has no other
sensible form" -- is what `allow` exists for, and using it here is correct. But
a rule that fires once per destructor forever will keep re-appearing in every
project's first LoopZero round, and each one costs 8 markers.
