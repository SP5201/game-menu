unit UI_PopupAnimation;

{
  Win11 弹出动画：每帧按 rcFinal 左上角 + 宽高插值 SetRect，保证左上锚点固定。
  进度驱动对齐 Test 中 XAnimaItem_SetCallback + DelayEx。
}

interface

uses
  Windows, Types, Math, XCGUI;

const
  { 相对设计稿 200ms，主菜单加速 3 倍；子菜单无 stagger、时长更短 }
  UI_POPUP_ANIM_ENTER_MS_DEFAULT = 67;
  UI_POPUP_ANIM_ENTER_MS_SUBMENU = 20;
  UI_POPUP_ANIM_TRANSLATE_LOGICAL_PX = 10;
  UI_POPUP_ANIM_SCALE_START = 0.85;
  UI_POPUP_ANIM_SCALE_OVERSHOOT = 1.02;

  UI_POSITION_FLAG_LEFT_TOP = 4;

procedure UIPopupAnim_SetLastMenuPopupPosition(const nPosition: Integer);
function UIPopupAnim_GetLastMenuPopupPosition: Integer;
function UIPopupAnim_IsSystemAnimationEnabled: Boolean;
procedure UIPopupAnim_OnMenuPopupWindow(const hPopupWnd: HWINDOW; const nParentItemId: Integer;
  const rcFinal: TRect);
procedure UIPopupAnim_OnMenuExit;

implementation

type
  PPopupAnimEnterCtx = ^TPopupAnimEnterCtx;
  TPopupAnimEnterCtx = record
    hPopupWnd: HWINDOW;
    rcFinal: TRect;
    wFinal: Integer;
    hFinal: Integer;
    dyPx: Integer;
  end;

  TPopupAnimSlot = record
    hPopupWnd: HWINDOW;
    hAnimSeq: HXCGUI;
    rcFinal: TRect;
    pEnterCtx: PPopupAnimEnterCtx;
  end;

const
  UI_POPUP_ANIM_MAX_SLOTS = 8;
  UI_POPUP_ANIM_LOOP_ONCE = 1;
  UI_POPUP_ANIM_ENTER_PHASE_A = 0.6;

var
  GPopupMenuPosition: Integer = menu_popup_position_left_top;
  GPopupAnimSlots: array[0..UI_POPUP_ANIM_MAX_SLOTS - 1] of TPopupAnimSlot;
  GPopupAnimSlotCount: Integer = 0;

function UIPopupAnim_IsSystemAnimationEnabled: Boolean;
var
  animOn: BOOL;
begin
  animOn := True;
  if SystemParametersInfo(SPI_GETANIMATION, 0, @animOn, 0) then
    Result := animOn
  else
    Result := True;
end;

procedure UIPopupAnim_SetLastMenuPopupPosition(const nPosition: Integer);
begin
  GPopupMenuPosition := nPosition;
end;

function UIPopupAnim_GetLastMenuPopupPosition: Integer;
begin
  Result := GPopupMenuPosition;
end;

function UIPopupAnim_LogicalYToPx(const hPopupWnd: HWINDOW; const logicalPx: Integer): Integer;
var
  nDpi: Integer;
begin
  nDpi := XWnd_GetDPI(hPopupWnd);
  if nDpi <= 0 then
    nDpi := 96;
  Result := MulDiv(logicalPx, nDpi, 96);
end;

function UIPopupAnim_EaseOutCubic(const t: Single): Single;
var
  u: Single;
begin
  if t <= 0 then
    Exit(0);
  if t >= 1 then
    Exit(1);
  u := t - 1;
  Result := u * u * u + 1;
end;

function UIPopupAnim_ScaleAtProgress(const t: Single): Single;
var
  u: Single;
begin
  if t <= 0 then
    Exit(UI_POPUP_ANIM_SCALE_START);
  if t >= 1 then
    Exit(1.0);
  if t < UI_POPUP_ANIM_ENTER_PHASE_A then
  begin
    u := t / UI_POPUP_ANIM_ENTER_PHASE_A;
    Result := UI_POPUP_ANIM_SCALE_START
      + (UI_POPUP_ANIM_SCALE_OVERSHOOT - UI_POPUP_ANIM_SCALE_START) * UIPopupAnim_EaseOutCubic(u);
  end
  else
  begin
    u := (t - UI_POPUP_ANIM_ENTER_PHASE_A) / (1.0 - UI_POPUP_ANIM_ENTER_PHASE_A);
    Result := UI_POPUP_ANIM_SCALE_OVERSHOOT + (1.0 - UI_POPUP_ANIM_SCALE_OVERSHOOT) * u;
  end;
end;

procedure UIPopupAnim_ApplyEnterFrame(const ctx: PPopupAnimEnterCtx; const progress: Single);
var
  rc: TRect;
  scaleVal: Single;
  yOff, wCur, hCur: Integer;
begin
  if (ctx = nil) or (not XC_IsHWINDOW(ctx^.hPopupWnd)) then
    Exit;
  if progress <= 0 then
    scaleVal := UI_POPUP_ANIM_SCALE_START
  else if progress >= 1 then
    scaleVal := 1.0
  else
    scaleVal := UIPopupAnim_ScaleAtProgress(progress);

  if progress <= 0 then
    yOff := ctx^.dyPx
  else if progress >= 1 then
    yOff := 0
  else
    yOff := Round(ctx^.dyPx * (1.0 - progress));

  wCur := Max(1, Round(ctx^.wFinal * scaleVal));
  hCur := Max(1, Round(ctx^.hFinal * scaleVal));

  rc.Left := ctx^.rcFinal.Left;
  rc.Top := ctx^.rcFinal.Top + yOff;
  rc.Right := rc.Left + wCur;
  rc.Bottom := rc.Top + hCur;
  XWnd_SetRect(ctx^.hPopupWnd, rc);
  XWnd_Redraw(ctx^.hPopupWnd);
end;

function UIPopupAnim_FindSlotIndex(const hPopupWnd: HWINDOW): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to GPopupAnimSlotCount - 1 do
    if GPopupAnimSlots[i].hPopupWnd = hPopupWnd then
      Exit(i);
end;

function UIPopupAnim_FindSlotByAnim(const hAnimSeq: HXCGUI): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to GPopupAnimSlotCount - 1 do
    if GPopupAnimSlots[i].hAnimSeq = hAnimSeq then
      Exit(i);
end;

procedure UIPopupAnim_FreeEnterCtx(var ctx: PPopupAnimEnterCtx);
begin
  if ctx <> nil then
  begin
    Dispose(ctx);
    ctx := nil;
  end;
end;

procedure UIPopupAnim_ApplyFinalRect(const idx: Integer);
begin
  if (idx < 0) or (idx >= GPopupAnimSlotCount) then
    Exit;
  if XC_IsHWINDOW(GPopupAnimSlots[idx].hPopupWnd) then
  begin
    XWnd_SetRect(GPopupAnimSlots[idx].hPopupWnd, GPopupAnimSlots[idx].rcFinal);
    XWnd_Redraw(GPopupAnimSlots[idx].hPopupWnd);
  end;
end;

procedure UIPopupAnim_OnEnterFrame(hAnimItem: HXCGUI; progress: Single); stdcall;
var
  ctx: PPopupAnimEnterCtx;
begin
  ctx := PPopupAnimEnterCtx(XAnimaItem_GetUserData(hAnimItem));
  UIPopupAnim_ApplyEnterFrame(ctx, progress);
end;

procedure UIPopupAnim_OnAnimaComplete(hAnimation: HXCGUI; nFlag: Integer); stdcall;
var
  idx: Integer;
  ctxNil: PPopupAnimEnterCtx;
begin
  idx := UIPopupAnim_FindSlotByAnim(hAnimation);
  if idx < 0 then
    Exit;
  UIPopupAnim_ApplyFinalRect(idx);
  ctxNil := GPopupAnimSlots[idx].pEnterCtx;
  UIPopupAnim_FreeEnterCtx(ctxNil);
  GPopupAnimSlots[idx].pEnterCtx := nil;
end;

procedure UIPopupAnim_ReleaseObjectAnim(const hPopupWnd: HWINDOW);
var
  idx: Integer;
  ctxNil: PPopupAnimEnterCtx;
begin
  idx := UIPopupAnim_FindSlotIndex(hPopupWnd);
  if idx >= 0 then
  begin
    UIPopupAnim_ApplyFinalRect(idx);
    ctxNil := GPopupAnimSlots[idx].pEnterCtx;
    UIPopupAnim_FreeEnterCtx(ctxNil);
    GPopupAnimSlots[idx].pEnterCtx := nil;
  end;
  if XC_IsHWINDOW(hPopupWnd) then
    XAnima_ReleaseEx(hPopupWnd, True);
end;

procedure UIPopupAnim_RemoveSlotAt(const idx: Integer);
var
  i: Integer;
begin
  if (idx < 0) or (idx >= GPopupAnimSlotCount) then
    Exit;
  UIPopupAnim_ReleaseObjectAnim(GPopupAnimSlots[idx].hPopupWnd);
  for i := idx to GPopupAnimSlotCount - 2 do
    GPopupAnimSlots[i] := GPopupAnimSlots[i + 1];
  Dec(GPopupAnimSlotCount);
  FillChar(GPopupAnimSlots[GPopupAnimSlotCount], SizeOf(TPopupAnimSlot), 0);
end;

procedure UIPopupAnim_HideAllExcept(const hKeepWnd: HWINDOW);
var
  i: Integer;
  hWnd: HWINDOW;
begin
  i := GPopupAnimSlotCount - 1;
  while i >= 0 do
  begin
    hWnd := GPopupAnimSlots[i].hPopupWnd;
    if (hWnd <> hKeepWnd) and XC_IsHWINDOW(hWnd) then
      UIPopupAnim_RemoveSlotAt(i)
    else
      Dec(i);
  end;
end;

procedure UIPopupAnim_RegisterSlot(const hPopupWnd: HWINDOW; const hAnimSeq: HXCGUI;
  const rcFinal: TRect; const ctx: PPopupAnimEnterCtx);
var
  idx: Integer;
begin
  idx := UIPopupAnim_FindSlotIndex(hPopupWnd);
  if idx >= 0 then
  begin
    UIPopupAnim_FreeEnterCtx(GPopupAnimSlots[idx].pEnterCtx);
    GPopupAnimSlots[idx].hAnimSeq := hAnimSeq;
    GPopupAnimSlots[idx].rcFinal := rcFinal;
    GPopupAnimSlots[idx].pEnterCtx := ctx;
    Exit;
  end;
  if GPopupAnimSlotCount >= UI_POPUP_ANIM_MAX_SLOTS then
    UIPopupAnim_RemoveSlotAt(0);
  GPopupAnimSlots[GPopupAnimSlotCount].hPopupWnd := hPopupWnd;
  GPopupAnimSlots[GPopupAnimSlotCount].hAnimSeq := hAnimSeq;
  GPopupAnimSlots[GPopupAnimSlotCount].rcFinal := rcFinal;
  GPopupAnimSlots[GPopupAnimSlotCount].pEnterCtx := ctx;
  Inc(GPopupAnimSlotCount);
end;

procedure UIPopupAnim_PlayEnter(const hPopupWnd: HWINDOW; const nParentItemId: Integer;
  const rcFinal: TRect);
var
  hAnimSeq, hAnimItem: HXCGUI;
  durTotal: Cardinal;
  ctx: PPopupAnimEnterCtx;
  w, h: Integer;
begin
  if not XC_IsHWINDOW(hPopupWnd) then
    Exit;

  UIPopupAnim_ReleaseObjectAnim(hPopupWnd);

  if nParentItemId = 0 then
  begin
    UIPopupAnim_HideAllExcept(hPopupWnd);
    durTotal := UI_POPUP_ANIM_ENTER_MS_DEFAULT;
  end
  else
    durTotal := UI_POPUP_ANIM_ENTER_MS_SUBMENU;

  w := rcFinal.Right - rcFinal.Left;
  h := rcFinal.Bottom - rcFinal.Top;
  if (w < 1) or (h < 1) then
    Exit;

  New(ctx);
  ctx^.hPopupWnd := hPopupWnd;
  ctx^.rcFinal := rcFinal;
  ctx^.wFinal := w;
  ctx^.hFinal := h;
  ctx^.dyPx := UIPopupAnim_LogicalYToPx(hPopupWnd, UI_POPUP_ANIM_TRANSLATE_LOGICAL_PX);

  UIPopupAnim_ApplyEnterFrame(ctx, 0);

  hAnimSeq := XAnima_Create(hPopupWnd, UI_POPUP_ANIM_LOOP_ONCE);
  XAnima_SetCallback(hAnimSeq, Integer(@UIPopupAnim_OnAnimaComplete));
  hAnimItem := XAnima_DelayEx(hAnimSeq, durTotal, UI_POPUP_ANIM_LOOP_ONCE, ease_flag_linear, False);
  XAnimaItem_SetCallback(hAnimItem, Integer(@UIPopupAnim_OnEnterFrame));
  XAnimaItem_SetUserData(hAnimItem, Integer(ctx));
  XAnima_Run(hAnimSeq, hPopupWnd);
  UIPopupAnim_RegisterSlot(hPopupWnd, hAnimSeq, rcFinal, ctx);
end;

procedure UIPopupAnim_OnMenuPopupWindow(const hPopupWnd: HWINDOW; const nParentItemId: Integer;
  const rcFinal: TRect);
begin
  if not XC_IsHWINDOW(hPopupWnd) then
    Exit;
  if not UIPopupAnim_IsSystemAnimationEnabled then
  begin
    UIPopupAnim_ReleaseObjectAnim(hPopupWnd);
    Exit;
  end;
  UIPopupAnim_PlayEnter(hPopupWnd, nParentItemId, rcFinal);
end;

procedure UIPopupAnim_OnMenuExit;
var
  i: Integer;
begin
  i := GPopupAnimSlotCount - 1;
  while i >= 0 do
  begin
    UIPopupAnim_RemoveSlotAt(i);
    Dec(i);
  end;
end;

end.
