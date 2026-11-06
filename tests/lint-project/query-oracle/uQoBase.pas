unit uQoBase;

interface

type
  { Stand-ins for the library classes the rules look for: the fixture runs without a library index. }
  TObject2 = class
  end;

  TQoStream = class
  public
    function Read(var ABuf; ACount: Integer): Integer;
    function Write(const ABuf; ACount: Integer): Integer;
  end;

  TQoFileStream = class(TQoStream)
  end;

  TQoBox = class
  public
    function Read(var ABuf; ACount: Integer): Integer;
    constructor Create;
  end;

  TThread = class
  public
    constructor Create;
  end;

  TQoBaseWorker = class(TThread)
  end;

  TIdHTTPResponseInfo = class
  public
    ContentText: string;
  end;

  TQoNote = class
  public
    ContentText: string;
  end;

implementation

end.
