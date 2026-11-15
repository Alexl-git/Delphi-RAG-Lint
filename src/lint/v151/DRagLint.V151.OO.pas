unit DRagLint.V151.OO;

{ Wave v151 lane OO -- object-model rules (Equals/GetHashCode, event calls, interface GUIDs, DLL exports, money as float, legacy containers).
  Scaffold created EMPTY by lane FRAME; lane OO owns this unit, its
  DRagLint.V151.OO.Support helpers and DRagLint.Fix.V151.OO. Called only by
  DRagLint.V151.Dispatch. How-to: C:\TEMP\claude\lanes\v151\FRAME\HOWTO-RULE-LANE.md. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

type
  /// <summary>Checker entry points of v151 lane OO; every method is called by TV151Dispatch.</summary>
  /// <remarks>Stateless; class methods only. A method that has nothing to check returns nil.
  /// Findings for ids not declared in Catalog are a lane bug: --rule would never reach them.</remarks>
  TV151OORules = class
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
  System.StrUtils
  , DRagLint.Core.Interfaces // dl:ok unused-unit-in-uses -- REVIEWED 2026-11-14 v151 OO: TLintFinding arrives via this unit (frame convention); removal not compile-verified
  , DRagLint.V151.OO.Support
  ;

class procedure TV151OORules.Catalog(const ADecls: TList<TV151RuleDecl>);
begin
  ADecls.Add(V151Rule(EQUALS_HASH_RULE, 'bug-patterns', 'warning', 'Equals overridden without GetHashCode (or the reverse)'));
  ADecls.Add(V151Rule(EVENT_CALL_RULE, 'bug-patterns', 'warning', 'Event field called without an Assigned check'));
  ADecls.Add(V151Rule(DUP_GUID_RULE, 'bug-patterns', 'warning', 'Two interfaces declare the same GUID'));
  ADecls.Add(V151Rule(DLL_EXPORT_RULE, 'bug-patterns', 'warning', 'Exported routine has no calling convention'));
  ADecls.Add(V151Rule(MONEY_FLOAT_RULE, 'bug-patterns', 'warning', 'Money amount held as floating point'));
  ADecls.Add(V151Rule(DEFAULT_PARAM_RULE, 'structure', 'hint', 'Parameter with a default value', False));
  ADecls.Add(V151Rule(TRIVIAL_ACCESSOR_RULE, 'refactoring', 'hint', 'Accessor method only reads or writes a field', False));
  ADecls.Add(V151Rule(UNNEEDED_FORWARD_RULE, 'dead-code', 'hint', 'Forward declaration that is not needed', False));
  ADecls.Add(V151Rule(LEGACY_TLIST_RULE, 'modernize', 'hint', 'Non-generic list read through a cast', False));
  ADecls.Add(V151Rule(LEGACY_STACK_QUEUE_RULE, 'modernize', 'hint', 'Non-generic stack or queue read through a cast', False));
end;

class function TV151OORules.CheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
begin
  var Ctx: TV151FileCtx:= ACtx;
  Result:= OOCheckFile(ACtx.Path,
    function(S: string): Boolean
    begin
      Result:= Ctx.Wants(S);
    end);
end;

class function TV151OORules.CheckDfm(const ACtx: TV151FileCtx): TArray<TLintFinding>; // dl:ok unused-parameter -- REVIEWED 2026-11-14 v151 OO: fixed frame hook signature, OO has no DFM rule
begin
  Result:= nil;
end;

class function TV151OORules.CheckRawBytes(const ACtx: TV151FileCtx; const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>; // dl:ok unused-parameter -- REVIEWED 2026-11-14 v151 OO: fixed frame hook signature, OO has no raw-byte rule
begin
  Result:= nil;
end;

class function TV151OORules.CheckProject(const ACtx: TV151ProjectCtx): TArray<TLintFinding>;
const
  MAX_INTERFACES = 1000000; // dl:ok unreadable-literal -- REVIEWED 2026-11-14 v151 OO: sanity cap, not a magnitude to read
begin
  Result:= nil;
  if (ACtx.Store = nil) or not ACtx.Wants(DUP_GUID_RULE) then Exit;
  { Cross-unit duplicate GUID: the index stores the literal GUID text of each interface in
    symbols.signature (EXT, 1.51); a constant reference or '' is skipped (value not stored).
    Same-file duplicates are the per-file check's job, and a dispinterface sharing its dual
    interface's GUID lives in the same file, so only a group spanning two files is reported. }
  var Groups: TObjectDictionary<string, TList<TSymbol>>:= TObjectDictionary<string, TList<TSymbol>>.Create([doOwnsValues]);
  var Found : TList<TLintFinding>:= TList<TLintFinding>.Create;
  try
    for var Sym: TSymbol in ACtx.Store.FindSymbolsByKind('interface', False, MAX_INTERFACES) do
    begin
      var Key: string:= UpperCase(Sym.Signature).Trim;
      if not StartsStr('''', Key) then Continue;
      var L: TList<TSymbol>;
      if not Groups.TryGetValue(Key, L) then
      begin
        L:= TList<TSymbol>.Create;
        Groups.Add(Key, L);
      end;
      L.Add(Sym);
    end;
    for var L: TList<TSymbol> in Groups.Values do
    begin
      if L.Count < 2 then Continue;
      var Path0: string:= ACtx.Store.GetFilePath(L[0].FileId);
      for var I: Integer:= 1 to L.Count - 1 do
      begin
        if L[I].FileId = L[0].FileId then Continue;
        var F: TLintFinding:= Default(TLintFinding);
        F.RuleId   := DUP_GUID_RULE;
        F.FileId   := L[I].FileId;
        F.FilePath := ACtx.Store.GetFilePath(L[I].FileId);
        F.StartLine:= L[I].StartLine;
        F.StartCol := 1;
        F.EndLine  := L[I].StartLine;
        F.EndCol   := 1;
        F.Severity := 'warning';
        F.SymbolName:= L[I].Name;
        F.Message  := Format('Interface %s has the same GUID as %s in %s; Supports and as cannot tell '
          + 'the two apart. Give one of them a new GUID.', [L[I].Name, L[0].Name, ExtractFileName(Path0)]);
        Found.Add(F);
      end;
    end;
    Result:= Found.ToArray;
  finally
    Found.Free;
    Groups.Free;
  end;
end;

end.
