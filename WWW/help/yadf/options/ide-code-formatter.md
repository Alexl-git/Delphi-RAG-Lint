---
id: ide-code-formatter
title: Use YADF as the IDE code formatter
summary: Use YADF for Format Source and format-on-save (Delphi 13.2+, F profile). Needs an IDE restart.
group: ide-and-profiles
groupTitle: Profiles & IDE integration
order: 20
default: "off"
since: "1.0.21.0"
status: "preview"
manual: true
---

# Use YADF as the IDE code formatter

Only shown on the IDE options page, and only meaningful in Delphi 13.2 or
newer, which has a pluggable code-formatter interface.

When on, the IDE's own **Format Source** command and format-on-save call YADF
with the settings of the [F profile](profiles.md). When off (the default) the
IDE keeps its built-in formatter and YADF is used only through its own
shortcuts and the command line.

The change takes effect after an IDE restart.

## Related

- [Profiles (F and R)](profiles.md) - choose which settings the IDE formatter uses.
