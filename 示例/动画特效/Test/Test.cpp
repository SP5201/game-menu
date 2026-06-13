// Test.cpp : 定义应用程序的入口点。
//

#include "stdafx.h"
#include "Test.h"
#include <vector>

//包含炫彩界面库文件
#include "../../../DLL/xcgui.h"
#pragma comment(lib,"../../../DLL/XCGUI.lib")

#pragma warning(disable:4244)

#if  10


class CMyBase
{
public:
	virtual  void Release() = 0;
};

HWINDOW          hWindow = NULL;
HSVG             hSvg = NULL;
std::vector<HSVG>     list_svg;
std::vector<HXCGUI>   list_xcgui;
std::vector<HXCGUI>   list_animation;
std::vector<CMyBase*>  list_object;

void ReleaseObject(HXCGUI hObject)
{
	XC_OBJECT_TYPE xc_type = XObj_GetTypeBase(hObject);
	if (XC_ELE == xc_type)
		XEle_Destroy((HELE)hObject);
	else if (XC_SHAPE == xc_type)
		XShape_Destroy(hObject);
	else if (XC_SVG == xc_type)
		XSvg_Release((HSVG)hObject);
}

void ReleaseAnimation()
{
	for (auto var: list_object)
		var->Release();
	list_object.clear();

	for (auto var: list_animation)
		XAnima_Release(var);
	list_animation.clear();

	for (auto  var: list_svg)
		XSvg_Release(var);
	list_svg.clear();

	for (auto var : list_xcgui)
		ReleaseObject(var);
	list_xcgui.clear();
}

HELE CreateButtonRadio(int left, int& top, const wchar_t* pName)
{
	HELE hBtn = XBtn_Create(left, top, 110, 30, pName, hWindow);
	XBtn_SetTextAlign(hBtn, textAlignFlag_left | textAlignFlag_vcenter);
	XObj_SetTypeEx(hBtn, button_type_radio);
	XBtn_SetGroupID(hBtn, 1);
	top += 29;
	return hBtn;
}
HELE CreateButton(int left, int top, int width, int height, const wchar_t* pName)
{
	HELE hBtn = XBtn_Create(left, top, width, height, pName, hWindow);
	XBtn_SetTextAlign(hBtn, textAlignFlag_left | textAlignFlag_vcenter);
	//XObj_SetTypeEx(hBtn, button_type_radio);
	//XBtn_SetGroupID(hBtn, 2);
	XEle_SetPadding(hBtn, 10, 0, 0, 0);
	return hBtn;
}

int CALLBACK OnWndDrawWindow(HWINDOW hWindow, HDRAW hDraw, BOOL* pbHandled)
{
	*pbHandled = TRUE;
	XWnd_DrawWindow(hWindow, hDraw);

	if (hSvg)
	{
		XDraw_DrawSvgSrc(hDraw, hSvg);
	}
	for (auto var: list_svg)
		XDraw_DrawSvgSrc(hDraw, var);

// 	RECT rc;
// 	rc.left = 200;
// 	rc.top = 100;
// 	rc.right = rc.left + 100;
// 	rc.bottom = rc.top + 100;
// 	
// 	XDraw_SetBrushColor(hDraw, 0xFF0000FF);
// 	
// 	XDraw_SetOffset(hDraw, -100, 0);
// 	XDraw_FillEllipse(hDraw, &rc);
// 	XDraw_SetOffset(hDraw, 0, 0);

	return 0;
}

//下落  缩放 缓动
int CALLBACK OnBtnClick1(BOOL* pbHandled)
{
	ReleaseAnimation();
	int left = 130;
	int top = 22;
	list_svg.push_back(XSvg_LoadFile(L"svg\\公益.svg"));
	list_svg.push_back(XSvg_LoadFile(L"svg\\时间戳.svg"));
	list_svg.push_back(XSvg_LoadFile(L"svg\\技术服务.svg"));
	list_svg.push_back(XSvg_LoadFile(L"svg\\底层架构.svg"));
	list_svg.push_back(XSvg_LoadFile(L"svg\\查验.svg"));
	list_svg.push_back(XSvg_LoadFile(L"svg\\接口配置.svg"));

	HXCGUI hGroup = XAnimaGroup_Create(0);
	list_animation.push_back(hGroup);
	XAnima_Run(hGroup, hWindow);
	for (UINT i = 0; i < list_svg.size(); i++)
	{
		XSvg_SetSize(list_svg[i], 100, 100);
		XSvg_SetPosition(list_svg[i], left, top);

		HXCGUI  hAnimation = XAnima_Create(list_svg[i]);
		XAnimaGroup_AddItem(hGroup, hAnimation);

		XAnima_Move(hAnimation, 500, left, 22, 1, ease_flag_bounce | ease_flag_out);
		XAnima_Delay(hAnimation, 500);

		XAnima_Delay(hAnimation, 100*i);
		XAnima_Alpha(hAnimation, 500, 0, 1);

		XAnima_Delay(hAnimation, 500);

		XAnima_Alpha(hAnimation, 500, 255, 1);
		XAnima_Delay(hAnimation, 1000);

		XAnima_Move(hAnimation, 2000, left, 500, 1, ease_flag_bounce | ease_flag_out);
		XAnima_Delay(hAnimation, 1000);

		left += 130;
		{
			hAnimation = XAnima_Create(list_svg[i]);
			XAnima_Delay(hAnimation, 6000 + i * 200);
			XAnima_Scale(hAnimation, 1200, 2.0, 2.0, 1, ease_flag_cubic | ease_flag_in);

			XAnimaGroup_AddItem(hGroup, hAnimation);
		}
	}
	return 0;
}

//下落 缩放 缓动
int CALLBACK OnBtnClick2(BOOL* pbHandled)
{
	ReleaseAnimation();
	int left = 450;
	int top = 22;
	
	list_svg.push_back(XSvg_LoadFile(L"svg\\公益.svg"));
	XSvg_SetSize(list_svg[0], 100, 100);
	XSvg_SetPosition(list_svg[0], left, top);

	HXCGUI hGroup = XAnimaGroup_Create();
	list_animation.push_back(hGroup);
	XAnima_Run(hGroup, hWindow);

	//下落
	HXCGUI hAnimation = XAnima_Create(list_svg[0], 0);
	XAnimaGroup_AddItem(hGroup, hAnimation);
	{
		XAnima_Move(hAnimation, 2000,left, 500, 1, ease_flag_bounce | ease_flag_out);
		//停留
		XAnima_Delay(hAnimation, 2000);
		//返回顶部
		XAnima_Move(hAnimation, 500, left, 22, 1, ease_flag_bounce | ease_flag_out);
	}

	//缩放
	hAnimation = XAnima_Create(list_svg[0], 1);
	XAnimaGroup_AddItem(hGroup, hAnimation);
	{
		XAnima_Delay(hAnimation, 2000);
		XAnima_Scale(hAnimation, 1000, 2.0, 2.0, 0, ease_flag_cubic | ease_flag_in);
	}
	return 0;
}

//呼吸
int CALLBACK OnBtnClick3(BOOL* pbHandled)
{
	ReleaseAnimation();
	int left = 300;
	int top = 150;

	list_svg.push_back(XSvg_LoadFile(L"svg\\公益.svg"));
	XSvg_SetSize(list_svg[0], 300, 300);
	XSvg_SetPosition(list_svg[0], left, top);

	HXCGUI hAnimation = XAnima_Create(list_svg[0], 1);
	list_animation.push_back(hAnimation);
	XAnima_Scale(hAnimation, 1500, 2.0, 2.0, 0, ease_flag_quad | ease_flag_in);
	XAnima_Run(hAnimation, hWindow);
	return 0;
}

//不透明度
int CALLBACK OnBtnClick4(BOOL* pbHandled)
{
	ReleaseAnimation();
	int left = 200;
	int top = 30;
	list_svg.push_back(XSvg_LoadFile(L"svg\\公益.svg"));
 	list_svg.push_back(XSvg_LoadFile(L"svg\\公益.svg"));
	list_svg.push_back(XSvg_LoadFile(L"svg\\公益.svg"));
	for (UINT i = 0; i < list_svg.size(); i++)
	{
		XSvg_SetSize(list_svg[i], 100, 100);
		XSvg_SetPosition(list_svg[i], left + i * 100, top);
	}

	HXCGUI hAnimation = XAnima_Create(list_svg[0], 1);
	list_animation.push_back(hAnimation);
	XAnima_AlphaEx(hAnimation, 3000, 0, 255, 1);
	XAnima_Run(hAnimation, hWindow);

	hAnimation = XAnima_Create(list_svg[1], 1);
	list_animation.push_back(hAnimation);
	XAnima_Alpha(hAnimation, 3000, 0, 1, 0, TRUE);
	XAnima_Run(hAnimation, hWindow);

	hAnimation = XAnima_Create(list_svg[2], 1);
	list_animation.push_back(hAnimation);
	XAnima_Alpha(hAnimation, 3000, 0, 0, 0, TRUE);
	XAnima_Run(hAnimation, hWindow);

#if 10
	top = 100;
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);

	XAnima_Alpha(hAnimation, 3000, 0, 1, 0, TRUE);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10
	top += 150;
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);

	XAnima_AlphaEx(hAnimation, 3000, 255, 50, 1, 0, TRUE);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10
	top += 150;
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);

	XAnima_AlphaEx(hAnimation, 3000, 50, 255, 1, 0, TRUE);
	XAnima_Run(hAnimation, hWindow);
#endif
	return 0;
}

//移动
int CALLBACK OnBtnClick5(BOOL* pbHandled)
{
	ReleaseAnimation();
	int left = 150;
	int top = 30;

	list_svg.push_back(XSvg_LoadFile(L"svg\\公益.svg"));
	list_svg.push_back(XSvg_LoadFile(L"svg\\时间戳.svg"));
	list_svg.push_back(XSvg_LoadFile(L"svg\\技术服务.svg"));
	for (UINT i = 0; i< list_svg.size(); i++)
	{
		XSvg_SetSize(list_svg[i], 100, 100);
		XSvg_SetPosition(list_svg[i], left, top + i*100);
	}

	top = 22;
	//循环
	HXCGUI hAnimation = XAnima_Create(list_svg[0], 1);
	list_animation.push_back(hAnimation);
	XAnima_Run(hAnimation, hWindow);
	XAnima_Move(hAnimation, 2000, 750, top, 10, 0, TRUE); top += 100;

	//一次,往返
	hAnimation = XAnima_Create(list_svg[1], 1);
	list_animation.push_back(hAnimation);
	XAnima_Run(hAnimation, hWindow);
  	XAnima_Move(hAnimation, 2000, 750, top, 1, 0, TRUE); top += 100;

	//一次, 不往返
	hAnimation = XAnima_Create(list_svg[2], 1);
	list_animation.push_back(hAnimation);
	XAnima_Run(hAnimation, hWindow);
 	XAnima_Move(hAnimation, 2000, 750, top, 1, 0, FALSE);
	return 0;
}

//形状文本
int CALLBACK OnBtnClick6(BOOL* pbHandled)
{
	ReleaseAnimation();
	int left = 140;
	int top = 100;

	HXCGUI hShapeText1 = XShapeText_Create(left, top, 100, 30, L"循环滚动", hWindow); top += 50;
	HXCGUI hShapeText2 = XShapeText_Create(left, top, 100, 30, L"往返滚动", hWindow); top += 50;
	HXCGUI hShapeText3 = XShapeText_Create(left, top, 100, 30, L"移动到末尾", hWindow); top += 50;
	list_xcgui.push_back(hShapeText1);
	list_xcgui.push_back(hShapeText2);
	list_xcgui.push_back(hShapeText3);

	top = 100;
	HXCGUI hAnimation = XAnima_Create(hShapeText1, 0);
	list_animation.push_back(hAnimation);
	XAnima_Run(hAnimation, hWindow);
	XAnima_Move(hAnimation, 3000, 750, top, 1, ease_flag_bounce | ease_flag_out, TRUE);
	
	hAnimation = XAnima_Create(hShapeText2, 1);
	list_animation.push_back(hAnimation);
	XAnima_Run(hAnimation, hWindow);
	XAnima_Move(hAnimation, 3000, 750, top +50, 1, ease_flag_bounce | ease_flag_out, TRUE);
	
	hAnimation = XAnima_Create(hShapeText3, 1);
	list_animation.push_back(hAnimation);
	XAnima_Run(hAnimation, hWindow);
	XAnima_Move(hAnimation, 1500, 750, top +100, 1, ease_flag_bounce | ease_flag_out, FALSE);
	return 0;
}

//按钮
int CALLBACK OnBtnClick7(BOOL* pbHandled)
{
	ReleaseAnimation();
 	int left = 125;
 	int top = 50;
#if 10
	HXCGUI hGroup = XAnimaGroup_Create(0);
	list_animation.push_back(hGroup);
	XAnima_Run(hGroup,hWindow);
	for (int i = 0; i < 13; i++)
	{
		HELE hButton = XBtn_Create(left, top, 60, 30, L"透明度", hWindow);
		list_xcgui.push_back(hButton);

		HXCGUI  hAnimation = XAnima_Create(hButton);
		XAnimaGroup_AddItem(hGroup, hAnimation);

		XAnima_Delay(hAnimation, 500);

		XAnima_Delay(hAnimation, 100 * i);
		XAnima_AlphaEx(hAnimation, 1200, 255, 20, 1,0, TRUE);
		left += 61;
	}
#endif

#if 1
	left = 125;
	top = 100;
	hGroup = XAnimaGroup_Create(0);
	list_animation.push_back(hGroup);
	XAnima_Run(hGroup, hWindow);
	for (int i = 0; i < 7; i++)
	{
		HELE hButton = XBtn_Create(left, top, 80, 30, L"循环滚动", hWindow);
		list_xcgui.push_back(hButton);

		{
 			HXCGUI  hAnimation = XAnima_Create(hButton);
			XAnimaGroup_AddItem(hGroup, hAnimation);

			XAnima_Move(hAnimation, 500, left, top, 1, ease_flag_bounce | ease_flag_out);
			XAnima_Delay(hAnimation, 500);

			XAnima_Delay(hAnimation, 100 * i);
			XAnima_AlphaEx(hAnimation, 500, 255, 0, 1);

			XAnima_Delay(hAnimation, 500);

			XAnima_AlphaEx(hAnimation, 500, 0, 255, 1);
			XAnima_Delay(hAnimation, 1000);

			XAnima_Move(hAnimation, 2000, left, 500, 1, ease_flag_bounce | ease_flag_out);
			XAnima_Delay(hAnimation, 1000);
		}
		{
			HXCGUI hAnimation = XAnima_Create(hButton, 1);
			XAnimaGroup_AddItem(hGroup, hAnimation);
			XAnima_Delay(hAnimation, 6000 + i * 200);
			XAnima_Scale(hAnimation, 1200, 1.5, 2.0, 1, ease_flag_cubic | ease_flag_in, TRUE);

 		}
		left += 110;
	}
#endif
	return 0;
}

HELE  hLayout1 = NULL;
HELE  hLayout2 = NULL;
HELE  hLayout3 = NULL;
int CALLBACK OnMouseStay8(HELE hLayout, BOOL* pbHandled)
{
	if (hLayout1 != hLayout)
		XEle_SetAlpha(hLayout1, 200);
	if (hLayout2 != hLayout)
		XEle_SetAlpha(hLayout2, 200);
	if (hLayout3 != hLayout)
		XEle_SetAlpha(hLayout3, 200);

	HXCGUI hAnimation = XAnima_Create(hLayout, 1);
	list_animation.push_back(hAnimation);
	XAnima_LayoutWidth(hAnimation, 300, layout_size_weight, 200, 1, 0, FALSE);
	XAnima_Run(hAnimation, hWindow);
	return 0;
}

int CALLBACK OnMouseLeave8(HELE hLayout, HELE hEleStay, BOOL* pbHandled)
{
	HXCGUI hAnimation = XAnima_Create(hLayout, 1);
	list_animation.push_back(hAnimation);
	XAnima_LayoutWidth(hAnimation, 300, layout_size_weight, 100, 1, 0, FALSE);
	XAnima_Run(hAnimation, hWindow);

	XEle_SetAlpha(hLayout1, 255);
	XEle_SetAlpha(hLayout2, 255);
	XEle_SetAlpha(hLayout3, 255);
	return 0;
}

//布局焦点展开
int CALLBACK OnBtnClick8(BOOL* pbHandled)
{
	ReleaseAnimation();

	HELE  hLayout = XLayout_Create(140, 100, 750, 100, hWindow);
	XLayoutBox_SetSpace(hLayout, 20);
	list_xcgui.push_back(hLayout);

	for (int i = 0;i<3; i++)
	{
		HELE hLayout_ = XLayout_Create(0, 0, 100, 100, hLayout);
		XEle_SetPadding(hLayout_, 10, 0, 10, 0);

		HXCGUI hShapeText = XShapeText_Create(0, 0, 100, 100, L"炫彩界面库-www.xcgui.com-鼠标移动到上面查看", hLayout_);
		XShapeText_SetTextColor(hShapeText, RGBA(255, 255, 255,255));
		XWidget_LayoutItem_SetWidth(hShapeText, layout_size_fill, 0);

		list_xcgui.push_back(hLayout_);
		XEle_EnableMouseThrough(hLayout_, FALSE);
		XWidget_LayoutItem_SetWidth(hLayout_, layout_size_weight, 100);
		
		XBkM_SetBkInfo(XEle_GetBkManager(hLayout_), L"{99:1.9.9;98:16(0);5:2(15)20(1)21(3)26(1)22(-7839744)23(255)9(5,5,5,5);}");
		XEle_RegEventC1(hLayout_, XE_MOUSESTAY, OnMouseStay8);
		XEle_RegEventC1(hLayout_, XE_MOUSELEAVE, OnMouseLeave8);

		if (0 == i)	hLayout1 = hLayout_;
		if (1 == i)	hLayout2 = hLayout_;
		if (2 == i)	hLayout3 = hLayout_;
	}

	XWnd_AdjustLayout(hWindow);
	XWnd_Redraw(hWindow);
	return 0;
}

int CALLBACK OnMouseStay9(HELE hEle, BOOL* pbHandled)
{
	HELE hEle2 = (HELE)XEle_GetUserData(hEle);
	//释放当前对象关联的动画
	for (int i = list_animation.size() - 1; i >= 0; i--)
	{
		HXCGUI hObjectUI = XAnima_GetObjectUI(list_animation[i]);
		if (hEle == hObjectUI || hEle2 == hObjectUI)
		{
			XAnima_Release(list_animation[i], FALSE);
			list_animation.erase(list_animation.begin() + i);
		}
	}

	HXCGUI hAnimation = XAnima_Create(hEle, 1);
	list_animation.push_back(hAnimation);
	XAnima_Run(hAnimation, hEle);
	XAnima_AlphaEx(hAnimation, 1000, 255, 0,1);
	XAnima_Show(hAnimation, 0, FALSE);

	XEle_SetAlpha(hEle2, 0);
	XWidget_Show(hEle2, TRUE);

	hAnimation = XAnima_Create(hEle2, 1);
	list_animation.push_back(hAnimation);
	XAnima_Run(hAnimation, hEle2);
	XAnima_Delay(hAnimation, 500);
	XAnima_AlphaEx(hAnimation, 1000, 0, 255, 1);

	return 0;
}

int CALLBACK OnMouseLeave9(HELE hEle2, HELE hEleStay, BOOL* pbHandled)
{
	HELE hEle = (HELE)XEle_GetUserData(hEle2);
	//释放当前对象关联的动画
	for (int i = list_animation.size() - 1; i >= 0; i--)
	{
		HXCGUI hObjectUI = XAnima_GetObjectUI(list_animation[i]);
		if (hEle == hObjectUI || hEle2 == hObjectUI)
		{
			XAnima_Release(list_animation[i], FALSE);
			list_animation.erase(list_animation.begin() + i);
		}
	}

	HXCGUI hAnimation = XAnima_Create(hEle2, 1);
	list_animation.push_back(hAnimation);
	XAnima_Run(hAnimation, hEle2);
	XAnima_AlphaEx(hAnimation, 1000, 255, 0, 1);
	XAnima_Show(hAnimation, 0, FALSE);

	XEle_SetAlpha(hEle, 0);
	XWidget_Show(hEle, TRUE);

	hAnimation = XAnima_Create(hEle, 1);
	list_animation.push_back(hAnimation);
	XAnima_Run(hAnimation, hEle);
	XAnima_Delay(hAnimation, 500);
	XAnima_AlphaEx(hAnimation, 1000, 0, 255, 1);
	return 0;
}

//图片切换- 两个基础元素透明度切换
int CALLBACK OnBtnClick9(BOOL* pbHandled)
{
	ReleaseAnimation();

	int left = 150;
	int top = 50;
	for (int i = 0; i<3; i++)
	{
		wchar_t  buf[MAX_PATH] = {0};
		wsprintf(buf, L"image\\img-%d.jpg", i*2+1);
		HIMAGE hImage = XImage_LoadFile(buf);
		XImage_SetDrawType(hImage, image_draw_type_fixed_ratio);
		
		HELE   hEle = XEle_Create(left, top, 211, 270, hWindow);
		XEle_AddBkImage(hEle, element_state_flag_leave, hImage);
		list_xcgui.push_back(hEle);

		//--
		wsprintf(buf, L"image\\img-%d.jpg", i*2 + 2);
		HIMAGE hImage2 = XImage_LoadFile(buf);
		XImage_SetDrawType(hImage2, image_draw_type_fixed_ratio);

		HELE   hEle2 = XEle_Create(left, top, 211, 270, hWindow);
		XEle_AddBkImage(hEle2, element_state_flag_leave, hImage2);
		list_xcgui.push_back(hEle2);
		//--
		XEle_SetUserData(hEle, (vint)hEle2);
		XEle_SetUserData(hEle2, (vint)hEle);
		XWidget_Show(hEle2, FALSE);

		HXCGUI hText = XShapeText_Create(left, top + 280, 200, 40, L"炫彩界面库-图片切换\n$66.66", hWindow);
		XShapeText_SetTextColor(hText, RGBA(80, 80, 80, 255));
		list_xcgui.push_back(hText);

		XEle_RegEventC1(hEle, XE_MOUSESTAY, OnMouseStay9);
		XEle_RegEventC1(hEle2, XE_MOUSELEAVE, OnMouseLeave9);

		left += (211+10);
	}
	XWnd_Redraw(hWindow);
	return 0;
}

int CALLBACK OnMouseStay10(HELE hEle, BOOL* pbHandled)
{
	//释放当前对象关联的动画
	for (int i = list_animation.size() - 1; i >= 0; i--)
	{
		if (hEle == XAnima_GetObjectUI(list_animation[i]))
		{
			XAnima_Release(list_animation[i], FALSE);
			list_animation.erase(list_animation.begin() + i);
		}
	}
	HXCGUI hPic = XEle_GetChildByIndex(hEle, 0);

	HXCGUI hAnimation = XAnima_Create(hPic, 1);
	list_animation.push_back(hAnimation);
	XAnima_Run(hAnimation, hEle);
 	XAnima_Move(hAnimation, 500, -(211+10), 0, 1, ease_flag_cubic | ease_flag_in);

	hPic = XEle_GetChildByIndex(hEle, 1);

	hAnimation = XAnima_Create(hPic, 1);
	list_animation.push_back(hAnimation);
	XAnima_Run(hAnimation, hEle);
   	XAnima_Move(hAnimation, 500, 0, 0, 1, ease_flag_cubic | ease_flag_in);
	return 0;
}

int CALLBACK OnMouseLeave10(HELE hEle, HELE hEleStay, BOOL* pbHandled)
{
	//释放当前对象关联的动画
	for (int i = list_animation.size() - 1; i >= 0; i--)
	{
		if (hEle == XAnima_GetObjectUI(list_animation[i]))
		{
			XAnima_Release(list_animation[i], FALSE);
			list_animation.erase(list_animation.begin() + i);
		}
	}

	HXCGUI hPic = XEle_GetChildByIndex(hEle, 0);

	HXCGUI hAnimation = XAnima_Create(hPic, 1);
	list_animation.push_back(hAnimation);
	XAnima_Run(hAnimation, hEle);
	XAnima_Move(hAnimation, 500, 0, 0,1, ease_flag_cubic | ease_flag_in);

	hPic = XEle_GetChildByIndex(hEle, 1);

	hAnimation = XAnima_Create(hPic, 1);
	list_animation.push_back(hAnimation);
	XAnima_Run(hAnimation, hEle);
	XAnima_Move(hAnimation, 500, 211+10, 0,1, ease_flag_cubic | ease_flag_in);
	return 0;
}

//图片切换2 - 滚动切换
int CALLBACK OnBtnClick10(BOOL* pbHandled)
{
	ReleaseAnimation();

	int left = 150;
	int top = 50;
	for (int i = 0; i < 3; i++)
	{
		HELE hEle = XEle_Create(left, top, 211, 270, hWindow);
		XEle_EnableDrawBorder(hEle, FALSE);
		list_xcgui.push_back(hEle);

 		wchar_t  buf[MAX_PATH] = { 0 };
 		wsprintf(buf, L"image\\img-%d.jpg", i * 2 + 1);
 		HIMAGE hImage = XImage_LoadFile(buf);	XImage_SetDrawType(hImage, image_draw_type_fixed_ratio);
 
		wsprintf(buf, L"image\\img-%d.jpg", i * 2 + 2);
  		HIMAGE hImage2 = XImage_LoadFile(buf);	XImage_SetDrawType(hImage2, image_draw_type_fixed_ratio);

 	 	HXCGUI hShapePic = XShapePic_Create(0, 0, 211, 270, hEle);
  		XShapePic_SetImage(hShapePic, hImage);
 
		HXCGUI hShapePic2 = XShapePic_Create(211+10, 0, 211, 270, hEle);
		XShapePic_SetImage(hShapePic2, hImage2);
  
  		HXCGUI hText = XShapeText_Create(left, top + 280, 200, 40, L"炫彩界面库3.2+\n$66.66", hWindow);
  		XShapeText_SetTextColor(hText, RGBA(80, 80, 80, 255));
  		list_xcgui.push_back(hText);

		XEle_RegEventC1(hEle, XE_MOUSESTAY, OnMouseStay10);
		XEle_RegEventC1(hEle, XE_MOUSELEAVE, OnMouseLeave10);

		left += (211+10);
	}
	XWnd_Redraw(hWindow);
	return 0;
}

int CALLBACK OnBtnClick11(BOOL* pbHandled)
{
	ReleaseAnimation();
	std::wstring  str = LR"(<svg x="0" y="0" width="25" height="25" viewBox="0 0 100 100"><circle cx="50" cy="50" r="50" fill="#ee6362" /></svg>)";
	std::wstring  str2 = LR"(<svg x="0" y="0" width="25" height="25" viewBox="0 0 100 100"><circle cx="50" cy="50" r="50" fill="#2cb0b2" /></svg>)";
	std::wstring  str3 = LR"(<svg x="0" y="0" width="20" height="20" viewBox="0 0 100 100"><circle cx="50" cy="50" r="50" fill="#f00" /></svg>)";
	int left = 160;
	int top = 80;
#if 10 //两个球型交替移动

	HSVG  hSvg =XSvg_LoadStringW(str.c_str());
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);

	HXCGUI hGroup = XAnimaGroup_Create(0);
	list_animation.push_back(hGroup);
	XAnima_Run(hGroup, hWindow);

	HXCGUI hAnimation = XAnima_Create(hSvg, 1);
	XAnimaGroup_AddItem(hGroup, hAnimation);
	XAnima_Move(hAnimation, 1000, left + 50, top, 1, ease_flag_sine | ease_flag_inOut, FALSE);
	XAnima_Move(hAnimation, 1000, left, top, 1, ease_flag_sine | ease_flag_inOut, FALSE);

 	hSvg = XSvg_LoadStringW(str2.c_str());
 	list_svg.push_back(hSvg);
 	XSvg_SetPosition(hSvg, left+50, top);

 	hGroup = XAnimaGroup_Create(0);
	list_animation.push_back(hGroup);
 	XAnima_Run(hGroup, hWindow);

	hAnimation = XAnima_Create(hSvg, 1);
	XAnimaGroup_AddItem(hGroup, hAnimation);
	XAnima_Move(hAnimation, 1000, left, top, 1, ease_flag_sine | ease_flag_inOut, FALSE);
	XAnima_Move(hAnimation, 1000, left+ 50, top, 1, ease_flag_sine | ease_flag_inOut, FALSE);
#endif

#if 10  //一排小球 缩放
	left = 350;
 	hGroup = XAnimaGroup_Create(0);
	list_animation.push_back(hGroup);
 	XAnima_Run(hGroup, hWindow);

	for (int i = 0 ; i<10; i++)
	{
		HSVG  hSvg = XSvg_LoadStringW(str3.c_str());
		list_svg.push_back(hSvg);
		XSvg_SetPosition(hSvg, left + i*50, top);

		HXCGUI hAnimation = XAnima_Create(hSvg, 0);
		XAnimaGroup_AddItem(hGroup, hAnimation);

		XAnima_Delay(hAnimation,  i*200);
		XAnima_Scale(hAnimation, 1000, 2.0f, 2.0f, 1, 0 , TRUE);
	}

#endif

#if 10 //一排小球 垂直缩放
	top = 150;
	hGroup = XAnimaGroup_Create(0);
	list_animation.push_back(hGroup);
	XAnima_Run(hGroup, hWindow);

	for (int i = 0; i < 10; i++)
	{
		HSVG  hSvg = XSvg_LoadStringW(str3.c_str());
		list_svg.push_back(hSvg);
		XSvg_SetPosition(hSvg, left + i * 50, top);

		HXCGUI hAnimation = XAnima_Create(hSvg, 0);
		XAnimaGroup_AddItem(hGroup, hAnimation);

		XAnima_Delay(hAnimation, i * 200);
		XAnima_Scale(hAnimation, 1000, 1.0f, 2.0f, 1, 0, TRUE);
	}

#endif

#if 10  //一排小球上下波浪
	left = 150;
	top = 200;
	for (int i = 0; i < 10; i++)
	{
		HSVG  hSvg = XSvg_LoadStringW(str3.c_str());
		list_svg.push_back(hSvg);
		int x = left + i * 35;
		XSvg_SetPosition(hSvg, x, top);

		HXCGUI hAnimation = XAnima_Create(hSvg, 0);
		XAnima_Run(hAnimation, hWindow);
		list_animation.push_back(hAnimation);

		XAnimaItem_EnableCompleteRelease(XAnima_Delay(hAnimation, i * 100), TRUE);
		XAnima_Move(hAnimation, 1200, x, top +100, 1, 0/*animation_cubic | ease_flag_inOut*/, TRUE);
	}
#endif

#if 1  //一排小球上下波浪
	left = 550;
	for (int i = 0; i < 10; i++)
	{
		HSVG  hSvg = XSvg_LoadStringW(str3.c_str());
		list_svg.push_back(hSvg);
		int x = left + i * 35;
		XSvg_SetPosition(hSvg, x, top);

		HXCGUI hAnimation = XAnima_Create(hSvg, 0);
		XAnima_Run(hAnimation, hWindow);
		list_animation.push_back(hAnimation);

		XAnimaItem_EnableCompleteRelease(XAnima_Delay(hAnimation, i * 150), TRUE);
		XAnima_Move(hAnimation, 1000, x, top + 50, 1, ease_flag_sine | ease_flag_inOut, TRUE);
	}
#endif


#if 1  //一排小球跳动
	left = 150;
	top = 350;
	for (int i = 0; i < 10; i++)
	{
		HSVG  hSvg = XSvg_LoadStringW(str3.c_str());
		list_svg.push_back(hSvg);
		int x = left + i * 35;
		XSvg_SetPosition(hSvg, x, top);

		HXCGUI hAnimation = XAnima_Create(hSvg, 0);
		XAnima_Run(hAnimation, hWindow);
		list_animation.push_back(hAnimation);

		XAnimaItem_EnableCompleteRelease(XAnima_Delay(hAnimation, i * 200), TRUE);
		XAnima_Move(hAnimation, 500, x, top + 50, 1, ease_flag_quint | ease_flag_out, TRUE);
		XAnima_Delay(hAnimation, 1700);
	}
#endif

#if 1  //一排小球移动
	std::wstring  str4 = LR"(<svg x="0" y="0" width="15" height="15" viewBox="0 0 100 100"><circle cx="50" cy="50" r="50" fill="#f00" /></svg>)";
	left = 220;
	top = 600;
	for (int i = 5; i >=0; i--)
	{
		HSVG  hSvg = XSvg_LoadStringW(str4.c_str());
		list_svg.push_back(hSvg);
		XSvg_SetPosition(hSvg, 100-(i* 25), top);
		XSvg_SetAlpha(hSvg, 0);

		HXCGUI hAnimation = XAnima_Create(hSvg, 0);
		{
			XAnima_Run(hAnimation, hWindow);
			list_animation.push_back(hAnimation);

			XAnimaItem_EnableCompleteRelease(XAnima_Delay(hAnimation, i * 100), TRUE);
			XAnima_Move(hAnimation, 2000, 550 - (i * 25), top, 1, ease_flag_quad | ease_flag_out, FALSE);
			XAnima_Move(hAnimation, 2000, 900 - (i* 25), top, 1, ease_flag_quad | ease_flag_in, FALSE);
			XAnima_Move(hAnimation, 0, 100-(i* 25), top, 1);
			XAnima_Delay(hAnimation, 500);
		}
		hAnimation = XAnima_Create(hSvg, 0);
		{
			XAnima_Run(hAnimation, hWindow);
			list_animation.push_back(hAnimation);

			XAnimaItem_EnableCompleteRelease( XAnima_Delay(hAnimation, i * 100), TRUE);
			XAnima_AlphaEx(hAnimation, 2000, 0, 255, 1, ease_flag_quad | ease_flag_out, FALSE);
			XAnima_AlphaEx(hAnimation, 2000, 255, 0, 1, ease_flag_quad | ease_flag_in, FALSE);
			XAnima_Delay(hAnimation, 500);
		}
	}
#endif
	XWnd_Redraw(hWindow);
	return 0;
}

//旋转
int CALLBACK OnBtnClick12(BOOL* pbHandled)
{
	ReleaseAnimation();
	HSVG hSvg = NULL;
	HXCGUI  hAnimation = NULL;

	int left = 120;
	int top = 100;

#if 10   //移动 360度旋转
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);

	XSvg_SetPosition(hSvg, left, top);
	XSvg_SetRotateAngle(hSvg, 0);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);
	XAnima_Rotate(hAnimation, 1700, 360, 1, 0);
	//XAnima_Rotate(hAnimation, 0, 0, 1, 0);
	XAnima_Run(hAnimation, hWindow);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);
	XAnima_Move(hAnimation, 3000, left + 500, top, 1, 0, TRUE);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10   //移动 往返旋转
	top = 350;
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	XSvg_SetRotateAngle(hSvg, -45);
	XSvg_SetUserFillColor(hSvg, RGBA(255, 0, 0, 255), TRUE);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);
	XAnima_Rotate(hAnimation, 1500, 45, 1, ease_flag_quad | ease_flag_in);
	XAnima_Rotate(hAnimation, 1500, -45, 1, ease_flag_quad | ease_flag_in);
	XAnima_Run(hAnimation, hWindow);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);
	XAnima_Move(hAnimation, 3000, left+500, top, 1, 0, TRUE);
	XAnima_Run(hAnimation, hWindow);
#endif
	return 0;
}

//旋转 摇摆
int CALLBACK OnBtnClick13(BOOL* pbHandled)
{
	ReleaseAnimation();
	HSVG hSvg = NULL;
	HXCGUI  hAnimation = NULL;
	HXCGUI  hRotate = NULL;

	int left = 130;
	int top = 80;

#if 10  //自身 摇摆 往返
	left = 120;
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	XSvg_SetRotateAngle(hSvg, -45);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);
	XAnima_Rotate(hAnimation, 1000, 45, 1, 0, TRUE);
	//XAnimaRotate_SetCenter(, -50,-50, TRUE);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10  //自身 旋转
	left = 500;
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);

	XAnima_Rotate(hAnimation, 1000, 360, 1, ease_flag_expo | ease_flag_in, FALSE);
	XAnima_Rotate(hAnimation, 0, 0, 1, 0, FALSE);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10  //两个叠加 悬挂摆动
	left =300;
	top = 250;
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	XSvg_SetRotateAngle(hSvg, 45);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);

	hRotate = XAnima_Rotate(hAnimation, 3000, 100, 1, ease_flag_quad | ease_flag_inOut /* ease_flag_expo | ease_flag_in*/, TRUE);
	XAnimaRotate_SetCenter(hRotate, left + 10, top + 50, FALSE);
	XAnima_Run(hAnimation, hWindow);

	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	XSvg_SetRotateAngle(hSvg, 45);
	XSvg_SetUserFillColor(hSvg, RGBA(255, 0, 0, 255), TRUE);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);

	hRotate = XAnima_Rotate(hAnimation, 3000, 100, 1, ease_flag_cubic | ease_flag_inOut, TRUE);
	XAnimaRotate_SetCenter(hRotate, left + 10, top + 50, FALSE);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10  //砍东西效果
	left =500;
	top = 400;
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	XSvg_SetRotateAngle(hSvg, -45);
	XSvg_SetUserFillColor(hSvg, RGBA(255, 0, 0, 255), TRUE);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);

	hRotate = XAnima_Rotate(hAnimation, 1500, 0, 1, ease_flag_expo | ease_flag_in, TRUE);
	XAnimaRotate_SetCenter(hRotate, left, top, FALSE);
	XAnima_Run(hAnimation, hWindow);
#endif
	return 0;
}
//旋转 移动 缩放
int CALLBACK OnBtnClick14(BOOL* pbHandled)
{
	ReleaseAnimation();
	HSVG hSvg = NULL;
	HXCGUI  hAnimation = NULL;
	HXCGUI  hRotate = NULL;

	int left = 130;
	int top = 50;

#if 10   //移动 360度旋转
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	XSvg_SetSize(hSvg, 50, 50);
	XSvg_SetUserFillColor(hSvg, RGBA(255, 0, 0, 255), TRUE);
	XSvg_SetPosition(hSvg, left, top);
	XSvg_SetRotateAngle(hSvg, 0);

	HXCGUI hGroup = XAnimaGroup_Create();
	list_animation.push_back(hGroup);

	//旋转
	hAnimation = XAnima_Create(hSvg, 0);
	XAnimaGroup_AddItem(hGroup, hAnimation);
	XAnima_Rotate(hAnimation, 600, 360, 4, 0,FALSE);

	//缩放
	hAnimation = XAnima_Create(hSvg, 0);
	XAnimaGroup_AddItem(hGroup, hAnimation);
	XAnima_Scale(hAnimation, 2400, 7.0, 7.0, 1, 0, FALSE);
	XAnima_Delay(hAnimation, 1000);
	XAnima_Scale(hAnimation, 1000, 1.0/7.0f, 1.0/7.0f, 1, 0, FALSE);
	
	//移动
	hAnimation = XAnima_Create(hSvg, 0);
	XAnimaGroup_AddItem(hGroup, hAnimation);
	XAnima_Move(hAnimation, 2400, left + 500, top+300, 1, 0, FALSE);
	XAnima_Delay(hAnimation, 1000);
	XAnima_Move(hAnimation, 1000, left, top, 1, 0, FALSE);
	
	XAnima_Run(hGroup, hWindow);
#endif
	return 0;
}

//旋转 开合效果
int CALLBACK OnBtnClick15(BOOL* pbHandled)
{
	ReleaseAnimation();
	HSVG hSvg = NULL;
	HXCGUI  hAnimation = NULL;
	HXCGUI  hRotate = NULL;

	int left = 150;
	int top = 80;
	int height=0;
	int width = 0;

#if 10  //砍东西效果
	top = 200;
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	height = XSvg_GetHeight(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	XSvg_SetRotateAngle(hSvg, -45);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);

	hRotate = XAnima_Rotate(hAnimation, 2000, 0, 1, ease_flag_bounce | ease_flag_out, TRUE);
	XAnimaRotate_SetCenter(hRotate, left, top+ height/2, FALSE);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10  //砍东西效果
	top = 300;
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	height = XSvg_GetHeight(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	XSvg_SetRotateAngle(hSvg, 45);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);

	hRotate = XAnima_Rotate(hAnimation, 2000, 0, 1, ease_flag_bounce | ease_flag_out, TRUE);
	XAnimaRotate_SetCenter(hRotate, left, top+ height/2, FALSE);
	XAnima_Run(hAnimation, hWindow);
#endif

	//----------------------------------------
#if 10  //砍东西效果
	left = 500;
	top = 200;
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	width = XSvg_GetWidth(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	XSvg_SetRotateAngle(hSvg, 45);
	XSvg_SetUserFillColor(hSvg, RGBA(255, 0, 0, 255), TRUE);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);

	hRotate = XAnima_Rotate(hAnimation, 2000, 0, 1, ease_flag_bounce | ease_flag_out, TRUE);
	XAnimaRotate_SetCenter(hRotate, left+ width, top + height / 2, FALSE);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10  //砍东西效果
	top = 300;
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	width = XSvg_GetWidth(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	XSvg_SetRotateAngle(hSvg, -45);
	XSvg_SetUserFillColor(hSvg, RGBA(255, 0, 0, 255), TRUE);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);

	hRotate = XAnima_Rotate(hAnimation, 2000, 0, 1, ease_flag_bounce | ease_flag_out, TRUE);
	XAnimaRotate_SetCenter(hRotate, left+ width, top + height / 2, FALSE);
	XAnima_Run(hAnimation, hWindow);
#endif
	return 0;
}

//颜色渐变
int CALLBACK OnBtnClick16(BOOL* pbHandled)
{
	ReleaseAnimation();
	HSVG hSvg = NULL;
	HXCGUI  hAnimation = NULL;

	int left = 150;
	int top = 50;
#if 10
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	XSvg_SetUserFillColor(hSvg, RGBA(255, 0, 0, 255), TRUE);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);

	XAnima_Color(hAnimation, 1500, RGBA(0, 0, 255, 255), 1,0, TRUE);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10
	top = 225;
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	XSvg_SetUserFillColor(hSvg, RGBA(0, 255, 0, 255), TRUE);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);

	XAnima_Color(hAnimation, 1500, RGBA(255, 0, 0, 255), 1, 0, TRUE);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10
	top = 400;
	hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	XSvg_SetUserFillColor(hSvg, RGBA(255, 255, 0, 255), TRUE);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);

	XAnima_Color(hAnimation, 1500, RGBA(0, 0, 255, 255), 1, 0, TRUE);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10
	std::wstring  str = LR"(<svg viewBox="0 0 200 200"><circle cx="100" cy="100" r="100" fill="#ff0" /></svg>)";
	hSvg = XSvg_LoadStringW(str.c_str());
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, 500, 300);
	XSvg_SetUserFillColor(hSvg, RGBA(255, 255, 0, 255), TRUE);

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);

	XAnima_Color(hAnimation, 1500, RGBA(0, 255, 255, 255), 1, 0, TRUE);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10
	HFONTX hFontx = XFont_CreateEx(L"微软雅黑", 36, fontStyle_bold);
	HXCGUI hShapeText = XShapeText_Create(500, 100, 200, 50, L"炫彩界面库", hWindow);
	list_xcgui.push_back(hShapeText);
	XShapeText_SetFont(hShapeText, hFontx);
	XShapeText_SetTextColor(hShapeText, RGBA(255, 0, 0, 255));

	hAnimation = XAnima_Create(hShapeText, 0);
	list_animation.push_back(hAnimation);

	XAnima_Color(hAnimation, 1500, RGBA(0, 0, 255, 255), 1, 0, TRUE);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10
	hShapeText = XShapeText_Create(500, 200, 100, 20, L"炫彩界面库", hWindow);
	list_xcgui.push_back(hShapeText);

	hAnimation = XAnima_Create(hShapeText, 0);
	list_animation.push_back(hAnimation);

	XAnima_Color(hAnimation, 1500, RGBA(0, 255, 0, 255), 1, 0, TRUE);
	XAnima_Run(hAnimation, hWindow);
#endif

	return 0;
}

int CALLBACK OnBtnClick17(BOOL* pbHandled)
{
	ReleaseAnimation();
	HSVG hSvg = NULL;
	HXCGUI  hAnimation = NULL;
	HXCGUI  hScale = NULL;
	int left = 150;
	int top = 50;
#if 10
	hSvg = XSvg_LoadFile(L"svg\\查验.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	list_xcgui.push_back(XShapeText_Create(left, top + 65, 150, 20, L"position_flag_leftTop", hWindow));

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);
	hScale = XAnima_Scale(hAnimation, 3000, 0.5, 0.5, 1, 0, TRUE);
	XAnimaScale_SetPosition(hScale, position_flag_leftTop);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10
	top += 150;
	hSvg = XSvg_LoadFile(L"svg\\查验.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	list_xcgui.push_back(XShapeText_Create(left, top+65, 150, 20, L"position_flag_left", hWindow));

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);
	hScale = XAnima_Scale(hAnimation, 3000, 0.5, 0.5, 1, 0, TRUE);
	XAnimaScale_SetPosition(hScale, position_flag_left);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10
	top += 150;
	hSvg = XSvg_LoadFile(L"svg\\查验.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	list_xcgui.push_back(XShapeText_Create(left, top + 65, 150, 20, L"position_flag_leftBottom", hWindow));

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);
	hScale = XAnima_Scale(hAnimation, 3000, 0.5, 0.5, 1, 0, TRUE);
	XAnimaScale_SetPosition(hScale, position_flag_leftBottom);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10
	top = 50;
	left += 150;
	hSvg = XSvg_LoadFile(L"svg\\查验.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	list_xcgui.push_back(XShapeText_Create(left, top + 65, 150, 20, L"position_flag_top", hWindow));

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);
	hScale = XAnima_Scale(hAnimation, 3000, 0.5, 0.5, 1, 0, TRUE);
	XAnimaScale_SetPosition(hScale, position_flag_top);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10
	top += 150;
	hSvg = XSvg_LoadFile(L"svg\\查验.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	list_xcgui.push_back(XShapeText_Create(left, top + 65, 150, 20, L"position_flag_center", hWindow));

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);
	hScale = XAnima_Scale(hAnimation, 3000, 0.5, 0.5, 1, 0, TRUE);
	XAnimaScale_SetPosition(hScale, position_flag_center);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10
	top += 150;
	hSvg = XSvg_LoadFile(L"svg\\查验.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	list_xcgui.push_back(XShapeText_Create(left, top + 65, 150, 20, L"position_flag_bottom", hWindow));

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);
	hScale = XAnima_Scale(hAnimation, 3000, 0.5, 0.5, 1, 0, TRUE);
	XAnimaScale_SetPosition(hScale, position_flag_bottom);
	XAnima_Run(hAnimation, hWindow);
#endif

	left += 150;
	top = 50;
#if 10
	hSvg = XSvg_LoadFile(L"svg\\查验.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	list_xcgui.push_back(XShapeText_Create(left, top + 65, 150, 20, L"position_flag_rightTop", hWindow));

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);
	hScale = XAnima_Scale(hAnimation, 3000, 0.5, 0.5, 1, 0, TRUE);
	XAnimaScale_SetPosition(hScale, position_flag_rightTop);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10
	top += 150;
	hSvg = XSvg_LoadFile(L"svg\\查验.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	list_xcgui.push_back(XShapeText_Create(left, top + 65, 150, 20, L"position_flag_right", hWindow));

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);
	hScale= XAnima_Scale(hAnimation,3000, 0.5, 0.5, 1,0, TRUE);
	XAnimaScale_SetPosition(hScale, position_flag_right);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10
	top += 150;
	hSvg = XSvg_LoadFile(L"svg\\查验.svg");
	list_svg.push_back(hSvg);
	XSvg_SetPosition(hSvg, left, top);
	list_xcgui.push_back(XShapeText_Create(left, top + 65, 150, 20, L"position_flag_rightBottom", hWindow));

	hAnimation = XAnima_Create(hSvg, 0);
	list_animation.push_back(hAnimation);
	hScale = XAnima_Scale(hAnimation, 3000, 0.5, 0.5, 1, 0, TRUE);
	XAnimaScale_SetPosition(hScale, position_flag_rightBottom);
	XAnima_Run(hAnimation, hWindow);
#endif
	return 0;
}

int CALLBACK OnMouseStay18(HELE hButton, BOOL* pbHandled)
{
	//释放当前按钮对象关联的动画
	for (int i = list_animation.size()-1; i >= 0; i--)
	{
		if (hButton == XAnima_GetObjectUI(list_animation[i]))
		{
			XAnima_Release(list_animation[i],FALSE);
			list_animation.erase(list_animation.begin() + i);
		}
	}

	HXCGUI hAnimation = XAnima_Create(hButton, 1);
	list_animation.push_back(hAnimation);
	//HXCGUI hScale = XAnima_Scale(hAnimation, 500, 2.0, 1.0, 1, ease_flag_quad | ease_flag_out, FALSE);
	HXCGUI hScale = XAnima_ScaleSize(hAnimation, 400, 250, 40, 1, ease_flag_quad | ease_flag_out, FALSE);
	XAnimaScale_SetPosition(hScale, position_flag_left);
	XAnima_Run(hAnimation, hWindow);
	return 0;
}

int CALLBACK OnMouseLeave18(HELE hButton, HELE hEleStay, BOOL* pbHandled)
{
	//释放当前按钮对象关联的动画
	for (int i = list_animation.size() - 1; i >= 0; i--)
	{
		if (hButton == XAnima_GetObjectUI(list_animation[i]))
		{
			XAnima_Release(list_animation[i], FALSE);
			list_animation.erase(list_animation.begin() + i);
		}
	}

	HXCGUI hAnimation = XAnima_Create(hButton, 1);
	list_animation.push_back(hAnimation);
	//HXCGUI hScale = XAnima_Scale(hAnimation, 500, 0.5, 1.0, 1, ease_flag_quad | ease_flag_in, FALSE);
	HXCGUI hScale = XAnima_ScaleSize(hAnimation, 400, 150, 40, 1, ease_flag_quad | ease_flag_in, FALSE);
	XAnimaScale_SetPosition(hScale, position_flag_left);
	XAnima_Run(hAnimation, hWindow);
	return 0;
}

int CALLBACK OnBtnClick18(BOOL* pbHandled)
{
	ReleaseAnimation();
	int left = 150;
	int top = 50;
	HFONTX  hFontx = XFont_Create(10);
	for (int i = 0; i<5;i++)
	{
		HELE hButton = XBtn_Create(left, top, 150, 40, L"鼠标 停留 离开", hWindow);
		list_xcgui.push_back(hButton);
		XEle_SetFont(hButton, hFontx);
		XEle_SetTextColor(hButton, RGBA(255, 255, 255, 255));
		XBkM_SetBkInfo(XEle_GetBkManager(hButton), L"{99:1.9.9;98:16(0)32(1)64(2);5:2(15)20(1)21(3)26(1)22(-25024)23(255)9(4,4,4,4);5:2(15)20(1)21(3)26(1)22(-20122)23(255)9(4,4,4,4);5:2(15)20(1)21(3)26(1)22(-1667526)23(255)9(4,4,4,4);}");
		XEle_RegEventC1(hButton, XE_MOUSESTAY, OnMouseStay18);
		XEle_RegEventC1(hButton, XE_MOUSELEAVE, OnMouseLeave18);
		top += 60;
	}
	XWnd_Redraw(hWindow);
	return 0;
}

//窗口缓动 从上往下
int CALLBACK OnBtnClick19_1(BOOL* pbHandled)
{
	RECT rcWindow;
	XWnd_GetRect(hWindow ,&rcWindow);
	int left = rcWindow.left+ (rcWindow.right - rcWindow.left-400) / 2;
	int top = rcWindow.top + (rcWindow.bottom - rcWindow.top-300) / 2;

	HWINDOW hModal = XModalWnd_Create(400, 300, L"窗口缓动", XWnd_GetHWND(hWindow), window_style_modal);

	HXCGUI hAnimation = XAnima_Create(hModal, 1);
	list_animation.push_back(hAnimation);
	XAnima_MoveEx(hAnimation, 1000, left, 20, left, top, 1, ease_flag_bounce | ease_flag_out, FALSE);
	XAnima_Run(hAnimation, hModal);

	XModalWnd_DoModal(hModal);
	return 0;
}

//窗口缓动 从左往右
int CALLBACK OnBtnClick19_2(BOOL* pbHandled)
{
	RECT rcWindow;
	XWnd_GetRect(hWindow, &rcWindow);
	int left = rcWindow.left + (rcWindow.right - rcWindow.left - 400) / 2;
	int top = rcWindow.top + (rcWindow.bottom - rcWindow.top - 300) / 2;

	HWINDOW hModal = XModalWnd_Create(400, 300, L"窗口缓动", XWnd_GetHWND(hWindow), window_style_modal);

	HXCGUI hAnimation = XAnima_Create(hModal, 1);
	list_animation.push_back(hAnimation);
	XAnima_MoveEx(hAnimation, 1000, 20, top, left, top, 1, ease_flag_bounce | ease_flag_out, FALSE);
	XAnima_Run(hAnimation, hModal);

	XModalWnd_DoModal(hModal);
	return 0;
}

//窗口缩放
int CALLBACK OnBtnClick19_3(BOOL* pbHandled)
{
	HWINDOW hModal = XModalWnd_Create(400, 300, L"窗口缩放", XWnd_GetHWND(hWindow), window_style_modal);

	HXCGUI hAnimation = XAnima_Create(hModal, 1);
	list_animation.push_back(hAnimation);
	//XAnima_Delay(hAnimation, 500);
	XAnima_ScaleSize(hAnimation, 1000, 500, 400, 1, ease_flag_quad | ease_flag_in, TRUE);
	XAnima_Run(hAnimation, hModal);

	XModalWnd_DoModal(hModal);
	return 0;
}
//窗口缩放
int CALLBACK OnBtnClick19_4(BOOL* pbHandled)
{
	HWINDOW hModal = XModalWnd_Create(400*0.5, 300*0.5, L"窗口缩放", XWnd_GetHWND(hWindow), window_style_modal);

	HXCGUI hAnimation = XAnima_Create(hModal, 1);
	list_animation.push_back(hAnimation);
	//XAnima_Delay(hAnimation, 100);
	XAnima_ScaleSize(hAnimation, 1000, 400, 300, 1, ease_flag_back | ease_flag_out, FALSE);
	XAnima_Run(hAnimation, hModal);

	XModalWnd_DoModal(hModal);
	return 0;
}
//窗口透明
int CALLBACK OnBtnClick19_5(BOOL* pbHandled)
{
	HWINDOW hModal = XModalWnd_Create(400, 300, L"窗口缩放", XWnd_GetHWND(hWindow), window_style_modal);
	XWnd_SetTransparentType(hModal, window_transparent_shadow);
	XWnd_SetTransparentAlpha(hModal, 1);

 	HXCGUI hAnimation = XAnima_Create(hModal, 1);
 	list_animation.push_back(hAnimation);
 	XAnima_Delay(hAnimation, 100);
	XAnima_Alpha(hAnimation, 1000, 255, 1, 0, FALSE);
 	XAnima_Run(hAnimation, hModal);

	XModalWnd_DoModal(hModal);
	return 0;
}

HELE  hEle_mask = NULL; //遮罩
int CALLBACK OnWndDestroy20(BOOL* pbHandled)
{
	if (hEle_mask)
	{
		XEle_Destroy(hEle_mask);
		hEle_mask = NULL;
		XWnd_Redraw(hWindow);
	}
	return 0;
}

//遮盖层 内嵌子弹窗
int CALLBACK OnBtnClick20_1(BOOL* pbHandled)
{
	RECT rect;
	XWnd_GetBodyRect(hWindow, &rect);

	XC_EnableDPI(FALSE);
	hEle_mask = XEle_Create(rect.left, rect.top, rect.right- rect.left, rect.bottom- rect.top, hWindow);
	XC_EnableDPI(TRUE);

	XEle_AddBkFill(hEle_mask, window_state_flag_leave, RGBA(0,0,0, 200));

	HWINDOW hWindow_ = XWnd_CreateEx(0, WS_CHILD, NULL, 0, 0, 300, 200, L"123", XWnd_GetHWND(hWindow));

	XWnd_Show(hWindow_, TRUE);
	XWnd_RegEventC(hWindow_, WM_DESTROY, OnWndDestroy20);
	XWnd_Redraw(hWindow);
	return 0;
}

//遮盖层 内嵌消息框
int CALLBACK OnBtnClick20_2(BOOL* pbHandled)
{
	RECT rect;
	XWnd_GetBodyRect(hWindow, &rect);
	XC_EnableDPI(FALSE);
	hEle_mask = XEle_Create(rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top, hWindow);
	XC_EnableDPI(TRUE);

	XEle_AddBkFill(hEle_mask, window_state_flag_leave, RGBA(0, 0, 0, 200));

	HWINDOW hWindow_ = XMsg_CreateEx(0, WS_CHILD, NULL, L"炫彩界面库", L"标题", messageBox_flag_ok | messageBox_flag_icon_info, XWnd_GetHWND(hWindow));
	XWnd_Show(hWindow_, TRUE);
	XWnd_RegEventC(hWindow_, WM_DESTROY, OnWndDestroy20);
	XWnd_Redraw(hWindow);
	return 0;
}

//遮盖层 消息框
int CALLBACK OnBtnClick20_3(BOOL* pbHandled)
{
	RECT rect;
	XWnd_GetBodyRect(hWindow, &rect);
	XC_EnableDPI(FALSE);
	hEle_mask = XEle_Create(rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top, hWindow);
	XC_EnableDPI(TRUE);

	XEle_AddBkFill(hEle_mask, window_state_flag_leave, RGBA(0, 0, 0, 200));

	HWINDOW hWindow_ = XMsg_Create(L"炫彩界面库", L"标题", messageBox_flag_ok | messageBox_flag_icon_info, XWnd_GetHWND(hWindow));
	XWnd_Show(hWindow_, TRUE);
	XWnd_RegEventC(hWindow_, WM_DESTROY, OnWndDestroy20);
	XWnd_Redraw(hWindow);
	return 0;
}

HSVG hSvg1 = NULL;
HSVG hSvg2 = NULL;
int CALLBACK OnDraw19(HELE hEle, HDRAW hDraw, BOOL* pbHandled)
{
	*pbHandled = TRUE;
	XEle_DrawEle(hEle, hDraw);

	XDraw_DrawSvgSrc(hDraw, hSvg1);
	XDraw_DrawSvgSrc(hDraw, hSvg2);
	return 0;
}

int CALLBACK OnLButtonDown19(HELE hEle, UINT nFlags, POINT* pPt, BOOL* pbHandled)
{
	*pbHandled = TRUE;
	XEle_Destroy(hEle);

	if (hSvg1) {
		XSvg_Destroy(hSvg1);
		hSvg1 = NULL;
	}
	if (hSvg2) {
		XSvg_Destroy(hSvg2);
		hSvg2 = NULL;
	}
	XWnd_Redraw(hWindow);
	return 0;
}

//遮盖层 等待
int CALLBACK OnBtnClick20_4(BOOL* pbHandled)
{
	std::wstring  str = LR"(<svg x="0" y="0" width="25" height="25" viewBox="0 0 100 100"><circle cx="50" cy="50" r="50" fill="#ee6362" /></svg>)";
	std::wstring  str2 = LR"(<svg x="0" y="0" width="25" height="25" viewBox="0 0 100 100"><circle cx="50" cy="50" r="50" fill="#2cb0b2" /></svg>)";
	
	hSvg1 = XSvg_LoadStringW(str.c_str());
	hSvg2 = XSvg_LoadStringW(str2.c_str());
	//list_xcgui.push_back(hSvg1);
	//list_xcgui.push_back(hSvg2);

	RECT rect;
	XWnd_GetBodyRect(hWindow, &rect);
	XC_EnableDPI(FALSE);
	hEle_mask = XEle_Create(rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top, hWindow);
	XC_EnableDPI(TRUE);

	XEle_AddBkFill(hEle_mask, window_state_flag_leave, RGBA(0, 0, 0, 200));
	XEle_RegEventC1(hEle_mask, XE_PAINT, OnDraw19);
	XEle_RegEventC1(hEle_mask, XE_LBUTTONDOWN, OnLButtonDown19);

	int left = rect .left+( rect.right- rect.left - 100)/2;
	int top = (rect.bottom- rect.top)/2 - 50;
	XShapeText_SetTextColor(XShapeText_Create(left, top-25, 100, 20, L"正在加载...", hEle_mask), RGBA(255,255,255,255));

#if 10 //两个球型交替移动

	XSvg_SetPosition(hSvg1, left, top);

	HXCGUI hGroup = XAnimaGroup_Create(0);
	list_animation.push_back(hGroup);
	XAnima_Run(hGroup, hWindow);

	HXCGUI hAnimation = XAnima_Create(hSvg1, 1);
	XAnimaGroup_AddItem(hGroup, hAnimation);
	XAnima_Move(hAnimation, 1000, left + 50, top, 1, ease_flag_sine | ease_flag_inOut, FALSE);
	XAnima_Move(hAnimation, 1000, left, top, 1, ease_flag_sine | ease_flag_inOut, FALSE);

	XSvg_SetPosition(hSvg2, left + 50, top);

	hGroup = XAnimaGroup_Create(0);
	list_animation.push_back(hGroup);
	XAnima_Run(hGroup, hWindow);

	hAnimation = XAnima_Create(hSvg2, 1);
	XAnimaGroup_AddItem(hGroup, hAnimation);
	XAnima_Move(hAnimation, 1000, left, top, 1, ease_flag_sine | ease_flag_inOut, FALSE);
	XAnima_Move(hAnimation, 1000, left + 50, top, 1, ease_flag_sine | ease_flag_inOut, FALSE);
#endif
	return 0;
}

int CALLBACK OnBtnClick19_6_5_close(HELE hEle, BOOL* pbHandled)
{
	*pbHandled = TRUE;
	XEle_Destroy((HELE)XEle_GetUserData(hEle));
	XWnd_Redraw(hWindow);
	return 0;
}

//遮盖层 基础元素弹窗
int CALLBACK OnBtnClick20_5(BOOL* pbHandled)
{
	RECT rect;
	XWnd_GetBodyRect(hWindow, &rect);
	XC_EnableDPI(FALSE);
	hEle_mask = XEle_Create(rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top, hWindow);
	XC_EnableDPI(TRUE);
	XEle_AddBkFill(hEle_mask, window_state_flag_leave, RGBA(0, 0, 0, 200));
	XEle_RegEventC1(hEle_mask, XE_PAINT, OnDraw19);
	XEle_RegEventC1(hEle_mask, XE_LBUTTONDOWN, OnLButtonDown19);

	int width = 350;
	int height = 170;
	int left = rect.left + (rect.right - rect.left - width) / 2;
	int top = (rect.bottom - rect.top) / 2 - height;

	HELE hEleDlg = XEle_Create(left, 10, width, height, hEle_mask);
	XWidget_Show(hEleDlg, FALSE);
	XEle_EnableBkTransparent(hEleDlg, TRUE);
	XBkM_SetBkInfo(XEle_GetBkManager(hEleDlg), L"{99:1.9.9;98:1(0);5:2(15)20(1)21(3)26(1)22(-1)23(255)9(10,10,10,10);}");
	XShapeText_SetTextColor(XShapeText_Create(50, 5, 220, 20, L"炫彩界面库-仅作功能演示,没有美化处理", hEleDlg), RGBA(80, 80, 80, 255));
	
	HELE hBtnClose = XBtn_Create(width -40, 2, 30, 22, L"", hEleDlg);
	XBkM_SetBkInfo(XEle_GetBkManager(hBtnClose), L"{99:1.9.9;98:16(0,1)32(0,1)64(0,1);5:2(48)8(45.00)3(2,10,2,10)20(1)21(3)26(0)22(-8355712)23(255);5:2(48)8(45.00)3(10,2,100,100)20(1)21(3)26(0)22(-8355712)23(255);}");

	XShapeText_SetTextColor(XShapeText_Create(20, 60, 200, 20, L"请输入内容(这是一个演示)", hEleDlg), RGBA(80, 80, 80, 255));
	
	std::wstring  strBkm = L"{99:1.9.9;98:16(0)32(1)64(1);5:2(15)20(1)21(3)26(0)22(-1)23(255)10(1)7(1)11(3)16(0)12(-3618616)13(255)9(5,5,5,5);5:2(15)20(1)21(3)26(0)22(-1)23(255)10(1)7(1)11(3)16(0)12(-17897)13(255)9(5,5,5,5);}";
	HELE  hEdit = XEdit_Create(20, 82, width -40, 26, hEleDlg);
	XEdit_SetDefaultText(hEdit, L"请输入内容...");
	XEle_SetBorderSize(hEdit, 10, 0, 10, 0);
	XBkM_SetBkInfo(XEle_GetBkManager(hEdit), strBkm.c_str());

	int left_ = 190;
	int top_ = height - 35;
	HELE hBtnOk = XBtn_Create(left_, top_, 60, 22, L"确定", hEleDlg); left_ += 80;
	HELE hBtnCancel = XBtn_Create(left_, top_, 60, 22, L"取消", hEleDlg);
	XBkM_SetBkInfo(XEle_GetBkManager(hBtnOk), strBkm.c_str());
	XBkM_SetBkInfo(XEle_GetBkManager(hBtnCancel), strBkm.c_str());

	XEle_SetUserData(hBtnOk, (vint)hEle_mask);
	XEle_SetUserData(hBtnClose, (vint)hEle_mask);
	XEle_SetUserData(hBtnCancel, (vint)hEle_mask);

	XEle_RegEventC1(hBtnOk, XE_BNCLICK, OnBtnClick19_6_5_close);
	XEle_RegEventC1(hBtnClose, XE_BNCLICK, OnBtnClick19_6_5_close);
	XEle_RegEventC1(hBtnCancel, XE_BNCLICK, OnBtnClick19_6_5_close);

	HXCGUI hAnimation = XAnima_Create(hEle_mask,1);
	list_animation.push_back(hAnimation);
	XAnima_AlphaEx(hAnimation, 500, 0, 255, 1, 0, FALSE);
	XAnima_Run(hAnimation, hEle_mask);

	hAnimation = XAnima_Create(hEleDlg, 1);
	list_animation.push_back(hAnimation);
	XAnima_Show(hAnimation, 500, TRUE);
	XAnima_Move(hAnimation, 500, left, top, 1, ease_flag_bounce | ease_flag_out, FALSE);
	XAnima_Run(hAnimation, hEle_mask);

	XWnd_Redraw(hWindow);
	return 0;
}

//窗口特效
int CALLBACK OnBtnClick19(BOOL* pbHandled)
{
	ReleaseAnimation();
	int top = 200;
	int left = 140;
	int width = 120;
	int height_btn = 35;
	int height = 34;

	HELE hButton = CreateButton(left, top, width, height_btn, L"窗口 从上往下"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick19_1);

	hButton = CreateButton(left, top, width, height_btn, L"窗口 从左往右"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick19_2);

	hButton = CreateButton(left, top, width, height_btn, L"窗口 缩放"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick19_3);
	
	hButton = CreateButton(left, top, width, height_btn, L"窗口 缩放2"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick19_4);
	
	hButton = CreateButton(left, top, width, height_btn, L"窗口 透明"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick19_5);

	XWnd_Redraw(hWindow);
	return 0;
}

//遮盖弹窗
int CALLBACK OnBtnClick20(BOOL* pbHandled)
{
	ReleaseAnimation();
	int top = 200;
	int left = 140;
	int width = 150;
	int height_btn = 35;
	int height = 34;

	HELE hButton = CreateButton(left, top, width, height_btn, L"遮盖层-内嵌子弹窗"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick20_1);

	hButton = CreateButton(left, top, width, height_btn, L"遮盖层-内嵌消息框"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick20_2);

	hButton = CreateButton(left, top, width, height_btn, L"遮盖层-消息框"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick20_3);

	hButton = CreateButton(left, top, width, height_btn, L"遮盖层-等待"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick20_4);

	hButton = CreateButton(left, top, width, height_btn, L"遮盖层-基础元素弹窗"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick20_5);

	XWnd_Redraw(hWindow);
	return 0;
}

int CALLBACK OnBtnClick21_1(BOOL* pbHandled)
{
	HSVG hSvg=XSvg_LoadFile(L"svg\\成功.svg");
	XSvg_SetSize(hSvg, 16, 16);

	XNotifyMsg_WindowPopup(hWindow, position_flag_top, L"成功", L"这是一条成功的提示消息", XImage_LoadSvg(hSvg), notifyMsg_skin_success);
	return 0;
}
int CALLBACK OnBtnClick21_2(BOOL* pbHandled)
{
	HSVG hSvg = XSvg_LoadFile(L"svg\\警告.svg");
	XSvg_SetSize(hSvg, 16, 16);

	XNotifyMsg_WindowPopup(hWindow, position_flag_top, L"警告", L"这是一条警告的提示消息", XImage_LoadSvg(hSvg), notifyMsg_skin_warning);
	return 0;
}
int CALLBACK OnBtnClick21_3(BOOL* pbHandled)
{
	HSVG hSvg = XSvg_LoadFile(L"svg\\消息.svg");
	XSvg_SetSize(hSvg, 16, 16);

	XNotifyMsg_WindowPopup(hWindow, position_flag_top, L"消息", L"这是一条消息的提示消息", XImage_LoadSvg(hSvg), notifyMsg_skin_message);
	return 0;
}
int CALLBACK OnBtnClick21_4(BOOL* pbHandled)
{
	HSVG hSvg = XSvg_LoadFile(L"svg\\错误.svg");
	XSvg_SetSize(hSvg, 16, 16);

	XNotifyMsg_WindowPopup(hWindow, position_flag_top, L"错误", L"这是一条错误的提示消息", XImage_LoadSvg(hSvg), notifyMsg_skin_error);
	return 0;
}
int CALLBACK OnBtnClick21_5(BOOL* pbHandled)
{
	HSVG hSvg = XSvg_LoadFile(L"svg\\成功.svg");
	XSvg_SetSize(hSvg, 16, 16);

	XNotifyMsg_WindowPopupEx(hWindow, position_flag_top, L"成功", L"这是一条成功的提示消息,没有关闭按钮", XImage_LoadSvg(hSvg), notifyMsg_skin_success, FALSE, TRUE);
	return 0;
}
int CALLBACK OnBtnClick21_6(BOOL* pbHandled)
{
	HSVG hSvg = XSvg_LoadFile(L"svg\\成功.svg");
	XSvg_SetSize(hSvg, 16, 16);

	XNotifyMsg_WindowPopupEx(hWindow, position_flag_top, L"成功", L"这是一条成功的提示消息,手动关闭,这是一个自动换行文本", XImage_LoadSvg(hSvg), notifyMsg_skin_no, TRUE, FALSE);
	return 0;
}
int CALLBACK OnBtnClick21_7(BOOL* pbHandled)
{
	HSVG hSvg = XSvg_LoadFile(L"svg\\成功.svg");
	XSvg_SetSize(hSvg, 16, 16);

	XNotifyMsg_WindowPopup(hWindow, position_flag_top, NULL, L"这是一条成功的提示消息,没有标题", XImage_LoadSvg(hSvg), notifyMsg_skin_success);
	return 0;
}

int CALLBACK OnBtnClick21_8(BOOL* pbHandled)
{
	HSVG hSvg = XSvg_LoadFile(L"svg\\成功.svg");
	XSvg_SetSize(hSvg, 16, 16);

	XNotifyMsg_WindowPopupEx(hWindow, position_flag_top, L"成功", L"这是一条成功的提示消息,\n自定义大小", XImage_LoadSvg(hSvg), notifyMsg_skin_success, TRUE,TRUE, 300,200);
	return 0;
}

int CALLBACK OnBtnClick21_right_1(BOOL* pbHandled)
{
	HSVG hSvg = XSvg_LoadFile(L"svg\\成功.svg");
	XSvg_SetSize(hSvg, 20, 20);

	XNotifyMsg_WindowPopupEx(hWindow, position_flag_right, L"成功", L"这是一条成功的提示消息", XImage_LoadSvg(hSvg), notifyMsg_skin_success);
	return 0;
}
int CALLBACK OnBtnClick21_right_2(BOOL* pbHandled)
{
	HSVG hSvg = XSvg_LoadFile(L"svg\\警告.svg");
	XSvg_SetSize(hSvg, 20, 20);

	XNotifyMsg_WindowPopupEx(hWindow, position_flag_right, L"警告", L"这是一条警告的提示消息", XImage_LoadSvg(hSvg), notifyMsg_skin_warning);
	return 0;
}
int CALLBACK OnBtnClick21_right_3(BOOL* pbHandled)
{
	HSVG hSvg = XSvg_LoadFile(L"svg\\消息.svg");
	XSvg_SetSize(hSvg, 20, 20);

	XNotifyMsg_WindowPopupEx(hWindow, position_flag_right, L"消息", L"这是一条消息的提示消息", XImage_LoadSvg(hSvg), notifyMsg_skin_message);
	return 0;
}
int CALLBACK OnBtnClick21_right_4(BOOL* pbHandled)
{
	HSVG hSvg = XSvg_LoadFile(L"svg\\错误.svg");
	XSvg_SetSize(hSvg, 20, 20);

	XNotifyMsg_WindowPopup(hWindow, position_flag_right, L"错误", L"这是一条错误的提示消息", XImage_LoadSvg(hSvg), notifyMsg_skin_error);
	return 0;
}
int CALLBACK OnBtnClick21_right_5(BOOL* pbHandled)
{
	HSVG hSvg = XSvg_LoadFile(L"svg\\成功.svg");
	XSvg_SetSize(hSvg, 20, 20);

	XNotifyMsg_WindowPopupEx(hWindow, position_flag_right, L"成功", L"这是一条成功的提示消息,没有关闭按钮", XImage_LoadSvg(hSvg), notifyMsg_skin_success,  FALSE, TRUE);
	return 0;
}
int CALLBACK OnBtnClick21_right_6(BOOL* pbHandled)
{
	HSVG hSvg = XSvg_LoadFile(L"svg\\成功.svg");
	XSvg_SetSize(hSvg, 20, 20);

	XNotifyMsg_WindowPopupEx(hWindow, position_flag_right, L"成功", L"这是一条成功的提示消息,手动关闭,这是一个自动换行文本", XImage_LoadSvg(hSvg), notifyMsg_skin_no, TRUE, FALSE);
	return 0;
}
int CALLBACK OnBtnClick21_right_7(BOOL* pbHandled)
{
	HSVG hSvg = XSvg_LoadFile(L"svg\\成功.svg");
	XSvg_SetSize(hSvg, 20, 20);

	XNotifyMsg_WindowPopupEx(hWindow, position_flag_right, NULL, L"这是一条成功的提示消息,没有标题", XImage_LoadSvg(hSvg), notifyMsg_skin_success);
	return 0;
}

//消息通知
int CALLBACK OnBtnClick21(BOOL* pbHandled)
{
	ReleaseAnimation();
	int top = 200;
	int left = 140;
	int width = 150;
	int height_btn = 35;
	int height = 34;
	//-----top------------
 	HELE hButton = CreateButton(left, top, width, height_btn, L"top-成功"); top += height;
 	list_xcgui.push_back(hButton);
 	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick21_1);

	hButton = CreateButton(left, top, width, height_btn, L"top-警告消息"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick21_2);

	hButton = CreateButton(left, top, width, height_btn, L"top-消息"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick21_3);

	hButton = CreateButton(left, top, width, height_btn, L"top-错误消息"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick21_4);

	hButton = CreateButton(left, top, width, height_btn, L"top-没有关闭按钮"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick21_5);

	hButton = CreateButton(left, top, width, height_btn, L"top-手动关闭消息"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick21_6);

	hButton = CreateButton(left, top, width, height_btn, L"top-不带标题"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick21_7);

	hButton = CreateButton(left, top, width, height_btn, L"top-自定义大小"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick21_8);

	//-----right------------
	left +=160;
	top = 200;
	hButton = CreateButton(left, top, width, height_btn, L"right-成功"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick21_right_1);

	hButton = CreateButton(left, top, width, height_btn, L"right-警告消息"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick21_right_2);

	hButton = CreateButton(left, top, width, height_btn, L"right-消息"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick21_right_3);

	hButton = CreateButton(left, top, width, height_btn, L"right-错误消息"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick21_right_4);

	hButton = CreateButton(left, top, width, height_btn, L"right-没有关闭按钮"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick21_right_5);

	hButton = CreateButton(left, top, width, height_btn, L"right-手动关闭消息"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick21_right_6);

	hButton = CreateButton(left, top, width, height_btn, L"right-不带标题"); top += height;
	list_xcgui.push_back(hButton);
	XEle_RegEventC(hButton, XE_BNCLICK, OnBtnClick21_right_7);

	XWnd_Redraw(hWindow);
	return 0;
}

HELE hSliderBar1 = NULL;
HELE hSliderBar2 = NULL;
HELE hSliderBar3 = NULL;
HELE hProgBar1 = NULL;
HELE hProgBar2 = NULL;
HELE hProgBar3 = NULL;
void CALLBACK OnAnimationItem_22(HXCGUI hAnimation, float pos)
{
	if (XC_IsHELE(hSliderBar1)) XSliderBar_SetPos(hSliderBar1, (int)((100.0f * pos)+0.5f));
	if (XC_IsHELE(hSliderBar2)) XSliderBar_SetPos(hSliderBar2, (int)((80.0f * pos) + 0.5f));
	if (XC_IsHELE(hSliderBar3)) XSliderBar_SetPos(hSliderBar3, (int)((50.0f * pos) + 0.5f));

	if(hProgBar1) XProgBar_SetPos(hProgBar1, (int)((100.0f * pos) + 0.5f));
	if(hProgBar2) XProgBar_SetPos(hProgBar2, (int)((80.0f * pos) + 0.5f));
	if(hProgBar3) XProgBar_SetPos(hProgBar3, (int)((50.0f * pos) + 0.5f));
}

//进度条
int CALLBACK OnBtnClick22(BOOL* pbHandled)
{
	ReleaseAnimation();

	int left = 150;
	int top = 100;
	int width = 500;
	std::wstring  strBackground = L"{99:1.9.9;98:16(0);5:2(37)3(0,8,0,0)20(1)21(3)26(1)22(-3618616)23(255)9(3,3,3,3);}";
#if 10 //滑动条
	hSliderBar1 = XSliderBar_Create(left, top, width, 20, hWindow); top += 50;
	hSliderBar2 = XSliderBar_Create(left, top, width, 20, hWindow); top += 50;
	hSliderBar3 = XSliderBar_Create(left, top, width, 20, hWindow); top += 50;
	list_xcgui.push_back(hSliderBar1);
	list_xcgui.push_back(hSliderBar2);
	list_xcgui.push_back(hSliderBar3);
	XEle_SetBkInfo(hSliderBar1, strBackground.c_str());
	XEle_SetBkInfo(hSliderBar2, strBackground.c_str());
	XEle_SetBkInfo(hSliderBar3, strBackground.c_str());
	XSliderBar_SetButtonWidth(hSliderBar1, 20);
	XSliderBar_SetButtonWidth(hSliderBar2, 20);
	XSliderBar_SetButtonWidth(hSliderBar3, 20);
	XEle_SetBkInfo(XSliderBar_GetButton(hSliderBar1), L"{99:1.9.9;98:16(0)32(0)64(0);6:2(15)20(1)21(3)26(1)22(-25024)23(255);}");
	XEle_SetBkInfo(XSliderBar_GetButton(hSliderBar2), L"{99:1.9.9;98:16(0)32(0)64(0);6:2(15)20(1)21(3)26(1)22(-25024)23(255);}");
	XEle_SetBkInfo(XSliderBar_GetButton(hSliderBar3), L"{99:1.9.9;98:16(0)32(0)64(0);6:2(15)20(1)21(3)26(0)22(-1)23(255)10(1)7(2)11(3)16(1)12(-25024)13(255);}");

	HIMAGE  hImage = XImage_LoadFile(L"image\\sliderBar.png");
	XImage_SetDrawTypeAdaptive(hImage, 5, 5, 5, 5);
	XSliderBar_SetImageLoad(hSliderBar1, hImage);
	XSliderBar_SetImageLoad(hSliderBar2, hImage);

	HXCGUI hAnimation= XAnima_Create(NULL, 0);
	list_animation.push_back(hAnimation);
	XAnimaItem_SetCallback(XAnima_DelayEx(hAnimation, 2000,1, ease_flag_quad | ease_flag_out, TRUE), OnAnimationItem_22);
	XAnima_Run(hAnimation, hWindow);
#endif

#if 10  //进度条
 	hProgBar1 = XProgBar_Create(left, top, width, 20, hWindow); top += 50;
 	hProgBar2 = XProgBar_Create(left, top, width, 20, hWindow); top += 50;
 	hProgBar3 = XProgBar_Create(left, top, width, 20, hWindow); top += 50;
	list_xcgui.push_back(hProgBar1);
	list_xcgui.push_back(hProgBar2);
	list_xcgui.push_back(hProgBar3);
	XEle_SetBkInfo(hProgBar1, L"{99:1.9.9;98:16(0);5:2(15)20(1)21(3)26(1)22(-3618616)23(255)9(10,10,10,10);}");
	XEle_SetBkInfo(hProgBar2, L"{99:1.9.9;98:16(0);5:2(15)20(1)21(3)26(1)22(-3618616)23(255)9(10,10,10,10);}");

 	hImage = XImage_LoadFile(L"image\\progressBar.png");
 	XImage_SetDrawTypeAdaptive(hImage, 10, 0, 10, 0);
 	XProgBar_SetImageLoad(hProgBar1, hImage);
 	XProgBar_SetImageLoad(hProgBar2, hImage);

	XEle_SetTextColor(hProgBar1, RGBA(255,255,255,255));
	XEle_SetTextColor(hProgBar2, RGBA(255, 255, 255, 255));
#endif
	//XEle_AddBkBorder()
	XWnd_Redraw(hWindow);
	return 0;
}

HXCGUI hTabBar_Background = NULL;
HXCGUI hTabBar_Background2 = NULL;
HXCGUI hTabBar_Background3 = NULL;
HXCGUI hTabBar_Background4 = NULL;
int CALLBACK OnBtnClick23_1(HELE hButton, BOOL* pbHandled)
{
	int x, y;
	XEle_GetPosition(hButton, &x, &y);
	HELE hFocusEle = (HELE)XEle_GetUserData(hButton);

	XEle_ClearBkInfo(hFocusEle);
	XEle_AddBkFill(hFocusEle, element_state_flag_leave, XEle_GetTextColor(hButton));

	HXCGUI hAnimation = XAnima_Create(hFocusEle, 1);
	list_animation.push_back(hAnimation);
	XAnimaMove_SetFlag(XAnima_Move(hAnimation, 400, x+20, y, 1, ease_flag_quad | ease_flag_out), animation_move_x);
	XAnima_Run(hAnimation, hTabBar_Background);

	HIMAGE hImage = XBtn_GetIcon(hButton, 0);
	HSVG   hSvg = XImage_GetSvg(hImage);

	hAnimation = XAnima_Create(hSvg, 1);
	list_animation.push_back(hAnimation);

	int  index = rand();
	index = index % 3;
	if (0== index)
	{
		XAnima_Scale(hAnimation, 600, 1.5, 1.5, 1, ease_flag_quad | ease_flag_in, TRUE);
	} else if (1 == index)
	{
		XAnima_Rotate(hAnimation, 600, 360, 1, 0, FALSE);
	} else if (2 == index)
	{
		XAnima_Rotate(hAnimation, 200, -45, 1, 0, FALSE);
		XAnima_Rotate(hAnimation, 400, 45, 2, 0,TRUE);
		XAnima_Rotate(hAnimation, 200, 0, 1, 0, FALSE);
	}
	XAnima_Run(hAnimation, hButton);
	return 0;
}

int CALLBACK OnBtnClick23_2(HELE hButton, BOOL* pbHandled)
{
	int x, y;
	XEle_GetPosition(hButton, &x, &y);
	HELE hFocusEle = (HELE)XEle_GetUserData(hButton);

	HXCGUI hAnimation = XAnima_Create(hFocusEle, 1);
	list_animation.push_back(hAnimation);
	XAnimaMove_SetFlag(XAnima_Move(hAnimation, 400, x, y, 1, ease_flag_quad | ease_flag_out), animation_move_x);
	XAnima_Run(hAnimation, hTabBar_Background2);
	return 0;
}

int CALLBACK OnSetFocus23_1(HELE hEdit, BOOL* pbHandled)
{
	RECT rect;
	XEle_GetRect(hEdit, &rect);
	HELE hFocusEle = XEle_Create(rect.left + (rect.right - rect.left) / 2, rect.bottom - 2, 1, 2, hWindow);
	int index = rand();
	COLORREF color = RGBA(200, 0, 0, 255);
 	switch (index % 4)
 	{
 	case 0: color = RGBA(171, 72, 188, 255); break;
 	case 1: color = RGBA(254, 167, 38, 255); break;
 	case 2: color = RGBA(38, 166, 154, 255); break;
 	}
	XEle_AddBkFill(hFocusEle, element_state_flag_leave, color);
	XEle_SetUserData(hEdit, (vint)hFocusEle);

	HXCGUI hAnimation = XAnima_Create(hFocusEle, 1);
	list_animation.push_back(hAnimation);

	XAnima_ScaleSize(hAnimation, 400, rect.right-rect.left, 2 ,1 , ease_flag_quad | ease_flag_out, FALSE);
	XAnima_Run(hAnimation, hTabBar_Background3);
	return 0;
}
int CALLBACK OnKillFocus23_1(HELE hEdit, BOOL* pbHandled)
{
	HELE hFocusEle = (HELE)XEle_GetUserData(hEdit);

	HXCGUI hAnimation = XAnima_Create(hFocusEle, 1);
	list_animation.push_back(hAnimation);

	XAnima_ScaleSize(hAnimation, 400, 0, 2, 1, ease_flag_circ | ease_flag_out, FALSE);
	XAnima_DestroyObjectUI(hAnimation, 0);
	XAnima_Run(hAnimation, hTabBar_Background3);
	return 0;
}

int CALLBACK OnSetFocus23_2(HELE hEdit, BOOL* pbHandled)
{
	RECT rect;
	XEle_GetRect(hEdit, &rect);
	HELE hFocusEle = (HELE)XEle_GetUserData(hEdit);
	
	int index = rand();
	COLORREF color = RGBA(200, 0, 0, 255);
	switch (index % 4)
	{
	case 0: color = RGBA(171, 72, 188, 255); break;
	case 1: color = RGBA(254, 167, 38, 255); break;
	case 2: color = RGBA(38, 166, 154, 255); break;
	}
	XEle_ClearBkInfo(hFocusEle);
	XEle_AddBkBorder(hFocusEle, element_state_flag_leave, color,2);

	HXCGUI hAnimation = XAnima_Create(hFocusEle, 1);
	list_animation.push_back(hAnimation);
	XAnima_Move(hAnimation, 400, rect.left, rect.top, 1, ease_flag_quad | ease_flag_out, FALSE);
	XAnima_Run(hAnimation, hTabBar_Background4);
	return 0;
}

//焦点追踪- 线
class CFocusTraceButton_Line : public  CMyBase
{
public:
	HXCGUI  m_hShapeRect;
	HELE    m_hFocusEle;
	BOOL    m_bChangeColor;
	int     m_focusOffset;
	std::vector<HXCGUI>  m_list;
	CFocusTraceButton_Line() {
		m_hShapeRect = NULL;
		m_hFocusEle = NULL;
		m_bChangeColor = FALSE;
		m_focusOffset = -1;
	}
	virtual  void Release() {
		for (auto var : m_list)
			ReleaseObject(var);
		delete  this;
	}
	void CreatePane(int x, int y, int width, int height, HXCGUI hParent)
	{
		m_hShapeRect = XShapeRect_Create(x, y, width, height, hParent);
		m_list.push_back(m_hShapeRect);
		XShapeRect_SetFillColor(m_hShapeRect, RGBA(156, 39, 176, 255));
		XShapeRect_EnableBorder(m_hShapeRect, FALSE);
	}
	void CreatePane2(int x, int y, int width, int height, HXCGUI hParent)
	{
		m_hShapeRect = XShapeRect_Create(x, y, width, height, hParent);
		m_list.push_back(m_hShapeRect);
		XShapeRect_SetBorderColor(m_hShapeRect, RGBA(200, 200, 200, 255));
		XShapeRect_EnableFill(m_hShapeRect, FALSE);
	}
	void CreateFocusEle(int x, int y, int width, int height, COLORREF color, HXCGUI hParent)
	{
		m_hFocusEle = XEle_Create(x, y, width, height, hWindow);
		m_list.push_back(m_hFocusEle);
		XEle_EnableTopmost(m_hFocusEle, TRUE);
		XEle_AddBkFill(m_hFocusEle, element_state_flag_leave, color);
	}
	HELE CreateButton(int x, int y, int width, int height, const wchar_t* pName, HSVG hSvg, HXCGUI hParent)
	{
		HELE hButton = XBtn_Create(x, y, width, height, pName, hParent);
		m_list.push_back(hButton);
		std::wstring str = L"{99:1.9.9;98:16(0)32(1)64(2);5:2(15)20(1)21(3)26(1)22(-5232740)23(255);5:2(15)20(1)21(3)26(1)22(-4702042)23(255);5:2(15)20(1)21(3)26(1)22(-4303953)23(255);}";
		XEle_SetBkInfo(hButton, str.c_str());
		XEle_SetTextColor(hButton, RGBA(255, 255, 255, 255));
		XSvg_SetSize(hSvg, 24, 24);
		XSvg_SetUserFillColor(hSvg, RGBA(255, 255, 255, 255), TRUE);

		HIMAGE  hImage = XImage_LoadSvg(hSvg);
		XBtn_SetIcon(hButton, hImage);
		XEle_RegEventCPP1(hButton, XE_BNCLICK, &CFocusTraceButton_Line::OnBtnClick2);
		return hButton;
	}
	void CreateButton2(int x, int y, int width, int height, const wchar_t* pName, HSVG hSvg, COLORREF color, COLORREF colorBack, HXCGUI hParent)
	{
		HELE hButton = XBtn_Create(x, y, width, height, pName, hParent);
		m_list.push_back(hButton);

		XBtn_SetIconAlign(hButton, button_icon_align_top);
		XSvg_SetUserFillColor(hSvg, color, TRUE);
		XEle_SetTextColor(hButton, color);
		XEle_AddBkFill(hButton, element_state_flag_stay, colorBack);
		XEle_AddBkFill(hButton, element_state_flag_down, colorBack);

		XSvg_SetSize(hSvg, 32, 32);
		HIMAGE  hImage = XImage_LoadSvg(hSvg);
		XBtn_SetIcon(hButton, hImage);

		XEle_AddBkFill(hButton, element_state_flag_leave, RGBA(255, 255, 255, 255));
		XEle_RegEventCPP1(hButton, XE_BNCLICK, &CFocusTraceButton_Line::OnBtnClick2);
	}
private:
	int  OnBtnClick(HELE hButton, BOOL* pbHandled)
	{
		int x, y;
		XEle_GetPosition(hButton, &x, &y);

		HXCGUI hAnimation = XAnima_Create(m_hFocusEle, 1);
		XAnimaMove_SetFlag(XAnima_Move(hAnimation, 400, x, y, 1, ease_flag_quad | ease_flag_out), animation_move_x);
		XAnima_Run(hAnimation, m_hShapeRect);
		return 0;
	}
	int OnBtnClick2(HELE hButton, BOOL* pbHandled)
	{
		if (m_bChangeColor)
		{
			XEle_ClearBkInfo(m_hFocusEle);
			XEle_AddBkFill(m_hFocusEle, element_state_flag_leave, XEle_GetTextColor(hButton));
		}

		RECT  rect;
		XEle_GetRect(hButton, &rect);
		HXCGUI hAnimation = XAnima_Create(m_hFocusEle, 1);
		if (-1 == m_focusOffset)
		{
			XEle_SetWidth(m_hFocusEle, rect.right- rect.left);
			XAnimaMove_SetFlag(XAnima_Move(hAnimation, 400, rect.left, 0, 1, ease_flag_quad | ease_flag_out), animation_move_x);
		} else
		{
			XEle_SetWidth(m_hFocusEle, (rect.right - rect.left)- m_focusOffset - m_focusOffset);
			XAnimaMove_SetFlag(XAnima_Move(hAnimation, 400, rect.left + m_focusOffset, 0, 1, ease_flag_quad | ease_flag_out), animation_move_x);
		}
		XAnima_Run(hAnimation, m_hShapeRect);

		HIMAGE hImage = XBtn_GetIcon(hButton, 0);
		HSVG   hSvg = XImage_GetSvg(hImage);

		hAnimation = XAnima_Create(hSvg, 1);
		int  index = rand();
		index = index % 3;
		if (0 == index)
		{
			XAnima_Scale(hAnimation, 600, 1.5, 1.5, 1, ease_flag_quad | ease_flag_in, TRUE);
		} else if (1 == index)
		{
			XAnima_Rotate(hAnimation, 600, 360, 1, 0, FALSE);
		} else if (2 == index)
		{
			XAnima_Rotate(hAnimation, 200, -45, 1, 0, FALSE);
			XAnima_Rotate(hAnimation, 300, 45, 1, 0, TRUE);
			XAnima_Rotate(hAnimation, 200, 0, 1, 0, FALSE);
		}
		XAnima_Run(hAnimation, hButton);
		return 0;
	}
};

//焦点追踪- 边
class CFocusTraceEdit_Border : public  CMyBase
{
public:
	HXCGUI  m_hShapeRect;
	HELE    m_hFocusEle;
	std::vector<HXCGUI>  m_list;
	CFocusTraceEdit_Border() {
		m_hShapeRect = NULL;
		m_hFocusEle = NULL;
	}
	virtual  void Release() {
		for (auto var: m_list)
			ReleaseObject(var);
		delete  this;
	}
	void CreatePane(int x, int y, int width, int height, HXCGUI hParent)
	{
		m_hShapeRect = XShapeRect_Create(x, y, width, height, hParent);
		m_list.push_back(m_hShapeRect);
		XShapeRect_SetBorderColor(m_hShapeRect, RGBA(200, 200, 200, 255));
		XShapeRect_EnableFill(m_hShapeRect, FALSE);
	}
	void CreateFocusEle(int x, int y, int width, int height, HXCGUI hParent)
	{
		m_hFocusEle = XEle_Create(x, y, width, height, hParent);
		m_list.push_back(m_hFocusEle);
		XEle_EnableTopmost(m_hFocusEle, TRUE);
		XEle_EnableMouseThrough(m_hFocusEle, TRUE);
		XEle_EnableBkTransparent(m_hFocusEle, TRUE);
		XEle_AddBkBorder(m_hFocusEle, element_state_flag_leave, RGBA(254, 167, 38, 255), 2);
	}
	void CreateEdit(int x, int y, int width, int height, HXCGUI hParent)
	{
		HELE hEdit = XEdit_Create(x, y, width, height, hParent);
		m_list.push_back(hEdit);
		XEle_EnableDrawFocus(hEdit, FALSE);

		XEle_AddBkFill(hEdit, element_state_flag_leave, RGBA(245, 245, 245, 255));
		XEle_AddBkFill(hEdit, element_state_flag_stay, RGBA(245, 245, 245, 255));
		XEle_AddBkBorder(hEdit, element_state_flag_leave, RGBA(220, 220, 220, 255), 1);
		XEle_AddBkBorder(hEdit, element_state_flag_stay, RGBA(200, 200, 200, 255), 1);

		XEle_RegEventCPP1(hEdit, XE_SETFOCUS, &CFocusTraceEdit_Border::OnSetFocus);
	}
private:
	int OnSetFocus(HELE hEdit, BOOL* pbHandled)
	{
		RECT rect;
		XEle_GetRect(hEdit, &rect);

		int index = rand();
		COLORREF color = RGBA(200, 0, 0, 255);
		switch (index % 4)
		{
		case 0: color = RGBA(171, 72, 188, 255); break;
		case 1: color = RGBA(254, 167, 38, 255); break;
		case 2: color = RGBA(38, 166, 154, 255); break;
		}
		XEle_ClearBkInfo(m_hFocusEle);
		XEle_AddBkBorder(m_hFocusEle, element_state_flag_leave, color, 2);

		HXCGUI hAnimation = XAnima_Create(m_hFocusEle, 1);
		XAnima_Move(hAnimation, 400, rect.left, rect.top, 1, ease_flag_quad | ease_flag_out, FALSE);
		XAnima_Run(hAnimation, m_hShapeRect);
		return 0;
	}
};

//焦点追踪-线
class CFocusTraceEdit_Line : public  CMyBase
{
public:
	HXCGUI  m_hShapeRect;
	std::vector<HXCGUI>  m_list;
	CFocusTraceEdit_Line() {
		m_hShapeRect = NULL;
	}
	virtual  void Release() {
		for (auto var : m_list)
			ReleaseObject(var);
		delete  this;
	}
	void CreatePane(int x, int y, int width, int height, HXCGUI hParent)
	{
		m_hShapeRect = XShapeRect_Create(x, y, width, height, hParent);
		m_list.push_back(m_hShapeRect);
		XShapeRect_SetBorderColor(m_hShapeRect, RGBA(200, 200, 200, 255));
		XShapeRect_EnableFill(m_hShapeRect, FALSE);
	}
	void CreateEdit(int x, int y, int width, int height, HXCGUI hParent)
	{
		HELE hEdit = XEdit_Create(x, y, width, height, hParent);
		m_list.push_back(hEdit);
		XEle_EnableDrawFocus(hEdit, FALSE);

		XEle_AddBkFill(hEdit, element_state_flag_leave, RGBA(235, 235, 235, 255));
		XEle_AddBkFill(hEdit, element_state_flag_stay, RGBA(235, 235, 235, 255));
		XEle_RegEventCPP1(hEdit, XE_SETFOCUS, &CFocusTraceEdit_Line::OnSetFocus);
		XEle_RegEventCPP1(hEdit, XE_KILLFOCUS, &CFocusTraceEdit_Line::OnKillFocus);
	}
private:
	int  OnSetFocus(HELE hEdit, BOOL* pbHandled)
	{
		RECT rect;
		XEle_GetRect(hEdit, &rect);
		HELE hFocusEle = XEle_Create(rect.left + (rect.right - rect.left) / 2, rect.bottom - 2, 1, 2, hWindow);
		int index = rand();
		COLORREF color = RGBA(200, 0, 0, 255);
		switch (index % 4)
		{
		case 0: color = RGBA(171, 72, 188, 255); break;
		case 1: color = RGBA(254, 167, 38, 255); break;
		case 2: color = RGBA(38, 166, 154, 255); break;
		}
		XEle_AddBkFill(hFocusEle, element_state_flag_leave, color);
		XEle_SetUserData(hEdit, (vint)hFocusEle);

		HXCGUI hAnimation = XAnima_Create(hFocusEle, 1);
		XAnima_ScaleSize(hAnimation, 400, rect.right - rect.left, 2, 1, ease_flag_quad | ease_flag_out, FALSE);
		XAnima_Run(hAnimation, m_hShapeRect);
		return 0;
	}
	int  OnKillFocus(HELE hEdit, BOOL* pbHandled)
	{
		HELE hFocusEle = (HELE)XEle_GetUserData(hEdit);
		if (hFocusEle)
		{
			HXCGUI hAnimation = XAnima_Create(hFocusEle, 1);
			XAnima_ScaleSize(hAnimation, 400, 0, 2, 1, ease_flag_circ | ease_flag_out, FALSE);
			XAnima_DestroyObjectUI(hAnimation, 0);
			XAnima_Run(hAnimation, m_hShapeRect);
		}
		return 0;
	}
};

//焦点追踪
int CALLBACK OnBtnClick23(BOOL* pbHandled)
{
	ReleaseAnimation();
	int left = 150;
	int top = 80;
	int width = 100;
	int height = 60;
#if 1  //图标按钮 切换
	{
		CFocusTraceButton_Line* pFocus = new CFocusTraceButton_Line;
		list_object.push_back(pFocus);
		pFocus->m_focusOffset = 20;
		pFocus->m_bChangeColor = TRUE;
		pFocus->CreatePane2(left, top - 20, 600, height + 40, hWindow); left += 50;
		pFocus->CreateFocusEle(left, top + height - 2, width, 2, RGBA(0, 162, 232, 255), hWindow);

		pFocus->CreateButton2(left, top, width, height, L"Button", XSvg_LoadFile(L"svg\\公益.svg"), RGBA(171, 72, 188, 255), RGBA(247, 238, 248, 255), hWindow); left += width;
		pFocus->CreateButton2(left, top, width, height, L"Button", XSvg_LoadFile(L"svg\\时间戳.svg"), RGBA(254, 167, 38, 255), RGBA(253, 244, 232, 255), hWindow); left += width;
		pFocus->CreateButton2(left, top, width, height, L"Button", XSvg_LoadFile(L"svg\\技术服务.svg"), RGBA(38, 166, 154, 255), RGBA(236, 246, 245, 255), hWindow); left += width;
	}
#endif

#if 1 //图标按钮 切换2 导航条
	left = 150;
	top += 100;
	width = 90;
	height = 40;
	{
		CFocusTraceButton_Line* pFocus = new CFocusTraceButton_Line;
		list_object.push_back(pFocus);
		pFocus->CreatePane(left, top, 600, height, hWindow); left += 50;
		pFocus->CreateFocusEle(left, top + height-3, width, 3, RGBA(0, 162, 232, 255), hWindow);

		pFocus->CreateButton(left, top, width, height, L"Button", XSvg_LoadFile(L"svg\\公益.svg"), hWindow); left += width;
		pFocus->CreateButton(left, top, width, height, L"Button", XSvg_LoadFile(L"svg\\时间戳.svg"), hWindow); left += width;
		pFocus->CreateButton(left, top, width, height, L"Button", XSvg_LoadFile(L"svg\\技术服务.svg"), hWindow); left += width;
	}
#endif

#if 1  //编辑框 焦点边
	left = 150;
	top += 80;
	width = 150;
	height = 30;
	{
		CFocusTraceEdit_Line* pFocus = new CFocusTraceEdit_Line;
		list_object.push_back(pFocus);
		pFocus->CreatePane(left, top, 600, height + 40, hWindow); left += 50;  top += 20;
		pFocus->CreateEdit(left, top, width, height, hWindow); left += (width + 20);
		pFocus->CreateEdit(left, top, width, height, hWindow); left += (width + 20);
		pFocus->CreateEdit(left, top, width, height, hWindow); left += (width + 20);
	}
#endif

#if 1  //编辑框 焦点矩形
	left = 150;
	top += 90;
	width = 150;
	height = 30;
	{
		CFocusTraceEdit_Border* pFocus = new CFocusTraceEdit_Border;
		list_object.push_back(pFocus);
		pFocus->CreatePane(left, top, 600, height + 40, hWindow); left += 50; top += 20;
		pFocus->CreateFocusEle(left, top, width, height, hWindow);

		pFocus->CreateEdit(left, top, width, height, hWindow); left += (width + 20);
		pFocus->CreateEdit(left, top, width, height, hWindow); left += (width + 20);
		pFocus->CreateEdit(left, top, width, height, hWindow); left += (width + 20);
	}
#endif

	XWnd_Redraw(hWindow);
	return 0;
}
HELE hTabPage_Background = NULL; //页面背景,裁剪
HELE hTabPage_cur = NULL; //当前页面
int CALLBACK OnBtnClick24_1(HELE hButton, BOOL* pbHandled)
{
	BOOL bMoveLeft = FALSE;

	int id_old = 0;
	int id_new = XEle_GetUserData(hButton);
	if (hTabPage_cur && XC_IsHELE(hTabPage_cur))
	{
		id_old = XEle_GetUserData(hTabPage_cur);
		if (id_new == id_old)
			return 0;
	}

	if (id_old < id_new)
		bMoveLeft = TRUE;

	int width = 600;
	int height = 300;
	if (hTabPage_cur)
	{
		if (XC_IsHELE(hTabPage_cur))
		{
			HXCGUI hAnimation = XAnima_Create(hTabPage_cur, 1);
			XAnima_Move(hAnimation, 500, bMoveLeft ? 1- width : width,0,1, ease_flag_quad | ease_flag_out,FALSE);
			XAnima_DestroyObjectUI(hAnimation, 0);
			XAnima_Run(hAnimation, hTabPage_Background);
		}
		hTabPage_cur = NULL;
	}
	
	int left = bMoveLeft ? width + 10 : 1 - width - 10;
	hTabPage_cur = XEle_Create(left, 0, width, height, hTabPage_Background);
	if (1 == id_new)
	{
		XEle_AddBkFill(hTabPage_cur, element_state_flag_leave, RGBA(34, 177, 76, 255));
		XBtn_Create(100, 100, 100, 30, L"我是页面 1", hTabPage_cur);
	} else if (2 == id_new)
	{
		XEle_AddBkFill(hTabPage_cur, element_state_flag_leave, RGBA(254, 167, 38, 255));
		XBtn_Create(100, 100, 100, 30, L"我是页面 2", hTabPage_cur);
	} else if (3 == id_new)
	{
		XEle_AddBkFill(hTabPage_cur, element_state_flag_leave, RGBA(38, 166, 154, 255));
		XBtn_Create(100, 100, 100, 30, L"我是页面 3", hTabPage_cur);
	}
	if (hTabPage_cur)
	{
		XEle_SetUserData(hTabPage_cur, id_new);

		HXCGUI hAnimation = XAnima_Create(hTabPage_cur, 1);
		XAnima_Move(hAnimation, 500, 0, 0, 1, ease_flag_quad | ease_flag_out, FALSE);
		XAnima_Run(hAnimation, hTabPage_Background);
	}
	XEle_Redraw(hTabPage_Background);
	return 0;
}

int CALLBACK OnBtnClick24(BOOL* pbHandled)
{
	ReleaseAnimation();

	int left = 150;
	int top = 80;
	int width = 90;
	int height = 40;
	
	CFocusTraceButton_Line* pFocus = new CFocusTraceButton_Line;
	list_object.push_back(pFocus);
	pFocus->CreatePane(left, top, 600, height, hWindow); left += 50;
	pFocus->CreateFocusEle(left, top + height - 3, width, 3, RGBA(255, 255, 255, 255), hWindow);

	HELE hButton1 = pFocus->CreateButton(left, top, width, height, L"Button1", XSvg_LoadFile(L"svg\\公益.svg"), hWindow); left += width;
	HELE hButton2 = pFocus->CreateButton(left, top, width, height, L"Button2", XSvg_LoadFile(L"svg\\时间戳.svg"), hWindow); left += width;
	HELE hButton3 = pFocus->CreateButton(left, top, width, height, L"Button3", XSvg_LoadFile(L"svg\\技术服务.svg"), hWindow); left += width;

	left = 150;
	top += 40;
	//作为背景, 对动画区域裁剪
	hTabPage_Background = XEle_Create(left, top, 600, 300, hWindow);
	list_xcgui.push_back(hTabPage_Background);
	XEle_SetUserData(hButton1, 1);
	XEle_SetUserData(hButton2, 2);
	XEle_SetUserData(hButton3, 3);

	XEle_RegEventC1(hButton1, XE_BNCLICK, OnBtnClick24_1);
	XEle_RegEventC1(hButton2, XE_BNCLICK, OnBtnClick24_1);
	XEle_RegEventC1(hButton3, XE_BNCLICK, OnBtnClick24_1);
	OnBtnClick24_1(hButton1, NULL);

	XWnd_Redraw(hWindow);
	return 0;
}

//展开收缩面板
class CExpandGroup :public CMyBase
{
public:
	struct  panel_info_
	{
		HELE hPanel;
		HELE hButton;
		int  height;
		std::vector<HXCGUI> list_temp;
		std::vector<HXCGUI> list_temp2;
		std::vector<HXCGUI> list_temp3;
		std::vector<HXCGUI> list_temp4;
	};
	std::vector<panel_info_*>   m_list;

	HELE  m_hLayout;
	virtual void Release()
	{
		for (auto var: m_list)
			delete var;
		
		if(XC_IsHELE(m_hLayout)) XEle_Destroy(m_hLayout);
		delete this; 
	}
	HELE CreateLayout(int x, int y, int width, int height)
	{
		m_hLayout = XLayout_Create(x, y, width, height, hWindow);
		XLayoutBox_EnableHorizon(m_hLayout, FALSE);
		XEle_AddBkBorder(m_hLayout, element_state_flag_leave, RGBA(200,200,200,255), 1);
		XEle_SetPadding(m_hLayout, 1, 0, 1, 1);
		XWidget_LayoutItem_SetHeight(m_hLayout, layout_size_auto, 0);
		return m_hLayout;
	}
	HELE CreatePanel(const wchar_t* pName, HSVG hSvg)
	{
		HELE hButton = XBtn_Create(0, 0, 100, 40, pName, m_hLayout);
		XObj_SetTypeEx(hButton, button_type_check);
		XWidget_LayoutItem_SetWidth(hButton, layout_size_fill, 0);
		XEle_EnableDrawBorder(hButton, FALSE);
		XEle_EnableDrawFocus(hButton, FALSE);
		XBtn_SetTextAlign(hButton, textAlignFlag_left | textAlignFlag_vcenter);
		XEle_SetPadding(hButton, 20, 0, 0, 0);
		XEle_SetBkInfo(hButton, L"{99:1.9.9;98:272(0)288(0)320(0)128(0);5:2(7)3(0,0,0,1)20(1)21(3)26(0)22(-3618616)23(255);}");
		XEle_EnableBkTransparent(hButton, TRUE);

		XSvg_SetSize(hSvg, 24, 24);
		XBtn_SetIcon(hButton, XImage_LoadSvg(hSvg));
		XEle_SetCursor(hButton, ::LoadCursor(NULL, IDC_HAND));

		HELE hPanel = XEle_Create(0, 0, 100, 0, m_hLayout);
		XWidget_LayoutItem_SetWidth(hPanel, layout_size_fill, 0);
		XEle_EnableCanvas(hPanel, FALSE);
		XEle_EnableDrawBorder(hPanel, FALSE);

		panel_info_* pInfo = new panel_info_;
		pInfo->hPanel = hPanel;
		pInfo->hButton = hButton;
		pInfo->height = 200;
		m_list.push_back(pInfo);
		
		int left = 20;
		int top = 10;
		int width = 500;
		HXCGUI hText = XShapeText_Create(left + width, top, 200, 20, L"炫彩界面库 3.3.0", pInfo->hPanel);
		pInfo->list_temp.push_back(hText);
		XShapeText_SetTextColor(hText, RGBA(80, 80, 80, 255));

		top += 25;
		for (int i = 0; i < 3; i++)
		{
			HELE hEle = XEle_Create(left + width, top, 100, 50, pInfo->hPanel);
			pInfo->list_temp2.push_back(hEle);
			if(0==i)
				XEle_AddBkFill(hEle, element_state_flag_leave, RGBA(213, 162, 221, 255));
			else if (1 == i)
				XEle_AddBkFill(hEle, element_state_flag_leave, RGBA(255, 221, 170, 255));
			else if (2 == i)
				XEle_AddBkFill(hEle, element_state_flag_leave, RGBA(151, 232, 223, 255));
			left += 130;
		}
		left = 20;
		top += 70;

		hText = XShapeText_Create(left + width, top, 200, 20, L"炫彩界面库 3.3.1", pInfo->hPanel);
		pInfo->list_temp3.push_back(hText);
		XShapeText_SetTextColor(hText, RGBA(80, 80, 80, 255));

		top += 25;
		for (int i = 0; i < 3; i++)
		{
			HELE hEle = XEle_Create(left + width, top, 100, 50, pInfo->hPanel);
			pInfo->list_temp4.push_back(hEle);
			if (0 == i)
				XEle_AddBkFill(hEle, element_state_flag_leave, RGBA(213, 162, 221, 255));
			else if (1 == i)
				XEle_AddBkFill(hEle, element_state_flag_leave, RGBA(255, 221, 170, 255));
			else if (2 == i)
				XEle_AddBkFill(hEle, element_state_flag_leave, RGBA(151, 232, 223, 255));
			left += 130;
		}
		XEle_RegEventCPP1(hButton, XE_BNCLICK, &CExpandGroup::OnBtnClick);
		return  hButton;
	}
	int  OnBtnClick(HELE hButton, BOOL* pbHandled)
	{
		panel_info_* pInfo = NULL;
		for (auto var : m_list)
		{
			if (var->hButton == hButton)
			{
				pInfo = var;
				break;;
			}
		}
		if (NULL == pInfo) return 0;

		HXCGUI hGroup = XAnimaGroup_Create(1);
		HXCGUI hAnimation = XAnima_Create(pInfo->hPanel, 1);
		XAnimaGroup_AddItem(hGroup, hAnimation);

		int width = XEle_GetWidth(pInfo->hPanel);
		BOOL bExpand = XBtn_IsCheck(hButton) ? FALSE : TRUE;
		int left = 0;
		int top = 0;
		if (pInfo->list_temp.size() > 0)
		{
			HXCGUI hText = pInfo->list_temp[0];
			Animation25_Move(hGroup, hText, bExpand ? 0 : 600, bExpand ? -width : width, TRUE);
		}

		int count = pInfo->list_temp2.size();
		for (int i = 0; i < count; i++)
		{
			HELE  hEle = (HELE)pInfo->list_temp2[i];
			Animation25_Move(hGroup, hEle, bExpand ? 200 : 400, bExpand ? -width : width, TRUE);
		}
		if (pInfo->list_temp3.size() > 0)
		{
			HXCGUI hText = pInfo->list_temp3[0];
			Animation25_Move(hGroup, hText, bExpand ? 400 : 200, bExpand ? -width : width, TRUE);
		}

		count = pInfo->list_temp4.size();
		for (int i = 0; i < count; i++)
		{
			HELE  hEle = (HELE)pInfo->list_temp4[i];
			Animation25_Move(hGroup, hEle, bExpand ? 600 : 0, bExpand ? -width : width, TRUE);
		}
		if (bExpand)
		{
			XAnima_LayoutHeight(hAnimation, 400, layout_size_fixed, pInfo->height, 1, ease_flag_quad | ease_flag_out, FALSE);
		} else
		{
			XAnima_Delay(hAnimation, 400);
			XAnima_LayoutHeight(hAnimation, 400, layout_size_fixed, 0, 1, ease_flag_quad | ease_flag_in, FALSE);
		}
		XAnima_Run(hGroup, hWindow);
		return 0;
	}
	void Animation25_Move(HXCGUI hGroup, HXCGUI hObjectUI, int delay, int offsetx, BOOL bDestroy)
	{
		int left = 0;
		int top = 0;
		if (XC_IsHELE(hObjectUI))
			XEle_GetPosition((HELE)hObjectUI, &left, &top);
		else
			XShape_GetPosition(hObjectUI, &left, &top);

		HXCGUI hAnimationMove = XAnima_Create(hObjectUI, 1);
		XAnimaGroup_AddItem(hGroup, hAnimationMove);
		if (delay > 0)
			XAnima_Delay(hAnimationMove, delay);
		XAnima_Move(hAnimationMove, 300, left + offsetx, top, 1, offsetx<0 ?(ease_flag_quad | ease_flag_out) : (ease_flag_quad | ease_flag_in), FALSE);
	}
};

//折叠面板
int CALLBACK OnBtnClick25(BOOL* pbHandled)
{
	ReleaseAnimation();

	int left = 150;
	int top = 50;
	int width = 500;
	int height = 500;

	CExpandGroup* pExpandGroup = new CExpandGroup;
	list_object.push_back(pExpandGroup);
	pExpandGroup->CreateLayout(left, top, width, height);

	HELE hButton = pExpandGroup->CreatePanel(L"折叠1", XSvg_LoadFile(L"svg\\公益.svg"));
	pExpandGroup->CreatePanel(L"折叠2", XSvg_LoadFile(L"svg\\时间戳.svg"));
	pExpandGroup->CreatePanel(L"Button3", XSvg_LoadFile(L"svg\\技术服务.svg"));
	
	XEle_AdjustLayout(pExpandGroup->m_hLayout);
	pExpandGroup->OnBtnClick(hButton, NULL);
	XBtn_SetCheck(hButton, TRUE);

	XWnd_Redraw(hWindow);
	return 0;
}

class CImagePlay : public CMyBase
{
public:
	std::vector<HELE>  m_list;
	std::vector<HELE>  m_listFocus;
	RECT    m_rect;
	HELE    m_hParent;
	HXCGUI  m_hAnimationGroup;
	int     m_index;
	virtual void Release()
	{
		XAnima_Release(m_hAnimationGroup,FALSE);
		if (m_hParent && XC_IsHELE(m_hParent)) XEle_Destroy(m_hParent);
		delete  this;
	}
	void Create(int x, int y, int width, int height, HXCGUI hParent)
	{
		m_hAnimationGroup = NULL;
		m_index = 0;
		m_rect = { x, y, x + width, y + height };
		m_hParent = XEle_Create(x, y, width, height, hParent);

		HELE hBtnLeft = XBtn_Create(10, height/2-35/2, 35,35, L"", m_hParent);
		HELE hBtnRight = XBtn_Create(width - 35 -10, height / 2-35/2, 35, 35, L"", m_hParent);
		XEle_SetCursor(hBtnLeft, ::LoadCursor(NULL, IDC_HAND));
		XEle_SetCursor(hBtnRight, ::LoadCursor(NULL, IDC_HAND));
		XEle_EnableTopmost(hBtnLeft, TRUE);
		XEle_EnableTopmost(hBtnRight, TRUE);
		XEle_EnableBkTransparent(hBtnLeft, TRUE);
		XEle_EnableBkTransparent(hBtnRight, TRUE);
		XEle_SetBkInfo(hBtnLeft, L"{99:1.9.9;98:16(3,1,2)32(0,1,2)64(3,1,2);6:2(15)20(1)21(3)26(1)22(1342177280)23(80);5:2(18)8(135.00)3(2,15,2,10)20(1)21(3)26(1)22(-1)23(255);5:2(18)8(45.00)3(2,9,2,10)20(1)21(3)26(1)22(-1)23(255);6:2(15)20(1)21(3)26(1)22(838860800)23(50);}");
		XEle_SetBkInfo(hBtnRight, L"{99:1.9.9;98:16(0,1,2)32(3,1,2)64(0,1,2);6:2(15)20(1)21(3)26(1)22(838860800)23(50);5:2(18)8(45.00)3(2,15,2,10)20(1)21(3)26(1)22(-1)23(255);5:2(18)8(135.00)3(2,9,2,10)20(1)21(3)26(1)22(-1)23(255);6:2(15)20(1)21(3)26(1)22(1342177280)23(80);}");
		XEle_RegEventCPP(hBtnLeft, XE_BNCLICK, &CImagePlay::OnBtnClickLeft);
		XEle_RegEventCPP(hBtnRight, XE_BNCLICK, &CImagePlay::OnBtnClickRight);
	}
	void CreatePage(const wchar_t* pName, COLORREF color)
	{
		HELE hEle= XEle_Create(0, 0, m_rect.right - m_rect.left, m_rect.bottom - m_rect.top, m_hParent);
		m_list.push_back(hEle);
		XEle_AddBkFill(hEle, element_state_flag_leave, color);

		HXCGUI hText= XShapeText_Create(20, m_rect.bottom- m_rect.top - 30, 200, 20, pName, hEle);
		XShapeText_SetTextColor(hText, RGBA(255, 255, 255, 255));
		if (1 != m_list.size())
		{
			XWidget_Show(hEle, FALSE);
		}
		HELE hFocus = XBtn_Create(0, 0, 20, 20, L"", m_hParent);
		m_listFocus.push_back(hFocus);
		XEle_SetUserData(hFocus, m_listFocus.size()-1);
		XBtn_SetGroupID(hFocus, 9);
		XObj_SetTypeEx(hFocus, button_type_radio);
		XEle_EnableTopmost(hFocus, TRUE);
		XEle_EnableBkTransparent(hFocus, TRUE);
		XEle_SetCursor(hFocus, ::LoadCursor(NULL, IDC_HAND));
		XEle_SetBkInfo(hFocus, L"{sizeT:100,100;99:1.9.9;98:272(0)288(1,0)320(1,0)128(1,0);6:2(15)3(5,5,5,5)20(1)21(3)26(1)22(-1761607681)23(150);6:2(15)20(1)21(3)26(1)22(1694498815)23(100);}");
		XEle_RegEventCPP1(hFocus, XE_BUTTON_CHECK, &CImagePlay::OnButtonCheckFocus);
	}
	void End()
	{
		int count = m_listFocus.size();
		int left =( m_rect.right-m_rect.left - count * 30)/2;
		for (auto var: m_listFocus)
		{
			XEle_SetPosition(var, left, m_rect.bottom- m_rect.top - 50);
			left += 30;
		}
		Run(TRUE);
	}
private:
	int  OnBtnClickLeft(BOOL* pbHandled)
	{
		Run(TRUE);
		return 0;
	}
	int  OnBtnClickRight(BOOL* pbHandled)
	{
		Run(FALSE);
		return 0;
	}
	int  OnButtonCheckFocus(HELE hButton, BOOL bCheck, BOOL* pbHandled)
	{
		if (bCheck)
		{
			int index = XEle_GetUserData(hButton);
			Run(TRUE, index);
		}
		return 0;
	}
	static void CALLBACK OnAnimation(HXCGUI hAnimation, int flag)
	{
		CImagePlay*  pImagePayl = (CImagePlay*)XAnima_GetUserData(hAnimation);
		pImagePayl->m_hAnimationGroup = NULL;
		pImagePayl->Run();
	}
	void Run(BOOL bLeft = TRUE , int index=-1)
	{
		if (m_hAnimationGroup)
		{
			XAnima_Release(m_hAnimationGroup);
			m_hAnimationGroup = NULL;
		}

		int count = m_list.size();
		if (count < 2) return;

		if (-1 != index)
		{
			if (m_index == index) return;
			if (m_index <= index) bLeft = TRUE;
			else bLeft = FALSE;
		}
		m_hAnimationGroup = XAnimaGroup_Create(1);

		int width = m_rect.right - m_rect.left;
		if (m_index < count)
		{
			HELE hPage = m_list[m_index];
			XEle_SetPosition(hPage, 0, 0);

			HXCGUI hAnimation = XAnima_Create(hPage, 1);
			XAnima_Move(hAnimation, 1000, bLeft? -width : width, 0, 1, ease_flag_quad | ease_flag_out, FALSE);
			XAnima_Delay(hAnimation, 2000);
			XAnimaGroup_AddItem(m_hAnimationGroup, hAnimation);
		}
		if (-1 != index)
		{
			m_index = index;
		} else if (bLeft)
		{
			m_index++;
			if (m_index >= count) m_index = 0;
		} else
		{
			m_index--; 
			if (m_index < 0) m_index = count-1;
		}
		if (m_index<0 || m_index >= count)
			m_index = 0;

		if (m_index < count)
		{
			HELE hPage = m_list[m_index];
			XEle_SetPosition(hPage, bLeft? width : -width, 0);
			XWidget_Show(hPage, TRUE);

			HXCGUI hAnimation = XAnima_Create(hPage, 1);
			XAnima_Move(hAnimation, 1000, 0, 0, 1, ease_flag_quad | ease_flag_out, FALSE);
			XAnimaGroup_AddItem(m_hAnimationGroup, hAnimation);
		}
		XAnima_Run(m_hAnimationGroup, m_hParent);
		XAnima_SetUserData(m_hAnimationGroup, (vint)this);
		XAnima_SetCallback(m_hAnimationGroup, &CImagePlay::OnAnimation);

		XBtn_SetCheck(m_listFocus[m_index], TRUE);
	}
};

//图片轮播
int CALLBACK OnBtnClick26(BOOL* pbHandled)
{
	ReleaseAnimation();
	CImagePlay* pImagePlay = new CImagePlay;
	list_object.push_back(pImagePlay);
	pImagePlay->Create(150, 80, 600, 300, hWindow);
	pImagePlay->CreatePage(L"1. 炫彩界面库3.3.1", RGBA(251, 140, 0, 255));
	pImagePlay->CreatePage(L"2. 炫彩界面库3.3.2", RGBA(239, 83, 80, 255));
	pImagePlay->CreatePage(L"3. 炫彩界面库3.3.3", RGBA(194, 24, 91, 255));
	pImagePlay->End();

	XWnd_Redraw(hWindow);
	return 0;
}

//通过背景管理器实现动画
class CButtonAnimation
{
public:
	static void Run(HELE hButton, int type)
	{
		XEle_SetTextColor(hButton, RGBA(255, 255, 255, 255));
		if (1 == type || 2 == type || 3 == type)
			XEle_SetBkInfo(hButton, L"{99:1.9.9;98:16(0,1)32(0,1)64(0);5:41(10)2(15)20(1)21(3)26(0)22(-2984423)23(255);5:41(1)2(15)3(10,10,10,10)20(1)21(3)26(0)22(-1669594)23(255);}");
		else if (4 == type || 5 == type)
			XEle_SetBkInfo(hButton, L"{99:1.9.9;98:16(0,1)32(0,1)64(0);5:41(10)2(15)20(1)21(3)26(0)22(-2984423)23(255);5:41(1)2(11)8(160.00)3(10,-5,10,-5)20(1)21(3)26(0)22(-1669594)23(255);}");

		XEle_SetUserData(hButton, type);
		XEle_RegEventC1(hButton, XE_MOUSESTAY, &CButtonAnimation::OnMouseStay);
		XEle_RegEventC1(hButton, XE_MOUSELEAVE, &CButtonAnimation::OnMouseLeave);
	}
	static int CALLBACK OnMouseStay(HELE hButton, BOOL* pbHandled)
	{
		XAnima_ReleaseEx(hButton, FALSE);
		HXCGUI hAnimation = XAnima_Create(hButton, 1);
		XAnimaItem_SetCallback(XAnima_Delay(hAnimation, 500), OnAnimationItem);
		XAnima_Run(hAnimation, hButton);
		return 0;
	}
	static int CALLBACK OnMouseLeave(HELE hButton, HELE hEleStay, BOOL* pbHandled)
	{
		XAnima_ReleaseEx(hButton, FALSE);
		HXCGUI hAnimation = XAnima_Create(hButton, 1);
		XAnimaItem_SetCallback(XAnima_Delay(hAnimation, 500), OnAnimationItem);
		XAnima_Run(hAnimation, hButton);
		return 0;
	}
	static void CALLBACK OnAnimationItem(HXCGUI hAnimation, float pos)
	{
		HELE hButton = (HELE)XAnima_GetObjectUI(hAnimation);
		if (!XC_IsHELE(hButton))
			return;

		int width, height;
		XEle_GetSize(hButton, &width, &height);

		HBKM hBkM = XEle_GetBkManager(hButton);
		common_state3_  state = XBtn_GetState(hButton);
		int  type = XEle_GetUserData(hButton);
		if (1 == type)
		{
			if (common_state3_leave == state)
			{
				vint hObj = XBkM_GetObject(hBkM, 1);
				int sizeH = width / 2 * pos;
				int sizeV = height / 2 * pos;
				XBkObj_SetMargin(hObj, sizeH, sizeV, sizeH, sizeV);
			} else  if (common_state3_stay == state)
			{
				vint hObj = XBkM_GetObject(hBkM, 1);
				int sizeH = width / 2 * (1.0f - pos);
				int sizeV = height / 2 * (1.0f - pos);
				XBkObj_SetMargin(hObj, sizeH, sizeV, sizeH, sizeV);
			}
		} else if (2 == type)
		{
			if (common_state3_leave == state)
			{
				vint hObj = XBkM_GetObject(hBkM, 1);
				int sizeH = width / 2 * pos;
				XBkObj_SetMargin(hObj, sizeH, 0, sizeH, 0);
			} else  if (common_state3_stay == state)
			{
				vint hObj = XBkM_GetObject(hBkM, 1);
				int sizeH = width / 2 * (1.0f - pos);
				XBkObj_SetMargin(hObj, sizeH, 0, sizeH, 0);
			}
		} else if (3 == type)
		{
			if (common_state3_leave == state)
			{
				vint hObj = XBkM_GetObject(hBkM, 1);
				int sizeH = width * pos;
				XBkObj_SetMargin(hObj, 0, 0, sizeH, 0);
			} else  if (common_state3_stay == state)
			{
				vint hObj = XBkM_GetObject(hBkM, 1);
				int sizeH = width * (1.0f - pos);
				XBkObj_SetMargin(hObj, 0, 0, sizeH, 0);
			}
		} else if (4 == type)
		{
			if (common_state3_leave == state)
			{
				vint hObj = XBkM_GetObject(hBkM, 1);
				int sizeH = width / 2 * (1.0f - pos);
				XBkObj_SetMargin(hObj, sizeH, 0, sizeH, 0);
			} else  if (common_state3_stay == state)
			{
				vint hObj = XBkM_GetObject(hBkM, 1);
				int sizeH = width / 2 * pos;
				if (pos == 1.0f)
					sizeH = 0;
				XBkObj_SetMargin(hObj, sizeH, 0, sizeH, 0);
			}
		} else if (5 == type)
		{
			width += 30;
			if (common_state3_leave == state)
			{
				vint hObj = XBkM_GetObject(hBkM, 1);
				int sizeH = width * (1.0f - pos);
				XBkObj_SetMargin(hObj, sizeH - 15, -5, 10, -5);
			} else  if (common_state3_stay == state)
			{
				vint hObj = XBkM_GetObject(hBkM, 1);
				int sizeH = width * pos;
				XBkObj_SetMargin(hObj, sizeH - 15, -5, 10, -5);
			}
		}
	}
};

//背景管理器
int CALLBACK OnBtnClick27(BOOL* pbHandled)
{
	ReleaseAnimation();
	int left = 150, top = 50;
	for (int i = 0; i < 5; i++)
	{
		HELE hButton = XBtn_Create(left, top, 120, 40, L"Button", hWindow); top += 50;
		list_xcgui.push_back(hButton);
		CButtonAnimation::Run(hButton, 1);
	}
	left += 140; top = 50;
	for (int i = 0; i < 5; i++)
	{
		HELE hButton = XBtn_Create(left, top, 120, 40, L"Button", hWindow); top += 50;
		list_xcgui.push_back(hButton); 
		CButtonAnimation::Run(hButton, 2);
	}
	left += 140; top = 50;
	for (int i = 0; i < 5; i++)
	{
		HELE hButton = XBtn_Create(left, top, 120, 40, L"Button", hWindow); top += 50;
		list_xcgui.push_back(hButton); 
		CButtonAnimation::Run(hButton, 3);
	}
	left += 140; top = 50;
	for (int i = 0; i < 5; i++)
	{
		HELE hButton = XBtn_Create(left, top, 120, 40, L"Button", hWindow); top += 50;
		list_xcgui.push_back(hButton); 
		CButtonAnimation::Run(hButton, 4);
	}

	left += 140; top = 50;
	for (int i = 0; i < 5; i++)
	{
		HELE hButton = XBtn_Create(left, top, 120, 40, L"Button", hWindow); top += 50;
		list_xcgui.push_back(hButton); 
		CButtonAnimation::Run(hButton, 5);
	}
	XWnd_Redraw(hWindow);
	return 0;
}

#if defined (_MSC_VER) && (_MSC_VER > 1900)
#pragma  comment(lib,"Shcore.lib")
#include <shellscalingapi.h>
#endif
// DPI scale the position and size of the button control 
// void UpdateButtonLayoutForDpi(HWND hWnd)
// {
// 	int iDpi = GetDpiForWindow(hWnd);
// 	int dpiScaledX = MulDiv(INITIALX_96DPI, iDpi, 96);
// 	int dpiScaledY = MulDiv(INITIALY_96DPI, iDpi, 96);
// 	int dpiScaledWidth = MulDiv(INITIALWIDTH_96DPI, iDpi, 96);
// 	int dpiScaledHeight = MulDiv(INITIALHEIGHT_96DPI, iDpi, 96);
// 	SetWindowPos(hWnd, hWnd, dpiScaledX, dpiScaledY, dpiScaledWidth, dpiScaledHeight, SWP_NOZORDER | SWP_NOACTIVATE);
// }

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPTSTR lpCmdLine, int nCmdShow)
{
	//BOOL b = SetProcessDPIAware();
	//SetProcessDpiAwarenessContext(1);
#if defined (_MSC_VER) && (_MSC_VER > 1900)
	SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE);
#endif
	int  a = _MSC_VER;
	XInitXCGUI(FALSE);
	//XC_EnableDPI(TRUE);

	XC_ShowLayoutFrame(TRUE);
	XC_ShowSvgFrame(TRUE);
	//XC_SetPaintFrequency(100);
	hWindow = XWnd_Create(0, 0,1020, 650, L"炫彩界面库 动画特效 SVG特效", NULL, window_style_default);
//	HIMAGE  hImage = XImage_LoadSvgFile(L"svg\\时间戳.svg");
//	XWnd_AddBkImage(hWindow, window_state_flag_body_leave, hImage);

//	hSvg = XSvg_LoadFile(L"svg\\时间戳.svg");
//	XSvg_SetAlpha(hSvg, 10);

	int top = 35;
	XEle_RegEventC(CreateButtonRadio(10, top, L"1.下落 缩放 缓动"), XE_BNCLICK, OnBtnClick1);
	XEle_RegEventC(CreateButtonRadio(10, top, L"2.下落 呼吸SVG"), XE_BNCLICK, OnBtnClick2);
	XEle_RegEventC(CreateButtonRadio(10, top, L"3.呼吸SVG"), XE_BNCLICK, OnBtnClick3);
	XEle_RegEventC(CreateButtonRadio(10, top, L"4.不透明度SVG"), XE_BNCLICK, OnBtnClick4);
	XEle_RegEventC(CreateButtonRadio(10, top, L"5.移动SVG"), XE_BNCLICK, OnBtnClick5);
	XEle_RegEventC(CreateButtonRadio(10, top, L"6.形状文本"), XE_BNCLICK, OnBtnClick6);
	XEle_RegEventC(CreateButtonRadio(10, top, L"7.按钮"), XE_BNCLICK, OnBtnClick7);
	XEle_RegEventC(CreateButtonRadio(10, top, L"8.布局焦点展开"), XE_BNCLICK, OnBtnClick8);
	XEle_RegEventC(CreateButtonRadio(10, top, L"9.图片切换"), XE_BNCLICK, OnBtnClick9);
	XEle_RegEventC(CreateButtonRadio(10, top, L"10.图片切换2"), XE_BNCLICK, OnBtnClick10);
	XEle_RegEventC(CreateButtonRadio(10, top, L"11.进度 等待"), XE_BNCLICK, OnBtnClick11);
	XEle_RegEventC(CreateButtonRadio(10, top, L"12.旋转 移动"), XE_BNCLICK, OnBtnClick12);
	XEle_RegEventC(CreateButtonRadio(10, top, L"13.旋转 摇摆"), XE_BNCLICK, OnBtnClick13);
	XEle_RegEventC(CreateButtonRadio(10, top, L"14.旋转 移动 缩放"), XE_BNCLICK, OnBtnClick14);
	XEle_RegEventC(CreateButtonRadio(10, top, L"15.旋转 开合效果"), XE_BNCLICK, OnBtnClick15);
	XEle_RegEventC(CreateButtonRadio(10, top, L"16.颜色渐变"), XE_BNCLICK, OnBtnClick16);
	XEle_RegEventC(CreateButtonRadio(10, top, L"17.缩放 位置"), XE_BNCLICK, OnBtnClick17);
	XEle_RegEventC(CreateButtonRadio(10, top, L"18.按钮 宽度"), XE_BNCLICK, OnBtnClick18);

	top = 35;
	XEle_RegEventC(CreateButtonRadio(900, top, L"19.窗口特效"), XE_BNCLICK, OnBtnClick19);
	XEle_RegEventC(CreateButtonRadio(900, top, L"20.遮盖弹窗"), XE_BNCLICK, OnBtnClick20);
	XEle_RegEventC(CreateButtonRadio(900, top, L"21.通知消息"), XE_BNCLICK, OnBtnClick21);
	XEle_RegEventC(CreateButtonRadio(900, top, L"22.进度条"), XE_BNCLICK, OnBtnClick22);
	
	XEle_RegEventC(CreateButtonRadio(900, top, L"23.焦点追踪"), XE_BNCLICK, OnBtnClick23);
	
	XEle_RegEventC(CreateButtonRadio(900, top, L"24.页面切换 滑动"), XE_BNCLICK, OnBtnClick24);
	XEle_RegEventC(CreateButtonRadio(900, top, L"25.折叠面板"), XE_BNCLICK, OnBtnClick25);
	XEle_RegEventC(CreateButtonRadio(900, top, L"26.图片轮播"), XE_BNCLICK, OnBtnClick26);
	XEle_RegEventC(CreateButtonRadio(900, top, L"27.背景管理器"), XE_BNCLICK, OnBtnClick27);

//	XEle_RegEventC(CreateButtonRadio(top, L"17.按钮状态切换"), XE_BNCLICK, OnBtnClick17);
//	XEle_RegEventC(CreateButtonRadio(top, L"17.图片翻转"), XE_BNCLICK, OnBtnClick17);

	//SVG 克隆, SVG 单独设置属性, SVG判断重复加载文件

	XWnd_RegEventC1(hWindow, WM_PAINT, &OnWndDrawWindow);
	XWnd_Show(hWindow, TRUE);
	XRunXCGUI();
	ReleaseAnimation();
	XExitXCGUI();
	return TRUE;
}
#endif
