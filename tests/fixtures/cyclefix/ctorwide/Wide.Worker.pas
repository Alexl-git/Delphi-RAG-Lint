unit Wide.Worker;

interface

uses
  System.Classes,
  Wide.Sink,
  Wide.Proc;

type
  /// <summary>The Loader TFolderWorker shape: a thread whose Execute overrides the library's.</summary>
  TWideWorker = class(TThread)
  private
    FID  : Integer;
    FSink: TWideSink;
    FProc: TWideProc;
    FDone: Integer;
    function GetDone: Integer;
  protected
    procedure Execute; override;
  public
    /// <summary>A suspended worker.</summary>
    /// <param name="pId">Its id.</param>
    /// <param name="pSink">Not owned.</param>
    constructor Create(pId: Integer; pSink: TWideSink);
    /// <summary>Frees the processor.</summary>
    destructor Destroy; override;
    /// <summary>Starts the thread and waits for it.</summary>
    procedure RunToEnd;
    /// <summary>The id.</summary>
    property ID: Integer read FID;
    /// <summary>Folders done, through a method accessor.</summary>
    property Done: Integer read GetDone;
  end;

implementation

constructor TWideWorker.Create(pId: Integer; pSink: TWideSink);
begin
  inherited Create(True);
  FID   := pId;
  FSink := pSink;
end;

destructor TWideWorker.Destroy;
begin
  FProc.Free;
  inherited;
end;

function TWideWorker.GetDone: Integer;
begin
  Result := FDone;
end;

procedure TWideWorker.RunToEnd;
begin
  Start;
  WaitFor;
end;

procedure TWideWorker.Execute;
begin
  FProc := TWideProc.Create('dir', FSink);
  FProc.ProcessFolder(FID);
  Inc(FDone);
end;

end.