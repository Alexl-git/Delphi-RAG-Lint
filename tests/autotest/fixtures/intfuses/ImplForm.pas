unit ImplForm;

interface

uses
  Classes, LibA;

implementation

uses
  ImplU;

type
  TImplForm = class(TComponent)
    btnTop: TSrcBtn;
  end;

{$R *.dfm}

end.
