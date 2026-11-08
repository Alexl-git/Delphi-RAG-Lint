unit WideDm;

interface

uses
  System.Classes,
  Data.DB,
  Wide.Sink;

type
  /// <summary>The Loader TdmX shape: a data module with a .dfm, a public field the consumer stores, two plain methods.</summary>
  TWideDm = class(TDataModule)
    Src: TDataSource;
    procedure DataModuleCreate(Sender: TObject);
  private
    FSink: TWideSink;
  public
    GId: Int64;
    /// <summary>Hands the sink over.</summary>
    /// <param name="pSink">Not owned.</param>
    procedure Configure(pSink: TWideSink);
    /// <summary>Prints what the instance holds.</summary>
    /// <param name="pDir">Printed.</param>
    /// <param name="pId">Printed beside GId.</param>
    procedure LoadData(const pDir: string; pId: Integer);
  end;

implementation

{$R *.dfm}

uses
  System.SysUtils,
  WideHub;

procedure TWideDm.DataModuleCreate(Sender: TObject);
begin
  Writeln('[dm] streamed ', ClassName, ' ', Src.Name);
end;

procedure TWideDm.Configure(pSink: TWideSink);
begin
  FSink := pSink;
end;

procedure TWideDm.LoadData(const pDir: string; pId: Integer);
begin
  FSink.Say(Format('[dm] %s %s %d %d', [GHubTitle, pDir, GId, pId]));
end;

end.