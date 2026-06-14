unit XTree;

interface

uses
  Winapi.Windows, System.Classes, Winapi.Messages, XScrollView, XCGUI, XWidget;

type
  TXTree = class(TXSView)
  protected
    procedure CreateHandle(x, y, cx, cy: Integer; hParent: TXWidget); override;
  public
    destructor Destroy; override;
    class function CreateEx(x, y, cx, cy: Integer; hParent: TXWidget): TXTree;

    procedure EnableDragItem(bEnable: BOOL);
    procedure EnableConnectLine(bEnable, bSolid: BOOL);
    procedure EnableExpand(bEnable: BOOL);
    procedure EnableTemplateReuse(bEnable: BOOL);
    procedure SetConnectLineColor(color: Integer);
    procedure SetSplitLineColor(color: Integer);
    procedure SetExpandButtonSize(nWidth, nHeight: Integer);
    procedure SetConnectLineLength(nLength: Integer);
    procedure SetDragInsertPositionColor(color: Integer);
    procedure SetDrawItemBkFlags(nFlags: Integer);

    function SetItemTemplateXML(pXmlFile: PWideChar): BOOL;
    function SetItemTemplateXMLFromMem(data: Pointer; length: Integer): BOOL;
    function SetItemTemplateXMLFromZipRes(id: Integer; pFileName, pPassword: PWideChar; hModule: HMODULE = 0): BOOL;
    function SetItemTemplateXMLFromString(pStringXML: PChar): BOOL;
    function SetItemTemplateXMLSel(pXmlFile: PWideChar): BOOL;
    function SetItemTemplateXMLSelFromString(pStringXML: PChar): BOOL;
    function SetItemTemplate(hTemp: HTEMP): BOOL;
    function SetItemTemplateSel(hTemp: HTEMP): BOOL;
    function GetItemTemplate: HTEMP;

    function SetItemData(nID: Integer; nUserData: vint): BOOL;
    function GetItemData(nID: Integer): vint;
    function SetSelectItem(nID: Integer): BOOL;
    function GetSelectItem: Integer;
    procedure VisibleItem(nID: Integer);
    function IsExpand(nID: Integer): BOOL;
    function ExpandItem(nID: Integer; bExpand: BOOL): BOOL;
    function ExpandAllChildItem(nID: Integer; bExpand: BOOL): BOOL;
    function HitTest(pPt: PPoint): Integer;
    function HitTestOffset(pPt: PPoint): Integer;
    function GetFirstChildItem(nID: Integer): Integer;
    function GetEndChildItem(nID: Integer): Integer;
    function GetPrevSiblingItem(nID: Integer): Integer;
    function GetNextSiblingItem(nID: Integer): Integer;
    function GetParentItem(nID: Integer): Integer;

    procedure SetIndentation(nWidth: Integer);
    function GetIndentation: Integer;
    procedure SetItemHeight(nID, nHeight, nSelHeight: Integer);
    procedure GetItemHeight(nID: Integer; out pHeight, pSelHeight: Integer);
    procedure SetRowSpace(nSpace: Integer);
    function GetRowSpace: Integer;
    function MoveItem(nMoveItem, nDestItem, nFlag: Integer): BOOL;
    procedure SetItemHeightDefault(nHeight, nSelHeight: Integer);
    procedure GetItemHeightDefault(out pHeight, pSelHeight: Integer);

    function GetTemplateObject(nID, nTempItemID: Integer): HXCGUI;
    function GetItemIDFromHXCGUI(hXCGUI: HXCGUI): Integer;
    function CreateAdapter: HXCGUI;
    procedure BindAdapter(hAdapter: HXCGUI);
    function GetAdapter: HXCGUI;
    procedure RefreshData;
    procedure RefreshItem(nID: Integer);

    function InsertItemText(pValue: PWideChar; nParentID: Integer = XC_ID_ROOT; insertID: Integer = XC_ID_LAST): Integer;
    function InsertItemTextEx(pName, pValue: PWideChar; nParentID: Integer = XC_ID_ROOT; insertID: Integer = XC_ID_LAST): Integer;
    function InsertItemImage(hImage: HIMAGE; nParentID: Integer = XC_ID_ROOT; insertID: Integer = XC_ID_LAST): Integer;
    function InsertItemImageEx(pName: PWideChar; hImage: HIMAGE; nParentID: Integer = XC_ID_ROOT; insertID: Integer = XC_ID_LAST): Integer;

    function GetCount: Integer;
    function GetCountColumn: Integer;
    function SetItemText(nID, iColumn: Integer; pValue: PWideChar): BOOL;
    function SetItemTextEx(nID: Integer; pName, pValue: PWideChar): BOOL;
    function SetItemImage(nID, iColumn: Integer; hImage: HIMAGE): BOOL;
    function SetItemImageEx(nID: Integer; pName: PWideChar; hImage: HIMAGE): BOOL;
    function GetItemText(nID, iColumn: Integer): PWideChar;
    function GetItemTextEx(nID: Integer; pName: PWideChar): PWideChar;
    function GetItemImage(nID, iColumn: Integer): HIMAGE;
    function GetItemImageEx(nID: Integer; pName: PWideChar): HIMAGE;
    function DeleteItem(nID: Integer): BOOL;
    procedure DeleteItemAll;
    procedure DeleteColumnAll;
  end;

implementation

procedure TXTree.CreateHandle(x, y, cx, cy: Integer; hParent: TXWidget); begin Handle := XTree_Create(x, y, cx, cy, hParent.Handle); end;
destructor TXTree.Destroy; begin inherited; end;
class function TXTree.CreateEx(x, y, cx, cy: Integer; hParent: TXWidget): TXTree; var Tree: TXTree; begin Tree := TXTree.Create; Tree.Handle := XTree_CreateEx(x, y, cx, cy, hParent.Handle); Result := Tree; end;

procedure TXTree.EnableDragItem(bEnable: BOOL); begin XTree_EnableDragItem(Handle, bEnable); end;
procedure TXTree.EnableConnectLine(bEnable, bSolid: BOOL); begin XTree_EnableConnectLine(Handle, bEnable, bSolid); end;
procedure TXTree.EnableExpand(bEnable: BOOL); begin XTree_EnableExpand(Handle, bEnable); end;
procedure TXTree.EnableTemplateReuse(bEnable: BOOL); begin XTree_EnableTemplateReuse(Handle, bEnable); end;
procedure TXTree.SetConnectLineColor(color: Integer); begin XTree_SetConnectLineColor(Handle, color); end;
procedure TXTree.SetSplitLineColor(color: Integer); begin XTree_SetSplitLineColor(Handle, color); end;
procedure TXTree.SetExpandButtonSize(nWidth, nHeight: Integer); begin XTree_SetExpandButtonSize(Handle, nWidth, nHeight); end;
procedure TXTree.SetConnectLineLength(nLength: Integer); begin XTree_SetConnectLineLength(Handle, nLength); end;
procedure TXTree.SetDragInsertPositionColor(color: Integer); begin XTree_SetDragInsertPositionColor(Handle, color); end;
procedure TXTree.SetDrawItemBkFlags(nFlags: Integer); begin XTree_SetDrawItemBkFlags(Handle, nFlags); end;

function TXTree.SetItemTemplateXML(pXmlFile: PWideChar): BOOL; begin Result := XTree_SetItemTemplateXML(Handle, pXmlFile); end;
function TXTree.SetItemTemplateXMLFromMem(data: Pointer; length: Integer): BOOL; begin Result := XTree_SetItemTemplateXMLFromMem(Handle, data, length); end;
function TXTree.SetItemTemplateXMLFromZipRes(id: Integer; pFileName, pPassword: PWideChar; hModule: HMODULE = 0): BOOL; begin Result := XTree_SetItemTemplateXMLFromZipRes(Handle, id, pFileName, pPassword, hModule); end;
function TXTree.SetItemTemplateXMLFromString(pStringXML: PChar): BOOL; begin Result := XTree_SetItemTemplateXMLFromString(Handle, pStringXML); end;
function TXTree.SetItemTemplateXMLSel(pXmlFile: PWideChar): BOOL; begin Result := XTree_SetItemTemplateXMLSel(Handle, pXmlFile); end;
function TXTree.SetItemTemplateXMLSelFromString(pStringXML: PChar): BOOL; begin Result := XTree_SetItemTemplateXMLSelFromString(Handle, pStringXML); end;
function TXTree.SetItemTemplate(hTemp: HTEMP): BOOL; begin Result := XTree_SetItemTemplate(Handle, hTemp); end;
function TXTree.SetItemTemplateSel(hTemp: HTEMP): BOOL; begin Result := XTree_SetItemTemplateSel(Handle, hTemp); end;
function TXTree.GetItemTemplate: HTEMP; begin Result := XTree_GetItemTemplate(Handle); end;

function TXTree.SetItemData(nID: Integer; nUserData: vint): BOOL; begin Result := XTree_SetItemData(Handle, nID, nUserData); end;
function TXTree.GetItemData(nID: Integer): vint; begin Result := XTree_GetItemData(Handle, nID); end;
function TXTree.SetSelectItem(nID: Integer): BOOL; begin Result := XTree_SetSelectItem(Handle, nID); end;
function TXTree.GetSelectItem: Integer; begin Result := XTree_GetSelectItem(Handle); end;
procedure TXTree.VisibleItem(nID: Integer); begin XTree_VisibleItem(Handle, nID); end;
function TXTree.IsExpand(nID: Integer): BOOL; begin Result := XTree_IsExpand(Handle, nID); end;
function TXTree.ExpandItem(nID: Integer; bExpand: BOOL): BOOL; begin Result := XTree_ExpandItem(Handle, nID, bExpand); end;
function TXTree.ExpandAllChildItem(nID: Integer; bExpand: BOOL): BOOL; begin Result := XTree_ExpandAllChildItem(Handle, nID, bExpand); end;
function TXTree.HitTest(pPt: PPoint): Integer; begin Result := XTree_HitTest(Handle, pPt); end;
function TXTree.HitTestOffset(pPt: PPoint): Integer; begin Result := XTree_HitTestOffset(Handle, pPt); end;
function TXTree.GetFirstChildItem(nID: Integer): Integer; begin Result := XTree_GetFirstChildItem(Handle, nID); end;
function TXTree.GetEndChildItem(nID: Integer): Integer; begin Result := XTree_GetEndChildItem(Handle, nID); end;
function TXTree.GetPrevSiblingItem(nID: Integer): Integer; begin Result := XTree_GetPrevSiblingItem(Handle, nID); end;
function TXTree.GetNextSiblingItem(nID: Integer): Integer; begin Result := XTree_GetNextSiblingItem(Handle, nID); end;
function TXTree.GetParentItem(nID: Integer): Integer; begin Result := XTree_GetParentItem(Handle, nID); end;

procedure TXTree.SetIndentation(nWidth: Integer); begin XTree_SetIndentation(Handle, nWidth); end;
function TXTree.GetIndentation: Integer; begin Result := XTree_GetIndentation(Handle); end;
procedure TXTree.SetItemHeight(nID, nHeight, nSelHeight: Integer); begin XTree_SetItemHeight(Handle, nID, nHeight, nSelHeight); end;
procedure TXTree.GetItemHeight(nID: Integer; out pHeight, pSelHeight: Integer); begin XTree_GetItemHeight(Handle, nID, pHeight, pSelHeight); end;
procedure TXTree.SetRowSpace(nSpace: Integer); begin XTree_SetRowSpace(Handle, nSpace); end;
function TXTree.GetRowSpace: Integer; begin Result := XTree_GetRowSpace(Handle); end;
function TXTree.MoveItem(nMoveItem, nDestItem, nFlag: Integer): BOOL; begin Result := XTree_MoveItem(Handle, nMoveItem, nDestItem, nFlag); end;
procedure TXTree.SetItemHeightDefault(nHeight, nSelHeight: Integer); begin XTree_SetItemHeightDefault(Handle, nHeight, nSelHeight); end;
procedure TXTree.GetItemHeightDefault(out pHeight, pSelHeight: Integer); begin XTree_GetItemHeightDefault(Handle, pHeight, pSelHeight); end;

function TXTree.GetTemplateObject(nID, nTempItemID: Integer): HXCGUI; begin Result := XTree_GetTemplateObject(Handle, nID, nTempItemID); end;
function TXTree.GetItemIDFromHXCGUI(hXCGUI: HXCGUI): Integer; begin Result := XTree_GetItemIDFromHXCGUI(Handle, hXCGUI); end;
function TXTree.CreateAdapter: HXCGUI; begin Result := XTree_CreateAdapter(Handle); end;
procedure TXTree.BindAdapter(hAdapter: HXCGUI); begin XTree_BindAdapter(Handle, hAdapter); end;
function TXTree.GetAdapter: HXCGUI; begin Result := XTree_GetAdapter(Handle); end;
procedure TXTree.RefreshData; begin XTree_RefreshData(Handle); end;
procedure TXTree.RefreshItem(nID: Integer); begin XTree_RefreshItem(Handle, nID); end;

function TXTree.InsertItemText(pValue: PWideChar; nParentID: Integer = XC_ID_ROOT; insertID: Integer = XC_ID_LAST): Integer; begin Result := XTree_InsertItemText(Handle, pValue, nParentID, insertID); end;
function TXTree.InsertItemTextEx(pName, pValue: PWideChar; nParentID: Integer = XC_ID_ROOT; insertID: Integer = XC_ID_LAST): Integer; begin Result := XTree_InsertItemTextEx(Handle, pName, pValue, nParentID, insertID); end;
function TXTree.InsertItemImage(hImage: HIMAGE; nParentID: Integer = XC_ID_ROOT; insertID: Integer = XC_ID_LAST): Integer; begin Result := XTree_InsertItemImage(Handle, hImage, nParentID, insertID); end;
function TXTree.InsertItemImageEx(pName: PWideChar; hImage: HIMAGE; nParentID: Integer = XC_ID_ROOT; insertID: Integer = XC_ID_LAST): Integer; begin Result := XTree_InsertItemImageEx(Handle, pName, hImage, nParentID, insertID); end;

function TXTree.GetCount: Integer; begin Result := XTree_GetCount(Handle); end;
function TXTree.GetCountColumn: Integer; begin Result := XTree_GetCountColumn(Handle); end;
function TXTree.SetItemText(nID, iColumn: Integer; pValue: PWideChar): BOOL; begin Result := XTree_SetItemText(Handle, nID, iColumn, pValue); end;
function TXTree.SetItemTextEx(nID: Integer; pName, pValue: PWideChar): BOOL; begin Result := XTree_SetItemTextEx(Handle, nID, pName, pValue); end;
function TXTree.SetItemImage(nID, iColumn: Integer; hImage: HIMAGE): BOOL; begin Result := XTree_SetItemImage(Handle, nID, iColumn, hImage); end;
function TXTree.SetItemImageEx(nID: Integer; pName: PWideChar; hImage: HIMAGE): BOOL; begin Result := XTree_SetItemImageEx(Handle, nID, pName, hImage); end;
function TXTree.GetItemText(nID, iColumn: Integer): PWideChar; begin Result := XTree_GetItemText(Handle, nID, iColumn); end;
function TXTree.GetItemTextEx(nID: Integer; pName: PWideChar): PWideChar; begin Result := XTree_GetItemTextEx(Handle, nID, pName); end;
function TXTree.GetItemImage(nID, iColumn: Integer): HIMAGE; begin Result := XTree_GetItemImage(Handle, nID, iColumn); end;
function TXTree.GetItemImageEx(nID: Integer; pName: PWideChar): HIMAGE; begin Result := XTree_GetItemImageEx(Handle, nID, pName); end;
function TXTree.DeleteItem(nID: Integer): BOOL; begin Result := XTree_DeleteItem(Handle, nID); end;
procedure TXTree.DeleteItemAll; begin XTree_DeleteItemAll(Handle); end;
procedure TXTree.DeleteColumnAll; begin XTree_DeleteColumnAll(Handle); end;

end.
