unit CvLib;
interface
uses System.Classes;
type
  TScreenCursorOld = (scoDefault, scoWait);
  TScreenCursorNew = (scnDefault, scnWait);
  TOldParam = class(TCollectionItem)
  private
    FName: string; FDataType: Integer;
  published
    property Name: string read FName write FName;
    property DataType: Integer read FDataType write FDataType;
  end;
  TNewParam = class(TCollectionItem)
  private
    FName: string; FParamType: Integer;
  published
    property Name: string read FName write FName;
    property ParamType: Integer read FParamType write FParamType;
  end;
  TOldParams = class(TCollection)
  private
    function GetItem(I: Integer): TOldParam;
  public
    property Items[I: Integer]: TOldParam read GetItem; default;
  end;
  TNewParams = class(TCollection)
  private
    function GetItem(I: Integer): TNewParam;
  public
    property Items[I: Integer]: TNewParam read GetItem; default;
  end;
  TOldQuery = class(TComponent)
  private
    FSql: string; FParams: TOldParams;
  published
    property Sql: string read FSql write FSql;
    property Params: TOldParams read FParams write FParams;
  end;
  TNewQuery = class(TComponent)
  private
    FSql: string; FParams: TNewParams;
  published
    property Sql: string read FSql write FSql;
    property Params: TNewParams read FParams write FParams;
  end;
  TOldField = class(TComponent)
  private
    FSize: Integer;
  published
    property Size: Integer read FSize write FSize;
  end;
  TNewField = class(TComponent)
  private
    FSize: Integer;
  published
    property Size: Integer read FSize write FSize;
  end;
implementation
function TOldParams.GetItem(I: Integer): TOldParam; begin Result:= TOldParam(inherited Items[I]); end;
function TNewParams.GetItem(I: Integer): TNewParam; begin Result:= TNewParam(inherited Items[I]); end;
end.
