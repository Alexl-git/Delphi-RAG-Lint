unit TlsVerificationDisabledClean;

interface

type
  TGood = class
    function VerifyPeer(Certificate: TObject; AOk: Boolean; ADepth, AError: Integer): Boolean;
    procedure CloseQuery(var CanClose: Boolean);
    function IsValid: Boolean;
  end;

implementation

function TGood.VerifyPeer(Certificate: TObject; AOk: Boolean; ADepth, AError: Integer): Boolean;
begin
  Result := AOk and (AError = 0);
end;

procedure TGood.CloseQuery(var CanClose: Boolean);
begin
  CanClose := True;
end;

function TGood.IsValid: Boolean;
begin
  // VerifyMode := [] in a comment
  Result := True;
end;

const
  Note = 'VerifyMode := []';

end.
