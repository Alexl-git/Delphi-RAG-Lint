unit DRagLint.Core.Model;

interface

type
  TSymbolKind = (
    skUnit, skProgram, skPackage,
    skClass, skInterface, skRecord, skEnum,
    skProcedure, skFunction, skMethod, skConstructor, skDestructor,
    skProperty, skField, skVarDecl, skConstDecl, skTypeAlias
  );

  TSymbolKindHelper = record helper for TSymbolKind
    function ToText: string;
    class function FromText(const AText: string): TSymbolKind; static;
  end;

  TFileTxToken = record
    FileId: Int64;
    Path: string;
  end;

  TSymbol = record
    Id: Int64;
    FileId: Int64;
    ParentId: Int64;
    Kind: TSymbolKind;
    Name: string;
    QualifiedName: string;
    Signature: string;
    Modifiers: string;
    StartLine: Integer;
    StartCol: Integer;
    EndLine: Integer;
    EndCol: Integer;
  end;

  TReference = record
    Id: Int64;
    SymbolId: Int64;
    FileId: Int64;
    Kind: string;
    NameText: string;
    StartLine: Integer;
    StartCol: Integer;
    EndLine: Integer;
    EndCol: Integer;
  end;

  TChunk = record
    Id: Int64;
    FileId: Int64;
    SymbolId: Int64;
    Kind: string;
    StartLine: Integer;
    EndLine: Integer;
    Text: string;
  end;

  TLintFinding = record
    Id: Int64;
    RuleId: string;
    FileId: Int64;
    FilePath: string;
    StartLine: Integer;
    StartCol: Integer;
    EndLine: Integer;
    EndCol: Integer;
    Severity: string;
    Message: string;
  end;

implementation

uses
  System.SysUtils;

const
  KindText: array[TSymbolKind] of string = (
    'unit', 'program', 'package',
    'class', 'interface', 'record', 'enum',
    'procedure', 'function', 'method', 'constructor', 'destructor',
    'property', 'field', 'var', 'const', 'type'
  );

function TSymbolKindHelper.ToText: string;
begin
  Result := KindText[Self];
end;

class function TSymbolKindHelper.FromText(const AText: string): TSymbolKind;
var
  K: TSymbolKind;
begin
  for K := Low(TSymbolKind) to High(TSymbolKind) do
    if SameText(KindText[K], AText) then
      Exit(K);
  raise Exception.CreateFmt('Unknown symbol kind: "%s"', [AText]);
end;

end.
