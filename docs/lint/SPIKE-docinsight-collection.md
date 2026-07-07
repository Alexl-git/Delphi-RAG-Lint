# Spike: RAD Studio DocInsight-collection investigation

Status: investigation only, no code changed. Feeds a future decision for
drag-lint's AutoDocument track. Bounded spike (~1 session), not exhaustive.

## Question

The user recalled that RAD Studio collects documentation into a folder
during compilation, and asked why it never gave meaningful results. This
note investigates what that feature actually is, how it is configured, why
it likely underdelivered, and what drag-lint should do about it.

## 1. What the feature actually is (two distinct things, often conflated)

RAD Studio has **two unrelated features** that both revolve around the same
`///` triple-slash XML doc comments, and they are easy to confuse:

- **(a) Help Insight (IDE tooltip, no file output).** This is a built-in
  Code Insight feature. The IDE parser reads `///` comments directly from
  source and renders them as a hover tooltip (type, declaring file/line,
  and any `<summary>`/`<param>`/etc. content) while editing. Confirmed via
  web search of the docwiki "XML Documentation Comments" / "Help Insight"
  pages: "the special comment is picked up by the parser without needing
  to compile, as long as source code files are visible and browsable by
  the IDE." This is pure in-editor UX -- it writes nothing to disk.

- **(b) Compiler XML-documentation emission (real file output).**
  CONFIRMED locally by direct testing against the installed compiler
  (`C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc32.exe`):
  - `dcc32 --help` lists `--doc = output XML documentation` and
    `-NX<path> = unit .xml output directory`.
  - The `.dproj`/MSBuild property names (confirmed by grepping
    `CodeGear.Delphi.Targets`) are `DCC_OutputXMLDocumentation` (maps to
    `--doc`) and `DCC_XMLOutput` (maps to `-NX<path>`, the output folder).
    In the IDE this is Project > Options > Delphi Compiler > Compiling >
    "Generate XML Documentation" (confirmed via web search of community
    sources describing that exact menu path).
  - **Empirical test performed in this spike:** compiled a throwaway unit
    (`TSpikeThing.Add`, with `<summary>`/`<param>`/`<returns>` comments)
    with `dcc32 --doc -NXxmlout DocSpikeProg.dpr`. It produced one `.xml`
    file per compiled unit in the target folder (the folder must already
    exist -- the compiler does not create it and fails with `F2039` if
    missing). Shape observed:
    ```xml
    <namespace name="DocSpikeUnit" platform="Win32">
      <class name="TSpikeThing" file="DocSpikeUnit.pas" line="7">
        <devnotes><summary>...</summary></devnotes>
        <ancestor name="TObject" namespace="System">...</ancestor>
        <members>
          <function name="Add" visibility="public" file="..." line="13">
            <devnotes>
              <summary>...</summary>
              <param name="A">...</param>
              <param name="B">...</param>
              <returns>...</returns>
            </devnotes>
            <parameters>
              <parameter name="A" type="Integer" />
              <parameter name="B" type="Integer" />
              <retval type="Integer" />
            </parameters>
          </function>
        </members>
      </class>
    </namespace>
    ```
  - It emits **one XML file per compiled unit** (plus one for the
    project/dpr itself listing its uses and top-level vars), a full class
    surface (including every *inherited* ancestor member, e.g. all of
    `TObject`'s methods, whether documented or not) with `<devnotes>` only
    where a `///` comment existed on that declaration.

- **(c) "Documentation Insight" (DocInsight) is a separate, third-party,
  commercial IDE add-on**, historically sold by DevJet Software, for
  browsing/editing/generating Delphi API docs from the same `///` comment
  convention. It is NOT the same thing as Embarcadero's built-in Help
  Insight or the `--doc` XML emission -- it is a plugin that reads/writes
  the same comment syntax but is a distinct product with its own UI and
  its own doc-generation pipeline (HTML/CHM-style output, richer than the
  compiler's raw per-unit XML). This is very likely the source of the
  "DocInsight" name our project's tooling and comment style already use.
  (Confirmed via web search results referencing "Special Offer for
  Documentation Insight" / devjetsoftware.com and community mentions
  distinguishing it from Embarcadero's own Code Insight / Help Insight.)

## 2. What it emits + how it is configured

- Trigger: `.dproj` properties `DCC_OutputXMLDocumentation=true` (enables
  `--doc`) and `DCC_XMLOutput=<folder>` (enables `-NX<folder>`, otherwise
  the compiler errors if `--doc` is set without an output path pointing at
  a real, pre-existing directory). IDE path: Project Options > Delphi
  Compiler > Compiling > "Generate XML Documentation" + an output
  directory field.
- Output: one `.xml` file per source unit compiled (named after the unit),
  written into the configured folder, containing `<devnotes>` (compiler's
  own name for the doc-comment payload) wrapping whatever `<summary>`,
  `<param>`, `<returns>` etc. tags were present in the `///` comment
  immediately preceding the declaration, plus full structural metadata
  (every member, visibility, file/line, inherited ancestry) regardless of
  whether it was documented.
- **Neither property is set in any `.dproj` in this repo** (checked
  `src/cli/drag-lint.dproj`, `src/config/drag-lint-config.dproj`,
  `src/delphi-plugin/dclDragLintWizard.dproj`, and others via grep for
  `DCC_OutputXMLDocumentation`/`DCC_XMLOutput` -- zero hits) -- the feature
  is off by default in a normal project and was never enabled in this
  codebase, on either compiler or IDE side, before this spike.

## 3. Why it underdelivered for the user

Working hypothesis, moderately confirmed by the evidence gathered:

1. **Off by default and easy to miss.** It requires an explicit `.dproj`
   opt-in on both the "generate" flag and a valid output folder; the
   folder is not auto-created (verified: `F2039` fatal error if the target
   directory does not already exist on disk). A user who never explicitly
   enabled it, or created the target folder, gets either nothing or a
   compile error that looks unrelated to documentation.
2. **Name confusion with the third-party "Documentation Insight" tool.**
   The user (and this project's own conventions) call the `///` comment
   discipline "DocInsight," which is the name of a *separate commercial
   plugin* with its own richer doc-generation UI. Someone expecting that
   product's polished output (browsable HTML/CHM docs) from Embarcadero's
   built-in `--doc` switch would be disappointed: the built-in feature
   only emits a raw, verbose, per-unit XML dump (see section 1c) -- not
   consumable documentation on its own; it needs a further XSLT/tool step
   to become anything human-readable, which RAD Studio does not ship.
3. **Known compiler-side flakiness.** Community reports (e.g. a
   Delphi-PRAXiS thread titled roughly "Is XML Documentation in 10.4 105%
   broken?") describe the feature behaving inconsistently across IDE
   versions, and older Borland-era forum threads ("Help Insight w/ XML
   Documentation not working") describe comment placement rules (e.g. the
   `<summary>` must be directly above the *interface* declaration, not an
   implementation-section duplicate) that silently produce empty output
   when violated. *(Unconfirmed in detail -- these are community forum
   reports found via search, not independently reproduced in this spike;
   flagged as a plausible contributing factor, not a verified root cause.)*
4. **It was never something to "collect meaningful results" from in the
   sense the user meant** -- Help Insight tooltips (section 1a) require no
   file output at all, so if the user was looking at IDE hover text and
   expecting a doc folder to also appear, that expectation conflates the
   two independent features.

## 4. Recommendation for drag-lint

**Supersede, do not feed/augment**, at least for now.

Reasoning:
- The built-in `--doc`/`DCC_XMLOutput` emission is a low-level, verbose,
  per-unit structural dump (full inherited-member ancestry, no filtering,
  no cross-reference/caller information) that is not itself a usable
  documentation artifact -- it would need a further rendering step RAD
  Studio does not provide. drag-lint's `document`/`doc-drift` workflow
  (index-driven, facts-enriched, managed-region merge) is already a
  strictly more useful pipeline: it knows callers/callees/usages that the
  compiler's XML has no notion of, and it writes back into the same `///`
  comments the compiler would read, rather than a side-channel XML file.
- Feeding into it (emitting compiler-compatible XML) would mean investing
  in a format that is (a) not required for Help Insight tooltips at all
  (those read `///` comments directly, independent of this pipeline), and
  (b) not obviously consumed by anything else in this project's toolchain
  -- there is no evidence any part of this codebase or its build already
  relies on `DCC_OutputXMLDocumentation` output, so there is nothing
  existing to "augment."
- The one scenario where augmenting would matter is if a *future* consumer
  wants the compiler's own per-unit XML specifically (e.g. some external
  doc-site generator that only understands this exact schema). That is
  speculative today; if it materializes, drag-lint's index already has
  strictly richer facts than that XML shape, so the better integration
  point would be a drag-lint export command that *emits* this same
  `<namespace>/<class>/<devnotes>` XML shape from its own index (cheap,
  since the shape is now documented in section 1) rather than relying on
  `dcc32 --doc` output as an input.
- Net: no dependency on the built-in feature is needed or recommended.
  drag-lint's own `///`-comment generation/repair (already shipped) is the
  complete, better replacement for what a user hoping for "collected
  documentation" was actually looking for.

## Sources consulted

- Local, empirically verified in this spike:
  - `dcc32 --help` output (Delphi 13 / RAD Studio 37.0 install) --
    confirmed `--doc` and `-NX<path>` switches.
  - `C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\CodeGear.Delphi.Targets`
    -- confirmed MSBuild property names `DCC_OutputXMLDocumentation` and
    `DCC_XMLOutput`.
  - Direct compile of a throwaway test unit with `--doc -NX<dir>` --
    confirmed the emitted XML shape (section 1b) and the `F2039`
    missing-directory failure mode.
  - Grep of this repo's `.dproj` files -- confirmed neither property is
    set anywhere in this codebase.
- Web search (docwiki MCP server was unavailable/unresponsive during this
  spike, so Embarcadero docwiki pages were reached indirectly via search
  snippets rather than full-page fetch, which returned HTTP 403):
  - "XML Documentation for Delphi Code" (docwiki, RADStudio/Athens) --
    describes the `--doc` feature and IDE menu path.
  - "XML Documentation Comments" (docwiki, RADStudio/Athens) -- describes
    `///` comment tags and confirms Help Insight parses comments directly
    without compiling.
  - "Help Insight" (docwiki) -- tooltip feature description.
  - Delphi-PRAXiS forum thread on XML Documentation reliability in 10.4
    (unconfirmed detail, flagged as community report only).
  - Delphi-PRAXiS "Special Offer for Documentation Insight" and related
    search results identifying DevJet Software's "Documentation Insight"
    as a distinct third-party commercial product.

Unconfirmed items (explicitly flagged above): the exact root cause(s)
behind community "XML Documentation broken" reports (section 3, point 3)
were not independently reproduced -- taken from forum snippets only.
