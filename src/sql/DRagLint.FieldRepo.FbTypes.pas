unit DRagLint.FieldRepo.FbTypes;

{ drag-lint 1.52 -- lane TTS: Firebird type-code dictionaries.

  Port of the two dictionaries TableTools builds in TableTool.GlobalObject.pas
  (TGlobalObject.Create: FFieldAsType / FFieldVarType) and of the lookup rules of
  FieldsInfo.Model.pas GetFieldAccessor / GetFieldVarType. A key is the
  RDB$FIELDS.RDB$FIELD_TYPE code; sub_type 1 adds FB_SUBTYPE_ADD to it. No other
  sub_type has an entry. Pure data: no Firebird, no FireDAC. }

interface

const
  /// <summary>Offset TableTools adds to a type code for RDB$FIELD_SUB_TYPE = 1
  /// (TableTool.Interfaces.SUBTYPE_ADD).</summary>
  FB_SUBTYPE_ADD = 10000;

type
  /// <summary>One dictionary entry: the key and the two strings TableTools maps it to.</summary>
  /// <remarks>Key = RDB$FIELD_TYPE, or RDB$FIELD_TYPE + FB_SUBTYPE_ADD for sub_type 1.</remarks>
  TFbTypeEntry = record
    Key: Integer;
    Accessor: string;
    VarType: string;
  end;

/// <summary>Every entry of the TableTools dictionaries, in key order.</summary>
/// <returns>20 entries: codes 7, 8, 10, 12, 13, 14, 16, 23..29, 35, 37, 261 and the
/// sub_type-1 keys of 14, 37 and 261.</returns>
function FbTypeEntries: TArray<TFbTypeEntry>;  // dl:ok unused-public-symbol@0d37 -- consumed by SchemaSeedTests and lane TTGEN

/// <summary>The TField accessor TableTools writes into FIELD_AS_TYPE ('AsInteger' ...).</summary>
/// <param name="pType">RDB$FIELD_TYPE.</param>
/// <param name="pSubType">RDB$FIELD_SUB_TYPE; NULL is passed as 0.</param>
/// <param name="pAccessor">The accessor; '' when the result is False.</param>
/// <returns>False when the sub_type is not 0 or 1 or the key has no entry (TableTools
/// raised in both cases).</returns>
function TryFbFieldAccessor(pType, pSubType: Integer; out pAccessor: string): Boolean;

/// <summary>The Delphi type TableTools writes into VAR_TYPE ('integer', 'string' ...).</summary>
/// <param name="pType">RDB$FIELD_TYPE.</param>
/// <param name="pSubType">RDB$FIELD_SUB_TYPE; NULL is passed as 0.</param>
/// <param name="pLength">RDB$FIELD_LENGTH; a CHAR(1) OCTETS (type 14, sub_type 1,
/// length 1) maps to 'Byte' instead of 'TBytes'.</param>
/// <param name="pVarType">The Delphi type; '' when the result is False.</param>
/// <returns>False under the same conditions as TryFbFieldAccessor.</returns>
function TryFbFieldVarType(pType, pSubType, pLength: Integer; out pVarType: string): Boolean;

implementation

uses
  System.SysUtils;

const
  FB_TYPE_SHORT = 7;
  FB_TYPE_LONG = 8;
  FB_TYPE_FLOAT = 10;
  FB_TYPE_DATE = 12;
  FB_TYPE_TIME = 13;
  FB_TYPE_CHAR = 14;
  FB_TYPE_INT64 = 16;
  FB_TYPE_BOOLEAN = 23;
  FB_TYPE_DEC16 = 24;
  FB_TYPE_DEC34 = 25;
  FB_TYPE_INT128 = 26;
  FB_TYPE_DOUBLE = 27;
  FB_TYPE_TIME_TZ = 28;
  FB_TYPE_TIMESTAMP_TZ = 29;
  FB_TYPE_TIMESTAMP = 35;
  FB_TYPE_VARCHAR = 37;
  FB_TYPE_BLOB = 261;

function Entry(pKey: Integer; const pAccessor, pVarType: string): TFbTypeEntry;
begin
  Result.Key := pKey;
  Result.Accessor := pAccessor;
  Result.VarType := pVarType;
end;

function FbTypeEntries: TArray<TFbTypeEntry>;
begin
  Result := [
    Entry(FB_TYPE_SHORT, 'AsInteger', 'integer'),
    Entry(FB_TYPE_LONG, 'AsInteger', 'integer'),
    Entry(FB_TYPE_FLOAT, 'AsSingle', 'double'),
    Entry(FB_TYPE_DATE, 'AsDateTime', 'TDateTime'),
    Entry(FB_TYPE_TIME, 'AsDateTime', 'TDateTime'),
    Entry(FB_TYPE_CHAR, 'AsString', 'string'),
    Entry(FB_TYPE_INT64, 'AsLargeInt', 'Int64'),
    Entry(FB_TYPE_BOOLEAN, 'AsBoolean', 'Boolean'),
    Entry(FB_TYPE_DEC16, 'AsBCD', 'TBCD'),
    Entry(FB_TYPE_DEC34, 'AsBCD', 'TBCD'),
    Entry(FB_TYPE_INT128, 'AsBCD', 'TBCD'),
    Entry(FB_TYPE_DOUBLE, 'AsFloat', 'double'),
    Entry(FB_TYPE_TIME_TZ, 'AsDateTime', 'TDateTime'),
    Entry(FB_TYPE_TIMESTAMP_TZ, 'AsSQLTimeStampOffset', 'TSQLTimeStampOffset'),
    Entry(FB_TYPE_TIMESTAMP, 'AsSQLTimeStamp', 'TSQLTimeStamp'),
    Entry(FB_TYPE_VARCHAR, 'AsString', 'string'),
    Entry(FB_TYPE_BLOB, 'AsBlob', 'TPicture'),
    Entry(FB_TYPE_CHAR + FB_SUBTYPE_ADD, 'AsByte', 'TBytes'),
    Entry(FB_TYPE_VARCHAR + FB_SUBTYPE_ADD, 'AsByte', 'TBytes'),
    Entry(FB_TYPE_BLOB + FB_SUBTYPE_ADD, 'AsString', 'TStringList')];
end;

{ Finds the entry for (pType, pSubType); False for any sub_type other than 0 / 1. }
function FindEntry(pType, pSubType: Integer; out pEntry: TFbTypeEntry): Boolean;
var
  Key: Integer;
  Item: TFbTypeEntry;
begin
  Result := False;
  pEntry := Default(TFbTypeEntry);
  if (pSubType <> 0) and (pSubType <> 1) then
    Exit;
  Key := if pSubType = 1 then pType + FB_SUBTYPE_ADD else pType;
  for Item in FbTypeEntries do
    if Item.Key = Key then
    begin
      pEntry := Item;
      Exit(True);
    end;
end;

function TryFbFieldAccessor(pType, pSubType: Integer; out pAccessor: string): Boolean;
var
  Item: TFbTypeEntry;
begin
  Result := FindEntry(pType, pSubType, Item);
  pAccessor := Item.Accessor;
end;

function TryFbFieldVarType(pType, pSubType, pLength: Integer; out pVarType: string): Boolean;
var
  Item: TFbTypeEntry;
begin
  Result := FindEntry(pType, pSubType, Item);
  pVarType := Item.VarType;
  if Result and (pType = FB_TYPE_CHAR) and (pSubType = 1) and (pLength = 1) then
    pVarType := 'Byte';
end;

end.
