program DfmChainLoad;

{ A REAL VCL load of an inheritance CHAIN of .dfm files (1.26.5), for the
  convert suites. Each argument is one chain, its files joined with '+',
  ancestor first: 'Base.dfm+Child.dfm'. Every file of a chain is read with
  TReader.ReadRootComponent into ONE root, exactly as the VCL builds an
  inherited form, with FireDAC, BDE and the Data.DB field classes registered.
  Output per chain:
    ERR <file> : <message>          a reader error (handled, the load goes on)
    FATAL <file> : <class>: <msg>   the load stopped
    FIELDS <dataset>: <f1> <f2> ... one line per TDataSet, its Fields in order
    DONE <last file> errors=<n>
  WHY: a .dfm can parse (DfmLoadCheck) and still load DIFFERENTLY -- the `[n]`
  child-position marker on a header decides where a parent's child lands
  (TReader.ReadComponent -> Parent.SetChildOrder), so a dataset's Fields
  order only shows after a real load. Built on demand by DfmChainLoad.ps1. }

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.SysUtils,
  Data.DB,
  Bde.DBTables,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Param, FireDAC.Stan.Error,
  FireDAC.DatS, FireDAC.Phys.Intf, FireDAC.DApt.Intf, FireDAC.Stan.Async, FireDAC.DApt,
  FireDAC.Comp.DataSet, FireDAC.Comp.Client;

type
  { stands in for a component class this loader does not link (a data source,
    a third-party control): the component is read, its own properties dropped }
  TStub = class(TComponent);

  THandler = class
    FileName: string;
    Count   : Integer;
    procedure DoError(Reader: TReader; const Message: string; var Handled: Boolean);
    procedure DoFindMethod(Reader: TReader; const MethodName: string; var Address: Pointer; var Error: Boolean);
    procedure DoFindClass(Reader: TReader; const ClassName: string; var ComponentClass: TComponentClass);
  end;

procedure THandler.DoError(Reader: TReader; const Message: string; var Handled: Boolean);
begin
  Inc(Count);
  Writeln('ERR ', FileName, ' : ', Message);
  Handled:= True;
end;

procedure THandler.DoFindClass(Reader: TReader; const ClassName: string; var ComponentClass: TComponentClass);
begin
  if GetClass(ClassName) = nil then ComponentClass:= TStub;
end;

procedure THandler.DoFindMethod(Reader: TReader; const MethodName: string; var Address: Pointer; var Error: Boolean);
begin
  Error  := False;
  Address:= nil;
end;

procedure LoadChain(const AChain: string);
var
  Text, Bin: TMemoryStream;
  Reader   : TReader;
  Root     : TComponent;
  H        : THandler;
begin
  H   := THandler.Create;
  Text:= TMemoryStream.Create;
  Bin := TMemoryStream.Create;
  Root:= TDataModule.CreateNew(nil);
  try
    for var Path: string in AChain.Split(['+']) do
    begin
      H.FileName:= ExtractFileName(Path);
      Text.Clear;
      Bin.Clear;
      Text.LoadFromFile(Path);
      try
        ObjectTextToBinary(Text, Bin);
        Bin.Position:= 0;
        Reader:= TReader.Create(Bin, 4096);
        try
          Reader.OnError     := H.DoError;
          Reader.OnFindMethod:= H.DoFindMethod;
          Reader.OnFindComponentClass:= H.DoFindClass;
          Reader.ReadRootComponent(Root);
        finally
          Reader.Free;
        end;
      except
        on E: Exception do
        begin
          Inc(H.Count);
          Writeln('FATAL ', H.FileName, ' : ', E.ClassName, ': ', E.Message);
        end;
      end;
    end;
    for var K: Integer:= 0 to Root.ComponentCount - 1 do
      if Root.Components[K] is TDataSet then
      begin
        Write('FIELDS ', Root.Components[K].Name, ':');
        for var F: TField in TDataSet(Root.Components[K]).Fields do Write(' ', F.FieldName);
        Writeln;
      end;
    Writeln('DONE ', H.FileName, ' errors=', H.Count);
  finally
    try
      Root.Free;
    except
      on Exception do ;
    end;
    Bin.Free;
    Text.Free;
    H.Free;
  end;
end;

begin
  RegisterClasses([TFDTable, TFDQuery, TFDAutoIncField, TFDUpdateSQL, TFDStoredProc, TFDConnection,
    TFDMemTable, TTable, TQuery, TUpdateSQL, TStoredProc, TDatabase, TSession, TDataSource,
    TStringField, TIntegerField, TFloatField, TBooleanField, TDateTimeField, TAutoIncField,
    TSmallintField, TWordField, TLargeintField, TDateField, TTimeField, TBlobField, TMemoField,
    TGraphicField, TCurrencyField, TBCDField, TFMTBCDField, TWideStringField]);
  for var I: Integer:= 1 to ParamCount do LoadChain(ParamStr(I));
end.
