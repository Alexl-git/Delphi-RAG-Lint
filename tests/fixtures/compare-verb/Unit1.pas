unit Unit1;

{ Fixture for tests\autotest\run_compare_verb.ps1: two routines write TFoo.FName.
  The test copies this folder to a temp dir and, for C-DIFF, makes Reset write it too. }

interface

type
  TFoo = class
  private
    FName: string;
  public
    procedure SetName(const pValue: string);
    procedure Load;
    procedure Reset;
  end;

implementation

procedure TFoo.SetName(const pValue: string);
begin
  FName:= pValue;
end;

procedure TFoo.Load;
begin
  FName:= 'loaded';
end;

procedure TFoo.Reset;
begin
end;

end.
