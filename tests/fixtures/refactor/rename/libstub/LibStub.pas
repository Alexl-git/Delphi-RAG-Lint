unit LibStub;

// NOT part of the project. The guard indexes it as a miniature platform library, so the proof has library facts without the
// 3 GB database: TList's Count and TObject's Free live here, and only here.

interface

type
  TObject = class
    procedure Free;
    function ClassName: string;
    procedure AfterConstruction; virtual;
  end;
  TInterfacedObject = class(TObject)
  end;
  TList = class(TObject)
    function Count: Integer;
    procedure Add;
  end;
  TStringList = class(TList)
    function Capacity: Integer;
  end;

function Format: string;

implementation

end.
