// 便携包自检程序：输出实际 _MSC_VER，验证工具链可用
#include <stdio.h>
int main() {
#if defined(_M_X64)
    const char* arch = "x64";
#elif defined(_M_IX86)
    const char* arch = "x86";
#else
    const char* arch = "unknown";
#endif
    printf("hello from msvc portable, arch=%s, compiler ver. %d\n", arch, _MSC_VER);
    return 0;
}
