#include "quickjs-libc.h"

typedef char *(*VosModuleNormalizeFunc)(void *, const char *, const char *, void *);

void vos_set_module_loader(void *runtime_handle, VosModuleNormalizeFunc normalize) {
    JSRuntime *runtime = *(JSRuntime **)runtime_handle;
    JS_SetModuleLoaderFunc(runtime, (JSModuleNormalizeFunc *)normalize, js_module_loader, NULL);
}

char *vos_js_strdup(void *context, const char *value) {
    return js_strdup((JSContext *)context, value);
}
