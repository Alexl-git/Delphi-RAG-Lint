unit DRagLint.V151.TXT;

{ Wave v151 lane TXT -- raw-text rules on .pas and .dfm bytes (bidi and invisible characters, control characters, todo comments, file headers, hard-coded strings).
  Scaffold created EMPTY by lane FRAME; lane TXT owns this unit, its
  DRagLint.V151.TXT.Support helpers and DRagLint.Fix.V151.TXT. Called only by
  DRagLint.V151.Dispatch. How-to: C:\TEMP\claude\lanes\v151\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v151 lane TXT; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV151TXTRules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.</remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the .pas unit's sibling form file.</summary>
    /// <param name="ACtx">The file being linted; ACtx.DfmPath is not empty when this is called.</param>
    /// <returns>Findings (FilePath may be the .dfm); nil when none.</returns>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the raw bytes of the .pas and of its sibling .dfm, before any decoding.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">The file the bytes come from (ACtx.Path or ACtx.DfmPath).</param>
    /// <param name="ABytes">The file content exactly as on disk.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check, lint-all only, run once after the per-file loop.</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.Classes
  , System.IOUtils
  , DRagLint.Core.Encoding
  , DRagLint.V151.TXT.Support
  ;

class procedure TV151TXTRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule('bidi-control', 'security', 'warning',
    'Bidirectional control character in the source: the code can read differently from how it compiles'));
  ADecls.Add(V151Rule('invisible-char', 'security', 'warning',
    'Invisible or zero-width character in the source text'));
  ADecls.Add(V151Rule('control-char', 'bug-patterns', 'warning',
    'Control character or invalid UTF-8 byte in the source text'));
  ADecls.Add(V151Rule('todo-comment', 'other', 'hint',
    'Comment starts with an open-work marker (TODO, FIXME)', False));
  ADecls.Add(V151Rule('file-header', 'policy', 'hint',
    'File does not start with the header from drag-lint-header.txt', False));
  ADecls.Add(V151Rule('hardcoded-string', 'other', 'hint',
    'String literal with text for people in a statement: use a resourcestring', False));
end;

class function TV151TXTRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
end;

class function TV151TXTRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
end;

class function TV151TXTRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;
var
  Found: TList<TLintFinding>;
  Wants: TTXTCharWants;
  Utf8: TBytes;
  HadBom, IsPas: Boolean;
  Src: string;
begin
  Result:= nil;
  if (Length(ABytes) = 0) or TxtIsBinaryDfm(ABytes) then Exit;
  IsPas:= SameText(ExtractFileExt(AFilePath), '.pas');
  Wants.Control:= ACtx.Wants('control-char');
  Wants.Bidi   := ACtx.Wants('bidi-control');
  Wants.Invis  := ACtx.Wants('invisible-char');
  Found:= TList<TLintFinding>.Create;
  try
    Utf8:= EnsureUtf8Bytes(ABytes);
    HadBom:= (Length(ABytes) >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF);
    if Wants.Control or Wants.Bidi or Wants.Invis then
      TxtScanChars(Utf8, HadBom, AFilePath, Wants, Found);
    if IsPas and (ACtx.Wants('todo-comment') or ACtx.Wants('hardcoded-string') or ACtx.Wants('file-header')) then
    begin
      Src:= TEncoding.UTF8.GetString(TxtSanitizeUtf8(Utf8));
      if ACtx.Wants('todo-comment') or ACtx.Wants('hardcoded-string') then
        TxtScanText(Src, AFilePath, ACtx.Wants('todo-comment'), ACtx.Wants('hardcoded-string'), Found);
      if ACtx.Wants('file-header') then
        TxtCheckHeader(Src, AFilePath, Found);
    end;
    Result:= Found.ToArray;
  finally
    Found.Free;
  end;
end;

class function TV151TXTRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;
begin
  Result:= nil;
end;

end.
