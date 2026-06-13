// Test.cpp : 定义应用程序的入口点。
//

#include "stdafx.h"
#include "Test.h"

//包含炫彩界面库文件
#include "../../../DLL/xcgui.h"
#pragma comment(lib,"../../../DLL/XCGUI.lib")

#include <vector>
using namespace std;

class CEditRecv
{
public:
	HELE    m_hEdit;
	USHORT  m_style1;
	HIMAGE  m_hImageAvatar;
	HIMAGE  m_hImageAvatar2;
	HIMAGE  m_hImageBubble;
	HIMAGE  m_hImageBubble2;
	void OnExit()
	{
		if (XC_IsHXCGUI(m_hImageAvatar, XC_IMAGE_FRAME)) XImage_Release(m_hImageAvatar);
		if (XC_IsHXCGUI(m_hImageAvatar2, XC_IMAGE_FRAME)) XImage_Release(m_hImageAvatar2);
		if (XC_IsHXCGUI(m_hImageBubble, XC_IMAGE_FRAME)) XImage_Release(m_hImageBubble);
		if (XC_IsHXCGUI(m_hImageBubble2, XC_IMAGE_FRAME)) XImage_Release(m_hImageBubble2);
	}
	void Init(HWINDOW hWindow, int left, int top, int width, int height)
	{
		m_hEdit = XEdit_CreateEx(left, top, width, height, edit_type_chat, hWindow);
		XEle_EnableKeyTab(m_hEdit, TRUE);
		XEdit_SetRowHeight(m_hEdit, 20);
		//XEle_SetPadding(m_hEdit,50, 0, 60, 0);

		HFONTX  hFont1 = XFont_CreateEx(L"微软雅黑", 9);
		m_style1 = XEdit_AddStyle(m_hEdit, hFont1, RGBA(0, 0, 255, 255), TRUE);
		m_hImageAvatar = XImage_LoadFile(L"image\\avatar.png"); //头像
		m_hImageAvatar2 = XImage_LoadFile(L"image\\logo.png"); //头像
		m_hImageBubble = XImage_LoadFileAdaptive(L"image\\bubble.png", 20, 15, 20, 15); //气泡
		m_hImageBubble2 = XImage_LoadFileAdaptive(L"image\\bubble2.png", 20, 16, 20, 10); //气泡2

		//m_hImageAvatar =XImage_LoadFile(LR"(C:\Users\MF\Desktop\\QQ.png)");
		//XImage_SetDrawType(m_hImageAvatar, image_draw_type_stretch);
		//XImage_SetScaleSize(m_hImageAvatar, 50,50);

		//XEle_SetPadding(m_hEdit, 100, 0, 100, 0);
		{
			// 			XEdit_AddText(m_hEdit, L"\n");
			// 			XEdit_AddChatBegin(m_hEdit, 0, 0, chat_flag_center);
			// 			XEdit_AddText(m_hEdit, L"系统消息:123456\n");
			// 			XEdit_AddChatEnd(m_hEdit);
		}

		// 		static int send_left = 1;
		// 		if (send_left % 2)
		// 			XEdit_AddChatBegin(m_hEdit, m_hImageAvatar, m_hImageBubble, chat_flag_left | chat_flag_next_row_bubble);
		// 		else
		// 			XEdit_AddChatBegin(m_hEdit, m_hImageAvatar2, m_hImageBubble2, chat_flag_right | chat_flag_next_row_bubble);
		// 		send_left++;
		// 		XEdit_AddTextEx(m_hEdit, L"【实习】梦飞(154460336) 2019/1/23 20:30:12\n", m_style1);
		// 		int iCurRow = XEdit_GetCurRow(m_hEdit);
		// 		XEdit_SetRowHeightEx(m_hEdit, iCurRow - 1, 40);
		// 
		// 		XEdit_AddTextEx(m_hEdit, L"炫彩界面库\n", 2);
		// 		XEdit_AddText(m_hEdit, L"123");
		// 
		// 		XEdit_AddChatEnd(m_hEdit);
	}
	void Recv(edit_data_copy_* data, BOOL bInsert)
	{
		if (bInsert) //插入
		{
			XEdit_SetCurPos(m_hEdit, 0);
			XEdit_InsertText(m_hEdit, 0, 0, L"\n");
			XEdit_InsertChatBegin(m_hEdit, 0, 0, chat_flag_center);
			XEdit_InsertText(m_hEdit, 1, 0, L"系统消息:123456 - 插入");
			XEdit_AddChatEnd(m_hEdit);
			int iRow, iCol;
			XEdit_GetCurPosEx(m_hEdit, &iRow, &iCol);
			XEdit_InsertText(m_hEdit, iRow, iCol, L"\n");

			XEle_Redraw(m_hEdit);
			return;
		}
		{
			XEdit_AddText(m_hEdit, L"\n");
			XEdit_AddChatBegin(m_hEdit, 0, 0, chat_flag_center);
			XEdit_AddText(m_hEdit, L"系统消息:123456");
			XEdit_AddChatEnd(m_hEdit);
			XEdit_AddText(m_hEdit, L"\n");
		}

		static int send_left = 1;
		if (send_left % 2)
			XEdit_AddChatBegin(m_hEdit, m_hImageAvatar, m_hImageBubble, chat_flag_left | chat_flag_next_row_bubble);
		else
			XEdit_AddChatBegin(m_hEdit, m_hImageAvatar2, m_hImageBubble2, chat_flag_right | chat_flag_next_row_bubble);
		send_left++;
		XEdit_AddTextEx(m_hEdit, L"【实习】梦飞(154460336) 2019/1/23 20:30:12\n", m_style1);
		int iCurRow = XEdit_GetCurRow(m_hEdit);
		XEdit_SetRowHeightEx(m_hEdit, iCurRow - 1, 40);
		AddData(data);

		//XEdit_AddTextEx(m_hEdit, L"炫彩界面库\n", 2);
		//XEdit_AddText(m_hEdit, L"123");

		XEdit_AddChatEnd(m_hEdit);

		XEdit_AddText(m_hEdit, L"\n");
		XEdit_AutoScroll(m_hEdit);
		XEle_Redraw(m_hEdit);
	}
	void AddData(edit_data_copy_* data)
	{
		//读取样式表
		vector<USHORT>  styleTable(data->nStyleCount, edit_style_default);
		for (int i = 0; i < data->nStyleCount; i++)
		{
			HXCGUI hObj = (HXCGUI)data->pStyle[i].hFont_image_obj;
			XC_OBJECT_TYPE ty = XObj_GetTypeBase(hObj);
			if (XC_IMAGE_FRAME == ty)
			{
				//HIMAGE hSrc=XImage_GetImageSrc(hObj);
				//const wchar_t* pFile = XImgSrc_GetFile(hSrc);
				int iStyle = XEdit_AddStyle(m_hEdit, hObj, 0, FALSE);
				styleTable[i] = iStyle;
			} else 	if (XC_FONT == ty)
			{
				COLORREF color = data->pStyle[i].color;
				int iStyle = XEdit_AddStyle(m_hEdit, (HFONTX)hObj, color, data->pStyle[i].bColor);
				styleTable[i] = iStyle;
			} else 	if (XC_ELE == ty)
			{
				if (XC_BUTTON == XC_GetObjectType(hObj))
				{
					HELE  hBtn = XBtn_Create(0, 0, XEle_GetWidth((HELE)hObj), XEle_GetHeight((HELE)hObj), XBtn_GetText((HELE)hObj), m_hEdit);
					USHORT iStyle = XEdit_AddStyle(m_hEdit, hBtn, 0, FALSE);
					styleTable[i] = iStyle;
				}
			} else if (XC_SHAPE == ty)
			{
				if (XC_IsHXCGUI(hObj, XC_SHAPE_GIF))
				{
					HIMAGE hImageGif = XShapeGif_GetImage(hObj);
					//HIMAGE hSrc=XImage_GetImageSrc(hImageGif);
					//const wchar_t* pFile = XImgSrc_GetFile(hSrc);
					{
						HXCGUI hGif = XShapeGif_Create(0, 0, XImage_GetWidth(hImageGif), XImage_GetHeight(hImageGif), m_hEdit);
						XShapeGif_SetImage(hGif, hImageGif);
						int iStyle = XEdit_AddStyle(m_hEdit, hGif, 0, FALSE);
						styleTable[i] = iStyle;
					}
				}
			}
		}
		XEdit_AddData(m_hEdit, data, styleTable.data(), data->nStyleCount);
	}
};

class CEditSend
{
public:
	HWINDOW m_hWindow;
	HELE m_hEdit;
	HELE m_hBtnSend;
	HELE m_hBtnSend_Insert;
	HELE m_hBtnImg1;
	HELE m_hBtnImg2;
	HELE m_hBtnImg3;
	HELE m_hButton;
	HELE m_hBtnFont1;
	HELE m_hBtnFont2;
	HELE m_hBtnFont3;
	HELE m_hBtnColor1;
	HELE m_hBtnColor2;
	HELE m_hBtnColor3;
	int  m_iCurStyle;

	CEditRecv* m_pRecv;
	void Init(HWINDOW hWindow, int left, int top, int width, int height)
	{
		m_hWindow = hWindow;
		InitBar(left, top);

		m_hBtnSend = XBtn_Create(left + width + 10, top, 80, 30, L"发 送", hWindow);
		XEle_EnableFocus(m_hBtnSend, FALSE);

		m_hBtnSend_Insert = XBtn_Create(left + width + 10, top + 40, 80, 30, L"插 入", hWindow);
		XEle_EnableFocus(m_hBtnSend_Insert, FALSE);

		m_hEdit = XEdit_CreateEx(left, top, width, height, edit_type_richedit, hWindow);

		XEle_EnableKeyTab(m_hEdit, TRUE);
		XEdit_EnableAutoWrap(m_hEdit, FALSE);
#if 10
		XEdit_AddText(m_hEdit, L"ABC");

		HIMAGE hImage1 = XImage_LoadFile(L"image\\123.png");
		HIMAGE hImage2 = XImage_LoadFile(L"image\\logo.png");
		XEdit_AddObject(m_hEdit, hImage1);
		XEdit_AddObject(m_hEdit, hImage2);

		HELE hBtn = XBtn_Create(0, 0, 60, 24, L"cc", m_hEdit);
		XEdit_AddObject(m_hEdit, hBtn);

		HIMAGE hImageGif = XImage_LoadFile(L"image\\gif.gif");
		if (hImageGif)
		{
			HXCGUI hGif = XShapeGif_Create(0, 0, XImage_GetWidth(hImageGif), XImage_GetHeight(hImageGif), m_hEdit);
			XShapeGif_SetImage(hGif, hImageGif);
			XEdit_AddObject(m_hEdit, hGif);
		}

		int iStyle = XEdit_AddStyleEx(m_hEdit, L"微软雅黑", 16, 0, RGBA(200, 0, 0, 255), TRUE);
		XEdit_AddTextEx(m_hEdit, L"123", iStyle);
		iStyle = XEdit_AddStyleEx(m_hEdit, L"微软雅黑", 24, 0, RGBA(0, 200, 0, 255), TRUE);
		XEdit_AddTextEx(m_hEdit, L"123", iStyle);
		iStyle = XEdit_AddStyleEx(m_hEdit, L"微软雅黑", 36, 0, RGBA(0, 0, 200, 255), TRUE);
		XEdit_AddTextEx(m_hEdit, L"123", iStyle);
#endif
		XEle_RegEventCPP(m_hBtnSend, XE_BNCLICK, &CEditSend::OnBtnClick_Send);
		XEle_RegEventCPP(m_hBtnSend_Insert, XE_BNCLICK, &CEditSend::OnBtnClick_Send_Insert);
		XEle_RegEventCPP(m_hBtnImg1, XE_BNCLICK, &CEditSend::OnBtnClick_img1);
		XEle_RegEventCPP(m_hBtnImg2, XE_BNCLICK, &CEditSend::OnBtnClick_img2);
		XEle_RegEventCPP(m_hBtnImg3, XE_BNCLICK, &CEditSend::OnBtnClick_img3);
		XEle_RegEventCPP(m_hButton, XE_BNCLICK, &CEditSend::OnBtnClick_button);
		XEle_RegEventCPP(m_hBtnFont1, XE_BUTTON_CHECK, &CEditSend::OnBtnClick_font1);
		XEle_RegEventCPP(m_hBtnFont2, XE_BUTTON_CHECK, &CEditSend::OnBtnClick_font2);
		XEle_RegEventCPP(m_hBtnFont3, XE_BUTTON_CHECK, &CEditSend::OnBtnClick_font3);

		XEle_RegEventCPP(m_hBtnColor1, XE_BUTTON_CHECK, &CEditSend::OnBtnClick_color1);
		XEle_RegEventCPP(m_hBtnColor2, XE_BUTTON_CHECK, &CEditSend::OnBtnClick_color2);
		XEle_RegEventCPP(m_hBtnColor3, XE_BUTTON_CHECK, &CEditSend::OnBtnClick_color3);
		XEle_RegEventCPP(m_hEdit, XE_EDIT_STYLE_CHANGED, &CEditSend::OnEditStyleChanged);
		XWnd_RegEventCPP(hWindow, WM_PAINT, &CEditSend::OnWndDrawWindow);
	}
	void InitBar(int left, int top)
	{
		int x = left;
		m_hBtnImg1 = XBtn_Create(x, top - 25, 60, 20, L"img1", m_hWindow); x += 65;
		m_hBtnImg2 = XBtn_Create(x, top - 25, 60, 20, L"img2", m_hWindow); x += 65;
		m_hBtnImg3 = XBtn_Create(x, top - 25, 60, 20, L"gif", m_hWindow); x += 65;
		m_hButton = XBtn_Create(x, top - 25, 60, 20, L"button", m_hWindow); x += 65;
		m_hBtnFont1 = XBtn_Create(x, top - 25, 60, 20, L"字体12", m_hWindow); x += 65;
		m_hBtnFont2 = XBtn_Create(x, top - 25, 60, 20, L"字体24", m_hWindow); x += 65;
		m_hBtnFont3 = XBtn_Create(x, top - 25, 60, 20, L"字体36", m_hWindow); x += 65;

		m_hBtnColor1 = XBtn_Create(x, top - 25, 60, 20, L"color1", m_hWindow); x += 65;
		m_hBtnColor2 = XBtn_Create(x, top - 25, 60, 20, L"color2", m_hWindow); x += 65;
		m_hBtnColor3 = XBtn_Create(x, top - 25, 60, 20, L"color3", m_hWindow); x += 65;

		XEle_EnableFocus(m_hBtnImg1, FALSE);
		XEle_EnableFocus(m_hBtnImg2, FALSE);
		XEle_EnableFocus(m_hBtnImg3, FALSE);
		XEle_EnableFocus(m_hButton, FALSE);
		XEle_EnableFocus(m_hBtnFont1, FALSE);
		XEle_EnableFocus(m_hBtnFont2, FALSE);
		XEle_EnableFocus(m_hBtnFont3, FALSE);

		XEle_EnableFocus(m_hBtnColor1, FALSE);
		XEle_EnableFocus(m_hBtnColor2, FALSE);
		XEle_EnableFocus(m_hBtnColor3, FALSE);

		XBtn_SetTypeEx(m_hBtnFont1, button_type_radio);
		XBtn_SetTypeEx(m_hBtnFont2, button_type_radio);
		XBtn_SetTypeEx(m_hBtnFont3, button_type_radio);
		XBtn_SetGroupID(m_hBtnFont1, 2);
		XBtn_SetGroupID(m_hBtnFont2, 2);
		XBtn_SetGroupID(m_hBtnFont3, 2);

		XBtn_SetTypeEx(m_hBtnColor1, button_type_radio);
		XBtn_SetTypeEx(m_hBtnColor2, button_type_radio);
		XBtn_SetTypeEx(m_hBtnColor3, button_type_radio);
		XBtn_SetGroupID(m_hBtnColor1, 3);
		XBtn_SetGroupID(m_hBtnColor2, 3);
		XBtn_SetGroupID(m_hBtnColor3, 3);
	}
	int  OnBtnClick_Send(BOOL* pbHandled)
	{
		edit_data_copy_* data = XEdit_GetData(m_hEdit);
		if (data)
		{
			m_pRecv->Recv(data, FALSE);
			XEdit_FreeData(data);
		}
		return 0;
	}
	int  OnBtnClick_Send_Insert(BOOL* pbHandled)
	{
		edit_data_copy_* data = XEdit_GetData(m_hEdit);
		if (data)
		{
			m_pRecv->Recv(data, TRUE);
			XEdit_FreeData(data);
		}
		return 0;
	}
	int  OnBtnClick_img1(BOOL* pbHandled)
	{
		HIMAGE hImage = XImage_LoadFile(L"image\\123.png");
		if (hImage)
		{
			XEdit_AddObject(m_hEdit, hImage);
			//	XEdit_AddObject(m_hEdit, hImage);
			XEle_AdjustLayout(m_hEdit);

			XEdit_AutoScroll(m_hEdit);
			XEle_Redraw(m_hEdit);
		}
		return 0;
	}
	int  OnBtnClick_img2(BOOL* pbHandled)
	{
		HIMAGE hImage = XImage_LoadFile(L"image\\logo.png");
		if (hImage)
		{
			XEdit_AddObject(m_hEdit, hImage);
			XEle_AdjustLayout(m_hEdit);

			XEdit_AutoScroll(m_hEdit);
			XEle_Redraw(m_hEdit);
		}
		return 0;
	}
	int  OnBtnClick_img3(BOOL* pbHandled)
	{
		HIMAGE hImageGif = XImage_LoadFile(L"image\\gif.gif");
		if (hImageGif)
		{
			HXCGUI hGif = XShapeGif_Create(0, 0, XImage_GetWidth(hImageGif), XImage_GetHeight(hImageGif), m_hEdit);
			XShapeGif_SetImage(hGif, hImageGif);
			XEdit_AddObject(m_hEdit, hGif);
			XEle_AdjustLayout(m_hEdit);

			XEdit_AutoScroll(m_hEdit);
			XEle_Redraw(m_hEdit);
		}
		return 0;
	}
	int  OnBtnClick_button(BOOL* pbHandled)
	{
		HELE hButton = XBtn_Create(0, 0, 60, 20, L"button", m_hEdit);
		XEdit_AddObject(m_hEdit, hButton);
		XEle_AdjustLayout(m_hEdit);

		XEdit_AutoScroll(m_hEdit);
		XEle_Redraw(m_hEdit);
		return 0;
	}
	int  OnBtnClick_font1(BOOL bCheck, BOOL* pbHandled)
	{
		if (bCheck)	FontColorChange();
		return 0;
	}
	int  OnBtnClick_font2(BOOL bCheck, BOOL* pbHandled)
	{
		if (bCheck)	FontColorChange();
		return 0;
	}
	int  OnBtnClick_font3(BOOL bCheck, BOOL* pbHandled)
	{
		if (bCheck)	FontColorChange();
		return 0;
	}
	int  OnBtnClick_color1(BOOL bCheck, BOOL* pbHandled)
	{
		if (bCheck)	FontColorChange();
		return 0;
	}
	int  OnBtnClick_color2(BOOL bCheck, BOOL* pbHandled)
	{
		if (bCheck)	FontColorChange();
		return 0;
	}
	int  OnBtnClick_color3(BOOL bCheck, BOOL* pbHandled)
	{
		if (bCheck) FontColorChange();
		return 0;
	}
	void FontColorChange()
	{
		int fontSize = 12;
		if (XBtn_IsCheck(m_hBtnFont1))
		{
			fontSize = 12;
		} else if (XBtn_IsCheck(m_hBtnFont2))
		{
			fontSize = 24;
		} else if (XBtn_IsCheck(m_hBtnFont3))
		{
			fontSize = 36;
		}
		COLORREF  color = 0XFF000000;
		if (XBtn_IsCheck(m_hBtnColor1))
		{
			color = RGBA(200, 0, 0, 255);
		} else if (XBtn_IsCheck(m_hBtnColor2))
		{
			color = RGBA(0, 200, 0, 255);
		} else if (XBtn_IsCheck(m_hBtnColor3))
		{
			color = RGBA(0, 0, 200, 255);
		}
		int iStyle = XEdit_AddStyleEx(m_hEdit, L"微软雅黑", fontSize, 0, color, TRUE);
		m_iCurStyle = iStyle;
		XEdit_SetCurStyle(m_hEdit, iStyle);
		XWnd_Redraw(m_hWindow);
	}
	int  OnEditStyleChanged(int iStyle, BOOL* pbHandled)
	{
		m_iCurStyle = iStyle;
		XWnd_Redraw(m_hWindow);
		return 0;
	}
	int  OnWndDrawWindow(HDRAW hDraw, BOOL* pbHandled)
	{
		*pbHandled = TRUE;
		XWnd_DrawWindow(m_hWindow, hDraw);
		RECT rc;
		XEle_GetRect(m_hEdit, &rc);
		XDraw_SetBrushColor(hDraw, RGBA(200, 0, 0, 255));

		edit_style_info_ info;
		if (XEdit_GetStyleInfo(m_hEdit, m_iCurStyle, &info))
		{
			if (edit_style_type_font_color == info.type)
			{
				if (info.hFont_image_obj)
				{
					wstring  text = L"字体:";
					font_info_ f;
					XFont_GetFontInfo((HFONTX)info.hFont_image_obj, &f);
					text += f.name;
					text += L", ";
					text += XC_itow(f.nSize);
					XDraw_TextOut(hDraw, rc.right + 10, rc.top + 90, text.c_str(), text.size());
				};
				if (info.bColor)
				{
					wstring text = L"颜色:";
					wchar_t  buf[32] = { 0 };
					buf[0] = L'#';
					buf[1] = L'F';
					buf[2] = L'F';
					wsprintf(buf + 3, L"%02X", GetRValue(info.color));
					wsprintf(buf + 5, L"%02X", GetGValue(info.color));
					wsprintf(buf + 7, L"%02X", GetBValue(info.color));
					text += buf;
					XDraw_TextOut(hDraw, rc.right + 10, rc.top + 110, text.c_str(), text.size());
				}
			}
		}
		return 0;
	}
};

class CQQChat
{
public:
	HWINDOW m_hWindow;
	HELE m_hEdit;
	CEditRecv   m_edit_recv;
	CEditSend   m_edit_send;

	CQQChat() {
		Init();
	}
	void Init()
	{
		m_hWindow = XWnd_Create(0, 0, 800, 800, L"炫彩界面库窗口", NULL, window_style_default);
		XWnd_EnableDragWindow(m_hWindow, TRUE);
		XWnd_EnableDragBorder(m_hWindow, FALSE);

		int top = 40;
		m_edit_recv.Init(m_hWindow, 20, top, 600, 500); top += (500 + 30);
		m_edit_send.Init(m_hWindow, 20, top, 600, 200);
		m_edit_send.m_pRecv = &m_edit_recv;
		XWnd_ShowWindow(m_hWindow, SW_SHOW);
	}
	void OnExit()
	{
		m_edit_recv.OnExit();
	}
};

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPTSTR lpCmdLine, int nCmdShow)
{
	XInitXCGUI(FALSE);
	CQQChat  MyWindow;
	XRunXCGUI();
	MyWindow.OnExit();
	XExitXCGUI();
	return 0;
}
