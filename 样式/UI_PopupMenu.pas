unit UI_PopupMenu;

interface

uses
  Windows, Types, XCGUI, XMenu, UI_Theme, UI_PopupAnimation;

const
  UI_POPUP_MENU_ITEM_HEIGHT_DEFAULT = 32;
  /// <summary>菜单文字左边距（与左侧勾同列对齐，不宜过大以免与勾间隔过远）。</summary>
  UI_POPUP_MENU_TEXT_PAD_LEFT = 26;
  /// <summary>用于计算弹窗水平收窄量：与此前默认 42 的差值会自窗口右侧裁掉，与绘制内边距一致。</summary>
  UI_POPUP_MENU_TEXT_PAD_LEFT_BASELINE = 42;
  UI_POPUP_MENU_TEXT_PAD_RIGHT = 12;
  /// <summary>有子菜单时，文字与右侧「展开」箭头之间的留白。</summary>
  UI_POPUP_MENU_SUBMENU_ARROW_GAP = 6;
  /// <summary>子菜单展开箭头占用宽度（含与右内边距的间隔）。</summary>
  UI_POPUP_MENU_SUBMENU_ARROW_TOTAL = 16;
  UI_POPUP_MENU_ITEM_ICON_SIZE = 16;
  UI_POPUP_MENU_CHECK_INSET_LEFT = 2;
  UI_POPUP_MENU_CHECK_GAP_BEFORE_TEXT = 4;

type
  TPopupMenuUI = class(TXMenu)
  private
    FHostEle: HELE;
    class function OnMenuPopupWnd(HostEle: HELE; hMenu: HMENUX; var pInfo: Tmenu_popupWnd_; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnMenuExit(HostEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnMenuDrawItem(HostEle: HELE; AHDraw: HDRAW; var pInfo: Tmenu_drawItem_; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnMenuDrawBackground(HostEle: HELE; AHDraw: HDRAW; var pInfo: Tmenu_drawBackground_; pbHandled: PBOOL): Integer; stdcall; static;
  public
    constructor Create(const hHostEle: HELE); reintroduce;
    destructor Destroy; override;
    procedure AddItemIcon(nID: Integer; const pText: String; nParentID: Integer; const svgPath: String; nFlags: Integer; svgWidth: Integer = UI_POPUP_MENU_ITEM_ICON_SIZE; svgHeight: Integer = UI_POPUP_MENU_ITEM_ICON_SIZE); reintroduce;
    procedure AddItemIconImage(nID: Integer; const pText: String; nParentID: Integer; const hImage: HIMAGE; nFlags: Integer);
    procedure AddItemIconData(nID: Integer; const pText: String; nParentID: Integer; const hIcon: HICON; nFlags: Integer); reintroduce;
    procedure AddItemShieldIcon(nID: Integer; const pText: String; nParentID: Integer; nFlags: Integer); reintroduce;
    procedure Popup(const hHostEle: HELE; var PtClient: TPoint; const nPosition: Integer = menu_popup_position_left_top);
  end;

implementation

uses
  AppConfig, SysUtils, ShellHelper;

{ TPopupMenuUI }

constructor TPopupMenuUI.Create(const hHostEle: HELE);
begin
  inherited Create;
  FHostEle := hHostEle;
  SetItemHeight(UI_POPUP_MENU_ITEM_HEIGHT_DEFAULT);
  EnableDrawItem(True);
  EnableDrawBackground(True);
  XEle_RegEvent(hHostEle, XE_MENU_POPUP_WND, @TPopupMenuUI.OnMenuPopupWnd);
  XEle_RegEvent(hHostEle, XE_MENU_EXIT, @TPopupMenuUI.OnMenuExit);
  XEle_RegEvent(hHostEle, XE_MENU_DRAWITEM, @TPopupMenuUI.OnMenuDrawItem);
  XEle_RegEvent(hHostEle, XE_MENU_DRAW_BACKGROUND, @TPopupMenuUI.OnMenuDrawBackground);
end;

destructor TPopupMenuUI.Destroy;
begin
  if XC_IsHELE(FHostEle) then
  begin
    XEle_RemoveEvent(FHostEle, XE_MENU_POPUP_WND, @TPopupMenuUI.OnMenuPopupWnd);
    XEle_RemoveEvent(FHostEle, XE_MENU_EXIT, @TPopupMenuUI.OnMenuExit);
    XEle_RemoveEvent(FHostEle, XE_MENU_DRAWITEM, @TPopupMenuUI.OnMenuDrawItem);
    XEle_RemoveEvent(FHostEle, XE_MENU_DRAW_BACKGROUND, @TPopupMenuUI.OnMenuDrawBackground);
  end;
  inherited;
end;

procedure TPopupMenuUI.AddItemIcon(nID: Integer; const pText: String; nParentID: Integer; const svgPath: String; nFlags: Integer; svgWidth: Integer; svgHeight: Integer);
var
  hSvg: Integer;
  hImg: HIMAGE;
  ext: string;
begin
  if svgPath = '' then
  begin
    inherited AddItem(nID, pText, nParentID, nFlags);
    Exit;
  end;

  ext := LowerCase(ExtractFileExt(svgPath));

  if (ext = '.png') or (ext = '.jpg') or (ext = '.jpeg') then
  begin
    hImg := XImage_LoadFile(PWideChar(svgPath));
    if XC_GetObjectType(hImg) = XC_IMAGE then
      inherited AddItemIcon(nID, pText, nParentID, hImg, nFlags)
    else
      inherited AddItem(nID, pText, nParentID, nFlags);
    Exit;
  end;

  // default: treat as svg (keeps existing behavior for .svg)
  hSvg := XSvg_LoadFile(PWideChar(svgPath));
  if XC_GetObjectType(hSvg) <> XC_SVG then
  begin
    inherited AddItem(nID, pText, nParentID, nFlags);
    Exit;
  end;
  try
    XSvg_SetUserFillColor(hSvg, UITheme_TextPrimary, True);
    XSvg_SetUserStrokeColor(hSvg, UITheme_TextPrimary, 1, True);
    if svgWidth <= 0 then
      svgWidth := UI_POPUP_MENU_ITEM_ICON_SIZE;
    if svgHeight <= 0 then
      svgHeight := UI_POPUP_MENU_ITEM_ICON_SIZE;
    XSvg_SetSize(hSvg, svgWidth, svgHeight);
    hImg := XImage_LoadSvg(hSvg);
    if XC_GetObjectType(hImg) = XC_IMAGE then
      inherited AddItemIcon(nID, pText, nParentID, hImg, nFlags)
    else
      inherited AddItem(nID, pText, nParentID, nFlags);
  finally
  
    //  XSvg_Release(hSvg);
  end;
end;

procedure TPopupMenuUI.AddItemIconImage(nID: Integer; const pText: String; nParentID: Integer; const hImage: HIMAGE; nFlags: Integer);
begin
  if (hImage = 0) or (XC_GetObjectType(hImage) <> XC_IMAGE) then
    inherited AddItem(nID, pText, nParentID, nFlags)
  else
    inherited AddItemIcon(nID, pText, nParentID, hImage, nFlags);
end;

procedure TPopupMenuUI.AddItemIconData(nID: Integer; const pText: String; nParentID: Integer; const hIcon: HICON; nFlags: Integer);
var
  hImg: HIMAGE;
begin
  if hIcon = 0 then
  begin
    inherited AddItem(nID, pText, nParentID, nFlags);
    Exit;
  end;

  hImg := LoadImageFromIconData(hIcon);
  if XC_GetObjectType(hImg) = XC_IMAGE then
    inherited AddItemIcon(nID, pText, nParentID, hImg, nFlags)
  else
    inherited AddItem(nID, pText, nParentID, nFlags);
end;

procedure TPopupMenuUI.AddItemShieldIcon(nID: Integer; const pText: String; nParentID: Integer; nFlags: Integer);
var
  hShield: HICON;
begin
  hShield := GetShieldIconSmall;

  try
    AddItemIconData(nID, pText, nParentID, hShield, nFlags);
  finally
    if hShield <> 0 then
      DestroyIcon(hShield);
  end;
end;

procedure TPopupMenuUI.Popup(const hHostEle: HELE; var PtClient: TPoint; const nPosition: Integer);
var
  hWnd: Integer;
begin
  UIPopupAnim_SetLastMenuPopupPosition(nPosition);
  hWnd := XWidget_GetHWND(hHostEle);
  XEle_PointClientToWndClient(hHostEle, PtClient);
  Windows.ClientToScreen(hWnd, PtClient);
  inherited Popup(hWnd, PtClient.X, PtClient.Y, hHostEle, nPosition);
end;

class function TPopupMenuUI.OnMenuPopupWnd(HostEle: HELE; hMenu: HMENUX; var pInfo: Tmenu_popupWnd_; pbHandled: PBOOL): Integer; stdcall;
var
  rcWnd: TRect;
  rcFinal: TRect;
  rcMain: TRect;
  nShadowSize: Integer;
  hWalk: HXCGUI;
  hRootWnd: Integer;
begin
  Result := 0;
  nShadowSize := 12;

  XWnd_SetTransparentType(pInfo.hWindow, Ord(window_transparent_shadow));
  XWnd_SetPadding(pInfo.hWindow, 5, 0, 5, 5);
  XWnd_SetTransparentAlpha(pInfo.hWindow, 255);
  XWnd_SetShadowInfo(pInfo.hWindow, nShadowSize, 200, UITheme_WindowCornerRadius, False, UITheme_ShadowDefault);
  XWnd_GetRect(pInfo.hWindow, rcWnd);
  Dec(rcWnd.Right, UI_POPUP_MENU_TEXT_PAD_LEFT_BASELINE - UI_POPUP_MENU_TEXT_PAD_LEFT);
  Dec(rcWnd.Left, nShadowSize);
  Dec(rcWnd.Top, nShadowSize);
  Inc(rcWnd.Right, nShadowSize);
  Inc(rcWnd.Bottom, nShadowSize);

  hRootWnd := 0;
  hWalk := HostEle;
  while hWalk <> 0 do
  begin
    if XC_IsHWINDOW(hWalk) then
    begin
      hRootWnd := hWalk;
      Break;
    end;
    hWalk := XWidget_GetParent(hWalk);
  end;
  if hRootWnd <> 0 then
  begin
    XWnd_GetRect(hRootWnd, rcMain);
    if rcWnd.Left < rcMain.Left then
      OffsetRect(rcWnd, rcMain.Left - rcWnd.Left, 0);
    if rcWnd.Right > rcMain.Right then
      OffsetRect(rcWnd, rcMain.Right - rcWnd.Right, 0);
    if rcWnd.Top < rcMain.Top then
      OffsetRect(rcWnd, 0, rcMain.Top - rcWnd.Top);
    if rcWnd.Bottom > rcMain.Bottom then
      OffsetRect(rcWnd, 0, rcMain.Bottom - rcWnd.Bottom);
  end;

  rcFinal := rcWnd;
  XWnd_SetRect(pInfo.hWindow, rcWnd);
  UIPopupAnim_OnMenuPopupWindow(pInfo.hWindow, pInfo.nParentID, rcFinal);
end;

class function TPopupMenuUI.OnMenuExit(HostEle: HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  UIPopupAnim_OnMenuExit;
end;

class function TPopupMenuUI.OnMenuDrawItem(HostEle: HELE; AHDraw: HDRAW; var pInfo: Tmenu_drawItem_; pbHandled: PBOOL): Integer; stdcall;
var
  rcItem: TRect;
  rcText: TRect;
  rcTextF: TRectF;
  rcCheck: TRect;
  colorText: Integer;
  y: Integer;
  showCheck: Boolean;
  nTrimW: Integer;
  showSubMenuArrow: Boolean;
  hasItemIcon: Boolean;
  cxTip, cy, xTail: Integer;
  imgW, imgH, drawW, drawH, x0, y0, cSz: Integer;
begin
  Result := 0;
  nTrimW := UI_POPUP_MENU_TEXT_PAD_LEFT_BASELINE - UI_POPUP_MENU_TEXT_PAD_LEFT;
  rcItem := pInfo.rcItem;
  Dec(rcItem.Right, nTrimW);

  if (pInfo.nState and Integer(menu_item_flag_separator)) <> 0 then
  begin
    XDraw_SetLineWidth(AHDraw, 1);
    XDraw_SetBrushColor(AHDraw, UITheme_PopupMenu_AccentWhiteAlpha30);
    y := (rcItem.Top + rcItem.Bottom) div 2;
    XDraw_DrawLine(AHDraw, rcItem.Left - 2, y, rcItem.Right + 2, y);
    pbHandled^ := True;
    Exit;
  end;

  if (pInfo.nState and Integer(menu_item_flag_Select)) <> 0 then
  begin
    XDraw_SetBrushColor(AHDraw, UITheme_PopupMenu_AccentWhiteAlpha30);
    XDraw_FillRoundRect(AHDraw, rcItem, 4, 4);
  end;

  if pInfo.nID = 201 then
    showCheck := TAppConfig.IsShowCommonTools
  else if pInfo.nID = 202 then
    showCheck := TAppConfig.IsShowTrafficMonitor
  else
    showCheck := (pInfo.nState and Integer(menu_item_flag_Check)) <> 0;

  hasItemIcon := XC_GetObjectType(pInfo.hIcon) = XC_IMAGE;

  if showCheck then
  begin
    rcCheck := rcItem;
    Inc(rcCheck.Left, UI_POPUP_MENU_CHECK_INSET_LEFT);
    rcCheck.Right := rcItem.Left + UI_POPUP_MENU_TEXT_PAD_LEFT - UI_POPUP_MENU_CHECK_GAP_BEFORE_TEXT;
    XDraw_SetLineWidth(AHDraw, 2);
    XDraw_SetBrushColor(AHDraw, UITheme_PrimaryColor);
    XDraw_EnableSmoothingMode(AHDraw, True);
    XDraw_DrawLine(AHDraw,
      (rcCheck.Left + rcCheck.Right) div 2 - 5,
      (rcCheck.Top + rcCheck.Bottom) div 2,
      (rcCheck.Left + rcCheck.Right) div 2 - 2,
      (rcCheck.Top + rcCheck.Bottom) div 2 + 4);
    XDraw_DrawLine(AHDraw,
      (rcCheck.Left + rcCheck.Right) div 2 - 2,
      (rcCheck.Top + rcCheck.Bottom) div 2 + 4,
      (rcCheck.Left + rcCheck.Right) div 2 + 5,
      (rcCheck.Top + rcCheck.Bottom) div 2 - 4);
    XDraw_EnableSmoothingMode(AHDraw, False);
    XDraw_SetLineWidth(AHDraw, 1);
  end;

  showSubMenuArrow := (pInfo.nState and Integer(menu_item_flag_Popup)) <> 0;

  rcText := rcItem;
  Inc(rcText.Left, UI_POPUP_MENU_TEXT_PAD_LEFT);
  if showCheck and hasItemIcon then
    Inc(rcText.Left, UI_POPUP_MENU_ITEM_ICON_SIZE + UI_POPUP_MENU_CHECK_GAP_BEFORE_TEXT);
  Dec(rcText.Right, UI_POPUP_MENU_TEXT_PAD_RIGHT);
  if showSubMenuArrow then
    Dec(rcText.Right, UI_POPUP_MENU_SUBMENU_ARROW_TOTAL);

  colorText := UITheme_TextPrimary;

  if hasItemIcon then
  begin
    cSz := UI_POPUP_MENU_ITEM_ICON_SIZE;
    imgW := XImage_GetWidth(pInfo.hIcon);
    imgH := XImage_GetHeight(pInfo.hIcon);
    if (imgW > 0) and (imgH > 0) then
    begin
      if (imgW <= cSz) and (imgH <= cSz) then
      begin
        drawW := imgW;
        drawH := imgH;
      end
      else if (imgW * cSz) >= (imgH * cSz) then
      begin
        drawW := cSz;
        drawH := MulDiv(imgH, cSz, imgW);
      end
      else
      begin
        drawH := cSz;
        drawW := MulDiv(imgW, cSz, imgH);
      end;
    end
    else
    begin
      drawW := cSz;
      drawH := cSz;
    end;
    if showCheck then
      x0 := rcItem.Left + UI_POPUP_MENU_TEXT_PAD_LEFT + UI_POPUP_MENU_CHECK_GAP_BEFORE_TEXT
    else
      x0 := rcItem.Left + (UI_POPUP_MENU_TEXT_PAD_LEFT - drawW) div 2;
    y0 := (rcItem.Top + rcItem.Bottom - drawH) div 2;
    XDraw_ImageEx(AHDraw, pInfo.hIcon, x0, y0, drawW, drawH);
  end;

  XDraw_SetBrushColor(AHDraw, colorText);
  XDraw_SetTextAlign(AHDraw, textAlignFlag_left or textAlignFlag_vcenter or textFormatFlag_NoWrap);
  rcTextF.Left := rcText.Left + 0.5;
  rcTextF.Top := rcText.Top + 0.5;
  rcTextF.Right := rcText.Right + 0.5;
  rcTextF.Bottom := rcText.Bottom + 0.5;
  XDraw_DrawTextF(AHDraw, pInfo.pText, -1, rcTextF);

  if showSubMenuArrow then
  begin
    cxTip := rcItem.Right - UI_POPUP_MENU_TEXT_PAD_RIGHT;
    cy := (rcItem.Top + rcItem.Bottom) div 2;
    xTail := cxTip - 5;
    XDraw_SetLineWidth(AHDraw, 1);
    XDraw_SetBrushColor(AHDraw, colorText);
    XDraw_EnableSmoothingMode(AHDraw, True);
    XDraw_DrawLine(AHDraw, xTail, cy - 4, cxTip, cy);
    XDraw_DrawLine(AHDraw, cxTip, cy, xTail, cy + 4);
    XDraw_EnableSmoothingMode(AHDraw, False);
    XDraw_SetLineWidth(AHDraw, 1);
  end;

  pbHandled^ := True;
end;

class function TPopupMenuUI.OnMenuDrawBackground(HostEle: HELE; AHDraw: HDRAW; var pInfo: Tmenu_drawBackground_; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
  nBorderRadius: Integer;
begin
  Result := 0;
  nBorderRadius := UITheme_WindowCornerRadius;
  XWnd_GetClientRect(pInfo.hWindow, rc);
  XDraw_SetBrushColor(AHDraw, UITheme_SurfaceBase);
  XDraw_FillRoundRect(AHDraw, rc, UITheme_WindowCornerRadius, UITheme_WindowCornerRadius);
  XDraw_SetLineWidth(AHDraw, 1);
  XDraw_SetBrushColor(AHDraw, UITheme_SurfaceOutline);
  XDraw_DrawRoundRect(AHDraw, rc, nBorderRadius, nBorderRadius);
  pbHandled^ := True;
end;

end.

