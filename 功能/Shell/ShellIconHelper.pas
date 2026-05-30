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
  TShellIconCachePaths = record
    IconCacheDirectory: string;
    FileTypeIconDirectory: string;
  end;

  TShellIconInfo = record
    IconIndex: Integer;
    OverlayIndex: Integer;
  end;

function ExtractShellIconParts(iconIndexAndOverlay: Integer): TShellIconInfo;
function ParseDisplayNameForNavigation(const ItemPath: UnicodeString; out APidl: PItemIDList): HRESULT;
function GetListViewFileItemFromParsingPath(const AFullPath: string;
  const ACachePaths: TShellIconCachePaths): TListViewFileItem;
function LoadXImageFromFileMemory(const AFilePath: string): Integer;
function ResolveListItemIconFilePath(const AIconCachePath, AFilePath: string;
  const APaths: TShellIconCachePaths): string;
function ResampleIconFileToHImage(const APngPath: string; AMaxW, AMaxH: Integer): HIMAGE;
function GetListItemDisplayImageCacheKey(const AIconCachePath, AFilePath: string): string;
function TryAcquireSharedDisplayImage(const ACacheKey: string; AIconSide: Integer; out AImage: Integer): Boolean;
procedure PutSharedDisplayImage(const ACacheKey: string; AIconSide: Integer; AImage: Integer);
procedure ClearListDisplayImageCache;
function ImageListIconToHIMAGE(const AImageList: IUnknown; iconIndex: Integer; const ACachePngPath: string = ''): HIMAGE;
function GetItemImageFromParsingPath(const APath: string; out AIconCachePath: string;
  const ACachePaths: TShellIconCachePaths): HIMAGE;
function AcquireListItemFileImage(const AIconCachePath, AFilePath: string;
  const ACachePaths: TShellIconCachePaths; out AIconCachePathOut: string): HIMAGE;
function LoadImageFromIconData(const AIcon: HICON; const ACachePath: string = ''): HIMAGE;
function GetShieldIconSmall: HICON;
procedure ReleaseFileTypeImageCache;

implementation

uses
  ShellAPI,
  ActiveX,
  CommCtrl,
  GDIPAPI,
  GDIPOBJ,
  AppConfig,
  ShellPathHelper;

type
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
  cDefaultFileTypeCacheKey = 'default';
  cDefaultExeFileTypeCacheKey = 'exe';
  cDefaultExeIconFileName = 'exe.png';
  SHIL_SMALL = 0;
  SHIL_LARGE = 1;
  SHIL_EXTRALARGE = 2;
  SHIL_JUMBO = 4;
  IID_IImageList: TGUID = '{46EB5926-582E-4017-9FDF-E8998DAA0950}';
  /// <summary>与 GetItemImageFromParsingPath 回退顺序一致：JUMBO → EXTRALARGE → LARGE → SMALL。</summary>
  cShellImageListLevels: array[0..3] of Integer = (SHIL_JUMBO, SHIL_EXTRALARGE, SHIL_LARGE, SHIL_SMALL);

var
  // 非 EXE 类型：按类型键（扩展名 / folder / default）缓存 HIMAGE，避免重复 IO/解码。
  // Objects[] 里存 NativeInt：
  //   >= 0: HIMAGE 句柄
  //   -1 : 加载失败（失败哨兵，避免重复尝试）
  GFileTypeImageCache: TStringList;
  /// <summary>按 IconCache 文件名（如 txt.png、8 位哈希 png）共享 HIMAGE，列表项持有 AddRef。</summary>
  GIconCachePathImageCache: TStringList;
  /// <summary>列表预缩放图：键为「类型键#边长」，非 exe 同类型同边长共一柄。</summary>
  GListDisplayImageCache: TStringList;
  GDefaultFileTypeSysIconIndex: Integer = -1;
  GDefaultFileTypeSysIconIndexReady: Boolean = False;
  GDefaultExeSysIconIndex: Integer = -1;
  GDefaultExeSysIconIndexReady: Boolean = False;
  GShellImageLists: array[0..3] of IShellImageList;
  GSHGetImageListProc: TSHGetImageList = nil;
  GShellImageListsReady: Boolean = False;

function GetFormatNameFromPath(const APath: string): string; forward;
function EnsureShellImageListsLoaded: Boolean; forward;
procedure ReleaseShellImageLists; forward;
function GetSysIconIndexForPath(const APath: UnicodeString; APidl: PItemIDList; out SysIdx: Integer): Boolean; forward;
function ShellFileTypeIconFullPath(const APaths: TShellIconCachePaths; const AFileName: string): string; forward;
function ShellIconCacheFullPath(const APaths: TShellIconCachePaths; const AFileName: string): string; forward;

function GetDefaultFileTypeSysIconIndex: Integer;
const
  // 无关联扩展名；SHGFI_USEFILEATTRIBUTES 不要求文件真实存在。
  cDefRefPath = 'X:\__qdesktop_default_icon_ref.qdiconref';
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
  if SHGetFileInfoW(PWideChar(cDefRefPath), FILE_ATTRIBUTE_NORMAL, FileInfo, SizeOf(FileInfo),
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

function FileTypeCacheKey(const APath: string; ASysIconIndex: Integer): string;
begin
  if DirectoryExists(APath) then
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
  else if IsDefaultFileTypeSysIconIndex(ASysIconIndex) then
    Result := cDefaultFileTypeIconFileName
  else if AFormat <> '' then
    Result := AFormat + '.png'
  else
    Result := '';
end;

function ResolveFileTypeIconDiskPath(const APaths: TShellIconCachePaths; const AFormat: string;
  ASysIconIndex: Integer): string;
begin
  if SameText(AFormat, 'folder') then
    Exit(ShellFileTypeIconFullPath(APaths, 'folder.png'));
  if SameText(AFormat, 'exe') and IsDefaultExeSysIconIndex(ASysIconIndex) then
    Exit(ShellFileTypeIconFullPath(APaths, cDefaultExeIconFileName));
  if IsDefaultFileTypeSysIconIndex(ASysIconIndex) then
    Exit(ShellFileTypeIconFullPath(APaths, cDefaultFileTypeIconFileName));
  if AFormat <> '' then
    Result := ShellFileTypeIconFullPath(APaths, AFormat + '.png')
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
  v: NativeInt;
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
  v := NativeInt(GFileTypeImageCache.Objects[idx]);
  if v = -1 then
  begin
    Result := True; // 命中“失败哨兵”
    Exit;
  end;
  if v > 0 then
  begin
    AImage := HIMAGE(v);
    // 与列表项 ClearItems 中的 XImage_Release 成对；同类型多行共享一柄时需各自占用引用。
    XImage_AddRef(AImage);
    Result := True;
  end;
end;

procedure PutCachedFileTypeImage(const ACacheKey: string; const AImage: HIMAGE; const AFailed: Boolean);
var
  idx: Integer;
  v: NativeInt;
begin
  if GFileTypeImageCache = nil then
    Exit;
  if ShouldSkipFileTypeCacheKey(ACacheKey) then
    Exit;
  idx := GFileTypeImageCache.IndexOf(ACacheKey);
  if AFailed then
    v := -1
  else
    v := NativeInt(AImage);
  if idx < 0 then
    GFileTypeImageCache.AddObject(ACacheKey, TObject(v))
  else
    GFileTypeImageCache.Objects[idx] := TObject(v);
end;

procedure FreeFileTypeImageCache;
var
  i: Integer;
  v: NativeInt;
begin
  if GFileTypeImageCache = nil then
    Exit;
  for i := 0 to GFileTypeImageCache.Count - 1 do
  begin
    v := NativeInt(GFileTypeImageCache.Objects[i]);
    if XC_GetObjectType(v) = XC_IMAGE then
      XImage_Destroy(HIMAGE(v));
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
  AImage := HIMAGE(v);
  XImage_AddRef(AImage);
  Result := True;
end;

procedure PutIconCachePathImage(const ACacheKey: string; const AImage: HIMAGE);
var
  idx: Integer;
begin
  if (GIconCachePathImageCache = nil) or (ACacheKey = '') then
    Exit;
  if XC_GetObjectType(AImage) <> XC_IMAGE then
    Exit;
  idx := GIconCachePathImageCache.IndexOf(ACacheKey);
  if idx < 0 then
    GIconCachePathImageCache.AddObject(ACacheKey, TObject(NativeInt(AImage)))
  else
    GIconCachePathImageCache.Objects[idx] := TObject(NativeInt(AImage));
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

procedure ClearListDisplayImageCache;
var
  i: Integer;
  v: NativeInt;
begin
  if GListDisplayImageCache = nil then
    Exit;
  for i := 0 to GListDisplayImageCache.Count - 1 do
  begin
    v := NativeInt(GListDisplayImageCache.Objects[i]);
    if v > 0 then
      XImage_Release(HIMAGE(v));
  end;
  GListDisplayImageCache.Clear;
end;

procedure ReleaseFileTypeImageCache;
begin
  ClearListDisplayImageCache;
  FreeFileTypeImageCache;
  FreeIconCachePathImageCache;
  ReleaseShellImageLists;
end;

function AcquireListItemFileImage(const AIconCachePath, AFilePath: string;
  const ACachePaths: TShellIconCachePaths; out AIconCachePathOut: string): HIMAGE;
var
  cacheKey, iconPath: string;
begin
  Result := 0;
  AIconCachePathOut := Trim(AIconCachePath);
  cacheKey := NormalizeIconCachePathKey(AIconCachePathOut);
  if cacheKey <> '' then
  begin
    if TryAcquireIconCachePathImage(cacheKey, Result) then
      Exit;
    iconPath := ShellIconCacheFullPath(ACachePaths, cacheKey);
    if not FileExists(iconPath) then
      iconPath := ResolveListItemIconFilePath(AIconCachePathOut, AFilePath, ACachePaths);
    if (iconPath <> '') and FileExists(iconPath) then
    begin
      Result := LoadXImageFromFileMemory(iconPath);
      if Result <> 0 then
      begin
        XImage_EnableAutoDestroy(Result, False);
        PutIconCachePathImage(cacheKey, Result);
        XImage_AddRef(Result);
        Exit;
      end;
    end;
  end;
  Result := GetItemImageFromParsingPath(AFilePath, AIconCachePathOut, ACachePaths);
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

function ExtractShellIconParts(iconIndexAndOverlay: Integer): TShellIconInfo;
begin
  Result.IconIndex := iconIndexAndOverlay and $00FFFFFF;
  Result.OverlayIndex := (iconIndexAndOverlay shr 24) and $FF;
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
    Result := Result xor Byte(S[I]);
    Result := Result * 16777619;
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
    Result := XImage_LoadMemory(Integer(@buf[0]), size);
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

function ResolveListItemIconFilePath(const AIconCachePath, AFilePath: string;
  const APaths: TShellIconCachePaths): string;
var
  fn, fmt, p: string;
  sysIdx: Integer;
  gotIdx: Boolean;
begin
  Result := Trim(AIconCachePath);
  if (Result <> '') and FileExists(Result) then
    Exit;

  fn := ExtractFileName(Result);
  if (fn <> '') and (AFilePath <> '') and (not IsPerFileShellIconCacheFileName(fn)) then
  begin
    if DirectoryExists(AFilePath) then
      fmt := 'folder'
    else
      fmt := GetFormatNameFromPath(AFilePath);
    gotIdx := GetSysIconIndexForPath(UnicodeString(AFilePath), nil, sysIdx);
    if not gotIdx then
      sysIdx := -1;
    fn := FileTypeIconCacheFileName(fmt, sysIdx);
    if fn = '' then
      fn := ExtractFileName(Trim(AIconCachePath));
  end;
  if fn <> '' then
  begin
    p := IncludeTrailingPathDelimiter(APaths.FileTypeIconDirectory) + fn;
    if FileExists(p) then
    begin
      Result := p;
      Exit;
    end;
    p := IncludeTrailingPathDelimiter(APaths.IconCacheDirectory) + fn;
    if FileExists(p) then
    begin
      Result := p;
      Exit;
    end;
  end;

  if DirectoryExists(AFilePath) then
    fmt := 'folder'
  else
    fmt := GetFormatNameFromPath(AFilePath);
  gotIdx := GetSysIconIndexForPath(UnicodeString(AFilePath), nil, sysIdx);
  if not gotIdx then
    sysIdx := -1;
  Result := ResolveFileTypeIconDiskPath(APaths, fmt, sysIdx);
end;

function GetListItemDisplayImageCacheKey(const AIconCachePath, AFilePath: string): string;
var
  fn, fmt: string;
  sysIdx: Integer;
  gotIdx: Boolean;
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
  if DirectoryExists(AFilePath) then
    Exit('folder');
  fmt := GetFormatNameFromPath(AFilePath);
  if SameText(fmt, 'exe') then
  begin
    gotIdx := GetSysIconIndexForPath(UnicodeString(AFilePath), nil, sysIdx);
    if not gotIdx then
      sysIdx := -1;
    if IsDefaultExeSysIconIndex(sysIdx) then
      Exit(cDefaultExeFileTypeCacheKey);
    if fn <> '' then
      Exit(ChangeFileExt(fn, ''))
    else
      Exit('file:' + IntToHex(Fnv1a32(AnsiString(LowerCase(AFilePath))), 8));
  end;
  if (fmt <> '') and (not SameText(fmt, 'msc')) then
  begin
    gotIdx := GetSysIconIndexForPath(UnicodeString(AFilePath), nil, sysIdx);
    if not gotIdx then
      sysIdx := -1;
    Exit(FileTypeCacheKey(AFilePath, sysIdx));
  end;
  if fn <> '' then
    Result := ChangeFileExt(fn, '')
  else
    Result := 'file:' + IntToHex(Fnv1a32(AnsiString(LowerCase(AFilePath))), 8);
end;

function TryAcquireSharedDisplayImage(const ACacheKey: string; AIconSide: Integer; out AImage: Integer): Boolean;
var
  entryKey: string;
  idx: Integer;
  v: NativeInt;
begin
  Result := False;
  AImage := 0;
  if (ACacheKey = '') or (AIconSide <= 0) or (GListDisplayImageCache = nil) then
    Exit;
  entryKey := LowerCase(ACacheKey) + #9 + IntToStr(AIconSide);
  idx := GListDisplayImageCache.IndexOf(entryKey);
  if idx < 0 then
    Exit;
  v := NativeInt(GListDisplayImageCache.Objects[idx]);
  if v <= 0 then
    Exit;
  AImage := v;
  XImage_AddRef(HIMAGE(AImage));
  Result := True;
end;

procedure PutSharedDisplayImage(const ACacheKey: string; AIconSide: Integer; AImage: Integer);
var
  entryKey: string;
begin
  if (ACacheKey = '') or (AIconSide <= 0) or (AImage = 0) or (GListDisplayImageCache = nil) then
    Exit;
  entryKey := LowerCase(ACacheKey) + #9 + IntToStr(AIconSide);
  if GListDisplayImageCache.IndexOf(entryKey) >= 0 then
    Exit;
  GListDisplayImageCache.AddObject(entryKey, TObject(NativeInt(AImage)));
end;

function ResampleIconFileToHImage(const APngPath: string; AMaxW, AMaxH: Integer): HIMAGE;
var
  SrcBmp, DstBmp: TGPBitmap;
  G: TGPGraphics;
  DstRect: TGPRectF;
  BD: TBitmapData;
  SrcW, SrcH, DstW, DstH: Integer;
begin
  Result := 0;
  if (AMaxW <= 0) or (AMaxH <= 0) or (not FileExists(APngPath)) then
    Exit;

  SrcBmp := TGPBitmap.Create(APngPath);
  try
    if SrcBmp.GetLastStatus <> Ok then
      Exit;
    SrcW := SrcBmp.GetWidth;
    SrcH := SrcBmp.GetHeight;
    CalcImageFitSize(SrcW, SrcH, AMaxW, AMaxH, DstW, DstH);
    if (DstW >= SrcW) and (DstH >= SrcH) then
    begin
      Result := LoadXImageFromFileMemory(APngPath);
      Exit;
    end;

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
        if G.DrawImage(SrcBmp, DstRect, 0, 0, SrcW, SrcH, UnitPixel) <> Ok then
          Exit;
      finally
        G.Free;
      end;

      if DstBmp.LockBits(MakeRect(0, 0, DstW, DstH), ImageLockModeRead, PixelFormat32bppARGB, BD) <> Ok then
        Exit;
      try
        Result := XImage_LoadFromData(Integer(BD.Scan0), DstW, DstH);
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

function SaveBGRAAsPng(const APngPath: string; ABits: Pointer; const AW, AH: Integer): Boolean;
var
  GPBmp: TGPBitmap;
  EncoderClsid: TGUID;
begin
  Result := False;
  if (ABits = nil) or (AW <= 0) or (AH <= 0) then
    Exit;
  EncoderClsid := StringToGUID('{557CF406-1A04-11D3-9A73-0000F81EF32E}');
  GPBmp := TGPBitmap.Create(AW, AH, AW * 4, PixelFormat32bppARGB, ABits);
  try
    if GPBmp.GetLastStatus = Ok then
      Result := GPBmp.Save(PWideChar(APngPath), EncoderClsid, nil) = Ok;
  except
    Result := False;
  end;
  GPBmp.Free;
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

function LoadImageFromIconData(const AIcon: HICON; const ACachePath: string = ''): HIMAGE;
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
begin
  Result := 0;
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
        if ACachePath <> '' then
          SaveBGRAAsPng(ACachePath, Bits, W, H);
        Result := XImage_LoadFromData(Integer(Bits), W, H);

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

function ImageListIconToHIMAGE(const AImageList: IUnknown; iconIndex: Integer; const ACachePngPath: string): HIMAGE;
var
  imgList: IShellImageList;
  hFileIcon: HICON;
begin
  Result := 0;
  if (AImageList = nil) or (iconIndex < 0) then
    Exit;
  if not Supports(AImageList, IShellImageList, imgList) then
    Exit;
  hFileIcon := 0;
  if imgList.GetIcon(iconIndex, ILD_NORMAL, hFileIcon) <> S_OK then
    Exit;
  try
    if hFileIcon <> 0 then
      Result := LoadImageFromIconData(hFileIcon, ACachePngPath);
  finally
    if hFileIcon <> 0 then
      DestroyIcon(hFileIcon);
  end;
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

function ShellIconCacheFullPath(const APaths: TShellIconCachePaths; const AFileName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(APaths.IconCacheDirectory) + AFileName;
end;

function ShellFileTypeIconFullPath(const APaths: TShellIconCachePaths; const AFileName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(APaths.FileTypeIconDirectory) + AFileName;
end;

function GetItemImageFromParsingPath(const APath: string; out AIconCachePath: string;
  const ACachePaths: TShellIconCachePaths): HIMAGE;
var
  cached: HIMAGE;
  fmt: string;
  cacheFullPath: string;
  pathForIcon: string;
  SysIdx: Integer;
  typeCacheKey: string;
  ImageList: IShellImageList;
  hFileIcon: HICON;
  FileInfo: SHFILEINFOW;
  I: Integer;
  itemPidl: PItemIDList;
  hr: HRESULT;
  gotIndex: Boolean;
  canCacheByType: Boolean;
  sharedExeIcon: Boolean;
begin
  Result := 0;
  pathForIcon := NormalizeSystem32PathForIcon(APath);
  if DirectoryExists(pathForIcon) then
    fmt := 'folder'
  else
    fmt := GetFormatNameFromPath(APath);

  itemPidl := nil;
  hr := ParseDisplayNameForNavigation(pathForIcon, itemPidl);
  gotIndex := False;
  SysIdx := -1;
  if Succeeded(hr) and (itemPidl <> nil) then
    gotIndex := GetSysIconIndexForPath('', itemPidl, SysIdx);
  if not gotIndex then
    gotIndex := GetSysIconIndexForPath(pathForIcon, nil, SysIdx);
  if itemPidl <> nil then
    ILFree(itemPidl);

  sharedExeIcon := SameText(fmt, 'exe') and gotIndex and IsDefaultExeSysIconIndex(SysIdx);
  canCacheByType := sharedExeIcon or ((fmt <> '') and (not SameText(fmt, 'exe')) and
    (not SameText(fmt, 'msc')));
  if canCacheByType then
  begin
    if sharedExeIcon then
      typeCacheKey := cDefaultExeFileTypeCacheKey
    else
      typeCacheKey := FileTypeCacheKey(APath, SysIdx);
  end
  else
    typeCacheKey := '';
  if TryGetCachedFileTypeImage(typeCacheKey, cached) then
  begin
    Result := cached;
    Exit;
  end;

  if canCacheByType then
  begin
    if sharedExeIcon then
    begin
      AIconCachePath := cDefaultExeIconFileName;
      cacheFullPath := ShellFileTypeIconFullPath(ACachePaths, cDefaultExeIconFileName);
    end
    else
    begin
      AIconCachePath := FileTypeIconCacheFileName(fmt, SysIdx);
      cacheFullPath := ResolveFileTypeIconDiskPath(ACachePaths, fmt, SysIdx);
    end;
  end
  else
  begin
    AIconCachePath := BuildIconCacheFileName(APath);
    cacheFullPath := ShellIconCacheFullPath(ACachePaths, AIconCachePath);
  end;

  if (cacheFullPath <> '') and FileExists(cacheFullPath) then
  begin
    Result := LoadXImageFromFileMemory(cacheFullPath);
    if Result <> 0 then
    begin
      if canCacheByType then
      begin
        XImage_EnableAutoDestroy(Result, False);
        PutCachedFileTypeImage(typeCacheKey, Result, False);
      end;
      Exit;
    end;
  end;

  if gotIndex and EnsureShellImageListsLoaded then
  begin
    for I := Low(cShellImageListLevels) to High(cShellImageListLevels) do
    begin
      ImageList := GShellImageLists[I];
      if ImageList = nil then
        Continue;
      hFileIcon := 0;
      if ImageList.GetIcon(SysIdx, ILD_NORMAL, hFileIcon) = S_OK then
      begin
        try
          if hFileIcon <> 0 then
          begin
            if (cShellImageListLevels[I] = SHIL_JUMBO) and IsLikelyTopLeftSmallInJumbo(hFileIcon) then
              Continue;
            Result := LoadImageFromIconData(hFileIcon, cacheFullPath);
          end;
        finally
          if hFileIcon <> 0 then
            DestroyIcon(hFileIcon);
        end;
      end;
      if Result <> 0 then
        Break;
    end;
  end;

  if Result <> 0 then
  begin
    if canCacheByType then
    begin
      XImage_EnableAutoDestroy(Result, False);
      PutCachedFileTypeImage(typeCacheKey, Result, False);
    end;
    Exit;
  end;

  ZeroMemory(@FileInfo, SizeOf(FileInfo));
  if SHGetFileInfoW(PWideChar(pathForIcon), FILE_ATTRIBUTE_NORMAL, FileInfo, SizeOf(FileInfo),
    SHGFI_ICON or SHGFI_LARGEICON) <> 0 then
  begin
    try
      if FileInfo.hIcon <> 0 then
        Result := XImage_LoadFromHICON(FileInfo.hIcon);
    finally
      if FileInfo.hIcon <> 0 then
        DestroyIcon(FileInfo.hIcon);
    end;
  end;

  // 兜底分支（SHGetFileInfoW）：同样缓存一次（或记失败哨兵）。
  if canCacheByType then
  begin
    if Result <> 0 then
    begin
      XImage_EnableAutoDestroy(Result, False);
      PutCachedFileTypeImage(typeCacheKey, Result, False);
    end
    else
      PutCachedFileTypeImage(typeCacheKey, 0, True);
  end;
end;

function GetListViewFileItemFromParsingPath(const AFullPath: string;
  const ACachePaths: TShellIconCachePaths): TListViewFileItem;
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
  Result.FileImage := GetItemImageFromParsingPath(targetPath, Result.IconCachePath, ACachePaths);
  if not SameText(ExtractFileExt(targetPath), '.exe') then
    Result.IconCachePath := '';
  Result.InsertOrder := -1;
  Result.ItemGroupIndex := -1;
end;

initialization
  GFileTypeImageCache := TStringList.Create;
  GFileTypeImageCache.CaseSensitive := False;
  GFileTypeImageCache.Sorted := True;
  GFileTypeImageCache.Duplicates := dupIgnore;
  GIconCachePathImageCache := TStringList.Create;
  GIconCachePathImageCache.CaseSensitive := False;
  GIconCachePathImageCache.Sorted := True;
  GIconCachePathImageCache.Duplicates := dupIgnore;
  GListDisplayImageCache := TStringList.Create;
  GListDisplayImageCache.CaseSensitive := False;
  GListDisplayImageCache.Sorted := True;
  GListDisplayImageCache.Duplicates := dupIgnore;
  EnsureShellImageListsLoaded;

finalization
  ReleaseFileTypeImageCache;

end.
