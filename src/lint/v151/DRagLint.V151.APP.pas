unit DRagLint.V151.APP;

{ Wave v151 lane APP -- application-level rules (TLS verification, console/service UI calls, DUnitX asserts, contract units, weak ciphers, Win64 asm, writeln in GUI apps).
  Scaffold created EMPTY by lane FRAME; lane APP owns this unit, its
  DRagLint.V151.APP.Support helpers and DRagLint.Fix.V151.APP. Called only by
  DRagLint.V151.Dispatch. How-to: C:\TEMP\claude\lanes\v151\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;


type
  /// <summary>Checker entry points of v151 lane APP; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV151APPRules = class
  public
    /// <summary>Declares every rule id this lane may emit: new ids (V151Rule) and host ids of in-place expansions (V151Host).</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.</remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas (parse tree, index, library).</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the .pas unit's sibling form file.</summary>
    /// <param name="ACtx">The file being linted; ACtx.DfmPath is not empty when this is called.</param>
    /// <returns>Findings (FilePath may be the .dfm); nil when none.</returns>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the raw bytes of the .pas and of its sibling .dfm, before any decoding.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">The file the bytes come from (ACtx.Path or ACtx.DfmPath).</param>
    /// <param name="ABytes">The file content exactly as on disk.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check, lint-all only, run once after the per-file loop.</summary>
    /// <param name="ACtx">The project; Store is not nil.</param>
    /// <returns>Findings; nil when none.</returns>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  DRagLint.V151.APP.Support
  ;

class procedure TV151APPRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(RULE_TLS_VERIFY_OFF, 'security', 'warning',
    'TLS certificate verification is switched off'));
  ADecls.Add(V151Rule(RULE_UI_CALL, 'bug-patterns', 'warning',
    'Dialog call in a console program or a Windows service'));
  ADecls.Add(V151Rule(RULE_DUNITX_NO_ASSERT, 'other', 'info',
    'DUnitX test method that checks nothing'));
  ADecls.Add(V151Rule(RULE_CONTRACT_CLASS, 'policy', 'info',
    'Contract unit (Intf / Interfaces / Contracts) declares a class', False));
  ADecls.Add(V151Rule(RULE_WEAK_CIPHER, 'security', 'warning',
    'Broken cipher or mode (DES, 3DES, RC2, RC4, ECB)'));
  ADecls.Add(V151Rule(RULE_ASM_NO_WIN64, 'platform', 'warning',
    'asm block without a 64-bit variant'));
  ADecls.Add(V151Rule(RULE_WRITELN_GUI, 'platform', 'warning',
    'Write / WriteLn in a program without a console'));
end;

class function TV151APPRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Src: TAppSrc;
  Acc: TList<TLintFinding>;
  Text: string;
begin
  Result:= nil;
  if not (ACtx.Wants(RULE_TLS_VERIFY_OFF) or ACtx.Wants(RULE_UI_CALL) or ACtx.Wants(RULE_DUNITX_NO_ASSERT)  // dl:ok boolean-expression-complexity@6f93 -- REVIEWED 2026-11-14 v151 INT: one flat predicate over fixed values; splitting it does not make it clearer
    or ACtx.Wants(RULE_CONTRACT_CLASS) or ACtx.Wants(RULE_WEAK_CIPHER) or ACtx.Wants(RULE_ASM_NO_WIN64)
    or ACtx.Wants(RULE_WRITELN_GUI)) then Exit;
  Text:= ReadAppSource(ACtx.Path);
  if Text = '' then Exit;
  Src:= TAppSrc.Create(Text);
  Acc:= TList<TLintFinding>.Create;
  try
    if ACtx.Wants(RULE_TLS_VERIFY_OFF)   then TAppChecks.TlsVerificationDisabled(Src, ACtx.Path, Acc);
    if ACtx.Wants(RULE_UI_CALL)          then TAppChecks.UiCallInConsoleOrService(Src, ACtx.Path, Acc);
    if ACtx.Wants(RULE_DUNITX_NO_ASSERT) then TAppChecks.DunitxTestWithoutAssert(Src, ACtx.Path, Acc);
    if ACtx.Wants(RULE_CONTRACT_CLASS)   then TAppChecks.ContractUnitDeclaresClass(Src, ACtx.Path, Acc);
    if ACtx.Wants(RULE_WEAK_CIPHER)      then TAppChecks.WeakCipher(Src, ACtx.Path, Acc);
    if ACtx.Wants(RULE_ASM_NO_WIN64)     then TAppChecks.AsmWithoutWin64Variant(Src, ACtx.Path, Acc);
    if ACtx.Wants(RULE_WRITELN_GUI)      then TAppChecks.WritelnInGuiApp(Src, ACtx.Path, Acc);
    Result:= Acc.ToArray;
  finally
    Acc.Free;
    Src.Free;
  end;
end;

class function TV151APPRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@5b80 -- REVIEWED 2026-11-14 v151 INT: fixed TV151 frame hook signature; this lane has no rule on that hook
begin
  Result:= nil;
end;

class function TV151APPRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@8835 -- REVIEWED 2026-11-14 v151 INT: fixed TV151 frame hook signature; this lane has no rule on that hook
begin
  Result:= nil;
end;

class function TV151APPRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@cbb0 -- REVIEWED 2026-11-14 v151 INT: fixed TV151 frame hook signature; this lane has no rule on that hook
begin
  Result:= nil;
end;

end.
