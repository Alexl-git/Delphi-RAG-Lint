unit DRagLint.CLI.Hover;

// ---------------------------------------------------------------------------
// The hover verb (md / plain / json) and the hidden WCAG contrast self-test.
// Moved verbatim out of DRagLint.CLI (lane v1511 SPLIT, T07).
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>drag-lint hover --qname Foo.Bar [--db path] [--format md|plain|json]: the hover card of one symbol.</summary>
/// <param name="AArgs">--qname (required), --db, --format.</param>
/// <returns>0 when rendered; 2 on a usage error or a missing --db.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Common.ExplicitDbsExist, DRagLint.CLI.Common.OpenReadOnlyStore, DRagLint.CLI.Common.ReportNotFoundFor, DRagLint.CLI.Common.StaleDbRefusesRun, DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolDoc, DRagLint.Hover.Renderer.RenderHoverJson/2, DRagLint.Hover.Renderer.RenderHoverMarkdown, DRagLint.Hover.Renderer.RenderHoverPlain (+6 more)</para>
/// <para>Returns: 2; 1; 0</para>
/// <para>Complexity: 23 (cyclomatic, outer body), 113 lines (full implementation)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.ExplicitDbsExist"/>
/// <seealso cref="DRagLint.CLI.Common.OpenReadOnlyStore"/>
/// <seealso cref="DRagLint.CLI.Common.ReportNotFoundFor"/>
/// <seealso cref="DRagLint.CLI.Common.StaleDbRefusesRun"/>
/// <seealso cref="DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoHover(const AArgs: TArgs): Integer;

/// <summary>Hidden self-test verb of the WCAG contrast unit: prints known-answer ratios (BLACK_ON_WHITE, SAME, DARKFAIL, FIXED) for the test script to assert; no --db, no fixture.</summary>
/// <returns>Always 0 (the script judges the printed values).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Hover.Contrast.ContrastRatio, DRagLint.Hover.Contrast.EnsureReadable, Format, Writeln</para>
/// <para>Returns: 0</para>
/// <seealso cref="DRagLint.Hover.Contrast.ContrastRatio"/>
/// <seealso cref="DRagLint.Hover.Contrast.EnsureReadable"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoContrastSelfTest: Integer;

implementation

uses
  DRagLint.Core.Model, DRagLint.CLI.ConsumerDbs, Winapi.Windows, System.SysUtils, System.IOUtils,
  System.NetEncoding, System.DateUtils, System.Generics.Collections, FireDAC.Stan.Async, FireDAC.DApt,
  DRagLint.Core.Interfaces, Vcl.Graphics, DRagLint.Hover.Renderer, DRagLint.Hover.Contrast,
  DRagLint.Query.HoverModel, System.Diagnostics, System.RegularExpressions, DRagLint.Doc.Facts;

// --- hover ------------------------------------------------------------------

// v0.16: drag-lint hover --qname <Foo.Bar> [--db <path>] [--format md|plain|json]
// Looks up the first symbol matching the qualified name, retrieves its doc
// comment from symbol_docs, and renders it in the requested format.

// RenderHover* functions are now in DRagLint.Hover.Renderer (shared with LSP).
// These local wrappers forward to the shared unit so existing callers
// (DoHover below) continue to compile without change.

function RenderHoverPlain(const ASym: TSymbol; const ADoc: TParsedDoc): string;
begin
  Result:= DRagLint.Hover.Renderer.RenderHoverPlain(ASym, ADoc);
end;

function RenderHoverMarkdown(const ASym: TSymbol; const ADoc: TParsedDoc): string;
begin
  Result:= DRagLint.Hover.Renderer.RenderHoverMarkdown(ASym, ADoc);
end;

function RenderHoverJson(const ASym: TSymbol; const ADoc: TParsedDoc): string;
begin
  Result:= DRagLint.Hover.Renderer.RenderHoverJson(ASym, ADoc);
end;

function DoHover(const AArgs: TArgs): Integer;
var
  Store: ISymbolStore   ;
  Syms : TArray<TSymbol>;
  Doc  : TParsedDoc     ;
  Fmt  : string         ;
  Dbs  : TArray<string> ;
  Db   : string         ;
  UsedDb: string        ;
begin
  if not ExplicitDbsExist(AArgs, 'hover') then Exit(2);
  if AArgs.QName = '' then
  begin
    Writeln('Usage: drag-lint hover --qname <Foo.Bar> [--db <path>] ' + '[--format md|plain|json]');
    Exit(2);
  end;

  // v0.94.1 BUGFIX: hover must search ALL --db paths, not just one. The IDE (and
  // manifest resolution) pass several --db values -- e.g. a project index, a SQL
  // index, and a platform library index. The old code used AArgs.DbPath, which
  // the parser THEN set to the LAST --db, so hovering a symbol that lives in an
  // EARLIER db returned "No symbol matched" and the IDE silently fell back to the
  // plain string popup. Now: iterate every resolved db and use the FIRST one that
  // contains the qname (mirrors how query find-callers walks multiple dbs).
  // (ParseArgs now sets DbPath to the FIRST --db -- owner ruling 2026-08-25 --
  // which would have masked this particular symptom for the common ordering.
  // Walking every db is still the right answer: the qname may live in any of
  // them, and "not in the primary" is not "nowhere".)
  Dbs:= ResolveConsumerDbs(AArgs);
  if Length(Dbs) = 0 then begin Writeln('ERROR: no drag-lint index found. Pass --db <file.sqlite> or build the index first.'); Exit(2); end;

  Store := nil;
  UsedDb:= '';
  SetLength(Syms, 0);
  for Db in Dbs do
  begin
    if not TFile.Exists(Db) then Continue;
    var RoOk: Boolean;
    { Read-only: a re-published property's type is stored by index (the
      prop-types stage), so hover never needs to write. }
    Store:= OpenReadOnlyStore(Db, RoOk);
    if not RoOk then
    begin
      if StaleDbRefusesRun(AArgs, 'hover', Db) then Exit(2);
      Continue; { manifest-resolved: stale DB reported, scan the rest }
    end;
    Syms:= Store.FindSymbolsByQualifiedName(AArgs.QName);
    if Length(Syms) > 0 then begin UsedDb:= Db; Break; end;
    Store:= nil; { release before trying the next db }
  end;
  if (Length(Syms) = 0) or (Store = nil) then
  begin
    ReportNotFoundFor(SameText(AArgs.Format, 'json'), System.SysUtils.Format('No symbol matched qname: %s', [AArgs.QName]));
    Exit(1);
  end;

  Doc:= Store.GetSymbolDoc(Syms[0].Id);
  { v0.43: no doc comment is no longer fatal -- the renderer still shows the
    qualified name + an IDE-style Parameters block parsed from the signature,
    which is exactly what the LSP hover does. }

  { v(hover bundle): the assembly -- mine the Result:=/Exit() returns with their
    source lines, resolve the unit file, build the model, attach the Phase-2
    facts -- MOVED to DRagLint.Query.HoverModel so the LSP's `draglint/hoverBundle`
    answers from the same code. It used to live here, which is why the IDE had
    to SPAWN this exe to get a model at all. }
  Fmt:= LowerCase(AArgs.Format);
  if Fmt = '' then Fmt:= 'plain';

  { Wave 149 LX (UP 149): the other --db stores are extra stores for the facts, so the card's
    'Used in:' names a use that lives only in another project's DB, as `document --db A --db B`
    writes it. Only for the formats that render facts; a platform library (library-*.sqlite) is
    never an extra (its name fan-out is the 2026-08-13 junk-facts channel, paid per hover). }
  var HovExtra: TArray<ISymbolStore>:= nil;
  if (Fmt = 'json') or (Fmt = 'md') then
    for var ExDb: string in Dbs do
    begin
      if SameText(ExDb, UsedDb) or (not TFile.Exists(ExDb)) or LowerCase(ExtractFileName(ExDb)).StartsWith('library-') then Continue;
      var ExOk: Boolean;
      var ExSt: ISymbolStore:= OpenReadOnlyStore(ExDb, ExOk);
      if ExOk and (ExSt <> nil) then HovExtra:= HovExtra + [ExSt];
    end;
  var AsmWatch: TStopwatch:= TStopwatch.StartNew;
  var Asm_ : THoverAssembly:= AssembleHover(Store, Syms[0], (Fmt = 'json') or (Fmt = 'md'), HovExtra);
  var AsmMs: Int64:= AsmWatch.ElapsedMilliseconds;
  var Rhs  : TArray<string>:= Asm_.ReturnRhs;
  var Model: THoverModel   := Asm_.Model    ;

  // v(ADP2 T9 + hover facts fix): thread the SAME Phase-2 analysis facts
  // `document` renders into BOTH the hover markdown AND the structured json --
  // via TDocFactsBuilder.Build (the identical facts assembly `document` uses)
  // and TDocRegions.FormatPhase2FactLines (the SHARED formatter every surface
  // calls), so hover-json / hover-md / the managed doc block can never show
  // different facts for the same symbol (the doc/hover consistency lock).
  // Previously ONLY the md path built these, so `hover --format json` -- which
  // is exactly what the IDE's colored popup consumes -- omitted facts entirely
  // (the user's "we were supposed to show more info; where is it?"). Computed
  // only for the two formats that render facts (plain skips the covered-by BFS).
  if (Fmt = 'json') or (Fmt = 'md') then
  begin
    if Fmt = 'json' then Write(DRagLint.Hover.Renderer.RenderHoverJson(Model, Asm_.FactLines))
    else
    begin
      { 150 LX2: the md card names the callers, as the doc block does (json stays the popup's model). }
      var MdFacts: TArray<string>:= Asm_.FactLines;
      if Asm_.CalledFromLine <> '' then MdFacts:= [Asm_.CalledFromLine] + MdFacts;
      Write(DRagLint.Hover.Renderer.RenderHoverMarkdown(Syms[0], Doc, Rhs, MdFacts, Asm_.DeclaredType));
    end;
  end
  else
  begin
    Write(DRagLint.Hover.Renderer.RenderHoverPlain(Syms[0], Doc, Asm_.DeclaredType));
    for var ImplLine in Asm_.ImplLines do Writeln(ImplLine); { C22: plain skips FactLines, so the answering-methods line is printed here }
  end;
  { v152 HOVERCAP: DRAGLINT_PROFILE prints where the hover's time went -- the whole assembly, the check-init
    'Set by:' solve inside it, and the facts breakdown (its 'used-in directions' line printed only under
    lint doc-drift before, which hover never runs). stderr, so --format json stays one object.
    v152 HOVERCACHE: printed after the card, with 'total' = assembly + render, the span the hover cap covers. }
  if GetEnvironmentVariable('DRAGLINT_PROFILE') <> '' then
  begin
    var SetByMs: string:= TRegEx.Match(Asm_.Model.SetByJson, '"ms":(\d+)').Groups[1].Value;
    Writeln(ErrOutput, System.SysUtils.Format('  HOVER PROFILE assemble %d ms | set-by (check-init) %s ms | total %d ms',
      [AsmMs, if SetByMs = '' then '--' else SetByMs, AsmWatch.ElapsedMilliseconds]));
    Writeln(ErrOutput, DocFactsBuildProfile);
  end;
  Result:= 0;
end; // function

// v0.95 Task 1: hidden self-test verb for the WCAG contrast unit (no --db,
// no fixture -- just known-answer ratios so the .ps1 can assert without an index).
function DoContrastSelfTest: Integer;
begin
  // Known-answer lines: NAME=<ratio to 2dp> and READABLE=<hex of EnsureReadable>.
  Writeln(Format('BLACK_ON_WHITE=%.2f', [ContrastRatio(clBlack, clWhite)]));      // 21.00
  Writeln(Format('SAME=%.2f',           [ContrastRatio(clRed, clRed)]));          // 1.00
  // #0B57D0 keyword-blue on a dark (#1E1E1E) bg fails 4.5; EnsureReadable fixes it.
  Writeln(Format('DARKFAIL=%.2f',       [ContrastRatio($00D0570B, $001E1E1E)]));  // < 4.5
  Writeln(Format('FIXED=%.2f',
    [ContrastRatio(EnsureReadable($00D0570B, $001E1E1E, 4.5), $001E1E1E)]));       // >= 4.5
  Result:= 0;
end;

end.
