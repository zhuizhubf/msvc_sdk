# MSVC 2008 / 2010 便携工具链 —— GitHub Actions 方案（2008 与 2010 独立打包）

## 为什么拆两个工作流
- `build-vs2008.yml` → 产物 `msvc2008-portable-win.zip`（VC9, _MSC_VER 1500）
- `build-vs2010.yml` → 产物 `msvc2010-portable-win.zip`（VC10, _MSC_VER 1600）
两者**完全独立**，可单独触发、单独下载，互不干扰。已移除原方案里「每周一 03:00 UTC 定时巡检」的 `schedule` 触发器。

## 官方取件（微软下载中心至今在线，无需第三方存档）
| 工具链 | 官方页面 | 文件 | 直链 |
|---|---|---|---|
| VS2008 SP1 (中文) | id=13276 | VS2008SP1CHSX1512981.iso (898.1MB) | https://download.microsoft.com/download/1/9/d/19d22169-a4b2-455f-8c28-ed137bd91487/VS2008SP1CHSX1512981.iso |
| Windows SDK 7.1 | id=8442 | GRMSDKX_EN_DVD.iso (570.9MB) | https://download.microsoft.com/download/A/6/A/A6AC035D-DA3F-4F0C-ADA4-37C8E5D34E3D/GRMSDKX_EN_DVD.iso |
| VC10 编译器 SP1 修补 | id=4422 | vc-compiler-kb2519277.exe (121MB) | https://download.microsoft.com/download/0/B/D/0BDA894F-2CCD-4C2C-B5A7-4EB1171962E5/vc-compiler-kb2519277.exe |

SDK 7.1 ISO 官方 SHA1（x64）：`9203529F5F70D556A60C37F118A95214E6D10B5A`

## 「VS2010 在哪、要微软官方」——结论
- **VS2010 完整产品 ISO 已从微软公开下载中心下线**，官方文档明确：需登录 my.visualstudio.com（订阅）或 VLSC（批量授权）才能取。
- **但 VC10 编译器本身有微软官方公开来源**：Windows SDK 7.1 (id=8442) 装时勾选 "Visual C++ Compilers" 即装 `cl.exe`/`link.exe` 16.xx。这就是 `build-vs2010.yml` 默认走的路，**全程微软官方直链，零第三方存档**。
- 只有当你还需要 **MFC/ATL** 时，才必须自备 VS2010 ISO：在 Actions 手动触发时把订阅账号下到的 ISO 直链填进 `vs2010_iso_url` 参数（留空 = 纯 SDK 编译器包）。

## 用法
1. 把整个目录推到 GitHub 仓库（保持 `.github/workflows/` 路径）。
2. Actions 页 → 选 `build-vs2008-portable` 或 `build-vs2010-portable` → Run workflow。
3. 跑完在 Artifacts 下载对应 zip。

## 产物使用（任意 Windows 机，无需装 VS、无需管理员）
```
clenv.bat x86            :: 初始化 x86 环境（或 x64）
build.bat x86 hello.cpp  :: 默认 /MT 静态链 CRT
```
`clenv.bat` 纯靠 PATH/INCLUDE/LIB，**不读注册表**，因此在没装过 VS 的机器/容器里也能用（官方 vcvarsall.bat 做不到这点）。
看到 `[OK] MSVC 2008 ready` 与 `compiler ver. 1500`（2010 为 1600）即成功。

## 已知坑（脚本里已处理）
1. SDK 7.1 装 VC 编译器组件前必须有 .NET 4.x，否则编译器被静默跳过 → 预检脚本拦。
2. VS2008/VS2010 静默安装必须进 ISO 的 `Setup\Setup.exe /q /norestart`，根目录 `setup.hta` 不认 `/q`。
3. 装了 VS2010 SP1 后 SDK 7.1 的 `cl.exe` 会被移除 / 报 LNK1123 → 打 KB2519277 修复。
4. 绿色包不能用官方 `vcvarsall.bat`（查注册表 `HKLM\...\VisualStudio\SxS\VS7`，纯拷贝机没有会失败）→ 用自动生成的 `clenv.bat`。

## 免责声明
脚本不内嵌任何微软二进制，仅在企业/个人已有合法授权的前提下自动化"下载官方 ISO → 静默安装 → 抽取目录"流程。生产/企业构建机请走 MSDN 订阅或 VLSC 授权渠道。
