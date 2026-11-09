unit W4.Worker;

interface

uses
  System.Classes,
  W4.Sink;

type
  /// <summary>The Loader TFolderWorker shape: a thread whose Execute overrides the library's.</summary>
  TW4Worker = class(TThread)
  private
    FID  : Integer;
    FSink: TW4Sink;
    FDone: Integer;
    function GetDone: Integer;
  protected
    procedure Execute; override;
  public
    /// <summary>A suspended worker.</summary>
    /// <param name="pId">Its id.</param>
    /// <param name="pSink">Not owned.</param>
    constructor Create(pId: Integer; pSink: TW4Sink);
    /// <summary>Starts the thread and waits for it.</summary>
    procedure RunToEnd;
    /// <summary>The id.</summary>
    property ID: Integer read FID;
    /// <summary>Folders done, through a method accessor.</summary>
    property Done: Integer read GetDone;
  end;

implementation

uses
  System.SysUtils,
  W4Hub;

constructor TW4Worker.Create(pId: Integer; pSink: TW4Sink);
begin
  inherited Create(True);
  FID   := pId;
  FSink := pSink;
end;

function TW4Worker.GetDone: Integer;
begin
  Result := FDone;
end;

procedure TW4Worker.RunToEnd;
begin
  Start;
  WaitFor;
end;

procedure TW4Worker.Execute;
begin
  FSink.Say(GHubTitle + ' ' + IntToStr(FID));
  Inc(FDone);
end;

end.