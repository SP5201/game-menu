unit UI_QrCodeRender;

interface

uses
  Windows, Types, Math, XCGUI, GDIPAPI, GDIPOBJ, DelphiZXingQRCode, UI_Theme;

type
  TQrPaintLayout = record
    QrSize: Integer;
    QuietZone: Integer;
    InnerSize: Integer;
    ModuleSize: Integer;
    OffsetX: Integer;
    OffsetY: Integer;
    Valid: Boolean;
  end;

function QrHasMatrix(AQr: TDelphiZXingQRCode): Boolean;
function QrShouldPaintBackground(AQr: TDelphiZXingQRCode; BgAlpha: Byte): Boolean;
function QrCalcPaintLayout(AQr: TDelphiZXingQRCode; const Bounds: TRect; out Layout: TQrPaintLayout): Boolean;
function QrIsInFinderPattern(Row, Col: Integer; const Layout: TQrPaintLayout): Boolean;
function ColorIntToGp(Color: Integer): Cardinal;

procedure QrPaintMatrixXDraw(hDraw: hDraw; AQr: TDelphiZXingQRCode; const Layout: TQrPaintLayout;
  FgColor: Integer; Liquify: Boolean; ModuleRadius: Integer);

procedure QrPaintMatrixGp(G: TGPGraphics; AQr: TDelphiZXingQRCode; const Layout: TQrPaintLayout;
  FgColor: Cardinal; Liquify: Boolean; ModuleRadius: Integer);

procedure GpFillRoundRect(G: TGPGraphics; const ARect: TRect; Radius: Integer; Color: Cardinal);
procedure GpDrawRoundRect(G: TGPGraphics; const ARect: TRect; Radius: Integer; Color: Cardinal; LineWidth: Single);

function QrRgbToGpColor(R, G, B: Integer; A: Byte): Cardinal;

procedure QrPaintToGp(G: TGPGraphics; AQr: TDelphiZXingQRCode; const Bounds: TRect;
  BgR, BgG, BgB: Integer; BgA: Byte; FgR, FgG, FgB: Integer; FgA: Byte;
  Liquify: Boolean; ModuleRadius: Integer);

function QrSaveGpBitmapToFile(GPBmp: TGPBitmap; const AFilePath, AExt: string): Boolean;

function QrRenderToFile(AQr: TDelphiZXingQRCode; const AFilePath, AExt: string;
  BgR, BgG, BgB: Integer; BgA: Byte; FgR, FgG, FgB: Integer; FgA: Byte;
  Liquify: Boolean; ModuleRadius: Integer; ModuleSize: Integer = 10): Boolean;

implementation

uses
  SysUtils;

function QrHasMatrix(AQr: TDelphiZXingQRCode): Boolean;
begin
  Result := (AQr <> nil) and (AQr.Rows > 0);
end;

function QrShouldPaintBackground(AQr: TDelphiZXingQRCode; BgAlpha: Byte): Boolean;
begin
  Result := QrHasMatrix(AQr) and (BgAlpha > 0);
end;

function QrCalcPaintLayout(AQr: TDelphiZXingQRCode; const Bounds: TRect; out Layout: TQrPaintLayout): Boolean;
var
  w, h: Integer;
begin
  FillChar(Layout, SizeOf(Layout), 0);
  Result := False;
  if not QrHasMatrix(AQr) then
    Exit;

  Layout.QrSize := AQr.Rows;
  Layout.QuietZone := AQr.QuietZone;
  Layout.InnerSize := Layout.QrSize - Layout.QuietZone * 2;

  w := Bounds.Right - Bounds.Left;
  h := Bounds.Bottom - Bounds.Top;
  Layout.ModuleSize := w div Layout.QrSize;
  if h div Layout.QrSize < Layout.ModuleSize then
    Layout.ModuleSize := h div Layout.QrSize;
  if Layout.ModuleSize <= 0 then
    Exit;

  Layout.OffsetX := Bounds.Left + (w - Layout.ModuleSize * Layout.QrSize) div 2;
  Layout.OffsetY := Bounds.Top + (h - Layout.ModuleSize * Layout.QrSize) div 2;
  Layout.Valid := True;
  Result := True;
end;

function QrIsInFinderPattern(Row, Col: Integer; const Layout: TQrPaintLayout): Boolean;
var
  qz, innerSize: Integer;
begin
  qz := Layout.QuietZone;
  innerSize := Layout.InnerSize;
  Result := ((Row >= qz) and (Row < qz + 7) and (Col >= qz) and (Col < qz + 7)) or
            ((Row >= qz) and (Row < qz + 7) and (Col >= qz + innerSize - 7) and (Col < qz + innerSize)) or
            ((Row >= qz + innerSize - 7) and (Row < qz + innerSize) and (Col >= qz) and (Col < qz + 7));
end;

function ColorIntToGp(Color: Integer): Cardinal;
begin
  Result := Cardinal(Color);
end;

procedure GpAddRoundRectPath(Path: TGPGraphicsPath; const ARect: TRect; Radius: Integer);
var
  gpRect: TGPRect;
  r: Integer;
begin
  gpRect.X := ARect.Left;
  gpRect.Y := ARect.Top;
  gpRect.Width := ARect.Right - ARect.Left;
  gpRect.Height := ARect.Bottom - ARect.Top;
  r := Radius;
  if r * 2 > gpRect.Width then
    r := gpRect.Width div 2;
  if r * 2 > gpRect.Height then
    r := gpRect.Height div 2;
  if r <= 0 then
  begin
    Path.AddRectangle(gpRect);
    Exit;
  end;
  Path.AddArc(gpRect.X, gpRect.Y, r * 2, r * 2, 180, 90);
  Path.AddArc(gpRect.X + gpRect.Width - r * 2, gpRect.Y, r * 2, r * 2, 270, 90);
  Path.AddArc(gpRect.X + gpRect.Width - r * 2, gpRect.Y + gpRect.Height - r * 2, r * 2, r * 2, 0, 90);
  Path.AddArc(gpRect.X, gpRect.Y + gpRect.Height - r * 2, r * 2, r * 2, 90, 90);
  Path.CloseFigure;
end;

procedure GpFillRoundRect(G: TGPGraphics; const ARect: TRect; Radius: Integer; Color: Cardinal);
var
  path: TGPGraphicsPath;
  brush: TGPSolidBrush;
begin
  path := TGPGraphicsPath.Create;
  brush := TGPSolidBrush.Create(Color);
  try
    GpAddRoundRectPath(path, ARect, Radius);
    G.FillPath(brush, path);
  finally
    brush.Free;
    path.Free;
  end;
end;

procedure GpDrawRoundRect(G: TGPGraphics; const ARect: TRect; Radius: Integer; Color: Cardinal; LineWidth: Single);
var
  path: TGPGraphicsPath;
  pen: TGPPen;
begin
  path := TGPGraphicsPath.Create;
  pen := TGPPen.Create(Color, LineWidth);
  try
    GpAddRoundRectPath(path, ARect, Radius);
    G.DrawPath(pen, path);
  finally
    pen.Free;
    path.Free;
  end;
end;

procedure GpFillRectColor(G: TGPGraphics; const ARect: TRect; Color: Cardinal);
var
  brush: TGPSolidBrush;
  gpRect: TGPRect;
begin
  brush := TGPSolidBrush.Create(Color);
  try
    gpRect.X := ARect.Left;
    gpRect.Y := ARect.Top;
    gpRect.Width := ARect.Right - ARect.Left;
    gpRect.Height := ARect.Bottom - ARect.Top;
    G.FillRectangle(brush, gpRect);
  finally
    brush.Free;
  end;
end;

procedure GpFillEllipseColor(G: TGPGraphics; const ARect: TRect; Color: Cardinal);
var
  brush: TGPSolidBrush;
  gpRect: TGPRect;
begin
  brush := TGPSolidBrush.Create(Color);
  try
    gpRect.X := ARect.Left;
    gpRect.Y := ARect.Top;
    gpRect.Width := ARect.Right - ARect.Left;
    gpRect.Height := ARect.Bottom - ARect.Top;
    G.FillEllipse(brush, gpRect);
  finally
    brush.Free;
  end;
end;

procedure QrDrawFinderPatternXDraw(hDraw: hDraw; px, py, ms, radius: Integer; FgColor: Integer);
var
  rcOuter, rcInner: TRect;
  rrOuter, rrInner: Integer;
  halfMs: Integer;
begin
  halfMs := ms div 2;
  rcOuter := Rect(px + halfMs, py + halfMs, px + ms * 7 - halfMs, py + ms * 7 - halfMs);
  rrOuter := Min(radius, (ms * 7 - ms) div 2);
  XDraw_SetBrushColor(hDraw, FgColor);
  XDraw_SetLineWidth(hDraw, ms);
  XDraw_DrawRoundRect(hDraw, rcOuter, rrOuter, rrOuter);
  rcInner := Rect(px + ms * 2, py + ms * 2, px + ms * 5, py + ms * 5);
  rrInner := Min(radius, ms * 3 div 2);
  XDraw_SetBrushColor(hDraw, FgColor);
  XDraw_FillRoundRect(hDraw, rcInner, rrInner, rrInner);
end;

procedure QrDrawFinderPatternGp(G: TGPGraphics; px, py, ms, radius: Integer; FgColor: Cardinal);
var
  rcOuter, rcInner: TRect;
  rrOuter, rrInner: Integer;
  halfMs: Integer;
begin
  halfMs := ms div 2;
  rcOuter := Rect(px + halfMs, py + halfMs, px + ms * 7 - halfMs, py + ms * 7 - halfMs);
  rrOuter := Min(radius, (ms * 7 - ms) div 2);
  GpDrawRoundRect(G, rcOuter, rrOuter, FgColor, ms);
  rcInner := Rect(px + ms * 2, py + ms * 2, px + ms * 5, py + ms * 5);
  rrInner := Min(radius, ms * 3 div 2);
  GpFillRoundRect(G, rcInner, rrInner, FgColor);
end;

procedure QrPaintMatrixXDraw(hDraw: hDraw; AQr: TDelphiZXingQRCode; const Layout: TQrPaintLayout;
  FgColor: Integer; Liquify: Boolean; ModuleRadius: Integer);
var
  r, c, startC: Integer;
  qrSize, moduleSize, offsetX, offsetY, qz, innerSize: Integer;
  qrRect: TRect;
begin
  if not Layout.Valid then
    Exit;

  qrSize := Layout.QrSize;
  qz := Layout.QuietZone;
  innerSize := Layout.InnerSize;
  moduleSize := Layout.ModuleSize;
  offsetX := Layout.OffsetX;
  offsetY := Layout.OffsetY;

  XDraw_SetBrushColor(hDraw, FgColor);
  if Liquify then
  begin
    for r := 0 to qrSize - 1 do
      for c := 0 to qrSize - 1 do
        if AQr.IsBlack[r, c] and (not QrIsInFinderPattern(r, c, Layout)) then
        begin
          qrRect := Rect(offsetX + c * moduleSize, offsetY + r * moduleSize,
                         offsetX + (c + 1) * moduleSize, offsetY + (r + 1) * moduleSize);
          XDraw_FillEllipse(hDraw, qrRect);
          if (c + 1 < qrSize) and AQr.IsBlack[r, c + 1] and (not QrIsInFinderPattern(r, c + 1, Layout)) then
          begin
            qrRect := Rect(offsetX + c * moduleSize + moduleSize div 2, offsetY + r * moduleSize,
                           offsetX + (c + 1) * moduleSize + moduleSize div 2, offsetY + (r + 1) * moduleSize);
            XDraw_FillRect(hDraw, qrRect);
          end;
          if (r + 1 < qrSize) and AQr.IsBlack[r + 1, c] and (not QrIsInFinderPattern(r + 1, c, Layout)) then
          begin
            qrRect := Rect(offsetX + c * moduleSize, offsetY + r * moduleSize + moduleSize div 2,
                           offsetX + (c + 1) * moduleSize, offsetY + (r + 1) * moduleSize + moduleSize div 2);
            XDraw_FillRect(hDraw, qrRect);
          end;
        end;
  end
  else
  begin
    for r := 0 to qrSize - 1 do
    begin
      c := 0;
      while c < qrSize do
      begin
        if AQr.IsBlack[r, c] and (not QrIsInFinderPattern(r, c, Layout)) then
        begin
          startC := c;
          while (c < qrSize) and AQr.IsBlack[r, c] and (not QrIsInFinderPattern(r, c, Layout)) do
            Inc(c);
          qrRect := Rect(offsetX + startC * moduleSize, offsetY + r * moduleSize,
                         offsetX + c * moduleSize, offsetY + (r + 1) * moduleSize);
          XDraw_FillRect(hDraw, qrRect);
        end
        else
          Inc(c);
      end;
    end;
  end;

  if ModuleRadius > 0 then
  begin
    QrDrawFinderPatternXDraw(hDraw, offsetX + qz * moduleSize, offsetY + qz * moduleSize, moduleSize, ModuleRadius, FgColor);
    QrDrawFinderPatternXDraw(hDraw, offsetX + (qz + innerSize - 7) * moduleSize, offsetY + qz * moduleSize, moduleSize, ModuleRadius, FgColor);
    QrDrawFinderPatternXDraw(hDraw, offsetX + qz * moduleSize, offsetY + (qz + innerSize - 7) * moduleSize, moduleSize, ModuleRadius, FgColor);
  end
  else
  begin
    XDraw_SetBrushColor(hDraw, FgColor);
    for r := 0 to qrSize - 1 do
      for c := 0 to qrSize - 1 do
        if AQr.IsBlack[r, c] and QrIsInFinderPattern(r, c, Layout) then
        begin
          qrRect := Rect(offsetX + c * moduleSize, offsetY + r * moduleSize,
                         offsetX + (c + 1) * moduleSize, offsetY + (r + 1) * moduleSize);
          XDraw_FillRect(hDraw, qrRect);
        end;
  end;
end;

procedure QrPaintMatrixGp(G: TGPGraphics; AQr: TDelphiZXingQRCode; const Layout: TQrPaintLayout;
  FgColor: Cardinal; Liquify: Boolean; ModuleRadius: Integer);
var
  r, c, startC: Integer;
  qrSize, moduleSize, offsetX, offsetY, qz, innerSize: Integer;
  qrRect: TRect;
begin
  if not Layout.Valid then
    Exit;

  qrSize := Layout.QrSize;
  qz := Layout.QuietZone;
  innerSize := Layout.InnerSize;
  moduleSize := Layout.ModuleSize;
  offsetX := Layout.OffsetX;
  offsetY := Layout.OffsetY;

  if Liquify then
  begin
    for r := 0 to qrSize - 1 do
      for c := 0 to qrSize - 1 do
        if AQr.IsBlack[r, c] and (not QrIsInFinderPattern(r, c, Layout)) then
        begin
          qrRect := Rect(offsetX + c * moduleSize, offsetY + r * moduleSize,
                         offsetX + (c + 1) * moduleSize, offsetY + (r + 1) * moduleSize);
          GpFillEllipseColor(G, qrRect, FgColor);
          if (c + 1 < qrSize) and AQr.IsBlack[r, c + 1] and (not QrIsInFinderPattern(r, c + 1, Layout)) then
          begin
            qrRect := Rect(offsetX + c * moduleSize + moduleSize div 2, offsetY + r * moduleSize,
                           offsetX + (c + 1) * moduleSize + moduleSize div 2, offsetY + (r + 1) * moduleSize);
            GpFillRectColor(G, qrRect, FgColor);
          end;
          if (r + 1 < qrSize) and AQr.IsBlack[r + 1, c] and (not QrIsInFinderPattern(r + 1, c, Layout)) then
          begin
            qrRect := Rect(offsetX + c * moduleSize, offsetY + r * moduleSize + moduleSize div 2,
                           offsetX + (c + 1) * moduleSize, offsetY + (r + 1) * moduleSize + moduleSize div 2);
            GpFillRectColor(G, qrRect, FgColor);
          end;
        end;
  end
  else
  begin
    for r := 0 to qrSize - 1 do
    begin
      c := 0;
      while c < qrSize do
      begin
        if AQr.IsBlack[r, c] and (not QrIsInFinderPattern(r, c, Layout)) then
        begin
          startC := c;
          while (c < qrSize) and AQr.IsBlack[r, c] and (not QrIsInFinderPattern(r, c, Layout)) do
            Inc(c);
          qrRect := Rect(offsetX + startC * moduleSize, offsetY + r * moduleSize,
                         offsetX + c * moduleSize, offsetY + (r + 1) * moduleSize);
          GpFillRectColor(G, qrRect, FgColor);
        end
        else
          Inc(c);
      end;
    end;
  end;

  if ModuleRadius > 0 then
  begin
    QrDrawFinderPatternGp(G, offsetX + qz * moduleSize, offsetY + qz * moduleSize, moduleSize, ModuleRadius, FgColor);
    QrDrawFinderPatternGp(G, offsetX + (qz + innerSize - 7) * moduleSize, offsetY + qz * moduleSize, moduleSize, ModuleRadius, FgColor);
    QrDrawFinderPatternGp(G, offsetX + qz * moduleSize, offsetY + (qz + innerSize - 7) * moduleSize, moduleSize, ModuleRadius, FgColor);
  end
  else
  begin
    for r := 0 to qrSize - 1 do
      for c := 0 to qrSize - 1 do
        if AQr.IsBlack[r, c] and QrIsInFinderPattern(r, c, Layout) then
        begin
          qrRect := Rect(offsetX + c * moduleSize, offsetY + r * moduleSize,
                         offsetX + (c + 1) * moduleSize, offsetY + (r + 1) * moduleSize);
          GpFillRectColor(G, qrRect, FgColor);
        end;
  end;
end;

function QrRgbToGpColor(R, G, B: Integer; A: Byte): Cardinal;
begin
  Result := (Cardinal(A) shl 24) or (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(B);
end;

procedure QrPaintToGp(G: TGPGraphics; AQr: TDelphiZXingQRCode; const Bounds: TRect;
  BgR, BgG, BgB: Integer; BgA: Byte; FgR, FgG, FgB: Integer; FgA: Byte;
  Liquify: Boolean; ModuleRadius: Integer);
var
  layout: TQrPaintLayout;
  fgColor, bgColor, borderColor: Cardinal;
begin
  fgColor := QrRgbToGpColor(FgR, FgG, FgB, FgA);
  bgColor := QrRgbToGpColor(BgR, BgG, BgB, BgA);
  borderColor := ColorIntToGp(UITheme_BorderDefault);

  if QrShouldPaintBackground(AQr, BgA) then
    GpFillRoundRect(G, Bounds, 4, bgColor);
  GpDrawRoundRect(G, Bounds, 4, borderColor, 1);

  if not QrHasMatrix(AQr) then
    Exit;

  if QrCalcPaintLayout(AQr, Bounds, layout) then
    QrPaintMatrixGp(G, AQr, layout, fgColor, Liquify, ModuleRadius);
end;

function QrSaveGpBitmapToFile(GPBmp: TGPBitmap; const AFilePath, AExt: string): Boolean;
var
  EncoderClsid: TGUID;
  flatBmp: TGPBitmap;
  flatG: TGPGraphics;
  w, h: Integer;
begin
  Result := False;
  if (GPBmp = nil) or (GPBmp.GetLastStatus <> Ok) then
    Exit;

  if SameText(AExt, 'png') then
    EncoderClsid := StringToGUID('{557CF406-1A04-11D3-9A73-0000F81EF32E}')
  else if SameText(AExt, 'jpg') or SameText(AExt, 'jpeg') then
    EncoderClsid := StringToGUID('{557CF401-1A04-11D3-9A73-0000F81EF32E}')
  else
    EncoderClsid := StringToGUID('{557CF400-1A04-11D3-9A73-0000F81EF32E}');

  if SameText(AExt, 'jpg') or SameText(AExt, 'jpeg') then
  begin
    w := GPBmp.GetWidth;
    h := GPBmp.GetHeight;
    flatBmp := TGPBitmap.Create(w, h, PixelFormat32bppARGB);
    flatG := TGPGraphics.Create(flatBmp);
    try
      if (flatBmp.GetLastStatus <> Ok) or (flatG.GetLastStatus <> Ok) then
        Exit;
      flatG.Clear(QrRgbToGpColor(255, 255, 255, 255));
      flatG.DrawImage(GPBmp, 0, 0);
      Result := flatBmp.Save(PWideChar(AFilePath), EncoderClsid, nil) = Ok;
    finally
      flatG.Free;
      flatBmp.Free;
    end;
    Exit;
  end;

  Result := GPBmp.Save(PWideChar(AFilePath), EncoderClsid, nil) = Ok;
end;

function QrRenderToFile(AQr: TDelphiZXingQRCode; const AFilePath, AExt: string;
  BgR, BgG, BgB: Integer; BgA: Byte; FgR, FgG, FgB: Integer; FgA: Byte;
  Liquify: Boolean; ModuleRadius: Integer; ModuleSize: Integer): Boolean;
var
  qrSize, imgSize: Integer;
  GPBmp: TGPBitmap;
  G: TGPGraphics;
  rc: TRect;
begin
  Result := False;
  if not QrHasMatrix(AQr) then
    Exit;

  qrSize := AQr.Rows;
  imgSize := qrSize * ModuleSize;
  GPBmp := TGPBitmap.Create(imgSize, imgSize, PixelFormat32bppARGB);
  G := TGPGraphics.Create(GPBmp);
  try
    if (GPBmp.GetLastStatus <> Ok) or (G.GetLastStatus <> Ok) then
      Exit;
    G.SetSmoothingMode(SmoothingModeAntiAlias);
    G.SetPixelOffsetMode(PixelOffsetModeHighQuality);
    rc := Rect(0, 0, imgSize, imgSize);
    QrPaintToGp(G, AQr, rc, BgR, BgG, BgB, BgA, FgR, FgG, FgB, FgA, Liquify, ModuleRadius);
    Result := QrSaveGpBitmapToFile(GPBmp, AFilePath, AExt);
  finally
    G.Free;
    GPBmp.Free;
  end;
end;

end.
