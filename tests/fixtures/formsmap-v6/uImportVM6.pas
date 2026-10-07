unit uImportVM6;

interface

type
  IImportVM6 = interface
    ['{6A1F0C3E-2B7D-4E51-9C1A-5D3B8E0F6A21}']
    procedure OpenImport;
  end;

  TImportVM6 = class(TInterfacedObject, IImportVM6)
  private
    FReady: Boolean;
  public
    procedure OpenImport;
  end;

implementation

uses
  Vcl.Dialogs, uImport6;

procedure TImportVM6.OpenImport;
var
  F: TfrmImport6;
begin
  if not FReady then begin ShowMessage('Connect to a source first'); Exit; end;
  F := TfrmImport6.Create(nil);
  try
    F.Caption := 'Import';
    F.ShowModal;
  finally
    F.Free;
  end;
end;

end.
