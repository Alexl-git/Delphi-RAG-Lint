<!-- Owner-decision background for BACKLOG-TRIAGE-2026-09-28 section 2 (DEC-1..DEC-19), researched 2026-09-28 by three read-only agents against engine 1.20.0-alpha. Rulings are recorded in the triage doc, not here. -->
# Owner decisions DEC-1 .. DEC-19 -- detailed background

## TRIAGE 2026-10-25 (walkthrough D11 c, staleness pass; docs only)

Closed by events (marker under each heading): DEC-2, DEC-5, DEC-6, DEC-7, DEC-8, DEC-12, DEC-13, DEC-19.

DEC-4 (document --apply deletes fact lines the DB cannot see) -- NOT closed, state verified with git log: ENG-4
shipped (277cf798 "project tags on shared doc facts + doc-forget") and 7ffcbaa2 "writers keep what they cannot
see -- B-05/B-06/B-07" landed on top. The write-up's own gate -- re-run the DataCopy reproduction on the current
engine -- has NOT been done (it needs a write to a real DataCopy file). Left for the owner / an ENGINE slot.

LEFT FOR THE OWNER (write-up recommendation in brackets):
* DEC-1 LSP programme trigger "A1 lands" -- which A1? [schedule the LSP programme]. Also the trigger for the parked DEC-2 note.
* DEC-3 untagged legacy fact line deletion (ENG-4 deviation) [follow the settled design].
* DEC-4 re-run the DataCopy repro, then (a) hard invariant or (b) lighter follow-up [verify first].
* DEC-9 meaning of Covered by:.
* DEC-10 LSP full built-in suite for non-IDE clients.
* DEC-11 {$SCOPEDENUMS} extractor fact for enum-bare-read-scoped.
* DEC-14 force a mid-session VS Code engine refresh [retire].
* DEC-15 committed= counter on the section summary line [park/close].
* DEC-16 lint the legacy "// note // dl:shared A" marker [won't-fix].
* DEC-17 flip ShowInfoInline [leave off].
* DEC-18 DCU-only library indexing [keep parked].
Not independently re-verified here: the DEC-7 and DEC-8 closures rest on the walkthrough's wording, not on a fresh git check.
# Owner decisions DEC-1 .. DEC-6 -- detailed background
Prepared 2026-09-28. Source: docs/BACKLOG-TRIAGE-2026-09-28.md section 2, the
INBOX notes it names, docs/superpowers/plans/2026-09-24-followups-d20-d30.md,
git log, and the deployed engine (third_party/dll-win64/drag-lint.exe,
measured live: version 1.20.0-alpha / extractor 1.20.0-alpha / resolver
1.11.0-alpha). Read-only pass; no database was indexed or written; no source
file was edited.

---

## DEC-1 -- LSP programme trigger "A1 lands" -- which A1?

### 1. The question in one sentence
The LSP merge programme (diagnostics + completion merging into the IDE's
DelphiLSP session) is parked with the re-start condition "when A1 lands" --
and two different things in this repo are both plausibly "A1", one of which
already shipped 11 days ago and one of which has not been built at all.

### 2. What the thing is
"The LSP programme" (label C4 in prior triage docs) is a plan to make VS
Code / Zed / any DelphiLSP-based editor show drag-lint's findings and
completions INSIDE the same editor session as the real Pascal language
server, instead of as a separate, disconnected tool. drag-lint runs a proxy
process (drag-lint lsp --proxy) that sits between the editor and the real
DelphiLSP, relaying every JSON-RPC frame untouched today (Phase 1a, shipped).
The programme's next steps teach that proxy to OPEN and MODIFY frames: merge
its own lint findings into DelphiLSP's textDocument/publishDiagnostics
notifications, and merge its own completion items into
textDocument/completion responses.

Example of what a merged diagnostic would look like to VS Code (today
DelphiLSP's own compiler diagnostics and drag-lint's lint findings are two
unrelated things a user has to check separately):

  publishDiagnostics(uri, [
    { source: "delphilsp", message: "E2003 Undeclared identifier" },
    { source: "drag-lint", message: "unused-public-symbol: TFoo.Bar" }
  ])

"A1" is shorthand from an earlier planning pass (BACKLOG-SESSION-100-TRIAGE.md:22,
now retired but still the authoritative naming) for "row 5" of the six things
the park depends on: the exception-HANDLING fact -- i.e. the ability to
know, for a try..except on E: X do ... block, which exception classes a
routine catches and what it does with them (swallow / re-raise / show a
dialog / raise a different class). There are, however, TWO different things
in the repo that both answer to that one-line description:

* The doc/hover fact -- a Catches: line drag-lint writes into a routine's
  DocInsight comment (and shows on hover), computed at DOCUMENT TIME by
  scanning source text, no index column involved.
* The index ref-kind fact -- a refs.kind = 'handle' (paired with
  refs.kind = 'raise') row written by the EXTRACTOR at index time, so a SQL
  query can find every throw/catch site across a whole project DB.

### 3. How we got here
* 2026-08-31 (owner ruling, session 56): parked the whole LSP merge
  programme on opportunity cost, not doubt -- "lets park it for now ... Maybe
  in a week or 2 we will restart it." (docs/INBOX-lsp-merge-work-parked-until-mid-september.md:22-32).
* 2026-09-16 (owner re-ruling): the "restart in 1-2 weeks" date had
  quietly expired (2026-09-14) with nothing restarted, which the note calls
  out as a park silently decaying into an oversight. The owner changed the
  park from a DATE to a TRIGGER: "revisit when row 5 (item 3, the
  exception-HANDLING fact) lands" (docs/INBOX-lsp-merge-work-parked-until-mid-september.md:1-17).
  This is the ruling now in force. "Row 5" traces to a numbered backlog table
  from that session where row 5 was one line reading "the exception-HANDLING
  fact" with no further disambiguation between the two things above.
* 2026-09-17, commit 74e9ddd0: the doc/hover Catches: line SHIPPED
  (feat(autodoc): Catches: -- the exceptions a routine HANDLES (gap 3 of
  INBOX-report-exceptions-raised-and-handled)). This is entirely a source-text
  scan at document time (TDocFactsBuilder.MineHandlers); the commit message
  is explicit that this was chosen over an index-time symbol_facts column: no
  extractor bump, no reindex, no silently-stale rows. No refs.kind or
  schema change of any kind.
* 2026-09-23/24, the followups plan: while planning the next batch of
  engine work, docs/superpowers/plans/2026-09-24-followups-d20-d30.md:193
  reused the exact same "A1 exception HANDLING fact" wording for the OTHER
  thing -- the refs.kind INDEX fact (raise/handle), citing
  INBOX-no-raise-handle-fact-blocks-exception-paths.md and calling it "the
  row 5 trigger for the LSP (C4) and editor (C5) programmes" -- i.e. the plan
  author read the same "A1" label as still meaning the unshipped index fact,
  not the shipped doc fact. That index-level A1 has NOT been built; it sits
  in the plan's "next extractor batch" bucket (section 5 of the same plan),
  unscheduled.
* 2026-09-16, BACKLOG-SESSION-100-TRIAGE.md:22 already flagged this
  exact ambiguity in writing (superseded doc, but the flag was carried
  forward verbatim into BACKLOG-TRIAGE-2026-09-28.md row DEC-1): "if the
  trigger meant the doc-time Catches: line, it fired 09-17 and nobody
  re-triaged; if it meant the index fact, it has not fired. Rule on it."
  Nobody has ruled on it since; it is carried into this triage unresolved.

### 4. Current behaviour today
* The doc/hover Catches: fact is live and shipping in every document
  run today (confirmed shipped, commit 74e9ddd0, 2026-09-17).
* The index-level raise/handle ref kind does NOT exist. Measured live on
  this session's own self-index (src\cli\_D-RAG\drag-lint.sqlite, engine
  1.20.0-alpha):

    kind           COUNT(*)
    read           83910
    call           40791
    member-access  37872
    type_use       22344
    write          17986

  No raise, no handle. (Matches the CLIENT-DB measurement in
  INBOX-no-raise-handle-fact-blocks-exception-paths.md:15-29, taken on an
  older engine -- the gap is unchanged across four resolver/extractor bumps.)
* No LSP merge code has shipped: grepping CHANGELOG.md for
  ProxyMergeCompletion / "merge-completion" / "diagnostics merge" returns
  nothing. The proxy (src\lsp\DRagLint.LSP.Proxy.pas) is still the
  transparent, byte-identical relay described in INBOX-c6-lsp-phase2-plan.md
  section 2 -- no JSON parsing, no request tracking, no store.
* The park itself (INBOX-lsp-merge-work-parked-until-mid-september.md) is
  still status=parked-owner and has not been touched since 2026-09-16.

### 5. The options
* (a) The trigger meant the doc/hover fact. It fired 2026-09-17 and the
  programme has been unblocked, silently, for 11 days.
  Cost to actually execute the programme from here: per the last sizing
  (BACKLOG-SESSION-100-TRIAGE.md:150-155), C4.3 shared stub test harness
  (~1 day) -> C4.2 diagnostics merge, the priority item (~2.5-3.5 days) ->
  C4.4 completion merge, riding C4.2's substrate (~1.5-2 days) -> C4.6 LSP
  built-in checks for non-IDE clients (~1 day, itself a further decision,
  see DEC-10 in the wider backlog) = about 6-7 person-days total, no
  extractor or resolver bump anywhere in it (explicitly ruled out in
  INBOX-c6-lsp-phase2-plan.md section 5: "Do NOT bump
  DRAGLINT_EXTRACTOR_VERSION. Nothing here changes extraction").
  Risk: this is a 3-4 day single-tenant window on drag-lint's own build/test
  machine (per the 2026-08-31 owner ruling that stopped it the first time),
  though the isolation recipe (own worktree, own DB, never touch
  third_party/dll-win64) in INBOX-lsp-merge-work-parked-until-mid-september.md:64-91
  was proven to let other drag-lint work continue in parallel.
  Unblocks: the entire editor-integration-programme's most requested item
  (the owner called diagnostics merging "a very useful feature ... should
  be done ASAP" in the session that then parked it) and, per DEC-1's own
  row, "unblocks the most work" of any decision in this triage.
* (b) The trigger meant the index fact. It has not fired; the programme
  stays parked until it is built.
  Cost: see DEC-2 below -- an extractor bump (a full ~4h48m re-parse of
  every index) plus the (already-designed, see the ask in
  INBOX-no-raise-handle-fact-blocks-exception-paths.md:54-70) extractor
  work to emit raise/handle ref kinds, rated L in the backlog.
  Whichever way DEC-2 is ruled, this option means the LSP programme waits
  on that separate decision.
* (c) Re-word the trigger now, independent of which reading is "correct".
  Since the park's own text says "a date is a worse park than a trigger --
  if the trigger is what you want changed, change the trigger, not the
  date," the cleanest resolution may not be picking (a) or (b) at all, but
  deciding explicitly what SHOULD gate the programme going forward (e.g. "the
  doc fact was enough, start now" or "wait for both facts" or "wait for
  something else entirely") and writing that down so this ambiguity cannot
  recur.

### 6. Recommendation
Recommendation: rule (a) -- the doc/hover Catches: fact was the intended
trigger, it shipped 2026-09-17, and the LSP programme (C4.3->C4.2->C4.4->C4.6,
~6-7 days) should be scheduled. Reasoning: the doc/hover fact directly
serves the stated reason for wanting exception information in an editor
context (a human reading/hovering code), while the index-level fact primarily
serves the SEPARATE exception-paths diagram feature (DEC-2, a charts/graph
consumer, not an editor consumer) -- nothing in the original park's wording
ties the LSP programme to a SQL-queryable fact rather than a human-readable
one. Whichever way it is ruled, write the answer into
INBOX-lsp-merge-work-parked-until-mid-september.md itself so the trigger
cannot mean two things a second time.
---

## DEC-2 -- Is the raise/handle index fact still wanted?

> **REOPENED + done 2026-10-28 (owner).** The 2026-10-25 CLOSED banner is overridden: the channel also covers the long one-shot runs `index` (single root, `--project`, `--all`) and `lint-all` (gate: ControlChannelEnabledFor). `index` stops BETWEEN FILES at the storage layer file-transaction gate (no half-written file row, WAL checkpointed, connection closed, resolver stamp cleared so the resume re-derives edges, exit code 4); `lint-all` stops between files and prints the findings so far as PARTIAL (exit 4). `sql` is NOT widened (one guarded SELECT; a kill is harmless). Owner addition: build\stage-engine.ps1 and the installer ask through the channel first, kill only as the last resort. Wiki: docs\wiki\ide-release.md "The full update sequence".

### 1. The question in one sentence
Should the extractor be taught to write refs.kind = 'raise' /
refs.kind = 'handle' rows (so SQL/lint/graph tooling can distinguish a
raise Foo.Create from an on E: Foo do), now that the one team that asked
for it has already shipped a workaround?

### 2. What the thing is
Today, when the extractor sees a reference to an exception class, it
records it exactly like any other type reference: refs.kind = 'type_use'.
The SAME kind is produced by all three of these, which look nothing alike to
a human but are indistinguishable in the index:

  raise EMicroniteError.Create('...');     // a THROW
  except on E: EMicroniteError do ...      // a HANDLER
  var E: EMicroniteError;                  // neither

The ask (INBOX-no-raise-handle-fact-blocks-exception-paths.md:54-70) is
narrow and syntactic: two new refs.kind values, no flow analysis, no
cross-unit resolution -- "a refs.kind of raise on the type reference in a
raise statement, and a refs.kind of handle on the type reference in an
on E: T do clause," ideally with a bare except also recorded against its
enclosing routine ("this routine swallows everything" being, in the note's
words, "the single most useful thing such a chart can say").

### 3. How we got here
* 2026-09-23, filed from the "charts" session (a downstream consumer that
  builds architecture diagrams by querying drag-lint's index/CLI): this was
  "GAP 2", one of several missing facts blocking their diagram catalogue.
  Measured live at the time on the CLIENT DB (v=1.17.0-alpha/r=1.6.0-alpha):
  the complete refs.kind set was read/type_use/call/member-access/
  write/event-binding/attribute/di-unresolved/di-resolve -- no
  exception-shaped kind, and symbol_facts has no exception column either
  (INBOX-no-raise-handle-fact-blocks-exception-paths.md:17-34).
  The note explicitly says the team is doing nothing meanwhile: "We are not
  going to ship a diagram that draws a handler as a thrower ...
  exception-paths stays unbuilt."
* 2026-09-23, commit 1c2e4883 (docs(charts): exception-paths SHIPPED --
  syntax, parameters and limits (solid only when the call site is verified
  inside the try; never 'unhandled'); 21 questions shipped, 3 in flight):
  the charts team shipped exception-paths anyway, using their OWN
  raise/handler detection built on top of what the index already has (type
  references plus their own AST-level scan for the syntactic shapes), rather
  than the requested refs.kind values. This is the "GAP 2 workaround"
  DEC-2 refers to. The commit only touches docs (README.md, two wiki pages,
  a features HTML page) -- no engine or schema change, confirming this is a
  consumer-side workaround, not a fix to the underlying gap.
* 2026-09-24, docs/superpowers/plans/2026-09-24-followups-d20-d30.md:193
  logged the ask as still open, in the "next extractor batch" bucket
  (unscheduled), labelling it the "A1" trigger for the LSP/editor
  programmes (see DEC-1).

### 4. Current behaviour today
Re-measured live this session on the engine's own self-index (src\cli\_D-RAG\drag-lint.sqlite,
engine 1.20.0-alpha, three extractor/resolver bumps after the original
measurement): the refs.kind set is still exactly
read/call/member-access/type_use/write -- no raise, no handle.
The gap is unchanged. --help confirms no CLI surface mentions a raise/handle
ref kind. The charts team's exception-paths diagram is live and shipped
(per the commit above) using its own detection, so nobody is currently
BLOCKED, but the underlying index fact the note asked for still does not
exist, and any OTHER consumer wanting the same information (the LSP
programme, per DEC-1's option (b); any future lint rule keying off
raise/handle sites) would have to duplicate the charts team's workaround or
wait for this to be built properly.

### 5. The options
* (a) Build it. Rated L, and it is an EXTRACTOR change (new refs.kind
  values are written by the parser/extractor stage, which is on the hashed
  extractor surface guarded by run_extractor_version_guard.ps1) -- so it
  requires bumping DRAGLINT_EXTRACTOR_VERSION, which forces a full re-parse
  of every index in the manifest (measured cost: ~4h48m, per this session's
  own briefing). It would need to land alongside the next extractor batch
  that is already accumulating other asks (ENG-12 framework-type fact, the P1
  Delphi 12 triple-quoted-string grammar work) so the ~5-hour cost is paid
  once for several features, not once per feature. Risk: none technical noted
  in the source note beyond the usual "a bare except..end also needs
  recording against the routine" design question the note flags as open.
  What it unblocks: a clean, SQL-queryable exception-paths for ANY consumer
  (not just charts' bespoke scan), and DEC-1 option (b) if that is how DEC-1
  is ruled.
* (b) Close it. Charts' workaround stands and answers the one team that
  asked. Cost: zero. Risk: any future consumer (LSP, a lint rule) re-derives
  the same syntactic scan charts already wrote, or is told to depend on
  charts' output rather than the index directly.
* (c) Park until a second consumer appears. Defer the decision itself;
  keep the note open as a live ask rather than closing it, revisit if/when
  the LSP programme (DEC-1) or another team asks for the same shape. Cost:
  zero now; the note stays as one more open item in every backlog sweep.

### 6. Recommendation
Recommendation: (c), park explicitly (not silently) until a second
consumer appears, and revisit together with whatever DEC-1 decides. The
one team that asked already has a working, shipped answer, so there is no
live pain today; paying a ~4h48m full re-parse for a single already-served
consumer is poor value. But do not fully close the note (option b), because
DEC-1 option (b) would create a second consumer immediately if that is how
DEC-1 is ruled -- so the two decisions are coupled and should be read
together, not independently.
---

## DEC-3 -- ENG-4 deviation: is deleting an untagged legacy fact line correct?

### 1. The question in one sentence
When a project's own index can see that a caller named in an old,
pre-tagging Called from: / Used by: doc-comment line no longer exists,
should that line be silently deleted (today's behaviour) or always
preserved, with cleanup left to an explicit doc-forget --untagged command
(the originally settled design)?

### 2. What the thing is
drag-lint's document command writes machine-managed fact lines into a
routine's DocInsight comment, e.g.:

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Called from: TFoo.Bar (uFoo.pas), TBaz.Qux (uBaz.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>

When a unit is used by MORE THAN ONE project (a "shared unit", e.g. a common
library unit YADF, YADFOT and YADFSetup all compile), each project's own
index only sees ITS OWN callers -- a project's index is exactly its compile
closure (see CLAUDE.md's per-project DB rule). So when project A regenerates
this comment, it cannot tell the difference between "this caller was
deleted" and "this caller belongs to project B, which I simply cannot see."
Since 2026-09-23 (ENG-4, commit 277cf798), each entry can carry a
bracketed PROJECT TAG, e.g. Called from: [YADF]Foo.A (a.pas),
[YADF,YADFOT]Foo.B (b.pas) -- each project adds/removes only ITS OWN tag on
each run, and an entry is deleted only when its tag set empties (i.e., every
project that ever saw it has now stopped seeing it). This is unambiguous and
correct for TAGGED entries. The open question is about UNTAGGED entries --
ones written by an OLDER engine, before tagging existed, which a
newly-tagging engine encounters for the first time.

### 3. How we got here
* 2026-08-13, the original multi-project shared-unit design
  (docs/superpowers/plans/2026-08-13-shared-unit-docs-and-menu.md:490-526):
  faced with the same narrow-vs-wide-project problem, the owner ruled
  "OPTION 1, the writer merges" -- a project's write UNIONS its own fresh
  render with whatever the stored block already had from other projects, and
  states the consequence explicitly: "entries can only accumulate. A caller
  deleted in ANOTHER project's code is never reaped by this project, because
  this project cannot see that it is gone -- it looks identical to an
  out-of-closure entry. Reaping is check-shared's job" (a separate,
  explicit command a human runs on purpose). This is the "settled design"
  the 2026-09-24 followups plan refers to.
* 2026-09-20/23, ENG-4 (docs/INBOX-document-apply-drops-facts-outside-the-db.md,
  commit 277cf798) rebuilt this mechanism with per-project TAGS instead of
  a plain union, specifically so that TAGGED entries COULD be reaped safely
  (a project now genuinely knows which entries are its own to manage). The
  commit message is explicit about the boundary: "entries carry
  [ProjA,ProjB] tags ...; a run adds/removes only its own tag, an entry
  goes when its set empties; UNTAGGED LEGACY ENTRIES KEEP THE OLD RULES."
  "The old rules" is a reference back to code that predates even the 2026-08-13
  union design -- a narrower, per-entry vouching rule.
* What "the old rules" actually do, read from the shipped code
  (src/doc/DRagLint.Doc.SharedFacts.pas:1206-1208, inside ReconcileContent,
  the one function both the drift-checker and the writer call):

    else if PlausibleEntry(Bare) and (not UnitVouchable(AStore, Bare)) and
            (not IsUncertainEntry(Bare)) then X := Bare
    else Continue;    // entry DROPPED

  i.e.: an untagged stored entry is kept ONLY IF this project's index CANNOT
  vouch for the unit the entry names (meaning: plausibly belongs to another
  project). If this project's index DOES hold that unit (can vouch for it)
  and its fresh scan no longer finds the caller, the line is silently
  dropped (Continue). This is a NARROWER, more aggressive rule than the
  2026-08-13 design's blanket "never reaped, that is check-shared's job" --
  it reaps automatically whenever THIS project happens to be able to see the
  named unit, which is exactly the deviation the 2026-09-24 plan's triage
  section flags: "an UNTAGGED legacy inbound entry is still reaped when this
  index holds its unit; settled design said 'never reaped'. Ruling needed"
  (docs/superpowers/plans/2026-09-24-followups-d20-d30.md:184).
* The mechanism for a HUMAN to do the cleanup on purpose already exists and
  shipped in the same ENG-4 commit: doc-forget --untagged "drops every
  UNTAGGED entry in a block that already carries tags -- the legacy lines no
  project claims" (src/doc/DRagLint.Doc.ProjectTags.pas:75-76, :88-89).

### 4. Current behaviour today
Confirmed by reading the shipped code (DRagLint.Doc.SharedFacts.pas:1206-1208,
unchanged since 277cf798, 2026-09-23; the engine deployed today, 1.20.0-alpha,
has had two further version bumps since ENG-4 but this logic is lint/doc-side,
not on the extractor/resolver hashed surfaces, so it would not have moved
incidentally): an UNTAGGED entry naming a unit the running project's index
holds, and whose fresh scan no longer finds the caller, is deleted the moment
ANY project with that unit in its closure runs document --apply against it
-- with no diff/warning naming what was removed (the same silent-success
shape as DEC-4 below). A TAGGED entry cannot be lost this way (only by every
tag legitimately emptying). The risk is real but narrow: it can only fire on
OLD doc comments written before ENG-4 shipped (2026-09-23) that have not yet
been touched by a tagging-aware document --apply run; every run from here
converts survivors to the tagged regime, so the exposure shrinks over time by
itself, but does not shrink to zero for callers that are ONLY EVER seen by a
project that never re-runs document on that unit.

### 5. The options
* (a) Ratify current behaviour -- ship the deviation as the new,
  intentional design: untagged legacy lines self-clean whenever a capable
  project's index happens to run over them. Cost: S (a documentation change
  only -- the code already does this; write down that this supersedes the
  2026-08-13 "never reaped" ruling, and update
  docs/superpowers/plans/2026-08-13-shared-unit-docs-and-menu.md's
  "Option 1" note to say so). Risk: exactly the failure the 2026-08-13 ruling
  was written to prevent -- a caller that is real and still exists, but
  happens to live in a project's source tree that a DIFFERENT project's index
  ALSO nominally covers (e.g. a shared folder indexed by two projects with
  slightly different closures, or a stale/narrow index) can be deleted from
  the record even though nothing about the real code changed. The
  2026-08-13 design's whole point was that "this project cannot see it is
  gone" and "this project cannot see it at all" are indistinguishable from
  inside one project -- ratifying the deviation accepts that indistinguishability
  can sometimes resolve the wrong way.
* (b) Follow the settled design -- change the code so an untagged entry
  is NEVER auto-deleted (mirror the 2026-08-13 union rule: keep it,
  unconditionally, until a human runs doc-forget --untagged on purpose).
  Cost: S (the code path is a few lines -- replace the UnitVouchable
  conditional at SharedFacts.pas:1206-1208 with an unconditional keep for
  the untagged branch); the existing run_doc_project_tags.ps1 REAP tests
  would need to be checked/updated since they currently assert reaping
  happens (SharedFacts.pas:1216's comment references this test by name).
  Risk: legacy leftovers accumulate silently in every project's docs until
  someone runs doc-forget --untagged by hand -- exactly the original
  "entries can only accumulate" cost the 2026-08-13 ruling accepted knowingly.
* No third option is offered in the source materials; this is a binary
  ruling on which failure mode is preferred.

### 6. Recommendation
Recommendation: (b), follow the settled design. The 2026-08-13 ruling
reasoned through this exact tradeoff already and chose "never silently
delete, reap explicitly" specifically because a false deletion (losing a
real, still-true fact) is worse than a stale line surviving until someone
runs doc-forget --untagged. The current code's deviation was very likely
an oversight of ENG-4's implementation (which was primarily solving the
TAGGED case) rather than a deliberate re-litigation of the 2026-08-13
tradeoff -- nothing in the ENG-4 commit message argues for overturning it.
Ratifying (a) would need a positive reason to prefer silent, automatic
cleanup over the explicit doc-forget --untagged that already exists and
costs nothing extra to run.
---

## DEC-4 -- document --apply deletes fact lines the chosen DB cannot see

### 1. The question in one sentence
Should drag-lint document --apply be changed so it can NEVER remove a fact
line naming a unit outside the DB's own coverage (refuse-and-keep or
refuse-and-decline), given it has now damaged the same real project
(DataCopy) twice?

### 2. What the thing is
document --apply regenerates a unit's machine-managed doc-comment facts
(Called from:, Used by:, Covered by:, etc. -- see DEC-3) from what the
chosen --db can currently see, and REWRITES the file in place (with a
.bak). If the DB is a PROJECT index (per CLAUDE.md: one DB per project,
built from exactly that project's compile closure) and the stored comment
names callers from a unit OUTSIDE that closure -- most commonly a separate
test project's .pas files, which are never part of the production
project's .dproj -- the regeneration cannot see those callers and, unless
merge/preservation logic intervenes, simply omits them from what it writes,
and reports success with a plain edit count, e.g.:

  doc: 34/36 decl(s) documented, 68 edit(s) applied (.bak written)

with nothing in that line indicating anything was REMOVED, let alone what.

### 3. How we got here
* 2026-09-08 (first occurrence, older, different shape): document
  --apply deleted two whole DECLARATIONS from DataCopy while the file still
  parsed -- the first sign this command could be lossy on this project.
* 2026-09-20, this note filed (docs/INBOX-document-apply-drops-facts-outside-the-db.md):
  the SECOND, distinct finding -- deleting FACTS, not declarations. Reproduced
  directly:

    drag-lint document --unit C:\Projects\DataCopy\uMicroniteFormat.pas
                       --db   C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite --apply

  Before: 26 Used by: Test.* / Called from: Test.* lines. After: 7.
  File shrank 2,979 bytes; declaration count unchanged (54), so the
  2026-09-08 declaration-count guard did not catch this variant. Root cause
  stated in the note: the managed blocks were generated back when a DB
  covering the TEST project was ALSO in scope, so they name callers like
  Test.MahrMarformMMQ.TMicroniteFormatTests.A_block_we_wrote_reads_back --
  DataCopy.sqlite is DataCopy's own project index, which by definition
  never holds Tests\*.pas (that lives in a separate test project with its
  own DB). The note points out the tooling ALREADY has the right detector,
  just not wired to --apply: lint-all's doc-drift check reports exactly
  this case and REFUSES to auto-fix it:
  [warning] doc-drift: managed facts block is out of date -- names facts in
  unit(s) this index does not hold; not auto-fixed. Confirmed by reading the
  code (src/doc/DRagLint.Doc.Drift.pas:1061-1072): the lint-time check
  computes CanVouch := not TSharedFacts.RegenerationDropsUnvouchable(...)
  and only labels the finding [FIXABLE] when CanVouch is true --
  exactly the guard document --apply's own write path lacked at the time
  the note was filed.
  Consequence recorded in the note: DataCopy's owner has adopted a standing
  rule -- never run document --apply on it -- accepting 27+14+1+1 = 43
  permanent doc-drift warnings rather than risk losing the test-caller
  facts again, which directly conflicts with the project's "no lint finding
  should be noise" standard.
* 2026-09-23, ENG-4 (commit 277cf798, see DEC-3) changed the WRITER
  (not just the checker) to call the same ReconcileContent merge function
  for every regeneration, with the explicit intent, per its own commit
  message, of fixing precisely this shape: "document --apply from one
  project's DB deleted Called from: entries only another project could
  see ... a reconciled block (dl:shared, holding facts this DB cannot see,
  or already tagged) renders WHOLE inbound lists ... and a stored window is
  merged on its visible entries." Reading the merge rule that applies to
  an UNTAGGED entry (DataCopy's stored Test.* lines predate tagging, so
  they are untagged): SharedFacts.pas:1206-1208 keeps an untagged entry
  when UnitVouchable(AStore, Bare) is FALSE -- i.e., when the DB cannot
  vouch for (does not hold) the unit the entry names. Since Test\*.pas is
  never in DataCopy's own project closure, UnitVouchable should read
  false for these exact entries, which on its face means ENG-4's merge
  SHOULD now preserve them.
* 2026-09-28 (today), BACKLOG-TRIAGE-2026-09-28.md DEC-4's own text
  still states, in the present tense, "DataCopy now carries a standing
  'never run document --apply' rule" -- five days AFTER the ENG-4 fix
  shipped. Nothing in the record shows anyone has re-run the DataCopy
  reproduction since 2026-09-23 to confirm ENG-4 actually closes it.

### 4. Current behaviour today
Not established by live measurement in this pass -- this session was
explicitly told never to re-index or write the DataCopy DB, and confirming
this would require running document --apply against real DataCopy source
(a file write), which is outside this pass's read-only scope. From reading
the code alone: the ENG-4 merge mechanism (ReconcileContent,
SharedFacts.pas:1129-1221) is structurally the right shape to fix the
DataCopy repro -- an untagged Test.* entry should be classified
not-vouchable and kept. But three things keep this from being a closed
matter rather than an open decision: (1) nobody has re-run the DataCopy
repro since the fix to confirm it, (2) the preservation is a CONSEQUENCE of
heuristic predicates (PlausibleEntry, IsUncertainEntry, UnitVouchable)
rather than an explicit, audited invariant -- a subtly different entry shape
could still fall through, and (3) the "reports success with no indication
anything was removed" problem the note calls out as an independent, still-real
gap is unaffected by ENG-4 either way -- there is still no
--dry-run/diff surface naming what a document --apply would delete before
it does.

### 5. The options
* (a) Refuse-and-keep. Never remove a fact line naming a unit outside
  the DB set that is running -- make it an unconditional invariant (not a
  heuristic outcome) enforced at the point of write, independent of whatever
  ReconcileContent happens to compute. Cost: M (a hard guard on top of the
  existing merge, plus a fixture proving it holds even when the heuristics
  disagree). Effectively: codify what ENG-4 does in most cases into
  something that CANNOT regress via a future change to the heuristic
  predicates.
* (b) Refuse-and-decline. When document --apply detects (via the SAME
  RegenerationDropsUnvouchable check lint-all already uses) that applying
  would drop facts the DB cannot see, ABORT that unit with a message instead
  of applying a partial/lossy write -- symmetrical with how lint-all's
  doc-drift finding already declines to offer [FIXABLE] in this case. Cost:
  S-M (wire the existing detector into the --apply path as a hard stop
  rather than a silent merge). Costs the user a manual step (they must run a
  DB that covers the missing units, or accept the drift finding as
  permanent) but never writes a worse file than it started with.
* (c) Park with a written ruling. Explicitly record that ENG-4 is
  believed sufficient, on the understanding that nobody has re-verified it
  against the real DataCopy repro, and that DataCopy's "never run
  document --apply" rule stays standing until that verification happens.
  Cost: zero code; the risk is that this becomes another silently-stale
  note the way the pre-ENG-4 version already did for five days.

### 6. Recommendation
Recommendation: verify first, then likely (a). Before ruling on new
code, re-run the exact DataCopy reproduction from the note
(document --unit uMicroniteFormat.pas --db DataCopy.sqlite --apply, or
better, a --dry-run if the verb has one) on the CURRENT engine to see
whether ENG-4 already closes it -- this is a cheap, high-value check this
session could not do (no DataCopy writes allowed). If it is NOT fully
closed, (a) is preferable to (b): a hard, non-heuristic invariant against
ever removing an unvouchable line is worth the extra M effort because this
project has now lost real facts TWICE from the same underlying class of bug,
and a silent-success command is exactly the shape CLAUDE.md's "silence is
the failure mode" principle warns against. If verification shows ENG-4 DOES
fully close it, downgrade to (b) or even a lighter "add a
dry-run-that-shows-removals" follow-up, since a hard invariant on top of an
already-correct merge is lower value.
---

## DEC-5 -- Attach the platform library as an extra store at INDEX time?

> **CLOSED 2026-10-25 -- same question as T-10 / walkthrough D5: owner ruled b+c, NO attach by default; opt-in index --library-db stays; note retired to INBOX-Done.**

### 1. The question in one sentence
Should indexing a project ALSO attach its platform library (RTL/VCL/
third-party) index as an extra store and resolve cross-store references at
INDEX time (writing them into the database), or should cross-store binding
continue to happen only at QUERY/LSP time, when a caller explicitly passes
both --db flags?

### 2. What the thing is
A "store" here means one drag-lint SQLite index. Per CLAUDE.md's layout,
every project has its OWN index (e.g. Micronite2027.sqlite), and each
platform (Win32/Win64) has a separate LIBRARY index covering the RTL, VCL
and third-party units the project USES but does not own. A reference from
project code to a library symbol -- e.g. calling TStringList.Add where
TStringList is declared in System.Classes (library code, not project
code) -- cannot be resolved to a symbol_id using only the project's own
store, because TStringList's declaration lives in a different database
file. Today, this binding only happens when a CALLER explicitly attaches
both databases, e.g.:

  drag-lint query find-callers --name Add --db Micronite2027.sqlite --db library-Win64.sqlite

The open question is whether the INDEXER itself should do this join once, at
index time, and store the result (refs.external_target, a column that
exists in the schema but is empty everywhere today), so that a plain
single--db query resolves library symbols without the caller remembering
a second flag.

### 3. How we got here
* 2026-09-20 -> 2026-09-22, measured and written up in
  INBOX-resolve-only-writes-no-cross-store-edges.md, then split by owner
  ruling into this narrower feature question
  (docs/INBOX-attach-library-store-at-index-time.md:1-6).
* The measurement (INBOX-attach-library-store-at-index-time.md:8-25):
  confirmed on real project DBs that index --all --resolve-only and
  index --project ... --resolve-only write ZERO cross-store edges --
  refs.external_target is 0 rows in every project DB checked (Micronite2027
  266,162 refs; MicroniteMW1Service 237,032; YADF 13,821; ConvRulesEditor
  19,815; ConvRulesModelTests 18,571), before AND after a resolve pass. This
  is structural, not a bug of omission in one code path: call_edges.target_symbol_id
  and receiver_type_symbol_id are same-DB foreign keys, so a call_edges
  row literally CANNOT point outside its own store; refs.external_target is
  the only column built for this and nothing fills it. There is no
  cross-store edge table anywhere in the 32-table schema. The resolver's
  stderr never mentions attaching a library or platform store, in either
  --all or single--project mode.
  One thing IS confirmed live: the code PATH for cross-store resolution
  exists -- CallResolver.pas:2176 calls FindSymbolsByExactName against
  "the EXTRA STORES" and declines when Found <> 1 -- but nothing in the
  indexing entry points has ever been shown to actually HAND it those extra
  stores. This matches this session's own recorded lesson that a reader the
  resolve pass depends on IS resolve surface: the C2.5 read-side fold
  changed intra-store call_edges counts (+13 in each platform library) but
  wrote 0 cross-store external_target rows either side, confirming the
  capability is present in the resolver's machinery but unreached from any
  index verb today.

### 4. Current behaviour today
Re-confirmed structurally by this session's read of the code and the CLI
surface (no new measurement run, per the task's rule against re-indexing or
writing any database this session): the documented, current, and CORRECT
way to get cross-store resolution is the query-time join CLAUDE.md already
prescribes -- pass BOTH the project DB and the relevant platform library DB
to query / find-callers / hover / context. A single--db query against a
project index alone declines to resolve a library-typed receiver
(hover/doc facts "decline" rather than answer, per the note's own framing).
This is a real, felt cost: Phase 5 of the purity spec (library effect
summaries by qualified name, referenced in the note) is explicitly blocked
on this exact mechanism not existing at index time.

### 5. The options
* (a) Yes -- attach at index time. The indexer resolves project refs
  against the platform library and writes refs.external_target, so
  find-callers/hover resolve RTL/VCL symbols from inside a project with no
  second --db. Cost: L (2-4 days per the note's own estimate) plus a
  RESOLVER bump (DRAGLINT_RESOLVER_VERSION is on the hashed surface this
  touches, per CallResolver.pas), which means a full RE-RESOLVE of every
  index afterwards -- per this session's cost table, minutes per PROJECT but
  ~74 minutes PER PLATFORM LIBRARY (there are two: Win32 and Win64), so
  call it low-single-digit hours total, not the ~4h48m of a full extractor
  re-parse, but not free either. Risk, per the note itself: every project
  index would now DEPEND on a platform library index being present AND
  FRESH -- a coupling the one-DB-per-project layout was deliberately designed
  to remove (CLAUDE.md's whole "AUTHORITATIVE SET" doctrine exists to keep
  project and library concerns separable). A stale or wrong-platform library
  attached at index time could poison a project DB's own resolution results
  in a way that is hard to detect after the fact (this session's own memory
  log records more than one prior incident where a stale or wrong index
  answered confidently and wrongly). What it unblocks: Phase 5 of the
  purity spec (library effect summaries), and removes the "remember a second
  --db" burden from every interactive query, hover, and doc-fact lookup
  involving a library symbol.
* (b) No -- keep query-time joins. The existing --db proj --db library
  pattern already gives the same answers to any caller that follows the
  documented pattern, and CLAUDE.md already prescribes it as the
  "authoritative set" rule. Cost: zero code; the documentation already says
  so. The cost is entirely the recurring one of every caller (human or
  agent) having to remember to pass the second --db, and Phase 5 of the
  purity spec staying blocked.

### 6. Recommendation
Recommendation: (b), no -- keep query-time joins, unless/until Phase 5 of
the purity spec is actually scheduled. The note's own "why it might not"
section identifies the real cost precisely: this would re-couple every
project index to a platform library's freshness, which is the exact
per-project independence the current layout was built to buy (CLAUDE.md
documents this move away from shared/union DBs at length, with a list of
concrete incidents the old coupling caused). An L-effort change plus a
resolver bump and a multi-hour re-resolve of two library DBs is a real price
to pay for convenience alone when the documented two--db workaround
already produces correct answers today. Revisit as (a) specifically when
Phase 5 of the purity spec is picked up, since that is the one concrete
piece of work actually blocked on this rather than merely inconvenienced by
its absence.
---

## DEC-6 -- Merge feat/graphviz-export (Delphi-RAG-Lint-Graph, c74eaba)

> **CLOSED 2026-10-25 -- merged: Delphi-RAG-Lint-Graph main f44281c "merge: feat/graphviz-export -- DEC-6 (owner-approved 2026-10-06)"; c74eaba is contained in main (git branch --contains).**

### 1. The question in one sentence
Should the feat/graphviz-export branch in the SEPARATE Delphi-RAG-Lint-Graph
repository -- Graphviz-based static export of the graph viewer's current view
-- be merged into that repo's main?

### 2. What the thing is
Delphi-RAG-Lint-Graph is a standalone Delphi viewer application
(drag_lint_graph.exe) that renders drag-lint's index as an interactive
UML/call graph (classes, members, call edges, "Where Used" lists, a Code Flow
view), with its own live GDI-based rendering (TGraphViewModel +
TDragLintGraphControl). This branch adds a SEPARATE, static export path:
instead of (or in addition to) looking at the graph inside the app, the user
can click "Export..." and get a standalone .svg or self-contained .html
file (with pan/zoom/search/theme toggle built in) rendered by the external
Graphviz dot.exe tool, of EXACTLY the current view -- whatever collapse/
drill/focus/isolate state the user has navigated to. It reuses the same
visual language as the "charts" diagram feature elsewhere in this project
family (HTML-table nodes, one row per member, draglint://open?file=..&line=..
links so clicking a row can jump an editor to that line).

### 3. How we got here
* 2026-09-16, a spike plan was written but never run
  (docs/PLAN-2026-09-16-graphviz-skia-render-pipeline.md, referenced from
  the branch's own spike doc) proposing Graphviz as a possible future
  in-process render pipeline for the LIVE view (not just export).
* 2026-09-23, "Phase 0" spike (docs/SPIKE-graphviz-export-2026-09-23.md
  in the branch): measured real timings by driving the actual
  TGraphViewModel over a COPY of the ORM3 CLIENT index (171.5 MB, 57,119
  symbols; the live DB was never opened for writing) through Graphviz 16.1.0.
  Result: every view a user actually reads in practice (11-92 nodes, a
  focused neighbourhood, a single drilled-into unit) costs 1.5-2.7 seconds,
  entirely dot's own fixed per-process startup floor (measured at
  1.2-3.6 s even for a trivial two-node graph -- font/plugin resolution, not
  layout). Only a "show everything" view (391 nodes / 3,533 edges) costs
  20-25 seconds, and that cost scales with EDGE count, not node count. The
  spike's own verdict: "GO for export (phase 1) ... NO-GO for 'one dot
  process per structural change' in the live view" -- i.e., good enough to
  justify a one-shot export button, not good enough to replace the live
  interactive renderer.
* Same day, commit c74eaba (feat(graph): Graphviz export of the
  visible view (phase 0 spike + phase 1)) implemented Phase 1 on top of
  that verdict: two new units (DragLint.Graph.DotEmit.pas, 808 lines --
  emits DOT text from the CURRENT projection; DragLint.Graph.Export.pas,
  495 lines -- finds dot.exe, runs it, writes the standalone .svg/.html),
  an "Export..." button and --export/--goto CLI automation wired into
  MainForm.pas, and 15 new console tests (79 total, described as green in
  the commit message; end-to-end export tests run only when dot.exe is
  found on the machine).
* This is a SINGLE commit sitting on a worktree branch
  (C:\Projects\Delphi-RAG-Lint-Graph-wt\graphviz-export), branched from
  commit efbc1262. That repo's main has since moved on by two more
  commits (e8f637f, then merge commit 591d7f8 bringing in "the v0.5
  graph dev line ... 36 commits -- Win64 viewer, Flow View, Where-Used list,
  unified nav, editor-sync"), so the branch is now behind main, not merged
  forward.

### 4. Current behaviour today
Measured live (read-only) in the Delphi-RAG-Lint-Graph repo this session:
git merge-tree efbc1262 591d7f89 c74eaba shows exactly ONE real
conflict, in README.md (both sides added different text near the same
lines), and everything else (including a .vscode/settings.json theme-color
change) merges cleanly. No other file the branch touches
(DragLint.Graph.DotEmit.pas, DragLint.Graph.Export.pas,
drag_lint_graph.dpr/.dproj, tests/console/Test.Graph.DotEmit.pas) was
touched by anything that landed on main since the branch point, so this is
structurally a low-risk merge -- the feature was built in isolation and
nothing else has grown into the same files since. This session did not
build or run the branch (out of scope; no compilation was attempted), so
whether it still compiles and passes its 79 console tests against the
CURRENT main (post the 36-commit v0.5 merge) is not established here.

### 5. The options
* Merge (S). Resolve the one trivial README conflict, merge
  feat/graphviz-export into main. Cost: small -- a few minutes of
  conflict resolution plus, to be safe, a rebuild and a re-run of the 79
  console tests against the now-current main (the branch has not been
  proven to still build cleanly since main gained 36 commits of viewer
  work after the branch point). Risk: low, given the clean merge-tree
  result, but unverified against the newer main code (Flow View, editor-
  sync, unified nav landed after this branch was cut, and none of it is
  known to have been exercised together with the export feature). What it
  unblocks: a shareable, standalone artifact of any graph view (a .svg a
  developer can paste into a chat, ticket, or wiki page, or a self-contained
  .html a non-drag-lint-user can open and navigate) -- something the live
  GDI-only viewer cannot produce today.
* Hold. Leave the branch as is. Cost: zero now, but the branch drifts
  further behind main the longer it waits (each new commit on main is
  one more thing the eventual merge has to reconcile against, even though
  today's conflict surface is minimal). Appropriate if the owner wants to
  see the export feature demonstrated live first, or if graph-viewer work
  is not currently a priority relative to other streams.

### 6. Recommendation
Recommendation: merge. The measured merge-tree result is about as clean
as a stale branch can be (one trivial doc conflict), the feature is
self-contained (two new units plus wiring, no shared-file contention with
what has landed on main since), and the underlying design decision (a
one-shot export, not a live-view replacement) was reached through an honest
measurement with a clear GO/NO-GO split, not asserted. The only real
pre-merge step worth doing that this session could not do (build tooling,
out of scope for a read-only pass) is a rebuild against current main and a
re-run of the 79 console tests to confirm nothing in the 36 intervening
viewer commits interacts badly with the export path before calling it done.

---

# Owner decisions DEC-7 .. DEC-12 -- detailed background
Prepared 2026-09-28. Source: docs\BACKLOG-TRIAGE-2026-09-28.md section 2 and 3d, plus the
specs/notes/git history named under each item. All file:line and command output below were
read or run in this session unless marked "recorded" (copied from a doc, not re-verified now).
Engine measured live in this session: third_party\dll-win64\drag-lint.exe, 189 rules
(136 builtin + 53 external), schema 23 -- matches the header's "1.20.0-alpha, 189 rules".

---

## DEC-7 -- Turn `discarded-effect-free-result` ON by default?

> **CLOSED 2026-10-25 -- discarded-effect-free-result was turned ON (walkthrough D4 background: "DEC-7 turned discarded-effect-free-result ON").**

### 1. The question in one sentence
Should the lint rule that flags "you called a side-effect-free function and threw away its
return value" ship ON by default (it exists today, OFF), given that on ORM3 it fires exactly
3 times and all 3 are the same real latent bug?

### 2. What the thing is
The engine's purity analysis (`symbol_facts.effect_free`, `effect_summary`) proves, for some
routines, that calling them changes no observable state (no field write, no global write, no
I/O) -- their only "product" is the return value. If a function is proven `effect_free=1` and a
call site discards its result (`Foo;` as a statement), the call did *nothing at all*: it is dead
code by construction. Example (the exact ORM3 case, see section 4):
```pascal
function TAttrPlan.Describe: fstring;
begin
  Result:= inherited Describe;   // inherited is ALSO proven effect-free
end;
...
procedure TAttrPlan.UpdateNR;
begin
  Describe;          // <-- flagged: result discarded, and Describe does nothing
  fModified:= True;
end;
```
**Caveat named in the backlog: "ignores virtual overrides."** The rule proves effect-freedom
from the STATICALLY declared method body (and its `inherited` chain), not from every possible
override reachable through virtual dispatch on a less-derived (e.g. base-class-typed) receiver.
If a call site holds a base-class reference that could, at runtime, be a more-derived instance
overriding the method with a real side effect, the rule's "does nothing" claim is unproven for
that call site even though it was proven for the specific declaration it analyzed.

### 3. How we got here
* `cb606ffe` "feat(lint): discarded-effect-free-result + query-name-with-effect (OFF by
  default, summary-driven); v1.16.0-alpha" -- the rule shipped, OFF, riding purity v2
  (`symbol_facts.effect_free`/`effect_summary`).
* `92d719cc` "perf(lint): lint <file> --rule X runs only the checkers that can emit X (D3)" --
  performance follow-up, no behaviour change to the rule itself.
* `531e8b7a` "docs(measured): purity rules on ORM3 CLIENT (3/6/4 findings, 3/1/0 real) ..." --
  an early sizing pass recorded 3 `discarded-effect-free-result` findings, 3 of them judged real.
* `docs\INBOX-lint-rules-from-new-facts-2026-09-23.md` section D: "Two shipped with purity v2
  and are OFF by default ... Action before adding more in this family: measure those two on
  ORM3."
* `docs\INBOX-new-rules-from-graph-and-converter-facts.md` C3/D restate the same "measure before
  adding a third member to the family" caution.
* `docs\BACKLOG-TRIAGE-2026-09-28.md` section 3d, row NR-D (measured 2026-09-28, read-only,
  on the deployed 1.19.1 engine): "discarded-effect-free-result CLIENT 3 / SERVER 3 -- the
  SAME three TAttrPlan.Describe sites in the shared uPLANLIST.PAS (2360/2377/2385), i.e.
  DEC-7's 3/3; query-name-with-effect CLIENT 4 / SERVER 7 ... needs a precision pass before it
  could go ON." This is the exact basis DEC-7 in section 2 quotes ("ORM3: 3/3 real").

### 4. Current behaviour today -- MEASURED LIVE this session
```
drag-lint.exe lint-project --db C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite \
  --rule discarded-effect-free-result --enable discarded-effect-free-result
```
```
C:\Projects\DB\ORM3\COMMON\OBJECTS\uPLANLIST.PAS:2360:1  discarded-effect-free-result:
  Result of effect-free uPLANLIST.TAttrPlan.Describe is discarded (effect_free=1)
C:\Projects\DB\ORM3\COMMON\OBJECTS\uPLANLIST.PAS:2377:1  (same)
C:\Projects\DB\ORM3\COMMON\OBJECTS\uPLANLIST.PAS:2385:1  (same)
3 finding(s)
```
Reading uPLANLIST.PAS around those three lines (read this session): the calls are inside
TAttrPlan.InitZero (2360), TAttrPlan.Update (2377) and TAttrPlan.UpdateNR (2385), each a
bare "Describe;" statement. TAttrPlan.Describe (line 2347-2350) is
"Result:= inherited Describe;", and the ancestor TmcPLANLIST.Describe (line 1408-1413) is
literally "Result:= fPDESCRIPTION;" with the comment "Base implementation: return stored
description unchanged. All concrete subclasses override this to build a human-readable
summary." Every SIBLING class does exactly that -- e.g. TManualPlan.Describe (line 2412-2416)
is "fPDESCRIPTION:= 'Manual Plan' + '; N = ' + ... ; fModified:= True;", called from the same
three method shapes (InitZero/Update/UpdateNR) for its side effect. TAttrPlan is the
one class in this family that never overrode Describe to build its own description string --
its Describe forwards to a no-op base, so the three call sites that exist specifically to
populate fPDESCRIPTION do nothing for TAttrPlan instances. This reads as a genuine
copy-paste gap from whichever sibling class TAttrPlan was cloned from, not a false positive.
No subclass of TAttrPlan was found in uPLANLIST.PAS (searched), so the "ignores virtual
overrides" caveat does not undermine this specific finding.

### 5. The options
* (a) Turn it ON. Cost: S -- flip the default in the rule catalog, update --help/README/
  AI-USAGE rule counts (the docs-sync guard's check 2 enforces defaultOn matches
  rules --json, so this is a one-line catalog change plus the doc regeneration already
  routine for a default flip). No version bump (purity facts already exist; the rule reads
  them, it does not derive new ones). Risk: LOW on the measured evidence (3/3 real on the one
  corpus checked), but the family has exactly one other member measured
  (query-name-with-effect, 4/7, judged NOT precision-ready) and no measurement yet on any
  OTHER project (DataCopy, YADF, the CLI's own self-index) -- turning a rule on by default
  based on one project's 3 findings is a small sample. Unblocks: sets the precedent for sizing
  the rest of the purity-effect family (LR-5 side-effect-in-short-circuit, LR-6
  property-getter-with-effect, the assert-with-side-effect sibling already shipped).
* (b) Keep OFF. Cost: 0. The finding remains discoverable via --enable
  discarded-effect-free-result on demand (as already used above); nothing regresses. Risk:
  the TAttrPlan bug (and future ones like it) is invisible to anyone who does not know to ask
  for the rule by name.

### 6. Recommendation
Turn it ON. The evidence is a real bug found with zero false positives on the one corpus
measured, the rule needs no version bump, and the docs-sync cost is small and mechanical. The
"ignores virtual overrides" caveat is a soundness note for the rule's DESIGN, not evidence
against these 3 findings (verified no override chain complicates them). Recommend pairing the
flip with a one-line CHANGELOG note naming the caveat, so a future false positive through a
base-typed polymorphic receiver is recognized as the known limit rather than reported as new.

---

## DEC-8 -- Schedule the use-edges programme (property/field USE edges)?

> **CLOSED 2026-10-25 -- later ruled (walkthrough D11: "DEC-8 later ruled").**

### 1. The question in one sentence
Should the fully-designed "USE edges" feature -- binding a property/field READ or WRITE to its
declaration, the way a CALL already binds to a routine -- be scheduled as its own engineering
stream (estimated 3 days +/- half a day, plus a resolver-version bump), or stay deferred as it
has been since 2026-09-13?

### 2. What the thing is
Today the engine's call_edges table only ever points at one of five ROUTINE kinds
(skMethod, skProcedure, skFunction, skConstructor, skDestructor). A property or field
access like "if FProv.Flag then ..." produces a member-access ref in the index, but nothing
ever resolves it to the Flag property's declaration -- so find-callers --name Flag, "who
reads/writes this property/field", and lint-tree's dependent-impact analysis are all BLIND to
property/field usage. The design adds a second relation, use_edges (a NEW table, additive, no
schema bump), that records: which declaration a member-access ref resolves to, whether it's a
read or a write, and an "echo" -- e.g. reading X.Value (a property "read GetValue write
SetValue") also counts as touching GetValue. Example of the target surface:
```
drag-lint usages --name Connected --resolved
  used_in: uMain.ViewModel.pas:145 TMainViewModel.Connect [r]
           uMain.ViewModel.pas:210 TMainViewModel.Disconnect [r]
```
The owner's own framing (quoted in the spec): "Property is not a 'caller' per se, but it does
indirectly call setter and reader if any ... Besides callers do we have 'users'? ... it would be
useful to show this in autodoc and mouse hover popup as 'used in'."

### 3. How we got here
* The gap was first misdiagnosed in INBOX-property-refs-never-resolve.md (root cause: "never
  enters the resolve pass"), which the design spec (section 2 and 13) shows is WRONG -- the
  member-access ref DOES stream into ResolveCallTargets (since v20b, 2026-08-10); it dies at
  TCallResolver.LookupMethodOnType's METHOD_KINDS filter (CallResolver.pas:581) and again
  at the QIsRoutine guard (Storage.SQLite.pas:11114-11124) that refuses to write a
  non-routine target into call_edges.
* Two fixes were tried and reverted (spec section 2), both because they tried to make a
  property ride the CALL path, which the owner's framing explicitly forbids: a property use
  needs "its own classifier", not a widened call_edges.
* docs\superpowers\specs\2026-09-14-use-edges-design.md (675 lines) is the resulting DESIGN,
  written 2026-09-14 against engine 1.11.0-alpha, extractor 1.16.0-alpha, resolver
  1.2.0-alpha. Status header: "DESIGN ONLY -- awaiting owner approval. No source changed,
  nothing built."
* docs\PLAN-SESSION-95-OPEN-NOTES.md section 7 (2026-09-15) confirms it is "ALREADY DESIGNED.
  Do not re-plan it" and elevates its priority: the companion purity re-measurement showed the
  SAME binding gap (calls AND member-access both unbound) is responsible for most of the
  "unproven purity" noise -- ORM3 CLIENT's effect-free-routine rate would move from 26.9% to
  42.3% once both bind, and library-Win64 from 33.5% to 63.5%. It notes the two kinds of gap
  "co-occur at 1.58 kinds per routine" -- i.e. fixing member-access binding alone (this design)
  is worth doing together with the call-binding work, not standing entirely alone.
* docs\BACKLOG-TRIAGE-2026-09-28.md section 3a RB-3 records that most of the parenless/member
  binder work IS shipped (resolver 1.8.0) except one residual (Self.Tick double-ref), so the
  underlying resolver machinery this design would extend is mature.
* Owner deferred it 2026-09-13 (per DEC-8's own text: "owner-deferred 09-13"). Nothing has
  changed the design since; it is the same spec DEC-8 asks about today.

### 4. Current behaviour today
MEASURED in the spec (section 1, ORM3 CLIENT, and the shape is unchanged by anything shipped
since -- refs.symbol_id is still populated for call/member-access refs only when a ROUTINE
resolves): query find-callers --name Connected --resolved returns 0 callers for a property
with 602 name-matching member-access refs. usages --name Connected buckets all 602 into a
calls: field labeled by the ELSE-bucket rule (GroupFor, "call + anything else") -- so a
property with ZERO real calls presents as "calls: 602", which is actively misleading to a reader
(human or AI) who trusts the label. This has not changed: no use_edges table exists, and
DRAGLINT_RESOLVER_VERSION is still short of the 1.3.0-alpha the spec would bump to.

### 5. The options
* (a) Schedule it as its own stream (XL, resolver-bump only, no schema bump). Phase 1 (writer
  only, ~1 day): LookupMemberOnType, the classifier, refs.symbol_id for a certain property/field
  target, IsRoutineKind->IsReportableKind in lint-tree. Already delivers the owner's original
  lint-tree case (a commented-out property with live dependents gets flagged) and makes
  FindReferencesTo work for properties. Phase 2 (~1.5-2 days): the use_edges table itself,
  access-mode derivation, the echo, full usages --resolved, and the autodoc/hover "Used in:"
  rendering the owner explicitly asked for. Version cost: DRAGLINT_RESOLVER_VERSION bump -- a
  re-resolve, NOT a re-parse. The spec's own cost table (section 9.2): ORM3 CLIENT whole-DB
  2-4 minutes; both platform libraries together ~1h45m sequential, or the spec argues it is
  defensible to skip the immediate library re-resolve and let them report resolve-owed until
  their next scheduled run. Total wall clock ~2h against the ~4h48m a full re-parse costs. HARD
  CONSTRAINT proven testable (T0): find-callers output must stay byte-identical -- a property
  NEVER enters call_edges, by design, so this cannot silently change what "who calls X" means.
  Unblocks: the owner's original ask (autodoc/hover "Used in:"), the discarded-effect-free-
  result family's precision (an unbound member-access read looks identical to a genuine unknown
  today), and the CLIENT/SERVER data-path report (BACKLOG-94 sec.7) whose chains currently stop
  dead at every property accessor.
* (b) Keep deferred. Cost: 0 now. Risk: the purity re-measurement's headline (26.9%->42.3%)
  stays unrealized, usages's calls: bucket keeps mislabeling property/field touches as calls,
  and the spec -- already fully designed, reviewed against real INBOX mistakes, with a named test
  plan (T0-T11) -- ages further. Nothing about the design gets cheaper by waiting; if anything,
  every new resolver change since 2026-09-14 (RB-1..RB-5, D-series fixes) is a change the design
  will need to be re-verified against before implementation, which is pure carrying cost.

### 6. Recommendation
Schedule it, Phase 1 first as a standalone ship (S, ~1 day, unblocks lint-tree property
impact immediately), Phase 2 as the following batch. This is the single largest-yield
designed-but-unbuilt item across all six DECs -- it is cited as the prerequisite for two other
backlog items (the purity precision gain and the CLIENT/SERVER data-path report) and the design
work (including two false starts already ruled out) is sunk cost that a further deferral does
not preserve for free. Recommend NOT blocking phase 2 on the platform-library re-resolve
(spec's own recommendation, section 9.2) to avoid coupling this to an unrelated ~1h45m of
machine time.

---

## DEC-9 -- What should `Covered by:` mean: reachability, or a direct/asserting call?

### 1. The question in one sentence
The autodoc fact "Covered by: <TestName>" currently means "some test can REACH this method
through the call graph", which can name a test that never actually exercises the method's real
behaviour -- should that stay as-is (cost: 0), or should Covered by: be redefined to mean "a
test directly/assertingly calls this" (cost: L, and it rewrites every Covered by: line in
every indexed repo)?

### 2. What the thing is
document (the autodoc verb) inspects the call graph and, for a public method, tries to name a
test that "covers" it, rendering a line like:
```
/// <para>Covered by: Test.UsageWiring.TUsageWiringTests.DPP_reports_its_usage_even_when_the_consumed_source_survives</para>
```
The mechanism is a REACHABILITY heuristic: it walks the call graph to find SOME test that can
transitively reach the method, not a test that calls the method directly or asserts on its
result. Two methods can share a dispatch path (e.g. both TMarpossTransfer.TransferFile and an
unrelated DPP transfer mode route through a common shared entry point) and the heuristic will
name whichever test it found first, regardless of whether that test ever sets up the scenario
the flagged method actually needs.

### 3. How we got here
* Filed 2026-09-02 as docs\INBOX-covered-by-reachability-artifact.md, from DataCopy's Marposs
  -> MICRONITE conversion task: TMarpossTransfer.TransferFile and .ReportMessages both carried
  the identical Covered by: line naming a DPP test (Test.UsageWiring.pas) that "never calls
  ... and nothing in Test.UsageWiring.pas exercises the Marposs mode at all" -- confirmed
  independently by a second reviewer the same week (Task 8's review, "Minor finding 3").
* 9751dffd "fix(doc): an unprovable 'Covered by:' is marked, not asserted (item 6)" -- the
  IMMEDIATE remedy: the fact is now suffixed "(unverified)" wherever the reachability heuristic
  is the only evidence, so it no longer ASSERTS a coverage relationship it cannot demonstrate.
  Re-measured 2026-09-06 against the correct DB (DataCopyTests.sqlite, not DataCopy.sqlite --
  the note's own first draft named the wrong DB, itself a near-miss false-close): the same wrong
  test is still named, now carrying (unverified).
* ced256d9 "fix(doc): D27+D28 -- the [Project] tag is a stored fact of the index; Covered by:
  joins the tagged regime" and 239dc40a "fix(docs): final review -- project tags, find-callers
  writes/unit values, D23 released state" -- later hardening of the SAME fact's project-tag
  plumbing, unrelated to the reachability-vs-direct-call question.
* Owner ruling, session 100 triage (2026-09-16), quoted in the note's own header: "leave it for
  now, we might return to it later. Covered by: stays REACHABILITY with (unverified)
  marking." The status line calls this residual "a design question, not a defect" and
  explicitly blocks a "direct call" redefinition on the (separately parked) untypable-receivers
  brainstorm (RB-5 in the current backlog, since ruled: "attribute to the interface method",
  2026-09-16).

### 4. Current behaviour today
Confirmed live this session: src\doc\DRagLint.Doc.SharedFacts.pas:763 still reads the comment
"uncertain caller or the ' (unverified)' of a Covered by: test -- trimmed" -- the marking
mechanism from 9751dffd is present in the currently-built source, unchanged since the
2026-09-16 ruling. No commit since has touched the reachability-vs-direct-call semantics.

### 5. The options
* (a) Keep reachability, with (unverified). Cost: 0 -- this is already shipped and is the
  status quo. The marking is honest about what the fact can and cannot prove; a reader (human or
  AI) sees (unverified) and knows not to treat the named test as a behavioural guarantee.
  Residual risk: a reader who skims past the (unverified) suffix still gets misdirected to the
  WRONG test when debugging a failure, costing them the same investigation time the original
  DataCopy note describes.
* (b) Redefine to "direct/asserting call". Cost: L, and it is explicitly "doc churn":
  every Covered by: line in every indexed repo would need re-derivation and regeneration
  (document --apply reruns), and -- per the 2026-09-16 ruling -- the machinery to do this
  precisely is blocked on the untypable-receivers work (RB-5), because "direct call" through an
  interface-dispatched or polymorphic call chain needs the same receiver-typing improvements
  RB-5 addresses. Since RB-5 is now itself ruled and estimated (M, 2-3 days, per section 3a),
  this blocker may be more tractable than it was in September, but the doc-churn cost across
  every repo is unchanged and unestimated beyond "L".
* (c) Park indefinitely / retire the question. Cost: 0. Differs from (a) only in bookkeeping
  -- (a) is "keep it, actively decided"; (c) is "stop tracking this as an open decision at all."

### 6. Recommendation
Keep reachability with (unverified) (option a), and explicitly retire this as a live DEC
rather than re-parking it a third time. The (unverified) marking already discharged the
"confident wrong answer" failure mode that made this a wrong-class defect in September; what
remains is a genuine product-shape preference (do we want a cheaper, honest, sometimes-misleading
fact, or a more expensive, always-narrower, more-expensive-to-maintain one), not a bug. Revisit
only if RB-5's interface-dispatch work, now itself scheduled, turns out to make "direct call"
cheap as a side effect -- worth a fresh sizing pass after RB-5 ships, not a decision now.

---

## DEC-10 -- Should the LSP run the full built-in check suite for non-IDE clients?

### 1. The question in one sentence
Non-IDE LSP clients (anything but this repo's own VS Code extension, which has its own
out-of-process "live runner") see only ~11-14 of the engine's ~189 checks on didSave -- should
BuildDiagnostics be extended to run the whole built-in suite in-process (cost: real per-save
latency), or left as-is?

### 2. What the thing is
drag-lint lsp is a Language Server Protocol server. On didSave it calls
TLspCompletion.BuildDiagnostics (src\lsp\DRagLint.LSP.Completion.pas:885), which composes
its diagnostic set from: (1) the .scm-defined external rules via ALinter.LintFile, (2)
TAstChecker.CheckSyntaxErrors (all syntax errors), (3) only the string-equality-comparison
finding out of TAstChecker.CheckTypeAware's full output (a deliberate narrow slice, per the
inline comment at line 946-955: the .scm string-equality rule has known false positives the
built-in CheckTypeAware avoids, so only that ONE finding is swapped in), and (4)
TCloneChecker.Check (duplicate-code detection). This repo's own lint/lint-all CLI verbs, by
contrast, run the FULL built-in suite -- ~136 built-in checks plus 53 .scm rules today (189
total, measured live this session via rules --json).

### 3. How we got here
* Filed 2026-09-01 (session 57) from a live bug report of "flapping" gutter icons -- diagnostics
  appearing, then dropping to almost nothing, then reappearing.
* Diagnosis (docs\INBOX-lsp-gutter-runs-almost-no-builtin-checks.md): TWO independent
  mechanisms were tangled together. (i) The LSP publisher and the VS Code plugin's own "live
  runner" (which shells out to drag-lint lint and DOES get the full 45-of-45 set on the
  measured fixture file) both write the SAME per-file cache slot, and the cache's Update
  REPLACES rather than merges -- so whichever producer saved last (usually the LSP, on every
  keystroke-triggered save) overwrote the richer set. (ii) Separately, the LSP path itself
  structurally runs a narrower rule set than the CLI, which is the residual DEC-10 asks about.
* Fix 1 (give each producer its own overlay, union them) and fix 3 (the live runner owns the
  gutter, since it already gets the full 45) were SHIPPED -- confirmed by
  tests\plugin\run_diag_producer_overlays.ps1 (19 assertions, verified 2026-09-06) and an
  owner ruling recorded in the note: "the live runner owns the gutter." That ruling makes fix 2
  moot for the IDE specifically -- the VS Code extension's gutter no longer reads the
  LSP-published subset at all.
* What is left, and is explicitly NOT authorized to be built on this note's authority: "any
  NON-IDE LSP client still sees ~11 of 45 and has no live runner to fall back on. Whether the LSP
  should run the built-in suite is the owner's PERF call: it would put 126 checks in-process on
  every didSave, which is precisely the cost the IDE avoids by paying it out-of-process."
* Session 100 triage (2026-09-16) re-parked it with a TRIGGER, not a date: "revisit when row 5
  (the exception-HANDLING fact) lands" -- i.e. this is explicitly tied to DEC-1/DEC-2's resume
  condition, not independently scheduled.

### 4. Current behaviour today -- confirmed by reading the live source this session
src\lsp\DRagLint.LSP.Completion.pas:885-1037 (BuildDiagnostics) still composes exactly the
four sources above: .scm linter output, CheckSyntaxErrors (all findings, gated to .pas/
.inc), the SINGLE string-equality-comparison finding from CheckTypeAware (line 946-962,
comment unchanged since the fix), and TCloneChecker.Check (line 1034, gated to .pas/.inc).
Nothing else from the built-in suite runs on the LSP didSave path. Against a live rule catalog
of 189 (136 built-in + 53 external, measured this session via rules --json), a non-IDE LSP
client today sees: the 53 .scm rules, plus syntax errors, plus one specific built-in finding
type, plus clone detection -- i.e. still structurally the ~11-14-of-45-class gap the note
measured, now against a larger denominator (189 vs the September 45-rule snapshot).

### 5. The options
* (a) Run the full built-in suite in BuildDiagnostics. Cost: M. This makes the LSP path
  call the SAME ScanAdd(...) sequence lint/lint-all use (~136 built-in checks) on every
  didSave. Real cost is PERFORMANCE, not code complexity: the note is explicit that "the live
  runner already pays that cost out-of-process on a debounce, which is one argument for
  [keeping the LSP thin] instead." A naive implementation risks a visible editor stall on
  didSave for a large file, especially for any O(file-size) or O(project-size) built-in check.
  Unblocks: parity for any LSP client that is not this repo's own VS Code extension -- i.e. any
  other editor/IDE (Neovim, a generic LSP client, a CI integration) that speaks LSP and expects
  publishDiagnostics to be authoritative.
* (b) Do nothing (status quo). Cost: 0. Risk: unchanged -- any third-party LSP client is
  silently getting a partial view and has no way to discover this short of comparing counts
  against the CLI, exactly as the original bug report found by surprise.
* (c, not offered in the backlog line but implied by fix 3's precedent) Publish a notification
  that gutter diagnostics are partial, or document the limitation loudly, cheaper than (a) but
  does not close the gap, only names it.

### 6. Recommendation
Do not build (a) yet; the trigger the owner already set (row 5 / the exception-HANDLING fact,
tied to DEC-1) has not fired, so this is not ripe by the owner's own prior ruling. When it is
revisited, recommend measuring the actual per-didSave latency of the full built-in suite on a
realistic large file BEFORE committing to in-process execution -- the note itself frames this as
a PERF decision, and no latency number has ever been measured for this specific path (the
"~126 checks" cost is stated, never timed). If the measured cost is small (say, well under the
threshold that "lags a debounced live runner" would in practice), (a) is safe; if large, a
partial-suite compromise (e.g. run only checks proven fast/local, defer the rest to a debounced
background pass mirroring the live runner's own architecture) may serve non-IDE clients without
reproducing the IDE's original latency problem.

---

## DEC-11 -- Build the `{$SCOPEDENUMS}` extractor fact for `enum-bare-read-scoped`?

### 1. The question in one sentence
Should the extractor be taught to record whether an enum type was declared {$SCOPEDENUMS ON}
(a Delphi language feature that requires TEnum.Value qualification and forbids the bare
Value form), to support a lint rule flagging a bare scoped-enum read -- given it costs a full
extractor-version bump (~4h48m re-parse of every index) and the fact is measured 0 times on
every project DB checked, but explicitly UNmeasured on the platform libraries?

### 2. What the thing is
Delphi's {$SCOPEDENUMS ON} directive changes an enum type from Pascal's default "global
namespace" behaviour (TColor = (clRed, clBlue); ... X := clRed;) to a scoped one requiring the
type name (X := TColor.clRed;), catching accidental cross-enum collisions at compile time. The
proposed rule, enum-bare-read-scoped, would flag a bare read of a scoped enum's value where the
qualification was somehow omitted or misresolved -- but the extractor today records NOTHING
about whether an enum declaration carried {$SCOPEDENUMS}, so the fact the rule needs does not
exist in the index at all.

### 3. How we got here
* Filed 2026-09-23 in docs\INBOX-new-rules-from-graph-and-converter-facts.md, section A3
  (enum-bare-read-scoped), immediately after two SIBLING rules in the same family
  (enum-ordinal-persisted, enum-bare-read-in-with) were sized and one of them shipped
  (enum-read-inside-with, d041d009, 2026-09-23) on the back of the same session's enum-value
  ref binding work (resolver 1.6.0-alpha).
* The note states plainly: "Stands on: nothing yet. {$SCOPEDENUMS} appears 0 times in
  src -- the extractor does not record scopedness, so TEnumValueDecl cannot express it.
  Measured 0 occurrences on 33 project DBs, but explicitly NOT measured on the platform
  libraries, where RTL/VCL scoped enums live. Blocked on an extractor fact, and an extractor
  fact costs a version bump plus a ~3h17m full re-parse. Record, do not build."
* docs\INBOX-lint-rules-from-new-facts-2026-09-23.md does NOT separately list this rule (it
  covers a different but overlapping nine-rule set from the same session); the SCOPEDENUMS work
  is unique to the graph/converter-facts note.
* No commit anywhere touches SCOPEDENUMS/enum-bare-read-scoped (git log searched, both
  --grep and -S, zero hits) -- consistent with "record, do not build," never actioned since.
* The re-parse cost cited (~3h17m) is the 2026-09-17 measurement; the CURRENT recorded full
  re-parse cost (per this repo's own memory, project_full_reparse_duration.md, and repeated in
  the task brief) is ~4h48m, i.e. the cost has grown since the note was written -- the
  decision is, if anything, slightly more expensive today than when filed.

### 4. Current behaviour today
Unchanged: {$SCOPEDENUMS} is not extracted anywhere. Grepping the docs corpus for the token
(this session) finds it only in narrative/spec files (AI-USAGE.md, wiki pages, the
MEASURED-enum-value-refs-2026-09-23.md note, and the two 2026-09-23 enum-value-ref-binding
spec/plan files) -- none of which is a code file; src\ has zero occurrences, matching the
note's own claim. No rule named enum-bare-read-scoped exists in the live 189-rule catalog
(consistent with "record, do not build").

### 5. The options
* (a) Build it. Cost: L + extractor bump, i.e. the ~4h48m full re-parse of EVERY
  configured index (both platform libraries plus every project DB) is the real price, not the
  code. The code itself is bounded (record one boolean per enum type from the {$SCOPEDENUMS}
  preprocessor state at declaration time; extend TEnumValueDecl). Risk: the finding count is
  UNKNOWN and the one population that plausibly matters most (RTL/VCL scoped enums used inside
  the platform libraries -- TSeekOrigin and similar) was never measured, so this decision is
  currently being made on a partial denominator: "0 on projects" says nothing about whether the
  rule would flood or be silent once it can see the libraries. Unblocks: nothing else in the
  backlog names this as a dependency (unlike DEC-8's use-edges, which several other items
  depend on) -- it is a standalone rule.
* (b) Drop it. Cost: 0. Matches the note's own instinct ("record, do not build") and the
  measured population (0 on every DB actually checked). Risk: if a project DOES use
  {$SCOPEDENUMS} internally (not yet observed on any of the 33 project DBs checked), the gap
  stays permanently invisible -- but there is no evidence today that this is a real population
  anywhere in this codebase's own projects.
* (c) Measure the platform libraries FIRST, cheaply, before ruling. Not costed in the
  backlog, but worth naming: a text-level (not extractor-level) grep of {$SCOPEDENUMS} across
  the two platform library source trees (RTL/VCL/third-party units already on disk) would tell
  you, for near-zero cost, whether the "unmeasured" population is large or negligible, without
  committing to the 4h48m re-parse. This directly answers the open half of the note's own stated
  gap and should logically precede (a) or (b).

### 6. Recommendation
Do (c) first, cheaply, before ruling on (a) or (b). The note's own stated blocker is not
just "the extractor doesn't record it" but "we never checked the one place this might matter" --
a plain-text scan of the platform library source for {$SCOPEDENUMS} costs minutes, not hours,
and turns "unmeasured" into a real number. If that number is near-zero (plausible: most RTL/VCL
enums predate the 2011 scoped-enum feature and were never converted for compatibility), drop the
rule (b) with confidence. If it is large, the 4h48m re-parse buys a real, previously-invisible
rule population and (a) is worth scheduling alongside some other extractor-bump work (the
backlog's own precedent, PLAN-SESSION-95, batches extractor changes precisely so one re-parse
pays for several fixes at once) rather than spending a bump on this alone.

---

## DEC-12 -- Widen the docs-sync guard to police `--flag` parity in README / AI-USAGE?

> **CLOSED 2026-10-25 -- the write-up itself says "already decided and shipped" (owner ruled 2026-09-16, F5); see its own recommendation.**

### 1. The question in one sentence
Should the docs-sync guard also enforce that every CLI flag README.md and AI-USAGE.md is in
sync with --help (as it already does for verbs), given the backlog's stated baseline of
"16 of 144 flags missing from README, 39 from AI-USAGE" as of 2026-09-06?

### 2. What the thing is
tests\autotest\run_docs_sync_guard.ps1 is a battery runner that fails the build when
--help, README.md and docs\AI-USAGE.md drift out of sync with the actual CLI source. It exists
because, per its own header, four shipping verbs (usages, outline, ghost-check,
ghost-recover) were accepted by the CLI and driven by the IDE plugin for MONTHS while --help
never mentioned them -- nothing failed, because the tool was RIGHT and only the documentation was
wrong, which produces no error anywhere a human would notice by running the tool. CLAUDE.md's
own DOCS-IN-SYNC rule (this repo's highest-priority rule) states the target: "every flag a verb
accepts is listed on that verb's line" in --help, and README/AI-USAGE are held to matching
that surface.

### 3. How we got here -- and this is where the backlog text has GONE STALE
* e13be750 "test: docs-sync guard, and cover circular-demo in the encoding guard" -- the guard's
  original creation, VERB-only.
* docs\INBOX-docs-guard-checks-help-only.md (referenced inline in the guard's own comments,
  not separately fetched this session) originally PARKED the flag-parity question as "an owner
  decision with a price, not because it is hard," recording the exact baseline DEC-12 quotes:
  "README lacked 16 flags and AI-USAGE lacked 39" as of 2026-09-05/06 -- turning the check on
  would have cost 55 doc lines up front.
* 86970482 "docs(cli): --help lists every accepted flag; --seealso is the DEFAULT, not an
  opt-in" and the accompanying README/AI-USAGE work across sessions 93-97 closed most of that
  doc debt as a SIDE EFFECT of unrelated documentation passes.
* d38ff3d2 "test(docs-guard): derive the PER-VERB flag axis from source, and measure what
  --help omits" (2026-09-15) built tests\autotest\lib\CliFlagVerbMap.ps1 -- a from-source
  derivation of flag -> TArgs field -> reading routine -> verb, specifically because "ParseArgs
  is verb-agnostic" so nothing in the parser says which flag belongs to which verb's --help
  line. This is the PER-VERB axis (CLAUDE.md's "on that verb's line"), measured then as
  124 of 439 (flag, verb) cells absent from their verb's own --help block, across 33 verbs --
  and DELIBERATELY left as a ratcheted measurement, not a failing check, because "that gap is a
  banner-DESIGN decision the owner has not taken."
* The guard's own source (run_docs_sync_guard.ps1:1312-1342, check 9 "F5") states, in its own
  comment block, dated 2026-09-16: "Re-measured 2026-09-16: 163 flags in --help, 0 missing
  from either doc. The sessions 93-97 docs work closed the debt as a side effect ... Owner
  ruled to turn it on 2026-09-16." F5 -- the exact TOTAL flag-parity check DEC-12 describes as
  undecided -- is already implemented, already ON, and already enforced in the battery.

### 4. Current behaviour today -- MEASURED LIVE this session
Ran "pwsh -File tests\autotest\run_docs_sync_guard.ps1" in full, this session:
```
F3 every flag README.md names is in --help          : 0 named in prose but not in the banner
F3 every flag docs\AI-USAGE.md names is in --help    : 0 named in prose but not in the banner
F5 README.md names EVERY flag in --help (169 flags)  : 0 flag(s) in the banner this doc never names
F5 docs\AI-USAGE.md names EVERY flag in --help       : 0 flag(s) in the banner this doc never names
```
Plus F1/F2 (accepted<->documented in --help itself), F1x/F2x/F3x (exemption-list hygiene), and
5 planted-token POSITIVE CONTROLS, all PASS. Total flag parity is fully closed today: 0 of 169
--help flags are missing from either README or AI-USAGE, and the guard actively enforces this
in every battery run (DOCS SYNC GUARD: PASS). Live catalog also confirms 189 rules
(136 builtin + 53 external), 23 fixable, 158 default-on, 16 categories -- all cross-checked
against README/INSTALL by check 2, all PASS.
What is genuinely still open is the PER-VERB axis check 9's own comment names as deliberately
NOT enforced: whether a flag is listed on the RIGHT verb's --help line, not merely somewhere in
the banner. run_flag_verb_map.ps1 exists as the measurement tool for this (not re-run this
session to avoid an unnecessary extra pass on the deployed exe, but the mechanism and its
2026-09-15 baseline of 124/439 gaps are confirmed present in source, run_docs_sync_guard.ps1:
1081-1091).

### 5. The options
* (a) Do nothing further -- the TOTAL flag-parity check DEC-12 asks about is already shipped
  and passing. Cost: 0. This is a correction to the backlog entry, not a decision: DEC-12 as
  literally worded ("16 of 144 missing from README, 39 from AI-USAGE") describes a state that
  was true on 2026-09-06 and has been FALSE since 2026-09-16. The backlog line itself is the
  stale artifact here.
* (b) Additionally enforce the PER-VERB axis (a flag must appear on the SPECIFIC verb line(s)
  that accept it, not merely anywhere in the banner). Cost: unclear from the 2026-09-15
  measurement alone -- 124 of 439 cells would need doc lines added (each cell is one flag
  mentioned on one more verb's help line), which is a real, if bounded, documentation debt, plus
  ongoing maintenance discipline on every new flag. The guard's own comment explicitly frames
  this as "a banner-DESIGN decision the owner has not taken" -- i.e. it is itself a live,
  UN-superseded piece of the DEC-12 question, just not the piece the backlog line describes.
  Risk if built naively: check 9's own header warns that attributing flags to verbs by POSITION
  in the banner text is unreliable ("measured, a naive... parse attributes --rebuild to
  resolve-dbs and --fix to exceptions-sync") -- CliFlagVerbMap.ps1's from-source
  derivation avoids this, so the machinery already exists and would not need to be built, only
  wired into an enforced (not merely printed) check.
* (c) --help-only is enough. This was DEC-12's other stated option, and after (a) it
  reduces to: also skip the per-verb axis. Cost 0, same risk profile as before -- a flag can be
  discoverable in the banner globally while being undocumented on the specific verb a reader is
  looking at.

### 6. Recommendation
Close DEC-12 as stated -- it is already decided and shipped (owner ruled 2026-09-16, F5 is
live and passing). Correct the backlog line so it stops citing a September baseline that is
now wrong. The REAL open question hiding underneath DEC-12 is the PER-VERB axis (option b),
which the guard's own source already flags as an un-ruled design decision with a real, bounded
cost (124/439 cells, machinery already built in CliFlagVerbMap.ps1, only the enforcement
switch is missing) -- recommend re-filing that specifically as its own decision item (with a
FRESH measurement, since the 124/439 figure is 13 days old) rather than leaving it folded inside
a DEC-12 entry whose headline number no longer matches the code.


---

# Owner decisions DEC-13 .. DEC-19 -- detailed background
Prepared 2026-09-28. Source: docs\BACKLOG-TRIAGE-2026-09-28.md section 2, plus the plans/notes named per section.
Engine at time of writing: deployed 1.19.0-alpha / extractor 1.20.0-alpha per the triage doc header; the task brief
says the live engine on disk is 1.20.0-alpha / resolver 1.11.0 -- both numbers are moving nightly during this
session's re-parse; treat the exact patch digit as not load-bearing for these rulings.

---

## DEC-13 -- Widen the maintenance control channel beyond the `lsp` verb?

> **CLOSED 2026-10-25 -- the need (a clean stand-down of running engines) is served by drag-lint shutdown --all and ide-release (CLAUDE.md "Building"; docs\wiki\ide-release.md).**

### 1. The question in one sentence
Should the just-shipped "ask a running engine to stand down cleanly" control channel be turned on for every
drag-lint mode (any CLI run), or should it stay wired only into the long-lived `lsp` process, as it ships today?

### 2. What the thing is
When VS Code (or the RAD Studio IDE) starts drag-lint's language server (`drag-lint lsp --stdio`), that process
holds the project's SQLite index open for as long as the editor session lasts. If you then want to deploy a new
build of `drag-lint.exe` over `third_party\dll-win64\drag-lint.exe`, or run a full re-parse of a database that
server has open, the running process is in the way. Historically the only options were: close every editor by
hand, or `TerminateProcess` it -- which can leave a `-wal` (write-ahead-log) file uncheckpointed, i.e. a database
in a not-fully-committed state.

The control channel is a small, local, authenticated side door: a Windows named pipe (not a TCP port -- a TCP
port would be reachable from a browser tab via `http://127.0.0.1:<port>`, which is a real attack surface; a named
pipe is not) that a maintenance tool can use to say "finish what you are doing and exit". Example of the new verb:

```
drag-lint shutdown --db C:\Projects\DB\ORM3\SERVER\_D-RAG\MicroniteMW1Service.sqlite --dry-run
```

This asks only the engine(s) holding that one database to stand down; --dry-run just lists what would be asked.
A real run makes the target engine checkpoint its WAL, close its stores cleanly, reply "exiting", and exit 0 --
rather than being killed.

### 3. How we got here
- Owner's original request, 2026-09-14: "Can you then make a 'backdoor' API to allow remote shutdown for cases
  when we need to do maintenance to safely close drag-lint?" (quoted in docs\PLAN-maintenance-shutdown-channel.md:46-48).
- The plan explicitly renames "backdoor" to "a documented, local, user-scoped control channel" (:52-57) and
  clarifies "remote" means another process on this machine, not network-remote (:59-64).
- Session 93 (2026-09-15) shipped T2-T6: the pipe, the shutdown verb, graceful stand-down, docs, and a guard
  (tests\autotest\run_control_channel_guard.ps1, 60 checks). T1 (an instance registry file) turned out to be
  unnecessary because the pipe name already carries the pid and vanishes with the process.
- The plan's own status line: "Requirement 5 (who listens) answered PROVISIONALLY: lsp only -- the plan's own
  recommendation, taken in the owner's absence because narrow is the reversible direction... This is the decision
  that keeps the plan parked-owner." (:16-20).
- The gate is a single named function, ControlChannelEnabledFor (src\core\DRagLint.Core.ControlChannel.pas),
  so widening is a small, documented, one-place change -- the plan deliberately built it that way so the owner's
  answer, whichever it is, is cheap to apply.

### 4. Current behaviour today
The control channel is compiled in and live, but ControlChannelEnabledFor returns true only when the process
was started as lsp. A one-shot CLI run (drag-lint index ..., drag-lint lint-all ..., drag-lint sql ...) never
opens the pipe at all -- there is nothing for drag-lint shutdown to signal, because those runs are typically over
in seconds and hold no long-lived lock. drag-lint shutdown today only ever finds lsp processes on this machine.

### 5. The options
- (a) Widen it -- have every mode open the control pipe (effort: S, per the backlog line; mechanically it is
  relaxing the one gate function and re-running the guard). What changes for the user: a maintenance tool could
  also ask a long-running batch job (e.g. a lint-all or index --all in progress) to stand down gracefully rather
  than being killed. Cost: a slightly larger attack/audit surface (more processes listening on a pipe, though
  still local-only, ACL'd per-user-per-session) and the guard suite needs extending to cover non-lsp modes. Risk:
  low -- the transport and safety properties (local named pipe, per-user ACL, shutdown-only, audited) are
  unchanged; the only change is which processes install it.
- (b) Keep lsp-only (status quo) -- effort 0. The gap this leaves: a stuck or long-running one-shot CLI invocation
  (a multi-hour library re-parse, say) still has no clean way to be asked to stop short of Ctrl+C/TerminateProcess.
  In practice this has not been reported as a problem since 09-15 -- the maintenance pain point (staging a new exe
  over a locked one) was specifically about the long-lived lsp processes VS Code spawns, which this already covers.

### 6. Recommendation
Keep lsp-only for now. The plan's own reasoning still holds: narrow is the reversible direction, and the one real
pain point that motivated this (VS Code holding the exe/DB open) is already solved. Revisit only if a second
concrete case shows up (e.g. wanting to interrupt a long index --all cleanly) -- at that point it is a small,
well-isolated change to ControlChannelEnabledFor.

---

## DEC-14 -- Multi-client T4: force a mid-session VS Code engine refresh?

### 1. The question in one sentence
Should drag-lint (or its VS Code extension) forcibly restart/refresh a live VS Code language-server session
mid-session when a newer engine build becomes available, or should this be formally closed as "no" and the item
retired?

### 2. What the thing is
The VS Code extension does not run the canonical third_party\dll-win64\drag-lint.exe directly -- it copies
("mirrors") the engine binary into its own private, version-stamped folder under globalStorage, and it only
re-copies (a) when the extension activates, or (b) when the user runs "Restart Language Server". So if a new
engine is staged while VS Code is already open and the user does nothing, that VS Code session keeps using its
old private copy until one of those two triggers fires. "T4" is the idea of forcing that refresh automatically,
mid-session, without the user restarting anything.

### 3. How we got here
- docs\PLAN-multi-client-index-safety.md is the plan that investigated the whole multi-client (VS Code + CLI +
  RAD IDE all touching one database) safety question. Owner rulings, 2026-09-14 (:44-50): (1) the extractor must
  never downgrade a database; (2) only the IDE writes, every other client reads; (3) therefore no per-client
  database copies are needed.
- T1 and T2 (LSP opens read-only + never-downgrade gate) shipped in session 93 and make version skew safe: an old
  LSP is just a reader, and an old CLI is refused before it can write/re-parse with a stale extractor (:36-41).
- T4 itself: "Not built, and the owner's call: forcing a mid-session refresh, which the extension's own design
  notes reject." (:40-41). The extension was deliberately designed to refresh only at activation/explicit-restart,
  and T4 would override that design.
- The plan measured the residual skew directly: four different engine copies were live simultaneously during that
  session's own work, one five days stale (:35-36), and the engine now prints its own version plus extractor
  version plus the DB's stamp on stderr on every store it opens, so the skew is now visible in the extension log
  even though it is not auto-corrected.

### 4. Current behaviour today
A VS Code session keeps its mirrored engine copy until the user restarts the language server or reloads the
window. Because T1+T2 make an old engine safe (reader-only, or refused-if-it-would-downgrade), the only downside
of NOT forcing a refresh is that the user may be working against a slightly older ruleset/extractor for a while --
not correctness risk, just staleness of features/bugfixes. The skew is visible on request (stderr version line)
but not proactively surfaced to the user.

### 5. The options
- (a) Retire as "no" (effort 0) -- formally close DEC-14: document that T1+T2 already make the skew harmless, and
  that forcing a live engine swap under a process that has open file handles and in-flight LSP requests is exactly
  the kind of one-way-door risk the extension's own design avoids. This matches what was already decided in
  practice (T4 not built), just makes it official rather than perpetually "still open".
- (b) Build it -- effort not costed in the plan (it was never scoped, because the extension's own design rejects
  the premise). It would mean either the extension polling for a newer staged engine and silently restarting the
  LSP connection (disruptive: in-flight requests, open document state), or prompting the user to restart when a
  newer engine appears (much smaller, but really just a friendlier version of the existing manual restart, not
  "force"). Risk: forcibly killing and restarting a live LSP connection has UX cost for a benefit that is already
  covered safely by the passive mechanisms.

### 6. Recommendation
Retire as no (0 effort). T1+T2 already remove the correctness risk; forcing a live swap only buys marginal
freshness at real UX cost, and it fights the extension's own documented design. If proactive notification is ever
wanted, that is a much smaller, separate feature (a toast saying a newer engine is available) -- not this ticket.

---

## DEC-15 -- committed= counter on the section summary line (T6)?

### 1. The question in one sentence
Should the per-section index-run summary line gain one more field, committed= (files whose rows actually landed
in the database), on top of the files=/walked=/attempted=/up-to-date= fields that already shipped?

### 2. What the thing is
Every drag-lint index run against a manifest section prints a one-line summary, e.g. (real output,
docs\PLAN-section-summary-counters.md:239):
```
=== Library [Win64] -> ...library-Win64.sqlite : files=6993 symbols=2251298 refs=3480050 walked=7007 attempted=7003 up-to-date=916 [14918.1s, 28 attempted/min] ===
```
- files= -- a STOCK: every row currently in the files table (however it got there).
- walked= -- unique paths this run admitted to the walk (added by this plan).
- attempted= -- files that got past the up-to-date check and MAY have been parsed (an upper bound: includes files
  whose parse failed and left no row, and re-visits).
- up-to-date= -- files skipped because they were already current.
- committed= (proposed, NOT built) would answer a narrower question: of the files attempted, how many actually got
  a fresh row committed this run (a query against parsed_at >= the run's start time). attempted minus committed
  would then be "attempts that did not land" -- e.g. a parse that raised an exception.

### 3. How we got here
- docs\PLAN-section-summary-counters.md (written 2026-09-09, session 81) is the full investigation. It found the
  original labels (parsed=, skipped=) were not bugs but mislabelled: parsed= was contractually an upper bound on
  attempts, not a count of files actually parsed, and skipped= counted only up-to-date skips, colliding with the
  log word SKIP which means something else (oversize file, or an exception).
- Session 84 (2026-09-09) implemented T1-T5 (renaming to walked=/attempted=/up-to-date=, adding walked=, fixing
  the throughput numerator) and shipped in commit cf8a7b2. The header block records: "T1-T5 DONE, T6 NOT DONE."
  (:4).
- T6 is explicitly marked OPTIONAL in the plan: "T6 (committed=) was not implemented -- it is marked OPTIONAL and
  adds a per-section query for a number nothing has asked for yet." (:74-75). Section 6 of the plan (:231-234)
  specs it as a read-only count query, noting the parsed_at column already exists and that src\storage sits
  outside the hashed extractor surface, so adding it costs no re-parse.
- The backlog triage (2026-09-28) re-raises it verbatim as DEC-15: "committed= counter on the section summary line
  (T6, about 1 h) -- still wanted?" -- nobody has asked for the number since 09-09, and it is being re-asked
  rather than assumed dead.

### 4. Current behaviour today
The line already reports files=/symbols=/refs=/walked=/attempted=/up-to-date= plus timing and attempted/min.
There is no committed= field. The two things it would have told you -- how many files actually got new rows, and
how many attempts silently failed to land -- are today only inferable indirectly, e.g. by grepping the log for
SKIP or exception lines, or by diffing files= before and after.

### 5. The options
- (a) Build it (about 1 h, per the plan's T6 estimate) -- a single extra read-only count query per section, no
  schema change, no version bump. What it unblocks: an operator running a big re-parse could immediately see e.g.
  attempted 7003, committed 6990 and know 13 attempts silently failed, without grepping the log. Marginal value on
  top of attempted=/up-to-date=, since attempted minus up-to-date is already a close proxy for "genuinely
  reparsed", and the log's own SKIP-with-exception lines already name failures explicitly when they occur.
- (b) Leave it out -- effort 0. The plan itself already flagged this as speculative ("adds a number nothing has
  asked for yet"), and in the time since 09-09 nothing has, in fact, asked for it -- the two real defects the
  investigation surfaced (an enum-ordinal overflow, nested-root double-walk) were found and fixed without this
  counter, using the log's SKIP lines directly.

### 6. Recommendation
Leave it parked, i.e. close as not-currently-wanted. It is cheap to build if a concrete need appears, is fully
speced already in the plan's section 6, and costs nothing to defer. Re-open it the day a real investigation needs
to distinguish "attempted but not committed" from "up to date" at a glance rather than by reading the log.

---

## DEC-16 -- lint the legacy "// note // dl:shared A" marker shape?

### 1. The question in one sentence
Should drag-lint add a lint rule that flags the OLD two-slash "// note // dl:shared A" comment shape (which the
writer no longer emits and the reader no longer honours as intended), or is this a won't-fix given it has zero
real instances?

### 2. What the thing is
dl:shared is a marker drag-lint writes into a unit's header to record which projects share that unit, e.g.
"unit YADF.Options;   // dl:shared YADF, YADFOT, YADFSetup". The scanner that reads this marker
(DRagLint.Lint.SharedUnit.pas) used to be too loose: it treated the text dl:shared anywhere inside a header
comment as a marker, even mid-prose (e.g. a doc comment that happens to say "the unit is marked dl:shared"). A
related old writer shape put a second "// " before the marker on the same source line, e.g. "// note // dl:shared
A" -- syntactically indistinguishable from a real marker with an ordinary trailing comment before it, without
knowing which one wrote it. After the D26 fix (below), the reader now requires the marker to be the first token
of its own comment, so the old two-slash shape reads as UNSHARED rather than shared -- which would silently drop
the recorded project "A" the next time someone appends a new project to that marker.

### 3. How we got here
- 2026-09-24 followups plan, item D26 (docs\superpowers\plans\2026-09-24-followups-d20-d30.md:70-75): "the
  dl:shared scanner treats PROSE as a marker" -- ScanHeader (src\lint\DRagLint.Lint.SharedUnit.pas:212-302)
  returned a hit on the first occurrence of the literal text dl:shared anywhere in a header comment, so
  src\doc\DRagLint.Doc.SharedFacts.pas's own header comment (which discusses the marker in prose) was wrongly
  treated as itself being a shared unit.
- Fix, per the plan: require the marker to be the first token of its comment, matching exactly the shape the
  writer emits.
- Implementation history (LEDGER, docs\superpowers\plans\2026-09-24-followups-d20-d30.LEDGER.md): first round
  shipped in 18d18a85, but a review caught a regression -- "CRITICAL D26 re-arm on any embedded // re-admits
  prose as marker (reproduced: '// see // dl:shared below' -> shared)" (:80). Ruling R12 (:81) then split the fix:
  the reader stays strict (never re-arms on an embedded //), and the writer changes to always emit the marker as
  the first token when the unit line already carries a comment -- because the two shapes are syntactically
  identical, only the writer, which controls what it emits, can disambiguate them going forward.
- Fix round 1 report (:86): "old '// note // dl:shared A' shape: 0 of 8 real markers (all YADF) across 35 DBs."
  Every real dl:shared marker that exists across the whole indexed estate (35 databases) was checked, and none of
  them uses the old two-slash shape. All 8 real markers found are on YADF units and are in the still-honoured
  correct shape.
- Intake note recorded for the backlog triage (:87): "a lint warning for the legacy '// note // dl:shared A'
  shape (now reads unshared; adding a project silently drops A). 0 instances today." -- this became DEC-16.
- D26 landed as part of Batch B, which the controller marked complete (:90, commits 0e685c78..ce51002e), and the
  final battery and review closed it clean.

### 4. Current behaviour today
The reader (SharedUnit.pas) is strict: a marker only counts if it is the first token of its own comment. The
writer always emits it that way. The old two-slash shape, if it existed anywhere, would now read as "unit not
shared" silently, and a subsequent add-project on such a unit would write a fresh, correctly-shaped marker that
drops whatever project list the old marker held, because the old one was never read back. Measured: zero such
units exist across all 35 indexed databases as of the D26 fix round. No lint rule exists today to detect the old
shape if one were ever reintroduced (an old branch merge, a restored backup, a hand edit).

### 5. The options
- (a) Build the rule (S) -- a small lint check that specifically matches the old two-slash-before-marker shape and
  flags it, distinct from "not shared at all", so a reintroduction is caught loudly instead of silently reading as
  unshared. Cost: small implementation plus a fixture plus docs updates; ongoing cost is one more rule in the set
  the owner reviews.
- (b) Won't-fix -- the shape has zero real instances today and the writer no longer produces it, so the rule would
  be defending against a hypothetical rather than an existing corpus problem, consistent with the "don't add a
  rule for a population of zero" discipline already applied elsewhere in this backlog.

### 6. Recommendation
Won't-fix. Zero real instances after a full 35-DB sweep, the writer is already fixed so the population cannot grow
through normal use, and the strict reader already fails safe: an old-shape marker just reads as unshared, which
undercounts sharing rather than corrupting it. If a genuine reintroduction is ever suspected, a one-off sweep over
the estate is cheaper than carrying a permanent rule for a population that has been zero since it was checked.

---

## DEC-17 -- IDE: flip ShowInfoInline?

### 1. The question in one sentence
Should the RAD Studio IDE plugin start rendering INFO-severity findings inline in the editor gutter and message
rows, given that flipping the setting will mark roughly 12,000 lines on the ORM3 baseline?

### 2. What the thing is
drag-lint reports four severities: error, warning, info, hint. In VS Code, the Problems panel shows a per-row icon
for each severity for free (VS Code draws it from the LSP DiagnosticSeverity value drag-lint sends). In the RAD
Studio IDE plugin, a per-severity registry setting gates whether a severity paints an inline gutter mark at all:
EnableInlineMarkers, ShowErrorsInline, ShowWarningsInline, ShowHintsInline are all ON; ShowInfoInline is OFF
(HKCU\Software\drag-lint\DelphiPlugin). Because info is by far the most common severity (12,173 of 14,683 findings
on the ORM3 baseline, about 83 percent), leaving it off means most findings simply never paint a gutter mark --
which is why the IDE currently looks like it shows no icons at all for most files, even though errors and warnings
are technically enabled.

### 3. How we got here
- Filed 2026-08-25 (session 37) as docs\INBOX-ide-diagnostic-icons.md, owner observation: VS Code shows severity
  icons, the RAD IDE shows none.
- Session 38 (2026-08-26) investigated and found the root cause was NOT the painter, which does draw a filled
  coloured square, but that the diagnostics cache was being populated then wiped 1.8 seconds later by a stale
  fallback engine (a Win32 fallback with no rules folder, reporting 0 findings) -- a separate, now-fixed bug.
  Along the way it explicitly measured and recorded the ShowInfoInline gate: "ShowInfoInline = 0 explains a great
  deal on its own: info is about 83 percent of findings (12,173 of 14,683)... Do not just flip it -- switching it
  on marks about 12,000 lines, which is a noise decision for the owner, not a fix." (:183-186).
- Five commits shipped in that session covering icon-rendering machinery: per-severity gutter glyphs, SVG-sourced
  design but GDI-rendered (because TImageCollection cannot render SVG in this Delphi version), and three drawing
  defects found and fixed by replaying the pixel arithmetic. But ShowInfoInline itself was explicitly left
  untouched: "ShowInfoInline = 0 was NOT flipped. It remains the owner's call." (:57), restated at :121-122:
  "unchanged, deliberately. Flipping it marks about 12,000 lines."
- The 2026-09-06 correction note at the top of the same file retires a side-question (the Win32 fallback engine,
  which turned out not to exist at all) and confirms: "What remains here is the live-IDE pixel check and the
  ShowInfoInline decision, both genuinely IDE-bound." (:12-13).
- The backlog triage's IDE-6 item (severity icons, root cause fixed, needs a pixel check after DEC-17) is gated on
  this decision -- the icon-rendering code is done and compiled, but has never been seen in a live IDE, and the
  live-IDE check is more informative once the info-severity question is settled, since info dominates the
  population that would be checked.

### 4. Current behaviour today
ShowInfoInline remains 0 (off) in the registry default. Errors, warnings and hints paint inline; info findings do
not. The gutter and message-row icon rendering code itself is built, compiled, lint-clean, and arithmetic-
verified, but has never been run in a live IDE session -- nothing has confirmed it actually paints correctly end
to end.

### 5. The options
- (a) Yes, flip it on -- what changes for the user: roughly 12,000 additional lines across the ORM3 baseline would
  suddenly carry an inline info-severity mark (a gutter icon, and a Diagnostics-panel row). This is a genuine UX
  and noise decision, not a bug fix: it could make the editor feel much busier, especially in files with many
  low-severity findings. Effort: 0 code, it is a registry-default change; the real cost is the live pixel check
  the triage line calls for, confirming the newly-visible glyphs render legibly at gutter size and do not look
  like warnings (a documented past bug: the info glyph rendered as a solid bar at one size, reading as an
  exclamation mark).
- (b) No, leave it off -- effort 0. Info stays invisible inline; it remains visible via other surfaces such as a
  lint report or the full findings list for anyone who wants it. A live pixel check should still happen for
  error/warning/hint, the smaller and less noisy population, to finally validate the icon-drawing work that has
  been compiled but unverified since 2026-08-26.

### 6. Recommendation
Leave ShowInfoInline off for now, and do the live-IDE pixel check on the error/warning/hint population first (that
is IDE-6, already unblocked either way). Info at 83 percent of all findings is a genuinely large UX change that
deserves a deliberate, separate decision once the base icon rendering is proven in a live IDE -- flipping both an
unverified rendering path and a 12,000-line volume increase in the same step makes it hard to tell which change
caused which visual problem if something looks wrong.

---

## DEC-18 -- DCU-only library indexing

### 1. The question in one sentence
Should drag-lint build a decoder that extracts symbol-surface information from compiled .dcu files for
closed-source libraries that ship no .pas, or should this stay parked until a real closed-source library actually
blocks someone?

### 2. What the thing is
A .pas file is Delphi source text; a .dcu ("Delphi Compiled Unit") is the compiler's binary output for that unit
-- machine code plus a compiled symbol table, no source text. drag-lint's whole indexing pipeline is built on
tree-sitter parsing real .pas text, so today any unit that ships only as a .dcu (common for third-party
closed-source components, and for editions of Delphi that omit RTL/VCL source) is invisible to drag-lint: no
completion, no hover, no go-to-declaration, no "what implements this interface" for those units. The proposal is
to write a binary DCU decoder that reconstructs just the interface surface (unit name, uses clause, public and
published types, method signatures, properties, constants) as a synthetic .pas-shaped stub (a ".pasu"), and feed
that stub through the existing tree-sitter indexer -- so no new extraction or schema code is needed, only the
decoder plus some origin-tagging bookkeeping so real source always wins if it later becomes available.

### 3. How we got here
- Captured 2026-06-18 as docs\BACKLOG-dcu-indexing.md, from a design discussion, not a specific blocking incident.
- The note itself frames the key risk plainly: "Dominant risk: Version fragility. The DCU layout is undocumented
  and shifts per compiler release. RAD Studio 37 / Delphi 13 Florence is brand new; an existing decoder may not
  handle its DCUs yet." (:79-81).
- It proposes a one-day de-risking spike FIRST, before any real build: decode a unit already covered by source
  (e.g. System.SysUtils) with an existing decoder such as DCU32INT or IDR, diff the extracted interface against
  the known .pas, and that answers whether any decoder even understands Florence DCUs at all, and how complete
  the extraction is -- the two facts that decide whether the rest is worth doing.
- Re-asked at the 2026-09-16 session-100 triage and explicitly re-parked: "owner: KEEP PARKED. The one-day spike
  stays the entry point whenever a closed-source library actually blocks someone." (top of the file). This has
  already been ruled on once, less than two weeks before the current triage, and DEC-18 in the 09-28 backlog is
  re-listing that standing ruling rather than raising something new.

### 4. Current behaviour today
Nothing has been built. drag-lint has no DCU decoding capability at all; closed-source, source-less libraries
remain entirely unindexed: no symbols, no completion, hover, or go-to-declaration coverage. This has not, per the
note, actually blocked anyone yet on this codebase's own projects -- ORM3, YADF and the rest all ship with full
.pas source for what they use.

### 5. The options
- (a) Do the one-day spike now, proactively (effort about a day, then re-decide) -- resolves the two open unknowns,
  whether an existing decoder parses Florence DCUs at all and how complete the extraction is, before there is a
  concrete need. Upside: removes surprise later. Downside: spends a day on a problem nobody currently has, with
  real risk the spike simply confirms the fragility concern and produces no reusable artifact.
- (b) Keep parked until a closed-source library actually blocks someone (0 effort now, a much larger effort if ever
  built) -- the standing ruling since 2026-09-16. When it does become blocking, the one-day spike is the
  well-defined first step, and only if that succeeds does the full build get scheduled: a decoder, stub synthesis,
  origin and supersession bookkeeping, and per-platform library DB integration.

### 6. Recommendation
Keep it parked, consistent with the standing 2026-09-16 owner ruling. Nothing has changed since then to justify
revisiting it, no blocking incident has been reported, and the note already defines the correct, cheap first step
for whenever one appears. Re-litigating a decision made less than two weeks ago with no new evidence would just be
spending the same day of effort earlier than needed, against an undocumented, version-fragile binary format.

---

## DEC-19 -- Bind bare reads of the enclosing class's own FIELDS? (RB-2, charts in-class-field-reads)

> **CLOSED 2026-10-25 -- shipped: 3bf1f06c "merge: feat/e5-resolver -- E5/DEC-19" (resolver 1.12.0-alpha, 1.24.0-alpha).**

### 1. The question in one sentence
Should the resolver be changed to bind a bare read of one of the enclosing class's own FIELDS (e.g. "if FConnected
then" inside a method of the class that declares FConnected), the same way it already binds bare PROPERTY reads
and bare field/property WRITES -- at a measured cost of 31,417 new rows on ORM3 SERVER and 21,137 on ORM3 CLIENT?

### 2. What the thing is
Consider:
```pascal
type
  TPipeClientConnection = class
  private
    FConnected: Boolean;
  public
    procedure DoSomething;
  end;

procedure TPipeClientConnection.DoSomething;
begin
  if FConnected then   // a BARE read of the class's own field
    ...
end;
```
FConnected here is not qualified by Self. or any receiver -- it is just named directly, relying on Delphi's
ordinary scoping rule that an unqualified name inside a method first checks the enclosing class, and its
ancestors, for a matching member. drag-lint's resolver walks exactly that scoping chain (with-scope, then locals
and parameters, then the enclosing class and its ancestors) for every bare name it sees, in ResolveBareMemberRead
(src\index\DRagLint.Index.CallResolver.pas:4185). When it reaches the class and finds FConnected, it currently
checks what kind of member it found -- roughly: if the member is a property, bind it (record a member_accesses
row, a getter call edge, and so on); if it is anything else, a plain field, AND the read is bare with no explicit
receiver, decline with reason 'field' and write nothing for that reference (the exact lines are CallResolver.pas
4236-4238). The exact same Self.FConnected written explicitly, however, DOES bind, because the "bare, no receiver"
condition is false when there is a receiver, and a WRITE to the bare field (FConnected := True) already binds too,
since an earlier fix (D13). So today: bare field WRITE binds, bare field READ does not, and Self.field READ binds.
DEC-19 asks whether to close that last remaining gap.

### 3. How we got here
- The resolver's own doc comment states the design explicitly, and dates it: "A FIELD of the enclosing class read
  BARE is NOT bound ('field'), deliberately: that population is every bare field read in a codebase, and D16a
  asked for properties." (CallResolver.pas:1374-1376, in the remarks on the ResolveBareMemberRead declaration).
  The backlog triage line adds: "Deliberately declined since 1.8.0 and pinned by two guards as a separate
  decision."
- D13 (2026-09-23, resolver 1.8.0-alpha) shipped the bare-field-write binder and the Self.X read/write binder
  (property or field).
- D16a (same batch) shipped the bare-property-read binder (e.g. "N := TotalP" inside the class binds to the
  property, with its getter call edge) but deliberately stopped short of fields, per the same remark.
- Two guards pin the field-read decline as an intentional, tested boundary, not an oversight:
  - tests\callresolve\run_with_scope_bind.ps1, case OWN-FIELD (:165-167): "a bare own-class FIELD read stays
    unbound (by design)" -- and the file's header comment spells out the rule: "A bare FIELD read in its own
    class is deliberately left unbound (the population is every field read in the corpus; binding it is a
    separate decision) -- pinned by OWN-FIELD." (:27-29).
  - tests\callresolve\run_parenless_call_bind.ps1, case NEG-FIELD (:161-162): "check 4b NEG-FIELD: an own-class
    FIELD read stays unbound", with the comment: "NEG-FIELD is an own-class FIELD, left unbound by design."
    (:151).
- The gap was independently rediscovered from the outside by the charts and analytics team:
  docs\INBOX-in-class-field-reads-unbound.md (found during a charts re-baseline, ORM3 CLIENT, engine
  1.19.0-alpha, resolver 1.8.0-alpha). It gives concrete reproducers -- FConnected in TPipeClientConnection: 3
  unbound bare reads; Blueprint4.TfrmBlueprint4.FNoRecursion: 9 unbound bare reads, noting "48 bare writes to it
  ARE bound since D13" -- and explicitly asks "Please check whether one fix covers both" (D16 properties and this
  field case). Its impact note: "find-callers --resolved cannot report these reads... the charts now count them
  as unbound bare reads find-callers does not report, beside the reported total, so no chart says (0 reads)
  falsely." I.e. the charts team has already built a workaround shim for the gap rather than being blocked by it.
- A closely related but different gap, docs\INBOX-charts-receiver-typed-calls-unbound.md (a call or read through a
  unit-level var receiver of a project class, e.g. GDatasetsDef.GetTable), was raised by the same charts round and
  has already been fixed and shipped (commit 1aaeb0d0, resolver 1.11.0, RB-1 in the triage list) -- a sibling of
  DEC-19 in that both are cases where the charts' name-resolution shim needs something the resolver did not bind,
  but it is not itself blocked on this ruling.
- The 2026-09-28 backlog triage formalizes the pending case as both RB-2, in the ready-to-build resolver-batch
  table (BACKLOG-TRIAGE-2026-09-28.md:98, status "NOT CHANGED -> DEC-19"), and DEC-19, the actual owner-decision
  row (:87), each cross-referencing the other -- RB-2's plan note even says "one pass with RB-3; check one change
  covers both", i.e. it was scoped to piggyback on another already-planned resolver change if convenient.

### 4. Current behaviour today (measured read-only, 2026-09-28)
Confirmed against the live third_party\dll-win64\drag-lint.exe and the current ORM3 databases, read-only sql
queries only, no index or write performed:

- member_accesses table today: 19,603 rows on ORM3 SERVER
  (C:\Projects\DB\ORM3\SERVER\_D-RAG\MicroniteMW1Service.sqlite, 74.7 MB), 13,796 rows on ORM3 CLIENT
  (C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite, 171.6 MB).
- member_accesses is where a bound read or write of a field or property lands -- it is the fact table
  find-callers --resolved, the charts' who-reads and who-writes queries, and any lint rule keyed on member access
  (e.g. purity analysis) all consume. Every declined bare field read today produces a refs row (kind='read') with
  symbol_id IS NULL and no member_accesses row -- it exists as raw text and position data but carries no "this is
  a read of field X" fact anywhere a consumer can query.
- What DEC-19 "yes" would change, per consumer:
  - find-callers --resolved would start reporting these bare field reads as resolved accesses of the field, where
    today it reports nothing for them (the charts' own workaround note confirms this: "so no chart says (0 reads)
    falsely" -- meaning they are currently invisible, not falsely zero).
  - Charts who-reads / who-writes (in-class-field-reads in the charts' own naming) would get real, resolver-certain
    rows instead of relying on their own by-name shim; the charts note frames this exact population as its ask.
  - Lint rules that walk member_accesses (purity and effect analysis, unused-field-style checks) would see a large
    jump in recorded field-read activity for essentially every class with private fields read in their own
    methods -- a real behavioural change to any rule's counts, not just a coverage improvement.
- DB growth implied: measured via dbstat, read-only, on SERVER, the current 19,603-row member_accesses table
  occupies 663,552 bytes across 162 pages -- about 34 bytes per row at the page level. Applying that rate: plus
  31,417 rows on SERVER is roughly an extra 1.05 MB of table data (member_accesses would grow from 19,603 to about
  51,020 rows, a 160 percent increase); plus 21,137 rows on CLIENT is proportionally similar in absolute bytes,
  growing that table from 13,796 to about 34,933 rows, a 153 percent increase. Against DB file sizes of 74.7 MB
  (SERVER) and 171.6 MB (CLIENT) this is a small fraction of total size, roughly 1 to 1.5 percent -- indexes on
  member_accesses (e.g. by ref_id) would add somewhat more but not change the order of magnitude. The growth is
  not a storage concern; the real cost is entirely the behavioural change to consumer counts described above, plus
  the resolver re-resolve time, which is minutes, not a full re-parse.

### 5. The options
- (a) Yes, bind it. Cost, per the backlog line: "S code plus re-pin the two guards plus resolver bump."
  Concretely: change the field-decline branch in ResolveBareMemberRead to also bind plain fields, mirroring what
  already happens for Self.X and for property reads; rewrite the OWN-FIELD case in run_with_scope_bind.ps1 and the
  NEG-FIELD case in run_parenless_call_bind.ps1 from "stays unbound" assertions to "binds" assertions, since both
  currently exist specifically to prove the decline and so must flip, not just be relaxed; bump the resolver
  version constant; and re-resolve every project plus both platform libraries (minutes per project, roughly 74
  minutes per platform library per the standard cost figures -- CallResolver.pas is entirely resolver surface,
  confirmed via tests\resolver-surface.txt:26, so this is a resolver bump, NOT an extractor bump and not a
  multi-hour re-parse). What it unblocks: closes the last gap in "does a bare name inside a class bind the way
  Delphi actually resolves it", making writes, properties and now fields all consistent; removes the charts'
  by-name shim for this one case; makes find-callers --resolved and any purity or effect-style lint honest about
  field-read activity for every class. Risk: this is a large volume increase to a well-established fact table,
  roughly 30 to 60 percent more member_accesses rows on real projects -- any downstream rule or chart that treats
  "member reads" as a meaningful count, not just presence or absence, will see its numbers shift materially and
  will need to be re-baselined, exactly as happened for the RB-1 sibling fix, where charts had to re-clone and
  re-baseline after that one shipped.
- (b) No, leave it declined. Effort 0. Charts keeps counting these as unbound-but-known reads via its existing
  by-name shim, which it already built and which already avoids the "(0 reads)" false-negative problem. The
  asymmetry -- writes bind, bare reads do not, Self.-qualified reads do -- remains slightly confusing to a future
  reader of the resolver's own contract, but the contract already documents why, in its own words, at the
  declaration site.

### 6. Recommendation
Yes, bind it (option a). This is the more consistent design: Delphi itself does not distinguish FConnected from
Self.FConnected scoping-wise, and the resolver already binds the write side and the qualified-read side of the
exact same fields, so leaving only the bare-read case declined is an arbitrary asymmetry, not a safety-motivated
one, unlike DEC-18's genuine precision and version-fragility concern. The cost is small and well understood: S
code, two known guard edits, a resolver-only bump measured in minutes, not hours; and the DB growth is real but
small in absolute terms, roughly 1 to 1.5 percent of DB size. The one thing to do before flipping it: notify the
charts and archify-ir stream in advance, since their by-name shim and any counts built on today's "field reads are
absent" baseline will need to re-baseline the same way RB-1 required -- this is exactly the kind of change the
"charts re-clone after a resolver bump" pattern already exists to handle, so it is a known, not a novel,
coordination cost.
