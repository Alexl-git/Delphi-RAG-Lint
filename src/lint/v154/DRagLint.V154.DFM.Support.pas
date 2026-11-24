unit DRagLint.V154.DFM.Support;

{ Wave v154 lane DFM -- helpers of DRagLint.V154.DFM (private to the lane).
  Pure functions over the form-file object tree of DRagLint.V151.DFMB.Support (TDfmModel / TDfmObj,
  raw property values with line numbers): caption and shortcut decoding, class-name tests, source-text
  tests. No file access except ReadSource; nothing here knows a rule id. }

interface

uses
  System.SysUtils
  , DRagLint.V151.DFMB.Support
  ;

/// <summary>Decodes a form-file string value (quoted pieces, #nnn / #$hhhh characters, + joins) to text.</summary>
/// <param name="AValue">Raw property value as the form file spells it.</param>
/// <returns>The text; '' when the value is not a string literal (a list, a number, an identifier).</returns>
function DecodeDfmString(const AValue: string): string;

/// <summary>The accelerator letter of a caption: the character after the first single '&amp;' (a '&amp;&amp;' is a literal '&amp;').</summary>
/// <param name="ACaption">Decoded caption.</param>
/// <returns>The upper-case letter or digit; #0 when the caption has none.</returns>
function AcceleratorOf(const ACaption: string): Char;

/// <summary>The class name without a unit qualifier.</summary>
/// <param name="AClass">Class as the form file spells it.</param>
/// <returns>The last dotted segment.</returns>
function ClassLeaf(const AClass: string): string;

/// <summary>True when the class has accelerator-bearing captions (button, check box, radio, label, group box, tab sheet, menu item).</summary>
/// <param name="AClass">Class name.</param>
/// <returns>True for a class that renders an '&amp;' as an underlined key.</returns>
function IsAcceleratorClass(const AClass: string): Boolean;

/// <summary>True when the class is a database access component that belongs on a data module (connection, query, table, stored procedure, command, update object, transaction).</summary>
/// <param name="AClass">Class name.</param>
/// <returns>False for data sources, in-memory tables and data-aware controls.</returns>
function IsDbAccessClass(const AClass: string): Boolean;

/// <summary>True when the object is the designer's default name for its class: the class name without its 'T' plus a number.</summary>
/// <param name="AObj">Form-file object.</param>
/// <returns>True for Button1 of TButton, cxButton3 of TcxButton, FDQuery2 of TFDQuery.</returns>
function HasDefaultName(const AObj: TDfmObj): Boolean;

/// <summary>True when the object has the property and it is the identifier False / True.</summary>
/// <param name="AObj">Form-file object.</param>
/// <param name="AName">Property name.</param>
/// <param name="AValue">The boolean to compare with.</param>
/// <returns>True when the property is stored with that value.</returns>
function BoolPropIs(const AObj: TDfmObj; const AName: string; AValue: Boolean): Boolean;

/// <summary>True when the hint of the control can never show: an ancestor-or-self with ParentShowHint = False has no ShowHint = True.</summary>
/// <param name="AObj">Form-file object that stores a Hint.</param>
/// <returns>True when ShowHint is effectively False; False when it is on or depends on Application.ShowHint.</returns>
function HintIsInactive(const AObj: TDfmObj): Boolean;

/// <summary>Spells a stored shortcut number the way the IDE shows it.</summary>
/// <param name="AShortCut">Value of a ShortCut property (Ctrl = 16384, Shift = 8192, Alt = 32768, plus the key code).</param>
/// <returns>For example Ctrl+S or Shift+F5; the number itself for a key this helper does not name.</returns>
function ShortCutName(AShortCut: Integer): string;

/// <summary>Reads a unit source as text (any 8-bit encoding; the rules only look at identifiers).</summary>
/// <param name="APath">The .pas path.</param>
/// <returns>The text; '' when the file is missing or unreadable.</returns>
function ReadSource(const APath: string): string;

/// <summary>Number of whole-word, case-insensitive occurrences of a name in the source outside comment-only lines, not counting its own field declaration line.</summary>
/// <param name="ASource">Unit source.</param>
/// <param name="AName">Component name.</param>
/// <returns>Count of uses.</returns>
function CountCodeUses(const ASource, AName: string): Integer;

/// <summary>True when the source writes the ShowHint property or installs a hint handler.</summary>
/// <param name="ASource">Unit source.</param>
/// <returns>True for `ShowHint :=`, OnShowHint, OnHint.</returns>
function SourceControlsHints(const ASource: string): Boolean;

/// <summary>The body text of the implementation of a form method (`procedure TFoo.Name(...)`).</summary>
/// <param name="ASource">Unit source.</param>
/// <param name="AMethod">Method name without the class.</param>
/// <returns>The text between the method header and its `end;` at column 1; '' when not found.</returns>
function MethodBody(const ASource, AMethod: string): string;

implementation

uses
  System.StrUtils
  , System.Character
  , System.Math
  , System.IOUtils
  , System.RegularExpressions
  ;

const
  AMPERSAND    = '&';
  DEFAULT_NAME_NUM = '^\d+$';

function DecodeDfmString(const AValue: string): string;
begin
  Result:= '';
  var S: string:= Trim(AValue);
  var I: Integer:= 1;
  var Seen: Boolean:= False;
  while I <= Length(S) do
  begin
    var C: Char:= S[I];
    if C = '''' then
    begin
      Seen:= True;
      Inc(I);
      while I <= Length(S) do
      begin
        if S[I] <> '''' then Result:= Result + S[I]  // dl:ok concat-in-loop@d90d -- REVIEWED 2026-11-24 INT-W2: one caption literal, tens of characters
        else if (I < Length(S)) and (S[I + 1] = '''') then
        begin
          Result:= Result + '''';  // dl:ok concat-in-loop@5cd2 -- REVIEWED 2026-11-24 INT-W2: one caption literal, tens of characters
          Inc(I);
        end
        else Break;
        Inc(I);
      end;
      Inc(I);
    end
    else if C = '#' then
    begin
      Seen:= True;
      Inc(I);
      var Hex: Boolean:= (I <= Length(S)) and (S[I] = '$');
      if Hex then Inc(I);
      var Start: Integer:= I;
      while (I <= Length(S)) and (CharInSet(S[I], ['0'..'9']) or (Hex and CharInSet(S[I], ['a'..'f', 'A'..'F']))) do Inc(I);
      var Code: Integer:= StrToIntDef(IfThen(Hex, '$', '') + Copy(S, Start, I - Start), -1);
      if Code >= 0 then Result:= Result + Char(Code);  // dl:ok concat-in-loop@2523 -- REVIEWED 2026-11-24 INT-W2: one caption literal, tens of characters
    end
    else if CharInSet(C, [' ', '+', #10, #13, #9]) then Inc(I)
    else Exit('');  { an identifier or a number: not a literal }
  end;
  if not Seen then Result:= '';
end;

function AcceleratorOf(const ACaption: string): Char;
begin
  Result:= #0;
  var I: Integer:= 1;
  while I < Length(ACaption) do
  begin
    if ACaption[I] = AMPERSAND then
    begin
      if ACaption[I + 1] = AMPERSAND then Inc(I, 2)
      else
      begin
        var K: Char:= UpCase(ACaption[I + 1]);
        if K.IsLetterOrDigit then Exit(K);
        Exit(#0);
      end;
    end
    else Inc(I);
  end;
end;

function ClassLeaf(const AClass: string): string;
begin
  Result:= Copy(AClass, LastDelimiter('.', AClass) + 1, MaxInt);
end;

function IsAcceleratorClass(const AClass: string): Boolean;
begin
  var C: string:= ClassLeaf(AClass);
  Result:= False;
  for var Part in ['Button', 'CheckBox', 'RadioButton', 'Label', 'GroupBox', 'RadioGroup', 'TabSheet', 'MenuItem'] do
    if ContainsText(C, Part) then Exit(True);
end;

{ True for classes whose Active = True can be legitimate stored data: in-memory table, client dataset, buffered dataset. }
function IsStoredDataClass(const AClass: string): Boolean;
begin
  var C: string:= ClassLeaf(AClass);
  Result:= ContainsText(C, 'MemTable') or ContainsText(C, 'ClientDataSet') or ContainsText(C, 'BufDataset')
    or ContainsText(C, 'MemData') or ContainsText(C, 'VirtualTable');
end;

function IsDbAccessClass(const AClass: string): Boolean;
begin
  var C: string:= ClassLeaf(AClass);
  Result:= False;
  if IsStoredDataClass(C) or StartsText('Tcx', C) or StartsText('Tdx', C) or ContainsText(C, 'DataSource') then Exit;
  for var Part in ['Connection', 'Query', 'StoredProc', 'UpdateSQL', 'Transaction', 'Command', 'SQLTable'] do
    if ContainsText(C, Part) then Exit(True);
  Result:= MatchText(C, ['TFDTable', 'TADOTable', 'TIBTable', 'TTable', 'TDatabase', 'TIBDatabase', 'TIBSQL', 'TUniTable', 'TSQLTable']);
end;

function HasDefaultName(const AObj: TDfmObj): Boolean;
begin
  Result:= False;
  var C: string:= ClassLeaf(AObj.ClsName);
  if (Length(C) < 2) or (C[1] <> 'T') then Exit;
  var Base: string:= Copy(C, 2, MaxInt);
  var N: string:= AObj.ObjName;
  Result:= (Length(N) > Length(Base)) and SameText(Copy(N, 1, Length(Base)), Base)
    and TRegEx.IsMatch(Copy(N, Length(Base) + 1, MaxInt), DEFAULT_NAME_NUM);
end;

function BoolPropIs(const AObj: TDfmObj; const AName: string; AValue: Boolean): Boolean;
begin
  Result:= AObj.Has(AName) and SameText(Trim(AObj.Val(AName)), IfThen(AValue, 'True', 'False'));
end;

function HintIsInactive(const AObj: TDfmObj): Boolean;
begin
  Result:= False;
  var O: TDfmObj:= AObj;
  while O <> nil do
  begin
    if BoolPropIs(O, 'ParentShowHint', False) then Exit(not BoolPropIs(O, 'ShowHint', True));
    O:= O.Parent;
  end;
end;

function ShortCutName(AShortCut: Integer): string;
const
  FLAG_CTRL = 16384;
  FLAG_SHIFT = 8192;
  FLAG_ALT = 32768;
  KEY_MASK = 4095;
  KEY_F1 = 112;
  KEY_F12 = 123;
begin
  Result:= '';
  if AShortCut and FLAG_CTRL <> 0 then Result:= Result + 'Ctrl+';
  if AShortCut and FLAG_SHIFT <> 0 then Result:= Result + 'Shift+';
  if AShortCut and FLAG_ALT <> 0 then Result:= Result + 'Alt+';
  var Key: Integer:= AShortCut and KEY_MASK;
  if CharInSet(Char(Key), ['0'..'9', 'A'..'Z']) then Result:= Result + Char(Key)
  else if InRange(Key, KEY_F1, KEY_F12) then Result:= Result + 'F' + IntToStr(Key - KEY_F1 + 1)
  else Result:= Result + 'key ' + IntToStr(Key);
end;

function ReadSource(const APath: string): string;
begin
  Result:= '';
  if (APath = '') or not TFile.Exists(APath) then Exit;
  try
    Result:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(APath));
  except  // dl:ok bare-except@86a2 -- REVIEWED 2026-11-24 v154 DFM: an unreadable source keeps the code-dependent rules silent; no finding beats a false finding
    Result:= '';
  end;
end;

function CountCodeUses(const ASource, AName: string): Integer;
begin
  Result:= 0;
  var Word: TRegEx:= TRegEx.Create('\b' + TRegEx.Escape(AName) + '\b', [roIgnoreCase]);
  var Decl: TRegEx:= TRegEx.Create('^\s*' + TRegEx.Escape(AName) + '\s*:\s*[A-Za-z_][\w.]*\s*;', [roIgnoreCase]);
  for var Line in ASource.Split([#10]) do
  begin
    var T: string:= Trim(Line);
    if (T = '') or StartsStr('//', T) or Decl.IsMatch(T) then Continue;
    Inc(Result, Word.Matches(T).Count);
  end;
end;

function SourceControlsHints(const ASource: string): Boolean;
begin
  Result:= TRegEx.IsMatch(ASource, '\bShowHint\s*:=|\bOnShowHint\b|\bOnHint\b', [roIgnoreCase]);
end;

function MethodBody(const ASource, AMethod: string): string;
begin
  Result:= '';
  var M: TMatch:= TRegEx.Match(ASource, '(?:procedure|function)\s+\w+\.' + TRegEx.Escape(AMethod) + '\b[^;]*;', [roIgnoreCase]);
  if not M.Success then Exit;
  var Start: Integer:= M.Index + M.Length;
  var Stop: TMatch:= TRegEx.Match(Copy(ASource, Start, MaxInt), '^end;', [roMultiLine, roIgnoreCase]);
  Result:= if Stop.Success then Copy(ASource, Start, Stop.Index - 1) else Copy(ASource, Start, MaxInt);
end;

end.
