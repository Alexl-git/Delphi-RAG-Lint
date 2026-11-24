unit TypeCases;

{ schema-type-mismatch: accessors of FieldByName and of the persistent fields of DataMod. }

interface

procedure Accessors;
procedure Scoped;
procedure Persistent;

implementation

uses
  System.SysUtils, FireDAC.Comp.Client, Data.DB, DataMod;

procedure Accessors;
var
  Q: TFDQuery;
  I: Integer;
  S: string;
  V: Variant;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.SQL.Text := 'SELECT * FROM ORDERS';
    Q.Open;
    I := Q.FieldByName('NOTE').AsInteger; // FIRE schema-type-mismatch
    Q.FieldByName('CODE').AsFloat := 1; // FIRE schema-type-mismatch
    Q.FieldByName('NOTE').AsDateTime := 0; // FIRE schema-type-mismatch
    I := Q.FieldByName('CREATED').AsInteger; // FIRE schema-type-mismatch
    Q.FieldByName('QTY').AsDateTime := 0; // FIRE schema-type-mismatch
    I := Q.FieldByName('PICTURE').AsInteger; // FIRE schema-type-mismatch
    I := Q.FieldByName('VIADOMAIN').AsInteger; // FIRE schema-type-mismatch
    I := Q.FieldByName('NODOMAIN').AsInteger;
    S := Q.FieldByName('QTY').AsString;
    S := Q.FieldByName('CREATED').AsString;
    V := Q.FieldByName('NOTE').AsVariant;
    V := Q.FieldByName('NOTE').Value;
    I := Q.FieldByName('QTY').AsInteger;
    I := Q.FieldByName('PRICE').AsInteger;
    Q.FieldByName('PRICE').AsCurrency := 1;
    Q.FieldByName('CREATED').AsFloat := 1;
    if Q.FieldByName('NOTE').AsBoolean or Q.FieldByName('ACTIVE').AsBoolean or Q.FieldByName('FLAG').AsBoolean then
      Exit;
    I := Q.FieldByName('NOSUCH').AsInteger; // FIRE schema-unknown-column
    S := Q.FieldByName('BODY').AsString;
    if Q.FieldByName('NOTE').AsString.ToInteger = I then
      Exit;
  finally
    Q.Free;
  end;
end;

procedure Scoped;
var
  Q: TFDQuery;
  I: Integer;
begin
  Q := TFDQuery.Create(nil);
  Q.SQL.Text := 'SELECT QTY AS NOTE, NOTE AS QTY FROM ORDERS';
  Q.Open;
  I := Q.FieldByName('NOTE').AsInteger;
  I := Q.FieldByName('QTY').AsInteger; // FIRE schema-type-mismatch
  with Q do
    I := FieldByName('QTY').AsInteger + I; // FIRE schema-type-mismatch
  Q.Close;
end;

procedure Persistent;
var
  I: Integer;
  tblOrdersNOTE: TStringField;
begin
  I := dmMain.tblOrdersNOTE.AsInteger; // FIRE schema-type-mismatch
  I := dmMain.tblOrdersQTY.AsInteger;
  I := dmMain.qryLiveNOTE.AsInteger;
  tblOrdersNOTE := nil;
  I := tblOrdersNOTE.AsInteger + I;
end;

end.