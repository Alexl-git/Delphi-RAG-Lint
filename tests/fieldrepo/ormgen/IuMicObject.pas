unit IuMicObject;

{ Stub of the ORM3 unit of the same name: only what the generated units reference. }

interface

uses
  FireDAC.Comp.Client,
  MStreams;

type
  IMicObject = interface
    ['{C7EA8A61-0C71-4F49-AF90-1979E4BF340B}']
    function GetModified: Boolean;
    procedure SetModified(const Value: Boolean);
    function Reader(AStream: TABZMemoryStream): Boolean;
    function Writer(AStream: TABZMemoryStream): Boolean;
    property Modified: Boolean read GetModified write SetModified;
  end;

  IDataService = interface
    ['{E6A2B3C4-1D2E-4F5A-8B6C-7D8E9F0A1B2C}']
  end;

  IDataService<I: IMicObject> = interface(IDataService)
    ['{E6A2B3C4-1D2E-4F5A-8B6C-7D8E9F0A1B2D}']
    function Load(const Obj: I): Boolean;
    function Save(const Obj: I): Boolean;
    function NextID: Int64;
  end;

  IThreadStorage = interface
    ['{19678C1A-84CA-4791-872B-C9F468F81705}']
    function GetDataBase: TFDConnection;
    function GetTransaction: TFDTransaction;
    function GetUpdateTransaction: TFDTransaction;
    property DataBase: TFDConnection read GetDataBase;
    property Transaction: TFDTransaction read GetTransaction;
    property UpdateTransaction: TFDTransaction read GetUpdateTransaction;
  end;

implementation

end.
