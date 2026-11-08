unit DragLint.Plugin.ConvertSelectionEditor;

/// <summary>C12 ask N7: the form designer's right-click entries for Convert Components.</summary>
/// <remarks>A selection editor registered for TComponent adds two verbs to the designer's
/// context menu of every component; each does exactly what the drag-lint > Convert
/// Components main-menu item of the same name does (same launch path, same refusals).
/// Blast radius: every component's context menu in every design session while this
/// package is loaded; the IDE appends selection-editor verbs after the component editor's
/// own. DesignIntf has no UnregisterSelectionEditor: the registration belongs to this
/// package's registration group, which the IDE drops when the package unloads, as for
/// every component / property / selection editor a design-time package registers.
/// Spec: docs\superpowers\specs\2026-10-06-c12-engine-asks.md, N7.</remarks>

interface

const
  /// <summary>Designer verb 0: the selected components, as a `selected` request.</summary>
  CONVERT_VERB_SELECTED = 'drag-lint: Convert Selected Component(s)...';
  /// <summary>Designer verb 1: every instance on the form of the selected components' types.</summary>
  CONVERT_VERB_ALL_OF_TYPE = 'drag-lint: Convert All of This Type on the Form...';

/// <summary>Registers the selection editor. Called once from the wizard's Register.</summary>
procedure RegisterConvertSelectionEditor;

implementation

uses
  System.Classes
  , DesignIntf
  , DesignEditors
  , DragLint.Plugin.ConvertLaunch
  ;

type
  /// <summary>Adds the two Convert Components verbs to the designer's context menu.</summary>
  TDragLintConvertSelectionEditor = class(TSelectionEditor)
  public
    /// <summary>Two verbs.</summary>
    /// <returns>2.</returns>
    function GetVerbCount: Integer; override;
    /// <summary>The caption of verb Index.</summary>
    /// <param name="Index">0 or 1.</param>
    /// <returns>CONVERT_VERB_SELECTED or CONVERT_VERB_ALL_OF_TYPE; '' otherwise.</returns>
    function GetVerb(Index: Integer): string; override;
    /// <summary>Runs the main-menu item of the same name.</summary>
    /// <param name="Index">0 or 1.</param>
    /// <param name="List">Unused: the launch reads the designer's selection itself, so the
    /// right-click and the main menu cannot disagree about it.</param>
    procedure ExecuteVerb(Index: Integer; const List: IDesignerSelections); override;
  end;

const
  VERB_SELECTED = 0;
  VERB_ALL_OF_TYPE = 1;
  VERB_COUNT = 2;

function TDragLintConvertSelectionEditor.GetVerbCount: Integer;
begin
  Result:= VERB_COUNT;
end;

function TDragLintConvertSelectionEditor.GetVerb(Index: Integer): string;
begin
  case Index of
    VERB_SELECTED   : Result:= CONVERT_VERB_SELECTED;
    VERB_ALL_OF_TYPE: Result:= CONVERT_VERB_ALL_OF_TYPE;
  else
    Result:= '';
  end;
end;

procedure TDragLintConvertSelectionEditor.ExecuteVerb(Index: Integer; const List: IDesignerSelections);
begin
  { DEFERRED: the hand-off saves and CLOSES the unit, and this runs inside the designer's
    own popup handler; closing the designer under its menu is not safe. ForceQueue runs
    it on the main thread once the menu has returned. }
  case Index of
    VERB_SELECTED   : TThread.ForceQueue(nil, procedure begin InvokeConvertSelectedComponents(nil); end);
    VERB_ALL_OF_TYPE: TThread.ForceQueue(nil, procedure begin InvokeConvertAllOfTypeOnForm(nil); end);
  end;
end;

procedure RegisterConvertSelectionEditor;
begin
  RegisterSelectionEditor(TComponent, TDragLintConvertSelectionEditor);
end;

end.
