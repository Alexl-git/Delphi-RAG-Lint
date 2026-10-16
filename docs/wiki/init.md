# init

Configures a repository the way CodeGraph does: one `_D-RAG\config.json` at the
repository root holds everything drag-lint needs to know, and every verb run
inside that repository finds it by walking up from the current folder. Reach for
it once per repository, before the first `drag-lint index`.

## Running it from the CLI

```
drag-lint init [<root>] [--project <x.dproj>] [--force]
```

It writes `<root>\_D-RAG\config.json` -- the repository's only configuration:
`"projects"` (name, dproj, platform, delphi), `"exclude"`, `"settings"`,
`"docs"`, `"lint"`, `"layers"` -- plus a `.gitignore` beside it and a `_D-RAG`
line in `.cvsignore` when `<root>` holds a CVS working copy. In an SVN working
copy it prints the `svn propedit svn:ignore` command instead of running it.
Every `.dproj` under `<root>` becomes a project; its `"delphi"` comes from the
`.dproj` `ProjectVersion`. An existing config is never overwritten: `--project`
adds or updates one project, and `--force` rediscovers them all; both keep every
other key.

After `init`, `drag-lint index` with no target indexes every configured project
into `<root>\_D-RAG\<name>.sqlite`, and no `--db` is needed inside the
repository.

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

No index required: `init` only reads the project files below `<root>` and writes
the config. A repository without a `config.json` keeps working exactly as
before (the manifest and `.drag-lint.json` are still read).

## Example

Illustrative:

```
cd C:\Projects\MyRepo
drag-lint init
drag-lint index
```

This would register every `.dproj` below `MyRepo` and index each one into its
own database under `MyRepo\_D-RAG`.
