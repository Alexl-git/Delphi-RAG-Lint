unit ConvRules.MembersPanel;

{ A4 #migrate slice 1: the Members list under the #link grid (spec section 5, owner
  ruling D1 = A, D4 = A). Shows the '#migrate' lines of the active #convert block --
  Old | New | Kind | Note -- with Add... / Edit... / Delete. A code-built panel, no .dfm;
  every cell comes from ConvRules.Migrate.MembersRowText and every edit is done by the host
  through the three callbacks. Editor-only: NOT in the tests' compile closure. }

interface

uses
  System.Classes
  , System.SysUtils
  , Vcl.Controls
  , Vcl.StdCtrls
  , Vcl.ComCtrls
  , Vcl.ExtCtrls
  , ConvRules.Model
  ;

type
  /// <summary>The Members list: the active block's '#migrate' lines.</summary>
  /// <remarks>Controls carry stable names for the GUI driver: LblMembers, LvMembers,
  /// BtnMemberAdd, BtnMemberEdit, BtnMemberDelete. The list is shown whatever the engine (the
  /// lines are book content); Add / Edit are enabled only when the engine applies member
  /// migrations (SetEngineOk), Delete always. Item.Data is the borrowed node.</remarks>
  TMembersPanel = class(TPanel)
  private
    FLabel    : TLabel;
    FList     : TListView;
    FBtnAdd   : TButton;
    FBtnEdit  : TButton;
    FBtnDelete: TButton;
    FEngineOk : Boolean;
    FOnAdd    : TProc;
    FOnEdit   : TProc<TRuleNode>;
    FOnDelete : TProc<TRuleNode>;
    procedure AddColumn(const ACaption: string; AWidth: Integer);
    function NewButton(AParent: TWinControl; const AName, ACaption: string): TButton;
    function SelectedNode: TRuleNode;
    procedure UpdateButtons;
    procedure ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure AddClick(Sender: TObject);
    procedure EditClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
  public
    /// <summary>Builds the panel, empty.</summary>
    /// <param name="AOwner">The owner (the main form).</param>
    /// <param name="AOnAdd">Runs the Migrate dialog with an empty Old for the active block.</param>
    /// <param name="AOnEdit">Runs it for the node (Old fixed, New editable).</param>
    /// <param name="AOnDelete">Removes the node from the book.</param>
    constructor Create(AOwner: TComponent; const AOnAdd: TProc; const AOnEdit, AOnDelete: TProc<TRuleNode>); reintroduce;
    /// <summary>Says whether the run's engine applies member migrations (migrate_members).</summary>
    /// <param name="AOk">False: Add / Edit disabled and the caption says why.</param>
    procedure SetEngineOk(AOk: Boolean);
    /// <summary>Shows the '#migrate' lines of the block.</summary>
    /// <param name="ABook">The book, or nil for no block.</param>
    /// <param name="AHeaderIdx">The active header's index; -1 = no block.</param>
    procedure ShowBlock(ABook: TRuleBook; AHeaderIdx: Integer);
  end;

implementation

uses
  ConvRules.MigrateRules
  , ConvRules.Migrate
  ;

const
  BTN_W        = 80;
  BTN_COL_W    = 92;
  COL_OLD_W    = 160;
  COL_NEW_W    = 160;
  COL_KIND_W   = 70;
  COL_NOTE_W   = 420;
  CAPTION_OK   = 'Member migrations (#migrate) of this block';
  CAPTION_OFF  = 'member migrations -- not applied by this engine (needs migrate_members)';

constructor TMembersPanel.Create(AOwner: TComponent; const AOnAdd: TProc; const AOnEdit, AOnDelete: TProc<TRuleNode>);
var
  LButtons: TPanel;
begin
  inherited Create(AOwner);
  BevelOuter:= bvNone;
  Caption   := '';
  FOnAdd    := AOnAdd;
  FOnEdit   := AOnEdit;
  FOnDelete := AOnDelete;

  FLabel:= TLabel.Create(Self);
  FLabel.Parent          := Self;
  FLabel.Name            := 'LblMembers';
  FLabel.Align           := alTop;
  FLabel.AlignWithMargins:= True;
  FLabel.Caption         := CAPTION_OK;

  LButtons:= TPanel.Create(Self);
  LButtons.Parent    := Self;
  LButtons.Align     := alRight;
  LButtons.Width     := BTN_COL_W;
  LButtons.BevelOuter:= bvNone;
  FBtnAdd   := NewButton(LButtons, 'BtnMemberAdd', 'Add...');
  FBtnAdd.OnClick:= AddClick;
  FBtnEdit  := NewButton(LButtons, 'BtnMemberEdit', 'Edit...');
  FBtnEdit.OnClick:= EditClick;
  FBtnDelete:= NewButton(LButtons, 'BtnMemberDelete', 'Delete');
  FBtnDelete.OnClick:= DeleteClick;

  FList:= TListView.Create(Self);
  FList.Parent          := Self;
  FList.Name            := 'LvMembers';
  FList.Align           := alClient;
  FList.AlignWithMargins:= True;
  FList.ViewStyle       := vsReport;
  FList.ReadOnly        := True;
  FList.RowSelect       := True;
  FList.HideSelection   := False;
  FList.OnSelectItem    := ListSelect;
  FList.OnDblClick      := EditClick;
  AddColumn('Old', COL_OLD_W);
  AddColumn('New', COL_NEW_W);
  AddColumn('Kind', COL_KIND_W);
  AddColumn('Note', COL_NOTE_W);
  FEngineOk:= True;
  UpdateButtons;
end;

procedure TMembersPanel.AddColumn(const ACaption: string; AWidth: Integer);
var
  LCol: TListColumn;
begin
  LCol:= FList.Columns.Add;
  LCol.Caption:= ACaption;
  LCol.Width  := AWidth;
end;

function TMembersPanel.NewButton(AParent: TWinControl; const AName, ACaption: string): TButton;
begin
  Result:= TButton.Create(Self);
  Result.Parent          := AParent;
  Result.Name            := AName;
  Result.Caption         := ACaption;
  Result.Align           := alTop;
  Result.AlignWithMargins:= True;
  Result.Width           := BTN_W;
  Result.Top             := High(Word); // below the buttons made before it
end;

procedure TMembersPanel.SetEngineOk(AOk: Boolean);
begin
  FEngineOk:= AOk;
  FLabel.Caption:= if AOk then CAPTION_OK else CAPTION_OFF;
  UpdateButtons;
end;

procedure TMembersPanel.ShowBlock(ABook: TRuleBook; AHeaderIdx: Integer);
var
  LCells: TArray<string>;
  LItem : TListItem;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    if (ABook <> nil) and (AHeaderIdx >= 0) then
      for var LNode: TRuleNode in MigratesForBlock(ABook, AHeaderIdx) do
      begin
        LCells:= MembersRowText(LNode);
        LItem:= FList.Items.Add;
        LItem.Caption:= LCells[0];
        for var I: Integer:= 1 to High(LCells) do
          LItem.SubItems.Add(LCells[I]);
        LItem.Data:= LNode;
      end;
  finally
    FList.Items.EndUpdate;
  end; // try
  FBtnAdd.Tag:= Ord((ABook <> nil) and (AHeaderIdx >= 0)); // Add needs a block
  UpdateButtons;
end;

function TMembersPanel.SelectedNode: TRuleNode;
begin
  Result:= if FList.Selected <> nil then TRuleNode(FList.Selected.Data) else nil;
end;

procedure TMembersPanel.UpdateButtons;
begin
  FBtnAdd.Enabled   := FEngineOk and (FBtnAdd.Tag <> 0);
  FBtnEdit.Enabled  := FEngineOk and (SelectedNode <> nil);
  FBtnDelete.Enabled:= SelectedNode <> nil;
end;

procedure TMembersPanel.ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateButtons;
end;

procedure TMembersPanel.AddClick(Sender: TObject);
begin
  if FBtnAdd.Enabled and Assigned(FOnAdd) then
    FOnAdd();
end;

procedure TMembersPanel.EditClick(Sender: TObject);
begin
  if FBtnEdit.Enabled and Assigned(FOnEdit) and (SelectedNode <> nil) then
    FOnEdit(SelectedNode);
end;

procedure TMembersPanel.DeleteClick(Sender: TObject);
begin
  if Assigned(FOnDelete) and (SelectedNode <> nil) then
    FOnDelete(SelectedNode);
end;

end.
