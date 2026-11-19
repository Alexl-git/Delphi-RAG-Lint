unit DRagLint.V151.RTLCOLL.Support;

{ Wave v151 lane RTLCOLL -- helpers of DRagLint.V151.RTLCOLL (private to the lane).

  The analyses here work on MASKED source text: comments and the content of
  string literals are replaced by blanks, every other character (and every line
  break) keeps its offset, so an offset in the masked text is an offset in the
  file. All analyses are single-file and declaration-driven: a name counts as a
  dictionary / string list only when this very file declares it as one (or
  creates one into it). Anything the file does not show is silent, never a
  guess. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  ;

const
  RULE_DICT_GET      = 'dictionary-get-without-check';
  RULE_SL_LEAK       = 'stringlist-objects-leak';
  RULE_SL_UNSORTED   = 'stringlist-unsorted';
  RULE_NULL_COMPARE  = 'null-compare';
  RULE_REG_HKLM      = 'registry-hklm-write';
  RULE_RANDOM        = 'random-without-randomize';
  RULE_NOW_ELAPSED   = 'now-for-elapsed-time';

type
  /// <summary>One hit of an analysis: where, under which rule, and what to say.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.RTLCOLL.Support.pas), DRagLint.V151.RTLCOLL.Support.FindDictionaryGetWithoutCheck (DRagLint.V151.RTLCOLL.Support.pas), DRagLint.V151.RTLCOLL.Support.FindStringListObjectsLeak (DRagLint.V151.RTLCOLL.Support.pas), DRagLint.V151.RTLCOLL.Support.FindStringListUnsorted (DRagLint.V151.RTLCOLL.Support.pas), DRagLint.V151.RTLCOLL.Support.Hit (DRagLint.V151.RTLCOLL.Support.pas) (+4 more)</para>
  /// <para>Used in units: DRagLint.V151.RTLCOLL, DRagLint.V151.RTLCOLL.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRtlCollHit = record
    Rule  : string;
    Offset: Integer;
    Length: Integer;
    Msg   : string;
  end;

  /// <summary>Half-open offset range [First, Last) of one routine (or of the text before the first routine).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.V151.RTLCOLL.Support.pas), DRagLint.V151.RTLCOLL.Support.FindNowForElapsedTime (DRagLint.V151.RTLCOLL.Support.pas), DRagLint.V151.RTLCOLL.Support.FindRegistryHklmWrite (DRagLint.V151.RTLCOLL.Support.pas), DRagLint.V151.RTLCOLL.Support.Slice (DRagLint.V151.RTLCOLL.Support.pas), DRagLint.V151.RTLCOLL.Support.SplitRoutines (DRagLint.V151.RTLCOLL.Support.pas)</para>
  /// <para>Used in units: DRagLint.V151.RTLCOLL.Support</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRtlRange = record
    First: Integer;
    Last : Integer;
  end;

/// <summary>Blanks comments and string-literal content, keeping every offset and line break.</summary>
/// <param name="ASrc">Pascal source text.</param>
/// <returns>Text of the same length; string delimiters stay, their content and all comments become spaces.</returns>
/// <remarks>
/// Handles // line comments, { } and (* *) blocks (compiler directives included) and
/// doubled quotes inside strings. An unterminated block runs to the end of the text.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckFile (DRagLint.V151.RTLCOLL.pas), DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckProject (DRagLint.V151.RTLCOLL.pas)</para>
/// <para>Calls: PChar, SetString</para>
/// <para>Complexity: 32 (cyclomatic, outer body), 85 lines (full implementation)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function MaskSource(const ASrc: string): string;

/// <summary>Converts an offset into a 1-based line and column.</summary>
/// <param name="AMasked">The masked (or original) text.</param>
/// <param name="AOffset">0-based offset.</param>
/// <param name="ALine">Receives the 1-based line.</param>
/// <param name="ACol">Receives the 1-based column.</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.RTLCOLL.AddHits (DRagLint.V151.RTLCOLL.pas), DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckProject (DRagLint.V151.RTLCOLL.pas)</para>
/// <para>Mutates: ALine (out), ACol (out)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure OffsetToLineCol(const AMasked: string; AOffset: Integer; out ALine, ACol: Integer);

/// <summary>Reads a Pascal source file as ANSI text.</summary>
/// <param name="APath">File path.</param>
/// <returns>The text; empty when the file cannot be read.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckFile (DRagLint.V151.RTLCOLL.pas), DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckProject (DRagLint.V151.RTLCOLL.pas)</para>
/// <para>Returns: TFile.ReadAllText(APath, TEncoding.ANSI); ''</para>
/// <para>Catches: EArgumentException (swallowed); EDirectoryNotFoundException (swallowed); EFileNotFoundException (swallowed); EFOpenError (swallowed); EInOutError (swallowed)</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ReadSourceText(const APath: string): string;

/// <summary>dictionary-get-without-check: a read of Dict[Key] / Dict.Items[Key] with no key guard in the routine.</summary>
/// <param name="AMasked">Masked source.</param>
/// <returns>One hit per routine and dictionary (the first unguarded read); repeats of the same pattern add noise.</returns>
/// <remarks>
/// Only names this file declares as TDictionary, TObjectDictionary, TSortedDictionary,
/// IDictionary (or an alias / descendant declared in the file) count. A routine is guarded for a name when it
/// calls ContainsKey, TryGetValue, TryAdd, ExtractPair, enumerates Keys / Values / the dictionary, adds to it
/// before the read, or handles EKeyNotFoundException / EListError. A write target (Dict[Key] := ...) is not a read.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckFile (DRagLint.V151.RTLCOLL.pas)</para>
/// <para>Calls: CharInSet, ContainsText, Copy, DRagLint.V151.RTLCOLL.Support.BaseTypeName, DRagLint.V151.RTLCOLL.Support.Esc, DRagLint.V151.RTLCOLL.Support.Hit, DRagLint.V151.RTLCOLL.Support.MatchClose, DRagLint.V151.RTLCOLL.Support.NameMatches, DRagLint.V151.RTLCOLL.Support.TScan.Body, DRagLint.V151.RTLCOLL.Support.TScan.Create, DRagLint.V151.RTLCOLL.Support.TScan.Qualifies, DRagLint.V151.RTLCOLL.Support.TScan.RangeIndex, IntToStr, LowerCase, Trim</para>
/// <para>Returns: nil</para>
/// <para>Complexity: 20 (cyclomatic, outer body), 60 lines (full implementation)</para>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.BaseTypeName"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.Esc"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.Hit"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.MatchClose"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.NameMatches"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindDictionaryGetWithoutCheck(const AMasked: string): TArray<TRtlCollHit>;

/// <summary>stringlist-objects-leak: AddObject / InsertObject / Objects[i] := stores a freshly created object into a
/// string list that does not own its objects.</summary>
/// <param name="AMasked">Masked source.</param>
/// <returns>One hit per storing call.</returns>
/// <remarks>
/// The list must be created in this file. Silent when OwnsObjects is set (Create(True) or
/// OwnsObjects := True), when the file frees its Objects[] or hands the list to a Free/Clear/Destroy/Dispose/Release
/// routine, and for a local that is freed in the routine.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckFile (DRagLint.V151.RTLCOLL.pas)</para>
/// <para>Calls: ContainsText, DRagLint.V151.RTLCOLL.Support.Esc, DRagLint.V151.RTLCOLL.Support.Hit, DRagLint.V151.RTLCOLL.Support.IsFreshCreateExpr, DRagLint.V151.RTLCOLL.Support.IsUnownedList, DRagLint.V151.RTLCOLL.Support.SplitArgs, DRagLint.V151.RTLCOLL.Support.TScan.Body, DRagLint.V151.RTLCOLL.Support.TScan.Create, DRagLint.V151.RTLCOLL.Support.TScan.RangeIndex, SameText</para>
/// <para>Returns: nil</para>
/// <para>Complexity: 12 (cyclomatic, outer body), 45 lines (full implementation)</para>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.Esc"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.Hit"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.IsFreshCreateExpr"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.IsUnownedList"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.SplitArgs"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindStringListObjectsLeak(const AMasked: string): TArray<TRtlCollHit>;

/// <summary>stringlist-unsorted: Find, or a Duplicates assignment, on a list that is created but never sorted.</summary>
/// <param name="AMasked">Masked source.</param>
/// <returns>One hit per Find call / Duplicates assignment.</returns>
/// <remarks>
/// Silent when the file sets Sorted := True, calls Sort or CustomSort, assigns the list from another one,
/// or wraps it in a with statement.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckFile (DRagLint.V151.RTLCOLL.pas)</para>
/// <para>Calls: ContainsText, DRagLint.V151.RTLCOLL.Support.Esc, DRagLint.V151.RTLCOLL.Support.Hit, DRagLint.V151.RTLCOLL.Support.TScan.Create, DRagLint.V151.RTLCOLL.Support.TScan.CreatedIn, DRagLint.V151.RTLCOLL.Support.TScan.Qualifies, DRagLint.V151.RTLCOLL.Support.TScan.RangeIndex, DRagLint.V151.RTLCOLL.Support.TScan.ScopeText, StartsText</para>
/// <para>Returns: nil</para>
/// <para>Complexity: 11 (cyclomatic, outer body), 28 lines (full implementation)</para>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.Esc"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.Hit"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.TScan.Create"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.TScan.CreatedIn"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.TScan.Qualifies"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindStringListUnsorted(const AMasked: string): TArray<TRtlCollHit>;

/// <summary>null-compare: a comparison "= Null" or "&lt;&gt; Null" (either operand order).</summary>
/// <param name="AMasked">Masked source.</param>
/// <returns>One hit per comparison.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckFile (DRagLint.V151.RTLCOLL.pas)</para>
/// <para>Calls: ContainsText, DRagLint.V151.RTLCOLL.Support.Hit</para>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.Hit"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindNullCompare(const AMasked: string): TArray<TRtlCollHit>;

/// <summary>registry-hklm-write: a registry object rooted at HKEY_LOCAL_MACHINE that is written in the same routine,
/// or a Win32 Reg* write call given HKEY_LOCAL_MACHINE.</summary>
/// <param name="AMasked">Masked source.</param>
/// <returns>One hit per routine and registry object, at the first write.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckFile (DRagLint.V151.RTLCOLL.pas)</para>
/// <para>Calls: ContainsText, DRagLint.V151.RTLCOLL.Support.Esc, DRagLint.V151.RTLCOLL.Support.Hit, DRagLint.V151.RTLCOLL.Support.Slice, DRagLint.V151.RTLCOLL.Support.SplitRoutines</para>
/// <para>Returns: nil</para>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.Esc"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.Hit"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.Slice"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.SplitRoutines"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindRegistryHklmWrite(const AMasked: string): TArray<TRtlCollHit>;

/// <summary>Position of the first call to Random / RandomRange / RandomFrom, or -1.</summary>
/// <param name="AMasked">Masked source.</param>
/// <returns>Offset of the call, or -1 when the text has none.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckProject (DRagLint.V151.RTLCOLL.pas)</para>
/// <para>Calls: ContainsText, Copy, DRagLint.V151.RTLCOLL.Support.InSet</para>
/// <para>Returns: -1; M.Index - 1</para>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.InSet"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindFirstRandomCall(const AMasked: string): Integer;

/// <summary>True when the masked text calls Randomize or assigns RandSeed.</summary>
/// <param name="AMasked">Masked source.</param>
/// <returns><!-- drag-lint:auto type -->Boolean</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckProject (DRagLint.V151.RTLCOLL.pas)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SeedsRandom(const AMasked: string): Boolean;

/// <summary>now-for-elapsed-time: Now (or Time) taken into a local and subtracted from a later Now in the same routine.</summary>
/// <param name="AMasked">Masked source.</param>
/// <returns>One hit per elapsed-time computation.</returns>
/// <remarks>
/// Covers "Now - Start" and the DateUtils *Between(Now, Start) family. Both operands must be in one routine,
/// so an age computation against a stored timestamp stays silent.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.RTLCOLL.TV151RTLCOLLRules.CheckFile (DRagLint.V151.RTLCOLL.pas)</para>
/// <para>Calls: ContainsText, DRagLint.V151.RTLCOLL.Support.Esc, DRagLint.V151.RTLCOLL.Support.Hit, DRagLint.V151.RTLCOLL.Support.Slice, DRagLint.V151.RTLCOLL.Support.SplitRoutines, LowerCase, SameText</para>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.Esc"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.Hit"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.Slice"/>
/// <seealso cref="DRagLint.V151.RTLCOLL.Support.SplitRoutines"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindNowForElapsedTime(const AMasked: string): TArray<TRtlCollHit>;

implementation

uses
  DRagLint.Core.Encoding, System.IOUtils
  , System.StrUtils
  , System.RegularExpressions
  , System.Character
  ;

const
  DICT_TYPES : array[0..3] of string = ('tdictionary', 'tobjectdictionary', 'tsorteddictionary', 'idictionary');
  SL_TYPES   : array[0..1] of string = ('tstringlist', 'thashedstringlist');
  IDENT      = '[A-Za-z_]\w*';
  COMPOUND_OP_LEN = 3; // length of "+=" "-=" "*=" "/=" plus the char after


function MaskSource(const ASrc: string): string;
var
  I, N, J: Integer;
  Buf: TArray<Char>;
begin
  N:= Length(ASrc);
  SetLength(Buf, N);
  I:= 0;
  while I < N do
  begin
    var C: Char:= ASrc[I + 1];
    if (C = '/') and (I + 1 < N) and (ASrc[I + 2] = '/') then
    begin
      while (I < N) and (ASrc[I + 1] <> #10) and (ASrc[I + 1] <> #13) do
      begin
        Buf[I]:= ' ';
        Inc(I);
      end;
    end
    else if C = '{' then
    begin
      while (I < N) and (ASrc[I + 1] <> '}') do
      begin
        Buf[I]:= if (ASrc[I + 1] = #10) or (ASrc[I + 1] = #13) then ASrc[I + 1] else ' ';
        Inc(I);
      end;
      if I < N then
      begin
        Buf[I]:= ' ';
        Inc(I);
      end;
    end
    else if (C = '(') and (I + 1 < N) and (ASrc[I + 2] = '*') then
    begin
      Buf[I]:= ' ';
      Buf[I + 1]:= ' ';
      Inc(I, 2);
      while (I < N) and not ((ASrc[I + 1] = '*') and (I + 1 < N) and (ASrc[I + 2] = ')')) do
      begin
        Buf[I]:= if (ASrc[I + 1] = #10) or (ASrc[I + 1] = #13) then ASrc[I + 1] else ' ';
        Inc(I);
      end;
      for J:= 0 to 1 do
        if I < N then
        begin
          Buf[I]:= ' ';
          Inc(I);
        end;
    end
    else if C = '''' then
    begin
      Buf[I]:= '''';
      Inc(I);
      while I < N do
      begin
        if ASrc[I + 1] = '''' then
        begin
          if (I + 1 < N) and (ASrc[I + 2] = '''') then
          begin
            Buf[I]:= ' ';
            Buf[I + 1]:= ' ';
            Inc(I, 2);
            Continue;
          end;
          Buf[I]:= '''';
          Inc(I);
          Break;
        end;
        if (ASrc[I + 1] = #10) or (ASrc[I + 1] = #13) then
        begin
          Buf[I]:= ASrc[I + 1];
          Inc(I);
          Break; // unterminated literal ends at the line end
        end;
        Buf[I]:= ' ';
        Inc(I);
      end;
    end
    else
    begin
      Buf[I]:= C;
      Inc(I);
    end;
  end;
  SetString(Result, PChar(Buf), N);
end;

/// <summary>Splits masked source into routine ranges by the column-0 routine keyword convention.</summary>
/// <param name="AMasked">Output of <see cref="MaskSource"/>.</param>
/// <returns>The text before the first routine, then one range per routine header up to the next header,
/// initialization, finalization or the final "end.".</returns>
function SplitRoutines(const AMasked: string): TArray<TRtlRange>;
var
  Starts: TList<Integer>;
begin
  Starts:= TList<Integer>.Create;
  try
    var Re: TRegEx:= TRegEx.Create('^(?:class\s+)?(?:procedure|function|constructor|destructor|operator|initialization|finalization)\b|^end\.',
      [roMultiLine, roIgnoreCase]);
    for var M: TMatch in Re.Matches(AMasked) do
      Starts.Add(M.Index - 1);
    SetLength(Result, Starts.Count + 1);
    var Prev: Integer:= 0;
    for var K:= 0 to Starts.Count - 1 do
    begin
      Result[K].First:= Prev;
      Result[K].Last := Starts[K];
      Prev:= Starts[K];
    end;
    Result[Starts.Count].First:= Prev;
    Result[Starts.Count].Last := Length(AMasked);
  finally
    Starts.Free;
  end;
end;

procedure OffsetToLineCol(const AMasked: string; AOffset: Integer; out ALine, ACol: Integer);
begin
  ALine:= 1;
  var LineStart: Integer:= 0;
  var Lim: Integer:= AOffset;
  if Lim > Length(AMasked) then Lim:= Length(AMasked);
  for var I:= 0 to Lim - 1 do
    if AMasked[I + 1] = #10 then
    begin
      Inc(ALine);
      LineStart:= I + 1;
    end;
  ACol:= AOffset - LineStart + 1;
end;

function ReadSourceText(const APath: string): string;
begin
  try
    Result:= ReadSourceFileText(APath);
  except
    on E: EInOutError do Result:= '';
    on E: EFOpenError do Result:= '';
    on E: EArgumentException do Result:= '';
  end;
end;

{ ---------------------------------------------------------------- helpers }

function Hit(const ARule: string; AOffset, ALength: Integer; const AMsg: string): TRtlCollHit;
begin
  Result.Rule  := ARule;
  Result.Offset:= AOffset;
  Result.Length:= ALength;
  Result.Msg   := AMsg;
end;

function InSet(const AName: string; const ASet: array of string): Boolean;
begin
  Result:= False;
  for var S: string in ASet do
    if SameText(S, AName) then Exit(True);
end;

{ Last dotted segment of a type name ("System.Generics.Collections.TDictionary" -> "TDictionary"). }
function BaseTypeName(const AType: string): string;
begin
  var P: Integer:= LastDelimiter('.', AType);
  Result:= if P > 0 then Copy(AType, P + 1, MaxInt) else AType;
end;

{ Offset just past the ")" / "]" that closes the bracket opened at AOpen (a "(" or "["); -1 when unbalanced. }
function MatchClose(const AText: string; AOpen: Integer): Integer;
begin
  Result:= -1;
  var Depth: Integer:= 0;
  for var I:= AOpen to Length(AText) - 1 do
    case AText[I + 1] of
      '(', '[': Inc(Depth);
      ')', ']':
        begin
          Dec(Depth);
          if Depth = 0 then Exit(I + 1);
        end;
    end;
end;

{ Top-level comma-separated arguments between AOpen (the bracket) and its close. }
function SplitArgs(const AText: string; AOpen: Integer): TArray<string>;
begin
  Result:= nil;
  var Close: Integer:= MatchClose(AText, AOpen);
  if Close < 0 then Exit;
  var Depth: Integer:= 0;
  var Start: Integer:= AOpen + 1;
  for var I:= AOpen + 1 to Close - 2 do
    case AText[I + 1] of
      '(', '[': Inc(Depth);
      ')', ']': Dec(Depth);
      ',': if Depth = 0 then
           begin
             Result:= Result + [Trim(Copy(AText, Start + 1, I - Start))];
             Start:= I + 1;
           end;
    end;
  Result:= Result + [Trim(Copy(AText, Start + 1, Close - 1 - Start))];
end;

function Slice(const AText: string; const ARange: TRtlRange): string;
begin
  var Last: Integer:= ARange.Last;
  if Last > Length(AText) then Last:= Length(AText);
  Result:= Copy(AText, ARange.First + 1, Last - ARange.First);
end;

function Esc(const AName: string): string;
begin
  Result:= TRegEx.Escape(AName);
end;

type
  { 1.52 BUDGET: candidate start positions (1-based, ascending) of a TScan pattern for one occurrence of its anchor literal. }
  TStartsFn = reference to function(const AText: string; AAnchor: Integer): TArray<Integer>;

{ TScan's patterns all start with the lookbehind (?<![\w.]), which defeats PCRE's start
  optimisation: the pattern is tried at every position of a 1 MB unit (350 ms per TScan, three
  TScans per file). Every match of them contains a fixed literal (the '=' of an alias, the ':='
  of a creation, the ':' of a declaration) at a place the text before it determines, so the
  candidates are found from that literal: for each occurrence AStarts walks back to the start
  positions a match could have (ascending), and a \G-anchored copy of the same pattern is tried
  there. Taken leftmost first, never before the end of the previous match, this gives the matches
  TRegEx.Matches gives, in its order. Text that is not plain ASCII (where \w may mean more) takes
  the full scan. }

function IsWordChar(C: Char): Boolean; inline;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function IsBlank(C: Char): Boolean; inline;
begin
  Result:= CharInSet(C, [#9, #10, #11, #12, #13, ' ']);
end;

function IsAsciiText(const AText: string): Boolean;
const
  MAX_ASCII = 127;
begin
  for var C: Char in AText do
    if Ord(C) > MAX_ASCII then Exit(False);
  Result:= True;
end;

function AnchoredMatches(const AText, APattern, AAnchor: string; const AStarts: TStartsFn): TArray<TMatch>;
begin
  Result:= nil;
  if not IsAsciiText(AText) then
  begin
    for var M: TMatch in TRegEx.Matches(AText, APattern, [roIgnoreCase]) do Result:= Result + [M];
    Exit;
  end;
  var Anchored: TRegEx:= TRegEx.Create('\G(?:' + APattern + ')', [roIgnoreCase]);
  var NextAllowed: Integer:= 1;
  var Q: Integer:= PosEx(AAnchor, AText, 1);
  while Q > 0 do
  begin
    for var S: Integer in AStarts(AText, Q) do
      if S >= NextAllowed then
      begin
        var M: TMatch:= Anchored.Match(AText, S);
        if M.Success and (M.Index = S) then
        begin
          Result:= Result + [M];
          NextAllowed:= M.Index + M.Length;
          Break;
        end;
      end;
    Q:= PosEx(AAnchor, AText, Q + 1);
  end;
end;

{ Start of the word that ends at AEnd (1-based, inclusive), or 0 when AText[AEnd] is no word char. }
function WordStart(const AText: string; AEnd: Integer): Integer;
begin
  if (AEnd < 1) or not IsWordChar(AText[AEnd]) then Exit(0);
  Result:= AEnd;
  while (Result > 1) and IsWordChar(AText[Result - 1]) do Dec(Result);
end;

{ Last non-blank position before AFrom, or 0. }
function SkipBlanksBack(const AText: string; AFrom: Integer): Integer;
begin
  Result:= AFrom - 1;
  while (Result >= 1) and IsBlank(AText[Result]) do Dec(Result);
end;

{ IDENT \s* <anchor>: the word right before the anchor. }
function WordStartsBefore(const AText: string; AAnchor: Integer): TArray<Integer>;
begin
  var W: Integer:= WordStart(AText, SkipBlanksBack(AText, AAnchor));
  Result:= if W > 0 then [W] else nil;
end;

{ (?:Self \s* . \s*)? IDENT \s* <anchor>: the 'Self' of a 'Self . name' first, then the name. }
function SelfOrWordStartBefore(const AText: string; AAnchor: Integer): TArray<Integer>;
const
  SELF_WORD = 'self';
begin
  Result:= nil;
  var W: Integer:= WordStart(AText, SkipBlanksBack(AText, AAnchor));
  if W = 0 then Exit;
  Result:= [W];
  var P: Integer:= SkipBlanksBack(AText, W);
  if (P < 1) or (AText[P] <> '.') then Exit;
  var E: Integer:= SkipBlanksBack(AText, P);
  var S: Integer:= WordStart(AText, E);
  if (S > 0) and SameText(Copy(AText, S, E - S + 1), SELF_WORD) then Result:= [S, W];
end;

{ IDENT (?:\s*,\s* IDENT)* \s* <anchor>: every word of the comma list before the anchor, first word first. }
function ListStartsBefore(const AText: string; AAnchor: Integer): TArray<Integer>;
begin
  Result:= nil;
  var W: Integer:= WordStart(AText, SkipBlanksBack(AText, AAnchor));
  while W > 0 do
  begin
    Result:= [W] + Result;
    var P: Integer:= SkipBlanksBack(AText, W);
    if (P < 1) or (AText[P] <> ',') then Break;
    W:= WordStart(AText, SkipBlanksBack(AText, P));
  end;
end;
type
  { One file, scanned once per rule family: routine ranges, the type names that count as a target (the
    given ones plus aliases / descendants declared in the file) and the declaration facts.
    A name declared INSIDE a routine (parameter or local) is judged by that routine alone; any other name
    (field, global) by the whole file. }
  TScan = class
  strict private
    FLocal: TObjectDictionary<Integer, TDictionary<string, Boolean>>;
    FMasked    : string;
    FRanges    : TArray<TRtlRange>;
    FTargets   : TList<string>;
    FGlobalDecl: TDictionary<string, Boolean>; // name -> every "name: Type" in the pre-routine text is a target
    FCreated   : TDictionary<string, Boolean>; // name -> assigned "Target.Create" / "Target<...>" anywhere in the file
    function DeclMap(const AText: string): TDictionary<string, Boolean>;
  public
    constructor Create(const AMasked: string; const ATargets: array of string);
    property Masked: string read FMasked;
    property Ranges: TArray<TRtlRange> read FRanges;
    property Targets: TList<string> read FTargets;
    property GlobalDecl: TDictionary<string, Boolean> read FGlobalDecl;
    property Created: TDictionary<string, Boolean> read FCreated;
    destructor Destroy; override;
    function Body(AIdx: Integer): string;
    function RangeIndex(AOffset: Integer): Integer;
    function IsLocal(AIdx: Integer; const AName: string): Boolean;
    function Qualifies(AIdx: Integer; const AName: string): Boolean;
    function ScopeText(AIdx: Integer; const AName: string): string;
    function CreatedIn(AIdx: Integer; const AName: string): Boolean;
  end;

constructor TScan.Create(const AMasked: string; const ATargets: array of string);
begin
  inherited Create;
  FMasked:= AMasked;
  FRanges:= SplitRoutines(AMasked);
  FTargets:= TList<string>.Create;
  FLocal:= TObjectDictionary<Integer, TDictionary<string, Boolean>>.Create([doOwnsValues]);
  FCreated:= TDictionary<string, Boolean>.Create;
  for var T: string in ATargets do FTargets.Add(LowerCase(T));
  // aliases and descendants: TFoo = TDictionary<..>;  TFoo = class(TDictionary<..>);  TBar = TFoo;
  // (1.52 BUDGET: both patterns run anchored on their literal, see AnchoredMatches; the alias
  // matches are the same in both passes, so they are found once)
  var Aliases: TArray<TMatch>:= AnchoredMatches(AMasked,
    '(?<![\w.])(' + IDENT + ')\s*=\s*(?:class\s*\(\s*)?([\w.]+)\s*(?:<|[;)])', '=', WordStartsBefore);
  for var Pass:= 1 to 2 do
    for var M: TMatch in Aliases do
      if FTargets.Contains(LowerCase(BaseTypeName(M.Groups[2].Value))) and
         not FTargets.Contains(LowerCase(M.Groups[1].Value)) then
        FTargets.Add(LowerCase(M.Groups[1].Value));
  FGlobalDecl:= DeclMap(Slice(AMasked, FRanges[0]));
  // creations "Name := Target<..>.Create" / "Name := Target.Create"
  for var M: TMatch in AnchoredMatches(AMasked,
      '(?<![\w.])(?:Self\s*\.\s*)?(' + IDENT + ')\s*:=\s*(' + IDENT + '(?:\.' + IDENT + ')*?)\s*(?:<|\.\s*Create\b)', ':=',
      SelfOrWordStartBefore) do
    if FTargets.Contains(LowerCase(BaseTypeName(M.Groups[2].Value))) then
      FCreated.AddOrSetValue(LowerCase(M.Groups[1].Value), True);
end;

destructor TScan.Destroy;
begin
  FGlobalDecl.Free;
  FCreated.Free;
  FLocal.Free;
  FTargets.Free;
  inherited Destroy;
end;

function TScan.DeclMap(const AText: string): TDictionary<string, Boolean>;
begin
  Result:= TDictionary<string, Boolean>.Create;
  for var M: TMatch in AnchoredMatches(AText,
      '(?<![\w.])(' + IDENT + '(?:\s*,\s*' + IDENT + ')*)\s*:(?!=)\s*(' + IDENT + '(?:\.' + IDENT + ')*)', ':', ListStartsBefore) do
  begin
    var IsTarget: Boolean:= FTargets.Contains(LowerCase(BaseTypeName(M.Groups[2].Value)));
    for var Nm: string in M.Groups[1].Value.Split([',']) do
    begin
      var L: string:= LowerCase(Trim(Nm));
      var Old: Boolean;
      if Result.TryGetValue(L, Old) then Result[L]:= Old and IsTarget
      else Result.Add(L, IsTarget);
    end;
  end;
end;

function TScan.Body(AIdx: Integer): string;
begin
  Result:= Slice(FMasked, FRanges[AIdx]);
end;

function TScan.RangeIndex(AOffset: Integer): Integer;
begin
  Result:= 0;
  for var I:= 0 to High(FRanges) do
    if (AOffset >= FRanges[I].First) and (AOffset < FRanges[I].Last) then Exit(I);
end;

function TScan.IsLocal(AIdx: Integer; const AName: string): Boolean;
var
  Map: TDictionary<string, Boolean>;
begin
  if AIdx = 0 then Exit(False);
  if not FLocal.TryGetValue(AIdx, Map) then
  begin
    Map:= DeclMap(Body(AIdx));
    FLocal.Add(AIdx, Map);
  end;
  Result:= Map.ContainsKey(LowerCase(AName));
end;

function TScan.Qualifies(AIdx: Integer; const AName: string): Boolean;
var
  Map: TDictionary<string, Boolean>;
  Flag: Boolean;
begin
  var L: string:= LowerCase(AName);
  if IsLocal(AIdx, AName) then
  begin
    Result:= FLocal.TryGetValue(AIdx, Map) and Map.TryGetValue(L, Flag) and Flag;
    Exit;
  end;
  if FGlobalDecl.TryGetValue(L, Flag) then Exit(Flag);
  Result:= CreatedIn(AIdx, AName);
end;

function TScan.ScopeText(AIdx: Integer; const AName: string): string;
begin
  Result:= if IsLocal(AIdx, AName) then Body(AIdx) else FMasked;
end;
function TScan.CreatedIn(AIdx: Integer; const AName: string): Boolean;
begin
  if (not IsLocal(AIdx, AName)) and FGlobalDecl.ContainsKey(LowerCase(AName)) then Exit(FCreated.ContainsKey(LowerCase(AName)));
  Result:= TRegEx.IsMatch(Body(AIdx), '(?<![\w.])(?:Self\s*\.\s*)?' + Esc(AName) + '\s*:=\s*(?:\w+\s*\.\s*)*(?:' + string.Join('|', FTargets.ToArray) + ')\b', [roIgnoreCase]);
end;

{ ------------------------------------------------- dictionary-get-without-check }

{ Index (1-based) and length of every match of APattern -- '(?<![\w.])(?:Self\s*\.\s*)?<name>...' -- in
  AMasked, in the order TRegEx.Matches would give them. A match always contains <name>, so only its
  occurrences (found by literal search in ALower) and a 'Self.' just before them are tried, each with a
  \G-anchored copy of the pattern, instead of running the pattern at every position of the file; a name
  that is not plain ASCII falls back to TRegEx.Matches. }
function NameMatches(const AMasked, ALower, AName, APattern: string): TArray<TPair<Integer, Integer>>;
const
  MAX_ASCII = 127;
  SELF_WORD = 'self';
begin
  Result:= nil;
  var Ascii: Boolean:= AName <> '';
  for var C: Char in AName do
    if Ord(C) > MAX_ASCII then Ascii:= False;
  if not Ascii then
  begin
    for var M: TMatch in TRegEx.Matches(AMasked, APattern, [roIgnoreCase]) do
      Result:= Result + [TPair<Integer, Integer>.Create(M.Index, M.Length)];
    Exit;
  end;
  var Anchored: TRegEx:= TRegEx.Create('\G' + APattern, [roIgnoreCase]);
  var NextAllowed: Integer:= 1;
  var Q: Integer:= PosEx(LowerCase(AName), ALower, 1);
  while Q > 0 do
  begin
    { candidate starts, leftmost first: the 'Self' of a 'Self . name', then the name itself }
    var Starts: TArray<Integer>:= [Q];
    var P: Integer:= Q - 1;
    while (P >= 1) and ((AMasked[P] <= ' ') or AMasked[P].IsWhiteSpace) do Dec(P);
    if (P >= 1) and (AMasked[P] = '.') then
    begin
      Dec(P);
      while (P >= 1) and ((AMasked[P] <= ' ') or AMasked[P].IsWhiteSpace) do Dec(P);
      if (P >= Length(SELF_WORD)) and (Copy(ALower, P - Length(SELF_WORD) + 1, Length(SELF_WORD)) = SELF_WORD) then
        Starts:= [P - Length(SELF_WORD) + 1, Q];
    end;
    var Found: Boolean:= False;
    for var S: Integer in Starts do
      if (not Found) and (S >= NextAllowed) then
      begin
        var M: TMatch:= Anchored.Match(AMasked, S);
        if M.Success and (M.Index = S) then
        begin
          Result:= Result + [TPair<Integer, Integer>.Create(M.Index, M.Length)];
          NextAllowed:= M.Index + M.Length;
          Found:= True;
        end;
      end;
    Q:= PosEx(LowerCase(AName), ALower, Q + 1);
  end;
end;

function FindDictionaryGetWithoutCheck(const AMasked: string): TArray<TRtlCollHit>;
var
  Scan: TScan;
  Names: TList<string>;
  Reported: TList<string>;
begin
  Result:= nil;
  if not (ContainsText(AMasked, 'Dictionary') and ContainsText(AMasked, '[')) then Exit;
  Scan:= TScan.Create(AMasked, DICT_TYPES);
  Names:= TList<string>.Create;
  Reported:= TList<string>.Create;
  try
    // candidate names: every declared name of a target type, plus names created as one (inline var)
    for var P in Scan.Created do
      if not Names.Contains(P.Key) then Names.Add(P.Key);
    for var P in Scan.GlobalDecl do
      if P.Value and not Names.Contains(P.Key) then Names.Add(P.Key);
    // locals / parameters declared as a dictionary in some routine
    var ReDecl: TRegEx:= TRegEx.Create('(?<![\w.])(' + IDENT + '(?:\s*,\s*' + IDENT + ')*)\s*:(?!=)\s*(' + IDENT + '(?:\.' + IDENT + ')*)', [roIgnoreCase]);
    for var M: TMatch in ReDecl.Matches(AMasked) do
      if Scan.Targets.Contains(LowerCase(BaseTypeName(M.Groups[2].Value))) then
        for var Nm: string in M.Groups[1].Value.Split([',']) do
          if not Names.Contains(LowerCase(Trim(Nm))) then Names.Add(LowerCase(Trim(Nm)));
    var Lower: string:= LowerCase(AMasked);
    for var Nm: string in Names do
    begin
      var N: string:= Esc(Nm);
      for var M: TPair<Integer, Integer> in NameMatches(AMasked, Lower, Nm, '(?<![\w.])(?:Self\s*\.\s*)?' + N + '\s*(?:\.\s*Items\s*)?\[') do
      begin
        var Open: Integer:= M.Key - 1 + M.Value - 1;
        var Close: Integer:= MatchClose(AMasked, Open);
        if Close < 0 then Continue;
        // a write target is not a read
        var After: Integer:= Close;
        while (After < Length(AMasked)) and CharInSet(AMasked[After + 1], [' ', #9, #13, #10]) do Inc(After);
        if Copy(AMasked, After + 1, 2) = ':=' then Continue;
        if TRegEx.IsMatch(Copy(AMasked, After + 1, COMPOUND_OP_LEN), '^(\+|-|\*|/)=') then Continue;
        var Idx: Integer:= Scan.RangeIndex(M.Key - 1);
        if not Scan.Qualifies(Idx, Nm) then Continue;
        var Body: string:= Scan.Body(Idx);
        var Before: string:= Copy(Body, 1, M.Key - 1 - Scan.Ranges[Idx].First);
        if TRegEx.IsMatch(Body, '(?<![\w.])(?:Self\s*\.\s*)?' + N + '\s*\.\s*(ContainsKey|TryGetValue|TryAdd|ExtractPair|Keys|Values|ToArray)\b', [roIgnoreCase]) then Continue;
        if TRegEx.IsMatch(Body, '\bin\s+(?:Self\s*\.\s*)?' + N + '\b', [roIgnoreCase]) then Continue;
        if TRegEx.IsMatch(Before, '(?<![\w.])(?:Self\s*\.\s*)?' + N + '\s*\.\s*(Add|AddOrSetValue)\s*\(', [roIgnoreCase]) then Continue;
        if TRegEx.IsMatch(Body, '\b(EKeyNotFoundException|EListError|EArgumentOutOfRangeException)\b', [roIgnoreCase]) then Continue;
        if TRegEx.IsMatch(Before, '\bproperty\s+' + N + '\b', [roIgnoreCase]) then Continue;
        // one finding per routine and dictionary: the same unguarded pattern repeated adds noise, not information
        var Key: string:= IntToStr(Idx) + '|' + LowerCase(Nm);
        if Reported.Contains(Key) then Continue;
        Reported.Add(Key);
        Result:= Result + [Hit(RULE_DICT_GET, M.Key - 1, Close - (M.Key - 1),
          'Dictionary read ' + Trim(Copy(AMasked, M.Key, Close - M.Key + 1)) +
          ' raises EListError / EKeyNotFoundException when the key is missing, and no ContainsKey / TryGetValue guards it in this routine -- use TryGetValue, or ContainsKey first')];
      end;
    end;
  finally
    Reported.Free;
    Names.Free;
    Scan.Free;
  end;
end;

{ ---------------------------------------------------- stringlist-objects-leak }

function IsFreshCreateExpr(const AArg: string): Boolean;
begin
  var S: string:= Trim(AArg);
  var Cast: TMatch:= TRegEx.Match(S, '^(?:TObject|Pointer|' + IDENT + ')\s*\((.*)\)$', [roIgnoreCase, roSingleLine]);
  if Cast.Success and TRegEx.IsMatch(Cast.Groups[1].Value, '^\s*[Tt]\w*(?:\.\w+)*\.Create\b') then S:= Trim(Cast.Groups[1].Value);
  Result:= TRegEx.IsMatch(S, '^[Tt]\w*(?:\.\w+)*\.Create\b');
end;

{ True when the list's ownership of its objects is shown in the name's scope. }
function OwnsOrFrees(const AScan: TScan; AIdx: Integer; const AName: string): Boolean;
begin
  var Sc: string:= AScan.ScopeText(AIdx, AName);
  var N: string:= Esc(AName);
  Result:=
    TRegEx.IsMatch(Sc, '(?<![\w.])(?:Self\s*\.\s*)?' + N + '\s*\.\s*OwnsObjects\s*:=\s*True\b', [roIgnoreCase]) or
    TRegEx.IsMatch(Sc, '(?<![\w.])(?:Self\s*\.\s*)?' + N + '\s*:=\s*\w*(?:TStringList|THashedStringList)\s*\.\s*Create\s*\(\s*True\b', [roIgnoreCase]) or
    TRegEx.IsMatch(Sc, '(?:Free|FreeAndNil|Destroy|Dispose|Release|Clear\w*|Free\w*)\s*\(\s*[^;]*\b' + N + '\s*\.\s*Objects\s*\[', [roIgnoreCase]) or
    TRegEx.IsMatch(Sc, '\b' + N + '\s*\.\s*Objects\s*\[[^\]]*\]\s*(?:as\s+\w+\s*\))?\s*\.\s*(Free|Destroy)\b', [roIgnoreCase]) or
    TRegEx.IsMatch(Sc, '\b(?:Free|Clear|Destroy|Dispose|Release|Cleanup|Empty)\w*\s*\(\s*(?:Self\s*\.\s*)?' + N + '\b', [roIgnoreCase]);
end;

{ True when AName is a string list created in its scope whose objects nothing owns or frees. }
function IsUnownedList(const AScan: TScan; AOffset: Integer; const AName: string): Boolean;
begin
  var Idx: Integer:= AScan.RangeIndex(AOffset);
  Result:= AScan.Qualifies(Idx, AName) and AScan.CreatedIn(Idx, AName) and not OwnsOrFrees(AScan, Idx, AName);
end;

function FindStringListObjectsLeak(const AMasked: string): TArray<TRtlCollHit>;
var
  Scan: TScan;
begin
  Result:= nil;
  if not (ContainsText(AMasked, 'AddObject') or ContainsText(AMasked, 'InsertObject') or ContainsText(AMasked, 'Objects[')) then Exit;
  Scan:= TScan.Create(AMasked, SL_TYPES);
  try
    var Re: TRegEx:= TRegEx.Create('(?<![\w.])(?:Self\s*\.\s*)?(' + IDENT + ')\s*\.\s*(AddObject|InsertObject)\s*\(', [roIgnoreCase]);
    for var M: TMatch in Re.Matches(AMasked) do
    begin
      var Nm: string:= M.Groups[1].Value;
      var Idx: Integer:= Scan.RangeIndex(M.Index - 1);
      if not IsUnownedList(Scan, M.Index - 1, Nm) then Continue;
      var Open: Integer:= M.Index - 1 + M.Length - 1;
      var Args: TArray<string>:= SplitArgs(AMasked, Open);
      var ObjIdx: Integer:= if SameText(M.Groups[2].Value, 'InsertObject') then 2 else 1;
      if Length(Args) <= ObjIdx then Continue;
      var Obj: string:= Args[ObjIdx];
      var Fresh: Boolean:= IsFreshCreateExpr(Obj);
      if not Fresh and TRegEx.IsMatch(Obj, '^' + IDENT + '$') then
      begin
        var Body: string:= Scan.Body(Idx);
        var V: string:= Esc(Obj);
        Fresh:= TRegEx.IsMatch(Body, '(?<![\w.])' + V + '\s*:=\s*[Tt]\w*(?:\.\w+)*\.Create\b', [roIgnoreCase]) and
          not TRegEx.IsMatch(Body, '(?:\b' + V + '\s*\.\s*(Free|Destroy)\b|\b(?:FreeAndNil|Free\w*)\s*\(\s*' + V + '\b)', [roIgnoreCase]);
      end;
      if Fresh then
        Result:= Result + [Hit(RULE_SL_LEAK, M.Index - 1, Length(Nm) + 1 + Length(M.Groups[2].Value),
          'The new object stored by ' + M.Groups[2].Value + ' is never freed: ' + Nm +
          ' does not own its objects -- create the list with TStringList.Create(True) (OwnsObjects) or free the objects yourself')];
    end;
    // Name.Objects[i] := TFoo.Create(...)
    var ReSet: TRegEx:= TRegEx.Create('(?<![\w.])(?:Self\s*\.\s*)?(' + IDENT + ')\s*\.\s*Objects\s*\[[^\]]*\]\s*:=\s*([Tt]\w*(?:\.\w+)*\.Create\b)', [roIgnoreCase]);
    for var M: TMatch in ReSet.Matches(AMasked) do
    begin
      var Nm: string:= M.Groups[1].Value;
      if not IsUnownedList(Scan, M.Index - 1, Nm) then Continue;
      Result:= Result + [Hit(RULE_SL_LEAK, M.Index - 1, M.Length,
        'The object assigned to ' + Nm + '.Objects[] is never freed: ' + Nm +
        ' does not own its objects -- create the list with TStringList.Create(True) (OwnsObjects) or free the objects yourself')];
    end;
  finally
    Scan.Free;
  end;
end;

{ ------------------------------------------------------- stringlist-unsorted }

function FindStringListUnsorted(const AMasked: string): TArray<TRtlCollHit>;
var
  Scan: TScan;
begin
  Result:= nil;
  if not (ContainsText(AMasked, 'StringList') and (ContainsText(AMasked, '.Find') or ContainsText(AMasked, 'Duplicates'))) then Exit;
  Scan:= TScan.Create(AMasked, SL_TYPES);
  try
    var Re: TRegEx:= TRegEx.Create('(?<![\w.])(?:Self\s*\.\s*)?(' + IDENT + ')\s*\.\s*(Find\s*\(|Duplicates\s*:=)', [roIgnoreCase]);
    for var M: TMatch in Re.Matches(AMasked) do
    begin
      var Nm: string:= M.Groups[1].Value;
      var Idx: Integer:= Scan.RangeIndex(M.Index - 1);
      if not (Scan.Qualifies(Idx, Nm) and Scan.CreatedIn(Idx, Nm)) then Continue;
      var Sc: string:= Scan.ScopeText(Idx, Nm);
      var N: string:= '(?<![\w.])(?:Self\s*\.\s*)?' + Esc(Nm);
      if TRegEx.IsMatch(Sc, N + '\s*\.\s*Sorted\s*:=\s*True\b', [roIgnoreCase]) then Continue;
      if TRegEx.IsMatch(Sc, N + '\s*\.\s*(Sort|CustomSort|Assign)\b', [roIgnoreCase]) then Continue;
      if TRegEx.IsMatch(Sc, '\bwith\s+[^;]*\b' + Esc(Nm) + '\b[^;]*\bdo\b', [roIgnoreCase]) then Continue;
      var IsFind: Boolean:= StartsText('Find', M.Groups[2].Value);
      Result:= Result + [Hit(RULE_SL_UNSORTED, M.Index - 1, M.Length - (if IsFind then 1 else 2),
        if IsFind then
          Nm + '.Find searches binary but ' + Nm + ' is never sorted (no Sorted := True, Sort or CustomSort in its scope) -- the result is wrong on unsorted data; set Sorted := True, call Sort first, or use IndexOf'
        else
          'Duplicates has no effect: ' + Nm + ' is never sorted (no Sorted := True in its scope) and TStringList applies Duplicates only to sorted lists')];    end;
  finally
    Scan.Free;
  end;
end;

{ ---------------------------------------------------------------- null-compare }

function FindNullCompare(const AMasked: string): TArray<TRtlCollHit>;
const
  MSG = 'Comparison with Null: the result depends on System.Variants.NullEqualityRule and is not a reliable null test -- use VarIsNull(X) or X.IsNull';
begin
  Result:= nil;
  if not ContainsText(AMasked, 'Null') then Exit;
  begin
    var Re1: TRegEx:= TRegEx.Create('(?<![:<>=!])(=|<>)\s*(?:(?:System\s*\.\s*)?Variants\s*\.\s*)?Null\b(?!\s*\.)', [roIgnoreCase]);
    for var M: TMatch in Re1.Matches(AMasked) do
    begin
      Result:= Result + [Hit(RULE_NULL_COMPARE, M.Index - 1, M.Length, MSG)];
    end;
    var Re2: TRegEx:= TRegEx.Create('(?<![\w.])Null\s*(=|<>)(?![=])', [roIgnoreCase]);
    for var M: TMatch in Re2.Matches(AMasked) do
      Result:= Result + [Hit(RULE_NULL_COMPARE, M.Index - 1, M.Length, MSG)];
  end;
end;

{ ---------------------------------------------------------- registry-hklm-write }

function FindRegistryHklmWrite(const AMasked: string): TArray<TRtlCollHit>;
const
  WRITES = 'WriteString|WriteInteger|WriteBool|WriteExpandString|WriteBinaryData|WriteFloat|WriteDate|WriteDateTime|WriteTime|WriteCurrency|CreateKey|DeleteKey|DeleteValue|RenameValue|SaveKey|RestoreKey|RegisterKey';
  WINAPI = 'RegCreateKeyEx|RegCreateKey|RegSetValueEx|RegSetValue|RegSetKeyValue|RegDeleteKey|RegDeleteKeyEx|RegDeleteValue|RegDeleteKeyValue';
begin
  Result:= nil;
  if not ContainsText(AMasked, 'HKEY_LOCAL_MACHINE') then Exit;
  for var R: TRtlRange in SplitRoutines(AMasked) do
  begin
    var Body: string:= Slice(AMasked, R);
    if not ContainsText(Body, 'HKEY_LOCAL_MACHINE') then Continue;
    // TRegistry objects rooted at HKLM
    var ReRoot: TRegEx:= TRegEx.Create('(?<![\w.])((?:' + IDENT + '\s*\.\s*)?)RootKey\s*:=\s*(?:\w+\s*\.\s*)*HKEY_LOCAL_MACHINE\b', [roIgnoreCase]);
    for var M: TMatch in ReRoot.Matches(Body) do
    begin
      var Obj: string:= TRegEx.Replace(M.Groups[1].Value, '\s*\.\s*$', '');
      var Pfx: string:= if Obj = '' then '(?<![\w.])' else '(?<![\w.])' + Esc(Obj) + '\s*\.\s*';
      var ReWrite: TRegEx:= TRegEx.Create(Pfx + '(?:(' + WRITES + ')\s*\(|OpenKey\s*\([^;]*,\s*True\s*\))', [roIgnoreCase]);
      var W: TMatch:= ReWrite.Match(Body, M.Index - 1 + M.Length);
      if not W.Success then Continue;
      var Off: Integer:= R.First + W.Index - 1;
      Result:= Result + [Hit(RULE_REG_HKLM, Off, W.Length,
        'Write below HKEY_LOCAL_MACHINE: it needs administrator rights and fails (or is virtualised) for a normal user -- write below HKEY_CURRENT_USER, or keep this in an installer / elevated helper')];
    end;
    // Win32 write calls given HKEY_LOCAL_MACHINE as the key
    var ReApi: TRegEx:= TRegEx.Create('(?<![\w.])(' + WINAPI + ')[AW]?\s*\(\s*(?:\w+\s*\.\s*)*HKEY_LOCAL_MACHINE\b', [roIgnoreCase]);
    for var M: TMatch in ReApi.Matches(Body) do
      Result:= Result + [Hit(RULE_REG_HKLM, R.First + M.Index - 1, M.Length,
        'Write below HKEY_LOCAL_MACHINE (' + M.Groups[1].Value + '): it needs administrator rights and fails (or is virtualised) for a normal user -- write below HKEY_CURRENT_USER, or keep this in an installer / elevated helper')];
  end;
end;

{ ------------------------------------------------------- random-without-randomize }

function FindFirstRandomCall(const AMasked: string): Integer;
begin
  Result:= -1;
  if not ContainsText(AMasked, 'Random') then Exit;
  var Re: TRegEx:= TRegEx.Create('(?<![\w.])(?:System\s*\.\s*)?(?:Random|RandomRange|RandomFrom)\b\s*(?=\(|;)', [roIgnoreCase]);
  for var M: TMatch in Re.Matches(AMasked) do
  begin
    // not a declaration "function Random(" and not a "Random := ..." assignment target
    var PreM: TMatch:= TRegEx.Match(Copy(AMasked, 1, M.Index - 1), '(\w+)\s*$');
    var Pre: string:= if PreM.Success then PreM.Groups[1].Value else '';
    if InSet(Pre, ['function', 'procedure', 'property', 'constructor']) then Continue;
    Exit(M.Index - 1);
  end;
end;

function SeedsRandom(const AMasked: string): Boolean;
begin
  Result:= TRegEx.IsMatch(AMasked, '(?<![\w.])(?:System\s*\.\s*)?Randomize\b', [roIgnoreCase]) or
    TRegEx.IsMatch(AMasked, '\bRandSeed\s*:=', [roIgnoreCase]);
end;

{ ------------------------------------------------------- now-for-elapsed-time }

function FindNowForElapsedTime(const AMasked: string): TArray<TRtlCollHit>;
const
  MSG = 'Elapsed time measured with Now: the wall clock jumps with daylight-saving changes and clock adjustments -- use TStopwatch (or GetTickCount64) for an interval';
begin
  Result:= nil;
  if not ContainsText(AMasked, 'Now') then Exit;
  var ReStart: TRegEx:= TRegEx.Create('(?<![\w.])(?:Self\s*\.\s*)?(' + IDENT + ')\s*:=\s*(?:System\s*\.\s*)?(?:Now|Time)\s*;', [roIgnoreCase]);
  for var R: TRtlRange in SplitRoutines(AMasked) do
  begin
    var Body: string:= Slice(AMasked, R);
    if not ContainsText(Body, 'Now') then Continue;
    var Starts: TList<string>:= TList<string>.Create;
    try
      for var M: TMatch in ReStart.Matches(Body) do
        if not Starts.Contains(LowerCase(M.Groups[1].Value)) then Starts.Add(LowerCase(M.Groups[1].Value));
      for var S: string in Starts do
      begin
        var V: string:= '(?:Self\s*\.\s*)?' + Esc(S);
        var Re: TRegEx:= TRegEx.Create('(?<![\w.])(?:Now|Time)\s*-\s*' + V + '\b|\b\w*Between\s*\(\s*(?:Now|Time)\s*,\s*' + V + '\s*\)|\b\w*Between\s*\(\s*' + V + '\s*,\s*(?:Now|Time)\s*\)',
          [roIgnoreCase]);
        // the use must come after the start assignment
        var StartOff: Integer:= 0;
        for var SM: TMatch in ReStart.Matches(Body) do
          if SameText(SM.Groups[1].Value, S) then
          begin
            StartOff:= SM.Index - 1;
            Break;
          end;
        for var U: TMatch in Re.Matches(Body, StartOff) do
          Result:= Result + [Hit(RULE_NOW_ELAPSED, R.First + U.Index - 1, U.Length, MSG)];
      end;
    finally
      Starts.Free;
    end;
  end;
end;

end.
