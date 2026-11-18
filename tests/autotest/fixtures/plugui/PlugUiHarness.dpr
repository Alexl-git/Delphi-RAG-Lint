program PlugUiHarness;
{ Lane PLUGUI (1.52) headless checks. Built by run_v152_PLUGUI.ps1 against a
  private->public copy of DragLint.Plugin.LintOptionsFrame and a stub ToolsAPI.
  Args: <rules-sample.json>. Exit 0 = all pass, 1 = any failure. }
{$APPTYPE CONSOLE}
uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils,
  Vcl.Graphics, Vcl.Forms, Vcl.Controls,
  DRagLint.Hover.Contrast,
  DragLint.Plugin.PlugUiCore,
  DragLint.Plugin.LintOptionsFrame;

var
  Failed: Integer = 0;
  F     : TLintOptionsFrame;
  Json  : string;

procedure Check(const AName: string; AOk: Boolean; const ADetail: string = '');
begin
  if AOk then Writeln('  [PASS] ', AName)
  else
  begin
    Writeln('  [FAIL] ', AName, ' ', ADetail);
    Inc(Failed);
  end;
end;

procedure PumpFor(AMs: Cardinal);
var
  T0: UInt64;
begin
  T0:= GetTickCount64;
  while GetTickCount64 - T0 < AMs do
  begin
    Application.ProcessMessages;
    Sleep(5);
  end;
end;

function Luma(AColor: TColor): Integer;
var
  C: Longint;
begin
  C:= ColorToRGB(AColor);
  Result:= (GetRValue(C) * 299 + GetGValue(C) * 587 + GetBValue(C) * 114) div 1000;
end;

function DarkMap(AColor: TColor): TColor;
begin
  case AColor of
    clWindow       : Result:= TColor($00202020);
    clWindowText   : Result:= TColor($00E8E8E8);
    clHighlight    : Result:= TColor($00804000);
    clHighlightText: Result:= TColor($00FFFFFF);
  else Result:= AColor;
  end;
end;

function LightMap(AColor: TColor): TColor;
begin
  Result:= ColorToRGB(AColor);
end;

procedure TestColors;
var
  B, T, M: TColor;
begin
  Writeln('== Find Usages row colours (N3) ==');
  UsageRowColors(False, DarkMap, B, T, M);
  Check('dark: background is dark', Luma(B) < 64, 'luma=' + IntToStr(Luma(B)));
  Check('dark: text is light', Luma(T) > 192, 'luma=' + IntToStr(Luma(T)));
  Check('dark: match readable on background', ContrastRatio(M, B) >= 3.0, Format('%.2f', [ContrastRatio(M, B)]));
  UsageRowColors(True, DarkMap, B, T, M);
  Check('dark selected: uses themed highlight', (B = DarkMap(clHighlight)) and (T = DarkMap(clHighlightText)));
  UsageRowColors(False, LightMap, B, T, M);
  Check('light: background light, text dark', (Luma(B) > 192) and (Luma(T) < 64));
  Check('light: match readable on background', ContrastRatio(M, B) >= 3.0, Format('%.2f', [ContrastRatio(M, B)]));
end;

procedure TestRefillRule;
begin
  Writeln('== search refill rule (N2) ==');
  Check('changed text refills', SearchRefillNeeded('abc', 'abcd', True));
  Check('trailing space does not refill', not SearchRefillNeeded('abc', 'abc ', True));
  Check('no data never refills', not SearchRefillNeeded('', 'x', False));
  Check('clear refills', SearchRefillNeeded('abc', '', True));
end;

procedure TestDebounce;
var
  N: Integer;
begin
  Writeln('== search debounce, clear button, wait cursor (N2) ==');
  F.ShowCatalog(0, Json);
  PumpFor(100);
  N:= F.FRenderCount;
  F.FEdtSearch.Text:= 'a';
  F.FEdtSearch.Text:= 'ab';
  F.FEdtSearch.Text:= 'abc';
  PumpFor(100);
  Check('no refill while still inside the debounce window', F.FRenderCount = N, 'renders=' + IntToStr(F.FRenderCount - N));
  PumpFor(SEARCH_DEBOUNCE_MS + 250);
  Check('exactly one refill after the burst', F.FRenderCount = N + 1, 'renders=' + IntToStr(F.FRenderCount - N));
  Check('wait cursor shown during the refill', F.FCursorInRender = crHourGlass);
  Check('cursor restored afterwards', Screen.Cursor = crDefault);
  Check('clear button visible with text', F.FBtnSearchClear.Visible);
  Check('applied filter is the typed text', F.FSearch = 'abc');

  N:= F.FRenderCount;
  F.FEdtSearch.Text:= 'abc ';
  PumpFor(SEARCH_DEBOUNCE_MS + 250);
  Check('trailing space triggers no refill', F.FRenderCount = N, 'renders=' + IntToStr(F.FRenderCount - N));

  F.FBtnSearchClear.Click;
  Check('clear button empties the box at once', F.FEdtSearch.Text = '');
  Check('clear button hides itself', not F.FBtnSearchClear.Visible);
  PumpFor(100);
  Check('clear is debounced too (no refill yet)', F.FRenderCount = N, 'renders=' + IntToStr(F.FRenderCount - N));
  PumpFor(SEARCH_DEBOUNCE_MS + 250);
  Check('clear refills once, showing all rules', (F.FRenderCount = N + 1) and (F.FSearch = ''), 'renders=' + IntToStr(F.FRenderCount - N));
end;

procedure TestClearSpeed;
var
  T0, T1, Fq: Int64;
  Ms: Double;
begin
  Writeln('== clear speed (reported, not asserted) ==');
  QueryPerformanceFrequency(Fq);
  F.FSearch:= 'naming';
  F.RenderCatalog(Json);
  F.FSearch:= '';
  QueryPerformanceCounter(T0);
  F.RenderCatalog(Json);
  F.Update;
  Application.ProcessMessages;
  QueryPerformanceCounter(T1);
  Ms:= (T1 - T0) * 1000.0 / Fq;
  Writeln(Format('  CLEAR_MS=%.0f', [Ms]));
end;

begin
  Application.Initialize;
  Json:= TFile.ReadAllText(ParamStr(1));
  F:= TLintOptionsFrame.Create(nil);
  try
    F.Width:= 1000;
    F.Height:= 800;
    F.Show;
    Application.ProcessMessages;
    TestColors;
    TestRefillRule;
    TestDebounce;
    TestClearSpeed;
  finally
    F.FDirty:= False;
    F.Free;
  end;
  if Failed > 0 then
  begin
    Writeln('FAILED: ', Failed);
    Halt(1);
  end;
  Writeln('ALL PASS');
end.
