---
id: delphi10-compat
title: Downgrade inline vars
summary: Hoist inline var declarations into a var block so the code builds on Delphi 10.2.3. Best-effort.
group: delphi-10-compatibility
order: 10
default: "false"
ini: Delphi10Compat
since: "1.0.0.0"
status: "stable"
---

# Downgrade inline vars

Hoist inline var declarations into a top-of-routine var block so the code builds on Delphi 10.2.3. Explicit types and simple literals are converted; the rest get a // TODO -oYADF marker. Best-effort, unverified on a real Tokyo toolchain.
