unit DRagLint.Index.IncludeUses;

// N-06 (spec docs\superpowers\specs\2026-10-24-uses-in-include.md): uses clauses
// that live inside an include file.
//
// The preprocessor runs defines-only: an active include directive is resolved,
// its defines applied, and its body text DISCARDED (offset identity). So the
// parser never saw a uses clause written in a .inc, and no unit_uses row
// existed for it -- cycles, circular-uses, deps and charts were blind to the
// edge. This unit turns the include SITES the preprocessor already reports
// (with the child output bytes it already produced, under the host's live
// defines) into unit_uses rows for the HOST file:
//   * file_id = the host, section = the host section the directive sits in;
//   * start/end line/col = coordinates INSIDE the .inc;
//   * OriginPath = the absolute .inc path, IncludeLine = the directive's host line.
// Graph consumers need nothing; every uses EDITOR keys on OriginPath and
// refuses (an .inc may be shared by many hosts).
//
// Only depth-0 sites are used: a uses clause in a NESTED include is ignored.
//
// ENCODING NOTE: this unit never writes a bare brace inside a // comment.

interface

uses
  System.SysUtils,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Preprocess.Types;

/// <summary>Extracts the uses entries written inside the depth-0 include
/// sites of one host file.</summary>
/// <param name="ASites">The sites the 3-arg Preprocess overload reported for
/// the host. Sites with Depth greater than 0 are ignored.</param>
/// <param name="AParser">The Delphi parser that parsed the host; reused for the
/// include text. Must not be nil.</param>
/// <param name="AHostPath">The host file path; its extension picks the section
/// for a program (.dpr) or package (.dpk).</param>
/// <param name="AImplementationLine">The host's TParseResult.ImplementationLine
/// (0 = none). For a unit, a directive on a later line gives section
/// implementation, otherwise interface.</param>
/// <returns>One TUnitUse per entry, FileId -1, OriginPath and IncludeLine set,
/// coordinates inside the .inc; empty when no site carries a uses clause.</returns>
/// <remarks>The include text is parsed once, wrapped as a synthetic unit
/// (unit, interface, body, implementation, end.) so the body starts on line 3;
/// lines are shifted back by 2. A site whose text has no `uses` word is
/// skipped without a parse. Parse errors in the include are tolerated: every
/// entry the parser still produced inside the body is kept. Pure apart from
/// the parse; thread-safe if AParser is.</remarks>
function ExtractIncludeUses(const ASites: TArray<TPPIncludeSite>; const AParser: IParser;
  const AHostPath: string; AImplementationLine: Integer): TArray<TUnitUse>;

/// <summary>True when AText contains the word `uses` (any case) delimited by
/// non-identifier characters -- the cheap gate before the include parse.</summary>
/// <param name="AText">The include text.</param>
/// <returns>True iff a standalone `uses` token occurs (comments not excluded:
/// a false positive only costs one parse).</returns>
function HasUsesWord(const AText: string): Boolean;

implementation

uses
  System.Generics.Collections;

const
  USES_WORD = 'uses';
  // The synthetic wrapper puts the include body on line 3.
  WRAP_HEAD  = 'unit DragLintInc_;'#10'interface'#10;
  WRAP_TAIL  = #10'implementation'#10'end.'#10;
  WRAP_SHIFT = 2;

function IsIdentChar(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['a'..'z', 'A'..'Z', '0'..'9', '_']);
end;

function HasUsesWord(const AText: string): Boolean;
var
  Lowered: string ;
  P      : Integer;
  After  : Integer;
begin
  Lowered:= LowerCase(AText);
  P:= Pos(USES_WORD, Lowered);
  while P > 0 do
  begin
    After:= P + Length(USES_WORD);
    if ((P = 1) or not IsIdentChar(Lowered[P - 1]))
      and ((After > Length(Lowered)) or not IsIdentChar(Lowered[After])) then
      Exit(True);
    P:= Pos(USES_WORD, Lowered, After);
  end;
  Result:= False;
end;

// Counts the lines of ABody (1 + the number of LF bytes).
function LineCount(const ABody: string): Integer;
var
  C: Char;
begin
  Result:= 1;
  for C in ABody do
    if C = #10 then Inc(Result);
end;

function HostSection(const AHostPath: string; AImplementationLine, AIncludeLine: Integer): TUnitUseSection;
var
  Ext: string;
begin
  Ext:= LowerCase(ExtractFileExt(AHostPath));
  if Ext = '.dpr' then Exit(uusProgram);
  if Ext = '.dpk' then Exit(uusPackage);
  if (AImplementationLine > 0) and (AIncludeLine > AImplementationLine) then
    Result:= uusImplementation
  else
    Result:= uusInterface;
end;

function ExtractIncludeUses(const ASites: TArray<TPPIncludeSite>; const AParser: IParser;
  const AHostPath: string; AImplementationLine: Integer): TArray<TUnitUse>;
var
  Rows : TList<TUnitUse>;
  Site : TPPIncludeSite ;
  Body : string         ;
  Lines: Integer        ;
  Res  : TParseResult   ;
  U    : TUnitUse       ;
begin
  Rows:= TList<TUnitUse>.Create;
  try
    for Site in ASites do
    begin
      if Site.Depth <> 0 then Continue;
      Body:= TEncoding.UTF8.GetString(Site.Resolved);
      if not HasUsesWord(Body) then Continue;
      Lines:= LineCount(Body);
      Res:= AParser.Parse(TEncoding.UTF8.GetBytes(WRAP_HEAD + Body + WRAP_TAIL), Site.Path);
      for U in Res.UsesEntries do
      begin
        // Keep only entries inside the body (the wrapper itself has none).
        if (U.StartLine - WRAP_SHIFT < 1) or (U.StartLine - WRAP_SHIFT > Lines) then Continue;
        var R: TUnitUse:= U;
        R.FileId     := -1;
        R.StartLine  := U.StartLine - WRAP_SHIFT;
        R.EndLine    := U.EndLine   - WRAP_SHIFT;
        R.Section    := HostSection(AHostPath, AImplementationLine, Site.HostLine);
        R.OriginPath := Site.Path;
        R.IncludeLine:= Site.HostLine;
        Rows.Add(R);
      end;
    end;
    Result:= Rows.ToArray;
  finally
    Rows.Free;
  end;
end;

end.
