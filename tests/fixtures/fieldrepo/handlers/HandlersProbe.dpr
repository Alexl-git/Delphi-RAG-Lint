program HandlersProbe;

{ Runs the generated handlers of uGen; run_fieldrepo_handlers.ps1 compares the output. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Data.DB,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.DApt,
  FireDAC.ConsoleUI.Wait,
  uGen in 'uGen.pas' {dmGen: TDataModule};

var
  VData: TdmGen;
begin
  FormatSettings.DecimalSeparator := '.';
  try
    VData := TdmGen.Create(nil);
    try
      VData.memOrders.CreateDataSet;
      VData.memOrders.Append;
      VData.memOrdersQTY.AsInteger := 3;
      Writeln('change=', VData.memOrdersNOTE.AsString);
      VData.memOrdersPRICE.AsFloat := 2.5;
      VData.memOrders.Post;
      Writeln('total=', VData.memOrdersTOTAL.AsString, ' vat=', VData.memOrdersVAT.AsString, ' handy=', VData.memOrdersHANDY.AsString);
      Writeln('text=', VData.memOrdersNOTE.DisplayText);
      VData.memOrders.Edit;
      VData.memOrdersNOTE.Text := 'abc';
      Writeln('set=', VData.memOrdersNOTE.AsString);
      try
        VData.memOrdersQTY.AsInteger := -1;
        Writeln('validate=none');
      except
        on E: Exception do
          Writeln('validate=', E.Message);
      end;
      VData.memOrdersQTY.Clear;
      VData.memOrders.Post;
      Writeln('null=', VData.memOrdersTOTAL.IsNull);
      Writeln('calls=', VData.Calls > 0);
    finally
      VData.Free;
    end;
  except
    on E: Exception do
      Writeln('EXCEPTION ', E.ClassName, ': ', E.Message);
  end;
end.
