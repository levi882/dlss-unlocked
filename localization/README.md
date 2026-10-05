# OptiScaler 游戏内菜单汉化

RTX 20/30 FP16 专版已迁移至作者发布的 DLSSG-Transfusion 1.4.5.3 优化 ASI 核心，
替代 dlssg_for_sm86。两处 NR 继续使用用户提供的 plain FP16 运行库。
Transfusion 面板移植自固定提交 b56bd2deed114507ad2c88f986d90ed50ffb4639，
直接接入 OptiScaler 的“Transfusion 帧生成”页，使用同一 ImGui 和系统中文字体，
无需 ReShade。JSON 配置键、模式值及热重载协议保留上游定义。
源面板及 MIT 许可在 transfusion/；适配脚本 apply-transfusion.ps1。
核心二进制使用官方 Release，保留作者未公开的优化内核。

构建此专版时增加 build-menu-zh.ps1 -TransfusionProfile；菜单产物为
Output/OptiScaler-0.9.34-Transfusion-zh-CN.zip。
用 build-transfusion-components.ps1 验证官方 ZIP 和 FP16 文件并生成组件输入。
package-release.ps1 负责核对哈希、配置、完整 ZIP 和安装器内容，CI 仅上传候选稿；
校验后再替换原发布附件。普通汉化发布页不受此次更新影响。
RTX 20 为实验性，尚未完成实际游戏验证。使用方式见 INSTALL-RTX20-30.zh-CN.txt。
transfusion_ui_check.cpp 使用真实移植面板验证模式渲染、鼠标点击保存、原始 JSON 键、
注释保留、快捷键释放，以及所有译文的字形。

此目录只处理游戏内菜单，安装器和原有文档保持原样。

当前代理 DLL 合入 `ShyVortex/OptiScaler-DLSSNR-PreSR-Multipass` **0.9.34** 的
低延迟输入选择同步和 DX12 菜单缩放、窗口边界修复，
源码固定提交 `73fab132f9f48d194926b27124d9320b0b4cc870`。
两个专版保留已有 0.9.33 底包的配套文件、Transfusion 核心、NR 和运行库恢复逻辑；
不会用标准包替换现有专版。package-release.ps1 继续校验原底包 SHA256。
翻译在文本尺寸计算和绘制处生效，控件 ID、INI 配置键和图形后端仍使用原始值。
Windows 系统中文字体与原西文字体合并；找不到字体时回退英文。

## 构建

准备上述提交的源码以及其 `.gitmodules` 指定版本的依赖，使用 Visual Studio 2022：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File localization/build-menu-zh.ps1 `
  -SourcePath temp_optiscaler/localized-source `
  -MSBuildPath "D:/OptiScaler-Aurora/build-tools/VS2022/MSBuild/Current/Bin/MSBuild.exe"
```

产物位于 `Output/OptiScaler-0.9.34-zh-CN.zip`。仅替换原 OptiScaler 代理 DLL，
安装与回退方法见 `INSTALL.zh-CN.txt`。
修改 `menu.zh-CN.txt` 后重新构建即可更新翻译。
字典由构建脚本生成 UTF-8 字节转义，避免中文 Windows 编译器代码页破坏字符串。

## 验证

`menu_ui_check.cpp` 使用相同 ImGui 源码和字体加载路径，验证全部译文字形、
原控件 ID、翻译文本宽度、`##` 隐藏 ID，以及实际模拟鼠标点击。
它也可以输出独立菜单预览；该预览不代表游戏内运行验证。
未映射的动态后端诊断、技术标识和文件名保留原文。

## RTX 40 专版

RTX 40 使用同一 Transfusion 中文面板及官方优化 ASI，NR 保留 ShortFuse SF-v2。
两处 NR SHA256 为 6EB209E764F39872625DEBD6ABAF45E2BB6322F6F270F781F70C059AE30B3927。
build-transfusion-components.ps1 -Profile RTX40 生成对应组件输入；
package-release.ps1 -Rtx40BundleZip 配合 NR-v0.9.34-RTX40-zh-CN 标签独立打包。
旧解锁和 Smooth Motion 默认关闭；使用方式见 INSTALL-RTX40.zh-CN.txt。

## 后续跟进

release-menu-zh.yml 每三小时检测上游稳定版，并在现有组件上重新编译中文代理 DLL。
源版本与 Git 标签、提交一致性必须通过校验；菜单适配点变化时构建会失败。
validate-menu.ps1 使用真实 ImGui 验证上游低延迟和菜单缩放回归、中文字体和控件 ID、
Transfusion 配置保存、注释保留与快捷键释放；这些检查不代替实际游戏验证。
候选 EXE 和 ZIP 上传到独立草稿，定时流程不覆盖公开 release。
手动指定 build_tag 时可复用已完成上述验证的菜单构建；GPU 组件仍从固定原始输入获取。
