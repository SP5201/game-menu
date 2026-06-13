// Test.cpp : 定义应用程序的入口点。
//

#include "stdafx.h"
#include "Test.h"

//包含炫彩界面库文件
#include "../../../DLL/xcgui.h"
#pragma comment(lib,"../../../DLL/XCGUI.lib")

class CMyWindowDemo
{
public:
	HWINDOW m_hWindow;
	CMyWindowDemo()
	{
		Init();
	}
	void Init()
	{
		XC_LoadResource(L"layout\\resource.res");  //加载资源文件
		HXCGUI hXCGUI = XC_LoadLayout(L"layout\\layout.xml"); //加载布局文件
		if (XC_IsHWINDOW(hXCGUI))
		{
			m_hWindow = (HWINDOW)hXCGUI;
			//XC_GetObjectByID(); //获取指定ID对象
			//XC_ShowLayoutFrame(TRUE); //显示布局边界
			XWnd_AdjustLayout(m_hWindow);
			XWnd_ShowWindow(m_hWindow, SW_SHOW);
		} else
		{
			//错误
		}
	}
};

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPTSTR lpCmdLine, int nCmdShow)
{
	XInitXCGUI(TRUE);
	//XC_AddFileSearchPath(L"E:\\MyUI\\XCGUI-test");  //添加文件搜索路径
	CMyWindowDemo  MyWindow;
	XRunXCGUI();
	XExitXCGUI();
	return 0;
}

