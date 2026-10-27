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

/// <summary>E14: re-derives the X4 fact symbols.directives = 'scopedenums'
/// on the host's enum TYPE symbols when an active include file sets the
/// SCOPEDENUMS switch.</summary>
/// <param name="ASites">The sites the 3-arg Preprocess overload reported for
/// the host, nested ones included (source order, a nested site after its
/// parent).</param>
/// <param name="AHostBytes">The host bytes the parser saw (preprocessed).</param>
/// <param name="ASymbols">The host's parsed symbols; the Directives of each
/// skEnum is rewritten in place. Other kinds are untouched.</param>
/// <remarks>The parser reads the switch from the host text only, where every
/// include directive is blanked. Here each depth-0 include contributes ONE
/// switch at its directive's host position: the state its own text -- and its
/// nested includes, at their positions inside it -- leaves behind. An include
/// that sets no switch contributes nothing, and when no include does the
/// parser's answer stands untouched (the common case costs one byte scan per
/// include). Inactive includes and inactive branches inside an include never
/// reach here: the preprocessor reports no site for the first and blanks the
/// second. Pure; thread-safe.</remarks>
procedure ApplyIncludeScopedEnums(const ASites: TArray<TPPIncludeSite>;
  const AHostBytes: TBytes; var ASymbols: TArray<TSymbol>);

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  DRagLint.Parser.Delphi13;
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

const
  SCOPED_DIRECTIVE = 'scopedenums';
  LF_BYTE          = 10;

type
  { E14: one switch in HOST coordinates (1-based line, 1-based byte column). }
  TSwitchAt = record
    Line: Integer;
    Col : Integer;
    IsOn: Boolean;
  end;

{ 1-based line and byte column of AOffset in ABytes. }
procedure LineColOf(const ABytes: TBytes; AOffset: Integer; out ALine, ACol: Integer);
var
  K, LineStart: Integer;
begin
  ALine    := 1;
  LineStart:= 0;
  for K:= 0 to AOffset - 1 do
    if ABytes[K] = LF_BYTE then
    begin
      Inc(ALine);
      LineStart:= K + 1;
    end;
  ACol:= AOffset - LineStart + 1;
end;

{ Byte offset of 1-based ALine / ACol in ABytes (clamped to the length). }
function OffsetOf(const ABytes: TBytes; ALine, ACol: Integer): Integer;
var
  Line: Integer;
begin
  Result:= 0;
  Line  := 1;
  while (Line < ALine) and (Result < Length(ABytes)) do
  begin
    if ABytes[Result] = LF_BYTE then Inc(Line);
    Inc(Result);
  end;
  Result:= Result + ACol - 1;
  if Result > Length(ABytes) then Result:= Length(ABytes);
end;

{ The switch state the include at AIdx leaves behind, its nested includes
  included. False when neither it nor a nested include sets the switch.
  ANext is the first site after AIdx's whole subtree. }
function IncludeEffect(const ASites: TArray<TPPIncludeSite>; AIdx: Integer;
  out ANext: Integer; out AIsOn: Boolean): Boolean;
var
  Events : TList<TScopedEnumSwitch>;
  Ev     : TScopedEnumSwitch;
  J, Next: Integer;
  ChildOn: Boolean;
begin
  AIsOn := False;
  Events:= TList<TScopedEnumSwitch>.Create;
  try
    Events.AddRange(ScanScopedEnumSwitches(ASites[AIdx].Resolved));
    J:= AIdx + 1;
    while (J < Length(ASites)) and (ASites[J].Depth > ASites[AIdx].Depth) do
    begin
      if IncludeEffect(ASites, J, Next, ChildOn) then
      begin
        Ev.Offset:= OffsetOf(ASites[AIdx].Resolved, ASites[J].HostLine, ASites[J].HostCol);
        Ev.IsOn  := ChildOn;
        Events.Add(Ev);
      end;
      J:= Next;
    end;
    ANext := J;
    Result:= Events.Count > 0;
    if not Result then Exit;
    Events.Sort(TComparer<TScopedEnumSwitch>.Construct(
      function(const A, B: TScopedEnumSwitch): Integer
      begin
        Result:= A.Offset - B.Offset;
      end));
    AIsOn:= Events.Last.IsOn;
  finally
    Events.Free;
  end;
end;

procedure ApplyIncludeScopedEnums(const ASites: TArray<TPPIncludeSite>;
  const AHostBytes: TBytes; var ASymbols: TArray<TSymbol>);
var
  Events: TList<TSwitchAt>;
  Ev    : TSwitchAt;
  Sw    : TScopedEnumSwitch;
  I     : Integer;
  Next  : Integer;
  IsOn  : Boolean;
  Found : Boolean;
begin
  Events:= TList<TSwitchAt>.Create;
  try
    Found:= False;
    I    := 0;
    while I < Length(ASites) do
    begin
      if (ASites[I].Depth = 0) and IncludeEffect(ASites, I, Next, IsOn) then
      begin
        Ev.Line:= ASites[I].HostLine;
        Ev.Col := ASites[I].HostCol;
        Ev.IsOn:= IsOn;
        Events.Add(Ev);
        Found:= True;
        I    := Next;
      end
      else
        Inc(I);
    end;
    { No include touches the switch: the parser's host-only answer is complete. }
    if not Found then Exit;
    for Sw in ScanScopedEnumSwitches(AHostBytes) do
    begin
      LineColOf(AHostBytes, Sw.Offset, Ev.Line, Ev.Col);
      Ev.IsOn:= Sw.IsOn;
      Events.Add(Ev);
    end;
    Events.Sort(TComparer<TSwitchAt>.Construct(
      function(const A, B: TSwitchAt): Integer
      begin
        Result:= if A.Line <> B.Line then A.Line - B.Line else A.Col - B.Col;
      end));
    for I:= 0 to High(ASymbols) do
    begin
      if ASymbols[I].Kind <> skEnum then Continue;
      IsOn:= False;
      for Ev in Events do
      begin
        if (Ev.Line > ASymbols[I].StartLine)
           or ((Ev.Line = ASymbols[I].StartLine) and (Ev.Col >= ASymbols[I].StartCol)) then Break;
        IsOn:= Ev.IsOn;
      end;
      ASymbols[I].Directives:= if IsOn then SCOPED_DIRECTIVE else '';
    end;
  finally
    Events.Free;
  end;
end;

end.