unit UA;

interface

uses
  UB, UC;

type
  IA = interface
    procedure Go;
  end;

  TA = class(TObject)
  public
    procedure Run;
  end;

implementation

uses
  System.SysUtils;

procedure TA.Run;
begin
  Sleep(1);
end;

end.
