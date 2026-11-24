program AllKindsLoad;

{ Loads the fixture form the way an application does (compiled unit, linked DFM) and prints what Delphi made of it.
  run_fieldrepo_dfmwrite.ps1 builds it before and after `repo write-dfm --apply`. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.TypInfo, Vcl.Forms, Data.DB, FireDAC.Comp.Client, FireDAC.UI.Intf,
  FireDAC.Stan.ExprFuncs, FireDAC.VCLUI.Wait,
  uAllKinds in 'uAllKinds.pas';

procedure PrintField(pForm: TfrmAllKinds; pField: TField);
begin
  Writeln(pField.Name, '|', pField.ClassName, '|', GetEnumName(TypeInfo(TFieldKind), Ord(pField.FieldKind)), '|', pField.FieldName,
    '|label=', pField.DisplayLabel.Replace(#233, '#233'), '|visible=', pField.Visible, '|align=', Ord(pField.Alignment), '|size=', pField.Size,
    '|published=', (pForm.FieldAddress(pField.Name) <> nil) and (PPointer(pForm.FieldAddress(pField.Name))^ = Pointer(pField)));
end;

procedure Fill(pForm: TfrmAllKinds);
begin
  pForm.memTools.CreateDataSet;
  pForm.memTools.AppendRecord([1, 'Drill']);
  pForm.memOrders.CreateDataSet;
  pForm.memOrders.Append;
  pForm.memOrders.FieldByName('ID').AsInteger := 1;
  pForm.memOrders.FieldByName('QTY').AsInteger := 5;
  if pForm.memOrders.FindField('TOOLID') <> nil then
    pForm.memOrders.FieldByName('TOOLID').AsInteger := 1;
  pForm.memOrders.Post;
end;

var
  GForm: TfrmAllKinds;
  GI: Integer;
begin
  try
    GForm := TfrmAllKinds.Create(nil);
    try
      for GI := 0 to GForm.memOrders.Fields.Count - 1 do
        PrintField(GForm, GForm.memOrders.Fields[GI]);
      for GI := 0 to GForm.memOrders.AggFields.Count - 1 do
        PrintField(GForm, GForm.memOrders.AggFields[GI]);
      Fill(GForm);
      if GForm.memOrders.FindField('TOOL') <> nil then
        Writeln('lookup=', GForm.memOrders.FieldByName('TOOL').AsString);
      if GForm.memOrders.AggFields.Count > 0 then
        Writeln('sum=', GForm.memOrders.AggFields[0].AsString);
      Writeln('columns=', GForm.GridView.ColumnCount, ',', GForm.Tree.ColumnCount);
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
