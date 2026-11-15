unit DRagLint.V151.Dispatch;

{ Wave v151 (1.51.0-alpha) lane FRAME: the ONE place that calls the fifteen v151
  rule-lane units. The CLI hooks call only this unit; the catalog learns the v151
  rows through TRuleCatalog's provider list (RegisterProviderRules), filled in
  this unit's initialization. The lane order below is fixed and alphabetical:
  APP CMP DFMA DFMB DS EXC MEM OO RTLCOLL RTLSTR STY THRA THRB TXT TYP.
  Owned by FRAME; a rule lane never edits it. }

interface

uses
  System.SysUtils
  , DRagLint.Core.Model
  , DRagLint.Lint.RuleCatalog
  , DRagLint.V151.Api
  ;

type
  /// <summary>Calls every v151 lane unit in a fixed order and merges their findings.</summary>
  /// <remarks>Stateless after unit initialization (the declaration list is built
  /// once there), so every method is safe to call from any thread the caller
  /// already lints on. With no lane declaring a rule, Wants is always False and
  /// the CLI hooks cost one boolean test per file.</remarks>
  TV151Dispatch = class
  public
    /// <summary>Every declaration of every lane (new rules and host expansions), lane order.</summary>
    /// <returns>A copy of the start-up list.</returns>
    class function Decls: TArray<TV151RuleDecl>; static;
    /// <summary>The catalog rows of the NEW v151 rules (host expansions excluded).</summary>
    /// <returns>One TRuleInfo per vdkNewRule declaration, Source = 'builtin'.</returns>
    class function CatalogRows: TArray<TRuleInfo>; static;
    /// <summary>Every rule id a lane may emit (new ids and host ids), lowercase.</summary>
    /// <returns>Distinct ids; empty while every lane is a stub.</returns>
    class function RuleIds: TArray<string>; static;
    /// <summary>Does this run need the v151 lanes at all?</summary>
    /// <param name="ANarrowRule">The run's --rule, '' for all.</param>
    /// <returns>False when no lane declares anything, or when --rule names an id no lane declares.</returns>
    class function Wants(const ANarrowRule: string): Boolean; static;
    /// <summary>Per-file pass: every lane's CheckFile, then CheckRawBytes on the .pas, then
    /// (sibling form present) CheckDfm and CheckRawBytes on the .dfm.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <returns>All findings, narrowed to ACtx.NarrowRule.</returns>
    /// <remarks>An exception in one lane is reported on stderr and that lane's
    /// findings for this file are dropped; the other lanes still run.</remarks>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Every lane's CheckDfm for ACtx.DfmPath (nil when there is no sibling form).</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <returns>Findings, narrowed.</returns>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Every lane's CheckRawBytes for one file's bytes.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">ACtx.Path or ACtx.DfmPath; read from disk here.</param>
    /// <returns>Findings, narrowed; nil when the file cannot be read.</returns>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string): TArray<TLintFinding>; static;
    /// <summary>Project-wide pass (lint-all): every lane's CheckProject.</summary>
    /// <param name="ACtx">The project.</param>
    /// <returns>Findings, narrowed.</returns>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.Generics.Collections
  , System.IOUtils
  , DRagLint.V151.APP
  , DRagLint.V151.CMP
  , DRagLint.V151.DFMA
  , DRagLint.V151.DFMB
  , DRagLint.V151.DS
  , DRagLint.V151.EXC
  , DRagLint.V151.MEM
  , DRagLint.V151.OO
  , DRagLint.V151.RTLCOLL
  , DRagLint.V151.RTLSTR
  , DRagLint.V151.STY
  , DRagLint.V151.THRA
  , DRagLint.V151.THRB
  , DRagLint.V151.TXT
  , DRagLint.V151.TYP
  ;

type
  TFileCheck  = reference to function(const ACtx: TV151FileCtx): TArray<TLintFinding>;
  TBytesCheck = reference to function(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;
  TProjCheck  = reference to function(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;
  TCatalogFn  = reference to procedure(const ADecls: TList<TV151RuleDecl>);

  { One lane's five entry points, so the fixed order is written exactly once. }
  TLaneEntry = record
    Name   : string;
    Catalog: TCatalogFn;
    OnFile : TFileCheck;
    OnDfm  : TFileCheck;
    OnBytes: TBytesCheck;
    OnProj : TProjCheck;
  end;

var
  GLanes: TArray<TLaneEntry>;
  GDecls: TArray<TV151RuleDecl>;
  GIds  : TArray<string>;

function Lane(const AName: string; const ACatalog: TCatalogFn; const AOnFile, AOnDfm: TFileCheck;
  const AOnBytes: TBytesCheck; const AOnProj: TProjCheck): TLaneEntry;
begin
  Result.Name   := AName;
  Result.Catalog:= ACatalog;
  Result.OnFile := AOnFile;
  Result.OnDfm  := AOnDfm;
  Result.OnBytes:= AOnBytes;
  Result.OnProj := AOnProj;
end;

procedure BuildLanes;
begin
  GLanes:= [
    Lane('APP',     TV151APPRules.Catalog,     TV151APPRules.CheckFile,     TV151APPRules.CheckDfm,     TV151APPRules.CheckRawBytes,     TV151APPRules.CheckProject),
    Lane('CMP',     TV151CMPRules.Catalog,     TV151CMPRules.CheckFile,     TV151CMPRules.CheckDfm,     TV151CMPRules.CheckRawBytes,     TV151CMPRules.CheckProject),
    Lane('DFMA',    TV151DFMARules.Catalog,    TV151DFMARules.CheckFile,    TV151DFMARules.CheckDfm,    TV151DFMARules.CheckRawBytes,    TV151DFMARules.CheckProject),
    Lane('DFMB',    TV151DFMBRules.Catalog,    TV151DFMBRules.CheckFile,    TV151DFMBRules.CheckDfm,    TV151DFMBRules.CheckRawBytes,    TV151DFMBRules.CheckProject),
    Lane('DS',      TV151DSRules.Catalog,      TV151DSRules.CheckFile,      TV151DSRules.CheckDfm,      TV151DSRules.CheckRawBytes,      TV151DSRules.CheckProject),
    Lane('EXC',     TV151EXCRules.Catalog,     TV151EXCRules.CheckFile,     TV151EXCRules.CheckDfm,     TV151EXCRules.CheckRawBytes,     TV151EXCRules.CheckProject),
    Lane('MEM',     TV151MEMRules.Catalog,     TV151MEMRules.CheckFile,     TV151MEMRules.CheckDfm,     TV151MEMRules.CheckRawBytes,     TV151MEMRules.CheckProject),
    Lane('OO',      TV151OORules.Catalog,      TV151OORules.CheckFile,      TV151OORules.CheckDfm,      TV151OORules.CheckRawBytes,      TV151OORules.CheckProject),
    Lane('RTLCOLL', TV151RTLCOLLRules.Catalog, TV151RTLCOLLRules.CheckFile, TV151RTLCOLLRules.CheckDfm, TV151RTLCOLLRules.CheckRawBytes, TV151RTLCOLLRules.CheckProject),
    Lane('RTLSTR',  TV151RTLSTRRules.Catalog,  TV151RTLSTRRules.CheckFile,  TV151RTLSTRRules.CheckDfm,  TV151RTLSTRRules.CheckRawBytes,  TV151RTLSTRRules.CheckProject),
    Lane('STY',     TV151STYRules.Catalog,     TV151STYRules.CheckFile,     TV151STYRules.CheckDfm,     TV151STYRules.CheckRawBytes,     TV151STYRules.CheckProject),
    Lane('THRA',    TV151THRARules.Catalog,    TV151THRARules.CheckFile,    TV151THRARules.CheckDfm,    TV151THRARules.CheckRawBytes,    TV151THRARules.CheckProject),
    Lane('THRB',    TV151THRBRules.Catalog,    TV151THRBRules.CheckFile,    TV151THRBRules.CheckDfm,    TV151THRBRules.CheckRawBytes,    TV151THRBRules.CheckProject),
    Lane('TXT',     TV151TXTRules.Catalog,     TV151TXTRules.CheckFile,     TV151TXTRules.CheckDfm,     TV151TXTRules.CheckRawBytes,     TV151TXTRules.CheckProject),
    Lane('TYP',     TV151TYPRules.Catalog,     TV151TYPRules.CheckFile,     TV151TYPRules.CheckDfm,     TV151TYPRules.CheckRawBytes,     TV151TYPRules.CheckProject)];
end;

procedure BuildDecls;
var
  L   : TList<TV151RuleDecl>;
  Seen: TDictionary<string, Boolean>;
begin
  L:= TList<TV151RuleDecl>.Create;
  Seen:= TDictionary<string, Boolean>.Create;
  try
    for var E: TLaneEntry in GLanes do E.Catalog(L);
    GDecls:= L.ToArray;
    GIds:= nil;
    for var D: TV151RuleDecl in GDecls do
      if not Seen.ContainsKey(LowerCase(D.Id)) then
      begin
        Seen.Add(LowerCase(D.Id), True);
        GIds:= GIds + [LowerCase(D.Id)];
      end;
  finally
    Seen.Free;
    L.Free;
  end;
end;

procedure LaneFailed(const ALane, AWhere, APath: string; E: Exception);
begin
  Writeln(ErrOutput, Format('v151 lane %s: %s skipped for %s (%s: %s)', [ALane, AWhere, ExtractFileName(APath), E.ClassName, E.Message]));
end;

{ TV151Dispatch }

class function TV151Dispatch.Decls: TArray<TV151RuleDecl>;
begin
  Result:= Copy(GDecls);
end;

class function TV151Dispatch.CatalogRows: TArray<TRuleInfo>;
begin
  Result:= nil;
  for var D: TV151RuleDecl in GDecls do
    if D.Kind = vdkNewRule then
    begin
      var R: TRuleInfo:= Default(TRuleInfo);
      R.Id             := D.Id;
      R.Category       := D.Category;
      R.DefaultSeverity:= D.Severity;
      R.Title          := D.Title;
      R.Source         := 'builtin';
      R.DefaultEnabled := D.Enabled;
      R.Params         := D.Params;
      Result:= Result + [R];
    end;
end;

class function TV151Dispatch.RuleIds: TArray<string>;
begin
  Result:= Copy(GIds);
end;

class function TV151Dispatch.Wants(const ANarrowRule: string): Boolean;
begin
  if Length(GIds) = 0 then Exit(False);
  if ANarrowRule = '' then Exit(True);
  for var Id: string in GIds do
    if SameText(Id, ANarrowRule) then Exit(True);
  Result:= False;
end;

class function TV151Dispatch.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if Length(GIds) = 0 then Exit;
  for var E: TLaneEntry in GLanes do
    try
      Result:= Result + E.OnFile(ACtx);
    except  // dl:ok try-except-swallowed@e084 -- REVIEWED 2026-11-13 v151 FRAME: logged to stderr by LaneFailed; one lane failing must not stop the others
      on X: Exception do LaneFailed(E.Name, 'CheckFile', ACtx.Path, X);
    end;
  Result:= V151Narrow(Result, ACtx.NarrowRule) + CheckRawBytes(ACtx, ACtx.Path) + CheckDfm(ACtx);
  if ACtx.DfmPath <> '' then Result:= Result + CheckRawBytes(ACtx, ACtx.DfmPath);
end;

class function TV151Dispatch.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if (Length(GIds) = 0) or (ACtx.DfmPath = '') then Exit;
  for var E: TLaneEntry in GLanes do
    try
      Result:= Result + E.OnDfm(ACtx);
    except  // dl:ok try-except-swallowed@a178 -- REVIEWED 2026-11-13 v151 FRAME: logged to stderr by LaneFailed; one lane failing must not stop the others
      on X: Exception do LaneFailed(E.Name, 'CheckDfm', ACtx.DfmPath, X);
    end;
  Result:= V151Narrow(Result, ACtx.NarrowRule);
end;

class function TV151Dispatch.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string): TArray<TLintFinding>;
var
  Bytes: TBytes;
begin
  Result:= nil;
  if (Length(GIds) = 0) or (AFilePath = '') then Exit;
  try
    Bytes:= TFile.ReadAllBytes(AFilePath);
  except  // dl:ok try-except-swallowed@1bbf -- REVIEWED 2026-11-13 v151 FRAME: logged to stderr by LaneFailed; one lane failing must not stop the others
    on X: Exception do
    begin
      LaneFailed('-', 'CheckRawBytes', AFilePath, X);
      Exit;
    end;
  end;
  for var E: TLaneEntry in GLanes do
    try
      Result:= Result + E.OnBytes(ACtx, AFilePath, Bytes);
    except  // dl:ok try-except-swallowed@0740 -- REVIEWED 2026-11-13 v151 FRAME: logged to stderr by LaneFailed; one lane failing must not stop the others
      on X: Exception do LaneFailed(E.Name, 'CheckRawBytes', AFilePath, X);
    end;
  Result:= V151Narrow(Result, ACtx.NarrowRule);
end;

class function TV151Dispatch.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if Length(GIds) = 0 then Exit;
  for var E: TLaneEntry in GLanes do
    try
      Result:= Result + E.OnProj(ACtx);
    except  // dl:ok try-except-swallowed@a704 -- REVIEWED 2026-11-13 v151 FRAME: logged to stderr by LaneFailed; one lane failing must not stop the others
      on X: Exception do LaneFailed(E.Name, 'CheckProject', ACtx.ProjectPath, X);
    end;
  Result:= V151Narrow(Result, ACtx.NarrowRule);
end;

initialization
  BuildLanes;  // dl:ok heavy-initialization@6546 -- REVIEWED 2026-11-14 v151 INT: BuildLanes passes the lanes' Check* hooks as method references (no parentheses); nothing runs them at init -- the rule reads the references as calls
  BuildDecls;
  RegisterProviderRules(TV151Dispatch.CatalogRows);

end.
