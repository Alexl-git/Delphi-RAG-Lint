# D6 report: cycle-lab and the Haiku run (2026-10-28)

Proposed wording for the WWW article "untangling circular uses" (WEBSITE owns the file):

> Section 08, "Honest edges", add: "We keep a lab of the shapes the engine will not touch (a class
> that is created or cast across the cycle, a reference-counted class, a metaclass, a conditional
> uses entry) and one project that does not compile at all (F2047). drag-lint reports each one with
> its kind and line. We handed that report alone to Haiku. It kept the build green every time, but it
> broke the cycle in three of seven cases; in the other four it moved a class into a new unit that still
> used its partner, so the cycle only changed its name. The check that counts is the one the playbook
> ends with: cycles must stop printing 'interface coupling' for that pair."

Open items: LabInc is not detected (uses in an include); cycles --fix --apply re-index drops
{$IFDEF}-guarded uses edges (post-apply prediction mismatch); fix dry run on an F2047 project says
mechanical, apply rolls back.