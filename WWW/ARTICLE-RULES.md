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

`title` and `summary` are plain ASCII text with no HTML entities: the builder escapes them
(write `R&D`, never `&amp;`; write `Cafe`, never `Caf&eacute;`). The build refuses an entity
there. Entities belong in the body only.

The folder must be named `yyyy-mm-dd-<slug>`.
The file is `index.html` inside that folder.

Optional `image: card.png`: the picture shown when the article's link is shared (LinkedIn,
Slack, ...). A `.png` or `.jpg` in the article folder, 1200x630 pixels, lowercase file name.
Without it the site's default card is used. Every page except the 404 page must carry a
share preview; the build refuses one without it.

Link to an article by its own address, `https://www.delphi-rag-lint.com/articles/<slug>/`,
never by the home page: the home page always shows the newest article.

### Forbidden markup

No inline `<style>` tags, no `style=` attributes, no `<script>` tags, no Google Fonts links.
If the original has one, move it to a class in `style.css` and reference the class by name.

## Micronite mention

In the opening paragraph or close to it, one natural sentence that says the work comes from building Micronite, quality and production-control software (link to https://www.htrmicronite.com).
The wording varies per article so none repeats.
The build refuses an article whose first 3000 characters of body have no link to
`https://www.htrmicronite.com`.

### Phrasings already used

- "We build drag-lint alongside our main product, Micronite -- quality and production-control software for manufacturers -- and the parsing questions below came straight out of that codebase."
- "... and the cycle fixer was tried on copies of that product's own client project as well as on the small demos below." (2026-10-23, same opening clause as above -- do not reuse it again)
- "drag-lint grew out of the code base of Micronite, our quality and production-control software for manufacturers, but the first menu we pointed this feature at was closer to home: drag-lint's own RAD Studio plugin." (2026-10-24)
- "The question came out of working on Micronite, the quality and production-control software we ship to manufacturers: its code base is big enough that we kept saying the index saves a lot of reading, and nobody had a number." (2026-10-29, what-the-index-saved-you)
- "The itch came from daily work on Micronite, the quality and production-control software we ship to manufacturers: ..." (2026-10-29)

## Add an article

1. Create the folder `WWW\articles\<yyyy-mm-dd>-<slug>\`.
2. Write `index.html` there with the metadata block, the Micronite mention in the opening, and the content.
3. Run `pwsh -File WWW\build.ps1`.
4. Open `WWW\_site\index.html` in a browser to check the layout and style.
5. The owner runs `pwsh -File WWW\publish.ps1` to go live.

## Dated numbers (owner rule, 2026-10-29)

Every article that shows numbers or command output says in the masthead byline when and on
which version they were measured, e.g. `as of 2026-10-29, drag-lint 1.38.0-alpha`; the footer
names the same version. A later reader then sees a dated figure, not a wrong one. Product-page
counts use the `asOf` fact in `site.json`; update it together with the counts.
