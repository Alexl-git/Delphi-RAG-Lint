unit double_free_member;

{ v151 WID-FLOW: double-free widened to (1) a direct Destroy call, which frees
  exactly like Free, and (2) fields and other member paths freed twice in
  straight-line code (two ADJACENT frees of the same path). }

interface

uses
  System.Classes, System.SysUtils;

type
  TBox = class
  private
    FL: TStringList;
    FM: TStringList;
  public
    procedure FieldTwice;
    procedure SelfFieldTwice;
    procedure FieldFreeAndNilThenFree;
    procedure FieldReassignedBetween;
    procedure FieldDifferent;
    procedure DestroyThenFree;
    procedure DestroyOnce;
  end;

implementation

procedure TBox.FieldTwice;
begin
  FL.Free;
  FL.Free;
end;

procedure TBox.SelfFieldTwice;
begin
  Self.FL.Free;
  Self.FL.Free;
end;

procedure TBox.FieldFreeAndNilThenFree;
begin
  FreeAndNil(FL);
  FL.Free;
end;

procedure TBox.FieldReassignedBetween;
begin
  FL.Free;
  FL := TStringList.Create;
  FL.Free;
end;

procedure TBox.FieldDifferent;
begin
  FL.Free;
  FM.Free;
end;

procedure TBox.DestroyThenFree;
var
  L: TStringList;
begin
  L := TStringList.Create;
  L.Destroy;
  L.Free;
end;

procedure TBox.DestroyOnce;
var
  L: TStringList;
begin
  L := TStringList.Create;
  L.Destroy;
end;

end.
