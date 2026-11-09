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
  const AHostPath: string; AImplementationLine: Integer): TArray<TUnitUse>; overload;

/// <summary>True when AText contains the word `uses` (any case) delimited by
/// non-identifier characters -- the cheap gate before the include parse.</summary>
/// <param name="AText">The include text.</param>
/// <returns>True iff a standalone `uses` token occurs (comments not excluded:
/// a false positive only costs one parse).</returns>
function HasUsesWord(const AText: string): Boolean;

/// <summary>149 EX2 (F4): finds the depth-0 include sites that stand IN a uses
/// list (`uses <$I x.inc>` (an include directive as the entry list), or after a comma of one) and patches the host's
/// parse bytes so its uses clause still parses.</summary>
/// <param name="ASites">The host's include sites (3-arg Preprocess overload).</param>
/// <param name="ARaw">The host bytes BEFORE preprocessing (UTF-8); the
/// directive's extent is read here, since the preprocessor blanked it.</param>
/// <param name="AParseBytes">The preprocessed host bytes the parser will see;
/// patched in place.</param>
/// <returns>One flag per ASites entry: True for a depth-0 site in a uses list.</returns>
/// <remarks>
/// The preprocessor blanks a directive, so `uses <$I x.inc>` (an include directive as the entry list) with the entries
/// and the closing semicolon in the .inc leaves the host a uses clause with no
/// entries; the clause then swallows the next section and the unit's real
/// uses edges are lost. For every such site the blanked directive bytes are
/// overwritten, same length, with a placeholder identifier (DLINC padded with
/// underscores), followed by the include's own last separator (';' or ',')
/// when it ends with one. The host's placeholder entry is dropped again by
/// DropIncludePlaceholders; the real entries come from the include through
/// ExtractIncludeUses. A site is in a uses list when the last significant
/// host token before it (whitespace and brace / paren-star comments skipped)
/// is the word `uses` or a comma. Offset identity holds: the patch replaces
/// spaces only, and a site whose blanked span is not all spaces is left alone.
/// </remarks>
function MarkUsesListIncludes(const ASites: TArray<TPPIncludeSite>; const ARaw: TBytes;
  var AParseBytes: TBytes): TArray<Boolean>;

/// <summary>149 EX2 (F4): removes the placeholder uses entries
/// MarkUsesListIncludes planted from a host's parsed uses entries.</summary>
/// <param name="ASites">The sites MarkUsesListIncludes saw.</param>
/// <param name="AInUses">Its result.</param>
/// <param name="AUses">The host's parsed uses entries; filtered in place.</param>
/// <remarks>An entry is dropped when it starts at a marked site's directive
/// position and its name starts with DLINC.</remarks>
procedure DropIncludePlaceholders(const ASites: TArray<TPPIncludeSite>; const AInUses: TArray<Boolean>;
  var AUses: TArray<TUnitUse>);

/// <summary>149 EX2 (F4): ExtractIncludeUses for a host some of whose sites
/// stand in a uses list.</summary>
/// <param name="ASites">As for the 4-arg overload.</param>
/// <param name="AParser">As for the 4-arg overload.</param>
/// <param name="AHostPath">As for the 4-arg overload.</param>
/// <param name="AImplementationLine">As for the 4-arg overload.</param>
/// <param name="AInUses">MarkUsesListIncludes' flags; nil = none marked.</param>
/// <returns>As for the 4-arg overload.</returns>
/// <remarks>A marked site's text is an entry LIST, not a clause: it is parsed as
/// `uses ` + text, with a closing `;` (after a placeholder entry when the text
/// ends with a comma) on a line of its own, which the body-line filter drops.
/// Columns on the include's first line are shifted back by the `uses ` prefix.
/// Unmarked sites behave as in the 4-arg overload.</remarks>
function ExtractIncludeUses(const ASites: TArray<TPPIncludeSite>; const AParser: IParser;
  const AHostPath: string; AImplementationLine: Integer; const AInUses: TArray<Boolean>): TArray<TUnitUse>; overload;

/// <summary>149 EX2 (F4): the file_includes rows of one host.</summary>
/// <param name="ASites">The host's include sites, every depth, source order.</param>
/// <param name="AInUses">MarkUsesListIncludes' flags; nil = none marked.</param>
/// <param name="AHostPath">The host path (picks program / package sections).</param>
/// <param name="AImplementationLine">The host's TParseResult.ImplementationLine.</param>
/// <returns>One row per site, same order. Section is set for depth 0 only.</returns>
function BuildFileIncludeRows(const ASites: TArray<TPPIncludeSite>; const AInUses: TArray<Boolean>;
  const AHostPath: string; AImplementationLine: Integer): TArray<TFileIncludeRow>;

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
  System.StrUtils,
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

const
  // 149 EX2 (F4): the uses-list placeholder and the prefix that turns an entry
  // list into a clause.
  PLACEHOLDER_NAME = 'DLINC';
  LIST_PREFIX      = 'uses ';
  BYTE_SPACE       = 32;
  BYTE_TAB         = 9;
  BYTE_LF          = 10;
  BYTE_CR          = 13;

function ExtractIncludeUses(const ASites: TArray<TPPIncludeSite>; const AParser: IParser;
  const AHostPath: string; AImplementationLine: Integer): TArray<TUnitUse>;
begin
  Result:= ExtractIncludeUses(ASites, AParser, AHostPath, AImplementationLine, nil);
end;

// 149 EX2: the last character of AText outside comments and whitespace
// (#0 when there is none). Strings are skipped as one significant token.
function LastSignificantChar(const AText: string): Char;
var
  K: Integer;
  N: Integer;
begin
  Result:= #0;
  N:= Length(AText);
  K:= 1;
  while K <= N do
  begin
    if (AText[K] = '/') and (K < N) and (AText[K + 1] = '/') then
    begin
      while (K <= N) and (AText[K] <> #10) do Inc(K);
      Continue;
    end;
    if AText[K] = #123 then
    begin
      while (K <= N) and (AText[K] <> #125) do Inc(K);
      Inc(K);
      Continue;
    end;
    if (AText[K] = '(') and (K < N) and (AText[K + 1] = '*') then
    begin
      Inc(K, 2);
      while (K < N) and not ((AText[K] = '*') and (AText[K + 1] = ')')) do Inc(K);
      Inc(K, 2);
      Continue;
    end;
    if AText[K] = '''' then
    begin
      Inc(K);
      while (K <= N) and (AText[K] <> '''') do Inc(K);
      Result:= '''';
      Inc(K);
      Continue;
    end;
    if not CharInSet(AText[K], [' ', #9, #10, #13]) then Result:= AText[K];
    Inc(K);
  end;
end;

function ExtractIncludeUses(const ASites: TArray<TPPIncludeSite>; const AParser: IParser;
  const AHostPath: string; AImplementationLine: Integer; const AInUses: TArray<Boolean>): TArray<TUnitUse>;
var
  Rows  : TList<TUnitUse>;
  Site  : TPPIncludeSite ;
  Body  : string         ;
  Lines : Integer        ;
  Res   : TParseResult   ;
  U     : TUnitUse       ;
  I     : Integer        ;
  InList: Boolean        ;
  Shift1: Integer        ;
begin
  Rows:= TList<TUnitUse>.Create;
  try
    for I:= 0 to High(ASites) do
    begin
      Site:= ASites[I];
      if Site.Depth <> 0 then Continue;
      Body:= TEncoding.UTF8.GetString(Site.Resolved);
      InList:= (I < Length(AInUses)) and AInUses[I];
      Lines:= LineCount(Body);
      Shift1:= 0;
      if InList then
      begin
        // An entry list: make it a clause; the closing line is past Lines, so dropped.
        case LastSignificantChar(Body) of
          ';': Body:= LIST_PREFIX + Body;
          ',': Body:= LIST_PREFIX + Body + #10 + PLACEHOLDER_NAME + ';';
        else
          Body:= LIST_PREFIX + Body + #10 + ';';
        end;
        Shift1:= Length(LIST_PREFIX);
      end
      else if not HasUsesWord(Body) then Continue;
      Res:= AParser.Parse(TEncoding.UTF8.GetBytes(WRAP_HEAD + Body + WRAP_TAIL), Site.Path);
      for U in Res.UsesEntries do
      begin
        // Keep only entries inside the body (the wrapper itself has none).
        if (U.StartLine - WRAP_SHIFT < 1) or (U.StartLine - WRAP_SHIFT > Lines) then Continue;
        var R: TUnitUse:= U;
        R.FileId     := -1;
        R.StartLine  := U.StartLine - WRAP_SHIFT;
        R.EndLine    := U.EndLine   - WRAP_SHIFT;
        if R.StartLine = 1 then R.StartCol:= R.StartCol - Shift1;
        if R.EndLine   = 1 then R.EndCol  := R.EndCol   - Shift1;
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

{ 149 EX2: index of the last significant byte before AOffset (whitespace and
  brace / paren-star comments skipped, scanning backward); -1 when none. }
function PrevSignificantByte(const ABytes: TBytes; AOffset: Integer): Integer;
var
  K: Integer;
begin
  K:= AOffset - 1;
  while K >= 0 do
  begin
    if ABytes[K] in [BYTE_SPACE, BYTE_TAB, BYTE_LF, BYTE_CR] then
      Dec(K)
    else if ABytes[K] = Ord(#125) then
    begin
      while (K >= 0) and (ABytes[K] <> Ord(#123)) do Dec(K);
      Dec(K);
    end
    else if (ABytes[K] = Ord(')')) and (K > 0) and (ABytes[K - 1] = Ord('*')) then
    begin
      Dec(K, 2);
      while (K > 0) and not ((ABytes[K - 1] = Ord('(')) and (ABytes[K] = Ord('*'))) do Dec(K);
      Dec(K, 2);
    end
    else
      Exit(K);
  end;
  Result:= -1;
end;

{ 149 EX2: True when the significant host token before AOffset is a comma or
  the word `uses`. }
function FollowsUsesOrComma(const ABytes: TBytes; AOffset: Integer): Boolean;
var
  K, J: Integer;
  Word: string;
begin
  K:= PrevSignificantByte(ABytes, AOffset);
  if K < 0 then Exit(False);
  if ABytes[K] = Ord(',') then Exit(True);
  J:= K;
  while (J >= 0) and IsIdentChar(Char(ABytes[J])) do Dec(J);
  if J = K then Exit(False);
  Word:= TEncoding.ASCII.GetString(ABytes, J + 1, K - J);
  Result:= SameText(Word, USES_WORD);
end;

{ 149 EX2: one past the last byte of the directive starting at AOffset in ARaw
  (brace or paren-star form); AOffset when it is neither or never closes on its line. }
function DirectiveEnd(const ARaw: TBytes; AOffset: Integer): Integer;
var
  K: Integer;
begin
  Result:= AOffset;
  if AOffset >= Length(ARaw) then Exit;
  K:= AOffset;
  if ARaw[K] = Ord(#123) then
  begin
    while (K < Length(ARaw)) and (ARaw[K] <> Ord(#125)) and (ARaw[K] <> BYTE_LF) do Inc(K);
    if (K < Length(ARaw)) and (ARaw[K] = Ord(#125)) then Result:= K + 1;
  end
  else if (ARaw[K] = Ord('(')) and (K + 1 < Length(ARaw)) and (ARaw[K + 1] = Ord('*')) then
  begin
    Inc(K, 2);
    while (K + 1 < Length(ARaw)) and not ((ARaw[K] = Ord('*')) and (ARaw[K + 1] = Ord(')'))) and (ARaw[K] <> BYTE_LF) do Inc(K);
    if (K + 1 < Length(ARaw)) and (ARaw[K] = Ord('*')) then Result:= K + 2;
  end;
end;

function MarkUsesListIncludes(const ASites: TArray<TPPIncludeSite>; const ARaw: TBytes;
  var AParseBytes: TBytes): TArray<Boolean>;
var
  I, K     : Integer;
  Off, Stop: Integer;
  Term     : string ;
  Patch    : string ;
  AllBlank : Boolean;
begin
  SetLength(Result, Length(ASites));
  for I:= 0 to High(ASites) do
  begin
    Result[I]:= False;
    if ASites[I].Depth <> 0 then Continue;
    Off:= OffsetOf(AParseBytes, ASites[I].HostLine, ASites[I].HostCol);
    if not FollowsUsesOrComma(AParseBytes, Off) then Continue;
    Result[I]:= True;
    Stop:= DirectiveEnd(ARaw, Off);
    if (Stop <= Off) or (Stop > Length(AParseBytes)) then Continue;
    AllBlank:= True;
    for K:= Off to Stop - 1 do
      if AParseBytes[K] <> BYTE_SPACE then AllBlank:= False;
    if not AllBlank then Continue;
    case LastSignificantChar(TEncoding.UTF8.GetString(ASites[I].Resolved)) of
      ';': Term:= ';';
      ',': Term:= ',';
    else
      Term:= '';
    end;
    if Stop - Off - Length(Term) < 1 then Continue;
    Patch:= Copy(PLACEHOLDER_NAME + StringOfChar('_', Stop - Off), 1, Stop - Off - Length(Term)) + Term;
    for K:= 1 to Length(Patch) do
      AParseBytes[Off + K - 1]:= Ord(Patch[K]);
  end;
end;

procedure DropIncludePlaceholders(const ASites: TArray<TPPIncludeSite>; const AInUses: TArray<Boolean>;
  var AUses: TArray<TUnitUse>);
var
  Kept: TList<TUnitUse>;
  U   : TUnitUse;
  I   : Integer;
  Drop: Boolean;
begin
  Kept:= TList<TUnitUse>.Create;
  try
    for U in AUses do
    begin
      Drop:= False;
      if StartsText(PLACEHOLDER_NAME, U.UnitName) then
        for I:= 0 to High(ASites) do
          if (I < Length(AInUses)) and AInUses[I]
            and (U.StartLine = ASites[I].HostLine) and (U.StartCol = ASites[I].HostCol) then
            Drop:= True;
      if not Drop then Kept.Add(U);
    end;
    AUses:= Kept.ToArray;
  finally
    Kept.Free;
  end;
end;

function BuildFileIncludeRows(const ASites: TArray<TPPIncludeSite>; const AInUses: TArray<Boolean>;
  const AHostPath: string; AImplementationLine: Integer): TArray<TFileIncludeRow>;
var
  I: Integer;
begin
  SetLength(Result, Length(ASites));
  for I:= 0 to High(ASites) do
  begin
    Result[I]:= Default(TFileIncludeRow);
    Result[I].IncPath := ASites[I].Path;
    Result[I].HostLine:= ASites[I].HostLine;
    Result[I].HostCol := ASites[I].HostCol;
    Result[I].Depth   := ASites[I].Depth;
    if ASites[I].Depth = 0 then
      Result[I].Section:= UnitUseSectionToStr(HostSection(AHostPath, AImplementationLine, ASites[I].HostLine));
    Result[I].InUses  := (I < Length(AInUses)) and AInUses[I];
  end;
end;

end.