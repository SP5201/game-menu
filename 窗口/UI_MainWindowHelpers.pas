unit UI_MainWindowHelpers;

interface

uses
  Windows, XCGUI, ListItemTypes, LibraryStore, ShellHelper;

function ListViewItemToLibraryItem(const AItem: TListViewFileItem): TLibraryItem;
function LibraryItemToListViewItem(const AItem: TLibraryItem; const AIndex, AGroupIndex: Integer): TListViewFileItem;
function ResolveItemIconPath(const AIconPath: string): string;
function GetShellIconCachePaths: TShellIconCachePaths;
function NormalizeCategoryIconFile(const AIconFile: string): string;
function BrowseForFolderPath(const ATitle: string; const AOwnerWnd: HWND; out AFolderPath: string): Boolean;
procedure ApplyDefaultStyles(hXCGUI: hXCGUI);
procedure ClampWindowBoundsToWorkArea(var ALeft, ATop, AWidth, AHeight: Integer);
procedure RestoreMainWindowBounds(AWnd: HWINDOW);
procedure SaveMainWindowBounds(AWnd: HWINDOW);

implementation

uses
  AppConfig, UI_ScrollBar, Math, SysUtils, ShlObj, ActiveX;

function ListViewItemToLibraryItem(const AItem: TListViewFileItem): TLibraryItem;
begin
  Result.FilePath := AItem.FilePath;
  Result.FileName := AItem.FileName;
  Result.IconCachePath := AItem.IconCachePath;
  Result.FileParams := AItem.FileParams;
  Result.WorkingDir := AItem.WorkingDir;
end;

function LibraryItemToListViewItem(const AItem: TLibraryItem; const AIndex, AGroupIndex: Integer): TListViewFileItem;
begin
  Result.FilePath := AItem.FilePath;
  Result.FileName := AItem.FileName;
  Result.IconCachePath := AItem.IconCachePath;
  Result.FileParams := AItem.FileParams;
  Result.WorkingDir := AItem.WorkingDir;
  Result.InsertOrder := AIndex;
  Result.FileImage := 0;
  Result.ItemGroupIndex := AGroupIndex;
end;

function ResolveItemIconPath(const AIconPath: string): string;
begin
  Result := Trim(AIconPath);
  if Result = '' then
    Exit;
  if not FileExists(Result) then
    Result := TAppConfig.BuildIconCachePathFromFileName(Result);
end;

function GetShellIconCachePaths: TShellIconCachePaths;
begin
  Result.IconCacheDirectory := TAppConfig.IconCacheDirectory;
  Result.FileTypeIconDirectory := TAppConfig.FileTypeIconDirectory;
end;

function NormalizeCategoryIconFile(const AIconFile: string): string;
begin
  Result := ExtractFileName(Trim(AIconFile));
end;

function BrowseForFolderPath(const ATitle: string; const AOwnerWnd: HWND; out AFolderPath: string): Boolean;
var
  browseInfo: TBrowseInfoW;
  pidl: PItemIDList;
  pathBuffer: array[0..MAX_PATH] of WideChar;
begin
  Result := False;
  AFolderPath := '';
  FillChar(browseInfo, SizeOf(browseInfo), 0);
  browseInfo.hwndOwner := AOwnerWnd;
  browseInfo.lpszTitle := PWideChar(ATitle);
  browseInfo.ulFlags := BIF_RETURNONLYFSDIRS or BIF_NEWDIALOGSTYLE;

  pidl := SHBrowseForFolderW(browseInfo);
  if pidl = nil then
    Exit;
  try
    if SHGetPathFromIDListW(pidl, pathBuffer) then
    begin
      AFolderPath := pathBuffer;
      Result := AFolderPath <> '';
    end;
  finally
    CoTaskMemFree(pidl);
  end;
end;

procedure ApplyDefaultStyles(hXCGUI: hXCGUI);
var
  i, n: Integer;
  hChild: Integer;
begin
  if XC_IsSViewExtend(hXCGUI) then
    TScrollBarUI.ApplyDefault(hXCGUI);
  if XC_IsHWINDOW(hXCGUI) then
  begin
    n := XWnd_GetChildCount(hXCGUI);
    for i := 0 to n - 1 do
    begin
      hChild := XWnd_GetChildByIndex(hXCGUI, i);
      ApplyDefaultStyles(hChild);
    end;
  end
  else if XC_IsHELE(hXCGUI) then
  begin
    n := XEle_GetChildCount(hXCGUI);
    for i := 0 to n - 1 do
    begin
      hChild := XEle_GetChildByIndex(hXCGUI, i);
      ApplyDefaultStyles(hChild);
    end;
  end;
end;

procedure ClampWindowBoundsToWorkArea(var ALeft, ATop, AWidth, AHeight: Integer);
var
  workRect: TRect;
begin
  AWidth := Max(AWidth, 640);
  AHeight := Max(AHeight, 420);

  workRect := TRect.Create(GetSystemMetrics(SM_XVIRTUALSCREEN), GetSystemMetrics(SM_YVIRTUALSCREEN), GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN), GetSystemMetrics(SM_YVIRTUALSCREEN) + GetSystemMetrics(SM_CYVIRTUALSCREEN));
  if workRect.IsEmpty then
    workRect := TRect.Create(0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));

  AWidth := Min(AWidth, workRect.Width);
  AHeight := Min(AHeight, workRect.Height);
  ALeft := EnsureRange(ALeft, workRect.Left, workRect.Right - AWidth);
  ATop := EnsureRange(ATop, workRect.Top, workRect.Bottom - AHeight);
end;

procedure RestoreMainWindowBounds(AWnd: HWINDOW);
var
  L, T, W, H: Integer;
begin
  if TAppConfig.TryGetMainWindowBounds(L, T, W, H) then
  begin
    ClampWindowBoundsToWorkArea(L, T, W, H);
    XWnd_SetWindowPos(AWnd, 0, L, T, W, H, SWP_NOZORDER or SWP_NOACTIVATE);
  end;
  if TAppConfig.IsMainWindowMaximized then
    XWnd_MaxWindow(AWnd, True);
end;

procedure SaveMainWindowBounds(AWnd: HWINDOW);
var
  rc: TRect;
  hWndReal: Windows.HWND;
  wp: TWindowPlacement;
  isMaximized: Boolean;
begin
  if not XC_IsHWINDOW(AWnd) then
    Exit;
  hWndReal := XWnd_GetHWND(AWnd);
  wp.length := SizeOf(TWindowPlacement);
  if GetWindowPlacement(hWndReal, wp) then
  begin
    rc := wp.rcNormalPosition;
    isMaximized := (wp.showCmd = SW_SHOWMAXIMIZED)
      or ((wp.showCmd = SW_SHOWMINIMIZED) and ((wp.flags and WPF_RESTORETOMAXIMIZED) <> 0));
  end
  else
  begin
    if IsIconic(hWndReal) then
      Exit;
    isMaximized := IsZoomed(hWndReal);
    XWnd_GetRect(AWnd, rc);
  end;

  TAppConfig.SetMainWindowBounds(rc.Left, rc.Top, rc.Right - rc.Left, rc.Bottom - rc.Top);
  TAppConfig.SetMainWindowMaximized(isMaximized);
  TAppConfig.Save;
end;

end.
