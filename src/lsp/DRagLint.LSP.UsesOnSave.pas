unit DRagLint.LSP.UsesOnSave;

{ Auto uses on save (plan docs\superpowers\plans\2026-10-29-auto-uses-on-save.md).
  VS Code's editor.codeActionsOnSave asks the server for code actions of a
  named source.* kind and applies EVERY one it gets back without asking. This
  unit re-emits the uses-clause edits the quickfixes already make under those
  two kinds, behind gates that keep a silent edit from being a guess:

    source.addMissingImports   -- only for a finding with exactly ONE fix (D1);
                                  an ambiguous name stays quickfix-only.

  The quickfix actions themselves are untouched; these are extra actions. }

interface

uses
  System.JSON;

const
  /// <summary>The code-action kinds this server answers on save, advertised in
  /// initialize under codeActionProvider.codeActionKinds beside 'quickfix'.</summary>
  /// <remarks>[0] adds a missing unit, [1] removes an unused one. A client
  /// enables either through editor.codeActionsOnSave.</remarks>
  KINDS_ON_SAVE: array[0..1] of string = ('source.addMissingImports', 'source.removeUnusedImports');

type
  /// <summary>Builds the on-save (source.*) code actions for the uses clause.</summary>
  /// <remarks>Stateless; every function is pure and thread-safe. Each returned
  /// action is a new object the caller owns.</remarks>
  TUsesOnSave = class
  public
    /// <summary>The source.addMissingImports twin of a unit-missing-from-uses
    /// quickfix, or nil when the finding is not safe to fix silently.</summary>
    /// <param name="ADiag">The unit-missing-from-uses diagnostic; cloned into the
    /// action's diagnostics list. Must not be nil.</param>
    /// <param name="AFixes">The diagnostic's data.fixes. Exactly one entry is
    /// required (D1): two or more (a circular-reference alternative) or none (an
    /// ambiguous name, declared in several units) yield nil.</param>
    /// <param name="AQuickfixEdit">The WorkspaceEdit of that single fix's
    /// quickfix; cloned, so the source action applies the SAME edit.</param>
    /// <returns>A new action {title, kind: 'source.addMissingImports',
    /// diagnostics: [ADiag], edit}; nil when AFixes.Count &lt;&gt; 1 or an argument
    /// is nil. The caller owns the result.</returns>
    class function AddMissingImportAction(const ADiag: TJSONObject; const AFixes: TJSONArray;
      const AQuickfixEdit: TJSONObject): TJSONObject; static;
  end;

implementation

class function TUsesOnSave.AddMissingImportAction(const ADiag: TJSONObject; const AFixes: TJSONArray;
  const AQuickfixEdit: TJSONObject): TJSONObject;
begin
  Result:= nil;
  if (ADiag = nil) or (AFixes = nil) or (AQuickfixEdit = nil) or (AFixes.Count <> 1) then Exit;
  var Title: string:= 'Add unit to uses';
  if AFixes.Items[0] is TJSONObject then
    Title:= TJSONObject(AFixes.Items[0]).GetValue<string>('title', Title);
  var DiagList: TJSONArray:= TJSONArray.Create;
  DiagList.AddElement(ADiag.Clone as TJSONObject);
  Result:= TJSONObject.Create;
  Result.AddPair('title'      , Title);
  Result.AddPair('kind'       , KINDS_ON_SAVE[0]);
  Result.AddPair('diagnostics', DiagList);
  Result.AddPair('edit'       , AQuickfixEdit.Clone as TJSONObject);
end;

end.
