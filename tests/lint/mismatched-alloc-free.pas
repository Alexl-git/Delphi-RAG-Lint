unit mismatched_alloc_free;

{ mismatched-alloc-free fixture.  HIT marker = rule fires, OK marker = silent. }

interface

implementation

uses
  System.SysUtils;

type
  TRec = record
    A: Integer;
  end;
  PRec = ^TRec;

procedure NewThenFreeMem;
var
  P: PRec;
begin
  New(P);
  FreeMem(P); {HIT}
end;

procedure GetMemThenFree;
var
  P: Pointer;
begin
  GetMem(P, 16);
  FreeAndNil(P); {HIT}
end;

procedure CreateThenFreeMem;
var
  O: TObject;
begin
  O:= TObject.Create;
  FreeMem(O); {HIT}
end;

procedure AddressOfLocal;
var
  V: Integer;
begin
  Dispose(@V); {HIT}
end;

procedure GetMemFreeMem;
var
  P: Pointer;
begin
  GetMem(P, 16);
  FreeMem(P); {OK}
end;

procedure NewDispose;
var
  P: PRec;
begin
  New(P);
  Dispose(P); {OK}
end;

procedure CreateFree;
var
  O: TObject;
begin
  O:= TObject.Create;
  O.Free; {OK}
end;

end.
