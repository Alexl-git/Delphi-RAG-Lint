unit FeatureGen.DocsCheck;

{ Docs-drift checks C1-C4 of the registry check (lane ki-docscheck, 2026-10-28).
  Pure text functions: the caller (FeatureGen.Check, CheckProse) supplies the prose, the engine --help
  text and the source index, and applies the allowlist (features\docs-check-allow.json). Nothing here
  reads the repo except the two loaders at the bottom.

  C1  a --flag written beside "drag-lint <verb>" must be on that verb's --help block
  C2  a quoted %ENVVAR%\... path must occur in the product sources
  C3  "Planned" / "until then" / "not yet" / "coming" on the prose of a shipped entry
  C4  (note only) an entry verified before the newest commit that touched its verb's source }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  ;

type
  /// <summary>One docs-drift finding: what was found and the token an allowlist row names to waive it.</summary>
  TDocFinding = record
    /// <summary>The offending token: the flag ("--out-root"), the path as written, or the phrase as written (lower case).</summary>
    Token: string;
    /// <summary>The finding text, "&lt;id&gt;: ..." with the place it came from.</summary>
    Text: string;
  end;

  /// <summary>Verb name (lower case) to the lower-cased text of its --help block.</summary>
  TVerbBlocks = TDictionary<string, string>;

/// <summary>Splits the engine --help text into one block per verb.</summary>
/// <param name="pHelp">The text of "drag-lint --help"; any line ending.</param>
/// <returns>A dictionary keyed by the lower-case verb: the verb's usage line plus the continuation lines that follow
/// it (indented, non-blank, not starting another verb); several lines of one verb ("query" and "query find") are joined.
/// Owned by the caller.</returns>
function HelpVerbBlocks(const pHelp: string): TVerbBlocks;

/// <summary>Check C1: every --flag written with a drag-lint verb exists on that verb's --help block.</summary>
/// <param name="pId">Entry id (or page), for the message.</param>
/// <param name="pWhere">Where the text came from, for the message.</param>
/// <param name="pText">The prose. Judged are the backtick spans and fenced lines that start with "drag-lint &lt;verb&gt;"
/// (also ".\drag-lint.exe"), and a whole string that starts that way; a span that is the first cell of a table row
/// or the start of a list item and starts with a --flag is judged against pPageVerbs when that list is not empty.</param>
/// <param name="pBlocks">HelpVerbBlocks of the engine help.</param>
/// <param name="pPageVerbs">The cli verbs of the entry (or entries) this prose belongs to; may be empty.</param>
/// <returns>One finding per flag that is not on its verb's block. A verb the help does not list is not judged here
/// (check B owns verb existence). --help and --version are always accepted.</returns>
function FlagProblems(const pId, pWhere, pText: string; const pBlocks: TVerbBlocks;
  const pPageVerbs: TArray<string>): TArray<TDocFinding>;

/// <summary>Normalises source text for PathProblems: lower case, "/" and doubled backslashes folded to one backslash.</summary>
/// <param name="pText">Source text.</param>
/// <returns>The folded text.</returns>
function FoldPathText(const pText: string): string;

/// <summary>Check C2: every quoted %ENVVAR%\... path occurs in the sources.</summary>
/// <param name="pId">Entry id (or page), for the message.</param>
/// <param name="pWhere">Where the text came from, for the message.</param>
/// <param name="pText">The prose.</param>
/// <param name="pSourceFolded">All product source text after FoldPathText.</param>
/// <returns>One finding per path whose part after the environment variable (cut at the first placeholder "&lt;",
/// wildcard "*" or "[", dropping a partial last segment) does not occur in pSourceFolded.</returns>
function PathProblems(const pId, pWhere, pText, pSourceFolded: string): TArray<TDocFinding>;

/// <summary>Check C3: an unfinished-work phrase in the prose of a shipped entry.</summary>
/// <param name="pId">Entry id (or page), for the message.</param>
/// <param name="pWhere">Where the text came from, for the message.</param>
/// <param name="pText">The prose.</param>
/// <returns>One finding per occurrence of "planned", "until then", "not yet" or "coming" (whole words, any case).</returns>
function PhraseProblems(const pId, pWhere, pText: string): TArray<TDocFinding>;

/// <summary>Loads the folded source text C2 searches.</summary>
/// <param name="pRepo">Repository root.</param>
/// <returns>The folded text of every product source file under the repo (docs, WWW, features, third_party, and any
/// tests, fixtures or build output folder are not product sources); '' when the repo has none.</returns>
function LoadFoldedSources(const pRepo: string): string;
/// <summary>Check C4 input: the newest commit date per file from "git log --name-only --format=@%cs".</summary>
/// <param name="pGitLog">The git output: a line "@yyyy-mm-dd" starts a commit, the lines below it are its files.</param>
/// <returns>Lower-case forward-slash repo-relative path to the newest yyyy-mm-dd (git prints newest first, so the
/// first sighting wins). Owned by the caller.</returns>
function ParseGitFileDates(const pGitLog: string): TDictionary<string, string>;

/// <summary>Check C4: the source files of a cli verb, by naming convention.</summary>
/// <param name="pVerb">The cli verb ("find-callers").</param>
/// <param name="pFiles">Lower-case forward-slash repo-relative source paths.</param>
/// <returns>Every path whose unit name (the part after the last dot of the file stem, hyphens dropped) equals the verb
/// with hyphens dropped, case-insensitively: verb "ask" gives "src/charts/draglint.charts.ask.pas".</returns>
function ConventionSources(const pVerb: string; const pFiles: TArray<string>): TArray<string>;

/// <summary>Check C4: the newest change date among pPaths that is later than the verified date.</summary>
/// <param name="pVerified">The entry's verified date, yyyy-mm-dd.</param>
/// <param name="pPaths">Lower-case forward-slash repo-relative paths of the entry's source.</param>
/// <param name="pDates">ParseGitFileDates output.</param>
/// <returns>The newest date after pVerified, or '' when no listed path changed after the verification.</returns>
function SourceChangedAfter(const pVerified: string; const pPaths: TArray<string>; const pDates: TDictionary<string, string>): string;
implementation

uses
  System.Classes
  , System.IOUtils
  , System.RegularExpressions
  ;

const
  VERB_LINE = '^\s{2}drag-lint\s+([a-z][a-z0-9-]*)';
  SPAN_PATTERN = '`([^`\r\n]+)`';
  CMD_PATTERN = '(?i)^\s*(?:\.\\)?drag-lint(?:\.exe)?\s+([a-z][a-z0-9-]*)(.*)$';
  FLAG_PATTERN = '(?<![\w-])(--[A-Za-z][A-Za-z0-9-]*)';
  GLOBAL_KEY = '*';
  PATH_PATTERN = '%(?:LOCALAPPDATA|APPDATA|TEMP|USERPROFILE|PROGRAMDATA)%[\\/][^\s`''")<>|,;]*';
  PHRASE_PATTERN = '(?i)\b(planned|until then|not yet|coming)\b';
  FENCE = '```';
  STANDALONE_MARK = #1;
  LEAD_CELL = '^\s*(?:\|\s*|[*-]\s+)$';
  SOURCE_EXTS: array[0..9] of string = ('.pas', '.dpr', '.inc', '.ps1', '.psm1', '.rs', '.c', '.h', '.iss', '.bat');
  SKIP_TOP: array[0..8] of string = ('docs', 'www', 'tests', 'features', 'third_party', 'svg', 'circular-demo', 'convrules', '.git');
  SKIP_ANY: array[0..6] of string = ('dcu', 'target', 'win32', 'win64', 'node_modules', 'tests', 'fixtures');
  ALWAYS_OK: array[0..1] of string = ('--help', '--version');

function InList(const pValue: string; const pList: array of string): Boolean;
var
  lS: string;
begin
  for lS in pList do
    if SameText(lS, pValue) then
      Exit(True);
  Result := False;
end;

function HelpVerbBlocks(const pHelp: string): TVerbBlocks;
var
  lLines: TArray<string>;
  lLine, lCur: string;
  lM: TMatch;
begin
  Result := TVerbBlocks.Create;
  lCur := '';
  lLines := pHelp.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  for lLine in lLines do
  begin
    lM := TRegEx.Match(lLine, VERB_LINE);
    if lM.Success then
      lCur := LowerCase(lM.Groups[1].Value)
    else if (Trim(lLine) = '') or (lLine[1] <> ' ') then
      lCur := '';
    // a flag-definition line outside every verb block ("  --output-encoding ascii|utf8") is accepted by every verb
    if (lCur = '') and Trim(lLine).StartsWith('--') then
      lCur := GLOBAL_KEY;
    if lCur <> '' then
    begin
      if Result.ContainsKey(lCur) then
        Result[lCur] := Result[lCur] + #10 + LowerCase(lLine)
      else
        Result.Add(lCur, LowerCase(lLine));
    end;
  end;
end;

function BlockHasFlag(const pBlock, pFlag: string): Boolean;
begin
  Result := TRegEx.IsMatch(pBlock, '(?<![\w-])' + TRegEx.Escape(LowerCase(pFlag)) + '(?![\w-])');
end;

{ The spans of pText a C1 judgement looks at, one string each. }
function CommandSpans(const pText: string): TArray<string>;
var
  lList: TList<string>;
  lLines: TArray<string>;
  lLine: string;
  lInFence: Boolean;
  lM: TMatch;
begin
  lList := TList<string>.Create;
  try
    lInFence := False;
    lLines := pText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
    for lLine in lLines do
    begin
      if Trim(lLine).StartsWith(FENCE) then
      begin
        lInFence := not lInFence;
        Continue;
      end;
      if lInFence then
        lList.Add(lLine)
      else
      begin
        for lM in TRegEx.Matches(lLine, SPAN_PATTERN) do
          if TRegEx.IsMatch(Copy(lLine, 1, lM.Index - 1), LEAD_CELL) then
            lList.Add(STANDALONE_MARK + lM.Groups[1].Value)
          else
            lList.Add(lM.Groups[1].Value);
        if (Pos('`', lLine) = 0) and TRegEx.IsMatch(lLine, CMD_PATTERN) then
          lList.Add(lLine);
      end;
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function FlagProblems(const pId, pWhere, pText: string; const pBlocks: TVerbBlocks;
  const pPageVerbs: TArray<string>): TArray<TDocFinding>;
var
  lSpan, lVerb, lVerbs: string;
  lM, lF: TMatch;
  lFound: Boolean;
  lPage, lBlk, lGlob: string;
  lItem: TDocFinding;
  lList: TList<TDocFinding>;

  procedure Add(const pFlag, pOwner: string);
  begin
    lItem.Token := LowerCase(pFlag);
    lItem.Text := Format('%s: %s writes %s with "%s", whose --help block has no such flag', [pId, pWhere, pFlag, pOwner]);
    lList.Add(lItem);
  end;

begin
  lList := TList<TDocFinding>.Create;
  try
    lGlob := '';
    pBlocks.TryGetValue(GLOBAL_KEY, lGlob);
    lPage := lGlob;
    for lVerb in pPageVerbs do
      if pBlocks.TryGetValue(LowerCase(lVerb), lBlk) then
        lPage := lPage + #10 + lBlk;
    lVerbs := string.Join(' ', pPageVerbs);
    for lSpan in CommandSpans(pText) do
    begin
      lM := TRegEx.Match(lSpan, CMD_PATTERN);
      if lM.Success then
      begin
        lVerb := LowerCase(lM.Groups[1].Value);
        if not pBlocks.TryGetValue(lVerb, lBlk) then
          Continue;
        for lF in TRegEx.Matches(lM.Groups[2].Value, FLAG_PATTERN) do
          if not (InList(lF.Value, ALWAYS_OK) or BlockHasFlag(lBlk, lF.Value) or BlockHasFlag(lGlob, lF.Value)) then
            Add(lF.Value, 'drag-lint ' + lVerb);
      end
      else if (Length(pPageVerbs) > 0) and lSpan.StartsWith(STANDALONE_MARK + '--') then
      begin
        lF := TRegEx.Match(Copy(lSpan, 2, MaxInt), '^' + FLAG_PATTERN);
        lFound := (not lF.Success) or InList(lF.Value, ALWAYS_OK) or BlockHasFlag(lPage, lF.Value);
        if not lFound then
          Add(lF.Value, 'drag-lint ' + lVerbs);
      end;
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function FoldPathText(const pText: string): string;
begin
  Result := LowerCase(pText).Replace('/', '\').Replace('\\', '\');
end;

function PathProblems(const pId, pWhere, pText, pSourceFolded: string): TArray<TDocFinding>;
var
  lList: TList<TDocFinding>;
  lM: TMatch;
  lPath, lTail: string;
  lCut: Integer;
  lItem: TDocFinding;
  lSegs: TArray<string>;
  lAfter: Integer;
  lCutDone: Boolean;
begin
  lList := TList<TDocFinding>.Create;
  try
    for lM in TRegEx.Matches(pText, PATH_PATTERN) do
    begin
      lPath := lM.Value.TrimRight(['.', ':', '*', '\', '/']);
      lTail := FoldPathText(TRegEx.Replace(lPath, '^%[A-Za-z]+%\\?', '', [roIgnoreCase]).Replace('/', '\'));
      lCutDone := False;
      for lCut := 1 to Length(lTail) do
        if CharInSet(lTail[lCut], ['<', '*', '[']) then
        begin
          lTail := Copy(lTail, 1, lCut - 1);
          // the cut left a partial last segment: drop it
          lSegs := lTail.Split(['\']);
          if Length(lSegs) > 0 then
            lTail := string.Join('\', Copy(lSegs, 0, Length(lSegs) - 1));
          lCutDone := True;
          Break;
        end;
      lTail := lTail.TrimRight(['\']);
      // the match stopped at a placeholder: its last segment is only a prefix (compare-<q>.html)
      lAfter := lM.Index + lM.Length;
      if (lAfter <= Length(pText)) and CharInSet(pText[lAfter], ['<', '*', '[']) and (Pos('\', lTail) > 0) and not lCutDone then
        lTail := Copy(lTail, 1, LastDelimiter('\', lTail) - 1);
      if lTail = '' then
        Continue;
      if Pos(lTail, pSourceFolded) = 0 then
      begin
        lItem.Token := lPath;
        lItem.Text := Format('%s: %s quotes the path %s, which occurs nowhere in the product sources (a renamed or moved folder or file?)',
          [pId, pWhere, lPath]);
        lList.Add(lItem);
      end;
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function PhraseProblems(const pId, pWhere, pText: string): TArray<TDocFinding>;
var
  lList: TList<TDocFinding>;
  lM: TMatch;
  lItem: TDocFinding;
begin
  lList := TList<TDocFinding>.Create;
  try
    for lM in TRegEx.Matches(pText, PHRASE_PATTERN) do
    begin
      lItem.Token := LowerCase(lM.Groups[1].Value);
      lItem.Text := Format('%s: %s says "%s" but the entry is shipped (finished work reads as done, not as a promise)',
        [pId, pWhere, lM.Value]);
      lList.Add(lItem);
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function IsProductSource(const pRepo, pFile: string): Boolean;
var
  lRel, lPart: string;
  lParts: TArray<string>;
begin
  lRel := Copy(pFile, Length(IncludeTrailingPathDelimiter(pRepo)) + 1, MaxInt);
  lParts := LowerCase(lRel).Split(['\']);
  if (Length(lParts) < 2) or InList(lParts[0], SKIP_TOP) then
    Exit(False);
  for lPart in lParts do
    if InList(lPart, SKIP_ANY) then
      Exit(False);
  Result := InList(LowerCase(ExtractFileExt(pFile)), SOURCE_EXTS);
end;

function LoadFoldedSources(const pRepo: string): string;
var
  lSb: TStringBuilder;
  lFile: string;
begin
  lSb := TStringBuilder.Create;
  try
    for lFile in TDirectory.GetFiles(pRepo, '*', TSearchOption.soAllDirectories) do
      if IsProductSource(pRepo, lFile) then
        lSb.Append(FoldPathText(TFile.ReadAllText(lFile, TEncoding.ANSI))).Append(#10);
    Result := lSb.ToString;
  finally
    lSb.Free;
  end;
end;

function ParseGitFileDates(const pGitLog: string): TDictionary<string, string>;
var
  lLine, lDate, lKey: string;
begin
  Result := TDictionary<string, string>.Create;
  lDate := '';
  for lLine in pGitLog.Replace(#13#10, #10).Split([#10]) do
    if lLine.StartsWith('@') then
      lDate := Copy(lLine, 2, MaxInt)
    else if (Trim(lLine) <> '') and (lDate <> '') then
    begin
      lKey := LowerCase(Trim(lLine)).Replace('\', '/');
      if not Result.ContainsKey(lKey) then
        Result.Add(lKey, lDate);
    end;
end;

function ConventionSources(const pVerb: string; const pFiles: TArray<string>): TArray<string>;
var
  lFile, lStem, lUnit, lWant: string;
  lList: TList<string>;
begin
  lWant := LowerCase(pVerb).Replace('-', '');
  lList := TList<string>.Create;
  try
    for lFile in pFiles do
    begin
      lStem := ChangeFileExt(ExtractFileName(lFile.Replace('/', '\')), '');
      lUnit := LowerCase(Copy(lStem, LastDelimiter('.', lStem) + 1, MaxInt)).Replace('-', '');
      if (lWant <> '') and (lUnit = lWant) then
        lList.Add(lFile);
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function SourceChangedAfter(const pVerified: string; const pPaths: TArray<string>; const pDates: TDictionary<string, string>): string;
var
  lPath, lDate: string;
begin
  Result := '';
  for lPath in pPaths do
    if pDates.TryGetValue(lPath, lDate) and (lDate > pVerified) and (lDate > Result) then
      Result := lDate;
end;
end.
