{ Reads a symbol's DECLARING SOURCE TEXT at query time.

  WHY THIS UNIT EXISTS. Declaration clauses -- `default clWindow`, `stored
  IsFontStored`, `nodefault`, `read FColor write SetColor` -- are semantics the
  extractor does not model. The stored `signature` for
  Vcl.StdCtrls.TCustomEdit.AutoSize is exactly `Boolean`; the `default True` is
  nowhere in the database. Indexing those clauses would be an EXTRACTION change
  and would cost a DRAGLINT_EXTRACTOR_VERSION bump -- hours of re-parsing across
  every database -- so the answer is recovered by re-reading the declaring line
  instead.

  BuildPropTree has done exactly that since the `default` work, with a private
  per-file line cache. `query find --decl-contains` needs the same reader, and a
  second copy of it is the shape this repo has been bitten by before: the T3j
  defect was a third copy of a doc-region window that omitted a guard while a
  comment claimed it matched. So the reader has ONE declaration and both callers
  share it.

  The cache is per-FILE, not per-symbol, because the caller's access pattern is
  many symbols from few files. It is query-scoped: create one, ask it, free it.
  Nothing here writes to the store, so a read-only handle (--no-write-back) is
  unaffected. }
unit DRagLint.Core.DeclText;

interface

uses
  System.Generics.Collections,
  DRagLint.Core.Model, DRagLint.Core.Interfaces;

type
  /// <summary>Recovers the declaring source text of a symbol, caching each
  /// file's lines so a sweep over many symbols reads every file once.</summary>
  /// <remarks>
  /// Query-scoped and single-threaded. Borrows the store; owns only
  /// its cache. Never raises: an unreadable file answers '' for every symbol
  /// in it, and '' means UNKNOWN -- never "the clause is absent".
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.QueryFindByDecl (DRagLint.CLI.pas), DRagLint.Convert.PropTree.BuildPropTree (DRagLint.Convert.PropTree.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Convert.PropTree</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDeclTextReader = class
  strict private
    FStore: ISymbolStore                     ;
    FLines: TDictionary<Int64, TArray<string>>;
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: nil;
    /// TFile.ReadAllLines(Path, TEncoding.ANSI).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Core.DeclText.TDeclTextReader.TextOf (DRagLint.Core.DeclText.pas)</para>
    /// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.GetFilePath</para>
    /// <para>Reads: FLines, FStore</para>
    /// <para>Touches: file system</para>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
    /// <seealso cref="DRagLint.Core.DeclText.TDeclTextReader.Create"/>
    /// <seealso cref="DRagLint.Core.DeclText.TDeclTextReader.Destroy"/>
    /// <seealso cref="DRagLint.Core.DeclText.TDeclTextReader.TextOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function LinesOf(AFileId: Int64): TArray<string>;
  public
    /// <summary>Binds the reader to a store. AStore is borrowed, not owned.</summary>
    /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.QueryFindByDecl (DRagLint.CLI.pas), DRagLint.Convert.PropTree.BuildPropTree (DRagLint.Convert.PropTree.pas)</para>
    /// <para>constructor</para>
    /// <para>Writes: FStore, FLines</para>
    /// <seealso cref="DRagLint.Core.DeclText.TDeclTextReader.Destroy"/>
    /// <seealso cref="DRagLint.Core.DeclText.TDeclTextReader.LinesOf"/>
    /// <seealso cref="DRagLint.Core.DeclText.TDeclTextReader.TextOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(const AStore: ISymbolStore);
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FLines</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Core.DeclText.TDeclTextReader.Create"/>
    /// <seealso cref="DRagLint.Core.DeclText.TDeclTextReader.LinesOf"/>
    /// <seealso cref="DRagLint.Core.DeclText.TDeclTextReader.TextOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;

    /// <summary>ASym's declaring source, StartLine..EndLine joined with a
    /// single space and trimmed.</summary>
    /// <param name="ASym">The symbol whose declaration is wanted.</param>
    /// <returns>The declaration text, or '' when the file is unreadable, the
    /// symbol has no file, or the line range is nonsense.</returns>
    /// <remarks>
    /// '' is UNKNOWN. A caller must never read it as evidence that a
    /// clause is absent -- that conflation is what made a bare redeclaration
    /// ('property AutoSize;') report as having no default.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.QueryFindByDecl (DRagLint.CLI.pas), DRagLint.Convert.PropTree.BuildPropTree.DeclTextOf (DRagLint.Convert.PropTree.pas) ?</para>
    /// <para>Calls: DRagLint.Core.DeclText.TDeclTextReader.LinesOf, Trim</para>
    /// <para>Returns: ''; Trim(string.Join(' ', Span))</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Core.DeclText.TDeclTextReader.LinesOf"/>
    /// <seealso cref="DRagLint.Core.DeclText.TDeclTextReader.Create"/>
    /// <seealso cref="DRagLint.Core.DeclText.TDeclTextReader.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function TextOf(const ASym: TSymbol): string;
  end;

implementation

uses
  System.SysUtils, System.IOUtils;

constructor TDeclTextReader.Create(const AStore: ISymbolStore);
begin
  inherited Create;
  FStore:= AStore;
  FLines:= TDictionary<Int64, TArray<string>>.Create;
end;

destructor TDeclTextReader.Destroy;
begin
  FLines.Free;
  inherited;
end;

function TDeclTextReader.LinesOf(AFileId: Int64): TArray<string>;
var
  Path: string;
begin
  if FLines.TryGetValue(AFileId, Result) then Exit;
  Result:= nil;
  if FStore <> nil then
  begin
    Path:= FStore.GetFilePath(AFileId);
    if (Path <> '') and TFile.Exists(Path) then
      try
        Result:= TFile.ReadAllLines(Path, TEncoding.ANSI);
      except // dl:ok try-except-swallowed@d7c1 -- a pure query with no report channel; '' already means "unknown" to every caller
        on E: Exception do
          { A source file that exists but cannot be READ -- locked by the IDE,
            permissions, a bad encoding -- must degrade the symbols in THAT
            file to "unknown" and must not abort a query that answers many
            other questions needing no file at all. There is nothing to log
            to. The effect is visible as '', which callers already treat as
            "do not conclude anything", so the failure is conservative rather
            than silent. }
          Result:= nil;
      end;
  end;
  // Cached even when nil, so an unreadable file is attempted ONCE per query
  // rather than once per symbol declared in it.
  FLines.Add(AFileId, Result);
end;

function TDeclTextReader.TextOf(const ASym: TSymbol): string;
var
  Lines: TArray<string>;
  Span : TArray<string>;
  I, Lo, Hi: Integer   ;
begin
  Result:= '';
  if ASym.FileId <= 0 then Exit;
  Lines:= LinesOf(ASym.FileId);
  if Length(Lines) = 0 then Exit;

  Lo:= ASym.StartLine;
  Hi:= ASym.EndLine;
  if Hi < Lo then Hi:= Lo;
  if (Lo < 1) or (Lo > Length(Lines)) then Exit;
  if Hi > Length(Lines) then Hi:= Length(Lines);

  SetLength(Span, Hi - Lo + 1);
  for I:= Lo to Hi do
    Span[I - Lo]:= Lines[I - 1];
  Result:= Trim(string.Join(' ', Span));
end;

end.
