unit UI_Button;

interface

uses
  Windows, SysUtils, Generics.Collections, XCGUI, XButton, UI_Theme;

type
  TButtonPaintFlags = Cardinal;
  THWindowKey = HWINDOW;
  TMaxBtnEle = HELE;

  TButtonUI = class(TXBtn)
  private
    class var
      FButtonMap: TDictionary<HXCGUI, TButtonPaintFlags>;
      FMaxBtnByWnd: TDictionary<THWindowKey, TMaxBtnEle>;
    class function BtnHasCaption(const hBtn: XCGUI.HELE): Boolean; static;
    class function BtnGetSvg(const hBtn: XCGUI.HELE; out hSvgIcon: HSVG; out SvgW, SvgH: Integer): Boolean; static;
    class procedure ApplyButtonSvgIcon(const hBtn: XCGUI.HELE; const SvgFile: PWideChar; const SvgWidth, SvgHeight: Integer); static;
    class function NeedsCustomPaint(const Flags: TButtonPaintFlags; const SvgLoaded: Boolean; const hBtn: XCGUI.HELE): Boolean; static;
    class procedure EnsureMaxBtnMap; static;
    class function ResolveMaxButton(const hWindow: THWindowKey): HELE; static;
  protected
    procedure Init; override;
    class function GetPaintFlagsOfHandle(const hBtn: XCGUI.HELE): TButtonPaintFlags; static;
    procedure SetPaintFlagsOfHandle(const hBtn: XCGUI.HELE; const Flags: TButtonPaintFlags);
    class function OnBtnPaint(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnDestroy(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    procedure ApplyPaintFlags(const PaintFlags: TButtonPaintFlags; const SvgFile: PWideChar; const SvgWidth: Integer; const SvgHeight: Integer);
  public
    class function FromXmlName(const XmlName: string; const PaintFlags: TButtonPaintFlags; const SvgFile: PWideChar = nil; const SvgWidth: Integer = 16; const SvgHeight: Integer = 16): TButtonUI; reintroduce;
    class function FormHandle(const hBtn: XCGUI.HELE; const PaintFlags: TButtonPaintFlags; const SvgFile: PWideChar = nil; const SvgWidth: Integer = 16; const SvgHeight: Integer = 16): TButtonUI;
    procedure SetSvgFile(const SvgFile: PWideChar);
    class procedure BindMaxButton(const hWindow: THWindowKey; const hBtn: XCGUI.HELE); static;
    class procedure SetMaxButtonSvg(const hWindow: THWindowKey; const AMaximized: Boolean); static;
    class procedure SyncMaxButtonSvg(const hWindow: THWindowKey); static;
    destructor Destroy; override;
  end;

const
  cBtnSvgMax = 'Resource\max.svg';
  cBtnSvgRestore = 'Resource\restore.svg';
  BB_NONE = 0;
  /// 启用边框
  BB_EnableBorder = $00000001;
  /// 启用高亮背景（主色圆角填充）
  BB_EnableHighlightBk = $00000002;
  /// 启用普通背景（浅白圆角填充）
  BB_EnableNormalBk = $00000004;
  /// 启用多选样式（圆角框 + 勾选）
  BB_EnableCheckStyle = $00000008;

implementation

class function TButtonUI.BtnHasCaption(const hBtn: XCGUI.HELE): Boolean;
var
  p: PWideChar;
begin
  p := XBtn_GetText(hBtn);
  Result := (p <> nil) and (p^ <> #0);
end;

class function TButtonUI.BtnGetSvg(const hBtn: XCGUI.HELE; out hSvgIcon: HSVG; out SvgW, SvgH: Integer): Boolean;
var
  hBtnIcon: HIMAGE;
begin
  hSvgIcon := 0;
  SvgW := 0;
  SvgH := 0;
  hBtnIcon := XBtn_GetIcon(hBtn, 0);
  if XC_GetObjectType(hBtnIcon) <> XC_IMAGE then
    Exit(False);
  hSvgIcon := XImage_GetSvg(hBtnIcon);
  Result := XC_GetObjectType(hSvgIcon) = XC_SVG;
  if Result then
    XSvg_GetSize(hSvgIcon, SvgW, SvgH);
end;

class procedure TButtonUI.ApplyButtonSvgIcon(const hBtn: XCGUI.HELE; const SvgFile: PWideChar; const SvgWidth, SvgHeight: Integer);
var
  hSvgIcon: HSVG;
  hBtnIcon: HIMAGE;
  nW, nH: Integer;
begin
  if (SvgFile = nil) or (SvgFile^ = #0) then
    Exit;
  hSvgIcon := XSvg_LoadFile(SvgFile);
  if XC_GetObjectType(hSvgIcon) <> XC_SVG then
    Exit;
  nW := SvgWidth;
  nH := SvgHeight;
  if nW <= 0 then
    nW := 16;
  if nH <= 0 then
    nH := 16;
  XSvg_SetUserFillColor(hSvgIcon, UITheme_IconFill, True);
  XSvg_SetUserStrokeColor(hSvgIcon, UITheme_IconFill, 1, True);
  XSvg_SetSize(hSvgIcon, nW, nH);
  hBtnIcon := XImage_LoadSvg(hSvgIcon);
  if XC_GetObjectType(hBtnIcon) = XC_IMAGE then
    XBtn_SetIcon(hBtn, hBtnIcon);
end;

class function TButtonUI.NeedsCustomPaint(const Flags: TButtonPaintFlags; const SvgLoaded: Boolean; const hBtn: XCGUI.HELE): Boolean;
begin
  Result := SvgLoaded or ((Flags and (BB_EnableBorder or BB_EnableHighlightBk or BB_EnableNormalBk or BB_EnableCheckStyle)) <> 0);
  if not Result and (hBtn <> 0) then
    Result := BtnHasCaption(hBtn);
end;

class function TButtonUI.FormHandle(const hBtn: XCGUI.HELE; const PaintFlags: TButtonPaintFlags; const SvgFile: PWideChar = nil; const SvgWidth: Integer = 16; const SvgHeight: Integer = 16): TButtonUI;
begin
  Result := TButtonUI(TButtonUI.FromHandle(hBtn));
  Result.ApplyPaintFlags(PaintFlags, SvgFile, SvgWidth, SvgHeight);
end;

class function TButtonUI.FromXmlName(const XmlName: string; const PaintFlags: TButtonPaintFlags; const SvgFile: PWideChar = nil; const SvgWidth: Integer = 16; const SvgHeight: Integer = 16): TButtonUI;
begin
  Result := TButtonUI(inherited FromXmlName(XmlName));
  Result.ApplyPaintFlags(PaintFlags, SvgFile, SvgWidth, SvgHeight);
end;

procedure TButtonUI.Init;
begin
  inherited;
  EnableBkTransparent(True);
  SetCursor(LoadCursor(0, IDC_HAND));
end;

destructor TButtonUI.Destroy;
begin
  if Assigned(FButtonMap) then
    FButtonMap.Remove(Handle);
  inherited;
end;

class function TButtonUI.GetPaintFlagsOfHandle(const hBtn: XCGUI.HELE): TButtonPaintFlags;
begin
  if Assigned(FButtonMap) and FButtonMap.TryGetValue(hBtn, Result) then
    Exit;
  Result := BB_EnableNormalBk;
end;

procedure TButtonUI.SetPaintFlagsOfHandle(const hBtn: XCGUI.HELE; const Flags: TButtonPaintFlags);
begin
  if Assigned(FButtonMap) then
    FButtonMap.AddOrSetValue(hBtn, Flags);
end;

procedure TButtonUI.ApplyPaintFlags(const PaintFlags: TButtonPaintFlags; const SvgFile: PWideChar; const SvgWidth: Integer; const SvgHeight: Integer);
var
  hSvgIcon: HSVG;
  svgW, svgH: Integer;
  SvgLoaded: Boolean;
  useCustomPaint: Boolean;
begin
  SetPaintFlagsOfHandle(Handle, PaintFlags);
  RegEvent(XE_DESTROY, @TButtonUI.OnBtnDestroy);
  ApplyButtonSvgIcon(Handle, SvgFile, SvgWidth, SvgHeight);

  SvgLoaded := BtnGetSvg(Handle, hSvgIcon, svgW, svgH);
  useCustomPaint := NeedsCustomPaint(PaintFlags, SvgLoaded, Handle);
  if useCustomPaint then
    RegEvent(XE_PAINT, @TButtonUI.OnBtnPaint);

  if not useCustomPaint then
    EnableBkTransparent(False);
end;

procedure TButtonUI.SetSvgFile(const SvgFile: PWideChar);
begin
  ApplyButtonSvgIcon(Handle, SvgFile, 16, 16);
  XEle_Redraw(Handle);
end;

class procedure TButtonUI.EnsureMaxBtnMap;
begin
  if FMaxBtnByWnd = nil then
    FMaxBtnByWnd := TDictionary<THWindowKey, TMaxBtnEle>.Create;
end;

class function TButtonUI.ResolveMaxButton(const hWindow: THWindowKey): HELE;
begin
  Result := 0;
  if (FMaxBtnByWnd <> nil) and FMaxBtnByWnd.TryGetValue(hWindow, Result) then
    Exit;
  Result := XWnd_GetButton(hWindow, button_type_max);
end;

class procedure TButtonUI.SetMaxButtonSvg(const hWindow: THWindowKey; const AMaximized: Boolean);
var
  hBtn: HELE;
  btnUi: TButtonUI;
begin
  if not XC_IsHWINDOW(hWindow) then
    Exit;
  hBtn := ResolveMaxButton(hWindow);
  if XC_GetObjectType(hBtn) <> XC_BUTTON then
    Exit;
  btnUi := TButtonUI(TButtonUI.FromHandle(hBtn));
  if AMaximized then
    btnUi.SetSvgFile(cBtnSvgRestore)
  else
    btnUi.SetSvgFile(cBtnSvgMax);
end;

class procedure TButtonUI.SyncMaxButtonSvg(const hWindow: THWindowKey);
var
  hWndReal: Windows.HWND;
begin
  if not XC_IsHWINDOW(hWindow) then
    Exit;
  hWndReal := XWnd_GetHWND(hWindow);
  SetMaxButtonSvg(hWindow, IsZoomed(hWndReal));
end;

class procedure TButtonUI.BindMaxButton(const hWindow: THWindowKey; const hBtn: XCGUI.HELE);
begin
  if (not XC_IsHWINDOW(hWindow)) or (XC_GetObjectType(hBtn) <> XC_BUTTON) then
    Exit;
  EnsureMaxBtnMap;
  FMaxBtnByWnd.AddOrSetValue(hWindow, hBtn);
end;

class function TButtonUI.OnBtnDestroy(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;

  if Assigned(FButtonMap) then
    FButtonMap.Remove(hEle);
end;

class function TButtonUI.OnBtnPaint(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall;
var
  F: TButtonPaintFlags;
  hSvgIcon: HSVG;
  svgW, svgH: Integer;
  pText: PWideChar;
  rcClient: TRect;
  wClient, hClient: Integer;
  xDraw, yDraw: Integer;
  nRadius: Integer;
  nStateEx: Integer;
  bHover: Boolean;
  bSvg: Boolean;
  bBkHighlight: Boolean;
  bBkNormal: Boolean;
  bCheckStyle: Boolean;
  bChecked: Boolean;
  rcBox: TRect;
  rcText: TRect;
  nBoxSize: Integer;

begin
  Result := 0;
  pbHandled^ := True;

  F := TButtonUI.GetPaintFlagsOfHandle(hEle);
  bSvg := BtnGetSvg(hEle, hSvgIcon, svgW, svgH);
  bBkHighlight := (F and BB_EnableHighlightBk) <> 0;
  bBkNormal := (F and BB_EnableNormalBk) <> 0;
  bCheckStyle := (F and BB_EnableCheckStyle) <> 0;
  bChecked := XBtn_IsCheck(hEle);

  XEle_GetClientRect(hEle, rcClient);
  nRadius := 4;

  if bBkHighlight or bBkNormal then
  begin
    nStateEx := XBtn_GetStateEx(hEle);
    bHover := (nStateEx = button_state_stay) or (nStateEx = button_state_down);
    if bBkHighlight then
    begin
      if bHover then
        XDraw_SetBrushColor(hDraw, UITheme_ButtonHighlightBkHover)
      else
        XDraw_SetBrushColor(hDraw, UITheme_ButtonHighlightBk);
    end
    else
    begin
      if bHover then
        XDraw_SetBrushColor(hDraw, UITheme_ButtonNormalBkHover)
      else
        XDraw_SetBrushColor(hDraw, UITheme_ButtonNormalBk);
    end;
    XDraw_FillRoundRect(hDraw, rcClient, nRadius, nRadius);
  end;

  if bSvg then
  begin
    wClient := rcClient.Width;
    hClient := rcClient.Height;
    xDraw := rcClient.Left + (wClient - svgW) div 2;
    yDraw := rcClient.Top + (hClient - svgH) div 2;
    XSvg_SetUserFillColor(hSvgIcon, UITheme_IconFill, True);
    XSvg_SetUserStrokeColor(hSvgIcon, UITheme_IconFill, 1, True);
    XDraw_DrawSvgEx(hDraw, hSvgIcon, xDraw, yDraw, svgW, svgH);
  end;

  if bCheckStyle then
  begin
    nBoxSize := 16;
    rcBox.Left := rcClient.Left;
    rcBox.Top := rcClient.Top + (rcClient.Height - nBoxSize) div 2 + 1;
    rcBox.Right := rcBox.Left + nBoxSize;
    rcBox.Bottom := rcBox.Top + nBoxSize;

    if bChecked then
    begin
      XDraw_SetBrushColor(hDraw, UITheme_ButtonHighlightBk);
      XDraw_FillRoundRect(hDraw, rcBox, 3, 3);
      XDraw_SetBrushColor(hDraw, UITheme_BorderDefault);
      XDraw_DrawRoundRect(hDraw, rcBox, 3, 3);
      XDraw_SetLineWidth(hDraw, 2);
      XDraw_SetBrushColor(hDraw, UITheme_CheckMark);
      XDraw_DrawLine(hDraw, rcBox.Left + 3, rcBox.Top + 8, rcBox.Left + 7, rcBox.Top + 12);
      XDraw_DrawLine(hDraw, rcBox.Left + 7, rcBox.Top + 12, rcBox.Left + 13, rcBox.Top + 5);
      XDraw_SetLineWidth(hDraw, 1);
    end
    else
    begin
      XDraw_SetBrushColor(hDraw, UITheme_BorderDefault);
      XDraw_DrawRoundRect(hDraw, rcBox, 3, 3);
    end;
  end;

  pText := XBtn_GetText(hEle);
  if (pText <> nil) and (pText^ <> #0) then
  begin
    rcText := rcClient;
    if bCheckStyle then
    begin
      rcText.Left := rcBox.Right + 8;
      XDraw_SetTextAlign(hDraw, Integer(textAlignFlag_left) or Integer(textAlignFlag_vcenter) or DT_SINGLELINE);
    end
    else
      XDraw_SetTextAlign(hDraw, Integer(textAlignFlag_center) or Integer(textAlignFlag_vcenter) or DT_SINGLELINE);
    XDraw_SetBrushColor(hDraw, UITheme_TextPrimary);
    XDraw_DrawText(hDraw, pText, -1, rcText);
  end;

  if (F and BB_EnableBorder) <> 0 then
  begin
    XDraw_SetLineWidth(hDraw, 1);
    XDraw_SetBrushColor(hDraw, UITheme_BorderDefault);
    XDraw_DrawRoundRect(hDraw, rcClient, nRadius, nRadius);
  end;
end;

initialization
  TButtonUI.FButtonMap := TDictionary<HXCGUI, TButtonPaintFlags>.Create;

finalization
  FreeAndNil(TButtonUI.FMaxBtnByWnd);
  TButtonUI.FButtonMap.Free;

end.
