unit DRagLint.FieldRepoEd.Grid;

{ drag-lint 1.52 -- lane TTD: the one place where the editor's grid control is chosen.

  Compiled with the conditional DL_DEVEX (the default shipped build, ruling A3) the grid is a
  DevExpress TcxGrid with a TcxGridDBTableView; without it the grid is a plain TDBGrid (the
  fallback for source builds that have no DevExpress). Everything else in the editor talks to
  this unit only, so the two builds differ by this unit's conditional and one define. }

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.DBGrids,
  Data.DB,
{$IFDEF DL_DEVEX}
  cxGridDBTableView,
{$ENDIF}
  System.SysUtils;

type
  /// <summary>One editable grid bound to a data source, built entirely in code.</summary>
  /// <remarks>Owned by the component passed to CreateRepoGrid; never freed by the caller.</remarks>
  TRepoGrid = class(TComponent)
  private
    FControl: TWinControl;
    FDataSource: TDataSource;
{$IFDEF DL_DEVEX}
    FView: TcxGridDBTableView;
{$ELSE}
    FGrid: TDBGrid;
{$ENDIF}
  public
    /// <summary>Number of columns the grid shows for the bound dataset.</summary>
    /// <returns>Column count; the dataset must be active so the columns exist.</returns>
    function ColumnCount: Integer;
    /// <summary>Number of data rows the grid sees.</summary>
    /// <returns>Record count of the bound dataset as the grid control reports it.</returns>
    function RowCount: Integer;
    /// <summary>The visible grid control (aligned client in its parent).</summary>
    property Control: TWinControl read FControl;
  end;

/// <summary>Creates a grid in pParent bound to pSource and creates its columns.</summary>
/// <param name="pOwner">Component that owns the grid wrapper and the control.</param>
/// <param name="pParent">Parent control; the grid is aligned alClient.</param>
/// <param name="pSource">Data source of an ACTIVE dataset (columns come from its fields).</param>
/// <returns>The grid wrapper, owned by pOwner.</returns>
function CreateRepoGrid(pOwner: TComponent; pParent: TWinControl;
  pSource: TDataSource): TRepoGrid;

/// <summary>Name of the grid control this build uses.</summary>
/// <returns>'DevExpress cxGrid' or 'TDBGrid'.</returns>
function RepoGridKind: string;

implementation

{$IFDEF DL_DEVEX}
uses
  cxGraphics, cxControls, cxLookAndFeels, cxLookAndFeelPainters, cxStyles, cxCustomData,
  cxFilter, cxData, cxDataStorage, cxEdit, cxNavigator, cxClasses, cxGridLevel,
  cxGridCustomTableView, cxGridTableView, cxGridCustomView, cxGrid;
{$ENDIF}

function RepoGridKind: string;
begin
{$IFDEF DL_DEVEX}
  Result := 'DevExpress cxGrid';
{$ELSE}
  Result := 'TDBGrid';
{$ENDIF}
end;

function TRepoGrid.ColumnCount: Integer;
begin
{$IFDEF DL_DEVEX}
  Result := FView.VisibleColumnCount;
{$ELSE}
  Result := FGrid.Columns.Count;
{$ENDIF}
end;

function TRepoGrid.RowCount: Integer;
begin
{$IFDEF DL_DEVEX}
  Result := FView.DataController.RecordCount;
{$ELSE}
  Result := FDataSource.DataSet.RecordCount;
{$ENDIF}
end;

function CreateRepoGrid(pOwner: TComponent; pParent: TWinControl;
  pSource: TDataSource): TRepoGrid;
{$IFDEF DL_DEVEX}
var
  Grid: TcxGrid;
  Level: TcxGridLevel;
{$ENDIF}
begin
  Result := TRepoGrid.Create(pOwner);
  Result.FDataSource := pSource;
{$IFDEF DL_DEVEX}
  Grid := TcxGrid.Create(Result);
  Grid.Parent := pParent;
  Grid.Align := alClient;
  Result.FView := Grid.CreateView(TcxGridDBTableView) as TcxGridDBTableView;
  Level := Grid.Levels.Add;
  Level.GridView := Result.FView;
  Result.FView.DataController.DataSource := pSource;
  Result.FView.DataController.CreateAllItems;
  Result.FView.OptionsData.Editing := True;
  Result.FView.OptionsData.Appending := True;
  Result.FView.OptionsData.Deleting := True;
  Result.FView.OptionsData.Inserting := True;
  Result.FView.OptionsView.ColumnAutoWidth := False;
  Result.FControl := Grid;
{$ELSE}
  Result.FGrid := TDBGrid.Create(Result);
  Result.FGrid.Parent := pParent;
  Result.FGrid.Align := alClient;
  Result.FGrid.DataSource := pSource;
  Result.FGrid.Options := Result.FGrid.Options + [dgEditing, dgTitles, dgColLines,
    dgRowLines, dgTabs, dgAlwaysShowSelection, dgConfirmDelete];
  Result.FGrid.Columns.RebuildColumns;
  Result.FControl := Result.FGrid;
{$ENDIF}
end;

end.
