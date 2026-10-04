# OptiScaler 游戏内菜单汉化

此目录只处理游戏内菜单，安装器和原有文档保持原样。

基于 `ShyVortex/OptiScaler-DLSSNR-PreSR-Multipass` 的 **0.9.33**，
固定提交 `8bfff2724e0287891d3c636cfede12cb4eca876b`。
翻译在文本尺寸计算和绘制处生效，控件 ID、INI 配置键和图形后端仍使用原始值。
Windows 系统中文字体与原西文字体合并；找不到字体时回退英文。

## 构建

准备上述提交的源码以及其 `.gitmodules` 指定版本的依赖，使用 Visual Studio 2022：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File localization/build-menu-zh.ps1 `
  -SourcePath temp_optiscaler/localized-source `
  -MSBuildPath "D:/OptiScaler-Aurora/build-tools/VS2022/MSBuild/Current/Bin/MSBuild.exe"
```

产物位于 `Output/OptiScaler-0.9.33-zh-CN.zip`。仅替换原 OptiScaler 代理 DLL，
安装与回退方法见 `INSTALL.zh-CN.txt`。
修改 `menu.zh-CN.txt` 后重新构建即可更新翻译。
字典由构建脚本生成 UTF-8 字节转义，避免中文 Windows 编译器代码页破坏字符串。

## 验证

`menu_ui_check.cpp` 使用相同 ImGui 源码和字体加载路径，验证全部译文字形、
原控件 ID、翻译文本宽度、`##` 隐藏 ID，以及实际模拟鼠标点击。
它也可以输出独立菜单预览；该预览不代表游戏内运行验证。
未映射的动态后端诊断、技术标识和文件名保留原文。
