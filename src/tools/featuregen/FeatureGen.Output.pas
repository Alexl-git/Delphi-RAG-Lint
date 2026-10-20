unit FeatureGen.Output;

{ Output writer for featuregen: every generated file goes through TOutputWriter.
  Text is normalised to CRLF and must be 7-bit ASCII; a file is written only when
  its bytes differ; nothing is ever written outside the root; an owned root has
  stale files removed. In check mode nothing on disk changes and every difference
  is reported instead. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.Generics.Collections
  ;

type
  /// <summary>Raised for a featuregen failure: non-ASCII output, a path outside the root, an unreadable source file.</summary>
  EFeatureGen = class(Exception);

  /// <summary>Outcome of one TOutputWriter run. Paths are root-relative with backslashes.</summary>
  TOutputResult = record
    /// <summary>Files actually written (new or different bytes). Empty in check mode.</summary>
    Written: TArray<string>;
    /// <summary>Files whose bytes differ from, or are absent on, disk, and (check mode, owned root) stale files. Each entry is the path, CRLF, then the first-difference text.</summary>
    Changed: TArray<string>;
    /// <summary>Stale files deleted from an owned root. Empty in check mode.</summary>
    Removed: TArray<string>;
  end;

  /// <summary>Writes generated files under one root with write-only-when-different semantics.</summary>
  /// <remarks>Not thread-safe. Call Put/PutBinary for every file of the run, then Finish once.</remarks>
  TOutputWriter = class
  strict private
    FRoot: string;
    FCheckOnly: Boolean;
    FOwnsRoot: Boolean;
    FProduced: TDictionary<string, Boolean>;
    FNames: TDictionary<string, string>;
    FTexts: TDictionary<string, string>;
    FWritten: TList<string>;
    FChanged: TList<string>;
    FRemoved: TList<string>;
    function ResolvePath(const pRelPath: string): string;
    procedure Store(const pRelPath: string; const pBytes: TBytes);
  public
    /// <summary>Creates a writer.</summary>
    /// <param name="pRoot">Directory every output lives under. Created on first write.</param>
    /// <param name="pCheckOnly">True: write and delete nothing, only report differences.</param>
    /// <param name="pOwnsRoot">True: Finish removes files under pRoot that this run did not produce.</param>
    constructor Create(const pRoot: string; pCheckOnly, pOwnsRoot: Boolean);
    destructor Destroy; override;
    /// <summary>Queues one text file. Line ends are normalised to CRLF.</summary>
    /// <param name="pRelPath">Path relative to the root.</param>
    /// <param name="pText">File content, 7-bit ASCII.</param>
    /// <param name="pContext">Names the producing entry/field for error messages.</param>
    /// <exception cref="EFeatureGen">A char above 127 (message names pContext and the 1-based line), or pRelPath leaves the root.</exception>
    procedure Put(const pRelPath, pText: string; const pContext: string);
    /// <summary>Queues one binary file copied byte for byte.</summary>
    /// <param name="pRelPath">Path relative to the root.</param>
    /// <param name="pSourceFile">Full path of the source file.</param>
    /// <exception cref="EFeatureGen">The source is missing, or pRelPath leaves the root.</exception>
    procedure PutBinary(const pRelPath, pSourceFile: string);
    /// <summary>Completes the run: removes stale files (owned root, not check mode) and reports.</summary>
    /// <returns>Written, Changed and Removed paths.</returns>
    function Finish: TOutputResult;
    /// <summary>Root-relative paths (backslashes) of every file queued so far, text and binary.</summary>
    /// <returns>The paths, in the order the files were queued.</returns>
    function ProducedFiles: TArray<string>;
    /// <summary>The text queued for a file, with LF line ends.</summary>
    /// <param name="pRelPath">Root-relative path as given to Put (either slash).</param>
    /// <returns>The text; '' when the file was not queued by Put.</returns>
    function TextOf(const pRelPath: string): string;
    /// <summary>The full path of the output root, no trailing delimiter.</summary>
    property Root: string read FRoot;
  end;

/// <summary>First-difference text of two strings, as Get-DiffHead in FeatureRegistry.psm1.</summary>
/// <param name="pOld">Old text.</param>
/// <param name="pNew">New text.</param>
/// <param name="pLines">Total line budget; half is shown from each side.</param>
/// <returns>An '@@ first difference at line N (old A lines, new B lines)' header, then up to pLines div 2 '-' lines and '+' lines, each ending CRLF.</returns>
function DiffHead(const pOld, pNew: string; pLines: Integer = 20): string;

implementation

function SplitLines(const pText: string): TArray<string>;
begin
  Result := pText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
end;

function DiffHead(const pOld, pNew: string; pLines: Integer): string;
var
  lA, lB: TArray<string>;
  lN, lFirst, lHalf, lI: Integer;
  lSb: TStringBuilder;
begin
  lA := SplitLines(pOld);
  lB := SplitLines(pNew);
  lN := Length(lA);
  if Length(lB) < lN then
    lN := Length(lB);
  lFirst := lN;
  for lI := 0 to lN - 1 do
    if not SameStr(lA[lI], lB[lI]) then
    begin
      lFirst := lI;
      Break;
    end;
  lSb := TStringBuilder.Create;
  try
    lSb.Append('@@ first difference at line ').Append(lFirst + 1).Append(' (old ').Append(Length(lA))
      .Append(' lines, new ').Append(Length(lB)).Append(' lines)').Append(#13#10);
    lHalf := pLines div 2;
    if lHalf < 1 then
      lHalf := 1;
    for lI := lFirst to Length(lA) - 1 do
    begin
      if lI >= lFirst + lHalf then
        Break;
      lSb.Append('-').Append(lA[lI]).Append(#13#10);
    end;
    for lI := lFirst to Length(lB) - 1 do
    begin
      if lI >= lFirst + lHalf then
        Break;
      lSb.Append('+').Append(lB[lI]).Append(#13#10);
    end;
    Result := lSb.ToString;
  finally
    lSb.Free;
  end;
end;

{ TOutputWriter }

constructor TOutputWriter.Create(const pRoot: string; pCheckOnly, pOwnsRoot: Boolean);
begin
  inherited Create;
  FRoot := ExcludeTrailingPathDelimiter(TPath.GetFullPath(pRoot));
  FCheckOnly := pCheckOnly;
  FOwnsRoot := pOwnsRoot;
  FProduced := TDictionary<string, Boolean>.Create;
  FNames := TDictionary<string, string>.Create;
  FTexts := TDictionary<string, string>.Create;
  FWritten := TList<string>.Create;
  FChanged := TList<string>.Create;
  FRemoved := TList<string>.Create;
end;

destructor TOutputWriter.Destroy;
begin
  FRemoved.Free;
  FChanged.Free;
  FWritten.Free;
  FTexts.Free;
  FNames.Free;
  FProduced.Free;
  inherited;  // dl:ok inherited-bare@246d -- REVIEWED 2026-10-19: the direct ancestor method is the intended one
end;

function TOutputWriter.ResolvePath(const pRelPath: string): string;
var
  lRel, lPart: string;
begin
  lRel := pRelPath.Replace('/', '\');
  if (lRel = '') or TPath.IsPathRooted(lRel) or (Pos(':', lRel) > 0) then
    raise EFeatureGen.CreateFmt('output path "%s" is not relative to the output root', [pRelPath]);
  for lPart in lRel.Split(['\']) do
    if lPart = '..' then
      raise EFeatureGen.CreateFmt('output path "%s" leaves the output root', [pRelPath]);
  Result := TPath.GetFullPath(TPath.Combine(FRoot, lRel));
  if not Result.StartsWith(FRoot + '\', True) then
    raise EFeatureGen.CreateFmt('output path "%s" leaves the output root', [pRelPath]);
end;

procedure TOutputWriter.Store(const pRelPath: string; const pBytes: TBytes);
var
  lFull, lKey, lOld, lNew: string;
  lExisting: TBytes;
  lDiffers: Boolean;
begin
  lFull := ResolvePath(pRelPath);
  lKey := Copy(lFull, Length(FRoot) + 2, MaxInt);
  FProduced.AddOrSetValue(LowerCase(lKey), True);
  FNames.AddOrSetValue(LowerCase(lKey), lKey);
  lDiffers := True;
  if TFile.Exists(lFull) then
  begin
    lExisting := TFile.ReadAllBytes(lFull);
    lDiffers := (Length(lExisting) <> Length(pBytes))
      or ((Length(pBytes) > 0) and not CompareMem(@lExisting[0], @pBytes[0], Length(pBytes)));
    if lDiffers then
    begin
      lOld := TEncoding.ANSI.GetString(lExisting);
      lNew := TEncoding.ANSI.GetString(pBytes);
      FChanged.Add(lKey + #13#10 + DiffHead(lOld, lNew));
    end;
  end
  else
    FChanged.Add(lKey + #13#10 + '@@ new file (' + IntToStr(Length(pBytes)) + ' bytes)' + #13#10);
  if lDiffers and not FCheckOnly then
  begin
    ForceDirectories(ExtractFilePath(lFull));
    TFile.WriteAllBytes(lFull, pBytes);
    FWritten.Add(lKey);
  end;
end;

procedure TOutputWriter.Put(const pRelPath, pText: string; const pContext: string);
var
  lI, lLine: Integer;
  lNorm: string;
begin
  lLine := 1;
  for lI := 1 to Length(pText) do
  begin
    if pText[lI] > #127 then
      raise EFeatureGen.CreateFmt('%s: non-ASCII character U+%.4X at line %d (file %s)',
        [pContext, Ord(pText[lI]), lLine, pRelPath]);
    if pText[lI] = #10 then
      Inc(lLine);
  end;
  lNorm := pText.Replace(#13#10, #10).Replace(#13, #10).Replace(#10, #13#10);
  Store(pRelPath, TEncoding.ASCII.GetBytes(lNorm));
  FTexts.AddOrSetValue(LowerCase(pRelPath.Replace('/', '\')), pText.Replace(#13#10, #10).Replace(#13, #10));
end;

function TOutputWriter.ProducedFiles: TArray<string>;
begin
  Result := FNames.Values.ToArray;
end;

function TOutputWriter.TextOf(const pRelPath: string): string;
begin
  if not FTexts.TryGetValue(LowerCase(pRelPath.Replace('/', '\')), Result) then
    Result := '';
end;

procedure TOutputWriter.PutBinary(const pRelPath, pSourceFile: string);
begin
  if not TFile.Exists(pSourceFile) then
    raise EFeatureGen.CreateFmt('binary source "%s" does not exist (for %s)', [pSourceFile, pRelPath]);
  Store(pRelPath, TFile.ReadAllBytes(pSourceFile));
end;

function TOutputWriter.Finish: TOutputResult;
var
  lFile, lKey, lDir: string;
begin
  if FOwnsRoot and TDirectory.Exists(FRoot) then
  begin
    for lFile in TDirectory.GetFiles(FRoot, '*', TSearchOption.soAllDirectories) do
    begin
      lKey := Copy(lFile, Length(FRoot) + 2, MaxInt);
      if FProduced.ContainsKey(LowerCase(lKey)) then
        Continue;
      if FCheckOnly then
        FChanged.Add(lKey + #13#10 + '@@ stale file (would be removed)' + #13#10)
      else
      begin
        TFile.Delete(lFile);
        FRemoved.Add(lKey);
      end;
    end;
    if not FCheckOnly then
      for lDir in TDirectory.GetDirectories(FRoot, '*', TSearchOption.soAllDirectories) do
        if TDirectory.Exists(lDir) and TDirectory.IsEmpty(lDir) then
          TDirectory.Delete(lDir);
  end;
  Result.Written := FWritten.ToArray;
  Result.Changed := FChanged.ToArray;
  Result.Removed := FRemoved.ToArray;
end;

end.
