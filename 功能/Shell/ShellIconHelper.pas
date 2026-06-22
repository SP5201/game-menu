unit ShellIconHelper;

interface

uses
  Classes,
  SysUtils,
  Windows,
  ShlObj,
  ListItemTypes,
  XCGUI;

type
  /// <summary>Shell 提取的 BGRA 像素（Worker 线程产出，UI 线程转 HIMAGE）。</summary>
  TShellIconPixelData = record
    Ok: Boolean;
    Width: Integer;
    Height: Integer;
    Bits: TBytes;
    IconCachePath: string;
    TypeCacheKey: string;
    CanCacheByType: Boolean;
  end;

function ExtractShellIconPixels(const APath: string; const AIconCachePath: string;
  out AData: TShellIconPixelData; AIsFolder: Boolean = False): Boolean;
function CreateHImageFromPixelData(const AData: TShellIconPixelData): HIMAGE;
function BuildListFileImageRequestKey(const AIconCachePath, AFilePath: string;
  AIsFolder: Boolean = False): string;
function TryAcquireCachedListFileImage(const AIconCachePath, AFilePath: string; out AImage: HIMAGE;
  AIsFolder: Boolean = False): Boolean;
/// <summary>仅查内存图标缓存，不触发 Shell/磁盘 IO（列表 RefreshVisibleItems 用）。</summary>
function TryAcquireMemoryCachedListFileImage(const AIconCachePath, AFilePath: string; out AImage: HIMAGE;
  out AResolvedIconCachePath: string; AIsFolder: Boolean = False): Boolean;
type
  /// <summary>列表占位图类型（Init 预热用）。</summary>
  TListPlaceholderKind = (lpkFolder, lpkApp, lpkFile);

/// <summary>返回占位图单例的 AddRef 副本（Init 时最多 3 次 Shell IO）。</summary>
function RefListPlaceholderImage(AKind: TListPlaceholderKind; out AImage: HIMAGE): Boolean;
procedure StoreListFileImageToMemoryCache(const AIconCachePath, AFilePath: string;
  const AData: TShellIconPixelData; var AFileImage: HIMAGE);
procedure StorePendingIconPixels(const AKey: string; var AData: TShellIconPixelData);
function TakePendingIconPixels(const AKey: string; out AData: TShellIconPixelData): Boolean;
procedure DiscardPendingIconPixelEntry(const AKey: string);
procedure ClearAllPendingIconPixels;
function GetListViewFileItemFromParsingPath(const AFullPath: string;
  ALoadIcon: Boolean = True): TListViewFileItem;
function LoadXImageFromFileMemory(const AFilePath: string): Integer;
procedure InvalidateListItemIconCaches(const AIconCachePath, AFilePath: string;
  AIsFolder: Boolean = False);
function IsListFileImageLoadFailed(const AIconCachePath, AFilePath: string;
  AIsFolder: Boolean = False): Boolean;
procedure MarkListFileImageLoadFailed(const AIconCachePath, AFilePath: string;
  AIsFolder: Boolean = False);
procedure ClearListFileImageLoadFailure(const AIconCachePath, AFilePath: string;
  AIsFolder: Boolean = False);
function GetItemImageFromParsingPath(const APath: string; out AIconCachePath: string): HIMAGE;
function AcquireListItemFileImage(const AIconCachePath, AFilePath: string;
  out AIconCachePathOut: string): HIMAGE;
function LoadImageFromIconData(const AIcon: HICON): HIMAGE;
function LoadApplicationIconToHImage(ADstW, ADstH: Integer): HIMAGE;
function GetShieldIconSmall: HICON;
procedure ReleaseFileTypeImageCache;

implementation

uses
  ShellAPI,
  ActiveX,
  CommCtrl,
  SyncObjs,
  GDIPAPI,
  GDIPOBJ,
  AppPaths,
  ShellHelper;

type
  PFileTypeCacheEntry = ^TFileTypeCacheEntry;
  TFileTypeCacheEntry = record
    Image: HIMAGE;
  end;
  PShellIconPixelData = ^TShellIconPixelData;

  IShellImageList = interface(IUnknown)
    ['{46EB5926-582E-4017-9FDF-E8998DAA0950}']
    function Add(hbmImage, hbmMask: HBITMAP; var pi: Integer): HRESULT; stdcall;
    function ReplaceIcon(i: Integer; hicon: HICON; var pi: Integer): HRESULT; stdcall;
    function SetOverlayImage(iImage, iOverlay: Integer): HRESULT; stdcall;
    function Replace(i: Integer; hbmImage, hbmMask: HBITMAP): HRESULT; stdcall;
    function AddMasked(hbmImage: HBITMAP; crMask: COLORREF; var pi: Integer): HRESULT; stdcall;
    function Draw(pimldp: Pointer): HRESULT; stdcall;
    function Remove(i: Integer): HRESULT; stdcall;
    function GetIcon(i, flags: Integer; var picon: HICON): HRESULT; stdcall;
  end;

  TSHGetImageList = function(iImageList: Integer; const riid: TGUID; out ppv): HRESULT; stdcall;

const
  cFolderRefPath = 'X:\__qdesktop_folder_placeholder';
  cAppRefPath = 'X:\__qdesktop_app_placeholder.exe';
  cDefaultFileTypeCacheKey = 'default';
  cDefaultExeFileTypeCacheKey = 'exe';
  cDefaultExeIconFileName = 'exe.png';
  /// <summary>与 AppConfig.cDefaultFileTypeIconFileName 一致，Shell 层不 uses AppConfig。</summary>
  cDefaultFileTypeIconFileName = 'default.png';
  /// <summary>无关联扩展名；SHGFI_USEFILEATTRIBUTES 不要求文件真实存在。</summary>
  cGenericFileIconRefPath = 'X:\__qdesktop_default_icon_ref.qdiconref';
  /// <summary>非 exe 按扩展名查 Shell 图标用的虚拟路径前缀（配合 SHGFI_USEFILEATTRIBUTES，不读真实文件）。</summary>
  cExtensionShellRefBase = 'X:\__qdesktop_ext_ref.';
  SHIL_SMALL = 0;
  SHIL_LARGE = 1;
  SHIL_EXTRALARGE = 2;
  SHIL_JUMBO = 4;
  IID_IImageList: TGUID = '{46EB5926-582E-4017-9FDF-E8998DAA0950}';
  /// <summary>与 GetItemImageFromParsingPath 回退顺序一致：JUMBO → EXTRALARGE → LARGE → SMALL。</summary>
  cShellImageListLevels: array[0..3] of Integer = (SHIL_JUMBO, SHIL_EXTRALARGE, SHIL_LARGE, SHIL_SMALL);

var
  // 非 EXE 类型：按类型键缓存图标句柄，避免重复 IO/解码。
  // Objects[] 里存 PFileTypeCacheEntry；Image=0 表示失败哨兵。
  GFileTypeImageCache: TStringList;
  /// <summary>按 IconCache 文件名（如 txt.png、8 位哈希 png）共享 HIMAGE，列表项持有 AddRef。</summary>
  GIconCachePathImageCache: TStringList;
  GDefaultFileTypeSysIconIndex: Integer = -1;
  GDefaultFileTypeSysIconIndexReady: Boolean = False;
  GDefaultExeSysIconIndex: Integer = -1;
  GDefaultExeSysIconIndexReady: Boolean = False;
  GShellImageLists: array[0..3] of IShellImageList;
  GSHGetImageListProc: TSHGetImageList = nil;
  GShellImageListsReady: Boolean = False;
  GPendingIconPixels: TStringList;
  GPendingIconPixelLock: TCriticalSection;
  /// <summary>按 BuildListFileImageRequestKey 记录 Shell 提取失败，避免反复 enqueue。</summary>
  GListFileImageFailureKeys: TStringList;
  /// <summary>三类占位图（文件/文件夹/应用程序，独立单例，不入类型缓存）。</summary>
  GFilePlaceholderImage: HIMAGE = 0;
  GFilePlaceholderReady: Boolean = False;
  GFolderPlaceholderImage: HIMAGE = 0;
  GFolderPlaceholderReady: Boolean = False;
  GAppPlaceholderImage: HIMAGE = 0;
  GAppPlaceholderReady: Boolean = False;

function EnsureShellImageListsLoaded: Boolean; forward;
function BuildIconCacheFileName(const APath: string): string; forward;
function GetFormatNameFromPath(const APath: string): string; forward;
function GetListItemDisplayImageCacheKey(const AIconCachePath, AFilePath: string;
  AIsFolder: Boolean = False): string; forward;
function ResampleBGRAToHImage(const ABits: TBytes; ASrcW, ASrcH, AMaxW, AMaxH: Integer): HIMAGE; forward;
procedure ReleaseShellImageLists; forward;
function GetSysIconIndexForPath(const APath: UnicodeString; APidl: PItemIDList; out SysIdx: Integer): Boolean; forward;
function GetSysIconIndexForShellExtract(const APath: string; out ASysIdx: Integer;
  AIsFolder: Boolean = False): Boolean; forward;
function TryResolveListFileTypeIcon(const AIconCachePath, AFilePath: string; out AImage: HIMAGE;
  AIsFolder: Boolean = False): Boolean; forward;
function IconTargetPathForShell(const AFilePath: string): string; forward;
function ResolveShortcutInfo(const AShortcutPath: string; out ATargetPath, AArguments, AWorkingDir: string): Boolean; forward;
procedure RemoveIconCachePathImageEntry(const ACacheKey: string); forward;
function IsLikelyTopLeftSmallInJumbo(const AIcon: HICON): Boolean; forward;
function ShouldShellIconByExtensionOnly(const APath: string): Boolean; forward;
function BuildExtensionShellRefPath(const AFormat: string): string; forward;
function PathTreatAsFolderForShellIcon(const APath: string; AIsFolder: Boolean): Boolean; forward;
function ShellQueryPathForIconExtract(const APath: string; AIsFolder: Boolean): string; forward;
function ShellIconAttributesForPath(const AQueryPath: string): DWORD; forward;

type
  TShellIconResolveContext = record
    PathForIcon: string;
    FormatName: string;
    SysIdx: Integer;
    GotSysIdx: Boolean;
    TypeCacheKey: string;
  end;

procedure InitShellIconResolveContext(const AFilePath: string; AIsFolder: Boolean;
  var Ctx: TShellIconResolveContext); forward;
function GetListItemDisplayImageCacheKeyWithSysIdx(const AIconCachePath, AFilePath: string;
  AIsFolder: Boolean; AGotSysIdx: Boolean; ASysIdx: Integer): string; forward;
function TryGetBestShellIconFromSysIndex(ASysIdx: Integer; out AHIcon: HICON): Boolean; forward;
function TryAcquireListFileImageInternal(const AIconCachePath, AFilePath: string; out AImage: HIMAGE;
  out AResolvedIconCachePath: string; ACheckFailureSentinel, AAllowShellResolve, AAllowDiskProbe: Boolean;
  AIsFolder: Boolean): Boolean; forward;

function GetDefaultFileTypeSysIconIndex: Integer;
var
  FileInfo: SHFILEINFOW;
begin
  if GDefaultFileTypeSysIconIndexReady then
  begin
    Result := GDefaultFileTypeSysIconIndex;
    Exit;
  end;
  GDefaultFileTypeSysIconIndexReady := True;
  Result := -1;
  ZeroMemory(@FileInfo, SizeOf(FileInfo));
  if SHGetFileInfoW(PWideChar(cGenericFileIconRefPath), FILE_ATTRIBUTE_NORMAL, FileInfo, SizeOf(FileInfo),
    SHGFI_SYSICONINDEX or SHGFI_LARGEICON or SHGFI_USEFILEATTRIBUTES) <> 0 then
    Result := FileInfo.iIcon;
  GDefaultFileTypeSysIconIndex := Result;
end;

function IsDefaultFileTypeSysIconIndex(AIndex: Integer): Boolean;
var
  defIdx: Integer;
begin
  if AIndex < 0 then
  begin
    Result := False;
    Exit;
  end;
  defIdx := GetDefaultFileTypeSysIconIndex;
  Result := (defIdx >= 0) and (AIndex = defIdx);
end;

function GetDefaultExeSysIconIndex: Integer;
const
  cExeDefRefPath = 'X:\__qdesktop_default_exe_icon_ref.exe';
var
  FileInfo: SHFILEINFOW;
begin
  if GDefaultExeSysIconIndexReady then
  begin
    Result := GDefaultExeSysIconIndex;
    Exit;
  end;
  GDefaultExeSysIconIndexReady := True;
  Result := -1;
  ZeroMemory(@FileInfo, SizeOf(FileInfo));
  if SHGetFileInfoW(PWideChar(cExeDefRefPath), FILE_ATTRIBUTE_NORMAL, FileInfo, SizeOf(FileInfo),
    SHGFI_SYSICONINDEX or SHGFI_LARGEICON or SHGFI_USEFILEATTRIBUTES) <> 0 then
    Result := FileInfo.iIcon;
  GDefaultExeSysIconIndex := Result;
end;

function IsDefaultExeSysIconIndex(AIndex: Integer): Boolean;
var
  defIdx: Integer;
begin
  if AIndex < 0 then
  begin
    Result := False;
    Exit;
  end;
  defIdx := GetDefaultExeSysIconIndex;
  Result := (defIdx >= 0) and (AIndex = defIdx);
end;

function FileTypeCacheKey(const APath: string; ASysIconIndex: Integer; AIsFolder: Boolean): string;
begin
  if PathTreatAsFolderForShellIcon(APath, AIsFolder) then
    Exit('folder');
  if SameText(GetFormatNameFromPath(APath), 'exe') then
  begin
    if IsDefaultExeSysIconIndex(ASysIconIndex) then
      Exit(cDefaultExeFileTypeCacheKey);
    Exit('');
  end;
  if IsDefaultFileTypeSysIconIndex(ASysIconIndex) then
    Exit(cDefaultFileTypeCacheKey);
  Result := GetFormatNameFromPath(APath);
end;

function FileTypeIconCacheFileName(const AFormat: string; ASysIconIndex: Integer): string;
begin
  if SameText(AFormat, 'folder') then
    Result := 'folder.png'
  else if SameText(AFormat, 'exe') and IsDefaultExeSysIconIndex(ASysIconIndex) then
    Result := cDefaultExeIconFileName
  else if SameText(AFormat, 'exe') then
    Result := ''
  else if IsDefaultFileTypeSysIconIndex(ASysIconIndex) then
    Result := cDefaultFileTypeIconFileName
  else if AFormat <> '' then
    Result := AFormat + '.png'
  else
    Result := '';
end;

function IsPerFileShellIconCacheFileName(const AFileName: string): Boolean;
var
  stem: string;
  i: Integer;
  c: Char;
begin
  Result := False;
  if not SameText(ExtractFileExt(AFileName), '.png') then
    Exit;
  stem := ChangeFileExt(ExtractFileName(AFileName), '');
  if Length(stem) <> 8 then
    Exit;
  for i := 1 to 8 do
  begin
    c := stem[i];
    if not (((c >= '0') and (c <= '9')) or ((c >= 'a') and (c <= 'f')) or ((c >= 'A') and (c <= 'F'))) then
      Exit;
  end;
  Result := True;
end;

function ShouldSkipFileTypeCacheKey(const ACacheKey: string): Boolean;
begin
  Result := (ACacheKey = '') or SameText(ACacheKey, 'msc');
end;

function TryGetCachedFileTypeImage(const ACacheKey: string; out AImage: HIMAGE): Boolean;
var
  idx: Integer;
  p: PFileTypeCacheEntry;
begin
  Result := False;
  AImage := 0;
  if GFileTypeImageCache = nil then
    Exit;
  if ShouldSkipFileTypeCacheKey(ACacheKey) then
    Exit;
  idx := GFileTypeImageCache.IndexOf(ACacheKey);
  if idx < 0 then
    Exit;
  p := PFileTypeCacheEntry(GFileTypeImageCache.Objects[idx]);
  if p = nil then
    Exit;
  if p.Image = 0 then
  begin
    Result := True; // 命中"失败哨兵"
    Exit;
  end;
  if XC_GetObjectType(p.Image) = XC_IMAGE then
  begin
    AImage := p.Image;
    XImage_AddRef(AImage);
    Result := True;
  end;
end;


procedure PutCachedFileTypeImage(const ACacheKey: string; const AImage: HIMAGE; const AFailed: Boolean);
var
  idx: Integer;
  p: PFileTypeCacheEntry;
  oldImg: HIMAGE;
begin
  if GFileTypeImageCache = nil then
    Exit;
  if ShouldSkipFileTypeCacheKey(ACacheKey) then
    Exit;
  idx := GFileTypeImageCache.IndexOf(ACacheKey);
  if idx < 0 then
  begin
    New(p);
    if AFailed then
      p.Image := 0
    else
      p.Image := AImage;
    GFileTypeImageCache.AddObject(ACacheKey, TObject(p));
  end
  else
  begin
    p := PFileTypeCacheEntry(GFileTypeImageCache.Objects[idx]);
    if p = nil then
    begin
      New(p);
      GFileTypeImageCache.Objects[idx] := TObject(p);
    end;
    if AFailed then
    begin
      oldImg := p.Image;
      p.Image := 0;
      if XC_GetObjectType(oldImg) = XC_IMAGE then
        XImage_Destroy(oldImg);
    end
    else if (p.Image <> 0) and (XC_GetObjectType(p.Image) = XC_IMAGE) then
    begin
      if (AImage <> 0) and (AImage <> p.Image) and (XC_GetObjectType(AImage) = XC_IMAGE) then
        XImage_Destroy(AImage);
    end
    else if AImage <> p.Image then
    begin
      oldImg := p.Image;
      p.Image := AImage;
      if (XC_GetObjectType(oldImg) = XC_IMAGE) and (oldImg <> AImage) then
        XImage_Destroy(oldImg);
    end;
  end;
end;

procedure FreeFileTypeImageCache;
var
  i: Integer;
  p: PFileTypeCacheEntry;
begin
  if GFileTypeImageCache = nil then
    Exit;
  for i := 0 to GFileTypeImageCache.Count - 1 do
  begin
    p := PFileTypeCacheEntry(GFileTypeImageCache.Objects[i]);
    if p <> nil then
    begin
      if XC_GetObjectType(p.Image) = XC_IMAGE then
        XImage_Destroy(p.Image);
      Dispose(p);
    end;
  end;
  FreeAndNil(GFileTypeImageCache);
end;

function NormalizeIconCachePathKey(const AIconCachePath: string): string;
begin
  Result := ExtractFileName(Trim(AIconCachePath));
end;

function TryAcquireIconCachePathImage(const ACacheKey: string; out AImage: HIMAGE): Boolean;
var
  idx: Integer;
  v: NativeInt;
begin
  Result := False;
  AImage := 0;
  if (GIconCachePathImageCache = nil) or (ACacheKey = '') then
    Exit;
  idx := GIconCachePathImageCache.IndexOf(ACacheKey);
  if idx < 0 then
    Exit;
  v := NativeInt(GIconCachePathImageCache.Objects[idx]);
  if v <= 0 then
    Exit;
  if XC_GetObjectType(v) <> XC_IMAGE then
    Exit;
  AImage := HIMAGE(v);
  XImage_AddRef(AImage);
  Result := True;
end;

procedure PutIconCachePathImage(const ACacheKey: string; const AImage: HIMAGE);
var
  idx: Integer;
  oldV: NativeInt;
begin
  if (GIconCachePathImageCache = nil) or (ACacheKey = '') then
    Exit;
  if XC_GetObjectType(AImage) <> XC_IMAGE then
    Exit;
  idx := GIconCachePathImageCache.IndexOf(ACacheKey);
  if idx < 0 then
    GIconCachePathImageCache.AddObject(ACacheKey, TObject(NativeInt(AImage)))
  else
  begin
    oldV := NativeInt(GIconCachePathImageCache.Objects[idx]);
    if (oldV > 0) and (oldV <> NativeInt(AImage)) and (XC_GetObjectType(oldV) = XC_IMAGE) then
      XImage_Destroy(HIMAGE(oldV));
    GIconCachePathImageCache.Objects[idx] := TObject(NativeInt(AImage));
  end;
end;

procedure FreeIconCachePathImageCache;
var
  i: Integer;
  v: NativeInt;
begin
  if GIconCachePathImageCache = nil then
    Exit;
  for i := 0 to GIconCachePathImageCache.Count - 1 do
  begin
    v := NativeInt(GIconCachePathImageCache.Objects[i]);
    if XC_GetObjectType(v) = XC_IMAGE then
      XImage_Destroy(HIMAGE(v));
  end;
  FreeAndNil(GIconCachePathImageCache);
end;

function TryGetShellTypeIcon(const AFilePath: string; out AImage: HIMAGE;
  AIsFolder: Boolean): Boolean;
var
  pathForIcon: string;
  attributes: DWORD;
  SysIdx: Integer;
  hFileIcon: HICON;
  FileInfo: SHFILEINFOW;
begin
  Result := False;
  AImage := 0;
  pathForIcon := ShellQueryPathForIconExtract(AFilePath, AIsFolder);
  if pathForIcon = '' then
    Exit;
  attributes := ShellIconAttributesForPath(pathForIcon);
  ZeroMemory(@FileInfo, SizeOf(FileInfo));
  SHGetFileInfoW(PWideChar(pathForIcon), attributes, FileInfo,
    SizeOf(FileInfo), SHGFI_SYSICONINDEX or SHGFI_LARGEICON or SHGFI_USEFILEATTRIBUTES);
  SysIdx := FileInfo.iIcon;
  if SysIdx < 0 then
    Exit;
  if TryGetBestShellIconFromSysIndex(SysIdx, hFileIcon) then
  begin
    try
      AImage := XImage_LoadFromHICON(hFileIcon);
      if XC_GetObjectType(AImage) = XC_IMAGE then
        Exit(True);
    finally
      DestroyIcon(hFileIcon);
    end;
  end;
  ZeroMemory(@FileInfo, SizeOf(FileInfo));
  if SHGetFileInfoW(PWideChar(pathForIcon), attributes, FileInfo, SizeOf(FileInfo),
    SHGFI_ICON or SHGFI_LARGEICON or SHGFI_USEFILEATTRIBUTES) <> 0 then
  begin
    try
      if FileInfo.hIcon <> 0 then
      begin
        AImage := XImage_LoadFromHICON(FileInfo.hIcon);
        if XC_GetObjectType(AImage) = XC_IMAGE then
          Result := True;
      end;
    finally
      if FileInfo.hIcon <> 0 then
        DestroyIcon(FileInfo.hIcon);
    end;
  end;
end;

procedure ReleaseFileTypeImageCache;
begin
  if XC_GetObjectType(GFilePlaceholderImage) = XC_IMAGE then
    XImage_Destroy(GFilePlaceholderImage);
  GFilePlaceholderImage := 0;
  GFilePlaceholderReady := False;
  if XC_GetObjectType(GFolderPlaceholderImage) = XC_IMAGE then
    XImage_Destroy(GFolderPlaceholderImage);
  GFolderPlaceholderImage := 0;
  GFolderPlaceholderReady := False;
  if XC_GetObjectType(GAppPlaceholderImage) = XC_IMAGE then
    XImage_Destroy(GAppPlaceholderImage);
  GAppPlaceholderImage := 0;
  GAppPlaceholderReady := False;
  FreeFileTypeImageCache;
  FreeIconCachePathImageCache;
  ReleaseShellImageLists;
end;

function IconTargetPathForShell(const AFilePath: string): string;
var
  targetPath, params, workDir: string;
begin
  Result := Trim(AFilePath);
  if (Result = '') or (not SameText(ExtractFileExt(Result), '.lnk')) then
    Exit;
  if ResolveShortcutInfo(Result, targetPath, params, workDir) and (Trim(targetPath) <> '') then
    Result := targetPath;
end;

function IconToBGRA(const AIcon: HICON; out AW, AH: Integer; out ABits: TBytes): Boolean;
var
  MemDC: HDC;
  Bmi: BITMAPINFO;
  Bits: Pointer;
  Dib: HBITMAP;
  OldObj: HGDIOBJ;
  IconInfo: TIconInfo;
  Bmp: BITMAP;
  W: Integer;
  H: Integer;
  byteCount: Integer;
begin
  Result := False;
  AW := 0;
  AH := 0;
  SetLength(ABits, 0);
  if AIcon = 0 then
    Exit;

  W := GetSystemMetrics(SM_CXICON);
  H := GetSystemMetrics(SM_CYICON);
  if GetIconInfo(AIcon, IconInfo) then
  begin
    try
      if (IconInfo.hbmColor <> 0) and (GetObject(IconInfo.hbmColor, SizeOf(Bmp), @Bmp) <> 0) then
      begin
        W := Bmp.bmWidth;
        H := Bmp.bmHeight;
      end
      else if (IconInfo.hbmMask <> 0) and (GetObject(IconInfo.hbmMask, SizeOf(Bmp), @Bmp) <> 0) then
      begin
        W := Bmp.bmWidth;
        H := Bmp.bmHeight;
        if H > 1 then
          H := H div 2;
      end;
    finally
      if IconInfo.hbmColor <> 0 then
        DeleteObject(IconInfo.hbmColor);
      if IconInfo.hbmMask <> 0 then
        DeleteObject(IconInfo.hbmMask);
    end;
  end;

  if (W <= 0) or (H <= 0) then
    Exit;

  ZeroMemory(@Bmi, SizeOf(Bmi));
  Bmi.bmiHeader.biSize := SizeOf(BITMAPINFOHEADER);
  Bmi.bmiHeader.biWidth := W;
  Bmi.bmiHeader.biHeight := -H;
  Bmi.bmiHeader.biPlanes := 1;
  Bmi.bmiHeader.biBitCount := 32;
  Bmi.bmiHeader.biCompression := BI_RGB;

  MemDC := CreateCompatibleDC(0);
  if MemDC = 0 then
    Exit;
  try
    Dib := CreateDIBSection(MemDC, Bmi, DIB_RGB_COLORS, Bits, 0, 0);
    if (Dib = 0) or (Bits = nil) then
      Exit;
    try
      OldObj := SelectObject(MemDC, Dib);
      try
        PatBlt(MemDC, 0, 0, W, H, BLACKNESS);
        DrawIconEx(MemDC, 0, 0, AIcon, W, H, 0, 0, DI_NORMAL);
        byteCount := W * H * 4;
        SetLength(ABits, byteCount);
        Move(Bits^, ABits[0], byteCount);
        AW := W;
        AH := H;
        Result := True;
      finally
        SelectObject(MemDC, OldObj);
      end;
    finally
      DeleteObject(Dib);
    end;
  finally
    DeleteDC(MemDC);
  end;
end;

function CreateHImageFromPixelData(const AData: TShellIconPixelData): HIMAGE;
begin
  Result := 0;
  if not AData.Ok or (AData.Width <= 0) or (AData.Height <= 0) or (Length(AData.Bits) < AData.Width * AData.Height * 4) then
    Exit;
  Result := XImage_LoadFromData(NativeInt(@AData.Bits[0]), AData.Width, AData.Height);
end;

function BuildListFileImageRequestKey(const AIconCachePath, AFilePath: string;
  AIsFolder: Boolean): string;
var
  iconKey, typeKey: string;
begin
  iconKey := LowerCase(Trim(AIconCachePath));
  if iconKey <> '' then
    Exit(LowerCase(Trim(AFilePath)) + #9 + iconKey);
  typeKey := GetListItemDisplayImageCacheKey(AIconCachePath, AFilePath, AIsFolder);
  if (typeKey <> '') and (Copy(typeKey, 1, 5) <> 'file:') then
    Exit('type:' + typeKey + #9 + iconKey);
  Result := LowerCase(Trim(AFilePath)) + #9 + iconKey;
end;

procedure InitShellIconResolveContext(const AFilePath: string; AIsFolder: Boolean;
  var Ctx: TShellIconResolveContext);
begin
  Ctx.PathForIcon := NormalizeSystem32PathForIcon(IconTargetPathForShell(AFilePath));
  if PathTreatAsFolderForShellIcon(AFilePath, AIsFolder) then
    Ctx.FormatName := 'folder'
  else
    Ctx.FormatName := GetFormatNameFromPath(AFilePath);
  Ctx.GotSysIdx := GetSysIconIndexForShellExtract(AFilePath, Ctx.SysIdx, AIsFolder);
  if not Ctx.GotSysIdx then
    Ctx.SysIdx := -1;
  Ctx.TypeCacheKey := FileTypeCacheKey(Ctx.PathForIcon, Ctx.SysIdx, AIsFolder);
end;

function TryGetBestShellIconFromSysIndex(ASysIdx: Integer; out AHIcon: HICON): Boolean;
var
  ImageList: IShellImageList;
  I: Integer;
  hFileIcon: HICON;
begin
  Result := False;
  AHIcon := 0;
  if (ASysIdx < 0) or not EnsureShellImageListsLoaded then
    Exit;
  for I := Low(cShellImageListLevels) to High(cShellImageListLevels) do
  begin
    ImageList := GShellImageLists[I];
    if ImageList = nil then
      Continue;
    hFileIcon := 0;
    if ImageList.GetIcon(ASysIdx, ILD_NORMAL, hFileIcon) <> S_OK then
      Continue;
    try
      if hFileIcon = 0 then
        Continue;
      if (cShellImageListLevels[I] = SHIL_JUMBO) and IsLikelyTopLeftSmallInJumbo(hFileIcon) then
        Continue;
      AHIcon := hFileIcon;
      hFileIcon := 0;
      Exit(True);
    finally
      if hFileIcon <> 0 then
        DestroyIcon(hFileIcon);
    end;
  end;
end;

function TryAcquireListFileImageInternal(const AIconCachePath, AFilePath: string; out AImage: HIMAGE;
  out AResolvedIconCachePath: string; ACheckFailureSentinel, AAllowShellResolve, AAllowDiskProbe: Boolean;
  AIsFolder: Boolean): Boolean;
var
  cacheKey, displayKey, inferredKey: string;
  cached: HIMAGE;
begin
  Result := False;
  AImage := 0;
  AResolvedIconCachePath := '';
  if ACheckFailureSentinel and IsListFileImageLoadFailed(AIconCachePath, AFilePath, AIsFolder) then
    Exit(True);
  cacheKey := NormalizeIconCachePathKey(AIconCachePath);
  if (cacheKey <> '') and TryAcquireIconCachePathImage(cacheKey, AImage) then
  begin
    AResolvedIconCachePath := cacheKey;
    Exit(True);
  end;
  displayKey := GetListItemDisplayImageCacheKey(AIconCachePath, AFilePath, AIsFolder);
  if (displayKey <> '') and TryGetCachedFileTypeImage(displayKey, cached) then
  begin
    if cached = 0 then
      Exit(True);
    AImage := cached;
    Exit(True);
  end;
  if AAllowDiskProbe and (cacheKey = '') and (Trim(AFilePath) <> '') and (Copy(displayKey, 1, 5) = 'file:') then
  begin
    inferredKey := BuildIconCacheFileName(AFilePath);
    if (inferredKey <> '') and TryAcquireIconCachePathImage(inferredKey, AImage) then
    begin
      AResolvedIconCachePath := inferredKey;
      Exit(True);
    end;
  end;
  if AAllowShellResolve then
    Result := TryResolveListFileTypeIcon(AIconCachePath, AFilePath, AImage, AIsFolder);
end;

function TryAcquireCachedListFileImage(const AIconCachePath, AFilePath: string; out AImage: HIMAGE;
  AIsFolder: Boolean): Boolean;
var
  resolvedPath: string;
begin
  Result := TryAcquireListFileImageInternal(AIconCachePath, AFilePath, AImage, resolvedPath,
    False, True, False, AIsFolder);
end;

function IsListFileImageLoadFailed(const AIconCachePath, AFilePath: string;
  AIsFolder: Boolean): Boolean;
var
  reqKey: string;
begin
  Result := False;
  if (GListFileImageFailureKeys = nil) or (Trim(AFilePath) = '') then
    Exit;
  reqKey := BuildListFileImageRequestKey(AIconCachePath, AFilePath, AIsFolder);
  Result := GListFileImageFailureKeys.IndexOf(reqKey) >= 0;
end;

procedure MarkListFileImageLoadFailed(const AIconCachePath, AFilePath: string;
  AIsFolder: Boolean);
var
  reqKey: string;
begin
  if (GListFileImageFailureKeys = nil) or (Trim(AFilePath) = '') then
    Exit;
  reqKey := BuildListFileImageRequestKey(AIconCachePath, AFilePath, AIsFolder);
  GListFileImageFailureKeys.Add(reqKey);
end;

procedure ClearListFileImageLoadFailure(const AIconCachePath, AFilePath: string;
  AIsFolder: Boolean);
var
  reqKey: string;
  idx: Integer;
begin
  if (GListFileImageFailureKeys = nil) or (Trim(AFilePath) = '') then
    Exit;
  reqKey := BuildListFileImageRequestKey(AIconCachePath, AFilePath, AIsFolder);
  idx := GListFileImageFailureKeys.IndexOf(reqKey);
  if idx >= 0 then
    GListFileImageFailureKeys.Delete(idx);
end;

function TryAcquireMemoryCachedListFileImage(const AIconCachePath, AFilePath: string; out AImage: HIMAGE;
  out AResolvedIconCachePath: string; AIsFolder: Boolean): Boolean;
begin
  Result := TryAcquireListFileImageInternal(AIconCachePath, AFilePath, AImage, AResolvedIconCachePath,
    True, False, True, AIsFolder);
end;

procedure StoreListFileImageToMemoryCache(const AIconCachePath, AFilePath: string;
  const AData: TShellIconPixelData; var AFileImage: HIMAGE);
var
  cacheKey: string;
  existing: HIMAGE;
begin
  if XC_GetObjectType(AFileImage) <> XC_IMAGE then
    Exit;
  if AData.CanCacheByType and (AData.TypeCacheKey <> '') then
  begin
    if TryGetCachedFileTypeImage(AData.TypeCacheKey, existing) and (existing <> 0) then
    begin
      if (AFileImage <> existing) and (XC_GetObjectType(AFileImage) = XC_IMAGE) then
        XImage_Destroy(AFileImage);
      AFileImage := existing;
      Exit;
    end;
    XImage_EnableAutoDestroy(AFileImage, False);
    PutCachedFileTypeImage(AData.TypeCacheKey, AFileImage, False);
    if TryGetCachedFileTypeImage(AData.TypeCacheKey, existing) then
    begin
      if existing <> 0 then
      begin
        if (AFileImage <> existing) and (XC_GetObjectType(AFileImage) = XC_IMAGE) then
          XImage_Destroy(AFileImage);
        AFileImage := existing;
      end
      else
        AFileImage := 0;
    end;
    Exit;
  end;
  cacheKey := NormalizeIconCachePathKey(AIconCachePath);
  if cacheKey = '' then
    cacheKey := NormalizeIconCachePathKey(AData.IconCachePath);
  if cacheKey <> '' then
  begin
    XImage_EnableAutoDestroy(AFileImage, False);
    PutIconCachePathImage(cacheKey, AFileImage);
  end;
end;

function LoadSysIconToHImage(const ARefPath: string; AAttributes: DWORD): HIMAGE;
var
  FileInfo: SHFILEINFOW;
  SysIdx: Integer;
  hFileIcon: HICON;
  img: HIMAGE;
begin
  Result := 0;
  ZeroMemory(@FileInfo, SizeOf(FileInfo));
  if SHGetFileInfoW(PWideChar(ARefPath), AAttributes, FileInfo, SizeOf(FileInfo),
    SHGFI_SYSICONINDEX or SHGFI_LARGEICON or SHGFI_USEFILEATTRIBUTES) = 0 then
    Exit;
  SysIdx := FileInfo.iIcon;
  if SysIdx < 0 then
    Exit;
  if not TryGetBestShellIconFromSysIndex(SysIdx, hFileIcon) then
    Exit;
  try
    img := XImage_LoadFromHICON(hFileIcon);
    if XC_GetObjectType(img) = XC_IMAGE then
    begin
      XImage_EnableAutoDestroy(img, False);
      Exit(img);
    end
    else if img <> 0 then
      XImage_Destroy(img);
  finally
    DestroyIcon(hFileIcon);
  end;
end;

function EnsureFilePlaceholderImage: HIMAGE;
begin
  if GFilePlaceholderReady then
  begin
    Result := GFilePlaceholderImage;
    Exit;
  end;
  GFilePlaceholderReady := True;
  GFilePlaceholderImage := LoadSysIconToHImage(cGenericFileIconRefPath, FILE_ATTRIBUTE_NORMAL);
  Result := GFilePlaceholderImage;
end;

function EnsureFolderPlaceholderImage: HIMAGE;
begin
  if GFolderPlaceholderReady then
  begin
    Result := GFolderPlaceholderImage;
    Exit;
  end;
  GFolderPlaceholderReady := True;
  GFolderPlaceholderImage := LoadSysIconToHImage(cFolderRefPath, FILE_ATTRIBUTE_DIRECTORY);
  Result := GFolderPlaceholderImage;
end;

function EnsureAppPlaceholderImage: HIMAGE;
begin
  if GAppPlaceholderReady then
  begin
    Result := GAppPlaceholderImage;
    Exit;
  end;
  GAppPlaceholderReady := True;
  GAppPlaceholderImage := LoadSysIconToHImage(cAppRefPath, FILE_ATTRIBUTE_NORMAL);
  Result := GAppPlaceholderImage;
end;

function RefListPlaceholderImage(AKind: TListPlaceholderKind; out AImage: HIMAGE): Boolean;
var
  img: HIMAGE;
begin
  Result := False;
  AImage := 0;
  case AKind of
    lpkFolder:
      img := EnsureFolderPlaceholderImage;
    lpkApp:
      img := EnsureAppPlaceholderImage;
  else
    img := EnsureFilePlaceholderImage;
  end;
  if XC_GetObjectType(img) <> XC_IMAGE then
    Exit;
  XImage_AddRef(img);
  AImage := img;
  Result := True;
end;

procedure StorePendingIconPixels(const AKey: string; var AData: TShellIconPixelData);
var
  entry: PShellIconPixelData;
  idx: Integer;
begin
  if (AKey = '') or (not AData.Ok) then
    Exit;
  New(entry);
  FillChar(entry^, SizeOf(entry^), 0);
  entry^.Ok := AData.Ok;
  entry^.Width := AData.Width;
  entry^.Height := AData.Height;
  entry^.IconCachePath := AData.IconCachePath;
  entry^.TypeCacheKey := AData.TypeCacheKey;
  entry^.CanCacheByType := AData.CanCacheByType;
  entry^.Bits := AData.Bits;
  SetLength(AData.Bits, 0);
  GPendingIconPixelLock.Enter;
  try
    idx := GPendingIconPixels.IndexOf(AKey);
    if idx >= 0 then
    begin
      SetLength(PShellIconPixelData(GPendingIconPixels.Objects[idx])^.Bits, 0);
      Dispose(PShellIconPixelData(GPendingIconPixels.Objects[idx]));
      GPendingIconPixels.Delete(idx);
    end;
    GPendingIconPixels.AddObject(AKey, TObject(entry));
  finally
    GPendingIconPixelLock.Leave;
  end;
end;

function TakePendingIconPixels(const AKey: string; out AData: TShellIconPixelData): Boolean;
var
  idx: Integer;
  entry: PShellIconPixelData;
begin
  Result := False;
  FillChar(AData, SizeOf(AData), 0);
  if AKey = '' then
    Exit;
  GPendingIconPixelLock.Enter;
  try
    idx := GPendingIconPixels.IndexOf(AKey);
    if idx < 0 then
      Exit;
    entry := PShellIconPixelData(GPendingIconPixels.Objects[idx]);
    GPendingIconPixels.Delete(idx);
  finally
    GPendingIconPixelLock.Leave;
  end;
  if entry = nil then
    Exit;
  try
    AData := entry^;
    SetLength(entry^.Bits, 0);
    Result := AData.Ok;
  finally
    Dispose(entry);
  end;
end;

procedure DiscardPendingIconPixelEntry(const AKey: string);
var
  idx: Integer;
  entry: PShellIconPixelData;
begin
  if (AKey = '') or (GPendingIconPixelLock = nil) then
    Exit;
  GPendingIconPixelLock.Enter;
  try
    if GPendingIconPixels = nil then
      Exit;
    idx := GPendingIconPixels.IndexOf(AKey);
    if idx < 0 then
      Exit;
    entry := PShellIconPixelData(GPendingIconPixels.Objects[idx]);
    GPendingIconPixels.Delete(idx);
  finally
    GPendingIconPixelLock.Leave;
  end;
  if entry <> nil then
  begin
    SetLength(entry^.Bits, 0);
    Dispose(entry);
  end;
end;

procedure ClearAllPendingIconPixels;
var
  i: Integer;
  entry: PShellIconPixelData;
begin
  if GPendingIconPixelLock = nil then
    Exit;
  GPendingIconPixelLock.Enter;
  try
    if GPendingIconPixels = nil then
      Exit;
    for i := 0 to GPendingIconPixels.Count - 1 do
    begin
      entry := PShellIconPixelData(GPendingIconPixels.Objects[i]);
      if entry <> nil then
      begin
        SetLength(entry^.Bits, 0);
        Dispose(entry);
      end;
    end;
    GPendingIconPixels.Clear;
  finally
    GPendingIconPixelLock.Leave;
  end;
end;

function AcquireListItemFileImage(const AIconCachePath, AFilePath: string;
  out AIconCachePathOut: string): HIMAGE;
var
  cacheKey, resolvedPath, targetPath: string;
begin
  Result := 0;
  AIconCachePathOut := Trim(AIconCachePath);
  cacheKey := NormalizeIconCachePathKey(AIconCachePathOut);

  resolvedPath := Trim(AIconCachePathOut);
  if (resolvedPath <> '') and FileExists(resolvedPath) then
  begin
    if TryAcquireIconCachePathImage(cacheKey, Result) then
      Exit;
    Result := LoadXImageFromFileMemory(resolvedPath);
    if Result <> 0 then
    begin
      XImage_EnableAutoDestroy(Result, False);
      if cacheKey <> '' then
        PutIconCachePathImage(cacheKey, Result);
      XImage_AddRef(Result);
    end;
    Exit;
  end;

  if TryAcquireCachedListFileImage(AIconCachePath, AFilePath, Result) then
    Exit;

  targetPath := IconTargetPathForShell(AFilePath);
  if targetPath = '' then
    targetPath := AFilePath;
  Result := GetItemImageFromParsingPath(targetPath, AIconCachePathOut);
end;

type
  SHSTOCKICONINFO = record
    cbSize: DWORD;
    hIcon: HICON;
    iSysImageIndex: Integer;
    iIcon: Integer;
    szPath: array[0..MAX_PATH - 1] of WideChar;
  end;

function SHGetStockIconInfo(siid: Integer; uFlags: UINT; var psii: SHSTOCKICONINFO): HRESULT; stdcall;
  external 'shell32.dll' name 'SHGetStockIconInfo';

const
  SIID_SHIELD = 77;
  SHGSI_ICON = $000000100;
  SHGSI_SMALLICON = $000000001;

const
  STR_PARSE_PREFER_FOLDER_BROWSING: PWideChar = 'ParseWithPreferredFolderBrowsing';

function EnsureShellImageListsLoaded: Boolean;
var
  ShellModule: HMODULE;
  I: Integer;
  hr: HRESULT;
  listUnk: IUnknown;
begin
  if GShellImageListsReady then
  begin
    Result := Assigned(GSHGetImageListProc);
    Exit;
  end;
  GShellImageListsReady := True;
  Result := False;
  ShellModule := GetModuleHandle('shell32.dll');
  if ShellModule = 0 then
    ShellModule := LoadLibrary('shell32.dll');
  if ShellModule = 0 then
    Exit;
  @GSHGetImageListProc := GetProcAddress(ShellModule, 'SHGetImageList');
  if not Assigned(GSHGetImageListProc) then
    Exit;
  for I := Low(cShellImageListLevels) to High(cShellImageListLevels) do
  begin
    GShellImageLists[I] := nil;
    listUnk := nil;
    hr := GSHGetImageListProc(cShellImageListLevels[I], IID_IImageList, listUnk);
    if Succeeded(hr) and (listUnk <> nil) then
      Supports(listUnk, IShellImageList, GShellImageLists[I]);
  end;
  Result := True;
end;

procedure ReleaseShellImageLists;
var
  I: Integer;
begin
  for I := Low(GShellImageLists) to High(GShellImageLists) do
    GShellImageLists[I] := nil;
  GSHGetImageListProc := nil;
  GShellImageListsReady := False;
end;

function ParseDisplayNameForNavigation(const ItemPath: UnicodeString; out APidl: PItemIDList): HRESULT;
var
  bindCtx: IBindCtx;
  dummy: IUnknown;
  eat: ULONG;
begin
  APidl := nil;
  if ItemPath = '' then
  begin
    Result := E_INVALIDARG;
    Exit;
  end;
  Result := CreateBindCtx(0, bindCtx);
  if Failed(Result) then
    Exit;
  dummy := TInterfacedObject.Create as IUnknown;
  Result := bindCtx.RegisterObjectParam(STR_PARSE_PREFER_FOLDER_BROWSING, dummy);
  if Failed(Result) then
    Exit;
  Result := SHParseDisplayName(PWideChar(ItemPath), bindCtx, APidl, 0, eat);
end;

function IsLikelyTopLeftSmallInJumbo(const AIcon: HICON): Boolean;
var
  IconInfo: TIconInfo;
  Bmp: BITMAP;
  Bmi: BITMAPINFO;
  Bits: array of DWORD;
  hScreenDc: HDC;
  X, Y: Integer;
  Pixel: DWORD;
  MinX, MinY, MaxX, MaxY: Integer;
  NonEmpty: Integer;
  W, H: Integer;
  ContentW, ContentH: Integer;
begin
  Result := False;
  if AIcon = 0 then
    Exit;
  if not GetIconInfo(AIcon, IconInfo) then
    Exit;
  try
    if IconInfo.hbmColor = 0 then
      Exit;
    if GetObject(IconInfo.hbmColor, SizeOf(Bmp), @Bmp) = 0 then
      Exit;

    W := Bmp.bmWidth;
    H := Bmp.bmHeight;
    if (W < 128) or (H < 128) then
      Exit;

    ZeroMemory(@Bmi, SizeOf(Bmi));
    Bmi.bmiHeader.biSize := SizeOf(BITMAPINFOHEADER);
    Bmi.bmiHeader.biWidth := W;
    Bmi.bmiHeader.biHeight := -H;
    Bmi.bmiHeader.biPlanes := 1;
    Bmi.bmiHeader.biBitCount := 32;
    Bmi.bmiHeader.biCompression := BI_RGB;

    SetLength(Bits, W * H);
    hScreenDc := GetDC(0);
    try
      if GetDIBits(hScreenDc, IconInfo.hbmColor, 0, H, @Bits[0], Bmi, DIB_RGB_COLORS) = 0 then
        Exit;
    finally
      ReleaseDC(0, hScreenDc);
    end;

    MinX := W;
    MinY := H;
    MaxX := -1;
    MaxY := -1;
    NonEmpty := 0;
    for Y := 0 to H - 1 do
      for X := 0 to W - 1 do
      begin
        Pixel := Bits[Y * W + X];
        if ((Pixel and $FF000000) <> 0) or ((Pixel and $00FFFFFF) <> 0) then
        begin
          Inc(NonEmpty);
          if X < MinX then MinX := X;
          if Y < MinY then MinY := Y;
          if X > MaxX then MaxX := X;
          if Y > MaxY then MaxY := Y;
        end;
      end;

    if NonEmpty = 0 then
      Exit;

    ContentW := MaxX - MinX + 1;
    ContentH := MaxY - MinY + 1;
    Result :=
      (ContentW <= (W div 2)) and
      (ContentH <= (H div 2)) and
      (MinX <= (W div 8)) and
      (MinY <= (H div 8));
  finally
    if IconInfo.hbmColor <> 0 then
      DeleteObject(IconInfo.hbmColor);
    if IconInfo.hbmMask <> 0 then
      DeleteObject(IconInfo.hbmMask);
  end;
end;

function Fnv1a32(const S: AnsiString): Cardinal;
var
  I: Integer;
begin
  Result := $811C9DC5;
  for I := 1 to Length(S) do
  begin
    Result := Cardinal((UInt64(Result xor Byte(S[I])) * UInt64(16777619)) and $FFFFFFFF);
  end;
end;

function BuildIconCacheFileName(const APath: string): string;
var
  Handle: THandle;
  FindData: TWin32FindDataW;
  Sig: AnsiString;
  Hash: Cardinal;
begin
  FillChar(FindData, SizeOf(FindData), 0);
  Handle := FindFirstFileW(PWideChar(APath), FindData);
  if Handle <> INVALID_HANDLE_VALUE then
    Windows.FindClose(Handle);
  Sig := AnsiString(LowerCase(APath) + '|' +
    IntToStr(FindData.nFileSizeHigh) + ':' + IntToStr(FindData.nFileSizeLow) + '|' +
    IntToStr(FindData.ftLastWriteTime.dwHighDateTime) + ':' + IntToStr(FindData.ftLastWriteTime.dwLowDateTime));
  Hash := Fnv1a32(Sig);
  Result := IntToHex(Hash, 8) + '.png';
end;

function GetFormatNameFromPath(const APath: string): string;
begin
  Result := LowerCase(Trim(ExtractFileExt(APath)));
  if (Result <> '') and (Result[1] = '.') then
    Delete(Result, 1, 1);
end;

function ShouldShellIconByExtensionOnly(const APath: string): Boolean;
var
  fmt: string;
begin
  if Trim(ExtractFileExt(APath)) = '' then
    Exit(False);
  fmt := GetFormatNameFromPath(APath);
  Result := (fmt <> '') and (not SameText(fmt, 'exe')) and (not SameText(fmt, 'msc'));
end;

function BuildExtensionShellRefPath(const AFormat: string): string;
var
  fmt: string;
begin
  fmt := LowerCase(Trim(AFormat));
  if (fmt <> '') and (fmt[1] = '.') then
    Delete(fmt, 1, 1);
  if fmt = '' then
    Result := cFolderRefPath
  else
    Result := cExtensionShellRefBase + fmt;
end;

function PathTreatAsFolderForShellIcon(const APath: string; AIsFolder: Boolean): Boolean;
var
  s: string;
  last: Char;
begin
  if AIsFolder then
    Exit(True);
  s := Trim(APath);
  if s = '' then
    Exit(False);
  last := s[Length(s)];
  Result := (last = '\') or (last = '/');
end;

function ShellQueryPathForIconExtract(const APath: string; AIsFolder: Boolean): string;
var
  pathForIcon: string;
begin
  pathForIcon := NormalizeSystem32PathForIcon(IconTargetPathForShell(APath));
  if pathForIcon = '' then
    Exit('');
  if Trim(ExtractFileExt(pathForIcon)) = '' then
  begin
    if PathTreatAsFolderForShellIcon(pathForIcon, AIsFolder) then
      Exit(cFolderRefPath);
    Exit(cGenericFileIconRefPath);
  end;
  if ShouldShellIconByExtensionOnly(pathForIcon) then
    Exit(BuildExtensionShellRefPath(GetFormatNameFromPath(pathForIcon)));
  Result := pathForIcon;
end;

function ResolveShortcutInfo(const AShortcutPath: string; out ATargetPath, AArguments, AWorkingDir: string): Boolean;
var
  hLoad: HRESULT;
  hGetPath: HRESULT;
  hGetArgs: HRESULT;
  hGetWorkDir: HRESULT;
  pShellLink: IShellLinkW;
  pPersistFile: IPersistFile;
  wTargetPath: array[0..MAX_PATH - 1] of WideChar;
  wArguments: array[0..1023] of WideChar;
  wWorkingDir: array[0..MAX_PATH - 1] of WideChar;
  findData: TWin32FindDataW;
begin
  Result := False;
  ATargetPath := '';
  AArguments := '';
  AWorkingDir := '';
  hLoad := CoCreateInstance(CLSID_ShellLink, nil, CLSCTX_INPROC_SERVER, IShellLinkW, pShellLink);
  if Failed(hLoad) then
    Exit;
  pPersistFile := pShellLink as IPersistFile;
  hLoad := pPersistFile.Load(PWideChar(AShortcutPath), STGM_READ);
  if Failed(hLoad) then
    Exit;
  pShellLink.Resolve(0, SLR_NO_UI or SLR_NOSEARCH);
  ZeroMemory(@wTargetPath, SizeOf(wTargetPath));
  ZeroMemory(@wArguments, SizeOf(wArguments));
  ZeroMemory(@wWorkingDir, SizeOf(wWorkingDir));
  ZeroMemory(@findData, SizeOf(findData));
  hGetPath := pShellLink.GetPath(wTargetPath, MAX_PATH, findData, SLGP_UNCPRIORITY);
  hGetArgs := pShellLink.GetArguments(wArguments, Length(wArguments));
  hGetWorkDir := pShellLink.GetWorkingDirectory(wWorkingDir, MAX_PATH);
  if Succeeded(hGetPath) and (wTargetPath[0] <> #0) then
  begin
    ATargetPath := NormalizeProgramFilesPathForWow64(wTargetPath);
    if Succeeded(hGetArgs) then
      AArguments := Trim(wArguments);
    if Succeeded(hGetWorkDir) then
      AWorkingDir := NormalizeProgramFilesPathForWow64(Trim(wWorkingDir));
    Result := True;
  end;
end;

function LoadXImageFromFileMemory(const AFilePath: string): Integer;
var
  fs: TFileStream;
  buf: TBytes;
  size: Integer;
begin
  Result := 0;
  if not FileExists(AFilePath) then
    Exit;
  fs := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
  try
    size := fs.Size;
    if size <= 0 then
      Exit;
    SetLength(buf, size);
    fs.ReadBuffer(buf[0], size);
    Result := XImage_LoadMemory(NativeInt(@buf[0]), size);
  finally
    fs.Free;
  end;
end;

procedure CalcImageFitSize(ASrcW, ASrcH, AMaxW, AMaxH: Integer; out ADstW, ADstH: Integer);
begin
  if (ASrcW <= 0) or (ASrcH <= 0) then
  begin
    ADstW := AMaxW;
    ADstH := AMaxH;
    Exit;
  end;
  if (ASrcW <= AMaxW) and (ASrcH <= AMaxH) then
  begin
    ADstW := ASrcW;
    ADstH := ASrcH;
    Exit;
  end;
  if (ASrcW * AMaxH) >= (ASrcH * AMaxW) then
  begin
    ADstW := AMaxW;
    ADstH := MulDiv(ASrcH, AMaxW, ASrcW);
  end
  else
  begin
    ADstH := AMaxH;
    ADstW := MulDiv(ASrcW, AMaxH, ASrcH);
  end;
  if ADstW < 1 then
    ADstW := 1;
  if ADstH < 1 then
    ADstH := 1;
end;

function GetListItemDisplayImageCacheKeyWithSysIdx(const AIconCachePath, AFilePath: string;
  AIsFolder: Boolean; AGotSysIdx: Boolean; ASysIdx: Integer): string;
var
  fn, fmt: string;
  sysIdx: Integer;
begin
  fn := NormalizeIconCachePathKey(AIconCachePath);
  if IsPerFileShellIconCacheFileName(fn) then
    Exit(ChangeFileExt(fn, ''));
  if AFilePath = '' then
  begin
    if fn <> '' then
      Result := ChangeFileExt(fn, '')
    else
      Result := '';
    Exit;
  end;
  if Trim(ExtractFileExt(AFilePath)) = '' then
  begin
    if AGotSysIdx then
      sysIdx := ASysIdx
    else if not GetSysIconIndexForShellExtract(AFilePath, sysIdx, AIsFolder) then
      sysIdx := -1;
    Result := FileTypeCacheKey(AFilePath, sysIdx, AIsFolder);
    if Result <> '' then
      Exit;
    if fn <> '' then
      Exit(ChangeFileExt(fn, ''))
    else
      Exit('file:' + IntToHex(Fnv1a32(AnsiString(LowerCase(AFilePath))), 8));
  end;
  fmt := GetFormatNameFromPath(AFilePath);
  if SameText(fmt, 'exe') then
  begin
    if AGotSysIdx then
      sysIdx := ASysIdx
    else if not GetSysIconIndexForShellExtract(AFilePath, sysIdx, AIsFolder) then
      sysIdx := -1;
    if IsDefaultExeSysIconIndex(sysIdx) then
      Exit(cDefaultExeFileTypeCacheKey);
    if fn <> '' then
      Exit(ChangeFileExt(fn, ''))
    else
      Exit('file:' + IntToHex(Fnv1a32(AnsiString(LowerCase(AFilePath))), 8));
  end;
  if (fmt <> '') and (not SameText(fmt, 'msc')) then
    Exit(fmt);
  if fn <> '' then
    Result := ChangeFileExt(fn, '')
  else
    Result := 'file:' + IntToHex(Fnv1a32(AnsiString(LowerCase(AFilePath))), 8);
end;

function GetListItemDisplayImageCacheKey(const AIconCachePath, AFilePath: string;
  AIsFolder: Boolean): string;
begin
  Result := GetListItemDisplayImageCacheKeyWithSysIdx(AIconCachePath, AFilePath, AIsFolder, False, -1);
end;

procedure RemoveIconCachePathImageEntry(const ACacheKey: string);
var
  idx: Integer;
  v: NativeInt;
begin
  if (ACacheKey = '') or (GIconCachePathImageCache = nil) then
    Exit;
  idx := GIconCachePathImageCache.IndexOf(ACacheKey);
  if idx < 0 then
    Exit;
  v := NativeInt(GIconCachePathImageCache.Objects[idx]);
  if XC_GetObjectType(v) = XC_IMAGE then
    XImage_Destroy(HIMAGE(v));
  GIconCachePathImageCache.Delete(idx);
end;

procedure InvalidateListItemIconCaches(const AIconCachePath, AFilePath: string;
  AIsFolder: Boolean);
var
  cacheKey: string;
begin
  cacheKey := NormalizeIconCachePathKey(AIconCachePath);
  if cacheKey <> '' then
    RemoveIconCachePathImageEntry(cacheKey);
  ClearListFileImageLoadFailure(AIconCachePath, AFilePath, AIsFolder);
end;

function ResampleBGRAToHImage(const ABits: TBytes; ASrcW, ASrcH, AMaxW, AMaxH: Integer): HIMAGE;
var
  SrcBmp, DstBmp: TGPBitmap;
  G: TGPGraphics;
  DstRect: TGPRectF;
  BD: TBitmapData;
  DstW, DstH: Integer;
begin
  Result := 0;
  if (AMaxW <= 0) or (AMaxH <= 0) or (ASrcW <= 0) or (ASrcH <= 0) or
     (Length(ABits) < ASrcW * ASrcH * 4) then
    Exit;
  CalcImageFitSize(ASrcW, ASrcH, AMaxW, AMaxH, DstW, DstH);
  if (DstW >= ASrcW) and (DstH >= ASrcH) then
    Exit(XImage_LoadFromData(NativeInt(@ABits[0]), ASrcW, ASrcH));

  SrcBmp := TGPBitmap.Create(ASrcW, ASrcH, ASrcW * 4, PixelFormat32bppARGB, @ABits[0]);
  try
    if SrcBmp.GetLastStatus <> Ok then
      Exit;
    DstBmp := TGPBitmap.Create(DstW, DstH, PixelFormat32bppARGB);
    try
      if DstBmp.GetLastStatus <> Ok then
        Exit;
      G := TGPGraphics.Create(DstBmp);
      try
        if G.GetLastStatus <> Ok then
          Exit;
        G.SetInterpolationMode(InterpolationModeHighQualityBicubic);
        G.SetPixelOffsetMode(PixelOffsetModeHighQuality);
        G.SetSmoothingMode(SmoothingModeHighQuality);
        G.Clear(0);
        DstRect.X := 0;
        DstRect.Y := 0;
        DstRect.Width := DstW;
        DstRect.Height := DstH;
        if G.DrawImage(SrcBmp, DstRect, 0, 0, ASrcW, ASrcH, UnitPixel) <> Ok then
          Exit;
      finally
        G.Free;
      end;
      if DstBmp.LockBits(MakeRect(0, 0, DstW, DstH), ImageLockModeRead, PixelFormat32bppARGB, BD) <> Ok then
        Exit;
      try
        Result := XImage_LoadFromData(NativeInt(BD.Scan0), DstW, DstH);
      finally
        DstBmp.UnlockBits(BD);
      end;
    finally
      DstBmp.Free;
    end;
  finally
    SrcBmp.Free;
  end;
end;

function LoadImageFromIconData(const AIcon: HICON): HIMAGE;
var
  srcW, srcH: Integer;
  bits: TBytes;
begin
  Result := 0;
  if not IconToBGRA(AIcon, srcW, srcH, bits) then
    Exit;
  Result := XImage_LoadFromData(NativeInt(@bits[0]), srcW, srcH);
end;

function GetApplicationIcon: HICON;
var
  inst: HINST;
  largeIcon: HICON;
  smallIcon: HICON;
begin
  inst := HINST(GetModuleHandle(nil));
  Result := HICON(LoadImage(inst, PChar('MAINICON'), IMAGE_ICON, 0, 0, LR_DEFAULTCOLOR));
  if Result = 0 then
    Result := HICON(LoadImage(inst, PChar('Icon'), IMAGE_ICON, 0, 0, LR_DEFAULTCOLOR));
  if Result = 0 then
    Result := HICON(LoadImage(inst, MAKEINTRESOURCE(1), IMAGE_ICON, 0, 0, LR_DEFAULTCOLOR));
  if Result = 0 then
  begin
    largeIcon := 0;
    smallIcon := 0;
    if ExtractIconEx(PChar(ParamStr(0)), 0, largeIcon, smallIcon, 1) > 0 then
      Result := largeIcon;
  end;
end;

function LoadApplicationIconToHImage(ADstW, ADstH: Integer): HIMAGE;
var
  appIcon: HICON;
  srcW, srcH: Integer;
  bits: TBytes;
begin
  Result := 0;
  if (ADstW <= 0) or (ADstH <= 0) then
    Exit;
  appIcon := GetApplicationIcon;
  if appIcon = 0 then
    Exit;
  try
    if IconToBGRA(appIcon, srcW, srcH, bits) then
      Result := ResampleBGRAToHImage(bits, srcW, srcH, ADstW, ADstH);
  finally
    DestroyIcon(appIcon);
  end;
end;

function GetShieldIconSmall: HICON;
var
  s: SHSTOCKICONINFO;
begin
  Result := 0;
  ZeroMemory(@s, SizeOf(s));
  s.cbSize := SizeOf(s);
  if Succeeded(SHGetStockIconInfo(SIID_SHIELD, SHGSI_ICON or SHGSI_SMALLICON, s)) then
    Result := s.hIcon;
end;

function GetSysIconIndexForPath(const APath: UnicodeString; APidl: PItemIDList; out SysIdx: Integer): Boolean;
var
  FileInfo: SHFILEINFOW;
begin
  SysIdx := 0;
  ZeroMemory(@FileInfo, SizeOf(FileInfo));
  if APidl <> nil then
    Result := SHGetFileInfoW(PWideChar(Pointer(APidl)), 0, FileInfo, SizeOf(FileInfo),
      SHGFI_PIDL or SHGFI_SYSICONINDEX or SHGFI_LARGEICON) <> 0
  else
    Result := SHGetFileInfoW(PWideChar(APath), FILE_ATTRIBUTE_NORMAL, FileInfo, SizeOf(FileInfo),
      SHGFI_SYSICONINDEX or SHGFI_LARGEICON) <> 0;
  if Result then
    SysIdx := FileInfo.iIcon;
end;

function ShellIconAttributesForPath(const AQueryPath: string): DWORD;
begin
  if SameText(AQueryPath, cFolderRefPath) then
    Result := FILE_ATTRIBUTE_DIRECTORY
  else
    Result := FILE_ATTRIBUTE_NORMAL;
end;

function GetSysIconIndexForShellExtract(const APath: string; out ASysIdx: Integer;
  AIsFolder: Boolean): Boolean;
var
  pathForIcon, shellPath: string;
  itemPidl: PItemIDList;
  hr: HRESULT;
  FileInfo: SHFILEINFOW;
begin
  ASysIdx := -1;
  pathForIcon := NormalizeSystem32PathForIcon(IconTargetPathForShell(APath));
  if pathForIcon = '' then
    Exit(False);

  if ShouldShellIconByExtensionOnly(pathForIcon) or (Trim(ExtractFileExt(pathForIcon)) = '') then
  begin
    shellPath := ShellQueryPathForIconExtract(APath, AIsFolder);
    ZeroMemory(@FileInfo, SizeOf(FileInfo));
    Result := SHGetFileInfoW(PWideChar(shellPath), ShellIconAttributesForPath(shellPath), FileInfo,
      SizeOf(FileInfo), SHGFI_SYSICONINDEX or SHGFI_LARGEICON or SHGFI_USEFILEATTRIBUTES) <> 0;
    if Result then
      ASysIdx := FileInfo.iIcon;
    Exit;
  end;

  itemPidl := nil;
  hr := ParseDisplayNameForNavigation(pathForIcon, itemPidl);
  if Succeeded(hr) and (itemPidl <> nil) then
  begin
    try
      if GetSysIconIndexForPath('', itemPidl, ASysIdx) then
        Exit(True);
    finally
      ILFree(itemPidl);
    end;
  end;

  if FileExists(pathForIcon) and GetSysIconIndexForPath(pathForIcon, nil, ASysIdx) then
    Exit(True);

  ZeroMemory(@FileInfo, SizeOf(FileInfo));
  Result := SHGetFileInfoW(PWideChar(pathForIcon), ShellIconAttributesForPath(pathForIcon), FileInfo,
    SizeOf(FileInfo), SHGFI_SYSICONINDEX or SHGFI_LARGEICON or SHGFI_USEFILEATTRIBUTES) <> 0;
  if Result then
    ASysIdx := FileInfo.iIcon;
end;

function TryResolveListFileTypeIcon(const AIconCachePath, AFilePath: string; out AImage: HIMAGE;
  AIsFolder: Boolean): Boolean;
var
  img: HIMAGE;
  pixel: TShellIconPixelData;
  ctx: TShellIconResolveContext;
  pathForIcon: string;
begin
  Result := False;
  AImage := 0;
  pathForIcon := Trim(AFilePath);
  if pathForIcon = '' then
    Exit;
  InitShellIconResolveContext(pathForIcon, AIsFolder, ctx);
  if SameText(ctx.FormatName, 'exe') then
  begin
    if not IsDefaultExeSysIconIndex(ctx.SysIdx) then
      Exit;
    if not TryGetShellTypeIcon(pathForIcon, img, AIsFolder) then
      Exit;
    if XC_GetObjectType(img) <> XC_IMAGE then
    begin
      if img <> 0 then
        XImage_Destroy(img);
      Exit;
    end;
    FillChar(pixel, SizeOf(pixel), 0);
    pixel.CanCacheByType := True;
    pixel.TypeCacheKey := cDefaultExeFileTypeCacheKey;
    pixel.IconCachePath := cDefaultExeIconFileName;
    StoreListFileImageToMemoryCache(AIconCachePath, pathForIcon, pixel, img);
    if XC_GetObjectType(img) <> XC_IMAGE then
      Exit;
    AImage := img;
    Exit(True);
  end;
  if SameText(ctx.FormatName, 'msc') then
    Exit;
  if ctx.FormatName = '' then
    Exit;
  if not TryGetShellTypeIcon(pathForIcon, img, AIsFolder) then
    Exit;
  if XC_GetObjectType(img) <> XC_IMAGE then
  begin
    if img <> 0 then
      XImage_Destroy(img);
    Exit;
  end;
  FillChar(pixel, SizeOf(pixel), 0);
  pixel.CanCacheByType := True;
  pixel.TypeCacheKey := GetListItemDisplayImageCacheKeyWithSysIdx(AIconCachePath, pathForIcon, AIsFolder,
    ctx.GotSysIdx, ctx.SysIdx);
  pixel.IconCachePath := FileTypeIconCacheFileName(ctx.FormatName, ctx.SysIdx);
  StoreListFileImageToMemoryCache(AIconCachePath, pathForIcon, pixel, img);
  if XC_GetObjectType(img) <> XC_IMAGE then
    Exit;
  AImage := img;
  Result := True;
end;

function TryExtractShellIconPixelsFromFileInfo(const pathForIcon: string; AUseFileAttributes: Boolean;
  var AData: TShellIconPixelData; AIsFolder: Boolean): Boolean;
var
  FileInfo: SHFILEINFOW;
  flags: UINT;
  srcW, srcH: Integer;
  queryPath: string;
begin
  Result := False;
  ZeroMemory(@FileInfo, SizeOf(FileInfo));
  if AUseFileAttributes then
  begin
    flags := SHGFI_ICON or SHGFI_LARGEICON or SHGFI_USEFILEATTRIBUTES;
    queryPath := ShellQueryPathForIconExtract(pathForIcon, AIsFolder);
  end
  else
  begin
    flags := SHGFI_ICON or SHGFI_LARGEICON;
    queryPath := pathForIcon;
  end;
  if SHGetFileInfoW(PWideChar(queryPath), ShellIconAttributesForPath(queryPath), FileInfo,
    SizeOf(FileInfo), flags) = 0 then
    Exit;
  try
    if (FileInfo.hIcon <> 0) and IconToBGRA(FileInfo.hIcon, srcW, srcH, AData.Bits) then
    begin
      AData.Width := srcW;
      AData.Height := srcH;
      AData.Ok := True;
      Result := True;
    end;
  finally
    if FileInfo.hIcon <> 0 then
      DestroyIcon(FileInfo.hIcon);
  end;
end;

function LoadImageFileToPixelData(const AFilePath: string; out AData: TShellIconPixelData): Boolean;
var
  SrcBmp: TGPBitmap;
  BD: TBitmapData;
  byteCount: Integer;
begin
  Result := False;
  FillChar(AData, SizeOf(AData), 0);
  if not FileExists(AFilePath) then
    Exit;
  SrcBmp := TGPBitmap.Create(AFilePath);
  try
    if SrcBmp.GetLastStatus <> Ok then
      Exit;
    AData.Width := SrcBmp.GetWidth;
    AData.Height := SrcBmp.GetHeight;
    if (AData.Width <= 0) or (AData.Height <= 0) then
      Exit;
    if SrcBmp.LockBits(MakeRect(0, 0, AData.Width, AData.Height), ImageLockModeRead, PixelFormat32bppARGB, BD) <> Ok then
      Exit;
    try
      byteCount := AData.Width * AData.Height * 4;
      SetLength(AData.Bits, byteCount);
      Move(BD.Scan0^, AData.Bits[0], byteCount);
      AData.Ok := True;
      Result := True;
    finally
      SrcBmp.UnlockBits(BD);
    end;
  finally
    SrcBmp.Free;
  end;
end;

function ExtractShellIconPixels(const APath: string; const AIconCachePath: string;
  out AData: TShellIconPixelData; AIsFolder: Boolean): Boolean;
var
  pathForIcon, hintPath: string;
  ctx: TShellIconResolveContext;
  hFileIcon: HICON;
  canCacheByType: Boolean;
  srcW, srcH: Integer;
begin
  Result := False;
  FillChar(AData, SizeOf(AData), 0);
  hintPath := Trim(AIconCachePath);
  if (hintPath <> '') and FileExists(hintPath) then
  begin
    if LoadImageFileToPixelData(hintPath, AData) then
    begin
      AData.IconCachePath := hintPath;
      Exit(True);
    end;
  end;

  pathForIcon := NormalizeSystem32PathForIcon(IconTargetPathForShell(APath));
  if pathForIcon = '' then
    Exit;

  InitShellIconResolveContext(APath, AIsFolder, ctx);
  canCacheByType := (ctx.TypeCacheKey <> '') and not ShouldSkipFileTypeCacheKey(ctx.TypeCacheKey);
  AData.CanCacheByType := canCacheByType;
  AData.TypeCacheKey := ctx.TypeCacheKey;
  if canCacheByType then
  begin
    if SameText(ctx.TypeCacheKey, cDefaultFileTypeCacheKey) then
      AData.IconCachePath := FileTypeIconCacheFileName('', ctx.SysIdx)
    else if SameText(ctx.TypeCacheKey, cDefaultExeFileTypeCacheKey) then
      AData.IconCachePath := cDefaultExeIconFileName
    else
      AData.IconCachePath := FileTypeIconCacheFileName(ctx.TypeCacheKey, ctx.SysIdx);
  end
  else
    AData.IconCachePath := BuildIconCacheFileName(APath);

  if ctx.GotSysIdx and TryGetBestShellIconFromSysIndex(ctx.SysIdx, hFileIcon) then
  begin
    try
      if IconToBGRA(hFileIcon, srcW, srcH, AData.Bits) then
      begin
        AData.Width := srcW;
        AData.Height := srcH;
        AData.Ok := True;
        Exit(True);
      end;
    finally
      DestroyIcon(hFileIcon);
    end;
  end;

  if ShouldShellIconByExtensionOnly(pathForIcon) then
    Exit;
  Result := TryExtractShellIconPixelsFromFileInfo(pathForIcon, False, AData, AIsFolder);
  if not Result then
    Result := TryExtractShellIconPixelsFromFileInfo(pathForIcon, True, AData, AIsFolder);
end;

function GetItemImageFromParsingPath(const APath: string; out AIconCachePath: string): HIMAGE;
var
  data: TShellIconPixelData;
  cached: HIMAGE;
begin
  Result := 0;
  AIconCachePath := '';
  if not ExtractShellIconPixels(APath, '', data) then
    Exit;
  AIconCachePath := data.IconCachePath;
  if data.CanCacheByType and (data.TypeCacheKey <> '') then
  begin
    if TryGetCachedFileTypeImage(data.TypeCacheKey, cached) then
    begin
      if cached <> 0 then
        Result := cached;
      Exit;
    end;
  end;
  Result := CreateHImageFromPixelData(data);
  if Result <> 0 then
    StoreListFileImageToMemoryCache('', APath, data, Result);
end;

function GetListViewFileItemFromParsingPath(const AFullPath: string; ALoadIcon: Boolean): TListViewFileItem;
var
  P: string;
  targetPath: string;
  params: string;
  workDir: string;
  displayName: string;
begin
  P := Trim(AFullPath);
  if P = '' then
    exit;
  targetPath := P;
  params := '';
  workDir := ExtractFilePath(targetPath);
  displayName := ExtractFileName(targetPath);
  if SameText(ExtractFileExt(P), '.lnk') then
  begin
    displayName := ChangeFileExt(ExtractFileName(P), '');
    if not ResolveShortcutInfo(P, targetPath, params, workDir) then
      targetPath := P;
  end;
  Result.IconCachePath := '';
  Result.FilePath := targetPath;
  Result.FileName := displayName;
  if Result.FileName = '' then
    Result.FileName := targetPath;
  if SameText(ExtractFileExt(Result.FileName), '.lnk') then
    Result.FileName := ChangeFileExt(Result.FileName, '');
  Result.FileParams := params;
  if workDir = '' then
    workDir := ExtractFilePath(targetPath);
  Result.WorkingDir := workDir;
  Result.ShowCmd := SW_SHOWNORMAL;
  Result.DisplayTitle := ListViewItemDisplayTitle(Result);
  if ALoadIcon then
    Result.FileImage := GetItemImageFromParsingPath(targetPath, Result.IconCachePath)
  else
    Result.FileImage := 0;
  if not SameText(ExtractFileExt(targetPath), '.exe') then
    Result.IconCachePath := '';
  Result.InsertOrder := -1;
  Result.ItemGroupIndex := -1;
end;

function CreateSortedStrList: TStringList;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := False;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
end;

initialization
  GFileTypeImageCache := CreateSortedStrList;
  GIconCachePathImageCache := CreateSortedStrList;
  GPendingIconPixels := CreateSortedStrList;
  GPendingIconPixelLock := TCriticalSection.Create;
  GListFileImageFailureKeys := CreateSortedStrList;
  EnsureShellImageListsLoaded;

finalization
  ClearAllPendingIconPixels;
  FreeAndNil(GPendingIconPixels);
  FreeAndNil(GPendingIconPixelLock);
  FreeAndNil(GListFileImageFailureKeys);
  ReleaseFileTypeImageCache;

end.
