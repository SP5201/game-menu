unit UI_SidebarGrip;

interface

uses
  Windows, XCGUI, XElement, UI_Ele;

type
  TSidebarGripUI = class(TEleUI)
  private
    class var
      CHostWnd: HWINDOW;
      CSidebar: HELE;
      CSizing: Boolean;
      CHovered: Boolean;
      CDragStartW: Integer;
      CDragStartWndX: Integer;
      CMinSidebarW: Integer;
      CMaxSidebarW: Integer;
      CMinMainContentW: Integer;
    class function OnLDown(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnLUp(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnMove(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnMouseStay(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnMouseLeave(hEle: HELE; hEleStay: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnPaint(hEle: HELE; hDraw: Integer; pbHandled: PBOOL): Integer; stdcall; static;
  public
    procedure Attach(const ASidebar: HELE; const AHostWnd: HWINDOW;
      const AMinSidebarW: Integer = 120; const AMaxSidebarW: Integer = 560; const AMinMainContentW: Integer = 240);
  end;

implementation

uses
  Math, UI_Theme;



procedure TSidebarGripUI.Attach(const ASidebar: HELE; const AHostWnd: HWINDOW;
  const AMinSidebarW: Integer = 120; const AMaxSidebarW: Integer = 560; const AMinMainContentW: Integer = 240);
begin
  CSidebar := ASidebar;
  CHostWnd := AHostWnd;
  CMinSidebarW := AMinSidebarW;
  CMaxSidebarW := AMaxSidebarW;
  CMinMainContentW := AMinMainContentW;
  CSizing := False;
  CHovered := False;
  SetCursor(LoadCursor(0, IDC_SIZEWE));
  RegEvent(XE_PAINT, @TSidebarGripUI.OnPaint);
  RegEvent(XE_LBUTTONDOWN, @TSidebarGripUI.OnLDown);
  RegEvent(XE_LBUTTONUP, @TSidebarGripUI.OnLUp);
  RegEvent(XE_MOUSEMOVE, @TSidebarGripUI.OnMove);
  RegEvent(XE_MOUSESTAY, @TSidebarGripUI.OnMouseStay);
  RegEvent(XE_MOUSELEAVE, @TSidebarGripUI.OnMouseLeave);
end;

class function TSidebarGripUI.OnLDown(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer;
var
  ptWnd: TPoint;
begin
  Result := 0;
  CSizing := True;
    pbHandled^ := True;
  CDragStartW := XEle_GetWidth(CSidebar);
  if XWnd_GetCursorPos(CHostWnd, ptWnd) then
    CDragStartWndX := ptWnd.X
  else
    CDragStartWndX := 0;
  XEle_SetCapture(hEle, True);
end;

class function TSidebarGripUI.OnLUp(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer;
begin
  Result := 0;
  if CSizing then
  begin
    CSizing := False;
    XEle_SetCapture(hEle, False);
  end;
  pbHandled^ := True;
end;

class function TSidebarGripUI.OnMove(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer;
var
  ptWnd: TPoint;
  rc: TRect;
  nW: Integer;
begin
  Result := 0;
  if not CSizing then
    Exit;
  if not XWnd_GetCursorPos(CHostWnd, ptWnd) then
    Exit;
  nW := EnsureRange(CDragStartW + (ptWnd.X - CDragStartWndX), CMinSidebarW, CMaxSidebarW);
  if XWnd_GetClientRect(CHostWnd, rc) then
    nW := Min(nW, Max(rc.Width - CMinMainContentW, CMinSidebarW));
  XWidget_LayoutItem_SetWidth(CSidebar, layout_size_fixed, nW);
  XWnd_AdjustLayout(CHostWnd);
  XWnd_Redraw(CHostWnd);
    pbHandled^ := True;
end;

class function TSidebarGripUI.OnMouseStay(hEle: HELE; pbHandled: PBOOL): Integer;
begin
  Result := 0;
  CHovered := True;
  XEle_Redraw(hEle);
  pbHandled^ := True;
end;

class function TSidebarGripUI.OnMouseLeave(hEle: HELE; hEleStay: HELE; pbHandled: PBOOL): Integer;
begin
  Result := 0;
  CHovered := False;
  XEle_Redraw(hEle);
  pbHandled^ := True;
end;

class function TSidebarGripUI.OnPaint(hEle: HELE; hDraw: Integer; pbHandled: PBOOL): Integer;
var
  rc: TRect;
  nH, nLineW, xLine: Integer;
begin
  Result := 0;
  pbHandled^ := True;
  XEle_GetClientRect(hEle, rc);
  nH := rc.Height;
  if nH <= 0 then
    Exit;
  if CHovered then
    nLineW := rc.Width
  else
    nLineW := 1;
  nLineW := EnsureRange(nLineW, 1, rc.Width);
  xLine := rc.Left + (rc.Width - nLineW) div 2;
  XDraw_SetLineWidth(hDraw, nLineW);
  XDraw_SetBrushColor(hDraw, UITheme_SurfaceOutline);
  XDraw_DrawLine(hDraw, xLine, rc.Top, xLine, rc.Top + nH - 1);
end;

end.

