unit DRagLint.Query.HoverModel;

{ Assembles the STRUCTURED hover model -- the shape `hover --format json` emits
  and the IDE's colored popup consumes -- from an indexed symbol.

  WHY THIS UNIT EXISTS. The assembly (read the implementation span, mine the
  Result:=/Exit() returns with their source lines, resolve the unit file, build
  the model, then attach the Phase-2 doc facts) lived inline in
  DRagLint.CLI.DoHover, so the only way to obtain a model was to SPAWN
  drag-lint.exe. The IDE hover did exactly that, on the main thread, per hover,
  with the FULL database list -- which is what cold-opened the ~1.4 GB library
  index every time a tooltip appeared.

  Serving the popup over the already-warm LSP needed the same assembly in
  process. Copying it would have created a second definition of what a hover
  says about a symbol, and the two would have drifted the first time either was
  touched -- so it moved here, and BOTH surfaces now call it.

  THE FACTS ARE PART OF THE MODEL, NOT A GARNISH. TDocFactsBuilder.Build plus
  TDocRegions.FormatPhase2FactLines is the identical pair `document` uses to
  write the managed doc block. Routing every surface through it is the
  doc/hover consistency lock: the popup cannot claim something the committed
  documentation does not. }

interface

uses
  DRagLint.Core  .Model     ,
  DRagLint.Core  .Interfaces,
  DRagLint.Symbol.Describe  ,
  DRagLint.Hover .Renderer  ;

type
  /// <summary>Everything a hover surface needs about one symbol.</summary>
  /// <remarks>
  /// Returned as a record rather than a model plus out-params because
  /// the three parts are produced by one pass and are only correct together:
  /// ReturnRhs is what Model's return facts were built FROM, so a caller that
  /// rendered markdown from a separately mined list could contradict the JSON
  /// its own model produces.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoHover (DRagLint.CLI.pas), DRagLint.LSP.Server.TLSPServer.HandleHoverBundle (DRagLint.LSP.Server.pas), declaration (DRagLint.Query.HoverModel.pas), DRagLint.Query.HoverModel.AssembleHover (DRagLint.Query.HoverModel.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.LSP.Server, DRagLint.Query.HoverModel</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THoverAssembly = record
    Model    : THoverModel   ;
    /// <summary>Formatted Phase-2 fact lines; empty when the symbol has none.</summary>
    FactLines: TArray<string>;
    /// <summary>The mined Result:=/Exit() expressions, in first-seen order --
    /// what RenderHoverMarkdown takes as its AReturnRhs.</summary>
    ReturnRhs: TArray<string>;
  end;

/// <summary>Assembles the structured hover model for one indexed symbol,
/// together with the fact lines and mined returns that render with it.</summary>
/// <param name="AStore">The store that OWNS <paramref name="ASym"/>. Passing a
/// different store yields facts about a same-named symbol elsewhere, which is
/// the exact failure the hover framework-scope fix was about.</param>
/// <param name="ASym">The resolved symbol; its Id must be from AStore.</param>
/// <param name="AWithFacts">False leaves FactLines empty and SKIPS the Phase-2
/// facts build entirely. Only the surfaces that render facts should pay for it
/// -- `hover --format plain` never has, because the covered-by BFS inside it is
/// the expensive part of assembling a hover.</param>
/// <returns>A populated assembly; a zeroed one when AStore is nil.</returns>
/// <remarks>
/// Reads the symbol's implementation span through TLiveDocuments, so
/// an editor's UNSAVED buffer is mined when one is registered and the file on
/// disk otherwise. The disk path is byte-for-byte the read the CLI has always
/// done (ANSI), which is what lets the CLI keep emitting identical JSON.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoHover (DRagLint.CLI.pas), DRagLint.LSP.Server.TLSPServer.HandleHoverBundle (DRagLint.LSP.Server.pas)</para>
/// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolDoc, DRagLint.Core.LiveDocs.TLiveDocuments.Readable, DRagLint.Core.LiveDocs.TLiveDocuments.ReadLines, DRagLint.Doc.Facts.TDocFactsBuilder.Build, DRagLint.Doc.Regions.TDocRegions.FormatPhase2FactLines, DRagLint.Hover.Renderer.BuildHoverModel, DRagLint.Hover.Returns.MineReturnExpressionsEx, DRagLint.Symbol.Describe.DescribeTypeKind, ExtractFileName</para>
/// <para>Returns: Default(THoverAssembly)</para>
/// <para>Complexity: 13 (cyclomatic, outer body), 72 lines (full implementation)</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolDoc"/>
/// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.Readable"/>
/// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.ReadLines"/>
/// <seealso cref="DRagLint.Doc.Facts.TDocFactsBuilder.Build"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function AssembleHover(const AStore: ISymbolStore; const ASym: TSymbol;
  AWithFacts: Boolean = True): THoverAssembly;

implementation

uses
  System.SysUtils         ,
  DRagLint.Core .LiveDocs ,
  DRagLint.Hover.Returns  ,
  DRagLint.Doc  .Facts    ,
  DRagLint.Doc  .Regions  ,
  DRagLint.Index.Manifest ;

function AssembleHover(const AStore: ISymbolStore; const ASym: TSymbol;
  AWithFacts: Boolean): THoverAssembly;
var
  Doc     : TParsedDoc      ;
  Rhs     : TArray<string>  ;
  RhsLines: TArray<Integer> ;
  UnitFile: string          ;
begin
  Result:= Default(THoverAssembly);
  if AStore = nil then Exit;

  { No doc comment is not fatal: the renderer still shows the qualified name and
    an IDE-style Parameters block parsed from the signature. }
  Doc:= AStore.GetSymbolDoc(ASym.Id);

  SetLength(Rhs     , 0);
  SetLength(RhsLines, 0);
  if (ASym.ImplStartLine > 0) and (ASym.ImplEndLine >= ASym.ImplStartLine) then
  begin
    var Path: string:= AStore.GetFilePath(ASym.FileId);
    if (Path <> '') and TLiveDocuments.Readable(Path) then
    begin
      var AllLines: TArray<string>:= TLiveDocuments.ReadLines(Path);
      var Lo: Integer:= ASym.ImplStartLine - 1;   { 1-based -> 0-based }
      var Hi: Integer:= ASym.ImplEndLine   - 1;
      if Lo < 0 then Lo:= 0;
      if Hi > High(AllLines) then Hi:= High(AllLines);
      if Hi >= Lo then   { a stale or invalid span yields no returns, not a crash }
      begin
        var Body: TArray<string>;
        SetLength(Body, Hi - Lo + 1);
        for var k:= Lo to Hi do Body[k - Lo]:= AllLines[k];

        { Mine WITH first-seen line offsets so the popup can jump to each
          return's source line. Body[0] is source line ImplStartLine, so the
          absolute 1-based line is ImplStartLine + offset. }
        var Mined: TArray<TReturnMined>:= MineReturnExpressionsEx(Body, ASym.QualifiedName);
        SetLength(Rhs     , Length(Mined));
        SetLength(RhsLines, Length(Mined));
        for var mi:= 0 to High(Mined) do
        begin
          Rhs     [mi]:= Mined[mi].Expr;
          RhsLines[mi]:= ASym.ImplStartLine + Mined[mi].LineOffset;
        end;
      end;
    end;
  end;

  UnitFile        := ExtractFileName(AStore.GetFilePath(ASym.FileId));

  { A TYPE carries nothing in Signature -- the parser has no single line to
    put there -- so the hover showed a bare `enum FileLockInfo.TRmAppType`
    while Ctrl-Space on the same type listed its members. Reported from a
    live IDE 2026-08-24. DescribeTypeKind is the ONE describer the
    completion item builder also calls; see its header for why it does not
    live in either surface. Applied only when the symbol says nothing for
    itself, so a real signature is never overwritten. }
  var Described: TSymbol:= ASym;
  if Described.Signature = '' then Described.Signature:= DescribeTypeKind(Described, AStore);

  Result.Model    := BuildHoverModel(Described, Doc, UnitFile, Rhs, RhsLines);
  Result.ReturnRhs:= Rhs;

  { TDocFactsBuilder.Build + TDocRegions.FormatPhase2FactLines is the identical
    pair `document` uses to write the managed doc block. Going through it is the
    doc/hover consistency lock: the popup cannot claim a fact the committed
    documentation does not. }
  if AWithFacts then
  begin
    var Facts: TDocFacts:= TDocFactsBuilder.Build(AStore, ASym);
    Result.FactLines:= TDocRegions.FormatPhase2FactLines(Facts, LoadDocComplexityMin);
  end;
end; // function

end.
