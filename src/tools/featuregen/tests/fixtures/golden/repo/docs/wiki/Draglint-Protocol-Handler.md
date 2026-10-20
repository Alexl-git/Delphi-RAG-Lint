# The draglint:// Protocol Handler

**Makes a click on a chart row or a trace anchor open its line in RAD Studio.** A browser cannot write to the IDE plugin's named pipe, so one per-user registry key hands the `draglint://` link to `drag-lint-open.exe`, a small GUI helper (no console window, no PowerShell), which checks the link and passes it on. Part of [Charts and the IDE](Charts-and-the-IDE).

## Running it

```
drag-lint protocol register [--handler <drag-lint-open.exe>] [--dry-run] [--force]
drag-lint protocol status [--json]
drag-lint protocol unregister [--dry-run] [--force]
```

* `register` writes one key, `HKCU\Software\Classes\draglint` (never HKLM, no elevation), whose command runs the handler. The handler defaults to the `drag-lint-open.exe` beside `drag-lint.exe` and is registered in place. A handler inside a `*-wt\` worktree, or a registration that belongs to another program, is refused unless `--force` is given. `--dry-run` prints what would be written and writes nothing.
* `status` prints the registered command and one class: `ours`, `legacy-powershell`, `foreign` or `none`. It exits 0 only for `ours`. A key with no command is kept by `unregister` unless `--force` is given.
* `unregister` removes the key when it is ours or the legacy PowerShell one; a foreign one needs `--force`. `--dry-run` lists what it would remove.

The installer runs `drag-lint protocol register --handler <install>\bin\drag-lint-open.exe --force` as its optional `draglint://` task (it asks first when a registration already exists), and `protocol unregister` on uninstall only when this setup made the registration.

## What the handler accepts

Any web page can carry a `draglint://` link, so the handler validates before it does anything else. It takes exactly one argument, the link. The scheme match is case-insensitive. It rejects:

* a control character anywhere (a TAB or LF would forge a pipe frame);
* anything but a local drive path: no UNC, WebDAV, `\\?\` or device path (a UNC existence check alone leaks NTLM credentials);
* a `:` stream or a wildcard, a segment ending in a dot or space, a reserved device name (COM/LPT with a superscript 1-3 count too);
* a drive letter that is not ASCII A-Z;
* an extension outside `.pas .dfm .dpr .inc .sql .fmx` (never a project or package file);
* a line or column that is not ASCII digits (line 0, a chart's focus box, opens at line 1);
* a key given more than once.

A drive letter does not prove locality: a mapped or subst'ed drive can be a network share, so the handler reaches only servers the user has already mapped.

## What a click does

With RAD Studio running and the plugin loaded, the handler writes `<file><TAB><line><LF>` to the pipe `\\.\pipe\drag-lint-open-source` and the IDE navigates. With no IDE running it opens the file in **Notepad**, never by its default verb. A rejected link exits 2 after one line (attacker text capped at 512 characters) in the log `%LOCALAPPDATA%\drag-lint\logs\uri-handler.log`.

## Migration from a PowerShell registration

Earlier builds registered `charts\src\Register-DragLintProtocol.ps1`, which copied `Open-DragLintUri.ps1` to `%LOCALAPPDATA%\drag-lint\`. `drag-lint protocol status` reports that as `legacy-powershell`; `drag-lint protocol register` replaces it silently and deletes the copied script. Those scripts are superseded by the verb and the exe.

## Related

[Charts and the IDE](Charts-and-the-IDE), [ask](ask). Guards: `tests\autotest\run_protocol_verb.ps1`.