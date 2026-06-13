unit UI_Form;

interface

uses
  Windows, Messages, SysUtils, XCGUI, XForm, UI_Theme, UI_Button;

type
  TFormUI = class(TXForm)
  private
    class var
      FModalStack: array of HWINDOW;
    class function OnWndPaint(hWindow: hWindow; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnWndWinProc(hWindow: Integer; Msg: UINT; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
    class procedure UnregisterModal(hWindow: HWINDOW); static;
  public
    procedure ApplyDefault;
    destructor Destroy; override;
    class function LoadLayout(const LayoutFile: PWideChar): TFormUI;
    class function TopModal: HWINDOW; static;
    class procedure ReleaseModalStack; static;
    class procedure HandleWndSize(const hWindow: Integer; const Msg: UINT; const wParam: WPARAM); static;
    class procedure ApplyTitleLogo(const ALogoXmlName: string; ALogoSide: Integer = 20); static;
  protected
    procedure Init; override;
  end;

implementation

uses
  ShellHelper;

class procedure TFormUI.ApplyTitleLogo(const ALogoXmlName: string; ALogoSide: Integer);
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
  hLogo := XC_GetObjectByName(PWideChar(ALogoXmlName));
  if XC_GetObjectType(hLogo) = XC_SHAPE_PICTURE then
  begin
    hLogoImg := LoadApplicationIconToHImage(logoSide, logoSide);
    if XC_GetObjectType(hLogoImg) = XC_IMAGE then
      XShapePic_SetImage(hLogo, hLogoImg);
  end;
end;

class procedure TFormUI.UnregisterModal(hWindow: hWindow);
var
  i, j: Integer;
begin
  for i := 0 to High(FModalStack) do
    if XC_GetObjectType(FModalStack[i]) = XC_MODALWINDOW then
    begin
      for j := i to High(FModalStack) - 1 do
        FModalStack[j] := FModalStack[j + 1];
      SetLength(FModalStack, Length(FModalStack) - 1);
      Break;
    end;
end;

class function TFormUI.TopModal: HWINDOW;
begin
  if Length(FModalStack) > 0 then
    Result := FModalStack[High(FModalStack)]
  else
    Result := 0;
end;

class procedure TFormUI.ReleaseModalStack;
var
  h: Integer;
  n: Integer;
begin
  n := 0;
  while (Length(FModalStack) > 0) and (n < 512) do
  begin
    h := TopModal;
    if h = 0 then
      Break;
    XModalWnd_EndModal(h, IDCANCEL);
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

destructor TFormUI.Destroy;
begin
  UnregisterModal(Handle);
  inherited;
end;

class function TFormUI.LoadLayout(const LayoutFile: PWideChar): TFormUI;
var
  h: HXCGUI;
begin
  h := XC_LoadLayout(LayoutFile, 0, 0);
  if h = 0 then
    Exit(nil);
  Result := TFormUI.FromHandle(h);
end;

class procedure TFormUI.HandleWndSize(const hWindow: Integer; const Msg: UINT; const wParam: WPARAM);
begin
  if Msg <> WM_SIZE then
    Exit;
  if wParam = SIZE_MAXIMIZED then
    TButtonUI.SetMaxButtonSvg(hWindow, True)
  else if wParam = SIZE_RESTORED then
    TButtonUI.SetMaxButtonSvg(hWindow, False);
end;

class function TFormUI.OnWndWinProc(hWindow: Integer; Msg: UINT; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  HandleWndSize(hWindow, Msg, wParam);
end;

class function TFormUI.OnWndPaint(hWindow: hWindow; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
  nRadius: Integer;
  colorBk: Integer;
  hWndReal: Integer;
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
