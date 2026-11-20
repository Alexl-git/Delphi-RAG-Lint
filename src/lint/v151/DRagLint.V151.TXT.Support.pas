unit DRagLint.V151.TXT.Support;

{ Wave v151 lane TXT -- helpers of DRagLint.V151.TXT (private to the lane).
  Byte-level scan (bidi / invisible / control characters) and a small Pascal
  lexer (comments, string literals, begin/end depth) for the text rules. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  , DRagLint.Core.Model
  ;

const
  /// <summary>Per-file, per-rule cap on findings, so one corrupt file cannot flood a run.</summary>
  TXT_MAX_PER_RULE = 100;
  /// <summary>Name of the file-header template file looked up from the source directory upwards.</summary>
  TXT_HEADER_FILE = 'drag-lint-header.txt';

type
  /// <summary>Which character-level rules a scan should report.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.TXT.Support.pas), DRagLint.V151.TXT.Support.TxtScanChars (DRagLint.V151.TXT.Support.pas), DRagLint.V151.TXT.TV151TXTRules.CheckRawBytes (DRagLint.V151.TXT.pas)</para>
  /// <para>Used in units: DRagLint.V151.TXT, DRagLint.V151.TXT.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTXTCharWants = record
    Control: Boolean;
    Bidi   : Boolean;
    Invis  : Boolean;
  end;

/// <summary>True when ABytes is a binary form file (stream signature TPF0), which holds no text to scan.</summary>
/// <param name="ABytes">File content as on disk.</param>
/// <returns>True for a binary DFM.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.TXT.TV151TXTRules.CheckRawBytes (DRagLint.V151.TXT.pas)</para>
/// <para>Returns: (Length(ABytes) &gt;= 4) and (ABytes[0] = $54) and (ABytes[1] = $50)</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function TxtIsBinaryDfm(const ABytes: TBytes): Boolean;

/// <summary>Scans decoded UTF-8 bytes for bidi, invisible and control characters, and (UTF-8 BOM files) invalid bytes.</summary>
/// <param name="AUtf8">Content after EnsureUtf8Bytes (BOM stripped).</param>
/// <param name="AHadUtf8Bom">True when the file on disk started with a UTF-8 BOM: only then are invalid byte sequences reported (a BOM-less file with high bytes is legacy ANSI, not corruption).</param>
/// <param name="AFilePath">Path put into each finding.</param>
/// <param name="AWants">Which of the three rules to report.</param>
/// <param name="AOut">Findings are appended; capped at TXT_MAX_PER_RULE per rule.</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.TXT.TV151TXTRules.CheckRawBytes (DRagLint.V151.TXT.pas)</para>
/// <para>Calls: DRagLint.V151.TXT.Support.DecodeAt, DRagLint.V151.TXT.Support.IsBidi, DRagLint.V151.TXT.Support.IsControl, DRagLint.V151.TXT.Support.IsInvisible, DRagLint.V151.TXT.Support.MakeFinding, Format</para>
/// <para>Complexity: 19 (cyclomatic, outer body), 59 lines (full implementation)</para>
/// <seealso cref="DRagLint.V151.TXT.Support.DecodeAt"/>
/// <seealso cref="DRagLint.V151.TXT.Support.IsBidi"/>
/// <seealso cref="DRagLint.V151.TXT.Support.IsControl"/>
/// <seealso cref="DRagLint.V151.TXT.Support.IsInvisible"/>
/// <seealso cref="DRagLint.V151.TXT.Support.MakeFinding"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure TxtScanChars(const AUtf8: TBytes; AHadUtf8Bom: Boolean; const AFilePath: string;
  const AWants: TTXTCharWants; AOut: TList<TLintFinding>);

/// <summary>Copy of AUtf8 with every invalid byte replaced by '?', so the result always decodes as UTF-8 (TEncoding.UTF8 raises on bad bytes).</summary>
/// <param name="AUtf8">Bytes that may hold invalid sequences (a BOM file).</param>
/// <returns>Same length, valid UTF-8 where the input was.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.TXT.TV151TXTRules.CheckRawBytes (DRagLint.V151.TXT.pas)</para>
/// <para>Calls: Copy, DRagLint.V151.TXT.Support.DecodeAt</para>
/// <para>Returns: Copy(AUtf8)</para>
/// <seealso cref="DRagLint.V151.TXT.Support.DecodeAt"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function TxtSanitizeUtf8(const AUtf8: TBytes): TBytes;

/// <summary>Lexes Pascal source for open-work comments and human-text string literals.</summary>
/// <param name="ASource">Decoded source text.</param>
/// <param name="AFilePath">Path put into each finding.</param>
/// <param name="AWantTodo">Report todo-comment.</param>
/// <param name="AWantHard">Report hardcoded-string.</param>
/// <param name="AOut">Findings are appended; capped at TXT_MAX_PER_RULE per rule.</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.TXT.TV151TXTRules.CheckRawBytes (DRagLint.V151.TXT.pas)</para>
/// <para>Calls: CharInSet, Copy, DRagLint.V151.TXT.Support.ExcludedCallee, DRagLint.V151.TXT.Support.IsHumanText, DRagLint.V151.TXT.Support.IsIdChar, DRagLint.V151.TXT.Support.IsIdStart, DRagLint.V151.TXT.Support.MakeFinding, DRagLint.V151.TXT.Support.TodoMarker, LowerCase</para>
/// <para>Complexity: 98 (cyclomatic, outer body), 206 lines (full implementation)</para>
/// <seealso cref="DRagLint.V151.TXT.Support.ExcludedCallee"/>
/// <seealso cref="DRagLint.V151.TXT.Support.IsHumanText"/>
/// <seealso cref="DRagLint.V151.TXT.Support.IsIdChar"/>
/// <seealso cref="DRagLint.V151.TXT.Support.IsIdStart"/>
/// <seealso cref="DRagLint.V151.TXT.Support.MakeFinding"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure TxtScanText(const ASource, AFilePath: string; AWantTodo, AWantHard: Boolean; AOut: TList<TLintFinding>);

/// <summary>Compares the start of ASource with the header template found for AFilePath.</summary>
/// <param name="ASource">Decoded source text.</param>
/// <param name="AFilePath">The unit; the template file is searched from its directory upwards.</param>
/// <param name="AOut">One finding appended when the header is missing or different. Nothing when no template file exists.</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.TXT.TV151TXTRules.CheckRawBytes (DRagLint.V151.TXT.pas)</para>
/// <para>Calls: DRagLint.V151.TXT.Support.FindTemplate, DRagLint.V151.TXT.Support.MakeFinding, DRagLint.V151.TXT.Support.SplitTrimmedLines, Format</para>
/// <para>Complexity: 10 (cyclomatic, outer body), 28 lines (full implementation)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.V151.TXT.Support.FindTemplate"/>
/// <seealso cref="DRagLint.V151.TXT.Support.MakeFinding"/>
/// <seealso cref="DRagLint.V151.TXT.Support.SplitTrimmedLines"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure TxtCheckHeader(const ASource, AFilePath: string; AOut: TList<TLintFinding>);

implementation

uses
  System.Character
  , System.IOUtils
  , System.StrUtils
  ;

const
  CHEADER_MAX_UP = 10;
  CSNIPPET_MAX   = 60;

function MakeFinding(const ARule, APath: string; ALine, ACol, AEndCol: Integer;
  const ASeverity, AMessage: string): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId  := ARule;
  Result.FilePath:= APath;
  Result.StartLine:= ALine;
  Result.StartCol := ACol;
  Result.EndLine  := ALine;
  Result.EndCol   := AEndCol;
  Result.Severity := ASeverity;
  Result.Message  := AMessage;
end;

function TxtIsBinaryDfm(const ABytes: TBytes): Boolean;
begin
  Result:= (Length(ABytes) >= 4) and (ABytes[0] = $54) and (ABytes[1] = $50)  // dl:ok magic-literal@bc5e -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
    and (ABytes[2] = $46) and (ABytes[3] = $30);  // dl:ok magic-literal@df8b -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
end;

function IsBidi(ACp: Integer): Boolean;
begin
  Result:= (ACp = $061C) or (ACp = $200E) or (ACp = $200F)  // dl:ok boolean-expression-complexity@4733, magic-literal@4733 -- REVIEWED 2026-11-14 v151 INT: one flat predicate over fixed values; splitting it does not make it clearer; a spec value / fixed offset or length read at its single use site; a named constant adds nothing
    or ((ACp >= $202A) and (ACp <= $202E)) or ((ACp >= $2066) and (ACp <= $2069));  // dl:ok manual-inrange@21dd, magic-literal@21dd -- REVIEWED 2026-11-14 v151 INT: code-point range written as the spec writes it; InRange would hide the hex bounds; a spec value / fixed offset or length read at its single use site; a named constant adds nothing
end;

function IsInvisible(ACp: Integer): Boolean;
begin
  Result:= (ACp = $00AD) or (ACp = $115F) or (ACp = $1160) or (ACp = $180E)  // dl:ok boolean-expression-complexity@0530, magic-literal@0530 -- REVIEWED 2026-11-14 v151 INT: one flat predicate over fixed values; splitting it does not make it clearer; a spec value / fixed offset or length read at its single use site; a named constant adds nothing
    or ((ACp >= $200B) and (ACp <= $200D)) or ((ACp >= $2060) and (ACp <= $2064))  // dl:ok manual-inrange@491c, magic-literal@491c -- REVIEWED 2026-11-14 v151 INT: code-point range written as the spec writes it; InRange would hide the hex bounds; a spec value / fixed offset or length read at its single use site; a named constant adds nothing
    or (ACp = $3164) or (ACp = $FEFF) or (ACp = $FFA0);  // dl:ok magic-literal@80e2 -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
end;

function IsControl(ACp: Integer): Boolean;
begin
  Result:= ((ACp < $20) and (ACp <> 9) and (ACp <> 10) and (ACp <> 12) and (ACp <> 13))  // dl:ok boolean-expression-complexity@b6cf, magic-literal@b6cf -- REVIEWED 2026-11-14 v151 INT: one flat predicate over fixed values; splitting it does not make it clearer; a spec value / fixed offset or length read at its single use site; a named constant adds nothing
    or ((ACp >= $7F) and (ACp <= $9F));  // dl:ok manual-inrange@a435, magic-literal@a435 -- REVIEWED 2026-11-14 v151 INT: code-point range written as the spec writes it; InRange would hide the hex bounds; a spec value / fixed offset or length read at its single use site; a named constant adds nothing
end;

{ Decodes one UTF-8 sequence at AIdx. Returns its length; ACp = -1 for an invalid byte (length 1). }
function DecodeAt(const AB: TBytes; AIdx: Integer; out ACp: Integer): Integer;
var
  B0, Extra, J, Min: Integer;
  Cp: Cardinal;
begin
  B0:= AB[AIdx];
  if B0 < $80 then  // dl:ok magic-literal@af24 -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
  begin
    ACp:= B0;
    Exit(1);
  end;
  ACp:= -1;
  Result:= 1;
  if (B0 >= $C2) and (B0 <= $DF) then begin Extra:= 1; Cp:= B0 and $1F; Min:= $80; end  // dl:ok manual-inrange@3ac0, magic-literal@3ac0, multiple-statements-per-line@3ac0 -- REVIEWED 2026-11-14 v151 INT: code-point range written as the spec writes it; InRange would hide the hex bounds; a spec value / fixed offset or length read at its single use site; a named constant adds nothing; compact state reset in a scanner step, kept on one line like its siblings
  else if (B0 >= $E0) and (B0 <= $EF) then begin Extra:= 2; Cp:= B0 and $0F; Min:= $800; end  // dl:ok manual-inrange@fc6d, magic-literal@fc6d, multiple-statements-per-line@fc6d -- REVIEWED 2026-11-14 v151 INT: code-point range written as the spec writes it; InRange would hide the hex bounds; a spec value / fixed offset or length read at its single use site; a named constant adds nothing; compact state reset in a scanner step, kept on one line like its siblings
  else if (B0 >= $F0) and (B0 <= $F4) then begin Extra:= 3; Cp:= B0 and $07; Min:= $10000; end  // dl:ok manual-inrange@82dc, magic-literal@82dc, multiple-statements-per-line@82dc -- REVIEWED 2026-11-14 v151 INT: code-point range written as the spec writes it; InRange would hide the hex bounds; a spec value / fixed offset or length read at its single use site; a named constant adds nothing; compact state reset in a scanner step, kept on one line like its siblings
  else Exit;
  if AIdx + Extra >= Length(AB) then Exit;
  for J:= 1 to Extra do
  begin
    if (AB[AIdx + J] and $C0) <> $80 then Exit;  // dl:ok magic-literal@52aa -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
    Cp:= (Cp shl 6) or Cardinal(AB[AIdx + J] and $3F);  // dl:ok magic-literal@c4f2 -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
  end;
  if (Integer(Cp) < Min) or ((Cp >= $D800) and (Cp <= $DFFF)) or (Cp > $10FFFF) then Exit;  // dl:ok manual-inrange@01b1, magic-literal@01b1 -- REVIEWED 2026-11-14 v151 INT: code-point range written as the spec writes it; InRange would hide the hex bounds; a spec value / fixed offset or length read at its single use site; a named constant adds nothing
  ACp:= Integer(Cp);
  Result:= Extra + 1;
end;

function TxtSanitizeUtf8(const AUtf8: TBytes): TBytes;
var
  I, Len, Cp: Integer;
begin
  Result:= Copy(AUtf8);
  I:= 0;
  while I < Length(Result) do
  begin
    Len:= DecodeAt(Result, I, Cp);
    if Cp < 0 then Result[I]:= Ord('?');
    Inc(I, Len);
  end;
end;

procedure TxtScanChars(const AUtf8: TBytes; AHadUtf8Bom: Boolean; const AFilePath: string;
  const AWants: TTXTCharWants; AOut: TList<TLintFinding>);
const
  MAX_BMP_CODE_POINT   = $FFFF; { above it a code point is a surrogate pair in a string }
  SURROGATE_PAIR_UNITS = 2;
var
  I, Len, Cp, Line, Col, NCtl, NBidi, NInv: Integer;
begin
  I:= 0; Line:= 1; Col:= 1; NCtl:= 0; NBidi:= 0; NInv:= 0;  // dl:ok multiple-statements-per-line@7191 -- REVIEWED 2026-11-14 v151 INT: compact state reset in a scanner step, kept on one line like its siblings
  while I < Length(AUtf8) do
  begin
    Len:= DecodeAt(AUtf8, I, Cp);
    if Cp = 10 then  // dl:ok magic-literal@8399 -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
    begin
      Inc(Line);
      Col:= 0;
    end
    else if Cp < 0 then
    begin
      if AWants.Control and AHadUtf8Bom and (NCtl < TXT_MAX_PER_RULE) then
      begin
        AOut.Add(MakeFinding('control-char', AFilePath, Line, Col, Col + 1, 'warning',
          Format('Invalid UTF-8 byte $%.2X in a file that starts with a UTF-8 byte order mark', [AUtf8[I]])));
        Inc(NCtl);
      end;
    end
    else if IsControl(Cp) then
    begin
      { a Ctrl-Z (EOF marker) as the very last byte is a legacy DOS habit, not corruption }
      if AWants.Control and (NCtl < TXT_MAX_PER_RULE) and not ((Cp = $1A) and (I = High(AUtf8))) then  // dl:ok magic-literal@53a2 -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
      begin
        AOut.Add(MakeFinding('control-char', AFilePath, Line, Col, Col + 1, 'warning',
          Format('Control character U+%.4X in the source text', [Cp])));
        Inc(NCtl);
      end;
    end
    else if IsBidi(Cp) then
    begin
      if AWants.Bidi and (NBidi < TXT_MAX_PER_RULE) then
      begin
        AOut.Add(MakeFinding('bidi-control', AFilePath, Line, Col, Col + 1, 'warning',
          Format('Bidirectional control character U+%.4X: the code can read differently from how it compiles', [Cp])));
        Inc(NBidi);
      end;
    end
    else if IsInvisible(Cp) then
    begin
      if AWants.Invis and (NInv < TXT_MAX_PER_RULE) then
      begin
        AOut.Add(MakeFinding('invisible-char', AFilePath, Line, Col, Col + 1, 'warning',
          Format('Invisible character U+%.4X in the source text', [Cp])));
        Inc(NInv);
      end;
    end;
    { column counts UTF-16 units (the character column every finding reports; 1.52 BK-TAILS-ENG):
      a code point outside the BMP is a surrogate pair, two units; a continuation byte starts none }
    Inc(Col, if Cp > MAX_BMP_CODE_POINT then SURROGATE_PAIR_UNITS else 1);
    Inc(I, Len);
  end;
end;

{ ---------------- lexer ---------------- }

function IsIdStart(C: Char): Boolean;
begin
  Result:= C.IsLetter or (C = '_');
end;

function IsIdChar(C: Char): Boolean;
begin
  Result:= C.IsLetterOrDigit or (C = '_');
end;

{ todo-comment: the comment text (after the delimiters) starts with one of the two task markers TodoMarker accepts. }
function TodoMarker(const AText: string; AStart: Integer; out ASnippet: string): Boolean;
var
  I, J, N: Integer;
  W: string;
begin
  ASnippet:= '';
  N:= Length(AText);
  I:= AStart;
  while (I <= N) and CharInSet(AText[I], ['/', '*', '!', ' ', #9]) do Inc(I);
  J:= I;
  while (J <= N) and AText[J].IsLetter do Inc(J);
  W:= Copy(AText, I, J - I);
  Result:= False;
  if not (SameText(W, 'TODO') or SameText(W, 'FIXME')) then Exit;
  { prose such as "todo items are ..." is not a marker: needs capitals or a colon / paren right after }
  Result:= (W = UpperCase(W)) or ((J <= N) and CharInSet(AText[J], [':', '(']));
  if not Result then Exit;
  J:= I;
  while (J <= N) and (not CharInSet(AText[J], [#10, #13])) and (J - I < CSNIPPET_MAX) do Inc(J);
  ASnippet:= Trim(Copy(AText, I, J - I));
  if (ASnippet <> '') and (ASnippet[Length(ASnippet)] = '}') then
    SetLength(ASnippet, Length(ASnippet) - 1);
end;

function WordCount(const AText: string): Integer;
var
  I, Run: Integer;
begin
  Result:= 0;
  Run:= 0;
  for I:= 1 to Length(AText) + 1 do
    if (I <= Length(AText)) and AText[I].IsLetter then
      Inc(Run)
    else
    begin
      if Run >= 2 then Inc(Result);
      Run:= 0;
    end;
end;

function StartsWithWord(const AText, AWord: string): Boolean;
begin
  Result:= StartsText(AWord + ' ', Trim(AText)) or SameText(Trim(AText), AWord);
end;

{ RULES-S (1.52.3): text led by Select/Set/With whose next word is a plain-English lead-in ("Select a file")
  is a UI sentence, not SQL. }
function IsUiLeadIn(const AText: string): Boolean;
const
  CSqlLike: array[0..2] of string = ('select', 'set', 'with');
  CLeadIn: array[0..17] of string = ('a', 'an', 'the', 'your', 'one', 'all', 'any', 'this', 'that', 'at',
    'which', 'some', 'each', 'no', 'new', 'another', 'my', 'to');
var
  I: Integer;
  Words: TArray<string>;
  Hit: Boolean;
begin
  Result:= False;
  Words:= Trim(AText).Split([' ']);
  if Length(Words) < 2 then Exit;  // dl:ok magic-literal@a1c1 -- REVIEWED 2026-11-20 v1523 RULES-S: a lead word plus one more is the minimum shape
  Hit:= False;
  for I:= Low(CSqlLike) to High(CSqlLike) do
    if SameText(Words[0], CSqlLike[I]) then Hit:= True;
  if not Hit then Exit;
  if ContainsText(' ' + Trim(AText) + ' ', ' from ') then Exit;  // 'select a from t' keeps its column a
  for I:= Low(CLeadIn) to High(CLeadIn) do
    if SameText(Words[1], CLeadIn[I]) then Exit(True);
end;

{ hardcoded-string: words a person would read, not a key, path, SQL or format token. }
function IsHumanText(const AText: string): Boolean;
const
  CSQL: array[0..14] of string = ('select', 'insert', 'update', 'delete', 'create', 'alter', 'drop',
    'execute', 'with', 'from', 'where', 'set', 'order', 'group', 'merge');
var
  I, Letters: Integer;
  S: string;
begin
  Result:= False;
  S:= Trim(AText);
  if (Length(S) < 5) or not S[1].IsLetter then Exit;  // dl:ok magic-literal@0b8b -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
  if (Pos(' ', S) = 0) or (WordCount(S) < 2) then Exit;  // dl:ok pos-for-contains@f95d -- REVIEWED 2026-11-14 v151 INT: Pos over a delimited keyword list, as the rest of the unit does
  if S.IndexOfAny(['\', '/', '<', '>', '{', '}', '=', ';', '|']) >= 0 then Exit;
  for I:= Low(CSQL) to High(CSQL) do
    if StartsWithWord(S, CSQL[I]) and not IsUiLeadIn(S) then Exit;
  Letters:= 0;
  for I:= 1 to Length(S) do
    if S[I].IsLetter or (S[I] = ' ') then Inc(Letters);
  Result:= Letters * 10 >= Length(S) * 7;  // dl:ok magic-literal@80b9 -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
end;

{ Q19 (1.52.2): last-segment callees whose literals are keys, log text or option tables, not UI. }
function ExcludedLastSegment(const ASeg: string): Boolean;
const
  CKeyCalls: array[0..24] of string = ('ReadString', 'WriteString', 'ReadInteger', 'WriteInteger',
    'ReadBool', 'WriteBool', 'ReadFloat', 'WriteFloat', 'ReadDate', 'WriteDate', 'ReadDateTime',
    'WriteDateTime', 'ReadTime', 'WriteTime', 'ReadSection', 'ReadSections', 'ReadSectionValues',
    'EraseSection', 'DeleteKey', 'ValueExists', 'SectionExists', 'OpenKey', 'OpenKeyReadOnly',
    'KeyExists', 'ReadBinaryStream');
  { RULES-S (1.52.3): known logger call names only; Logout / Login / LogoffUser carry UI text. }
  CLogCalls: array[0..19] of string = ('Log', 'LogMsg', 'LogMessage', 'LogError', 'LogErr', 'LogWarn',
    'LogWarning', 'LogInfo', 'LogDebug', 'LogTrace', 'LogFmt', 'LogFormat', 'LogException', 'LogEvent',
    'LogText', 'LogLine', 'LogFatal', 'LogVerbose', 'LogToFile', 'LogStr');
  COptPrefix: array[0..4] of string = ('MakeOpt', 'AddOpt', 'RegisterOption', 'DefineOption', 'NewOpt');
var
  I: Integer;
begin
  Result:= SameText(ASeg, 'Assert') or SameText(ASeg, 'OutputDebugString')
    or StartsText('Trace', ASeg);
  if Result or StartsText('Debug', ASeg) or StartsText('CodeSite', ASeg) then Exit(True);
  for I:= Low(CLogCalls) to High(CLogCalls) do
    if SameText(ASeg, CLogCalls[I]) then Exit(True);
  for I:= Low(CKeyCalls) to High(CKeyCalls) do
    if SameText(ASeg, CKeyCalls[I]) then Exit(True);
  for I:= Low(COptPrefix) to High(COptPrefix) do
    if StartsText(COptPrefix[I], ASeg) then Exit(True);
end;

{ Q19 (1.52.2): a receiver segment that names a logger (FLog, Logger, AppLog, CodeSite). }
function LoggerReceiver(const ASeg: string): Boolean;
begin
  Result:= SameText(ASeg, 'Log') or StartsText('Logger', ASeg) or EndsText('Log', ASeg)
    or EndsText('Logger', ASeg) or EndsText('CodeSite', ASeg);
end;

{ AChain is the dotted callee text before a '(' (e.g. 'FLog.Info'). }
function ExcludedCallee(const AChain: string): Boolean;
var
  Segs: TArray<string>;
  I: Integer;
begin
  Segs:= AChain.Split(['.']);
  Result:= False;
  if Length(Segs) = 0 then Exit;
  if ExcludedLastSegment(Segs[High(Segs)]) then Exit(True);
  for I:= 0 to High(Segs) - 1 do
    if LoggerReceiver(Segs[I]) then Exit(True);
end;

{ Q19: a statement piece that starts a SQL command or clause (IsHumanText's own keyword list). }
function StartsSqlWord(const AText: string): Boolean;
const
  CSQLStart: array[0..14] of string = ('select', 'insert', 'update', 'delete', 'create', 'alter', 'drop',
    'execute', 'with', 'from', 'where', 'set', 'order', 'group', 'merge');
var
  I: Integer;
begin
  Result:= False;
  for I:= Low(CSQLStart) to High(CSQLStart) do
    if StartsWithWord(AText, CSQLStart[I]) and not IsUiLeadIn(AText) then Exit(True);
end;

{ Q19: a statement that joins pieces with '+' and holds a SQL piece is SQL text: drop its pending findings. }
procedure FlushStatement(APending: TList<TLintFinding>; AOut: TList<TLintFinding>; ADrop: Boolean; var ANHard: Integer);
var
  F: TLintFinding;
begin
  for F in APending do
    if not ADrop then
      AOut.Add(F)
    else
      Dec(ANHard);
  APending.Clear;
end;

procedure TxtScanText(const ASource, AFilePath: string; AWantTodo, AWantHard: Boolean; AOut: TList<TLintFinding>);  // dl:ok deep-nesting@2330, cyclomatic-complexity@7de0, cognitive-complexity@6060, too-many-locals@cb16 -- REVIEWED 2026-11-20 v1522 INT: one hand-written scanner over the source text; each branch is one lexical shape, splitting it would scatter the scanner state
var
  S: string;
  I, N, Line, LineStart, Depth, J, StartLine, StartCol, NTodo, NHard, K: Integer;
  C: Char;
  Word, Lower, LastIdent, Snippet, Content, PrevOp: string;
  Parens: TList<string>;
  Pending: TList<TLintFinding>;
  PrecededByDot, InExcluded, Closed, StmtSql, StmtPlus: Boolean;
begin
  S:= ASource;
  N:= Length(S);
  I:= 1; Line:= 1; LineStart:= 1; Depth:= 0; NTodo:= 0; NHard:= 0;  // dl:ok multiple-statements-per-line@e733 -- REVIEWED 2026-11-14 v151 INT: compact state reset in a scanner step, kept on one line like its siblings
  StmtSql:= False; StmtPlus:= False;  // dl:ok multiple-statements-per-line@81da -- REVIEWED 2026-11-20 Q19: compact state reset in a scanner step, kept on one line like its siblings
  LastIdent:= ''; PrevOp:= '';  // dl:ok multiple-statements-per-line@24f9 -- REVIEWED 2026-11-14 v151 INT: compact state reset in a scanner step, kept on one line like its siblings
  Parens:= TList<string>.Create;
  Pending:= TList<TLintFinding>.Create;
  try
    while I <= N do
    begin
      C:= S[I];
      if C = #10 then
      begin
        Inc(Line); Inc(I); LineStart:= I;  // dl:ok multiple-statements-per-line@9057 -- REVIEWED 2026-11-14 v151 INT: compact state reset in a scanner step, kept on one line like its siblings
      end
      else if (C = ' ') or (C = #9) or (C = #13) then
        Inc(I)
      else if C = '''' then
      begin
        StartLine:= Line; StartCol:= I - LineStart + 1;  // dl:ok multiple-statements-per-line@5767 -- REVIEWED 2026-11-14 v151 INT: compact state reset in a scanner step, kept on one line like its siblings
        Content:= '';
        { multi-line literal: ''' alone on its line up to a closing ''' line }
        K:= I + 3;  // dl:ok magic-literal@3082 -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
        while (K <= N) and CharInSet(S[K], [' ', #9, #13]) do Inc(K);
        if (I + 2 <= N) and (S[I + 1] = '''') and (S[I + 2] = '''') and ((K > N) or (S[K] = #10)) then
        begin
          J:= K;
          Closed:= False;
          while (J <= N) and not Closed do
          begin
            if S[J] = #10 then
            begin
              Inc(Line); LineStart:= J + 1;  // dl:ok multiple-statements-per-line@96d9 -- REVIEWED 2026-11-14 v151 INT: compact state reset in a scanner step, kept on one line like its siblings
              K:= J + 1;
              while (K <= N) and CharInSet(S[K], [' ', #9]) do Inc(K);
              if (K + 2 <= N) and (S[K] = '''') and (S[K + 1] = '''') and (S[K + 2] = '''') then
              begin
                J:= K + 3;  // dl:ok magic-literal@9c94 -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
                Closed:= True;
                Continue;
              end;
            end;
            Inc(J);
          end;
          I:= J;
        end
        else
        begin
          J:= I + 1;
          while J <= N do
          begin
            if S[J] = '''' then
            begin
              if (J < N) and (S[J + 1] = '''') then
              begin
                Content:= Content + '''';  // dl:ok concat-in-loop@aa74 -- REVIEWED 2026-11-14 v151 INT: a few short pieces per call, not an accumulating large string
                Inc(J, 2);
                Continue;
              end;
              Break;
            end;
            if (S[J] = #10) or (S[J] = #13) then Break;
            Content:= Content + S[J];  // dl:ok concat-in-loop@c290 -- REVIEWED 2026-11-14 v151 INT: a few short pieces per call, not an accumulating large string
            Inc(J);
          end;
          I:= J + 1;
          if StartsSqlWord(Content) then StmtSql:= True;
          if AWantHard and (Depth > 0) and (NHard < TXT_MAX_PER_RULE) and IsHumanText(Content)  // dl:ok boolean-expression-complexity@c4a9 -- REVIEWED 2026-11-14 v151 INT: one flat predicate over fixed values; splitting it does not make it clearer
            and (PrevOp <> '=') and (PrevOp <> '<>') then
          begin
            InExcluded:= False;
            for K:= 0 to Parens.Count - 1 do
              if ExcludedCallee(Parens[K]) then InExcluded:= True;
            if not InExcluded then
            begin
              Snippet:= Copy(Content, 1, CSNIPPET_MAX);
              Pending.Add(MakeFinding('hardcoded-string', AFilePath, StartLine, StartCol,
                StartCol + Length(Content) + 2, 'hint',
                'String literal with text for people in a statement; move it to a resourcestring so it can be translated: ' + Snippet));
              Inc(NHard);
            end;
          end;
        end;
        PrevOp:= '';
        LastIdent:= '';
      end
      else if (C = '/') and (I < N) and (S[I + 1] = '/') then
      begin
        if AWantTodo and (NTodo < TXT_MAX_PER_RULE) and TodoMarker(S, I + 2, Snippet) then
        begin
          AOut.Add(MakeFinding('todo-comment', AFilePath, Line, I - LineStart + 1,
            I - LineStart + 1 + Length(Snippet), 'hint', 'Open work marker in a comment: ' + Snippet));
          Inc(NTodo);
        end;
        while (I <= N) and (S[I] <> #10) do Inc(I);
      end
      else if C = '{' then
      begin
        StartLine:= Line; StartCol:= I - LineStart + 1;  // dl:ok multiple-statements-per-line@5767 -- REVIEWED 2026-11-14 v151 INT: compact state reset in a scanner step, kept on one line like its siblings
        if AWantTodo and (NTodo < TXT_MAX_PER_RULE) and (I < N) and (S[I + 1] <> '$')
          and TodoMarker(S, I + 1, Snippet) then
        begin
          AOut.Add(MakeFinding('todo-comment', AFilePath, StartLine, StartCol,
            StartCol + Length(Snippet), 'hint', 'Open work marker in a comment: ' + Snippet));
          Inc(NTodo);
        end;
        while (I <= N) and (S[I] <> '}') do
        begin
          if S[I] = #10 then
          begin
            Inc(Line); LineStart:= I + 1;  // dl:ok multiple-statements-per-line@5030 -- REVIEWED 2026-11-14 v151 INT: compact state reset in a scanner step, kept on one line like its siblings
          end;
          Inc(I);
        end;
        Inc(I);
      end
      else if (C = '(') and (I < N) and (S[I + 1] = '*') then
      begin
        StartLine:= Line; StartCol:= I - LineStart + 1;  // dl:ok multiple-statements-per-line@5767 -- REVIEWED 2026-11-14 v151 INT: compact state reset in a scanner step, kept on one line like its siblings
        if AWantTodo and (NTodo < TXT_MAX_PER_RULE) and (I + 1 < N) and (S[I + 2] <> '$')
          and TodoMarker(S, I + 2, Snippet) then
        begin
          AOut.Add(MakeFinding('todo-comment', AFilePath, StartLine, StartCol,
            StartCol + Length(Snippet), 'hint', 'Open work marker in a comment: ' + Snippet));
          Inc(NTodo);
        end;
        Inc(I, 2);
        while (I <= N) and not ((S[I] = '*') and (I < N) and (S[I + 1] = ')')) do
        begin
          if S[I] = #10 then
          begin
            Inc(Line); LineStart:= I + 1;  // dl:ok multiple-statements-per-line@5030 -- REVIEWED 2026-11-14 v151 INT: compact state reset in a scanner step, kept on one line like its siblings
          end;
          Inc(I);
        end;
        Inc(I, 2);
      end
      else if C = '(' then
      begin
        Parens.Add(LastIdent);
        Inc(I);
        LastIdent:= '';
        PrevOp:= '';
      end
      else if C = ')' then
      begin
        if Parens.Count > 0 then Parens.Delete(Parens.Count - 1);
        Inc(I);
        LastIdent:= '';
        PrevOp:= '';
      end
      else if IsIdStart(C) or ((C = '&') and (I < N) and IsIdStart(S[I + 1])) then
      begin
        J:= I;
        if C = '&' then Inc(J);
        while (J <= N) and IsIdChar(S[J]) do Inc(J);
        Word:= Copy(S, I, J - I);
        PrecededByDot:= (I > 1) and (S[I - 1] = '.');
        if (C <> '&') and not PrecededByDot then
        begin
          Lower:= LowerCase(Word);
          if (Lower = 'begin') or (Lower = 'try') or (Lower = 'asm') or ((Lower = 'case') and (Depth > 0)) then
            Inc(Depth)
          else if (Lower = 'end') and (Depth > 0) then
            Dec(Depth);
          if (Parens.Count = 0)
            and MatchStr(Lower, ['begin', 'end', 'else', 'then', 'do', 'try', 'finally', 'except']) then
          begin
            FlushStatement(Pending, AOut, StmtSql and StmtPlus, NHard);
            StmtSql:= False; StmtPlus:= False;  // dl:ok multiple-statements-per-line@81da -- REVIEWED 2026-11-20 Q19: compact state reset in a scanner step, kept on one line like its siblings
          end;
        end;
        LastIdent:= if PrecededByDot and (LastIdent <> '') then LastIdent + '.' + Word else Word;
        PrevOp:= '';
        I:= J;
      end
      else if C.IsDigit then
      begin
        while (I <= N) and (IsIdChar(S[I]) or (S[I] = '.')) do
        begin
          if (S[I] = '.') and (I < N) and (S[I + 1] = '.') then Break;
          Inc(I);
        end;
        PrevOp:= '';
        LastIdent:= '';
      end
      else if CharInSet(C, [':', '<', '>', '=']) then
      begin
        PrevOp:= '';
        while (I <= N) and CharInSet(S[I], [':', '<', '>', '=']) do
        begin
          PrevOp:= PrevOp + S[I];  // dl:ok concat-in-loop@344e -- REVIEWED 2026-11-14 v151 INT: a few short pieces per call, not an accumulating large string
          Inc(I);
        end;
        LastIdent:= '';
      end
      else
      begin
        PrevOp:= '';
        if C = '+' then StmtPlus:= True;
        if C = ';' then
        begin
          FlushStatement(Pending, AOut, StmtSql and StmtPlus, NHard);
          StmtSql:= False; StmtPlus:= False;  // dl:ok multiple-statements-per-line@81da -- REVIEWED 2026-11-20 Q19: compact state reset in a scanner step, kept on one line like its siblings
        end;
        if C <> '.' then LastIdent:= '';
        Inc(I);
      end;
    end;
  finally
    FlushStatement(Pending, AOut, StmtSql and StmtPlus, NHard);
    Pending.Free;
    Parens.Free;
  end;
end;

{ ---------------- file header ---------------- }

function FindTemplate(const AFilePath: string): string;
var
  Dir, Cand, Parent: string;
  Level: Integer;
begin
  Result:= '';
  Dir:= ExtractFilePath(ExpandFileName(AFilePath));
  for Level:= 1 to CHEADER_MAX_UP do
  begin
    Cand:= TPath.Combine(Dir, TXT_HEADER_FILE);
    if TFile.Exists(Cand) then Exit(Cand);
    Parent:= ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if (Parent = '') or SameText(Parent, Dir) then Break;
    Dir:= Parent;
  end;
end;

function SplitTrimmedLines(const AText: string): TArray<string>;
var
  L: TStringList;
  I: Integer;
begin
  L:= TStringList.Create;
  try
    L.Text:= AText;
    SetLength(Result, L.Count);
    for I:= 0 to L.Count - 1 do
      Result[I]:= TrimRight(L[I]);
  finally
    L.Free;
  end;
end;

procedure TxtCheckHeader(const ASource, AFilePath: string; AOut: TList<TLintFinding>);
var
  TplPath, Tpl: string;
  T, F: TArray<string>;
  NT, I, Bad: Integer;
begin
  TplPath:= FindTemplate(AFilePath);
  if TplPath = '' then Exit;
  Tpl:= TFile.ReadAllText(TplPath, TEncoding.UTF8);
  T:= SplitTrimmedLines(Tpl);
  NT:= Length(T);
  while (NT > 0) and (T[NT - 1] = '') do Dec(NT);
  if NT = 0 then Exit;
  F:= SplitTrimmedLines(ASource);
  Bad:= -1;
  for I:= 0 to NT - 1 do
    if (I >= Length(F)) or (F[I] <> T[I]) then
    begin
      Bad:= I;
      Break;
    end;
  if Bad < 0 then Exit;
  if Bad = 0 then
    AOut.Add(MakeFinding('file-header', AFilePath, 1, 1, 1, 'hint',
      'File does not start with the header from ' + TXT_HEADER_FILE))
  else
    AOut.Add(MakeFinding('file-header', AFilePath, Bad + 1, 1, 1, 'hint',
      Format('File header differs from %s at line %d', [TXT_HEADER_FILE, Bad + 1])));
end;

end.
