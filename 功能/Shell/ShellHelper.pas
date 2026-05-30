unit ShellHelper;

interface

uses
  Classes,
  SysUtils,
  Windows,
  ShlObj,
  ListItemTypes,
  ShellIconHelper,
  ShellDialogs,
  ShellExecuteHelper,
  ShellPathHelper,
  XCGUI;

type
  TShellIconCachePaths = ShellIconHelper.TShellIconCachePaths;
  TShellIconInfo = ShellIconHelper.TShellIconInfo;

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
function IsRunningUnderWow64: Boolean;
function ResolveSystem32ExePath(const AExeName: string): string;
function ResolveSystemBinaryPathForOsArchitecture(const AExeName: string): string;
function ResolveSystem32MscDocumentPath(const AMscFileName: string): string;
function OpenFileDialogSingle(const AOwnerWnd: Windows.HWND; const ATitle, AFilter: string; out AFilePath: string): Boolean;
function OpenFileDialogMulti(const AOwnerWnd: Windows.HWND; const ATitle, AFilter: string; AFiles: TStrings): Boolean;
function SaveFileDialog(const AOwnerWnd: Windows.HWND; const ATitle, AFilter, ADefaultFileName,
  AInitialDir, ADefaultExt: string; out AFilePath: string): Boolean;
function ShellExecuteDefaultVerb(hwnd: Windows.HWND; const FilePath, Parameters, WorkingDir: UnicodeString): Boolean;
function ShellExecuteRunAs(hwnd: Windows.HWND; const FilePath, Parameters, WorkingDir: UnicodeString): Boolean;
function ShellOpenFolderAndSelectPath(hwnd: Windows.HWND; const FilePath: UnicodeString): Boolean;

implementation

function ExtractShellIconParts(iconIndexAndOverlay: Integer): TShellIconInfo;
begin
  Result := ShellIconHelper.ExtractShellIconParts(iconIndexAndOverlay);
end;

function ParseDisplayNameForNavigation(const ItemPath: UnicodeString; out APidl: PItemIDList): HRESULT;
begin
  Result := ShellIconHelper.ParseDisplayNameForNavigation(ItemPath, APidl);
end;

function GetListViewFileItemFromParsingPath(const AFullPath: string;
  const ACachePaths: TShellIconCachePaths): TListViewFileItem;
begin
  Result := ShellIconHelper.GetListViewFileItemFromParsingPath(AFullPath, ACachePaths);
end;

function LoadXImageFromFileMemory(const AFilePath: string): Integer;
begin
  Result := ShellIconHelper.LoadXImageFromFileMemory(AFilePath);
end;

function ResolveListItemIconFilePath(const AIconCachePath, AFilePath: string;
  const APaths: TShellIconCachePaths): string;
begin
  Result := ShellIconHelper.ResolveListItemIconFilePath(AIconCachePath, AFilePath, APaths);
end;

function ResampleIconFileToHImage(const APngPath: string; AMaxW, AMaxH: Integer): HIMAGE;
begin
  Result := ShellIconHelper.ResampleIconFileToHImage(APngPath, AMaxW, AMaxH);
end;

function GetListItemDisplayImageCacheKey(const AIconCachePath, AFilePath: string): string;
begin
  Result := ShellIconHelper.GetListItemDisplayImageCacheKey(AIconCachePath, AFilePath);
end;

function TryAcquireSharedDisplayImage(const ACacheKey: string; AIconSide: Integer; out AImage: Integer): Boolean;
begin
  Result := ShellIconHelper.TryAcquireSharedDisplayImage(ACacheKey, AIconSide, AImage);
end;

procedure PutSharedDisplayImage(const ACacheKey: string; AIconSide: Integer; AImage: Integer);
begin
  ShellIconHelper.PutSharedDisplayImage(ACacheKey, AIconSide, AImage);
end;

procedure ClearListDisplayImageCache;
begin
  ShellIconHelper.ClearListDisplayImageCache;
end;

function ImageListIconToHIMAGE(const AImageList: IUnknown; iconIndex: Integer; const ACachePngPath: string): HIMAGE;
begin
  Result := ShellIconHelper.ImageListIconToHIMAGE(AImageList, iconIndex, ACachePngPath);
end;

function GetItemImageFromParsingPath(const APath: string; out AIconCachePath: string;
  const ACachePaths: TShellIconCachePaths): HIMAGE;
begin
  Result := ShellIconHelper.GetItemImageFromParsingPath(APath, AIconCachePath, ACachePaths);
end;

function AcquireListItemFileImage(const AIconCachePath, AFilePath: string;
  const ACachePaths: TShellIconCachePaths; out AIconCachePathOut: string): HIMAGE;
begin
  Result := ShellIconHelper.AcquireListItemFileImage(AIconCachePath, AFilePath, ACachePaths, AIconCachePathOut);
end;

function LoadImageFromIconData(const AIcon: HICON; const ACachePath: string): HIMAGE;
begin
  Result := ShellIconHelper.LoadImageFromIconData(AIcon, ACachePath);
end;

function GetShieldIconSmall: HICON;
begin
  Result := ShellIconHelper.GetShieldIconSmall;
end;

procedure ReleaseFileTypeImageCache;
begin
  ShellIconHelper.ReleaseFileTypeImageCache;
end;

function IsRunningUnderWow64: Boolean;
begin
  Result := ShellPathHelper.IsRunningUnderWow64;
end;

function ResolveSystem32ExePath(const AExeName: string): string;
begin
  Result := ShellPathHelper.ResolveSystem32ExePath(AExeName);
end;

function ResolveSystemBinaryPathForOsArchitecture(const AExeName: string): string;
begin
  Result := ShellPathHelper.ResolveSystemBinaryPathForOsArchitecture(AExeName);
end;

function ResolveSystem32MscDocumentPath(const AMscFileName: string): string;
begin
  Result := ShellPathHelper.ResolveSystem32MscDocumentPath(AMscFileName);
end;

function OpenFileDialogSingle(const AOwnerWnd: Windows.HWND; const ATitle, AFilter: string; out AFilePath: string): Boolean;
begin
  Result := ShellDialogs.OpenFileDialogSingle(AOwnerWnd, ATitle, AFilter, AFilePath);
end;

function OpenFileDialogMulti(const AOwnerWnd: Windows.HWND; const ATitle, AFilter: string; AFiles: TStrings): Boolean;
begin
  Result := ShellDialogs.OpenFileDialogMulti(AOwnerWnd, ATitle, AFilter, AFiles);
end;

function SaveFileDialog(const AOwnerWnd: Windows.HWND; const ATitle, AFilter, ADefaultFileName,
  AInitialDir, ADefaultExt: string; out AFilePath: string): Boolean;
begin
  Result := ShellDialogs.SaveFileDialog(AOwnerWnd, ATitle, AFilter, ADefaultFileName, AInitialDir, ADefaultExt, AFilePath);
end;

function ShellExecuteDefaultVerb(hwnd: Windows.HWND; const FilePath, Parameters, WorkingDir: UnicodeString): Boolean;
begin
  Result := ShellExecuteHelper.ShellExecuteDefaultVerb(hwnd, FilePath, Parameters, WorkingDir);
end;

function ShellExecuteRunAs(hwnd: Windows.HWND; const FilePath, Parameters, WorkingDir: UnicodeString): Boolean;
begin
  Result := ShellExecuteHelper.ShellExecuteRunAs(hwnd, FilePath, Parameters, WorkingDir);
end;

function ShellOpenFolderAndSelectPath(hwnd: Windows.HWND; const FilePath: UnicodeString): Boolean;
begin
  Result := ShellExecuteHelper.ShellOpenFolderAndSelectPath(hwnd, FilePath);
end;

end.
