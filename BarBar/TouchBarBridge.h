#import <Cocoa/Cocoa.h>

// 通过 @_silgen_name 暴露给 Swift 的 C 函数。它们封装了私有的
// DFRFoundation “系统模态” Touch Bar API，用于接管整个 Touch Bar。

void BarBarPresent(NSTouchBar *bar, NSString *identifier);
void BarBarDismiss(NSTouchBar *bar);
