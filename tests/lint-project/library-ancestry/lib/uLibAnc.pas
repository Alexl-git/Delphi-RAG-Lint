unit uLibAnc;

{ The LIBRARY half of run_library_ancestry_rules.ps1: stand-ins for RTL/VCL classes, indexed into
  a temp library DB. The project half (..\proj\uLibUse.pas) declares no ancestor of its own, so a
  verdict about these classes is only reachable when the library store reaches the checker. }

interface

type
  TComponent = class
  end;

  TControl = class(TComponent)
  public
    Caption: string;
  end;

  TLabel = class(TControl)
  end;

  TDataSet = class
  public
    function Eof: Boolean;
    function FieldByName(const AName: string): TObject;
    procedure Next;
    procedure Open;
    procedure Close;
  end;

  TLibQuery = class(TDataSet)
  end;

  TLibBase = class
  end;

  TLibPort = class(TLibBase)
  public
    procedure Open;
  end;

  TLibReport = class(TLibBase)
  public
    function Eof: Boolean;
    function FieldByName(const AName: string): TObject;
    procedure Next;
  end;

  TLibConfig = class(TLibBase)
  private
    function GetItem(const AKey: string): string;
  public
    function ContainsKey(const AKey: string): Boolean;
    property Items[const AKey: string]: string read GetItem; default;
  end;

  TThread = class
  public
    procedure Execute; virtual;
    procedure WaitFor;
  end;

  TLibWorker = class(TThread)
  end;

  TLibOwned = class(TComponent)
  end;

  /// <summary>A metaclass whose name does not say so; only the library index can tell.</summary>
  TLibMaker = class of TComponent;

  TCriticalSection = class
  public
    procedure Enter;
    procedure Leave;
  end;

  TLibSemaphore = class(TLibBase)
  public
    procedure Acquire;
    procedure Release;
  end;

  TIdHTTP = class
  public
    ReadTimeout: Integer;
    constructor Create(AOwner: TObject);
  end;

  TLibHttp = class(TIdHTTP)
  end;

  TStrings = class
  public
    procedure LoadFromFile(const AName: string);
  end;

  TStringList = class(TStrings)
  end;

  /// <summary>Its name says string, its ancestry says no TStrings.</summary>
  TLibStringTable = class(TLibBase)
  public
    procedure LoadFromFile(const AName: string);
  end;

  Exception = class
  public
    constructor Create(const AMsg: string);
  end;

  ELibFail = class(Exception)
  end;

  TLibFiller = class(TLibBase)
  public
    procedure Fill(var B; N: Integer);
  end;

implementation

function TDataSet.Eof: Boolean;
begin
  Result:= True;
end;

function TDataSet.FieldByName(const AName: string): TObject;
begin
  Result:= nil;
end;

procedure TDataSet.Next;
begin
end;

procedure TDataSet.Open;
begin
end;

procedure TDataSet.Close;
begin
end;

procedure TLibPort.Open;
begin
end;

function TLibReport.Eof: Boolean;
begin
  Result:= True;
end;

function TLibReport.FieldByName(const AName: string): TObject;
begin
  Result:= nil;
end;

procedure TLibReport.Next;
begin
end;

function TLibConfig.GetItem(const AKey: string): string;
begin
  Result:= AKey;
end;

function TLibConfig.ContainsKey(const AKey: string): Boolean;
begin
  Result:= AKey <> '';
end;

procedure TThread.Execute;
begin
end;

procedure TThread.WaitFor;
begin
end;

procedure TCriticalSection.Enter;
begin
end;

procedure TCriticalSection.Leave;
begin
end;

procedure TLibSemaphore.Acquire;
begin
end;

procedure TLibSemaphore.Release;
begin
end;

constructor TIdHTTP.Create(AOwner: TObject);
begin
  inherited Create;
end;

procedure TStrings.LoadFromFile(const AName: string);
begin
end;

procedure TLibStringTable.LoadFromFile(const AName: string);
begin
end;

constructor Exception.Create(const AMsg: string);
begin
  inherited Create;
end;

procedure TLibFiller.Fill(var B; N: Integer);
begin
end;

end.
