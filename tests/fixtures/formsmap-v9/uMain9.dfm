object frmMain9: TfrmMain9
  Left = 0
  Top = 0
  Caption = 'Demo Nine'
  ClientHeight = 400
  ClientWidth = 600
  OnCreate = FormCreate
  object dxBarManager1: TdxBarManager
    Categories.Strings = (
      'Default')
    Categories.ItemsVisibles = (
      2)
    PopupMenuLinks = <>
    Left = 40
    Top = 40
    DockControlHeights = (
      0
      0
      0
      0)
    object barMainMenu: TdxBar
      Caption = 'Main Menu'
      CaptionButtons = <>
      DockedLeft = 0
      IsMainMenu = True
      ItemLinks = <
        item
          Visible = True
          ItemName = 'subSetup'
        end>
      MultiLine = True
      Visible = True
    end
    object barLists: TdxBar
      Caption = 'Lists Bar'
      CaptionButtons = <>
      ItemLinks = <
        item
          Visible = True
          ItemName = 'btnCustomers'
        end
        item
          BeginGroup = True
          Visible = True
          ItemName = 'btnSuppliers'
        end>
      Visible = True
    end
    object barHome: TdxBar
      Caption = 'Main'
      CaptionButtons = <>
      ItemLinks = <
        item
          Visible = True
          ItemName = 'lblInfo'
        end
        item
          Visible = True
          ItemName = 'btnHome'
        end>
      Visible = True
    end
    object barQAT: TdxBar
      Caption = 'Quick Access Toolbar'
      CaptionButtons = <>
      ItemLinks = <
        item
          Visible = True
          ItemName = 'btnCustomers'
        end>
      Visible = True
    end
    object subSetup: TdxBarSubItem
      Caption = '&Setup'
      Category = 0
      Visible = ivAlways
      ItemLinks = <
        item
          Visible = True
          ItemName = 'btnGroups'
        end
        item
          BeginGroup = True
          Visible = True
          ItemName = 'btnUsers'
        end>
    end
    object btnGroups: TdxBarButton
      Action = actGroups
      Category = 0
    end
    object btnUsers: TdxBarButton
      Caption = 'Users'
      Category = 0
      Visible = ivAlways
      OnClick = btnUsersClick
    end
    object btnCustomers: TdxBarLargeButton
      Caption = 'Customer List'
      Category = 0
      Hint = 'Customer List'
      Visible = ivAlways
      OnClick = btnCustomersClick
    end
    object btnSuppliers: TdxBarButton
      Caption = 'Suppliers'
      Category = 0
      Visible = ivAlways
      OnClick = btnSuppliersClick
    end
    object btnHome: TdxBarButton
      Caption = 'Home Page'
      Category = 0
      Visible = ivAlways
      OnClick = btnHomeClick
    end
    object lblInfo: TdxBarStatic
      Caption = 'Info'
      Category = 0
      Visible = ivAlways
    end
    object btnOrphan: TdxBarButton
      Caption = 'Orphan'
      Category = 0
      Visible = ivAlways
      OnClick = btnOrphanClick
    end
    object btnOptions: TdxBarButton
      Caption = 'Options'
      Category = 0
      Visible = ivAlways
      OnClick = btnOptionsClick
    end
    object btnExit: TdxBarButton
      Caption = 'E&xit'
      Category = 0
      Visible = ivAlways
      OnClick = btnExitClick
    end
  end
  object ActionList1: TActionList
    Left = 80
    Top = 40
    object actGroups: TAction
      Caption = 'Groups'
      OnExecute = actGroupsExecute
    end
  end
  object dxRibbon1: TdxRibbon
    Left = 0
    Top = 0
    Width = 600
    Height = 120
    BarManager = dxBarManager1
    ApplicationButton.Menu = dxRibbonBackstageView1
    QuickAccessToolbar.Toolbar = barQAT
    Contexts = <>
    TabOrder = 0
    TabStop = False
    object tabHome: TdxRibbonTab
      Active = True
      Caption = 'Main'
      Groups = <
        item
          ToolbarName = 'barHome'
        end>
      Index = 0
    end
    object tabLists: TdxRibbonTab
      Caption = 'Lists'
      Groups = <
        item
          ToolbarName = 'barLists'
        end>
      Index = 1
    end
  end
  object popGrid: TdxBarPopupMenu
    BarManager = dxBarManager1
    ItemLinks = <
      item
        Visible = True
        ItemName = 'btnCustomers'
      end>
    UseOwnFont = False
    Left = 120
    Top = 40
  end
  object dxRibbonBackstageView1: TdxRibbonBackstageView
    Left = 0
    Top = 150
    Width = 300
    Height = 200
    Buttons = <
      item
        Item = btnOptions
      end
      item
        Item = btnExit
      end>
    Ribbon = dxRibbon1
  end
end
