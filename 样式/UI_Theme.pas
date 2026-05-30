unit UI_Theme;

interface

uses
  Windows, XCGUI;

var
  UITheme_WindowCornerRadius: Integer;   // 窗口默认圆角
  UITheme_WindowAlpha: Byte;             // 窗口默认透明度

  // ==== 语义色（推荐优先使用） ====
  UITheme_SurfaceBase: Integer;         // 基础表面色（窗口/菜单背景）
  UITheme_SurfaceOutline: Integer;      // 表面描边色
  UITheme_SurfaceHover: Integer;        // 悬停态表面色
  UITheme_SurfaceSelected: Integer;     // 选中态表面色
  UITheme_ShadowDefault: Integer;       // 默认阴影色
  UITheme_TextPrimary: Integer;         // 主文本色
  UITheme_TextPlaceholder: Integer;     // 占位文本色
  UITheme_ListHeaderSurface: Integer;   // 报表列表表头背景
  UITheme_ListHeaderText: Integer;       // 报表列表表头文字
  UITheme_ListHeaderSplitLine: Integer; // 报表列表表头列分隔线
  UITheme_BorderDefault: Integer;       // 默认边框色
  UITheme_InputSurface: Integer;        // 输入框背景色
  UITheme_InputSurfaceFocus: Integer;   // 输入框聚焦背景色
  UITheme_InputBorder: Integer;         // 输入框边框色
  UITheme_InputText: Integer;           // 输入框文本色
  UITheme_InputCaret: Integer;          // 输入框光标色
  UITheme_InputSelection: Integer;      // 输入框选区背景色
  UITheme_ScrollThumbIdle: Integer;     // 滚动条滑块常态色
  UITheme_ScrollThumbActive: Integer;   // 滚动条滑块激活态色
  UITheme_SvgColor: Integer;            //SVG颜色

  UITheme_ButtonHighlightBk: Integer;        // 按钮高亮背景
  UITheme_ButtonHighlightBkHover: Integer;   // 按钮高亮背景（悬停）
  UITheme_ButtonNormalBk: Integer;           // 按钮普通背景
  UITheme_ButtonNormalBkHover: Integer;      // 按钮普通背景（悬停）
  UITheme_IconFill: Integer;                 // 图标填充色
  UITheme_CheckMark: Integer;                // 勾选标记色

  UITheme_PrimaryColor: Integer;

  { 状态栏圆角进度条（默认 64×9） }
  UITheme_ProgressBarWidth: Integer;
  UITheme_ProgressBarHeight: Integer;
  UITheme_ProgressBarCornerRadius: Integer;
  UITheme_ProgressBarFill: Integer;   // CPU 进度色
  UITheme_ProgressBarTrack: Integer; // 轨道色
  UITheme_StatRamFill: Integer;       // RAM 进度/文字色
  UITheme_StatGpuFill: Integer;       // GPU 进度/文字色
  UITheme_StatNetDownFill: Integer;   // 状态栏下载 SVG 着色
  UITheme_StatNetUpFill: Integer;     // 状态栏上传 SVG 着色
  UITheme_StatLabel: Integer;         // CPU/RAM/GPU 标签文字色
  UITheme_StatBarTopLine: Integer;     // 底部状态栏顶部分隔线

  // PopupMenu 颜色
  UITheme_PopupMenu_AccentWhiteAlpha30: Integer; // 分隔线 & 选中底色

/// <summary>UTF-8 源文件（无 BOM）中的字面量按 UTF-8 字节解释，显式转为 Unicode string（避免 W1057）。</summary>
function UI_Utf8Src(const AUtf8: UTF8String): UnicodeString; overload;
function UI_Utf8Src(const ABytes: AnsiString): string; overload;

implementation

function UI_Utf8Src(const AUtf8: UTF8String): UnicodeString;
begin
  Result := string(AUtf8);
end;

function UI_Utf8Src(const ABytes: AnsiString): string;
begin
  Result := string(UTF8String(ABytes));
end;

initialization
  UITheme_WindowCornerRadius := 8;
  UITheme_WindowAlpha := 255;
  UITheme_SurfaceBase := RGBA(30, 30, 30, UITheme_WindowAlpha);
  UITheme_SurfaceOutline := RGBA(255, 255, 255, 10);
  UITheme_SurfaceSelected := RGBA(255, 255, 255, 20);
  UITheme_SurfaceHover := RGBA(255, 255, 255, 10);
  UITheme_ShadowDefault := RGBA(0, 0, 0, 225);
  UITheme_TextPrimary := RGBA(207, 207, 207, 255);
  UITheme_TextPlaceholder := RGBA(255, 255, 255, 36);
  UITheme_ListHeaderSurface := RGBA(42, 42, 42, 255);
  UITheme_ListHeaderText := RGBA(207, 207, 207, 255);
  UITheme_ListHeaderSplitLine := RGBA(255, 255, 255, 36);
  UITheme_BorderDefault := RGBA(255, 255, 255, 30);
  UITheme_InputSurface := RGBA(255, 255, 255, 4);
  UITheme_InputSurfaceFocus := RGBA(0, 0, 0, 60);
  UITheme_InputBorder := RGBA(255, 255, 255, 30);
  UITheme_InputText := RGBA(255, 255, 255, 150);
  UITheme_InputCaret := RGBA(255, 255, 255, 190);
  UITheme_InputSelection := RGBA(255, 255, 255, 80);
  UITheme_ScrollThumbIdle := RGBA(255, 255, 255, 40);
  UITheme_ScrollThumbActive := RGBA(255, 255, 255, 80);
  UITheme_ButtonHighlightBk := RGBA(210, 27, 70, 255);
  UITheme_ButtonHighlightBkHover := RGBA(210, 27, 70, 245);
  UITheme_ButtonNormalBk := RGBA(255, 255, 255, 32);
  UITheme_ButtonNormalBkHover := RGBA(255, 255, 255, 42);
  UITheme_IconFill := RGBA(255, 255, 255, 160);
  UITheme_CheckMark := RGBA(255, 255, 255, 255);
  UITheme_SvgColor := RGBA(255, 255, 255, 230);

  UITheme_PrimaryColor := RGBA(210, 27, 70, 255);

  UITheme_ProgressBarWidth := 50;
  UITheme_ProgressBarHeight := 7;
  UITheme_ProgressBarCornerRadius := 3;
  UITheme_ProgressBarFill := RGBA(239, 68, 68, 255);
  UITheme_ProgressBarTrack := RGBA(64, 64, 64, 255);
  UITheme_StatRamFill := RGBA(16, 185, 129, 255);
  UITheme_StatGpuFill := RGBA(59, 130, 246, 255);
  UITheme_StatNetDownFill := RGBA(125, 212, 232, 255);
  UITheme_StatNetUpFill := RGBA(52, 211, 153, 255);
  UITheme_StatLabel := RGBA(156, 163, 175, 200);
  UITheme_StatBarTopLine := RGBA(255, 255, 255, 28);

  UITheme_PopupMenu_AccentWhiteAlpha30 := RGBA(255, 255, 255, 18);

end.

