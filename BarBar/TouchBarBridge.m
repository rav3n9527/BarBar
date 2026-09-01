#import "TouchBarBridge.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#import <stdio.h>

// 加载 DFRFoundation（仅一次）。它提供私有的“系统模态” Touch Bar
// API（与表情选择器 / 音量 HUD 相同的机制）。
static void *BarBarDFRHandle(void) {
    static void *handle = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY);
        if (!handle) {
            fprintf(stderr, "BarBar: dlopen DFRFoundation failed\n");
        }
    });
    return handle;
}

static void *BarBarDFRSymbol(const char *name) {
    void *handle = BarBarDFRHandle();
    if (!handle) return NULL;
    return dlsym(handle, name);
}

void BarBarPresent(NSTouchBar *bar, NSString *identifier) {
    (void)BarBarDFRHandle();

    // 隐藏模态栏上的小 “X” 关闭按钮
    void (*hideClose)(BOOL) = BarBarDFRSymbol("DFRSystemModalShowsCloseBoxWhenFrontMost");
    if (hideClose) hideClose(NO);

    // 注册我们的标识符，以便模态栏可以展示它
    void (*setPresence)(NSString *, BOOL) = BarBarDFRSymbol("DFRElementSetControlStripPresenceForIdentifier");
    if (setPresence) setPresence(identifier, YES);

    Class cls = NSClassFromString(@"NSTouchBar");
    if (!cls) {
        fprintf(stderr, "BarBar: NSTouchBar class not found\n");
        return;
    }

    // 该方法在不同 macOS 版本中曾被重命名——尝试两个 selector。
    SEL sel = NSSelectorFromString(@"presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:");
    if (![cls respondsToSelector:sel]) {
        sel = NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:");
    }
    if (![cls respondsToSelector:sel]) {
        fprintf(stderr, "BarBar: presentSystemModal method not found on this macOS\n");
        return;
    }

    // placement = 1 → 完全接管（替换控制条 + ESC + 其他应用）
    ((void (*)(id, SEL, id, long long, id))objc_msgSend)(cls, sel, bar, 1LL, identifier);
    fprintf(stderr, "BarBar: presented system modal bar (placement=1)\n");
}

void BarBarDismiss(NSTouchBar *bar) {
    Class cls = NSClassFromString(@"NSTouchBar");
    if (!cls) return;

    SEL sel = NSSelectorFromString(@"dismissSystemModalFunctionBar:");
    if (![cls respondsToSelector:sel]) {
        sel = NSSelectorFromString(@"dismissSystemModalTouchBar:");
    }
    if ([cls respondsToSelector:sel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(cls, sel, bar);
    }
}
