unit DRagLint.Refactor.ScratchGate;

// ---------------------------------------------------------------------------
// The gate of a NEW, design-stage rewrite: the rewrite builds on a mirror of the project BEFORE it reaches the tree, then
// goes through the ordinary compile gate. Spec: docs\superpowers\specs\2026-11-06-extract-interface-lazy-init.md
// ---------------------------------------------------------------------------

interface

uses
  FireDAC.Comp.Client,
  DRagLint.Refactor.CompileGate;

const
  /// <summary>Refusal kind: the files have no common folder (two drives), so no mirror keeps their relative paths.</summary>
  CScratchUnavailable = 'scratch-unavailable';
  /// <summary>Refusal kind: the mirror builds without the rewrite and fails with it.</summary>
  CScratchCompileError = 'scratch-compile-error';
  /// <summary>Refusal kind: the mirror does not build even without the rewrite: the mirror cannot prove anything.</summary>
  CScratchUnusable = 'scratch-unusable';

/// <summary>Builds a rewrite on a scratch mirror of the project and, only when that passes, hands it to ApplyGated.</summary>
/// <param name="pConn">The project index: its `files` rows name the folders to mirror.</param>
/// <param name="pReq">The rewrite. LogDir is the scratch: the mirror lives in it, it must not exist or may be empty.</param>
/// <returns>The gate's outcome; Refusal is one of the CScratch* kinds when the mirror refused, in which case nothing in the
/// tree was written and Detail names the first dcc line.</returns>
/// <remarks>The mirror is the project's folder plus every folder holding an indexed file, source and resource extensions only,
/// under their common ancestor. Output folders are forced into the scratch on the msbuild line, so an absolute output path
/// in the project cannot overwrite its real exe. A unit reached by an absolute search path builds from the original: that is
/// why ApplyGated still follows. Never raises for a build or copy failure. Not thread-safe (the gate's globals).</remarks>
function ApplyThroughScratch(pConn: TFDConnection; const pReq: TGateRequest): TGateOutcome;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.StrUtils, System.RegularExpressions,
  System.Generics.Collections;

const
  CMirrorExtensions: array[0..15] of string = ('.pas', '.dpr', '.dpk', '.dproj', '.inc', '.dfm', '.fmx', '.res', '.rc', '.dcr',
    '.optset', '.obj', '.o', '.a', '.lib', '.tlb');
  CMirrorFolder = 'mirror';

// The longest folder both paths lie in, each with a trailing delimiter; '' when there is none.
function CommonFolder(const pA, pB: string): string;
begin
  Result:= '';
  for var Part in pA.Split([PathDelim]) do
  begin
    if Part = '' then Continue;
    var Next:= Result + Part + PathDelim;
    if not StartsText(Next, pB) then Break;
    Result:= Next;
  end;
end;

// Every folder to mirror, distinct, in lower case keys.
function FoldersToMirror(pConn: TFDConnection; const pProject: string): TArray<string>;
begin
  var Seen:= TDictionary<string, string>.Create;
  var Q:= TFDQuery.Create(nil);
  try
    var Add:= procedure(const pDir: string)
      begin
        var D:= IncludeTrailingPathDelimiter(pDir);
        if not Seen.ContainsKey(LowerCase(D)) then Seen.Add(LowerCase(D), D);
      end;
    Add(ExtractFilePath(pProject));
    Q.Connection:= pConn;
    Q.SQL.Text:= 'SELECT path FROM files';
    Q.Open;
    while not Q.Eof do
    begin
      var Dir:= ExtractFilePath(Q.Fields[0].AsString);
      if (Dir <> '') and TDirectory.Exists(Dir) then Add(Dir);
      Q.Next;
    end;
    Result:= Seen.Values.ToArray;
  finally
    Q.Free;
    Seen.Free;
  end;
end;

// Copies the folders under pTarget and returns the common ancestor; '' when they have none.
function MirrorProject(const pFolders: TArray<string>; const pTarget: string): string;
begin
  Result:= '';
  if Length(pFolders) = 0 then Exit;
  Result:= pFolders[0];
  for var Dir in pFolders do
  begin
    Result:= CommonFolder(Result, Dir);
    if Result = '' then Exit;
  end;
  for var Dir in pFolders do
  begin
    var Into:= TPath.Combine(pTarget, Copy(Dir, Length(Result) + 1, MaxInt));
    TDirectory.CreateDirectory(Into);  // dl:ok taint-path-traversal@581a -- the path is the run's own fresh scratch name under C:\TEMP or the operator's --project: local input, no privilege crossed
    for var F in TDirectory.GetFiles(Dir) do
      if MatchText(ExtractFileExt(F), CMirrorExtensions) then
        TFile.Copy(F, TPath.Combine(Into, ExtractFileName(F)), True);  // dl:ok taint-path-traversal@c925 -- the path is the run's own fresh scratch name under C:\TEMP or the operator's --project: local input, no privilege crossed
  end;
end;

// The msbuild run on the mirror: the gate's recipe, with the outputs forced into the scratch.
function BuildMirror(const pProject, pPlatform, pScratch, pTag: string): TArray<string>;
const
  CDccError = '\b(error E\d+|fatal F\d+|E\d{4}\b.*\[dcc|error MSB\d+)';
begin
  Result:= nil;
  var Platform:= if pPlatform = '' then 'Win64' else pPlatform;
  var Out_:= TPath.Combine(pScratch, 'out_' + pTag);
  TDirectory.CreateDirectory(Out_);  // dl:ok taint-path-traversal@711c -- the path is the run's own fresh scratch name under C:\TEMP or the operator's --project: local input, no privilege crossed
  var Bat:= TPath.Combine(pScratch, pTag + '.bat');
  var Log:= TPath.Combine(pScratch, pTag + '.log');
  var Text:= '@echo off'#13#10 + 'call "' + BuildEnvBat + '"'#13#10 + 'cd /d "' + ExtractFilePath(pProject) + '"'#13#10 +
    'msbuild /t:Build /p:Config=Debug /p:Platform=' + Platform + ' /v:minimal' +
    ' "/p:DCC_ExeOutput=' + Out_ + '" "/p:DCC_DcuOutput=' + Out_ + '" "/p:DCC_BplOutput=' + Out_ + '" "/p:DCC_DcpOutput=' + Out_ + '"' +
    ' "' + ExtractFileName(pProject) + '"'#13#10 + 'exit /b %ERRORLEVEL%'#13#10;
  TFile.WriteAllText(Bat, Text, TEncoding.ASCII);  // dl:ok taint-path-traversal@d913 -- the path is the run's own fresh scratch name under C:\TEMP or the operator's --project: local input, no privilege crossed
  var TimedOut: Boolean;
  var Code:= RunBounded('scratch build', 'cmd.exe /c "' + Bat + '"', Log, BuildTimeoutMs(pProject), TimedOut);
  if TimedOut then
  begin
    Result:= ['the scratch build ran past --build-timeout'];
    Exit;
  end;
  if TFile.Exists(Log) then
    for var L in TFile.ReadAllLines(Log) do  // dl:ok taint-path-traversal@19f3 -- the path is the run's own fresh scratch name under C:\TEMP or the operator's --project: local input, no privilege crossed
      if TRegEx.IsMatch(L, CDccError, [roIgnoreCase]) then Result:= Result + [Trim(L)];
  if (Code <> 0) and (Length(Result) = 0) then Result:= [Format('msbuild exited %d; see %s', [Code, Log])];
end;

function ApplyThroughScratch(pConn: TFDConnection; const pReq: TGateRequest): TGateOutcome;
begin
  Result:= Default(TGateOutcome);
  GGateVerb:= if pReq.Verb <> '' then pReq.Verb else GGateVerb;
  GRsVars  := pReq.RsVars;
  if not CompilerAvailable then
  begin
    Result.Refusal:= CGateCompilerUnavailable;
    Result.Detail := 'the RAD Studio build environment was not found: the compile gate cannot run; nothing written';
    Exit;
  end;
  var Scratch:= IncludeTrailingPathDelimiter(pReq.LogDir);
  var Mirror := TPath.Combine(Scratch, CMirrorFolder);
  try
    var Root:= MirrorProject(FoldersToMirror(pConn, pReq.Project), Mirror);
    if Root = '' then
    begin
      Result.Refusal:= CScratchUnavailable;
      Result.Detail := 'the project''s files have no common folder (two drives?); no mirror keeps their relative paths; nothing written';
      Exit;
    end;
    var Originals:= TDictionary<string, TBytes>.Create;
    try
      for var F in pReq.Files do
      begin
        var Into:= TPath.Combine(Mirror, Copy(ExpandFileName(F.Path), Length(Root) + 1, MaxInt));
        Originals.Add(Into, TFile.ReadAllBytes(Into));  // dl:ok taint-path-traversal@dd7e -- the path is the run's own fresh scratch name under C:\TEMP or the operator's --project: local input, no privilege crossed
        TFile.WriteAllBytes(Into, F.Bytes);  // dl:ok taint-path-traversal@59a7 -- the path is the run's own fresh scratch name under C:\TEMP or the operator's --project: local input, no privilege crossed
      end;
      var MirrorProj:= TPath.Combine(Mirror, Copy(ExpandFileName(pReq.Project), Length(Root) + 1, MaxInt));
      var Errors:= BuildMirror(MirrorProj, pReq.Platform, Scratch, 'scratch-after');
      if Length(Errors) > 0 then
      begin
        for var Pair in Originals do TFile.WriteAllBytes(Pair.Key, Pair.Value);  // dl:ok taint-path-traversal@7830 -- the path is the run's own fresh scratch name under C:\TEMP or the operator's --project: local input, no privilege crossed
        var Plain:= BuildMirror(MirrorProj, pReq.Platform, Scratch, 'scratch-baseline');
        Result.Refusal:= if Length(Plain) = 0 then CScratchCompileError else CScratchUnusable;
        Result.Detail := Format('the scratch build refused (%d line(s), first: %s); nothing written', [Length(Errors), Errors[0]]);
        Exit;
      end;
    finally
      Originals.Free;
    end;
  except
    on E: ECompileGateCancelled do
    begin
      Result.Refusal:= CGateCancelled;
      Result.Detail := 'cancelled -- nothing written';
      Exit;
    end;
    on E: Exception do
    begin
      Result.Refusal:= CScratchUnavailable;
      Result.Detail := 'the scratch copy could not be made or built: ' + E.Message + '; nothing written';
      Exit;
    end;
  end;
  Result:= ApplyGated(pReq);
end;

end.
