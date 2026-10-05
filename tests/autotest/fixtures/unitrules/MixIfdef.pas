unit MixIfdef;

interface

uses
  Classes, LibA{$IFDEF FOO}, OldU{$ENDIF};

type
  TMixIfdef = class(TComponent)
    btnTop: TSrcBtn;
  end;

implementation

{$R *.dfm}

end.
