unit Wide.Proc;

interface

uses
  Wide.Sink,
  WideDm;

type
  /// <summary>The Loader TFolderProcessor shape: owns data modules, stores a field through them.</summary>
  TWideProc = class
  private
    FDir  : string;
    FSink : TWideSink;
    FDm_A : TWideDm;
  public
    /// <summary>Creates the owned module.</summary>
    /// <param name="pDir">Passed on.</param>
    /// <param name="pSink">Not owned.</param>
    constructor Create(const pDir: string; pSink: TWideSink);
    /// <summary>Frees the owned module.</summary>
    destructor Destroy; override;
    /// <summary>Stores the id, then drives the module.</summary>
    /// <param name="pId">The folder id.</param>
    procedure ProcessFolder(pId: Integer);
  end;

implementation

constructor TWideProc.Create(const pDir: string; pSink: TWideSink);
begin
  inherited Create;
  FDir  := pDir;
  FSink := pSink;
  FDm_A := TWideDm  .Create(nil); FDm_A  .Configure(FSink);
end;

destructor TWideProc.Destroy;
begin
  FDm_A  .Free;
  inherited;
end;

procedure TWideProc.ProcessFolder(pId: Integer);
begin
  FDm_A  .GId := pId;  FDm_A  .LoadData(FDir, pId);
end;

end.