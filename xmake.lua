-- xmake.lua —— 用 xmake 统一编排 MSVC 2008/2010 便携工具链的 下载/安装/打包/构建
-- 用法：
--   xmake fetch   -- 下载官方 ISO 到 _dl/（带缓存，命中即跳过）
--   xmake install -- 挂载/静默安装 VS2008 + SDK7.1
--   xmake pack    -- 抽取 VC+SDK 目录、生成 clenv.bat、打包 zip
--   xmake build   -- 用绿色包编译自检程序（自动套 clenv 环境）
-- 指定工具链：xmake f --toolset=2008|2010  （默认 2008）
--
-- 说明：xmake 只做编排与构建驱动；MSVC 编译器本体仍来自微软官方 ISO 静默安装，
--       本脚本不内嵌任何微软二进制。

set_project("msvc-portable")
set_version("1.0.0")
set_description("Portable MSVC 2008/2010 toolchain fetched from official Microsoft ISOs")

-- 可配置：xmake f --toolset=2008 或 2010
option("toolset", {default = "2008", values = {"2008", "2010"}, description = "工具链版本"})

-- 官方直链（微软下载中心至今在线）
local PRESET = {
    vs2008 = {
        url  = "https://download.microsoft.com/download/1/9/d/19d22169-a4b2-455f-8c28-ed137bd91487/VS2008SP1CHSX1512981.iso",
        out  = "_dl/VS2008SP1.iso", min = 800,
    },
    sdk71 = {
        url  = "https://download.microsoft.com/download/A/6/A/A6AC035D-DA3F-4F0C-ADA4-37C8E5D34E3D/GRMSDKX_EN_DVD.iso",
        out  = "_dl/GRMSDKX.iso", min = 500, sha1 = "9203529F5F70D556A60C37F118A95214E6D10B5A",
    },
    kb = {
        url = "https://download.microsoft.com/download/0/B/D/0BDA894F-2CCD-4C2C-B5A7-4EB1171962E5/vc-compiler-kb2519277.exe",
        out = "_dl/vc-compiler-kb2519277.exe", min = 100,
    },
}

-- 通用下载（带缓存 + 体积校验）
local function fetch_one(item)
    import("net.filedownload")
    import("utils.archive")
    local target = path.join(os.projectdir(), item.out)
    if os.isfile(target) and (os.filesize(target) or 0) > item.min * 1024 * 1024 then
        print("[cache] %s 已存在，跳过", item.out)
        return
    end
    os.mkdir(path.directory(target))
    print("[fetch] %s -> %s", item.url, item.out)
    filedownload.download(item.url, {filepath = target})
    local sz = (os.filesize(target) or 0)
    if sz <= item.min * 1024 * 1024 then
        raise("下载体积异常(%d B < %d MB)，直链可能失效：%s", sz, item.min, item.url)
    end
    if item.sha1 then
        local actual = hash.sha1(target)
        if actual:lower() ~= item.sha1:lower() then
            os.rm(target)
            raise("SHA1 不匹配 实际=%s 期望=%s", actual, item.sha1)
        end
        print("[sha1] 校验通过")
    end
end

-- ============ xmake fetch ============
task("fetch")
    set_category("action")
    set_description("下载官方 ISO/补丁到 _dl/（带缓存）")
    on_run(function ()
        local toolset = get_config("toolset") or "2008"
        if toolset == "2010" then
            fetch_one(PRESET["sdk71"]); fetch_one(PRESET["kb"])
        else
            fetch_one(PRESET["vs2008"]); fetch_one(PRESET["sdk71"])
        end
        print("[OK] fetch 完成")
    end)

-- ============ xmake install ============
task("install")
    set_category("action")
    set_description("挂载 ISO 并静默安装 VS2008 + SDK7.1（Windows 专用）")
    on_run(function ()
        if not is_host("windows") then raise("install 仅支持 Windows runner") end
        local toolset = get_config("toolset") or "2008"
        -- 复用仓库里的静默安装脚本；xmake 负责串联与失败即停
        if toolset == "2010" then
            os.exec("powershell -NoProfile -ExecutionPolicy Bypass -File scripts/03-install-sdk71.ps1 -IsoPath \"$(pwd)\\..\\_dl\\GRMSDKX.iso\"")
            os.exec("powershell -NoProfile -ExecutionPolicy Bypass -File scripts/06-apply-kb.ps1 -KbPath \"$(pwd)\\..\\_dl\\vc-compiler-kb2519277.exe\"")
        else
            os.exec("powershell -NoProfile -ExecutionPolicy Bypass -File scripts/02-install-vs2008.ps1 -IsoPath \"%s\"", path.join(os.projectdir(), PRESET.vs2008.out))
            os.exec("powershell -NoProfile -ExecutionPolicy Bypass -File scripts/03-install-sdk71.ps1 -IsoPath \"%s\"", path.join(os.projectdir(), PRESET.sdk71.out))
        end
        print("[OK] install 完成")
    end)

-- ============ xmake pack ============
task("pack")
    set_category("action")
    set_description("抽取 VC+SDK 目录、生成 clenv.bat 并打包 zip")
    on_run(function ()
        local toolset = get_config("toolset") or "2008"
        local outdir = path.join(os.projectdir(), "msvc" .. toolset .. "-portable")
        os.exec("powershell -NoProfile -ExecutionPolicy Bypass -File scripts/04-collect.ps1 -Toolset %s -OutDir \"%s\"", toolset, outdir)
        import("utils.archive")
        local zip = path.join(os.projectdir(), "msvc" .. toolset .. "-portable-win.zip")
        archive.zip(outdir .. "/*", zip)
        print("[OK] pack 完成 -> %s", zip)
    end)

-- ============ 构建自检程序 ============
-- 用绿色包的 clenv.bat 注入环境后调用原生 cl，绕开 xmake 对注册表 VS 探测的依赖
target("hello")
    set_kind("binary")
    add_files("src/hello.cpp")
    on_build(function (target)
        if not is_host("windows") then raise("hello 仅支持 Windows") end
        local toolset = get_config("toolset") or "2008"
        local root = path.join(os.projectdir(), "msvc" .. toolset .. "-portable")
        local clenv = path.join(root, "clenv.bat")
        if not os.isfile(clenv) then raise("未找到 %s，请先 xmake pack", clenv) end
        local obj = path.join(target:targetdir(), "hello.obj")
        local exe = target:targetfile()
        os.mkdir(target:targetdir())
        -- /MT 静态链 CRT，产物不依赖目标机 VC 运行库
        os.exec("cmd /c \"call %s x86 && cl /MT /EHsc /Fe:%s %s\"", clenv, exe, path.join(os.projectdir(), "src/hello.cpp"))
        print("[OK] 编译完成 -> %s", exe)
        os.exec("cmd /c \"%s\"", exe)
    end)
