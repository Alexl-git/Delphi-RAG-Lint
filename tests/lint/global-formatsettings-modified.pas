unit global_formatsettings_modified;

interface

implementation

uses
  System.SysUtils;

type
  TExport = class
  private
    FDecimalSeparator: Char;
  public
    procedure Schreiben;
    procedure Lokal;
  end;

procedure TExport.Schreiben;
begin
  FormatSettings.DecimalSeparator := '.';
  FormatSettings.ShortDateFormat := 'yyyy-mm-dd';
end;

procedure TExport.Lokal;
var
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Create;
  FS.DecimalSeparator := '.';
  FDecimalSeparator := FS.DecimalSeparator;
end;

procedure Global;
begin
  DecimalSeparator := ',';
end;

end.
