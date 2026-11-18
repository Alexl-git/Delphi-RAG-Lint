unit DragLint.Plugin.Cmd.FindUsagesScope;

{ 1.52 command, owned by lane FUSCOPE (owner N3, 2026-11-17): Find Usages in one of four
  scopes -- This symbol (the declaration the caret is bound to, this project; the default of
  every Find Usages), Project (the name in this project), Group (the name in every project of
  the open group) and Everywhere (the name in every index the manifest knows).

  Four rows of the 1.52 command table (DragLint.Plugin.Cmd152): main menu drag-lint >
  Find Usages > <scope>, and the editor right-click drag-lint > Find Usages > <scope>.
  DragLint.Plugin.Editor is not edited. Each click asks the Find Usages panel
  (DragLint.Plugin.UsagesForm.ShowFindUsagesScoped) with the identifier at the caret; the
  engine answers `usages --scope <word>` (or draglint/usages for symbol / project). }

interface

implementation

uses
  System.SysUtils,
  Vcl.Dialogs,
  DragLint.Plugin.Cmd152,
  DragLint.Plugin.DbResolver,
  DragLint.Plugin.Settings,
  DragLint.Plugin.ExeResolver,
  DragLint.Plugin.UsagesForm,
  DragLint.Plugin.Editor;

const
  OWNER_LANE = 'FUSCOPE';
  PARENT_CAPTION = 'Find Usages';

{ The panel, for the identifier at the caret, in pScope. }
procedure FindUsagesIn(const pScope: string);
begin
  var Sym: string:= IdentifierAtCursor;
  if Sym = '' then
  begin
    ShowMessage('drag-lint Find Usages: put the caret on an identifier first.');
    Exit;
  end;
  var Exe: string;
  if not RequireEngine(Exe) then Exit;
  var Dbs: TArray<string>;
  try
    Dbs:= ResolveActiveIndexDbs(LoadSettings);
  except
    on E: Exception do Dbs:= nil; { the panel then says the engine found no database }
  end;
  ShowFindUsagesScoped(Sym, Exe, Dbs, pScope);
end;

procedure InvokeScopeSymbol(Sender: TObject);
begin
  FindUsagesIn('symbol');
end;

procedure InvokeScopeProject(Sender: TObject);
begin
  FindUsagesIn('project');
end;

procedure InvokeScopeGroup(Sender: TObject);
begin
  FindUsagesIn('group');
end;

procedure InvokeScopeEverywhere(Sender: TObject);
begin
  FindUsagesIn('everywhere');
end;

{ The fields every row shares. }
function BaseRow: TCmd152Command;
begin
  Result:= Default(TCmd152Command);
  Result.OwnerLane:= OWNER_LANE;
  Result.ParentPath:= PARENT_CAPTION;
  Result.Visible:= True;
  Result.Surfaces:= [csMainMenu, csEditorContext];
  Result.Needs:= cnSymbol;
  Result.EditorParent:= PARENT_CAPTION;
end;

{ The four rows, in menu order (the table sorts by Id). Each caption is a literal
  `.Caption :=` because the feature registry harvests menu captions from the source. }
procedure RegisterRows;
var
  Row: TCmd152Command;
begin
  Row:= BaseRow;
  Row.Id:= 'find-usages-scope-1-symbol';
  Row.Caption:= 'This symbol';
  Row.Click:= InvokeScopeSymbol;
  RegisterCmd152(Row);
  Row:= BaseRow;
  Row.Id:= 'find-usages-scope-2-project';
  Row.Caption:= 'Project';
  Row.Click:= InvokeScopeProject;
  RegisterCmd152(Row);
  Row:= BaseRow;
  Row.Id:= 'find-usages-scope-3-group';
  Row.Caption:= 'Group';
  Row.Click:= InvokeScopeGroup;
  RegisterCmd152(Row);
  Row:= BaseRow;
  Row.Id:= 'find-usages-scope-4-everywhere';
  Row.Caption:= 'Everywhere';
  Row.Click:= InvokeScopeEverywhere;
  RegisterCmd152(Row);
end;

initialization
  RegisterRows;

end.