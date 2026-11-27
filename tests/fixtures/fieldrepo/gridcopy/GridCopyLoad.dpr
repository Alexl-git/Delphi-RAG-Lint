program GridCopyLoad;

{ Loads the fixture form the way an application does (compiled unit, linked DFM) and prints what Delphi made of its
  grid views: the columns, their classes and bands, which handler each event points at, and what a column's
  OnGetDisplayText handler answers. run_v156_GCPM.ps1 builds it before and after a grid copy was written. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, Vcl.Forms, FireDAC.Stan.Def, FireDAC.Stan.Async, FireDAC.DApt, FireDAC.VCLUI.Wait,
  cxGridCustomView, cxGridCustomTableView, cxGridTableView, cxGridBandedTableView, cxGridDBDataDefinitions,
  uCopy in 'uCopy.pas';

procedure PrintItem(pForm: TfrmCopy; pItem: TcxCustomGridTableItem);
var
  VText, VField: string;
begin
  VText := 'x';
  if Assigned(pItem.OnGetDisplayText) then
    pItem.OnGetDisplayText(pItem, nil, VText);
  VField := '';
  if pItem.DataBinding is TcxGridItemDBDataBinding then
    VField := TcxGridItemDBDataBinding(pItem.DataBinding).FieldName;
  Writeln('  ', pItem.Name, '|', pItem.ClassName, '|', VField, '|caption=', pItem.Caption,
    '|band=', if pItem is TcxGridBandedColumn then TcxGridBandedColumn(pItem).Position.BandIndex.ToString else 'none',
    '|editor=', pItem.PropertiesClassName, '|text=', pForm.MethodName(TMethod(pItem.OnGetDisplayText).Code), '>', VText,
    '|draw=', pForm.MethodName(TMethod(pItem.OnCustomDrawCell).Code),
    '|published=', (pForm.FieldAddress(pItem.Name) <> nil) and (PPointer(pForm.FieldAddress(pItem.Name))^ = Pointer(pItem)));
end;

procedure PrintView(pForm: TfrmCopy; const pName: string);
var
  VView: TcxCustomGridTableView;
  VI: Integer;
begin
  VView := pForm.FindComponent(pName) as TcxCustomGridTableView;
  Writeln(pName, '|', VView.ClassName, '|items=', VView.ItemCount,
    '|bands=', if VView is TcxGridBandedTableView then TcxGridBandedTableView(VView).Bands.Count.ToString else 'none',
    '|draw=', pForm.MethodName(TMethod(VView.OnCustomDrawCell).Code),
    '|dblclick=', pForm.MethodName(TMethod(VView.OnCellDblClick).Code));
  for VI := 0 to VView.ItemCount - 1 do
    PrintItem(pForm, VView.Items[VI]);
end;

var
  GForm: TfrmCopy;
begin
  try
    GForm := TfrmCopy.Create(nil);
    try
      PrintView(GForm, 'tvMain');
      PrintView(GForm, 'bvMain');
      PrintView(GForm, 'cvMain');
      Writeln('LOADED');
    finally
      GForm.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln('FAILED ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
