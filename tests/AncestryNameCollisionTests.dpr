program AncestryNameCollisionTests;
{$APPTYPE CONSOLE}
{ A RECORD sharing a class's name must not decide an ancestry question.

  THE DEFECT THIS PINS. IsDescendantOf resolved its type name through
  ResolveTypeSymbolId, which returns the FIRST class/interface/record match. In
  library-Win32.sqlite three symbols are named TTimer -- DosCommand.TTimer (a
  RECORD), FMX.Types.TTimer, Vcl.ExtCtrls.TTimer -- and the record sorts first.
  So IsDescendantOf('TTimer','TComponent') asked a record, whose ancestor set is
  empty, and answered False. A record cannot descend from anything, so the
  question was decided by the one candidate that could never say yes.

  The consumer symptom was an object-leak false positive on
  DataCopy uMainZeissCopy.pas:2343 -- `LTimer := TTimer.Create(LDlg)`, whose own
  comment says the timer is owned by the dialog and dies with it.
  ConstructorTransfersOwnership was correct; the lookup underneath it was not.
  Win64 was clean only because DosCommand is a Win32-only library path, which is
  what made the bug look platform-specific when it was not.

  Direct store calls rather than a parsed fixture, because the whole defect is
  about the ORDER candidates come back in. Hand-building the rows makes the
  record precede the class deterministically; a .pas fixture would leave that to
  indexing order and could pass for the wrong reason. Same style as
  StorageHelperEdgesTests.dpr.

  THE CONTROLS. Returning True unconditionally would satisfy the headline
  assertion, so two negatives are asserted alongside it: an ancestor that is
  genuinely absent must still be False, and a name that IS only a record must
  still be False. }
uses
  System.SysUtils,
  DRagLint.Core.Model      in '..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Core.Interfaces in '..\src\core\DRagLint.Core.Interfaces.pas',
  DRagLint.Storage.SQLite  in '..\src\storage\DRagLint.Storage.SQLite.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName); end;
end;

procedure TestRecordDoesNotShadowClass;
var
  Store: ISymbolStore;
  Tok  : TFileTxToken;
  Sym  : TSymbol     ;
const
  { CWD-relative on purpose: the runner executes this from its own scratch dir,
    so a 'tests\' prefix would point at a folder that is not there. }
  DB_PATH = 'ancestrynamecollision.sqlite';
begin
  if FileExists(DB_PATH) then DeleteFile(DB_PATH);
  Store:= TSQLiteSymbolStore.Create(DB_PATH);
  Store.Migrate;

  { FILE 1 -- indexed FIRST, so its rows come back first. This is the shadowing
    record: DosCommand.TTimer in the real index. }
  Tok:= Store.OpenFileTx('acollide_a.pas', 0, 'shaA', 'delphi13');
  Sym:= Default(TSymbol);
  Sym.Kind         := skRecord;
  Sym.Name         := 'TTimer';
  Sym.QualifiedName:= 'ACollideA.TTimer';
  Sym.ParentId     := -1;
  Sym.StartLine:= 3; Sym.StartCol:= 3; Sym.EndLine:= 5; Sym.EndCol:= 7;
  Store.UpsertSymbol(Tok, Sym);

  { A record that is ONLY ever a record -- the second control. }
  Sym:= Default(TSymbol);
  Sym.Kind         := skRecord;
  Sym.Name         := 'TPurelyARecord';
  Sym.QualifiedName:= 'ACollideA.TPurelyARecord';
  Sym.ParentId     := -1;
  Sym.StartLine:= 7; Sym.StartCol:= 3; Sym.EndLine:= 9; Sym.EndCol:= 7;
  Store.UpsertSymbol(Tok, Sym);
  Store.CommitFileTx(Tok);

  { FILE 2 -- the real component, indexed SECOND so it loses a first-match race. }
  Tok:= Store.OpenFileTx('acollide_b.pas', 0, 'shaB', 'delphi13');
  Sym:= Default(TSymbol);
  Sym.Kind         := skClass;
  Sym.Name         := 'TComponent';
  Sym.QualifiedName:= 'ACollideB.TComponent';
  Sym.ParentId     := -1;
  Sym.StartLine:= 3; Sym.StartCol:= 3; Sym.EndLine:= 4; Sym.EndCol:= 7;
  Store.UpsertSymbol(Tok, Sym);

  Sym:= Default(TSymbol);
  Sym.Kind         := skClass;
  Sym.Name         := 'TTimer';
  Sym.QualifiedName:= 'ACollideB.TTimer';
  Sym.Heritage     := 'TComponent';
  Sym.ParentId     := -1;
  Sym.StartLine:= 5; Sym.StartCol:= 3; Sym.EndLine:= 6; Sym.EndCol:= 7;
  Store.UpsertSymbol(Tok, Sym);
  Store.CommitFileTx(Tok);

  Store.ResolveAncestry;

  Writeln;
  Writeln('A record must not decide a class ancestry question');
  Check('TTimer IS a TComponent, despite a record of the same name sorting first',
        Store.IsDescendantOf('TTimer', 'TComponent', 0));

  Writeln;
  Writeln('CONTROLS: it is not simply answering True');
  Check('TTimer is NOT a descendant of an absent ancestor',
        not Store.IsDescendantOf('TTimer', 'TNoSuchAncestor', 0));
  Check('a name that is ONLY a record is still not a TComponent',
        not Store.IsDescendantOf('TPurelyARecord', 'TComponent', 0));
  Check('an entirely unknown name is not a TComponent',
        not Store.IsDescendantOf('TNeverHeardOfIt', 'TComponent', 0));
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestRecordDoesNotShadowClass;
  except
    on E: Exception do
    begin
      Writeln('FAIL  unhandled exception: ', E.ClassName, ': ', E.Message);
      Inc(GFail);
    end;
  end;
  Writeln;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then Halt(1);
end.
