unit DRagLint.V156.DFMR;

{ Wave v156 (1.56.0-alpha) lane DFM-R -- dfm-god-handler (G-35) and dfm-control-overlap (G-36).
  Both rules read the text form file through the object tree of DRagLint.V151.DFMB.Support; a binary form
  file keeps them silent. Called only by DRagLint.V151.Dispatch (the ONE provider mechanism; v156 lanes reuse
  the DRagLint.V151.Api types). Both rules are OFF by default. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

const
  /// <summary>Rule id of G-35: one event handler wired to many events of one form.</summary>
  RULE_DFM_GOD_HANDLER = 'dfm-god-handler';
  /// <summary>Rule id of G-36: a visible control covers a sibling in the same parent.</summary>
  RULE_DFM_CONTROL_OVERLAP = 'dfm-control-overlap';

type
  /// <summary>Checker entry points of v156 lane DFM-R; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV156DFMRRules = class
  public
    /// <summary>Declares every rule id this lane may emit.</summary>
    /// <param name="ADecls">List to append to; owned by the caller.</param>
    /// <remarks>Called ONCE at start-up (unit initialization of DRagLint.V151.Dispatch); must not touch files or stores.
    /// Declares dfm-god-handler (structure, hint, OFF, parameter threshold = 5) and dfm-control-overlap (bug-patterns, info, OFF).</remarks>
    class procedure Catalog(const ADecls: TList<TV151RuleDecl>); static;
    /// <summary>Per-file check of one .pas; this lane has none.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <returns>nil.</returns>
    class function CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the .pas unit's sibling form file: both rules.</summary>
    /// <param name="ACtx">The file being linted; ACtx.DfmPath is not empty when this is called.</param>
    /// <returns>Findings located in the .dfm: one per handler wired to at least `threshold` events of two or more
    /// kinds (at its first binding), and one per control that covers an earlier visible sibling; nil when none or
    /// when the form file is binary or unreadable.</returns>
    /// <remarks>Threshold = ThresholdFor('dfm-god-handler', 5). Overlap needs a stored Width and Height, ignores
    /// Align, Anchors-to-the-far-edge, hidden controls, stacking parents and backdrops that contain a control.</remarks>
    class function CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; static;
    /// <summary>Per-file check of the raw bytes; this lane has none.</summary>
    /// <param name="ACtx">The file being linted.</param>
    /// <param name="AFilePath">The file the bytes come from.</param>
    /// <param name="ABytes">The file content exactly as on disk.</param>
    /// <returns>nil.</returns>
    class function CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; static;
    /// <summary>Project-wide check; this lane has none.</summary>
    /// <param name="ACtx">The project.</param>
    /// <returns>nil.</returns>
    class function CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.IOUtils
  , DRagLint.Lint.Config
  , DRagLint.Lint.RuleCatalog
  , DRagLint.V151.DFMB.Support
  , DRagLint.V156.DFMR.Support
  ;

const
  SEV_HINT = 'hint';
  SEV_INFO = 'info';
  CAT_STRUCT = 'structure';
  CAT_BUGS = 'bug-patterns';
  TITLE_GOD = 'One event handler is wired to many events of a form (a hidden dispatcher) -- split it per event or per control';
  TITLE_OVERLAP = 'A visible control covers a sibling in the same parent -- one of them is partly hidden';

procedure AddFinding(const AList: TList<TLintFinding>; const ACtx: TV151FileCtx; const ARule, ADefaultSev: string;
  ALine, ACol: Integer; const AMessage: string);
begin
  var F: TLintFinding:= Default(TLintFinding);
  F.RuleId   := ARule;
  F.FilePath := ACtx.DfmPath;
  F.StartLine:= ALine;
  F.StartCol := ACol;
  F.EndLine  := ALine;
  F.EndCol   := ACol + 1;
  F.Severity := ACtx.Cfg.ApplySeverity(ARule, ADefaultSev);
  F.Message  := AMessage;
  AList.Add(F);
end;

class procedure TV156DFMRRules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  var P: TRuleParam:= Default(TRuleParam);
  P.Name      := 'threshold';
  P.ParamType := 'int';
  P.DefaultVal:= IntToStr(DEFAULT_GOD_HANDLER_BINDINGS);
  ADecls.Add(V151Rule(RULE_DFM_GOD_HANDLER, CAT_STRUCT, SEV_HINT, TITLE_GOD, False, [P]));
  ADecls.Add(V151Rule(RULE_DFM_CONTROL_OVERLAP, CAT_BUGS, SEV_INFO, TITLE_OVERLAP, False));
end;

class function TV156DFMRRules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@e719 -- REVIEWED 2026-11-27 v156 DFM-R: signature fixed by the TV151 lane interface; this lane has no per-file source check
begin
  Result:= nil;
end;

class function TV156DFMRRules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  Result:= nil;
  if ACtx.DfmPath = '' then Exit;
  var WantsGod: Boolean:= ACtx.Wants(RULE_DFM_GOD_HANDLER);
  var WantsOverlap: Boolean:= ACtx.Wants(RULE_DFM_CONTROL_OVERLAP);
  if not (WantsGod or WantsOverlap) then Exit;
  var Model: TDfmModel;
  try
    Model:= TDfmModel.Parse(TEncoding.ANSI.GetString(TFile.ReadAllBytes(ACtx.DfmPath)));
  except  // dl:ok bare-except@8f3b, try-except-swallowed@8f3b -- REVIEWED 2026-11-27 v156 DFM-R: an unreadable form file keeps both rules silent: no finding beats a false finding
    Exit;
  end;
  var Found: TList<TLintFinding>:= TList<TLintFinding>.Create;
  try
    if WantsGod then
      for var G: TGodHandler in FindGodHandlers(Model, ACtx.Cfg.ThresholdFor(RULE_DFM_GOD_HANDLER, DEFAULT_GOD_HANDLER_BINDINGS)) do
        AddFinding(Found, ACtx, RULE_DFM_GOD_HANDLER, SEV_HINT, G.Line, G.Col,
          Format('Handler %s is wired to %d events of %d kinds (first on %s) -- a hidden dispatcher',
            [G.Handler, G.Bindings, G.EventKinds, G.Obj.ObjName]));
    if WantsOverlap then
      for var O: TOverlap in FindOverlaps(Model) do
      begin
        var Line: Integer:= O.Obj.Line;
        var Col: Integer:= 1;
        var I: Integer:= O.Obj.IndexOfProp('Left');
        if I >= 0 then
        begin
          Line:= O.Obj.Props[I].Line;
          Col := O.Obj.Props[I].Col;
        end;
        var More: string:= if O.Covered > 1 then Format(' and %d more', [O.Covered - 1]) else '';
        AddFinding(Found, ACtx, RULE_DFM_CONTROL_OVERLAP, SEV_INFO, Line, Col,
          Format('%s covers %s%s in the same parent -- one of them is partly hidden', [O.Obj.ObjName, O.Other.ObjName, More]));
      end;
    Result:= Found.ToArray;
  finally
    Found.Free;
    Model.Free;
  end;
end;

class function TV156DFMRRules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;  // dl:ok unused-parameter@2138 -- REVIEWED 2026-11-27 v156 DFM-R: signature fixed by the TV151 lane interface; this lane has no raw-byte check
begin
  Result:= nil;
end;

class function TV156DFMRRules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;  // dl:ok unused-parameter@a57e -- REVIEWED 2026-11-27 v156 DFM-R: signature fixed by the TV151 lane interface; this lane has no project-wide check
begin
  Result:= nil;
end;

end.
