unit DRagLint.Doc.Document;

interface

uses
  System.SysUtils,
  DRagLint.Core.Model, DRagLint.Core.Interfaces,
  DRagLint.Refactor.TextEdit;

type
  TDocumentAction = (daCreated, daExtended, daUnchanged, daNotFound);

  TDocumentResult = record
    Action  : TDocumentAction   ;
    QName   : string            ;
    FilePath: string            ;
    Line    : Integer           ;
    Edits   : TArray<TTextEdit> ;
  end;

  TDocumenter = class
  public
    /// <summary>Resolves AQName in the index and computes the DocInsight
    /// comment edits for its declaration. Reads the source file (ANSI) and the
    /// existing doc-comment above the decl, derives params + return from the
    /// signature, builds index-grounded facts, and merges into a managed-region
    /// comment. Action is daCreated (no prior comment), daExtended (prior
    /// comment changed), daUnchanged (identical -- no edits), or daNotFound
    /// (symbol/file missing). Edits are dry-run data; the caller applies them.</summary>
    /// <param name="AStore">Open symbol store to query; not owned. Must not be nil.</param>
    /// <param name="AQName">Fully qualified symbol name, e.g. Unit.TType.Method.</param>
    /// <returns>The classified action plus file/line and the computed edits.</returns>
    /// <remarks>Does not write files; TTextEditApplier.Apply performs any I/O.</remarks>
    class function BuildFor(const AStore: ISymbolStore; const AQName: string): TDocumentResult;
  end;

implementation

uses
  System.IOUtils, System.Generics.Collections,
  DRagLint.Doc.Facts, DRagLint.Doc.Regions,
  DRagLint.Parser.DocComments, DRagLint.Refactor.DocStub;

// Returns the TDocCommentRegion immediately preceding ASymStartLine (EndLine in
// [SymStartLine - 1 - AllowGap, SymStartLine - 1]). When ACaptureLoose is False,
// loose regions are skipped. Sentinel: Result.Kind = TDocCommentKind(-1) means
// none found. Mirrors DRagLint.Core.Indexer.FindDocRegionAbove (which is
// implementation-only there); kept local so this unit does not pull in Indexer.
function FindDocRegionAbove(ADocRegions: System.Generics.Collections.TList<TDocCommentRegion>;
  ASymStartLine: Integer; AAllowGap: Integer; ACaptureLoose: Boolean): TDocCommentRegion;
var
  I      : Integer          ;
  Best   : TDocCommentRegion;
  HasBest: Boolean          ;
begin
  HasBest:= False;
  // ADocRegions is sorted by StartLine ascending.
  for I:= 0 to ADocRegions.Count - 1 do
  begin
    if (not ACaptureLoose) and (ADocRegions[I].Kind in [dckLooseLine, dckLooseBlock]) then Continue;
    if (ADocRegions[I].EndLine >= ASymStartLine - 1 - AAllowGap) and (ADocRegions[I].EndLine <= ASymStartLine - 1) then
    begin
      Best:= ADocRegions[I];
      HasBest:= True;
    end;
    if ADocRegions[I].StartLine > ASymStartLine then Break;
  end;
  if HasBest then Result:= Best
  else
  begin
    FillChar(Result, SizeOf(Result), 0);
    Result.Kind:= TDocCommentKind(-1);
  end;
end;

class function TDocumenter.BuildFor(const AStore: ISymbolStore; const AQName: string): TDocumentResult;
var
  Syms     : TArray<TSymbol>                                   ;
  Sym      : TSymbol                                           ;
  Path     : string                                            ;
  Src      : string                                            ;
  Regions  : System.Generics.Collections.TList<TDocCommentRegion>;
  Region   : TDocCommentRegion                                 ;
  Existing : TParsedDoc                                        ;
  SigParams: TArray<string>                                    ;
  HasRet   : Boolean                                           ;
  Facts    : TDocFacts                                         ;
  Merged   : string                                            ;
  Prefix   : string                                            ;
  Sig      : string                                            ;
  E        : TTextEdit                                         ;
begin
  Result:= Default(TDocumentResult);
  Result.QName := AQName;
  Result.Action:= daNotFound;

  Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit;
  Sym:= Syms[0];

  Path:= AStore.GetFilePath(Sym.FileId);
  Result.FilePath:= Path;
  Result.Line    := Sym.StartLine;
  if (Path = '') or (not TFile.Exists(Path)) then Exit;

  Src:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(Path));

  // Existing doc-comment above the declaration (allow a 1-line gap; skip loose).
  // FindDocRegionAbove signals "not found" with Kind = TDocCommentKind(-1).
  Existing:= Default(TParsedDoc);
  Regions := TDocCommentScanner.Scan(Src);
  try
    Region:= FindDocRegionAbove(Regions, Sym.StartLine, 1, False);
    if Region.Kind <> TDocCommentKind(-1) then
      Existing:= TDocCommentParser.Dispatch(Region);
  finally
    Regions.Free;
  end;

  // Signature-derived params.
  Sig      := Trim(Sym.Signature);
  SigParams:= ParseParamNames(ExtractParamList(Sig));

  Facts := TDocFactsBuilder.Build(AStore, Sym);

  // Has a return value? The indexed Signature holds only '(params): RetType'
  // (no leading 'function' keyword), so SignatureHasReturn misses it, and class
  // functions carry kind skMethod (not skFunction). Facts.ReturnType is the
  // index-grounded truth -- the type text after the trailing ':', '' for a
  // procedure -- so use it first; keep the signature/kind checks as a fallback.
  HasRet := (Facts.ReturnType <> '')
            or SignatureHasReturn(Sig)
            or (Sym.Kind in [skFunction, skConstructor]);

  Prefix:= '/// ';
  Merged:= TDocRegions.MergeComment(Existing, SigParams, Facts, HasRet, Prefix);

  if Existing.HasContent then
  begin
    // Idempotency: a re-run on an already-current comment makes no edit.
    if SameText(Trim(Existing.RawBlock), Trim(Merged)) then
    begin
      Result.Action:= daUnchanged;
      Exit;
    end;
    // Replace the old comment span. Emit the delete over [StartLine, EndLine],
    // then an insert of the merged comment AFTER (StartLine - 1) so it lands at
    // the same spot. The applier sorts back-to-front by top-line, so the delete
    // (key = its EndLine, the larger) is processed before the insert (key =
    // StartLine - 1), keeping both line ranges valid against the original text.
    E:= Default(TTextEdit);
    E.FilePath:= Path;
    E.Kind    := tekDeleteLines;
    E.Line    := Existing.StartLine;
    E.EndLine := Existing.EndLine;
    Result.Edits:= Result.Edits + [E];

    E:= Default(TTextEdit);
    E.FilePath:= Path;
    E.Kind    := tekInsertLines;
    E.Line    := Existing.StartLine - 1; // insert AFTER (StartLine-1) => at StartLine
    E.Text    := Merged;
    Result.Edits:= Result.Edits + [E];

    Result.Action:= daExtended;
  end
  else
  begin
    // No prior comment: one insert above the declaration.
    E:= Default(TTextEdit);
    E.FilePath:= Path;
    E.Kind    := tekInsertLines;
    E.Line    := Sym.StartLine - 1; // insert AFTER (StartLine-1) => at StartLine
    E.Text    := Merged;
    Result.Edits:= Result.Edits + [E];

    Result.Action:= daCreated;
  end;
end;

end.
