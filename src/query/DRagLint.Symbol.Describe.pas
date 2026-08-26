unit DRagLint.Symbol.Describe;

{ What a TYPE says about itself in one line: a class or interface's ancestors, a
  helper's target, an enum's members.

  WHY THIS UNIT EXISTS -- it is the fix for a defect, not a tidy-up. The
  completion popup learned to describe a type on 2026-08-19, and the logic went
  where it was needed: inside MakeCompletionItem. On 2026-08-24 the owner
  hovered an enum in a live IDE and got `enum FileLockInfo.TRmAppType` with no
  members, while Ctrl-Space on the same type listed them correctly. One fact,
  two surfaces, one of them served.

  DRagLint.Query.HoverModel had already written down the rule that was broken:

      Copying it would have created a second definition of what a hover says
      about a symbol, and the two would have drifted the first time either was
      touched -- so it moved here, and BOTH surfaces now call it.

  So the answer is not to add the same case statement to the hover. It is one
  describer, called by the completion item builder and by the hover assembly,
  with a guard that asserts both surfaces report the SAME strings.

  WHY THIS IS NOT AN EXTRACTOR CHANGE, which matters because the alternative
  costs about five hours. Everything here is already indexed: `heritage` has
  carried the ancestor list since v11, `is_helper` since v15, and an enum's
  members are already child symbols of the enum. Writing any of it into
  `signature` at parse time would duplicate stored data AND move
  DRAGLINT_EXTRACTOR_VERSION, re-parsing every database on the box to say
  something it already knew. This reads what is there. }

interface

uses
  DRagLint.Core.Model     ,
  DRagLint.Core.Interfaces;

/// <summary>One line describing a TYPE symbol -- ancestors, helper target, or
/// enum members -- for the slot the completion popup and the hover both render
/// after the symbol name.</summary>
/// <param name="ASym">The symbol to describe. Non-type kinds yield ''.</param>
/// <param name="AStore">Used only to read an enum's member symbols; may be nil,
/// in which case an enum yields ''.</param>
/// <returns>'TBase', 'TBar, IBaz', 'helper for TColor', 'sIdle, sBusy, sDone',
/// or '' when the symbol declares nothing worth saying.</returns>
/// <remarks>
/// NOTHING IS INVENTED. A bare `TBase = class` declares no ancestor and
/// yields '' rather than 'TObject': both surfaces draw this string after a
/// colon, so a guessed value would be indistinguishable from an indexed one.
/// Callers apply it only when the symbol's own Signature is empty.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.LSP.Completion.TLspCompletion.MakeCompletionItem (DRagLint.LSP.Completion.pas), DRagLint.Query.HoverModel.AssembleHover (DRagLint.Query.HoverModel.pas)</para>
/// <para>Calls: DRagLint.Symbol.Describe.EnumMembersPreview</para>
/// <para>Returns: ''; 'helper for ' + ASym.Heritage; ASym.Heritage; EnumMembersPreview(ASym, AStore)</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Symbol.Describe.EnumMembersPreview"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DescribeTypeKind(const ASym: TSymbol; const AStore: ISymbolStore): string;

implementation

uses
  System.SysUtils,
  System.Classes ;

{ A preview, not an enumeration -- a 40-value enum would push everything else
  off the row, and the declaration is one Ctrl-click away. }
const
  MAX_ENUM_MEMBERS = 6;

function EnumMembersPreview(const ASym: TSymbol; const AStore: ISymbolStore): string;
var
  Kids : TArray<TSymbol>;
  Parts: TStringList    ;
  i    : Integer        ;
  Shown: Integer        ;
begin
  Result:= '';
  if not Assigned(AStore) then Exit;
  Kids:= AStore.FindAllChildSymbols(ASym.Id);
  if Length(Kids) = 0 then Exit;
  Parts:= TStringList.Create;
  try
    Shown:= 0;
    for i:= 0 to High(Kids) do
    begin
      if Kids[i].Kind <> skEnumValue then Continue;
      if Shown >= MAX_ENUM_MEMBERS then
      begin
        Parts.Add('...');
        Break;
      end;
      Parts.Add(Kids[i].Name);
      Inc(Shown);
    end;
    if Shown > 0 then Result:= String.Join(', ', Parts.ToStringArray);
  finally
    Parts.Free;
  end;
end;

function DescribeTypeKind(const ASym: TSymbol; const AStore: ISymbolStore): string;
begin
  Result:= '';
  case ASym.Kind of
    skClass, skRecord, skInterface:
      { A helper's Heritage is its TARGET, not an ancestor (the parser sets
        IsHelper for a declHelper node). Rendering it bare would read as
        `class TColorHelper: TColor`, i.e. as if it descended from TColor. }
      if ASym.IsHelper then
      begin
        if ASym.Heritage <> '' then Result:= 'helper for ' + ASym.Heritage;
      end
      else Result:= ASym.Heritage;
    skEnum:
      Result:= EnumMembersPreview(ASym, AStore);
  end;
end;

end.
