unit ConvRules.SkipList;

(* PURE model of the editor's "do not convert" marks and the named filters that
  set them in bulk. No UI, no engine, no file I/O -- the caller owns reading and
  writing the text; this unit only parses and emits it.

  These marks are editor BOOKKEEPING, not rules. Owner ruling 2026-09-20:
  whatever is not in a #convert is left alone, so a skipped class produces no
  directive and the engine never sees this file.

  File format (strict ASCII, CRLF):

    # ConvRulesEditor -- classes marked "do not convert".
    # Written by the editor; safe to hand-edit or diff.
    skip TLabel
    filter DevExpress = ^Tdx
    filter DevExpress = ^Tcx
    filter Standard = +std

  One regex per `filter` line, accumulating by name -- NOT a comma-separated
  list, because a regex may legitimately contain a comma ('{1,3}') and there
  would be no way to tell the two apart. `+std` is the standard-VCL/FMX flag
  rather than a pattern. Every line the parser does not recognise is preserved
  verbatim in Foreign and written back, so a hand edit is never destroyed. *)

interface

uses
  System.SysUtils
  , System.Classes
  ;

type
  /// <summary>A named group of exclusion regexes that marks classes in bulk.</summary>
  /// <remarks>
  /// Patterns are the same regexes ConvRules.FormTypes.TypeIsExcluded
  /// takes, so the matching semantics and their tests are shared. IncludeStandard
  /// is the '+std' flag: it matches types whose declaring unit is Vcl.* or FMX.*,
  /// which costs a declaring-unit resolution per type and so is applied on demand,
  /// never on a refresh.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.MainForm.TConvRulesForm.ApplyNamedFilterClick (ConvRules.MainForm.pas), ConvRules.SkipList.EmitSkipList (ConvRules.SkipList.pas), ConvRules.SkipList.MergePendingMarks (ConvRules.SkipList.pas), ConvRules.SkipList.SetNamedFilter (ConvRules.SkipList.pas), declaration (ConvRules.SkipList.pas)</para>
  /// <para>Used in units: ConvRules.MainForm, ConvRules.SkipList</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TNamedFilter = record
    Name           : string        ;
    Patterns       : TArray<string>;
    IncludeStandard: Boolean       ;
  end;

  /// <summary>The parsed skip file.</summary>
  /// <remarks>
  /// Foreign holds every unrecognised line verbatim so that emitting
  /// what was parsed is loss-free; the generated header lines are NOT foreign,
  /// or they would double on each save.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.MainForm.TConvRulesForm.LoadSkipList (ConvRules.MainForm.pas), ConvRules.SkipList.ParseSkipList (ConvRules.SkipList.pas), declaration (ConvRules.FormTypes.pas), declaration (ConvRules.MainForm.pas), declaration (ConvRules.SkipList.pas)</para>
  /// <para>Used in units: ConvRules.FormTypes, ConvRules.MainForm, ConvRules.SkipList</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSkipList = record
    Classes: TArray<string>      ;
    Filters: TArray<TNamedFilter>;
    Foreign: TArray<string>      ;
  end;

const
  /// <summary>The skip file's name inside the rules folder.</summary>
  SKIP_FILE_NAME = 'convrules-editor-skip.txt';

/// <summary>PURE: parse the skip file's text. Never raises; an unparseable line
/// becomes a Foreign line rather than an error.</summary>
/// <param name="AText">The whole file; CRLF or LF, both accepted.</param>
/// <returns>Classes, named filters, and preserved foreign lines.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.LoadSkipList (ConvRules.MainForm.pas)</para>
/// <para>Calls: ConvRules.SkipList.IndexOfFilter, ConvRules.SkipList.IsGeneratedHeader, Copy, Default, Pos, SameText, StartsText, Trim</para>
/// <para>Returns: Default(TSkipList)</para>
/// <para>Complexity: 13 (cyclomatic, outer body), 76 lines (full implementation)</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.SkipList.IndexOfFilter"/>
/// <seealso cref="ConvRules.SkipList.IsGeneratedHeader"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseSkipList(const AText: string): TSkipList;

/// <summary>PURE: render a skip list back to file text (ASCII, CRLF, trailing
/// newline). Class names are emitted case-insensitively sorted so the file
/// diffs cleanly; foreign lines follow in their original order.</summary>
/// <param name="AList">The list to render.</param>
/// <returns>The file text, always starting with the two header lines.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.SaveSkipList (ConvRules.MainForm.pas)</para>
/// <para>Calls: CompareText, Copy</para>
/// <para>Returns: SB.ToString</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function EmitSkipList(const AList: TSkipList): string;

/// <summary>PURE: is this class marked "do not convert"? Case-insensitive.</summary>
/// <param name="AList">The skip list.</param>
/// <param name="AClassName">A bare class name.</param>
/// <returns>True when the class is marked.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.FormTypes.StampSkipMarks (ConvRules.FormTypes.pas), ConvRules.SkipList.MergePendingMarks (ConvRules.SkipList.pas), ConvRules.SkipList.SetSkipped (ConvRules.SkipList.pas)</para>
/// <para>Calls: SameText, Trim</para>
/// <para>Returns: False; True</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsSkipped(const AList: TSkipList; const AClassName: string): Boolean;

/// <summary>PURE: return a copy with AClassName marked or unmarked. Marking an
/// already-marked class is a no-op, not a duplicate row.</summary>
/// <param name="AList">The skip list.</param>
/// <param name="AClassName">A bare class name; blank is ignored.</param>
/// <param name="AOn">True to mark, False to unmark.</param>
/// <returns>The updated list.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.FormTypes.SkipListFromRows (ConvRules.FormTypes.pas)</para>
/// <para>Calls: ConvRules.SkipList.IsSkipped, SameText, Trim</para>
/// <para>Returns: AList</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.SkipList.IsSkipped"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SetSkipped(const AList: TSkipList; const AClassName: string; AOn: Boolean): TSkipList;

/// <summary>PURE: where the skip file lives for a rules folder.</summary>
/// <param name="ARulesFolder">The folder holding the .rules books.</param>
/// <returns>The full path, or '' when no folder is known -- never a bare file
/// name, which would land in the process's current directory.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.LoadSkipList (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.SaveSkipList (ConvRules.MainForm.pas)</para>
/// <para>Calls: Trim</para>
/// <para>Returns: ''; TPath.Combine(ARulesFolder, SKIP_FILE_NAME)</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SkipFilePath(const ARulesFolder: string): string;

/// <summary>PURE: merge marks accumulated in memory before a rules folder was
/// known with the list freshly parsed from that folder's skip file, so that
/// loading the file never discards a pending mark.</summary>
/// <param name="AFromFile">ParseSkipList's result for the file just read --
/// the sole source for Foreign lines, which exist nowhere else.</param>
/// <param name="APending">The in-memory list as it stood before the file was
/// read, e.g. ticks made (via SetSkipped / SkipListFromRows) while no rules
/// folder was open yet.</param>
/// <returns>Classes: the union of both sides' names, case-insensitive -- a
/// class marked on either side stays marked. Filters: AFromFile's filters plus
/// any APending filter whose name AFromFile does not already have (a name
/// present on both sides keeps the file's entry). Foreign: AFromFile's foreign
/// lines only -- APending never carries its own.</returns>
/// <remarks>
/// A skip mark is a presence flag, not a value, so there is no real
/// conflict to arbitrate for Classes: a name on either side simply survives.
/// LoadSkipList is the one caller -- it merges instead of resetting so that
/// marks ticked before FRulesFolder became known are not thrown away.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.LoadSkipList (ConvRules.MainForm.pas)</para>
/// <para>Calls: ConvRules.SkipList.IndexOfFilter, ConvRules.SkipList.IsSkipped</para>
/// <para>Returns: AFromFile</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.SkipList.IndexOfFilter"/>
/// <seealso cref="ConvRules.SkipList.IsSkipped"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function MergePendingMarks(const AFromFile, APending: TSkipList): TSkipList;

/// <summary>PURE: fold ANewFilter into AList.Filters, replacing any existing
/// filter of the same name rather than appending a duplicate, and dropping
/// blank patterns.</summary>
/// <param name="AList">The skip list to update.</param>
/// <param name="ANewFilter">The filter as entered -- Patterns may contain blank
/// lines, e.g. straight from a memo control's Lines.</param>
/// <returns>AList with a filter of ANewFilter.Name set to ANewFilter's non-blank
/// patterns: a filter of the SAME name is REPLACED in place, never duplicated
/// (Apply pressed twice on one name leaves exactly one record); a new name is
/// appended.</returns>
/// <remarks>
/// Without this, ApplyNamedFilterClick appended a new TNamedFilter on
/// every Apply -- ParseSkipList's own by-name merge on the next load then wrote
/// the same pattern line once more per Apply/restart cycle -- and a blank memo
/// line survived into a Patterns entry, which EmitSkipList renders as
/// "filter Name = " and ParseSkipList then preserves as a foreign line forever
/// (A3, 2026-09-20 whole-branch review, Minor 10).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.MainForm.TConvRulesForm.ApplyNamedFilterClick (ConvRules.MainForm.pas)</para>
/// <para>Calls: ConvRules.SkipList.IndexOfFilter, Trim</para>
/// <para>Returns: AList</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.SkipList.IndexOfFilter"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SetNamedFilter(const AList: TSkipList; const ANewFilter: TNamedFilter): TSkipList;

implementation

uses
  System.StrUtils
  , System.IOUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  ;

const
  { Not part of the public interface -- the brief names only SKIP_FILE_NAME as
    exported. Kept as file-scope consts rather than literals so ParseSkipList,
    EmitSkipList and IsGeneratedHeader cannot drift out of sync with each other. }
  SKIP_HEADER_1  = '# ConvRulesEditor -- classes marked "do not convert".';
  SKIP_HEADER_2  = '# Written by the editor; safe to hand-edit or diff.';
  { The pattern token that means "standard VCL/FMX control". }
  SKIP_STD_TOKEN = '+std';

{ True when ALine is one of the two lines EmitSkipList generates. }
function IsGeneratedHeader(const ALine: string): Boolean;
begin
  Result:= SameText(Trim(ALine), SKIP_HEADER_1) or SameText(Trim(ALine), SKIP_HEADER_2);
end;

{ Index of AName in AList.Filters, or -1. Case-insensitive. }
function IndexOfFilter(const AList: TSkipList; const AName: string): Integer;
var
  i: Integer;
begin
  for i:= 0 to High(AList.Filters) do
    if SameText(AList.Filters[i].Name, AName) then
      Exit(i);
  Result:= -1;
end;

function ParseSkipList(const AText: string): TSkipList;
var
  Lines: TArray<string>;
  Raw  : string        ;
  T    : string        ;
  Arg  : string        ;
  Nm   : string        ;
  Pat  : string        ;
  p    : Integer       ;
  k    : Integer       ;
  Dup  : Boolean       ;
  C    : string        ;
begin
  Result:= Default(TSkipList);
  Lines := AText.Replace(#13#10, #10).Split([#10]);
  for Raw in Lines do
  begin
    T:= Trim(Raw);
    if T = '' then
      Continue;
    if IsGeneratedHeader(T) then
      Continue;

    if StartsText('skip ', T) then
    begin
      Arg:= Trim(Copy(T, 6, MaxInt));  // dl:ok magic-literal@5703 -- Length('skip ') + 1, the char after the prefix just matched above
      if Arg = '' then
        Continue;
      Dup:= False;
      for C in Result.Classes do
        if SameText(C, Arg) then
        begin
          Dup:= True;
          Break;
        end;
      if not Dup then
        Result.Classes:= Result.Classes + [Arg];
      Continue;
    end;

    if StartsText('filter ', T) then
    begin
      Arg:= Trim(Copy(T, 8, MaxInt));  // dl:ok magic-literal@6862 -- Length('filter ') + 1, the char after the prefix just matched above
      p  := Pos('=', Arg);
      if p <= 1 then
      begin
        Result.Foreign:= Result.Foreign + [Raw];
        Continue;
      end;
      Nm := Trim(Copy(Arg, 1, p - 1));
      Pat:= Trim(Copy(Arg, p + 1, MaxInt));
      // A blank name OR a blank value carries no usable content -- treat the
      // WHOLE line as foreign rather than creating an empty filter entry that
      // EmitSkipList would then render as nothing, silently destroying the
      // line on the next save (round-trip regression, fixed 2026-09-20).
      if (Nm = '') or (Pat = '') then
      begin
        Result.Foreign:= Result.Foreign + [Raw];
        Continue;
      end;
      k:= IndexOfFilter(Result, Nm);
      if k < 0 then
      begin
        SetLength(Result.Filters, Length(Result.Filters) + 1);
        k:= High(Result.Filters);
        Result.Filters[k].Name:= Nm;
      end;
      if SameText(Pat, SKIP_STD_TOKEN) then
        Result.Filters[k].IncludeStandard:= True
      else
        Result.Filters[k].Patterns:= Result.Filters[k].Patterns + [Pat];
      Continue;
    end;

    Result.Foreign:= Result.Foreign + [Raw];
  end; // for
end; // function

function EmitSkipList(const AList: TSkipList): string;
var
  SB    : TStringBuilder;
  Sorted: TArray<string>;
  C     : string        ;
  F     : TNamedFilter  ;
  P     : string        ;
begin
  SB:= TStringBuilder.Create;
  try
    SB.Append(SKIP_HEADER_1).Append(#13#10);
    SB.Append(SKIP_HEADER_2).Append(#13#10);

    Sorted:= Copy(AList.Classes);
    TArray.Sort<string>(Sorted, TComparer<string>.Construct(
      function(const L, R: string): Integer
      begin
        Result:= CompareText(L, R);
      end));
    for C in Sorted do
      SB.Append('skip ').Append(C).Append(#13#10);

    for F in AList.Filters do
    begin
      if F.IncludeStandard then
        SB.Append('filter ').Append(F.Name).Append(' = ').Append(SKIP_STD_TOKEN).Append(#13#10);
      for P in F.Patterns do
        SB.Append('filter ').Append(F.Name).Append(' = ').Append(P).Append(#13#10);
    end;

    for C in AList.Foreign do
      SB.Append(C).Append(#13#10);

    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

function IsSkipped(const AList: TSkipList; const AClassName: string): Boolean;
var
  C: string;
begin
  Result:= False;
  if Trim(AClassName) = '' then
    Exit;
  for C in AList.Classes do
    if SameText(C, AClassName) then
      Exit(True);
end; // function

function SetSkipped(const AList: TSkipList; const AClassName: string; AOn: Boolean): TSkipList;
var
  C   : string;
  Keep: TArray<string>;
begin
  Result:= AList;
  if Trim(AClassName) = '' then
    Exit;
  if AOn then
  begin
    if not IsSkipped(AList, AClassName) then
      Result.Classes:= AList.Classes + [Trim(AClassName)];
  end
  else
  begin
    Keep:= nil;
    for C in AList.Classes do
      if not SameText(C, AClassName) then
        Keep:= Keep + [C];
    Result.Classes:= Keep;
  end;
end; // function

function SkipFilePath(const ARulesFolder: string): string;
begin
  if Trim(ARulesFolder) = '' then
    Exit('');
  Result:= TPath.Combine(ARulesFolder, SKIP_FILE_NAME);
end; // function

function MergePendingMarks(const AFromFile, APending: TSkipList): TSkipList;
var
  C: string      ;
  F: TNamedFilter;
begin
  Result:= AFromFile;
  for C in APending.Classes do
    if not IsSkipped(Result, C) then
      Result.Classes:= Result.Classes + [C];
  for F in APending.Filters do
    if IndexOfFilter(Result, F.Name) < 0 then
      Result.Filters:= Result.Filters + [F];
  // Foreign is deliberately left as AFromFile's alone -- APending never carries
  // any of its own (see the doc-comment).
end; // function

function SetNamedFilter(const AList: TSkipList; const ANewFilter: TNamedFilter): TSkipList;
var
  F: TNamedFilter;
  P: string      ;
  k: Integer     ;
begin
  Result:= AList;
  F:= ANewFilter;
  F.Patterns:= nil;
  for P in ANewFilter.Patterns do
    if Trim(P) <> '' then
      F.Patterns:= F.Patterns + [P];
  k:= IndexOfFilter(Result, F.Name);
  if k >= 0 then
    Result.Filters[k]:= F
  else
    Result.Filters:= Result.Filters + [F];
end; // function

end.
