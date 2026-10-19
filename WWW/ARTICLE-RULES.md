# Article Rules

## Author

Claude Code, working in this repository, so articles are grounded in the real source, docs and release notes.
Facts are checked against the code or the drag-lint index before they are written.

## Audience

Working Delphi developers. Plain, concrete, no hype or marketing superlatives.

## Format

An HTML fragment in the site's style (inherited from the PARSING-LAYERS look).
Layout components may come from that file.
Any diagrams are inline SVG.
No external scripts or fonts.
All 7-bit ASCII.
Metadata block on top.

### Metadata block

Every article starts with an HTML comment block:

```html
<!--article
title: <Title Case>
date: yyyy-mm-dd
slug: lowercase-hyphen-separated-words
summary: One sentence, the standfirst's first sentence.
-->
```

The folder must be named `yyyy-mm-dd-<slug>`.
The file is `index.html` inside that folder.

### Forbidden markup

No inline `<style>` tags, no `style=` attributes, no `<script>` tags, no Google Fonts links.
If the original has one, move it to a class in `style.css` and reference the class by name.

## Micronite mention

In the opening paragraph or close to it, one natural sentence that says the work comes from building Micronite, quality and production-control software (link to https://www.htrmicronite.com).
The wording varies per article so none repeats.

### Phrasings already used

- "We build drag-lint alongside our main product, Micronite — quality and production-control software for manufacturers — and the parsing questions below came straight out of that codebase."

## Add an article

1. Create the folder `WWW\articles\<yyyy-mm-dd>-<slug>\`.
2. Write `index.html` there with the metadata block, the Micronite mention in the opening, and the content.
3. Run `pwsh -File WWW\build.ps1`.
4. Open `WWW\_site\index.html` in a browser to check the layout and style.
5. The owner runs `pwsh -File WWW\publish.ps1` to go live.
