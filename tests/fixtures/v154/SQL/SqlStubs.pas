unit SqlStubs;
interface
const
  SQL_SHARED = 'SELECT A FROM T WHERE ' + 'ID = :SHARED';
type
  TParam = class
    AsInteger: Integer;
  end;
  TParams = class
    function ParamByName(const N: string): TParam; virtual; abstract;
  end;
  TStrings = class
    Text: string;
    procedure Add(const S: string); virtual; abstract;
    procedure Clear; virtual; abstract;
  end;
  TDataSet = class
    Active: Boolean;
    Eof: Boolean;
    procedure Open; virtual; abstract;
    procedure Next; virtual; abstract;
    procedure Close; virtual; abstract;
  end;
  TFDQuery = class(TDataSet)
    SQL: TStrings;
    Params: TParams;
    ParamCheck: Boolean;
    MasterSource: TObject;
    Connection: TFDConnection;
    constructor Create(O: TObject);
    function ParamByName(const N: string): TParam; virtual; abstract;
    function FindParam(const N: string): TParam; virtual; abstract;
    function FieldByName(const N: string): TParam; virtual; abstract;
    procedure ExecSQL; virtual; abstract;
    procedure Execute(N: Integer); virtual; abstract;
  end;
  TFDConnection = class
    procedure ExecSQL(const S: string); virtual; abstract;
  end;
  TFDMemTable = class(TDataSet)
  end;
  TForm = class
  end;
function GetQ: TFDQuery;
implementation
constructor TFDQuery.Create(O: TObject);
begin
end;
function GetQ: TFDQuery;
begin
  Result := nil;
end;
end.