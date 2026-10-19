# WWW folder -- Delphi-RAG-Lint.com

This folder is the website source for https://www.delphi-rag-lint.com.

## Before writing an article

Read `ARTICLE-RULES.md`. It covers the metadata block, the Micronite mention, and the exact folder and file layout.

## Structure

- `site.json` -- products (name, repo, help links), Micronite URL, changelog links
- `build.ps1` -- builds the static site from source to `_site/` (git-ignored)
- `publish.ps1` -- runs build, checks output, uploads to IONOS with WinSCP
- `articles/` -- one folder per article, named `yyyy-mm-dd-slug`, containing `index.html`
- `help/` -- help pages (not this work; see the main spec)
- `templates/` -- `page.html` (layout), `404.html` (error page)
- `assets/` -- `style.css`, `fonts/` (IBM Plex), `releases.js` (GitHub version refresh)
- `web.config` -- IIS configuration (https redirect, security headers, 404 page)
- `tests/` -- PowerShell test suite, includes Node.js tests for `releases.js`

## Spec and design

See `C:\Projects\Delphi-RAG-lint\docs\superpowers\specs\2026-10-19-website-base-design.md` (git-ignored, local file).

## Never edit

- `help/dl/` -- owned by featuregen (CONVERTER team); test it when they deliver, then update the build
- Any generated manifest or feature registry files in `docs/wiki/`
