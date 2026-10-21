---
id: profiles
title: Profiles (F and R)
summary: Named settings files. F = Ctrl+Shift+Alt+F, R = Ctrl+Shift+Alt+R; assign a profile to a key with Set F / Set R.
group: ide-and-profiles
groupTitle: Profiles & IDE integration
order: 10
default: "yadf.ini"
since: "1.0.9.0"
status: "stable"
manual: true
---

# Profiles (F and R)

A profile is an INI file (`yadf-<name>.ini`) holding a complete set of
formatting options. The Profiles panel in YADFSetup and on the IDE options
page lists them and shows which one you are editing.

## F and R

Two profiles can be bound to keys:

- **F** - Ctrl+Shift+Alt+F in the IDE; also the profile the command line uses
  when no `--ini` is given. If F is unassigned, `yadf.ini` is used.
- **R** - Ctrl+Shift+Alt+R in the IDE, for a second style (for example a
  stricter one for new code).

## Buttons

- **Set F / Set R** - assign the selected profile to that key.
- **Unassign** - clear the F or R assignment of the selected profile (F then
  falls back to `yadf.ini`). Keyboard: Del.
- **New...** - create a new `yadf-<name>.ini`, seeded with the current
  settings.

The F/R mapping is stored in `%APPDATA%\YADF\profiles.ini`.

## Related

- [Use YADF as the IDE code formatter](ide-code-formatter.md) - uses the F profile.
