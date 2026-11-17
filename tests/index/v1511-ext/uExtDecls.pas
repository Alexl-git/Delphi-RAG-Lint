unit uExtDecls;

interface

uses
  uExtDefs;

const
  WM_EXT_PROBE = $0401;

type
  TExtMsg = record
    Msg: Cardinal;
    Res: NativeInt;
  end;

  TExtBoxG<T: TExtItem> = class
  public
    type
      TInnerG = record
        Val: T;
      end;
  private
    FItem: T;
  public
    function GetAt(const pIdx: Integer): Integer;
    procedure Fill<K: TExtOther>(const pKey: K);
  end;

  TExtLeaf = class(TExtItem)
  private
    procedure WMProbe(var pMsg: TExtMsg); message WM_EXT_PROBE;
  public
    procedure OldRun; deprecated 'use Run';
    function Inner: Integer;
  end;

implementation

function TExtBoxG<T>.GetAt(const pIdx: Integer): Integer;
begin
  Result := pIdx + FItem.Count;
end;

procedure TExtBoxG<T>.Fill<K>(const pKey: K);
begin
  FItem.Text := pKey.Text;
end;

procedure TExtLeaf.WMProbe(var pMsg: TExtMsg);
begin
  pMsg.Res := 1;
end;

procedure TExtLeaf.OldRun;
begin
  Run;
end;

function TExtLeaf.Inner: Integer;
var
  lInner: TExtBoxG<TExtLeaf>.TInnerG;
begin
  lInner.Val := Self;
  Result := lInner.Val.Count;
end;

end.
