unit LocaleFormatV151;

interface

implementation

uses Winapi.Windows, System.Classes, System.SysUtils;

procedure Bad(H: THandle; MyThread: TThread; Worker: TThread);
var
  S: string;
  D: Double;
  L: NativeInt;
begin
  L := GetWindowLong(H, GWL_STYLE);
  SetWindowLong(H, GWL_STYLE, L);
  L := GetClassLong(H, GCL_STYLE);
  MyThread.Resume;
  MyThread.Suspend;
  Worker.Resume;
  S := Format('%f', [D]);
  S := Format('%d items, %.2f', [1, D]);
  S := Format('%d', [1]);
  S := Format('%f', [D], FormatSettings);
  S := Format('%6.0f|%.0f', [D, D]);
  S := Format('%.2f%%', [D]);
  L := GetWindowLongPtr(H, GWL_STYLE);
end;

end.
