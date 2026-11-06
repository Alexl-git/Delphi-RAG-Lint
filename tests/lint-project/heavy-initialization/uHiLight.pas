unit uHiLight;

{ All silent: a list, a string computed with TPath, a routine nobody in the section calls, a
  closure the section only passes, and a file access in the finalization. }

interface

implementation

uses
  System.Classes, System.IOUtils;

var
  GList: TStringList;
  GPath: string;

type
  TLater = reference to procedure;

procedure NotCalled;
begin
  TFile.Delete('x');
end;

procedure RegisterLater(const AProc: TLater);
begin
end;

initialization
  GList:= TStringList.Create; // CONTROL-LIST
  GPath:= TPath.Combine('a', 'b'); // CONTROL-TPATH
  RegisterLater(procedure
    begin
      TFile.Delete('z'); // CONTROL-CLOSURE passing a closure does not run it
      NotCalled;
    end);
finalization
  GList.Free;
  TFile.Delete('y'); // CONTROL-FINAL a finalization is not an initialization
end.