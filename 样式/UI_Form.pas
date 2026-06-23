unit UI_Form;

interface

uses
  Windows, Messages, SysUtils, XCGUI, XForm, UI_Theme, UI_Button;

type
  TFormUI = class(TXForm)
  private
    class var
      FModalStack: array of XCGUI.HWINDOW;
    class function OnWndPaint(hWindow: XCGUI.HWINDOW; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnWndWinProc(hWindow: XCGUI.HWINDOW; Msg: UINT; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
    class procedure UnregisterModal(hWindow: XCGUI.HWINDOW); static;
  public
    constructor CreateEx(dwExStyle, dwStyle: DWORD; lpClassName: PWideChar; x, y, cx, cy: Integer; pTitle: PWideChar; hWndParent: XCGUI.HWINDOW; XCStyle: Integer); reintroduce;
    procedure ApplyDefault;
    destructor Destroy; override;
    class function LoadLayoutFile(const LayoutFile: PWideChar; hParent: HXCGUI = 0; hAttachWnd: XCGUI.HWINDOW = 0): HXCGUI; static;
    class function TopModal: XCGUI.HWINDOW; static;
    function GetNamed(const AName: string): HXCGUI;
    class procedure ReleaseModalStack; static;
    class procedure HandleWndSize(const hWindow: XCGUI.HWINDOW; const Msg: UINT; const wParam: WPARAM); static;
    procedure ApplyTitleLogo(const ALogoXmlName: string; ALogoSide: Integer = 20);
    procedure SetupDialogChrome(const ALogoXmlName: string; const ACloseBtnXmlName: string = ''; ALogoSide: Integer = 20);
    class procedure EndModalCancel(hEle: XCGUI.HELE); static;
    class procedure EndModalOk(hEle: XCGUI.HELE); static;
    class procedure EndModalCancelWnd(hWindow: XCGUI.HWINDOW); static;
    class procedure EndModalOkWnd(hWindow: XCGUI.HWINDOW); static;
    class function IsKeyFirstPress(lParam: LPARAM): Boolean; static;
    class function HandleModalKeyEscape(hWindow: XCGUI.HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL; ACheckRepeat: Boolean = False): Boolean; static;
    class function OnBtnModalCancel(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnModalOk(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnModalWndKeyDownEscape(hWindow: XCGUI.HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
    procedure RegModalEscape;
  protected
    procedure Init; override;
  end;

implementation

uses
  ShellIconHelper;

function TFormUI.GetNamed(const AName: string): HXCGUI;
var
  h: HXCGUI;
begin
  Result := 0;
  if Trim(AName) = '' then
    Exit;
  h := XC_GetObjectByName(PWideChar(AName));
  if XC_GetObjectType(h) = XC_ERROR then
    Exit;
  if IsHWINDOW and (XWidget_GetHWINDOW(h) <> Handle) then
    Exit;
  Result := h;
end;

procedure TFormUI.ApplyTitleLogo(const ALogoXmlName: string; ALogoSide: Integer);
var
  hLogo: HXCGUI;
  hLogoImg: HIMAGE;
  logoSide: Integer;
begin
  if Trim(ALogoXmlName) = '' then
    Exit;
  logoSide := ALogoSide;
  if logoSide < 1 then
    logoSide := 20;
  hLogo := GetNamed(ALogoXmlName);
  if XC_GetObjectType(hLogo) = XC_SHAPE_PICTURE then
  begin
    hLogoImg := LoadApplicationIconToHImage(logoSide, logoSide);
    if XC_GetObjectType(hLogoImg) = XC_IMAGE then
      XShapePic_SetImage(hLogo, hLogoImg);
  end;
end;

procedure TFormUI.SetupDialogChrome(const ALogoXmlName: string; const ACloseBtnXmlName: string; ALogoSide: Integer);
var
  hClose: HXCGUI;
begin
  ApplyTitleLogo(ALogoXmlName, ALogoSide);
  if Trim(ACloseBtnXmlName) = '' then
    Exit;
  hClose := GetNamed(ACloseBtnXmlName);
  if XC_GetObjectType(hClose) = XC_BUTTON then
    TButtonUI.FormHandle(hClose, BB_NONE, 'Resource\close.svg')
      .RegEvent(XE_BNCLICK, @TFormUI.OnBtnModalCancel);
end;

class procedure TFormUI.UnregisterModal(hWindow: XCGUI.HWINDOW);
var
  i, j: Integer;
begin
  for i := 0 to High(FModalStack) do
    if FModalStack[i] = hWindow then
    begin
      for j := i to High(FModalStack) - 1 do
        FModalStack[j] := FModalStack[j + 1];
      SetLength(FModalStack, Length(FModalStack) - 1);
      Break;
    end;
end;

class function TFormUI.TopModal: XCGUI.HWINDOW;
begin
  if Length(FModalStack) > 0 then
    Result := FModalStack[High(FModalStack)]
  else
    Result := 0;
end;

class procedure TFormUI.ReleaseModalStack;
var
  hModalWnd: XCGUI.HWINDOW;
  n: Integer;
begin
  n := 0;
  while (Length(FModalStack) > 0) and (n < 512) do
  begin
    hModalWnd := TopModal;
    if not XC_IsHWINDOW(hModalWnd) then
      Break;
    XModalWnd_EndModal(hModalWnd, IDCANCEL);
    Inc(n);
  end;
  SetLength(FModalStack, 0);
end;

procedure TFormUI.Init;
begin
  inherited;
  ApplyDefault;
  if XC_GetObjectType(Handle) = XC_MODALWINDOW then
  begin
    SetLength(FModalStack, Length(FModalStack) + 1);
    FModalStack[High(FModalStack)] := Handle;
  end;
end;

constructor TFormUI.CreateEx(dwExStyle, dwStyle: DWORD; lpClassName: PWideChar; x, y, cx, cy: Integer; pTitle: PWideChar; hWndParent: XCGUI.HWINDOW; XCStyle: Integer);
var
  hParentWnd: Windows.HWND;
begin
  if hWndParent <> 0 then
    hParentWnd := XWnd_GetHWND(hWndParent)
  else
    hParentWnd := 0;
  inherited CreateEx(dwExStyle, dwStyle, lpClassName, x, y, cx, cy, pTitle, hParentWnd, XCStyle);
end;

destructor TFormUI.Destroy;
begin
  UnregisterModal(Handle);
  inherited;
end;

class function TFormUI.LoadLayoutFile(const LayoutFile: PWideChar; hParent: HXCGUI; hAttachWnd: XCGUI.HWINDOW): HXCGUI;
begin
  Result := XC_LoadLayout(LayoutFile, hParent, hAttachWnd);
end;

class procedure TFormUI.EndModalCancel(hEle: XCGUI.HELE);
begin
  XModalWnd_EndModal(XWidget_GetHWINDOW(hEle), IDCANCEL);
end;

class procedure TFormUI.EndModalOk(hEle: XCGUI.HELE);
begin
  XModalWnd_EndModal(XWidget_GetHWINDOW(hEle), IDOK);
end;

class procedure TFormUI.EndModalCancelWnd(hWindow: XCGUI.HWINDOW);
begin
  XModalWnd_EndModal(hWindow, IDCANCEL);
end;

class procedure TFormUI.EndModalOkWnd(hWindow: XCGUI.HWINDOW);
begin
  XModalWnd_EndModal(hWindow, IDOK);
end;

class function TFormUI.IsKeyFirstPress(lParam: LPARAM): Boolean;
begin
  Result := (lParam and $40000000) = 0;
end;

class function TFormUI.HandleModalKeyEscape(hWindow: XCGUI.HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL; ACheckRepeat: Boolean): Boolean;
begin
  Result := False;
  if wParam <> VK_ESCAPE then
    Exit;
  if ACheckRepeat and not IsKeyFirstPress(lParam) then
    Exit;
  pbHandled^ := True;
  EndModalCancelWnd(hWindow);
  Result := True;
end;

class function TFormUI.OnBtnModalCancel(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  EndModalCancel(hEle);
end;

class function TFormUI.OnBtnModalOk(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  EndModalOk(hEle);
end;

class function TFormUI.OnModalWndKeyDownEscape(hWindow: XCGUI.HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  HandleModalKeyEscape(hWindow, wParam, lParam, pbHandled);
end;

procedure TFormUI.RegModalEscape;
begin
  if IsHWINDOW then
    RegEvent(WM_KEYDOWN, @TFormUI.OnModalWndKeyDownEscape);
end;

class procedure TFormUI.HandleWndSize(const hWindow: XCGUI.HWINDOW; const Msg: UINT; const wParam: WPARAM);
begin
  if Msg <> WM_SIZE then
    Exit;
  if wParam = SIZE_MAXIMIZED then
    TButtonUI.SetMaxButtonSvg(hWindow, True)
  else if wParam = SIZE_RESTORED then
    TButtonUI.SetMaxButtonSvg(hWindow, False);
end;

class function TFormUI.OnWndWinProc(hWindow: XCGUI.HWINDOW; Msg: UINT; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  HandleWndSize(hWindow, Msg, wParam);
end;

class function TFormUI.OnWndPaint(hWindow: XCGUI.HWINDOW; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
  nRadius: Integer;
  colorBk: Integer;
  hWndReal: Windows.HWND;
  isMaximized: Boolean;
begin
  Result := 0;
  XDraw_EnableSmoothingMode(hDraw, True);

  XWnd_GetClientRect(hWindow, rc);
  hWndReal := XWnd_GetHWND(hWindow);

  nRadius := UITheme_WindowCornerRadius;
  colorBk := UITheme_SurfaceBase;
  isMaximized := IsZoomed(hWndReal);

  XDraw_SetBrushColor(hDraw, colorBk);
  if isMaximized then
    XDraw_FillRect(hDraw, rc)
  else
    XDraw_FillRoundRect(hDraw, rc, nRadius, nRadius);

  if not isMaximized then
  begin
    XDraw_SetLineWidth(hDraw, 1);
    XDraw_SetBrushColor(hDraw, UITheme_SurfaceOutline);
    XDraw_DrawRoundRect(hDraw, rc, nRadius, nRadius);
  end;

  pbHandled^ := True;
end;

procedure TFormUI.ApplyDefault;
begin
  if IsHWINDOW then
  begin
    RegEvent(WM_PAINT, @TFormUI.OnWndPaint);
    RegEvent(XWM_WINDPROC, @TFormUI.OnWndWinProc);
    SetPadding(5, 0, 5, 5);
    SetDragBorderSize(
      UITheme_WindowDragBorderSize, 0,
      UITheme_WindowDragBorderSize, UITheme_WindowDragBorderSize);
    SetTransparentType(window_transparent_shadow);
    SetTransparentAlpha(UITheme_WindowAlpha);
    SetShadowInfo(13, 200, UITheme_WindowCornerRadius, False, UITheme_ShadowDefault);
  end;
end;

end.
