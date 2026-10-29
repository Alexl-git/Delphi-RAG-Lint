unit ClosureCapturesLoopLocal;

interface

uses
  System.Classes, System.SysUtils, System.Threading, System.Generics.Collections;

implementation

procedure Use(const S: string);
begin
end;

procedure Bad(const AItems: TArray<string>);
var
  I: Integer;
  Name: string;
begin
  for I:= 0 to High(AItems) do
  begin
    Name:= AItems[I];
    TThread.Queue(nil,
      procedure
      begin
        Use(Name);
      end);
  end;
end;

procedure BadTask(const AItems: TArray<string>);
var
  I: Integer;
  Name: string;
begin
  for I:= 0 to High(AItems) do
  begin
    Name:= AItems[I];
    TTask.Run(
      procedure
      begin
        Use(Name);
      end);
  end;
end;

procedure GoodNoCapture(const AItems: TArray<string>);
var
  I: Integer;
  Name: string;
begin
  for I:= 0 to High(AItems) do
  begin
    Name:= AItems[I];
    TThread.Queue(nil,
      procedure
      begin
        Use('constant');
      end);
  end;
end;

procedure GoodSynchronous(const AItems: TArray<string>; AList: TList<string>);
var
  I: Integer;
  Name: string;
begin
  for I:= 0 to High(AItems) do
  begin
    Name:= AItems[I];
    AList.ForEach(
      procedure(const S: string)
      begin
        Use(Name);
      end);
  end;
end;

procedure GoodOutsideLoop(const AName: string);
var
  Name: string;
begin
  Name:= AName;
  TThread.Queue(nil,
    procedure
    begin
      Use(Name);
    end);
end;

end.
