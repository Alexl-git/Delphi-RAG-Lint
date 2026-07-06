unit DRagLint.Lint.DocRules;

{ Report-only lint rules over the DocInsight doc-comment layer (ADF milestone).
  Both rules read the whole symbol/doc graph via ISymbolStore rather than a
  single file's AST -- the store-backed complement to the per-file `lint`
  command, run only where a store is open (`lint-all` / `lint-project`).

  missing-doc (Task 7, ships ON by default) flags a public/published
  declaration with NO doc-comment at all. doc-drift (Task 8) owns the
  complementary "your doc is stale" case -- a declaration that already HAS a
  doc-comment (including a drag-lint managed TODO stub) is "documented" for
  missing-doc's purposes and is never double-reported here. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <summary>Doc-comment-aware lint rules (missing-doc; doc-drift is Task 8).</summary>
  /// <remarks>Stateless; reads the supplied open store. Never raises.</remarks>
  TDocLintRules = class
  public
    /// <summary>Flags every public/published declaration in AStore that has
    /// no doc-comment of any kind.</summary>
    /// <param name="AStore">An open, migrated symbol store; nil yields no findings.</param>
    /// <returns>'missing-doc' findings, one per undocumented public/published
    /// declaration; empty if none.</returns>
    /// <remarks>Backed by ISymbolStore.FindUndocumented(kind, PublicOnly:=True),
    /// which already excludes private/protected members (public-surface-only,
    /// per the CDD scope rule) AND excludes any declaration that has a
    /// symbol_docs row -- including a drag-lint managed "TODO: describe." stub,
    /// which counts as "documented" here (doc-drift owns stale-stub reporting,
    /// so the two rules never double-report the same declaration). Restricted
    /// to the kinds CDD requires doc-comments on: types (class/interface/
    /// record/enum), routines (procedure/function/method/constructor/
    /// destructor), and properties. Never raises.</remarks>
    class function RunMissingDoc(const AStore: ISymbolStore): TArray<TLintFinding>;
  end;

implementation

{ Kinds CDD/DocInsight applies to: public/published types + routines +
  properties. Excludes containers (unit/program/package), fields (CDD scopes
  doc-comments to the public API surface -- a field is usually documented via
  its owning property or class remarks), locals/params, and the SQL/DFM/init
  markers that FindUndocumented would otherwise also return under kind=''. }
const
  DOCUMENTABLE_KINDS: array[0..10] of TSymbolKind = (
    skClass, skInterface, skRecord, skEnum,
    skProcedure, skFunction, skMethod, skConstructor, skDestructor,
    skProperty, skTypeAlias
  );

function IsDocumentableKind(AKind: TSymbolKind): Boolean;
var
  K: TSymbolKind;
begin
  Result:= False;
  for K in DOCUMENTABLE_KINDS do
    if K = AKind then Exit(True);
end;

class function TDocLintRules.RunMissingDoc(const AStore: ISymbolStore): TArray<TLintFinding>;
var
  Findings: TList<TLintFinding>;
  Syms    : TArray<TSymbol>    ;
  Sym     : TSymbol            ;
  F       : TLintFinding        ;
begin
  Result:= nil;
  if AStore = nil then Exit;
  Findings:= TList<TLintFinding>.Create;
  try
    { kind='' -> every kind; filter down to the documentable subset below so we
      don't ask CDD questions of fields/locals/units/SQL-DDL symbols. }
    Syms:= AStore.FindUndocumented('', True);
    for Sym in Syms do
    begin
      if not IsDocumentableKind(Sym.Kind) then Continue;
      F:= Default(TLintFinding);
      F.RuleId  := 'missing-doc';
      F.Severity:= 'warning';
      F.Message := Format('Public declaration ''%s'' has no DocInsight doc-comment', [Sym.Name]);
      F.FilePath:= AStore.GetFilePath(Sym.FileId);
      F.StartLine:= Sym.StartLine;
      F.StartCol := Sym.StartCol;
      F.EndLine  := Sym.StartLine;
      F.EndCol   := Sym.StartCol + Length(Sym.Name);
      Findings.Add(F);
    end;
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end;

end.
