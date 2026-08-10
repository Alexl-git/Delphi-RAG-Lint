unit DRagLint.Lint.ProjectChecks.Parse;

// v0.65: pure (DB-free, FireDAC-free) parsing & normalization helpers for the
// project-membership lint rules (unit-not-in-dpr / used-unit-not-resolvable).
// Split out of DRagLint.Lint.ProjectChecks so they can be unit-tested with a
// trivial standalone dcc64 build (no SQLite/FireDAC/Core deps). The split also
// isolates the brittle text-parsing from the DB-touching rule logic.

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.RegularExpressions
  , System.Generics.Collections
  , System.StrUtils
  ;

type
  /// <summary>How a used unit was resolved (or urvNone when unresolvable).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (DRagLint.Lint.ProjectChecks.Parse.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TUnitResolveVia = (urvNone, urvProjectMember, urvLibrary, urvAlias, urvRtlNamespace);
  /// <summary>Result of ResolveUsedUnit: whether the unit resolves, and via which source.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (DRagLint.Lint.ProjectChecks.Parse.pas)
  /// Used in units: DRagLint.Lint.ProjectChecks.Parse
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TUnitResolution = record
    Resolvable: Boolean;
    Via       : TUnitResolveVia;
  end;

/// <summary>Normalize a unit name or file path to a bare lower-case unit-name
/// segment, used on BOTH sides of every membership comparison so they match.</summary>
/// <param name="AName"><!-- drag-lint:auto type -->const string</param>
/// <remarks>
/// Only a known SOURCE extension (.pas/.dpk/.dpr) is stripped; a dotted
/// namespace like 'Foo.ViewModel' must NOT lose '.ViewModel' to ChangeFileExt
/// (FP-9). 'Foo.ViewModel' and 'Foo.ViewModel.pas' both -> 'viewmodel';
/// 'System.SysUtils' -> 'sysutils' (matches the index's last-segment norm).
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Lint.ProjectChecks.Parse.ResolveUsedUnit (DRagLint.Lint.ProjectChecks.Parse.pas), DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUnitsInDpr (DRagLint.Lint.ProjectChecks.pas), DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUsedUnitResolvable (DRagLint.Lint.ProjectChecks.pas)
/// Calls: ChangeFileExt, Copy, ExtractFileExt, ExtractFileName, LastDelimiter, LowerCase
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function NormUnit(const AName: string): string;

/// <summary>Blank out Pascal comments -- { ... }, (* ... *), and // ... -- in
/// place, preserving overall length and every line-break so byte offsets and
/// line numbers stay valid. String literals ('...') are left intact.</summary>
/// <param name="ASrc"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->Observed: ASrc.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Lint.ProjectChecks.Parse.ParseUsesFromContent (DRagLint.Lint.ProjectChecks.Parse.pas)
/// Calls: DRagLint.Lint.ProjectChecks.Parse.StripPasCommentsKeepLayout.Blank
/// Complexity: 23 (cyclomatic, outer body), 53 lines (full implementation)
/// Pure
/// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.StripPasCommentsKeepLayout.Blank"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function StripPasCommentsKeepLayout(const ASrc: string): string;

/// <summary>Extract unit names from the uses/contains/requires clauses in the
/// given .dpr/.dpk source text. Form-name hints and compiler directives are
/// scrubbed first so they are never mis-read as units (FP-8).</summary>
/// <param name="AContent"><!-- drag-lint:auto type -->const string</param>
/// <param name="AUsesStartLine">Receives the 1-based line of the first clause.</param>
/// <returns><!-- drag-lint:auto -->Observed: List.ToArray.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Lint.ProjectChecks.Parse.ExtractUsesNames (DRagLint.Lint.ProjectChecks.Parse.pas)
/// Calls: DRagLint.Lint.ProjectChecks.Parse.StripPasCommentsKeepLayout, SameText
/// Mutates: AUsesStartLine (out)
/// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.StripPasCommentsKeepLayout"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseUsesFromContent(const AContent: string; out AUsesStartLine: Integer): TArray<string>;

/// <summary>Read a .dpr/.dpk file and extract its uses-clause unit names.</summary>
/// <param name="AProgramPath"><!-- drag-lint:auto type -->const string</param>
/// <param name="AUsesStartLine"><!-- drag-lint:auto type -->out Integer</param>
/// <returns><!-- drag-lint:auto -->Observed:
/// ParseUsesFromContent(TFile.ReadAllText(AProgramPath), AUsesStartLine).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUnitsInDpr (DRagLint.Lint.ProjectChecks.pas)
/// Calls: DRagLint.Lint.ProjectChecks.Parse.ParseUsesFromContent
/// Mutates: AUsesStartLine (out)
/// Touches: file system
/// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.ParseUsesFromContent"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ExtractUsesNames(const AProgramPath: string; out AUsesStartLine: Integer): TArray<string>;

/// <summary>Read the .pas/.dpk &lt;DCCReference Include="..."/&gt; entries from a .dproj.</summary>
/// <param name="ADprojPath"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->Observed: List.ToArray.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUnitsInDpr (DRagLint.Lint.ProjectChecks.pas)
/// Calls: ExtractFileExt, SameText
/// Touches: file system
/// <!-- drag-lint:auto END -->
/// </remarks>
function ReadDCCReferences(const ADprojPath: string): TArray<string>;

/// <summary>Find the sibling .dpr or .dpk for a .dproj, or '' if none exists.</summary>
/// <param name="ADprojPath"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->Observed: ''.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUnitsInDpr (DRagLint.Lint.ProjectChecks.pas)
/// Calls: ChangeFileExt, ExtractFileName, ExtractFilePath
/// Touches: file system
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindSiblingProgramFile(const ADprojPath: string): string;

/// <summary>True if AUnitName is a classic Delphi unit alias (WinTypes, WinProcs,
/// DbiTypes, DbiProcs, DbiErrs) -- the compiler maps these to a real unit, so a
/// `uses` of one is always resolvable.</summary>
/// <param name="AUnitName"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->Observed: False.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Lint.ProjectChecks.Parse.ResolveUsedUnit (DRagLint.Lint.ProjectChecks.Parse.pas)
/// Calls: LowerCase, Trim
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsStandardUnitAlias(const AUnitName: string): Boolean;

/// <summary>True if AUnitName is an RTL/framework unit by namespace (System.*,
/// Vcl.*, Fmx.*, Winapi.*, Data.*, Datasnap.*, Soap.*, Web.*, FireDAC.*) or a
/// classic bare RTL name (Forms, SysUtils, Classes, Windows, ...). Belt-and-
/// suspenders so incomplete library-index coverage never false-flags core RTL.</summary>
/// <param name="AUnitName"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->Observed: False.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Lint.ProjectChecks.Parse.ResolveUsedUnit (DRagLint.Lint.ProjectChecks.Parse.pas)
/// Calls: LowerCase, StartsText, Trim
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsRtlNamespaceUnit(const AUnitName: string): Boolean;

/// <summary>Decide whether a used unit resolves to something known. Order:
/// project member -> platform library -> standard alias -> RTL namespace.
/// The two predicates receive the NORMALIZED name (NormUnit).</summary>
/// <param name="AUnitName">Verbatim used unit name, e.g. 'Bde.DBTables'.</param>
/// <param name="AIsProjectMember">Given a normalized stem, is it an indexed project unit?</param>
/// <param name="AIsInLibrary">Given a normalized stem, is it in the platform library DB?</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUsedUnitResolvable (DRagLint.Lint.ProjectChecks.pas)
/// Calls: AIsInLibrary, AIsProjectMember, DRagLint.Lint.ProjectChecks.Parse.IsRtlNamespaceUnit, DRagLint.Lint.ProjectChecks.Parse.IsStandardUnitAlias, DRagLint.Lint.ProjectChecks.Parse.NormUnit
/// Pure
/// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.IsRtlNamespaceUnit"/>
/// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.IsStandardUnitAlias"/>
/// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.NormUnit"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolveUsedUnit(const AUnitName: string;
  const AIsProjectMember, AIsInLibrary: TFunc<string, Boolean>): TUnitResolution;

implementation

function NormUnit(const AName: string): string;
const
  CSrcExt: array[0..2] of string = ('.pas', '.dpk', '.dpr');
var
  Ext   : string ;
  DotPos: Integer;
  I     : Integer;
begin
  Result:= ExtractFileName(AName);
  Ext   := LowerCase(ExtractFileExt(Result));
  for I:= Low(CSrcExt) to High(CSrcExt) do
    if Ext = CSrcExt[I] then
    begin
      Result:= ChangeFileExt(Result, '');
      Break;
    end;
  Result:= LowerCase(Result);
  DotPos:= LastDelimiter('.', Result);
  if DotPos > 0 then Result:= Copy(Result, DotPos + 1, MaxInt);
end;

function StripPasCommentsKeepLayout(const ASrc: string): string;
var
  I, N    : Integer;
  InString: Boolean;

  procedure Blank(AIdx: Integer);
  begin
    if (Result[AIdx] <> #10) and (Result[AIdx] <> #13) then Result[AIdx]:= ' ';
  end;

begin
  Result:= ASrc;
  N:= Length(ASrc);
  InString:= False;
  I:= 1;
  while I <= N do
  begin
    if InString then
    begin
      if ASrc[I] = '''' then InString:= False;
      Inc(I);
      Continue;
    end;
    case ASrc[I] of
      '''':
        begin
          InString:= True;
          Inc(I);
        end;
      '{':
        begin
          while (I <= N) and (ASrc[I] <> '}') do begin Blank(I); Inc(I); end;
          if I <= N then begin Blank(I); Inc(I); end;
        end;
      '(':
        if (I < N) and (ASrc[I + 1] = '*') then
        begin
          Blank(I); Blank(I + 1); Inc(I, 2);
          while (I < N) and not ((ASrc[I] = '*') and (ASrc[I + 1] = ')')) do begin Blank(I); Inc(I); end;
          if I < N then begin Blank(I); Blank(I + 1); Inc(I, 2); end
          else if I = N then begin Blank(I); Inc(I); end;
        end
        else
          Inc(I);
      '/':
        if (I < N) and (ASrc[I + 1] = '/') then
          while (I <= N) and (ASrc[I] <> #10) and (ASrc[I] <> #13) do begin Blank(I); Inc(I); end
        else
          Inc(I);
    else
      Inc(I);
    end;
  end;
end; // function

function ParseUsesFromContent(const AContent: string; out AUsesStartLine: Integer): TArray<string>;
var
  Scrubbed : string       ;
  RE       : TRegEx       ;
  UnitRE   : TRegEx       ;
  M        : TMatch       ;
  U        : TMatch       ;
  Clause   : string       ;
  List     : TList<string>;
  Idx      : Integer      ;
  LineCount: Integer      ;
  Pos      : Integer      ;
begin
  AUsesStartLine:= 1;
  // FP-8: scrub comments so form hints ({frmMain}) and directives ({$IFDEF})
  // inside the clause are not mis-extracted as units, and so a stray ';' inside
  // a hint cannot truncate the clause match.
  Scrubbed:= StripPasCommentsKeepLayout(AContent);
  // Match `uses ... ;`, `contains ... ;`, `requires ... ;`.
  RE:= TRegEx.Create('\b(uses|contains|requires)\b\s*(.*?);', [roIgnoreCase, roSingleLine]);
  // Inside the clause, a unit reference looks like `Name` or `Name in ''...''`.
  UnitRE:= TRegEx.Create('([A-Za-z_][A-Za-z0-9_\.]*)\s*(?:in\s+''[^'']*'')?', [roIgnoreCase]);
  List:= TList<string>.Create;
  try
    M:= RE.Match(Scrubbed);
    while M.Success do
    begin
      Clause:= M.Groups[2].Value;
      // Track the line of the first uses clause for the finding's location.
      if List.Count = 0 then
      begin
        LineCount:= 1;
        Pos:= M.Index;
        for Idx:= 1 to Pos do
          if (Idx <= Length(Scrubbed)) and (Scrubbed[Idx] = #10) then Inc(LineCount);
        AUsesStartLine:= LineCount;
      end;
      U:= UnitRE.Match(Clause);
      while U.Success do
      begin
        if (U.Groups[1].Value <> '') and (not SameText(U.Groups[1].Value, 'in')) then List.Add(U.Groups[1].Value);
        U:= U.NextMatch;
      end;
      M:= M.NextMatch;
    end; // while
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

function ExtractUsesNames(const AProgramPath: string; out AUsesStartLine: Integer): TArray<string>;
begin
  AUsesStartLine:= 1;
  if not TFile.Exists(AProgramPath) then Exit(nil);
  Result:= ParseUsesFromContent(TFile.ReadAllText(AProgramPath), AUsesStartLine);
end;

function ReadDCCReferences(const ADprojPath: string): TArray<string>;
var
  Content: string       ;
  RE     : TRegEx       ;
  M      : TMatch       ;
  List   : TList<string>;
  Inc    : string       ;
begin
  if not TFile.Exists(ADprojPath) then Exit(nil);
  Content:= TFile.ReadAllText(ADprojPath);
  RE:= TRegEx.Create('<DCCReference\s+Include="([^"]+)"', [roIgnoreCase, roSingleLine]);
  List:= TList<string>.Create;
  try
    M:= RE.Match(Content);
    while M.Success do
    begin
      Inc:= M.Groups[1].Value;
      // Only track .pas/.dpk units; skip .rc, .res, .dfm, etc.
      if SameText(ExtractFileExt(Inc), '.pas') or SameText(ExtractFileExt(Inc), '.dpk') then List.Add(Inc);
      M:= M.NextMatch;
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end; // function

function FindSiblingProgramFile(const ADprojPath: string): string;
var
  Base     : string;
  Dir      : string;
  Candidate: string;
begin
  Dir:= ExtractFilePath(ADprojPath);
  Base:= ChangeFileExt(ExtractFileName(ADprojPath), '');
  Candidate:= TPath.Combine(Dir, Base + '.dpr');
  if TFile.Exists(Candidate) then Exit(Candidate);
  Candidate:= TPath.Combine(Dir, Base + '.dpk');
  if TFile.Exists(Candidate) then Exit(Candidate);
  Result:= '';
end;

function IsStandardUnitAlias(const AUnitName: string): Boolean;
const
  ALIASES: array[0..4] of string = ('wintypes', 'winprocs', 'dbitypes', 'dbiprocs', 'dbierrs');
var
  I      : Integer;
  LowName: string;
begin
  LowName:= LowerCase(Trim(AUnitName));
  Result:= False;
  for I:= System.Low(ALIASES) to System.High(ALIASES) do
    if LowName = ALIASES[I] then Exit(True);
end;

function IsRtlNamespaceUnit(const AUnitName: string): Boolean;
const
  NS: array[0..8] of string = ('system.', 'vcl.', 'fmx.', 'winapi.', 'data.', 'datasnap.', 'soap.', 'web.', 'firedac.');
  BARE: array[0..14] of string = ('system', 'sysinit', 'forms', 'sysutils', 'classes',
    'windows', 'messages', 'variants', 'graphics', 'controls', 'dialogs', 'menus',
    'stdctrls', 'math', 'types');
var
  LowName: string;
  I      : Integer;
begin
  LowName:= LowerCase(Trim(AUnitName));
  Result:= False;
  for I:= System.Low(NS) to System.High(NS) do
    if StartsText(NS[I], LowName) then Exit(True);
  for I:= System.Low(BARE) to System.High(BARE) do
    if LowName = BARE[I] then Exit(True);
end;

function ResolveUsedUnit(const AUnitName: string;
  const AIsProjectMember, AIsInLibrary: TFunc<string, Boolean>): TUnitResolution;
var
  Norm: string;
begin
  Result.Resolvable:= False;
  Result.Via       := urvNone;
  Norm:= NormUnit(AUnitName);
  if Norm = '' then Exit;
  if Assigned(AIsProjectMember) and AIsProjectMember(Norm) then
    begin Result.Resolvable:= True; Result.Via:= urvProjectMember; Exit; end;
  if Assigned(AIsInLibrary) and AIsInLibrary(Norm) then
    begin Result.Resolvable:= True; Result.Via:= urvLibrary; Exit; end;
  if IsStandardUnitAlias(AUnitName) then
    begin Result.Resolvable:= True; Result.Via:= urvAlias; Exit; end;
  if IsRtlNamespaceUnit(AUnitName) then
    begin Result.Resolvable:= True; Result.Via:= urvRtlNamespace; Exit; end;
end;

end.
