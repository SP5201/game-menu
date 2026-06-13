//测试注册自定义回调函数
var ret = XC_Callback("XC_Callback"); //调用C函数.在C代码中注册的函数
//alert(ret, "返回值");
ret = XC_Callback2("XC_Callback2",100);
//alert(ret, "返回值");