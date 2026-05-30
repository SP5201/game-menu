unit UI_HintPopup;

interface

uses
  Windows, Messages, Classes, SysUtils, Types, Math, XCGUI, UI_Form,
  UI_Theme;

type
  /// 轻量提示窗：可控时长/位置，不依赖系统 Tooltip
  THintPopupUI = class(TFormUI)
  private
    class var
      FInstance: THintPopupUI;
    class var
      FOwnerHwnd: HWND;
      FTextShape: HXCGUI;
      FHoverHintMap: TStringList;
      FIsVisible: Boolean;
      FLastTargetHandle: Integer;
      FLastText: string;
    class function OnWndPaint(hWindow: hWindow; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnTargetMouseMove(hEle: HELE; nFlags: Cardinal; pPt: PPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnTargetMouseLeave(hEle: HELE; hEleStay: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function EnsureInstance(const ATargetComponentHandle: Integer): THintPopupUI; static;
    procedure SetTextAndResize(const AText: string);
  protected
    procedure Init; override;
  public
    class procedure ShowTextNearCursor(const AText: string; const AAutoCloseMs: Integer); static;
    class procedure ShowTextForTarget(const ATargetComponentHandle: Integer; const AText: string;
      const AAutoCloseMs: Integer; const APopupAbove: Boolean = False; const AOffsetY: Integer = 0); static;
    class procedure BindHoverHint(const ATargetComponentHandle: Integer; const AText: string); static;
    class procedure Hide; static;
  end;

implementation

const
  HintPaddingX = 10;
  HintPaddingY = 8;
  HintMaxWidth = 520;
  HintMinWidth = 120;
  HintMaxHeight = 420;
  HintShadowExtendX = 8;
  HintShadowExtendY = 8;
  HintDrawExpandX = 4;
  HintDrawExpandY = 4;
  HintTargetGap = 4;

procedure THintPopupUI.Init;
begin
  inherited;
  SetTransparentAlpha(240);
  RegEvent(WM_PAINT, @THintPopupUI.OnWndPaint);
end;

class function THintPopupUI.OnWndPaint(hWindow: hWindow; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
  rcBorder: TRect;
  nRadius: Integer;
  colorBk: Integer;
begin
  Result := 0;
  XDraw_EnableSmoothingMode(hDraw, True);
  XWnd_GetClientRect(hWindow, rc);

  nRadius := UITheme_WindowCornerRadius;
  colorBk := UITheme_SurfaceBase;

  XDraw_SetBrushColor(hDraw, colorBk);
  XDraw_FillRoundRect(hDraw, rc, nRadius, nRadius);

  rcBorder := rc;
  XDraw_SetLineWidth(hDraw, 1);
  XDraw_SetBrushColor(hDraw, UITheme_SurfaceOutline);
  XDraw_DrawRoundRect(hDraw, rcBorder, nRadius, nRadius);
  pbHandled^ := True;
end;

class function THintPopupUI.OnTargetMouseMove(hEle: HELE; nFlags: Cardinal; pPt: PPoint; pbHandled: PBOOL): Integer; stdcall;
var
  tipText: string;
  hintIndex: Integer;
begin
  Result := 0;
  tipText := '';
  if Assigned(FHoverHintMap) then
  begin
    hintIndex := FHoverHintMap.IndexOfName(IntToStr(hEle));
    if hintIndex >= 0 then
      tipText := FHoverHintMap.ValueFromIndex[hintIndex];
  end;
  if tipText <> '' then
  begin
    if FIsVisible and (FLastTargetHandle = hEle) and (FLastText = tipText) then
      Exit;
    ShowTextForTarget(hEle, tipText, 0);
  end;
end;

class function THintPopupUI.OnTargetMouseLeave(hEle: HELE; hEleStay: HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  Hide;
end;

class function THintPopupUI.EnsureInstance(const ATargetComponentHandle: Integer): THintPopupUI;
const
  WS_EX_NOACTIVATE = $08000000;
var
  exStyle: DWORD;
  style: DWORD;
  ownerHwnd: Integer;
begin
  ownerHwnd := 0;
  if ATargetComponentHandle <> 0 then
    ownerHwnd := XWidget_GetHWND(ATargetComponentHandle);

  if Assigned(FInstance) and FInstance.IsHWINDOW and (NativeUInt(FOwnerHwnd) = NativeUInt(ownerHwnd)) then
    Exit(FInstance);

  if Assigned(FInstance) and FInstance.IsHWINDOW then
    XWnd_DestroyWindow(FInstance.Handle);
  FInstance := nil;
  FOwnerHwnd := ownerHwnd;

  exStyle := WS_EX_TOPMOST or WS_EX_TRANSPARENT or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE;
  style := WS_POPUP;

  FInstance := THintPopupUI.CreateEx(exStyle, style, nil, 0, 0, 0, 0, '', ownerHwnd, window_style_nothing);

  XWnd_SetTransparentType(FInstance.Handle, Ord(window_transparent_shaped));
  XWnd_SetTransparentAlpha(FInstance.Handle, 240);

  FInstance.FTextShape := XShapeText_Create(HintPaddingX, HintPaddingY, 200, 80, '', FInstance.Handle);
  XShapeText_SetTextAlign(FInstance.FTextShape, DT_LEFT or DT_TOP or DT_WORDBREAK);
  XShapeText_SetTextColor(FInstance.FTextShape, UITheme_TextPrimary);
  XWnd_ShowWindow(FInstance.Handle, SW_HIDE);

  Result := FInstance;
  Result.Init;
end;

procedure THintPopupUI.SetTextAndResize(const AText: string);
var
  sz: TSize;
  nFont: HFONTX;
  rc: TRect;
  w, h: Integer;
  rcText: TRect;
begin
  XShapeText_SetText(FTextShape, PWideChar(AText));

  nFont := XC_GetDefaultFont();
  XC_GetTextShowSize(PWideChar(AText), -1, nFont, sz);

  w := EnsureRange(sz.cx + HintPaddingX * 2, HintMinWidth, HintMaxWidth);
  h := Min(HintMaxHeight, sz.cy + HintPaddingY * 2);
  Inc(w, HintShadowExtendX * 2);
  Inc(h, HintShadowExtendY * 2);

  rc := Rect(0, 0, w, h);
  XWnd_SetRect(Handle, rc);
  rcText := Rect(HintShadowExtendX + HintPaddingX, HintShadowExtendY + HintPaddingY,
    w - HintShadowExtendX - HintPaddingX, h - HintShadowExtendY - HintPaddingY);
  XShape_SetRect(FTextShape, rcText);
end;

class procedure THintPopupUI.ShowTextNearCursor(const AText: string; const AAutoCloseMs: Integer);
var
  dlg: THintPopupUI;
  pt: TPoint;
  x, y: Integer;
begin
  dlg := EnsureInstance(0);
  dlg.SetTextAndResize(AText);

  Windows.GetCursorPos(pt);
  x := pt.X + 14;
  y := pt.Y + 18;
  XWnd_SetPosition(dlg.Handle, x, y);
  XWnd_ShowWindow(dlg.Handle, SW_SHOWNOACTIVATE);
  FIsVisible := True;
  FLastTargetHandle := 0;
  FLastText := AText;
end;

class procedure THintPopupUI.ShowTextForTarget(const ATargetComponentHandle: Integer; const AText: string;
  const AAutoCloseMs: Integer; const APopupAbove: Boolean; const AOffsetY: Integer);
var
  dlg: THintPopupUI;
  pt: TPoint;
  ptAnchor: TPoint;
  hTargetWindow: Integer;
  rcTarget: TRect;
  rcPopup: TRect;
  popupW, popupH, targetW: Integer;
  x, y: Integer;
begin
  dlg := EnsureInstance(ATargetComponentHandle);
  dlg.SetTextAndResize(AText);

  if ATargetComponentHandle <> 0 then
  begin
    hTargetWindow := XWidget_GetHWINDOW(ATargetComponentHandle);
    XEle_GetWndClientRectDPI(ATargetComponentHandle, rcTarget);

    XWnd_GetRect(dlg.Handle, rcPopup);
    popupW := rcPopup.Right - rcPopup.Left;
    popupH := rcPopup.Bottom - rcPopup.Top;
    targetW := rcTarget.Right - rcTarget.Left;

    if APopupAbove then
    begin
      ptAnchor := TPoint.Create(rcTarget.Left, rcTarget.Top);
      XWnd_ClientToScreen(hTargetWindow, ptAnchor);
      x := ptAnchor.X + (targetW - popupW) div 2;
      y := ptAnchor.Y - popupH - HintTargetGap;
    end
    else
    begin
      ptAnchor := TPoint.Create(rcTarget.Left, rcTarget.Bottom);
      XWnd_ClientToScreen(hTargetWindow, ptAnchor);
      x := ptAnchor.X + (targetW - popupW) div 2;
      y := ptAnchor.Y + HintTargetGap;
    end;
    Inc(y, AOffsetY);
  end
  else
  begin
    Windows.GetCursorPos(pt);
    x := pt.X + 14;
    y := pt.Y + 18;
  end;

  XWnd_SetPosition(dlg.Handle, x, y);
  XWnd_ShowWindow(dlg.Handle, SW_SHOWNOACTIVATE);
  FIsVisible := True;
  FLastTargetHandle := ATargetComponentHandle;
  FLastText := AText;
end;

class procedure THintPopupUI.BindHoverHint(const ATargetComponentHandle: Integer; const AText: string);
var
  hintIndex: Integer;
  hintKey: string;
begin
  if ATargetComponentHandle = 0 then
    Exit;
  if FHoverHintMap = nil then
  begin
    FHoverHintMap := TStringList.Create;
    FHoverHintMap.NameValueSeparator := '=';
  end;
  hintKey := IntToStr(ATargetComponentHandle);
  hintIndex := FHoverHintMap.IndexOfName(hintKey);
  if hintIndex >= 0 then
    FHoverHintMap.ValueFromIndex[hintIndex] := AText
  else
  begin
    FHoverHintMap.Add(hintKey + '=' + AText);
    XEle_RegEvent(ATargetComponentHandle, XE_MOUSEMOVE, @THintPopupUI.OnTargetMouseMove);
    XEle_RegEvent(ATargetComponentHandle, XE_MOUSELEAVE, @THintPopupUI.OnTargetMouseLeave);
  end;
end;

class procedure THintPopupUI.Hide;
begin
  if Assigned(FInstance) and FInstance.IsHWINDOW then
    XWnd_ShowWindow(FInstance.Handle, SW_HIDE);
  FIsVisible := False;
  FLastTargetHandle := 0;
  FLastText := '';
end;

initialization
  THintPopupUI.FHoverHintMap := nil;
  THintPopupUI.FIsVisible := False;
  THintPopupUI.FLastTargetHandle := 0;
  THintPopupUI.FLastText := '';

finalization
  FreeAndNil(THintPopupUI.FHoverHintMap);

end.
