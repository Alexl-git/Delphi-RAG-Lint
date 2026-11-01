unit IfFix;

interface

type
  IJob = interface
    ['{6B3E0C1A-1111-4E2B-9C6E-000000000001}']
    procedure Execute;
    function GetName: string;
    property Name: string read GetName;
  end;

  IJobEx = interface(IJob)
    ['{6B3E0C1A-1111-4E2B-9C6E-000000000002}']
    procedure Cancel;
  end;

  TPlainJob = class(TInterfacedObject, IJob)
  public
    procedure Execute;
    function GetName: string;
  end;

  TRenamedJob = class(TInterfacedObject, IJob)
  public
    procedure IJob.Execute = RunJob;
    procedure RunJob;
    function GetName: string;
  end;

  TBaseJob = class(TInterfacedObject)
  public
    procedure Execute;
    function GetName: string;
  end;

  TInheritedJob = class(TBaseJob, IJobEx)
  public
    procedure Cancel;
  end;

  TSubJob = class(TPlainJob)
  end;

  TNotAJob = class(TInterfacedObject)
  public
    procedure Execute;
  end;

  TVirtJob = class(TInterfacedObject, IJob)
  public
    procedure Execute; virtual;
    function GetName: string;
  end;

  TOverJob = class(TVirtJob)
  public
    procedure Execute; override;
  end;

  TDelegatingJob = class(TInterfacedObject, IJob)
  private
    FInner: IJob;
  public
    property Inner: IJob read FInner implements IJob;
  end;

procedure UseIt(const pJob: IJob);

implementation

procedure TPlainJob.Execute; begin end;
function TPlainJob.GetName: string; begin Result := 'p'; end;
procedure TRenamedJob.RunJob; begin end;
function TRenamedJob.GetName: string; begin Result := 'r'; end;
procedure TBaseJob.Execute; begin end;
function TBaseJob.GetName: string; begin Result := 'b'; end;
procedure TInheritedJob.Cancel; begin end;
procedure TNotAJob.Execute; begin end;
procedure TVirtJob.Execute; begin end;
function TVirtJob.GetName: string; begin Result := 'v'; end;
procedure TOverJob.Execute; begin end;

procedure UseIt(const pJob: IJob);
var
  S: string;
begin
  pJob.Execute;
  S := pJob.Name;
  S := pJob.GetName;
end;

end.
