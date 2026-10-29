program PropDeclTypeTests;
{$APPTYPE CONSOLE}
{ ResolvePropertyDeclaredType -- the type hover shows for a property.

  THE DEFECTS THIS PINS (whole-branch review of fix/hang-int138, 2026-10-29):

  1. The type parser cut at the first space, so an own-accessor generic
     property `Map: TDictionary<string, Integer>` answered `TDictionary<string,`
     and an indexed signature `[I: Integer]: TFoo` answered `[I:`. The same
     truncation reached a RE-PUBLISHED generic property through the ancestor
     climb.
  2. The session cache kept MISSES (TypeName = '') and was never cleared, so a
     re-publication hovered before its ancestor was indexed stayed typeless
     until the process restarted, and a changed ancestor type stayed stale.

  Direct store calls rather than a parsed fixture: the indexed `[..]: T` shape
  is not what the current extractor emits, so hand-built rows are the only way
  to hold the parser to it. Same style as AncestryNameCollisionTests.dpr.

  THE CONTROLS. A plain `Integer` property and a plain re-publication must keep
  answering exactly as before, so a parser that returned the whole signature
  verbatim (accessors included) would still fail the accessor case. }
uses
  System.SysUtils,
  DRagLint.Core.Model        in '..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Core.Interfaces   in '..\src\core\DRagLint.Core.Interfaces.pas',
  DRagLint.Storage.SQLite    in '..\src\storage\DRagLint.Storage.SQLite.pas',
  DRagLint.Convert.PropTree  in '..\src\report\DRagLint.Convert.PropTree.pas';

var
  GPass, GFail: Integer;

procedure Check(const AName: string; ACond: Boolean; const AGot: string = '');
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else begin Inc(GFail); Writeln('FAIL  ', AName, '  got: [', AGot, ']'); end;
end;

function AddSym(const AStore: ISymbolStore; const ATok: TFileTxToken; AKind: TSymbolKind;
  const AName, AQName, ASig, AAccess, AHeritage: string; AParent: Int64; ALine: Integer): Int64;
var
  Sym: TSymbol;
begin
  Sym:= Default(TSymbol);
  Sym.Kind         := AKind;
  Sym.Name         := AName;
  Sym.QualifiedName:= AQName;
  Sym.Signature    := ASig;
  Sym.PropAccess   := AAccess;
  Sym.Heritage     := AHeritage;
  Sym.ParentId     := AParent;
  Sym.StartLine:= ALine; Sym.StartCol:= 3; Sym.EndLine:= ALine; Sym.EndCol:= 40;
  Result:= AStore.UpsertSymbol(ATok, Sym);
end;

function Prop(const AStore: ISymbolStore; const AQName: string): TSymbol;
var
  S: TSymbol;
begin
  Result:= Default(TSymbol);
  for S in AStore.FindSymbolsByQualifiedName(AQName) do
    if S.Kind = skProperty then Exit(S);
end;

procedure TestDeclaredTypes;
var
  Store: ISymbolStore;
  Tok  : TFileTxToken;
  Cls  : Int64;
  Got  : TDeclaredPropType;
const
  DB_PATH = 'propdecltype.sqlite';
begin
  if FileExists(DB_PATH) then DeleteFile(DB_PATH);
  Store:= TSQLiteSymbolStore.Create(DB_PATH);
  Store.Migrate;

  { The ancestor that declares the generic property. }
  Tok:= Store.OpenFileTx('pdt_base.pas', 0, 'shaBase', 'delphi13');
  Cls:= AddSym(Store, Tok, skClass, 'TPBase', 'PdtBase.TPBase', '', '', 'TObject', -1, 3);
  AddSym(Store, Tok, skProperty, 'Map', 'PdtBase.TPBase.Map',
    'TDictionary<string, Integer>', 'rw', '', Cls, 4);
  AddSym(Store, Tok, skProperty, 'Items', 'PdtBase.TPBase.Items',
    '[I: Integer]: TFoo read GetItem', 'ro', '', Cls, 5);
  AddSym(Store, Tok, skProperty, 'Count', 'PdtBase.TPBase.Count', 'Integer', 'ro', '', Cls, 6);
  AddSym(Store, Tok, skProperty, 'Cells', 'PdtBase.TPBase.Cells',
    '[I, J: Integer]: TArray<string> read GetCell', 'ro', '', Cls, 7);
  Store.CommitFileTx(Tok);

  { A descendant re-publishing Map and Count, and a re-publication whose
    ancestor is NOT indexed yet. }
  Tok:= Store.OpenFileTx('pdt_kid.pas', 0, 'shaKid', 'delphi13');
  Cls:= AddSym(Store, Tok, skClass, 'TPKid', 'PdtKid.TPKid', '', '', 'TPBase', -1, 3);
  AddSym(Store, Tok, skProperty, 'Map', 'PdtKid.TPKid.Map', '', '', '', Cls, 4);
  AddSym(Store, Tok, skProperty, 'Count', 'PdtKid.TPKid.Count', '', '', '', Cls, 5);
  Cls:= AddSym(Store, Tok, skClass, 'TPOrphan', 'PdtKid.TPOrphan', '', '', 'TPLate', -1, 7);
  AddSym(Store, Tok, skProperty, 'Text', 'PdtKid.TPOrphan.Text', '', '', '', Cls, 8);
  Store.CommitFileTx(Tok);
  Store.ResolveAncestry;

  Writeln;
  Writeln('Own accessors: the FULL declared type');
  Got:= ResolvePropertyDeclaredType(Store, Prop(Store, 'PdtBase.TPBase.Map'));
  Check('generic Map = TDictionary<string, Integer>', Got.TypeName = 'TDictionary<string, Integer>', Got.TypeName);
  Got:= ResolvePropertyDeclaredType(Store, Prop(Store, 'PdtBase.TPBase.Items'));
  Check('indexed Items = TFoo', Got.TypeName = 'TFoo', Got.TypeName);
  Got:= ResolvePropertyDeclaredType(Store, Prop(Store, 'PdtBase.TPBase.Cells'));
  Check('indexed generic Cells = TArray<string>', Got.TypeName = 'TArray<string>', Got.TypeName);
  Got:= ResolvePropertyDeclaredType(Store, Prop(Store, 'PdtBase.TPBase.Count'));
  Check('CONTROL plain Count = Integer', Got.TypeName = 'Integer', Got.TypeName);

  Writeln;
  Writeln('Re-published: the ancestor''s full type');
  Got:= ResolvePropertyDeclaredType(Store, Prop(Store, 'PdtKid.TPKid.Map'));
  Check('re-published Map = TDictionary<string, Integer>', Got.TypeName = 'TDictionary<string, Integer>', Got.TypeName);
  Check('re-published Map declared in PdtBase.TPBase', Got.DeclaredIn = 'PdtBase.TPBase', Got.DeclaredIn);
  Got:= ResolvePropertyDeclaredType(Store, Prop(Store, 'PdtKid.TPKid.Count'));
  Check('CONTROL re-published Count = Integer', Got.TypeName = 'Integer', Got.TypeName);

  Writeln;
  Writeln('A miss is not cached: the ancestor indexed later is found');
  Got:= ResolvePropertyDeclaredType(Store, Prop(Store, 'PdtKid.TPOrphan.Text'));
  Check('PREMISE orphan Text unresolved before TPLate is indexed', Got.TypeName = '', Got.TypeName);
  Tok:= Store.OpenFileTx('pdt_late.pas', 0, 'shaLate', 'delphi13');
  Cls:= AddSym(Store, Tok, skClass, 'TPLate', 'PdtLate.TPLate', '', '', 'TObject', -1, 3);
  AddSym(Store, Tok, skProperty, 'Text', 'PdtLate.TPLate.Text', 'string', 'rw', '', Cls, 4);
  Store.CommitFileTx(Tok);
  Store.ResolveAncestry;
  Got:= ResolvePropertyDeclaredType(Store, Prop(Store, 'PdtKid.TPOrphan.Text'));
  Check('orphan Text = string once TPLate is indexed', Got.TypeName = 'string', Got.TypeName);

  Writeln;
  Writeln('A cleared cache sees a changed ancestor type');
  Tok:= Store.OpenFileTx('pdt_late.pas', 0, 'shaLate2', 'delphi13');
  Cls:= AddSym(Store, Tok, skClass, 'TPLate', 'PdtLate.TPLate', '', '', 'TObject', -1, 3);
  AddSym(Store, Tok, skProperty, 'Text', 'PdtLate.TPLate.Text', 'WideString', 'rw', '', Cls, 4);
  Store.CommitFileTx(Tok);
  Store.ResolveAncestry;
  ClearPropertyDeclaredTypeCache;
  Got:= ResolvePropertyDeclaredType(Store, Prop(Store, 'PdtKid.TPOrphan.Text'));
  Check('orphan Text = WideString after the ancestor changed + cache cleared', Got.TypeName = 'WideString', Got.TypeName);
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestDeclaredTypes;
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
