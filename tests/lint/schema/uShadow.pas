unit uShadow;

{ Negative controls (lane FR-LINT): names that only LOOK like a resolved dataset, constant or column.
  Every target must be bound by the index, never matched by its bare name. }

interface

uses
  FireDAC.Comp.Client, uBounds, fMain;

procedure ShadowDataset(const pText: string);
procedure ShadowConst(pOrder: TORDERS; const pText: string; NOTE_LIMIT: Integer);
procedure ViaSetter(pOrder: TORDERS);
procedure OtherUnit(pForm: TfrmMain);

implementation

procedure ShadowDataset(const pText: string);
var
  qryOrders: TFDQuery;
begin
  qryOrders := TFDQuery.Create(nil);
  qryOrders.FieldByName('NOTE').Size := 77; { a local, not fMain's dataset -> silent }
end;

procedure ShadowConst(pOrder: TORDERS; const pText: string; NOTE_LIMIT: Integer);
begin
  pOrder.NOTE := Copy(pText, 1, NOTE_LIMIT); { the parameter, not uLimits.NOTE_LIMIT -> silent }
end;

procedure ViaSetter(pOrder: TORDERS);
begin
  pOrder.NOTETRIM := '12345678901234567890123'; { the setter may shorten the value -> silent }
end;

procedure OtherUnit(pForm: TfrmMain);
begin
  pForm.qryOrders.FieldByName('NOTE').Size := 88; { fMain's dataset from another unit -> FIRES }
end;

end.