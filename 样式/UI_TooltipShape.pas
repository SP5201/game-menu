unit UI_TooltipShape;

interface

uses
  Windows, Types, Math, XCGUI, UI_Theme;

type
  TTooltipArrowEdge = (
    TooltipArrowEdge_Top,
    TooltipArrowEdge_Bottom,
    TooltipArrowEdge_Left,
    TooltipArrowEdge_Right
  );

  TTooltipBubbleLayout = record
    CornerRadius: Integer;
    TriangleSize: Integer;
    TextPadX: Integer;
    TextPadY: Integer;
    ShadowPad: Integer;
  end;

const
  TooltipContentPad = 4;

  TooltipDefaultLayout: TTooltipBubbleLayout = (
    CornerRadius: 6;
    TriangleSize: 8;
    TextPadX: TooltipContentPad;
    TextPadY: TooltipContentPad;
    ShadowPad: 20;
  );

function TooltipLayoutLikePopupMenu: TTooltipBubbleLayout;

function TooltipCornerRadius: Integer;

procedure TooltipDrawPopupMenuSurface(hDraw: XCGUI.HDRAW; const ARc: TRect; ARadius: Integer);

procedure TooltipPrepareDraw(hDraw: XCGUI.HDRAW);

procedure TooltipCalcBubbleSize(const ATextSize: TSize; const L: TTooltipBubbleLayout;
  AEdge: TTooltipArrowEdge; out AWidth, AHeight: Integer);

procedure TooltipCalcTextRect(const ARc: TRect; const L: TTooltipBubbleLayout;
  AEdge: TTooltipArrowEdge; out ATextRect: TRect);

procedure TooltipDrawRoundRectPopup(hDraw: XCGUI.HDRAW; const ARc: TRect; AShadowPad, ARadius: Integer);

procedure TooltipDrawBubble(hDraw: XCGUI.HDRAW; const ARc: TRect; const L: TTooltipBubbleLayout;
  AEdge: TTooltipArrowEdge; TriangleCenterX: Integer);

implementation

uses
  D2D1;

const
  TooltipShadowSteps = 21;
  TooltipShadowMaxBlur = 40.0 / TooltipShadowSteps;
  TooltipShadowOffsetY = 1;
  TooltipShadowOpacityK = 0.035;
  TooltipArcSegments = 8;

function TooltipShadowLayerOpacity(AStep: Integer): Single;
var
  t: Extended;
begin
  t := (TooltipShadowSteps + 1 - AStep) / TooltipShadowSteps;
  Result := TooltipShadowOpacityK * Sqr(t);
  if Result < 0.015 then
    Result := 0;
end;

procedure AppendPoint(var pts: array of TPoint; var n: Integer; x, y: Integer);
begin
  pts[n].X := x;
  pts[n].Y := y;
  Inc(n);
end;

procedure AppendArcPoints(var pts: array of TPoint; var n: Integer; cx, cy, radius: Integer;
  angStart, angEnd: Extended; skipFirst: Boolean);
var
  i, iStart: Integer;
  t, a: Extended;
begin
  if skipFirst then
    iStart := 1
  else
    iStart := 0;
  for i := iStart to TooltipArcSegments do
  begin
    if TooltipArcSegments = 0 then
      t := 0
    else
      t := i / TooltipArcSegments;
    a := angStart + (angEnd - angStart) * t;
    AppendPoint(pts, n, cx + Round(radius * Cos(a)), cy - Round(radius * Sin(a)));
  end;
end;

procedure TooltipBuildBubblePoints(const clientRc: TRect; const L: TTooltipBubbleLayout;
  AEdge: TTooltipArrowEdge; cx: Integer; out pts: array of TPoint; out ptCount: Integer);
var
  r, triHalf, triPos, yFlat: Integer;
  left, top, right, bottom: Integer;
begin
  ptCount := 0;
  left := clientRc.Left;
  top := clientRc.Top;
  right := clientRc.Right;
  bottom := clientRc.Bottom;
  r := L.CornerRadius;
  triHalf := L.TriangleSize;
  triPos := cx - left;

  if AEdge = TooltipArrowEdge_Bottom then
  begin
    yFlat := bottom - triHalf;
    { 顶点顺序与 TooltipAppendBubblePathD2D 一致，避免 GDI 填充出现三角/矩形接缝 }
    AppendPoint(pts, ptCount, left + r, top);
    AppendPoint(pts, ptCount, right - r, top);
    AppendArcPoints(pts, ptCount, right - r, top + r, r, Pi * 0.5, 0, True);
    AppendPoint(pts, ptCount, right, bottom - triHalf - r);
    AppendArcPoints(pts, ptCount, right - r, bottom - triHalf - r, r, 0, -Pi * 0.5, True);
    AppendPoint(pts, ptCount, triPos + triHalf, yFlat);
    AppendPoint(pts, ptCount, triPos, bottom);
    AppendPoint(pts, ptCount, triPos - triHalf, yFlat);
    AppendPoint(pts, ptCount, left + r, yFlat);
    AppendArcPoints(pts, ptCount, left + r, bottom - triHalf - r, r, -Pi * 0.5, -Pi, True);
    AppendPoint(pts, ptCount, left, top + r);
    AppendArcPoints(pts, ptCount, left + r, top + r, r, Pi, Pi * 0.5, True);
  end
  else if AEdge = TooltipArrowEdge_Top then
  begin
    yFlat := top + triHalf;
    AppendPoint(pts, ptCount, triPos, top);
    AppendPoint(pts, ptCount, triPos + triHalf, yFlat);
    AppendPoint(pts, ptCount, right - r, yFlat);
    AppendArcPoints(pts, ptCount, right - r, yFlat + r, r, Pi * 0.5, 0, True);
    AppendPoint(pts, ptCount, right, bottom - r);
    AppendArcPoints(pts, ptCount, right - r, bottom - r, r, 0, -Pi * 0.5, True);
    AppendPoint(pts, ptCount, left + r, bottom);
    AppendArcPoints(pts, ptCount, left + r, bottom - r, r, -Pi * 0.5, -Pi, True);
    AppendPoint(pts, ptCount, left, yFlat + r);
    AppendArcPoints(pts, ptCount, left + r, yFlat + r, r, Pi, Pi * 0.5, True);
    AppendPoint(pts, ptCount, triPos - triHalf, yFlat);
  end
  else
  begin
    AppendPoint(pts, ptCount, left + r, top);
    AppendPoint(pts, ptCount, right - r, top);
    AppendArcPoints(pts, ptCount, right - r, top + r, r, Pi * 0.5, 0, True);
    AppendPoint(pts, ptCount, right, bottom - r);
    AppendArcPoints(pts, ptCount, right - r, bottom - r, r, 0, -Pi * 0.5, True);
    AppendPoint(pts, ptCount, left + r, bottom);
    AppendArcPoints(pts, ptCount, left + r, bottom - r, r, -Pi * 0.5, -Pi, True);
    AppendPoint(pts, ptCount, left, top + r);
    AppendArcPoints(pts, ptCount, left + r, top + r, r, Pi, Pi * 1.5, True);
  end;
end;

function RectToD2D1RectF(const ARc: TRect): TD2D1RectF;
begin
  Result := D2D1RectF(ARc.Left, ARc.Top, ARc.Right, ARc.Bottom);
end;

function TooltipCornerRadius: Integer;
begin
  Result := UITheme_WindowCornerRadius - 2;
  if Result < 0 then
    Result := 0;
end;

function TooltipLayoutLikePopupMenu: TTooltipBubbleLayout;
begin
  Result := TooltipDefaultLayout;
  Result.CornerRadius := TooltipCornerRadius;
end;

procedure TooltipPrepareDraw(hDraw: XCGUI.HDRAW);
begin
  if XC_IsEnableD2D then
    XDraw_D2D_Clear(hDraw, 0);
end;

procedure TooltipDrawPopupMenuSurface(hDraw: XCGUI.HDRAW; const ARc: TRect; ARadius: Integer);
var
  rc: TRect;
begin
  { 与 UI_PopupMenu.OnMenuDrawBackground 一致：UITheme_SurfaceBase + UITheme_SurfaceOutline }
  rc := ARc;
  XDraw_SetBrushColor(hDraw, UITheme_SurfaceBase);
  XDraw_FillRoundRect(hDraw, rc, ARadius, ARadius);
  XDraw_SetLineWidth(hDraw, 1);
  XDraw_SetBrushColor(hDraw, UITheme_SurfaceOutline);
  XDraw_DrawRoundRect(hDraw, rc, ARadius, ARadius);
end;

procedure TooltipDrawPopupMenuSurfacePath(hDraw: XCGUI.HDRAW; pPts: PPoint; ptCount: Integer);
begin
  if ptCount < 3 then
    Exit;
  XDraw_SetLineWidth(hDraw, 1);
  XDraw_SetBrushColor(hDraw, UITheme_SurfaceOutline);
  XDraw_DrawPolygon(hDraw, pPts, ptCount);
  XDraw_SetBrushColor(hDraw, UITheme_SurfaceBase);
  XDraw_FillPolygon(hDraw, pPts, ptCount);
end;

function ClampTriangleCenterX(const ARc: TRect; const L: TTooltipBubbleLayout; TriangleCenterX: Integer): Integer;
var
  minX, maxX: Integer;
begin
  minX := ARc.Left + L.ShadowPad + L.CornerRadius + L.TriangleSize;
  maxX := ARc.Right - L.ShadowPad - L.CornerRadius - L.TriangleSize;
  if maxX < minX then
    Result := (ARc.Left + ARc.Right) div 2
  else
    Result := EnsureRange(TriangleCenterX, minX, maxX);
end;

procedure TooltipAppendBubblePathD2D(Sink: ID2D1GeometrySink; const ClientRect: TD2D1RectF;
  CornerRadius, TriangleSize, TrianglePosition: Single; AEdge: TTooltipArrowEdge);
var
  arc: TD2D1ArcSegment;
begin
  arc.size := D2D1SizeF(CornerRadius, CornerRadius);
  arc.rotationAngle := 0;
  arc.sweepDirection := D2D1_SWEEP_DIRECTION_CLOCKWISE;
  arc.arcSize := D2D1_ARC_SIZE_SMALL;

  if AEdge = TooltipArrowEdge_Bottom then
  begin
    Sink.BeginFigure(D2D1PointF(ClientRect.left + CornerRadius, ClientRect.top), D2D1_FIGURE_BEGIN_FILLED);
    Sink.AddLine(D2D1PointF(ClientRect.right - CornerRadius, ClientRect.top));
    arc.point := D2D1PointF(ClientRect.right, ClientRect.top + CornerRadius);
    Sink.AddArc(arc);
    Sink.AddLine(D2D1PointF(ClientRect.right, ClientRect.bottom - TriangleSize - CornerRadius));
    arc.point := D2D1PointF(ClientRect.right - CornerRadius, ClientRect.bottom - TriangleSize);
    Sink.AddArc(arc);
    Sink.AddLine(D2D1PointF(ClientRect.left + TrianglePosition + TriangleSize, ClientRect.bottom - TriangleSize));
    Sink.AddLine(D2D1PointF(ClientRect.left + TrianglePosition, ClientRect.bottom));
    Sink.AddLine(D2D1PointF(ClientRect.left + TrianglePosition - TriangleSize, ClientRect.bottom - TriangleSize));
    Sink.AddLine(D2D1PointF(ClientRect.left + CornerRadius, ClientRect.bottom - TriangleSize));
    arc.point := D2D1PointF(ClientRect.left, ClientRect.bottom - TriangleSize - CornerRadius);
    Sink.AddArc(arc);
    Sink.AddLine(D2D1PointF(ClientRect.left, ClientRect.top + CornerRadius));
    arc.point := D2D1PointF(ClientRect.left + CornerRadius, ClientRect.top);
    Sink.AddArc(arc);
  end
  else if AEdge = TooltipArrowEdge_Top then
  begin
    Sink.BeginFigure(D2D1PointF(ClientRect.left + TrianglePosition, ClientRect.top), D2D1_FIGURE_BEGIN_FILLED);
    Sink.AddLine(D2D1PointF(ClientRect.left + TrianglePosition + TriangleSize, ClientRect.top + TriangleSize));
    Sink.AddLine(D2D1PointF(ClientRect.right - CornerRadius, ClientRect.top + TriangleSize));
    arc.point := D2D1PointF(ClientRect.right, ClientRect.top + TriangleSize + CornerRadius);
    Sink.AddArc(arc);
    Sink.AddLine(D2D1PointF(ClientRect.right, ClientRect.bottom - CornerRadius));
    arc.point := D2D1PointF(ClientRect.right - CornerRadius, ClientRect.bottom);
    Sink.AddArc(arc);
    Sink.AddLine(D2D1PointF(ClientRect.left + CornerRadius, ClientRect.bottom));
    arc.point := D2D1PointF(ClientRect.left, ClientRect.bottom - CornerRadius);
    Sink.AddArc(arc);
    Sink.AddLine(D2D1PointF(ClientRect.left, ClientRect.top + TriangleSize + CornerRadius));
    arc.point := D2D1PointF(ClientRect.left + CornerRadius, ClientRect.top + TriangleSize);
    Sink.AddArc(arc);
    Sink.AddLine(D2D1PointF(ClientRect.left + TrianglePosition - TriangleSize, ClientRect.top + TriangleSize));
    Sink.AddLine(D2D1PointF(ClientRect.left + TrianglePosition, ClientRect.top));
  end
  else
  begin
    Sink.BeginFigure(D2D1PointF(ClientRect.left + CornerRadius, ClientRect.top), D2D1_FIGURE_BEGIN_FILLED);
    Sink.AddLine(D2D1PointF(ClientRect.right - CornerRadius, ClientRect.top));
    arc.point := D2D1PointF(ClientRect.right, ClientRect.top + CornerRadius);
    Sink.AddArc(arc);
    Sink.AddLine(D2D1PointF(ClientRect.right, ClientRect.bottom - CornerRadius));
    arc.point := D2D1PointF(ClientRect.right - CornerRadius, ClientRect.bottom);
    Sink.AddArc(arc);
    Sink.AddLine(D2D1PointF(ClientRect.left + CornerRadius, ClientRect.bottom));
    arc.point := D2D1PointF(ClientRect.left, ClientRect.bottom - CornerRadius);
    Sink.AddArc(arc);
    Sink.AddLine(D2D1PointF(ClientRect.left, ClientRect.top + CornerRadius));
    arc.point := D2D1PointF(ClientRect.left + CornerRadius, ClientRect.top);
    Sink.AddArc(arc);
  end;

  Sink.EndFigure(D2D1_FIGURE_END_CLOSED);
end;

function TooltipCreateBubbleGeometry(hDraw: XCGUI.HDRAW; const clientRc: TRect; const L: TTooltipBubbleLayout;
  AEdge: TTooltipArrowEdge; cx: Integer; out AGeometry: ID2D1PathGeometry): Boolean;
var
  d2dRT: ID2D1RenderTarget;
  d2dFactory: ID2D1Factory;
  sink: ID2D1GeometrySink;
  clientRect: TD2D1RectF;
  triPos: Single;
begin
  Result := False;
  AGeometry := nil;
  if not XC_IsEnableD2D then
    Exit;
  d2dRT := ID2D1RenderTarget(XDraw_GetD2dRenderTarget(hDraw));
  if d2dRT = nil then
    Exit;
  d2dRT.GetFactory(d2dFactory);
  if (d2dFactory = nil) or Failed(d2dFactory.CreatePathGeometry(AGeometry)) then
    Exit;
  if Failed(AGeometry.Open(sink)) then
  begin
    AGeometry := nil;
    Exit;
  end;
  clientRect.left := clientRc.Left + 0.5;
  clientRect.top := clientRc.Top + 0.5;
  clientRect.right := clientRc.Right - 0.5;
  clientRect.bottom := clientRc.Bottom - 0.5;
  triPos := (cx - clientRc.Left) - 0.5;
  TooltipAppendBubblePathD2D(sink, clientRect, L.CornerRadius, L.TriangleSize, triPos, AEdge);
  if Failed(sink.Close) then
  begin
    AGeometry := nil;
    Exit;
  end;
  Result := True;
end;

procedure TooltipDrawPathShadowD2D(hDraw: XCGUI.HDRAW; Geometry: ID2D1PathGeometry);
var
  d2dRT: ID2D1RenderTarget;
  brush: ID2D1SolidColorBrush;
  oldTransform, offsetTransform: TD2D1Matrix3x2F;
  opacity: Single;
  i: Integer;
begin
  if Geometry = nil then
    Exit;
  d2dRT := ID2D1RenderTarget(XDraw_GetD2dRenderTarget(hDraw));
  if d2dRT = nil then
    Exit;

  d2dRT.GetTransform(oldTransform);
  offsetTransform._11 := 1;
  offsetTransform._12 := 0;
  offsetTransform._21 := 0;
  offsetTransform._22 := 1;
  offsetTransform._31 := 0;
  offsetTransform._32 := TooltipShadowOffsetY;
  d2dRT.SetTransform(offsetTransform * oldTransform);

  for i := TooltipShadowSteps downto 1 do
  begin
    opacity := TooltipShadowLayerOpacity(i);
    if opacity <= 0 then
      Continue;
    if Succeeded(d2dRT.CreateSolidColorBrush(RGBAToD2D1ColorF(RGBA(0, 0, 0, Round(255 * opacity))),
      nil, brush)) then
    begin
      try
        d2dRT.DrawGeometry(Geometry, brush, i * TooltipShadowMaxBlur, nil);
      finally
        brush := nil;
      end;
    end;
  end;

  d2dRT.SetTransform(oldTransform);
end;

procedure TooltipDrawPathShadowGDI(hDraw: XCGUI.HDRAW; const pts: array of TPoint; ptCount: Integer);
var
  offsetPts: array[0..63] of TPoint;
  i, j: Integer;
  opacity: Single;
  alpha: Byte;
begin
  if ptCount < 3 then
    Exit;
  for j := 0 to ptCount - 1 do
  begin
    offsetPts[j].X := pts[j].X;
    offsetPts[j].Y := pts[j].Y + TooltipShadowOffsetY;
  end;
  for i := TooltipShadowSteps downto 1 do
  begin
    opacity := TooltipShadowLayerOpacity(i);
    alpha := Round(255 * opacity);
    if alpha < 4 then
      Continue;
    XDraw_SetLineWidthF(hDraw, i * TooltipShadowMaxBlur);
    XDraw_SetBrushColor(hDraw, RGBA(0, 0, 0, alpha));
    XDraw_DrawPolygon(hDraw, @offsetPts[0], ptCount);
  end;
end;

procedure TooltipDrawPathFillD2D(hDraw: XCGUI.HDRAW; Geometry: ID2D1PathGeometry; AColor: Integer;
  offsetX, offsetY: Single);
var
  d2dRT: ID2D1RenderTarget;
  brush: ID2D1SolidColorBrush;
  oldTransform, offsetTransform: TD2D1Matrix3x2F;
begin
  if Geometry = nil then
    Exit;
  d2dRT := ID2D1RenderTarget(XDraw_GetD2dRenderTarget(hDraw));
  if d2dRT = nil then
    Exit;
  d2dRT.GetTransform(oldTransform);
  offsetTransform._11 := 1;
  offsetTransform._12 := 0;
  offsetTransform._21 := 0;
  offsetTransform._22 := 1;
  offsetTransform._31 := offsetX;
  offsetTransform._32 := offsetY;
  d2dRT.SetTransform(offsetTransform * oldTransform);
  if Succeeded(d2dRT.CreateSolidColorBrush(RGBAToD2D1ColorF(AColor), nil, brush)) then
  begin
    d2dRT.FillGeometry(Geometry, brush);
    brush := nil;
  end;
  d2dRT.SetTransform(oldTransform);
end;

procedure TooltipDrawPathStrokeD2D(hDraw: XCGUI.HDRAW; Geometry: ID2D1PathGeometry; AColor: Integer;
  lineWidth: Single; offsetX, offsetY: Single);
var
  d2dRT: ID2D1RenderTarget;
  brush: ID2D1SolidColorBrush;
  oldTransform, offsetTransform: TD2D1Matrix3x2F;
begin
  if Geometry = nil then
    Exit;
  d2dRT := ID2D1RenderTarget(XDraw_GetD2dRenderTarget(hDraw));
  if d2dRT = nil then
    Exit;
  d2dRT.GetTransform(oldTransform);
  offsetTransform._11 := 1;
  offsetTransform._12 := 0;
  offsetTransform._21 := 0;
  offsetTransform._22 := 1;
  offsetTransform._31 := offsetX;
  offsetTransform._32 := offsetY;
  d2dRT.SetTransform(offsetTransform * oldTransform);
  if Succeeded(d2dRT.CreateSolidColorBrush(RGBAToD2D1ColorF(AColor), nil, brush)) then
  begin
    d2dRT.DrawGeometry(Geometry, brush, lineWidth);
    brush := nil;
  end;
  d2dRT.SetTransform(oldTransform);
end;

procedure TooltipDrawBubblePathShadow(hDraw: XCGUI.HDRAW; const clientRc: TRect; const L: TTooltipBubbleLayout;
  AEdge: TTooltipArrowEdge; cx: Integer);
var
  geometry: ID2D1PathGeometry;
  pts: array[0..63] of TPoint;
  ptCount: Integer;
begin
  if XC_IsEnableD2D and TooltipCreateBubbleGeometry(hDraw, clientRc, L, AEdge, cx, geometry) then
  begin
    try
      TooltipDrawPathShadowD2D(hDraw, geometry);
    finally
      geometry := nil;
    end;
    Exit;
  end;

  TooltipBuildBubblePoints(clientRc, L, AEdge, cx, pts, ptCount);
  TooltipDrawPathShadowGDI(hDraw, pts, ptCount);
end;

procedure TooltipDrawBubblePathBody(hDraw: XCGUI.HDRAW; const clientRc: TRect; const L: TTooltipBubbleLayout;
  AEdge: TTooltipArrowEdge; cx: Integer);
var
  geometry: ID2D1PathGeometry;
  pts: array[0..63] of TPoint;
  ptCount: Integer;
begin
  if XC_IsEnableD2D and TooltipCreateBubbleGeometry(hDraw, clientRc, L, AEdge, cx, geometry) then
  begin
    try
      TooltipDrawPathFillD2D(hDraw, geometry, UITheme_SurfaceBase, 0, 0);
      TooltipDrawPathStrokeD2D(hDraw, geometry, UITheme_SurfaceOutline, 1.0, 0, 0);
    finally
      geometry := nil;
    end;
    Exit;
  end;

  TooltipBuildBubblePoints(clientRc, L, AEdge, cx, pts, ptCount);
  TooltipDrawPopupMenuSurfacePath(hDraw, @pts[0], ptCount);
end;

procedure TooltipDrawRoundRectShadow(hDraw: XCGUI.HDRAW; const ARc: TRect; AShadowPad, ARadius: Integer);
var
  i: Integer;
  opacity: Single;
  alpha: Byte;
  rcShadow: TRect;
begin
  rcShadow := ARc;
  OffsetRect(rcShadow, 0, TooltipShadowOffsetY);
  for i := TooltipShadowSteps downto 1 do
  begin
    opacity := TooltipShadowLayerOpacity(i);
    alpha := Round(255 * opacity);
    if alpha < 4 then
      Continue;
    XDraw_SetLineWidthF(hDraw, i * TooltipShadowMaxBlur);
    XDraw_SetBrushColor(hDraw, RGBA(0, 0, 0, alpha));
    XDraw_DrawRoundRect(hDraw, rcShadow, ARadius, ARadius);
  end;
end;

procedure TooltipCalcBubbleSize(const ATextSize: TSize; const L: TTooltipBubbleLayout;
  AEdge: TTooltipArrowEdge; out AWidth, AHeight: Integer);
begin
  AWidth := ATextSize.cx + L.TextPadX * 2 + L.ShadowPad * 2;
  AHeight := ATextSize.cy + L.TextPadY * 2 + L.ShadowPad * 2;
  case AEdge of
    TooltipArrowEdge_Top, TooltipArrowEdge_Bottom:
      Inc(AHeight, L.TriangleSize);
    TooltipArrowEdge_Left, TooltipArrowEdge_Right:
      Inc(AWidth, L.TriangleSize);
  end;
end;

procedure TooltipCalcTextRect(const ARc: TRect; const L: TTooltipBubbleLayout;
  AEdge: TTooltipArrowEdge; out ATextRect: TRect);
begin
  ATextRect := ARc;
  ATextRect.Left := ARc.Left + L.ShadowPad + L.TextPadX;
  ATextRect.Right := ARc.Right - L.ShadowPad - L.TextPadX;
  case AEdge of
    TooltipArrowEdge_Bottom:
      begin
        ATextRect.Top := ARc.Top + L.ShadowPad + L.TextPadY;
        ATextRect.Bottom := ARc.Bottom - L.ShadowPad - L.TextPadY - L.TriangleSize;
      end;
    TooltipArrowEdge_Top:
      begin
        ATextRect.Top := ARc.Top + L.ShadowPad + L.TextPadY + L.TriangleSize;
        ATextRect.Bottom := ARc.Bottom - L.ShadowPad - L.TextPadY;
      end;
    TooltipArrowEdge_Left:
      begin
        ATextRect.Left := ARc.Left + L.ShadowPad + L.TextPadX + L.TriangleSize;
        ATextRect.Top := ARc.Top + L.ShadowPad + L.TextPadY;
        ATextRect.Bottom := ARc.Bottom - L.ShadowPad - L.TextPadY;
      end;
    TooltipArrowEdge_Right:
      begin
        ATextRect.Right := ARc.Right - L.ShadowPad - L.TextPadX - L.TriangleSize;
        ATextRect.Top := ARc.Top + L.ShadowPad + L.TextPadY;
        ATextRect.Bottom := ARc.Bottom - L.ShadowPad - L.TextPadY;
      end;
  end;
end;

procedure TooltipDrawRoundRectPopup(hDraw: XCGUI.HDRAW; const ARc: TRect; AShadowPad, ARadius: Integer);
var
  rcBody: TRect;
begin
  rcBody := ARc;
  InflateRect(rcBody, -AShadowPad, -AShadowPad);
  TooltipDrawRoundRectShadow(hDraw, rcBody, AShadowPad, ARadius);
  TooltipDrawPopupMenuSurface(hDraw, rcBody, ARadius);
end;

procedure TooltipDrawBubble(hDraw: XCGUI.HDRAW; const ARc: TRect; const L: TTooltipBubbleLayout;
  AEdge: TTooltipArrowEdge; TriangleCenterX: Integer);
var
  clientRc: TRect;
  cx: Integer;
begin
  TooltipPrepareDraw(hDraw);
  XDraw_EnableSmoothingMode(hDraw, True);

  clientRc := ARc;
  InflateRect(clientRc, -L.ShadowPad, -L.ShadowPad);
  cx := ClampTriangleCenterX(ARc, L, TriangleCenterX);

  TooltipDrawBubblePathShadow(hDraw, clientRc, L, AEdge, cx);
  TooltipDrawBubblePathBody(hDraw, clientRc, L, AEdge, cx);
end;

end.
