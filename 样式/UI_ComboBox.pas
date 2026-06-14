unit UI_ComboBox;

interface

uses
  Windows, SysUtils, Types, XCGUI, XComboBox;

type
  TComboBoxUI = class(TXComboBox)
  private
    hAdapter: HXCGUI;
    FCornerRadius: Integer;
    FEnableBorder: Boolean;
    FEnableBkColor: Boolean;
    FEnableFocusBkColor: Boolean;
    FBkColor: Integer;
    FFocusBkColor: Integer;
    FBorderColor: Integer;
    FItemHeight: Integer;
    class function OnPaint(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnFocusChanged(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnPopupList(hEle: XCGUI.HELE; hWindow: XCGUI.HWINDOW; hListBox: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnPopupListDrawItem(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; var pItem: TlistBox_item_; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnPopupListButtonDown(hEle: XCGUI.HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
  protected
    procedure Init; override;
  public
    class function FromXmlName(const XmlName: string): TComboBoxUI; reintroduce;
    procedure InitTextItems(const Items: array of string; const DefaultIndex: Integer = 0);
    property ItemHeight: Integer read FItemHeight write FItemHeight;
  end;

implementation

uses
  UI_Edit, UI_Ele, UI_Theme, UI_ListBox, UI_Form, UI_ScrollBar;

class function TComboBoxUI.FromXmlName(const XmlName: string): TComboBoxUI;
begin
  Result := TComboBoxUI(inherited FromXmlName(XmlName));
end;

procedure TComboBoxUI.Init;
begin
  inherited;
  TEditUI.ApplyInputElementBaseStyle(Self.Handle);
  RegEvent(XE_SETFOCUS, @TComboBoxUI.OnFocusChanged);
  RegEvent(XE_KILLFOCUS, @TComboBoxUI.OnFocusChanged);
  RegEvent(XE_PAINT, @TComboBoxUI.OnPaint);
  RegEvent(XE_COMBOBOX_POPUP_LIST, @TComboBoxUI.OnPopupList);
  SetItemTemplateXML('Resource\Layout\ComboBox_Item.xml');
  FEnableBkColor := True;
  FBkColor := UITheme_InputSurface;
  FEnableBorder := True;
  SetBorderSize(4,0,2,0);
  FCornerRadius := 4;
  FFocusBkColor := UITheme_InputSurfaceFocus;
  FEnableFocusBkColor := True;
  EnableEdit(False);
  FBorderColor := UITheme_InputBorder;
  FItemHeight := 32;
  hAdapter := CreateAdapter;
  XAdTable_AddColumn(hAdapter, XC_NAME1);
end;

class function TComboBoxUI.OnPaint(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall;
var
  pComboUI: TComboBoxUI;
  rc: TRect;
  drawBorder: Boolean;
  borderColor: Integer;
  bkColor: Integer;
begin
  Result := 0;
  pComboUI := TComboBoxUI.FromHandle(hEle);
  XEle_GetClientRect(hEle, rc);

  drawBorder := pComboUI.FEnableBorder;
  borderColor := pComboUI.FBorderColor;
  bkColor := pComboUI.FBkColor;
  if pComboUI.IsFocus or pComboUI.IsFocusEx then
  begin
    drawBorder := True;
    borderColor := pComboUI.FocusBorderColor;
    if pComboUI.FEnableFocusBkColor then
      bkColor := pComboUI.FFocusBkColor;
  end;

  DrawRoundedElement(
    hDraw,
    rc,
    pComboUI.FCornerRadius,
    pComboUI.FEnableBkColor or ((pComboUI.IsFocus or pComboUI.IsFocusEx) and pComboUI.FEnableFocusBkColor),
    bkColor,
    drawBorder,
    borderColor
  );
end;

class function TComboBoxUI.OnFocusChanged(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  TComboBoxUI(TComboBoxUI.FromHandle(hEle)).Redraw;
end;

class function TComboBoxUI.OnPopupList(hEle: XCGUI.HELE; hWindow: XCGUI.HWINDOW; hListBox: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
var
  rcWnd: TRect;
  nShadowSize: Integer;
  itemHeight: Integer;
  selHeight: Integer;
  popupHeight: Integer;
  currentSelItem: Integer;
  logicalWidth: Integer;
  pComboUI: TComboBoxUI;
begin
  Result := 0;
  pbHandled^ := True;
  if not TFormUI.IsReused(hWindow) then
    TFormUI.FromHandle(hWindow);

  XEle_EnableDrawBorder(hListBox, False);
  XEle_EnableBkTransparent(hListBox, True);
  pComboUI := TComboBoxUI.FromHandle(hEle);
  XListBox_SetItemHeightDefault(hListBox, pComboUI.FItemHeight, pComboUI.FItemHeight);
  XListBox_SetRowSpace(hListBox, 1);
  TScrollBarUI.ApplyDefault(hListBox);

  currentSelItem := XComboBox_GetSelItem(hEle);
  if currentSelItem < 0 then
    currentSelItem := 0;
  XListBox_SetSelectItem(hListBox, currentSelItem);

  XListBox_GetItemHeightDefault(hListBox, itemHeight, selHeight);
  popupHeight := XListBox_GetCount_AD(hListBox) * (itemHeight + XListBox_GetRowSpace(hListBox)) + 6;
  if popupHeight > 300 then
    popupHeight := 300;

  nShadowSize := 13;
  XWnd_GetRect(hWindow, rcWnd);
  Dec(rcWnd.Left, nShadowSize);
  Dec(rcWnd.Top, nShadowSize);
  Inc(rcWnd.Right, nShadowSize);
  rcWnd.Bottom := rcWnd.Top + popupHeight + nShadowSize * 2;
  XWnd_SetRect(hWindow, rcWnd);

  logicalWidth := (rcWnd.Right - rcWnd.Left) - nShadowSize * 2;
  XEle_SetRectEx(hListBox, nShadowSize, nShadowSize + 1, logicalWidth, popupHeight + 1, True);
  XEle_RegEvent(hListBox, XE_LISTBOX_DRAWITEM, @TComboBoxUI.OnPopupListDrawItem);
  XEle_RegEvent(hListBox, XE_LBUTTONDOWN, @TComboBoxUI.OnPopupListButtonDown);
  XEle_RegEvent(hListBox, XE_RBUTTONDOWN, @TComboBoxUI.OnPopupListButtonDown);
end;

class function TComboBoxUI.OnPopupListDrawItem(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; var pItem: TlistBox_item_; pbHandled: PBOOL): Integer; stdcall;
var
  r: TRect;
  itemRect: TRect;
  markerRect: TRectF;
  pText: PWideChar;
begin
  Result := 0;
  r := pItem.rcItem;
  itemRect := pItem.rcItem;
  Inc(itemRect.Left, 2);
  Dec(itemRect.Right, 2);
  if pItem.nState = list_item_state_select then
  begin
    XDraw_SetBrushColor(hDraw, UITheme_SurfaceSelected);
    XDraw_FillRoundRect(hDraw, itemRect, 4, 4);
    markerRect.Left := itemRect.Left + 1;
    markerRect.Top := itemRect.Top + 5;
    markerRect.Right := itemRect.Right;
    markerRect.Bottom := itemRect.Bottom - 5;
    markerRect.Right := markerRect.Left + 3;
    XDraw_SetBrushColor(hDraw, UITheme_PrimaryColor);
    XDraw_FillRoundRectF(hDraw, markerRect, 1.5, 1.5);
  end
  else if pItem.nState = list_item_state_stay then
  begin
    XDraw_SetBrushColor(hDraw, UITheme_SurfaceHover);
    XDraw_FillRoundRect(hDraw, itemRect, 4, 4);
  end;

  XDraw_SetBrushColor(hDraw, UITheme_InputText);
  XDraw_SetTextAlign(hDraw, textAlignFlag_left or textAlignFlag_vcenter or textFormatFlag_NoWrap);
  Inc(r.Left, 12);
  pText := XListBox_GetItemTextEx(hEle, pItem.index, XC_NAME1);
  XDraw_DrawText(hDraw, pText, -1, r);
  pbHandled^ := True;
end;

class function TComboBoxUI.OnPopupListButtonDown(hEle: XCGUI.HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if XListBox_HitTestOffset(hEle, pPt) < 0 then
    pbHandled^ := True;
end;

procedure TComboBoxUI.InitTextItems(const Items: array of string; const DefaultIndex: Integer = 0);
var
  i: Integer;
begin
  for i := Low(Items) to High(Items) do
    XAdTable_AddItemText(Self.hAdapter, PWideChar(Items[i]));
  SetSelItem(DefaultIndex);
end;

end.

