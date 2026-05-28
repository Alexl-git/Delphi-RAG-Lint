program T7_storage;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Storage.SQLite;
var
  Store: ISymbolStore;
  Doc, Out: TParsedDoc;
  Sym: TSymbol;
  Tok: TFileTxToken;
  Id: Int64;
const
  DB_PATH = 'tests\t7.sqlite';
begin
  if FileExists(DB_PATH) then DeleteFile(DB_PATH);

  Store := TSQLiteSymbolStore.Create(DB_PATH);
  Store.Migrate;

  Tok := Store.OpenFileTx('virt.pas', 0, 'sha', 'delphi13');
  Sym := Default(TSymbol);
  Sym.Kind := skMethod;
  Sym.Name := 'Foo';
  Sym.QualifiedName := 'U.Foo';
  Sym.ParentId := -1;
  Sym.StartLine := 10; Sym.StartCol := 1; Sym.EndLine := 12; Sym.EndCol := 5;
  Id := Store.UpsertSymbol(Tok, Sym);

  FillChar(Doc, SizeOf(Doc), 0);
  Doc.Format := dfXmlDoc;
  Doc.RawBlock := '/// <summary>S</summary>';
  Doc.Summary := 'S';
  Doc.StartLine := 8; Doc.EndLine := 9;
  Doc.HasContent := True;
  Store.UpsertSymbolDoc(Tok, Id, Doc);
  Store.CommitFileTx(Tok);

  Out := Store.GetSymbolDoc(Id);
  Assert(Out.Summary = 'S', 'roundtrip summary='+Out.Summary);
  Assert(Out.Format = dfXmlDoc, 'roundtrip format');
  WriteLn('OK');
end.
