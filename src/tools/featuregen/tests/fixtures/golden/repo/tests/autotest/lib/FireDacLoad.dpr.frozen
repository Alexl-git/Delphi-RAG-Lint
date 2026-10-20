program FireDacLoad;

{ Loads each .dfm named on the command line into a TDataModule through VCL's
  own reader with the REAL FireDAC classes registered, then prints what landed
  in every TFDQuery / TFDStoredProc's Params. Driven by FireDacLoad.ps1.

  Output, one line each:
    FAIL <file>: <message>         a reader error (unknown property, bad value)
    PARAMS <file> <component> <count>
    PARAM <file> <component> <index> Name=<n> DataType=<dt> ParamType=<pt> Value=<v>
    DONE <file> errors=<n> }

{$APPTYPE CONSOLE}

uses
  System.Classes, System.SysUtils, System.Variants, System.TypInfo, Data.DB,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Param, FireDAC.Stan.Error,
  FireDAC.DatS, FireDAC.Phys.Intf, FireDAC.DApt.Intf, FireDAC.Stan.Async, FireDAC.DApt,
  FireDAC.Comp.DataSet, FireDAC.Comp.Client, FireDAC.Stan.Def, FireDAC.Stan.Pool,
  FireDAC.Phys, FireDAC.UI.Intf;

type
  TLoadHandler = class
  public
    FileName: string;
    Errors  : Integer;
    procedure DoError(pReader: TReader; const pMessage: string; var pHandled: Boolean);
    procedure DoFindMethod(pReader: TReader; const pMethodName: string; var pAddress: Pointer; var pError: Boolean);
  end;

procedure TLoadHandler.DoError(pReader: TReader; const pMessage: string; var pHandled: Boolean);
begin
  Inc(Errors);
  Writeln('FAIL ', FileName, ': ', pMessage);
  pHandled := True;
end;

procedure TLoadHandler.DoFindMethod(pReader: TReader; const pMethodName: string; var pAddress: Pointer;
  var pError: Boolean);
begin
  pError := False;
  pAddress := nil;
end;

procedure PrintParams(const pFile, pComp: string; pParams: TFDParams);
var
  lIdx: Integer;
  lPar: TFDParam;
begin
  Writeln('PARAMS ', pFile, ' ', pComp, ' ', pParams.Count);
  for lIdx := 0 to pParams.Count - 1 do
  begin
    lPar := pParams[lIdx];
    Writeln(Format('PARAM %s %s %d Name=%s DataType=%s ParamType=%s Value=%s',
      [pFile, pComp, lIdx, lPar.Name,
       GetEnumName(TypeInfo(TFieldType), Ord(lPar.DataType)),
       GetEnumName(TypeInfo(TParamType), Ord(lPar.ParamType)),
       VarToStr(lPar.Value)]));
  end;
end;

procedure LoadOne(const pPath: string);
var
  lText  : TMemoryStream;
  lBin   : TMemoryStream;
  lReader: TReader;
  lRoot  : TDataModule;
  lH     : TLoadHandler;
  lIdx   : Integer;
  lComp  : TComponent;
begin
  lH := TLoadHandler.Create;
  try
    lH.FileName := ExtractFileName(pPath);
    lText := TMemoryStream.Create;
    try
      lBin := TMemoryStream.Create;
      try
        lText.LoadFromFile(pPath);
        try
          ObjectTextToBinary(lText, lBin);
        except
          on E: Exception do
          begin
            Writeln('FAIL ', lH.FileName, ': ', E.ClassName, ': ', E.Message);
            Exit;
          end;
        end;
        lBin.Position := 0;
        lRoot := TDataModule.CreateNew(nil);
        try
          lReader := TReader.Create(lBin, 4096);
          try
            lReader.OnError := lH.DoError;
            lReader.OnFindMethod := lH.DoFindMethod;
            try
              lReader.ReadRootComponent(lRoot);
            except
              on E: Exception do
              begin
                Inc(lH.Errors);
                Writeln('FAIL ', lH.FileName, ': ', E.ClassName, ': ', E.Message);
              end;
            end;
          finally
            lReader.Free;
          end;
          for lIdx := 0 to lRoot.ComponentCount - 1 do
          begin
            lComp := lRoot.Components[lIdx];
            if lComp is TFDQuery then PrintParams(lH.FileName, lComp.Name, TFDQuery(lComp).Params)
            else if lComp is TFDStoredProc then PrintParams(lH.FileName, lComp.Name, TFDStoredProc(lComp).Params);
          end;
          Writeln('DONE ', lH.FileName, ' errors=', lH.Errors);
        finally
          lRoot.Free;
        end;
      finally
        lBin.Free;
      end;
    finally
      lText.Free;
    end;
  finally
    lH.Free;
  end;
end;

var
  gIdx: Integer;
begin
  RegisterClasses([TFDQuery, TFDStoredProc, TFDTable, TFDConnection, TFDMemTable, TFDUpdateSQL,
    TFDAutoIncField, TStringField, TIntegerField, TFloatField, TDateTimeField, TBooleanField]);
  for gIdx := 1 to ParamCount do
    LoadOne(ParamStr(gIdx));
end.
