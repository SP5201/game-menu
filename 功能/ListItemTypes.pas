unit ListItemTypes;

interface

uses
  SysUtils,
  Windows,
  XCGUI;

type
  /// <summary>列表/库条目绑定的文件元数据（路径、图标、显示名、启动参数等）。</summary>
  TListViewFileItem = record
    FilePath: string;
    /// <summary>已加载的真实图标；0 表示未加载，绘制时按路径显示文件/文件夹/应用程序占位图。</summary>
    FileImage: HIMAGE;
    /// <summary>预缓存的显示标题（避免绘制时反复调用 ListViewItemDisplayTitle）。</summary>
    DisplayTitle: string;
    IconCachePath: string;
    FileName: string;
    FileParams: string;
    WorkingDir: string;
    /// <summary>Shell 启动窗口方式（SW_SHOWNORMAL / SW_SHOWMINIMIZED / SW_SHOWMAXIMIZED）。</summary>
    ShowCmd: Integer;
    /// <summary>与数据库 id 顺序一致的插入序号；负数表示由列表在添加时自动分配。</summary>
    InsertOrder: Integer;
    /// <summary>数据库 group_index；全局搜索时每项独立；-1 表示使用列表当前活动分组。</summary>
    ItemGroupIndex: Integer;
  end;

  PListViewFileItem = ^TListViewFileItem;
  TListViewFileItemArray = array of TListViewFileItem;

/// <summary>从完整路径取最后一段名称（兼容末尾带 \ 的目录路径）。</summary>
function ListPathLeafName(const APath: string): string;

/// <summary>列表项显示标题：FileName → 路径末段 → 完整路径。</summary>
function ListViewItemDisplayTitle(const R: TListViewFileItem): string;
function ShowCmdFromComboIndex(const AIndex: Integer): Integer;
function ComboIndexFromShowCmd(const AShowCmd: Integer): Integer;
function NormalizeItemShowCmd(const AShowCmd: Integer): Integer;

implementation

function ListPathLeafName(const APath: string): string;
begin
  Result := ExtractFileName(ExcludeTrailingPathDelimiter(Trim(APath)));
end;

function ListViewItemDisplayTitle(const R: TListViewFileItem): string;
begin
  Result := Trim(R.FileName);
  if Result = '' then
    Result := ListPathLeafName(R.FilePath);
  if Result = '' then
    Result := Trim(R.FilePath);
end;

function ShowCmdFromComboIndex(const AIndex: Integer): Integer;
begin
  case AIndex of
    1:
      Result := SW_SHOWMAXIMIZED;
    2:
      Result := SW_SHOWMINIMIZED;
  else
    Result := SW_SHOWNORMAL;
  end;
end;

function ComboIndexFromShowCmd(const AShowCmd: Integer): Integer;
begin
  case NormalizeItemShowCmd(AShowCmd) of
    SW_SHOWMAXIMIZED:
      Result := 1;
    SW_SHOWMINIMIZED:
      Result := 2;
  else
    Result := 0;
  end;
end;

function NormalizeItemShowCmd(const AShowCmd: Integer): Integer;
begin
  case AShowCmd of
    SW_SHOWNORMAL, SW_SHOWMINIMIZED, SW_SHOWMAXIMIZED:
      Result := AShowCmd;
  else
    Result := SW_SHOWNORMAL;
  end;
end;

end.
