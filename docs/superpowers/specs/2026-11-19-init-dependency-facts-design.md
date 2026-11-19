# Init-dependency facts (lane INITDEP, 1.52.1)

Status: implemented on lane/v1521-initdep (owner away; design decided by the lane per the
2026-11-19 ruling Q2: "prebuilt init-dependency facts in the library index -- unit X init
registers into A/B -> X needed iff A/B used"). Spec loop run in one window (gates self-approved).

## Problem

`unused-unit-in-uses` cannot tell a dead import from a registration unit. FireDAC driver links
(`FireDAC.Phys.FB`), `FireDAC.Stan.Def`, `FireDAC.Stan.Async`, `FireDAC.VCLUI.Wait` export nothing
the project references, yet their `initialization` section registers a class into a registry
another unit owns. Today such a unit is an INFO "VERIFY BEFORE REMOVING" finding (13 of 13 false
on drag-lint's self-LoopZero). Lane SLZ-RULE1 adds an ALLOW-LIST of registration families as a
fallback. This spec adds the FACT the allow-list approximates.

## The fact

For every unit U with an `initialization` section, the index records the set of OTHER units the
section reaches: `init_deps(unit_symbol_id, target_unit, via_name)`.

* Reach = every ref enclosed by the initialization section (refs.enclosing_symbol_id, F2), plus,
  transitively, every ref enclosed by a routine OF THE SAME FILE that a reached ref binds to
  (`initialization RegisterAll;` follows into `procedure RegisterAll`). Kinds followed:
  procedure, function, method, constructor, destructor.
* A reached ref bound to a symbol declared in another file contributes that file's unit name
  (`FDRegisterDriverClass` -> `FireDAC.Phys.Intf`).
* A reached ref that is UNBOUND contributes the marker row `target_unit = '?'` (facts incomplete),
  except True/False/nil and the System intrinsics/basic types in a fixed list (Assigned, SizeOf,
  Length, Inc, Integer, string, ...), which the index never binds.
* Refs bound to the unit's own symbols contribute nothing (own variables, own classes).
* finalization and class constructors are NOT read: a finalization undoes what init did, and a
  unit with a class constructor keeps today's handling (excluded by `UnitHasSideEffectSection`).

Written by the resolver (calls stage, inside its transaction, after every binding stream), rebuilt
whole on each calls pass (~4 s on library-Win64, 1,936 sections). Stamp: meta
`init_deps_format = 1`. A DB without the stamp has NO facts (not "no deps").

Extractor/resolver surface: needs the INT extractor bump (re-parse fills every DB) and
DRAGLINT_RESOLVER_VERSION bump; this lane bumps neither.

## Consumption: unused-unit-in-uses

For a used unit U that is otherwise unused (no export referenced, no DFM class, no inline marker):

1. Look up U's facts in the store that holds U (project first, then library -- as InitSectionInfo).
2. Verdict:
   * **needed** -- some target T is `System`/`SysInit`, or T is reachable from the project WITHOUT
     passing through U (BFS over unit_uses from every project file; library units resolved by
     name in the library store, scope prefixes System./Winapi./Vcl./Data./Xml. tried for a bare
     name). -> no finding.
   * **dead** -- facts complete (no `?` row), at least one target, and no target reachable.
     -> WARNING, message names the targets.
   * **unknown** -- no stamp, an EMPTY target set (no section, or a section touching only the
     unit's own symbols and System intrinsics -- `Randomize` is one, so "empty" is not proof of
     idleness; InitSectionInfo's idle proof keeps deciding that case), a class constructor /
     destructor, or no target reachable but the facts are incomplete. -> fallback: the allow-list
     (`IsSideEffectUnit`, extended by SLZ-RULE1), then today's INFO/idle logic.
3. Facts win over the allow-list in BOTH directions (owner ruling: facts win, allow-list is the
   fallback): an allow-listed unit whose facts are complete and unreachable is reported.

Known limits (accepted, conservative): two registration units that each make the other's target
reachable both read as needed (mutual drag); a unit linked anyway through another path is not
reported even though removing this edge is safe.

## Acceptance (EARS)

* A1 WHEN the resolver runs THE index SHALL write one init_deps row per (unit, other unit reached
  by its initialization section) and stamp `init_deps_format`.
* A2 WHEN the section calls a same-file routine THE facts SHALL include the units that routine reaches.
* A3 IF a reached ref is unbound and not an intrinsic THEN the facts SHALL carry a `?` row.
* A4 WHEN an unused unit's init targets are reachable from the project without it THE rule SHALL
  NOT report it. (fixture: uReg registers into uRegistry; uConsumer also uses uRegistry)
* A5 WHEN an unused unit's facts are complete and no target is reachable THE rule SHALL report it as
  a WARNING naming the target. (fixture: uOrphanReg registers into uLonely, used by nobody else)
* A6 IF the facts are incomplete and no target is reachable THEN the rule SHALL fall back (INFO).
* A7 IF the DB carries no `init_deps_format` stamp THEN the rule SHALL behave exactly as before.

## Measured (2026-11-19, facts applied to COPIES of library-Win64 + drag-lint's own DB)

library-Win64: 2,131 rows, 1,544 units, 401 `?` rows, ~60 s. drag-lint itself:
unused-unit-in-uses 44 -> 34; the 10 removed are exactly the FireDAC Stan.Def / Stan.Option /
Phys.SQLite / Phys.IB / Phys.FB INFO findings self-LoopZero called false; 0 new findings, 0 dead
verdicts (the project uses FireDAC). A further 44 MARKED findings are answered by the project
DB's own facts -- `dl:ok unused-unit-in-uses ... linked for its initialization
(RegisterLspFeature)` in DRagLint.LSP.Features (13), Charts.Producer.Delphi (25), FieldRepo.FbImport
/ Schema (3+3) -- and those markers now read review-marker-unused (remove in the SLZ-MARK sweep). The fixture that first
shared one registry across three orphans showed the mutual-drag limit live (all read needed).

Fixtures: `tests\autotest\run_init_dependency_facts.ps1` (index a two-DB layout -- lib + prj -- and
assert A1-A7, each with a positive control).
