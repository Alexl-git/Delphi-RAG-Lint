unit IuMicX;

{ RB-A (wave 151) item 2 fixture: the ORM3 IuMicObject shape -- a forward
  declaration and the full interface of one name. }

interface

type
  IMicX = interface;
  IDataSvc = interface;

  IDataSvc = interface
    ['{11111111-0C71-4F49-AF90-1979E4BF340B}']
    function Get: IMicX;
  end;

  IMicX = interface
    ['{C7EA8A61-0C71-4F49-AF90-1979E4BF340B}']
    function GetDataService: IDataSvc;
  end;

implementation

end.