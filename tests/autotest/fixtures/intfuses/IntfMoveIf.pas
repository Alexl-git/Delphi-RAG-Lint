unit IntfMoveIf;

interface

uses
  Classes, LibA;

type
  TIntfMoveIf = class(TComponent)
    btnTop: TSrcBtn;
  end;

implementation

uses
  ImplU{$IFDEF MSWINDOWS}, LibB{$ENDIF};

{$R *.dfm}

end.
