unit uR10Base;

interface

type
  { Stand-ins: the fixture runs without a library index. }
  TObject = class
  end;

  TField = class(TObject)
  public
    AsString: string;
  end;

  TDataSet = class(TObject)
  public
    function FieldByName(const AName: string): TField;
    procedure Next;
    function Eof: Boolean;
  end;

  TR10Query = class(TDataSet)
  end;

  TR10Report = class(TObject)
  public
    function FieldByName(const AName: string): TField;
    procedure Next;
    function Eof: Boolean;
  end;

  TDictionary<K, V> = class(TObject)
  public
    function ContainsKey(const AKey: K): Boolean;
    function TryGetValue(const AKey: K; out AValue: V): Boolean;
    property Items[const AKey: K]: V read GetItem; default;
  end;

  TR10Config = class(TObject)
  public
    function ContainsKey(const AKey: string): Boolean;
    property Items[const AKey: string]: string read GetItem; default;
  end;

implementation

end.
