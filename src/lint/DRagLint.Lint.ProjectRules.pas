unit DRagLint.Lint.ProjectRules;

{ Index-wide ("project") lint rules that need the whole symbol/refs graph rather
  than a single file's AST -- the cross-file complement to the per-file `lint`
  command and the external .scm rules. Run via `drag-lint lint-project --db`.

  These deliberately do NOT duplicate the existing find-deadcode / cycles /
  uses-audit commands; they add structure + cross-unit-API checks. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <summary>Index-wide lint rules (oversized classes; unused exported routines).</summary>
  /// <remarks>Stateless; reads the supplied open store. Never raises.</remarks>
  TProjectLintRules = class
  public
    /// <summary>Runs the project rules over AStore and returns all findings.</summary>
    /// <param name="AStore">An open, migrated symbol store; nil yields no findings.</param>
    /// <param name="ARuleId">If non-empty, only that rule id is evaluated.</param>
    /// <returns>Findings across the whole index (file paths + lines); empty if none.</returns>
    class function Run(const AStore: ISymbolStore; const ARuleId: string = ''): TArray<TLintFinding>;
  end;

implementation

class function TProjectLintRules.Run(const AStore: ISymbolStore; const ARuleId: string): TArray<TLintFinding>;
var
  Findings: TList<TLintFinding>;
  FileIds : TArray<Int64>      ;
  Fid     : Int64             ;
  Path    : string            ;
  Syms    : TArray<TSymbol>    ;
  Sym     : TSymbol           ;
  Children: TArray<TSymbol>    ;
  Ch      : TSymbol           ;
  NMethods: Integer           ;
  NFields : Integer           ;
  Parent  : TSymbol           ;

  function WantRule(const AId: string): Boolean;
  begin
    Result:= (ARuleId = '') or (ARuleId = AId);
  end;

  procedure Add(const AId, ASeverity, AMsg: string; const ASym: TSymbol);
  var
    F: TLintFinding;
  begin
    F:= Default(TLintFinding);
    F.RuleId  := AId;
    F.Severity:= ASeverity;
    F.Message := AMsg;
    F.FilePath:= Path;
    F.StartLine:= ASym.StartLine;
    F.StartCol := ASym.StartCol;
    F.EndLine:= ASym.StartLine;
    F.EndCol := ASym.StartCol + Length(ASym.Name);
    Findings.Add(F);
  end;

begin
  Result:= nil;
  if AStore = nil then Exit;
  Findings:= TList<TLintFinding>.Create;
  try
    FileIds:= AStore.GetAllFileIds;
    for Fid in FileIds do
    begin
      Path:= AStore.GetFilePath(Fid);
      Syms:= AStore.FindSymbolsByFile(Path);
      for Sym in Syms do
      begin
        { god-class: a class with both many methods and many fields. }
        if WantRule('god-class') and (Sym.Kind = skClass) then
        begin
          Children:= AStore.FindAllChildSymbols(Sym.Id);
          NMethods:= 0;
          NFields := 0;
          for Ch in Children do
            case Ch.Kind of
              skMethod, skFunction, skProcedure, skConstructor, skDestructor: Inc(NMethods);
              skField: Inc(NFields);
            end;
          if (NMethods > 20) and (NFields > 15) then
            Add('god-class', 'info', Format('God class: %s has %d methods and %d fields -- consider splitting responsibilities', [Sym.Name, NMethods, NFields]), Sym);
        end;

        { unused-public-symbol: an exported (interface-section) free routine that
          nothing in the index references or calls -- likely dead public API.
          Restricted to unit-level routines (not class methods) so DFM-wired
          event handlers and virtual/override methods are not false positives. }
        if WantRule('unused-public-symbol') and (Sym.Section = 'interface') and (Sym.Kind in [skFunction, skProcedure]) and (Sym.ParentId > 0) and
          (Pos('override', LowerCase(Sym.Modifiers)) = 0) and not SameText(Sym.Name, 'Register') then
        begin
          Parent:= AStore.GetSymbolById(Sym.ParentId);
          if (Parent.Id = Sym.ParentId) and (Parent.Kind = skUnit) then
            if (Length(AStore.FindReferencesTo(Sym.Id)) = 0) and (Length(AStore.FindCallersByName(Sym.Name)) = 0) then
              Add('unused-public-symbol', 'info', Format('Exported routine %s has no references in the index -- possible dead public API', [Sym.Name]), Sym);
        end;
      end; // for Sym
    end; // for Fid
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end; // function

end.
