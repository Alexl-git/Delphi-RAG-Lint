program StorageHelperEdgesTests;
{$APPTYPE CONSOLE}
{ v15: store-level round-trip for the first-class helper-target edge
  (type_helpers). Mirrors tests\fixtures\T7_storage.dpr's direct-store-call
  style: hand-build TSymbol rows shaped exactly like the parser's TryWalkHelper
  output (IsHelper=True, Heritage=<target type name>), call ResolveHelpers (the
  whole-DB resolve pass), then assert FindHelpersOfType resolves the edge.
  This is a fast, parser-independent regression guard on the store/resolve
  logic; tests\autotest\run_helper_edges.ps1 covers the full parser+CLI path
  against the real _probe_helper.pas fixture. }
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

procedure TestHelperEdges;
var
  Store        : ISymbolStore;
  Tok          : TFileTxToken;
  Sym          : TSymbol     ;
  ColorHelperId: Int64       ;
  ColorEnumId  : Int64       ;
  PlainId      : Int64       ;
  Edges        : TArray<THelperEdge>;
const
  DB_PATH = 'tests\storagehelperedges.sqlite';
begin
  if FileExists(DB_PATH) then DeleteFile(DB_PATH);

  Store:= TSQLiteSymbolStore.Create(DB_PATH);
  Store.Migrate;

  Tok:= Store.OpenFileTx('probehelper.pas', 0, 'sha', 'delphi13');

  // TColor = (clRed, clGreen, clBlue);  -- the helper's target type.
  Sym:= Default(TSymbol);
  Sym.Kind:= skEnum;
  Sym.Name:= 'TColor';
  Sym.QualifiedName:= 'ProbeHelper.TColor';
  Sym.ParentId:= -1;
  Sym.StartLine:= 4; Sym.StartCol:= 3; Sym.EndLine:= 4; Sym.EndCol:= 37;
  ColorEnumId:= Store.UpsertSymbol(Tok, Sym);

  // TColorHelper = record helper for TColor ... end;
  // Shaped exactly as TryWalkHelper (DRagLint.Parser.Delphi13.pas) emits it:
  // Kind=skRecord, IsHelper=True, Heritage=target type name (verbatim).
  Sym:= Default(TSymbol);
  Sym.Kind:= skRecord;
  Sym.Name:= 'TColorHelper';
  Sym.QualifiedName:= 'ProbeHelper.TColorHelper';
  Sym.ParentId:= -1;
  Sym.IsHelper:= True;
  Sym.Heritage:= 'TColor';
  Sym.StartLine:= 5; Sym.StartCol:= 3; Sym.EndLine:= 7; Sym.EndCol:= 7;
  ColorHelperId:= Store.UpsertSymbol(Tok, Sym);

  // TPlain = record Field: TColor; end;  -- NOT a helper (IsHelper=False,
  // Heritage empty). Proves a plain record with a TColor-typed field does
  // NOT get mistaken for a helper targeting TColor.
  Sym:= Default(TSymbol);
  Sym.Kind:= skRecord;
  Sym.Name:= 'TPlain';
  Sym.QualifiedName:= 'ProbeHelper.TPlain';
  Sym.ParentId:= -1;
  Sym.StartLine:= 8; Sym.StartCol:= 3; Sym.EndLine:= 10; Sym.EndCol:= 7;
  PlainId:= Store.UpsertSymbol(Tok, Sym);

  Store.CommitFileTx(Tok);

  Store.ResolveHelpers;

  Edges:= Store.FindHelpersOfType('TColor');
  Check('FindHelpersOfType(TColor) returns exactly 1 edge', Length(Edges) = 1);
  if Length(Edges) = 1 then
  begin
    Check('edge.HelperSymbolId = TColorHelper', Edges[0].HelperSymbolId = ColorHelperId);
    Check('edge.TargetName = TColor', Edges[0].TargetName = 'TColor');
    Check('edge.TargetSymbolId resolves to the TColor enum symbol', Edges[0].TargetSymbolId = ColorEnumId);
    Check('edge.HelperKind = record', Edges[0].HelperKind = 'record');
  end;

  Edges:= Store.FindHelpersOfType('TPlain');
  Check('FindHelpersOfType(TPlain) returns 0 (TPlain is not a helper target)', Length(Edges) = 0);

  // Suppress hint: PlainId is asserted-by-absence above (no edge references it).
  if PlainId < 0 then Writeln('unreachable');

  DeleteFile(DB_PATH);
end;

begin
  GPass:= 0; GFail:= 0;
  try
    TestHelperEdges;
  except
    on E: Exception do begin Writeln('EXCEPTION ', E.ClassName, ': ', E.Message); Inc(GFail); end;
  end;
  Writeln('');
  Writeln(Format('storage-helper-edges-tests: %d pass / %d fail / %d total', [GPass, GFail, GPass + GFail]));
  if GFail > 0 then Halt(1) else Halt(0);
end.
