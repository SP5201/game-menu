// Test.cpp : 定义应用程序的入口点。
//

#include "stdafx.h"
#include "Test.h"

//包含炫彩界面库文件
#include "../../../DLL/xcgui.h"
#pragma comment(lib,"../../../DLL/XCGUI.lib")

class CMyEditor
{
public:
	HWINDOW m_hWindow;
	HELE m_hEdit;
	HFONTX m_hFont;
	CMyEditor() {
		Init();
	}
	void Init()
	{
		m_hWindow = XWnd_Create(0, 0, 550, 500, L"炫彩界面库窗口", NULL, window_style_default);
		HELE m_hButton_close = XBtn_Create(400, 5, 60, 20, L"", m_hWindow);
		XBtn_SetTypeEx(m_hButton_close, button_type_close);

		m_hEdit = XEditor_Create(20, 40, 500, 450, m_hWindow);
		XEle_EnableKeyTab(m_hEdit, TRUE);
		XEdit_EnableAutoWrap(m_hEdit, TRUE);

		m_hFont = XFont_CreateEx(L"微软雅黑", 12);
		XEle_SetFont(m_hEdit, m_hFont);
		XEle_SetTextColor(m_hEdit, RGBA(100, 100, 100,255));  //默认颜色

		int iStyle_const = XEdit_AddStyle(m_hEdit, NULL, RGBA(189, 99, 179,255), TRUE);  //常量
		int iStyle_fun = XEdit_AddStyle(m_hEdit, NULL, RGBA(255, 128, 0,255), TRUE);     //函数
		int iStyle_str = XEdit_AddStyle(m_hEdit, NULL, RGBA(206, 145, 120,255), TRUE);   //字符串
		int iStyle_comment = XEdit_AddStyle(m_hEdit, NULL, RGBA(67, 166, 74,255), TRUE); //注释
		int iStyle_key1 = XEdit_AddStyle(m_hEdit, NULL, RGBA(86, 156, 214,255), TRUE);   //key1
		int iStyle_key2 = XEdit_AddStyle(m_hEdit, NULL, RGBA(200, 0, 0,255), TRUE);      //key2

// 		XEditor_SetStyleMacro(m_hEdit, iStyle_const);
// 		XEditor_SetStyleFunction(m_hEdit, iStyle_fun);
// 		XEditor_SetStyleString(m_hEdit, iStyle_str);
// 		XEditor_SetStyleComment(m_hEdit, iStyle_comment);

		XEditor_AddKeyword(m_hEdit, L"if", iStyle_key1);
		XEditor_AddKeyword(m_hEdit, L"int", iStyle_key1);
		XEditor_AddKeyword(m_hEdit, L"function", iStyle_key2);
		XEditor_AddKeyword(m_hEdit, L"return", iStyle_key2);

		XEditor_AddConst(m_hEdit, LR"(XE_BNCLICK //按钮点击事件)");

		XEditor_AddFunction(m_hEdit, LR"(HXCGUI XC_LoadLayout(const wchar_t *pFileName, HXCGUI hParent=NULL); //我是描述)");
		XEditor_AddFunction(m_hEdit, LR"(HXCGUI XEle_RegEvent(const wchar_t *pFileName, HXCGUI hParent=NULL); //我是描述)");
		XEditor_AddFunction(m_hEdit, LR"(HXCGUI XWnd_AdjustLayout(const wchar_t *pFileName, HXCGUI hParent=NULL); //我是描述)");
		XEditor_AddFunction(m_hEdit, LR"(HXCGUI XWnd_ShowWindow(const wchar_t *pFileName, HXCGUI hParent=NULL); //我是描述)");

		XEditor_SetBreakpoint(m_hEdit, 0, TRUE);
		XEditor_SetBreakpoint(m_hEdit, 2, TRUE);
		XEditor_SetBreakpoint(m_hEdit, 3, FALSE);
		XEditor_SetRunRow(m_hEdit, 0);

		XEdit_SetText(m_hEdit, L"int main(int a, int b) //123456\n\
{\n\
	XC_LoadLayout(\"layout.xml\",0);\n\
	XE_BNCLICK;\n\
	return 0;\n\
}\n");

		XWnd_ShowWindow(m_hWindow, SW_SHOW);
	}
};

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPTSTR lpCmdLine, int nCmdShow)
{
	XInitXCGUI(TRUE);
	CMyEditor  MyWindow;
	XRunXCGUI();
	XExitXCGUI();
	return 0;
}
