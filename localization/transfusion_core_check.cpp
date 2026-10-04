#include <windows.h>
#include <cstdio>
#include <cwchar>
#include "transfusion/addon_api.h"
int main(int argc,char** argv) {
    if(argc!=2)return 1;
    HMODULE core=LoadLibraryA(argv[1]);
    if(!core){printf("Load failed: %lu\n",GetLastError());return 2;}
    auto path=reinterpret_cast<DLSSGTGetConfigPathFn>(GetProcAddress(core,DLSSGT_EXPORT_GET_CONFIG_PATH));
    auto status=reinterpret_cast<DLSSGTGetStatusFn>(GetProcAddress(core,DLSSGT_EXPORT_GET_STATUS));
    auto capture=reinterpret_cast<DLSSGTSetHotkeyCaptureFn>(GetProcAddress(core,DLSSGT_EXPORT_SET_HOTKEY_CAPTURE));
    if(!path||!status||!capture)return 3;
    wchar_t buffer[2048]{};
    uint32_t length=0;
    for(int i=0;i<50 && !length;++i){length=path(buffer,2048);if(!length)Sleep(100);}
    wprintf(L"Config: %ls (length %u)\n",buffer,length);
    if(!length||!wcsstr(buffer,L"OptiScaler\\plugins\\DLSSG-Transfusion.json"))return 4;
    DLSSGTStatus state{};state.size=sizeof(state);state.version=DLSSGT_ADDON_API_VERSION;
    if(!status(&state))return 5;
    capture(1);capture(0);
    printf("Official ASI loaded; API v%u and plugin configuration path verified. Game rendering not tested.\n",DLSSGT_ADDON_API_VERSION);
}
