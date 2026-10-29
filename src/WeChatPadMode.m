#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
static BOOL padMode(id self, SEL cmd) { return YES; }
static BOOL phoneLayout(id self, SEL cmd) { return NO; }
static void hookBoolClassMethod(Class cls, const char *name, IMP replacement) {
    Method m = class_getClassMethod(cls, sel_registerName(name));
    const char *type = m ? method_getTypeEncoding(m) : NULL;
    if (m && type && (type[0] == 'B' || type[0] == 'c')) method_setImplementation(m, replacement);
}
static BOOL installed = NO;
static void installPadMode(void) {
    if (installed) return;
    Class device = objc_getClass("DeviceInfo");
    Method method = device ? class_getClassMethod(device, sel_registerName("isiPad")) : NULL;
    if (!method) { NSLog(@"[LocalPadMode] DeviceInfo.isiPad unavailable"); return; }
    const char *type = method_getTypeEncoding(method);
    if (!type || (type[0] != 'B' && type[0] != 'c')) {
        NSLog(@"[LocalPadMode] Unexpected method signature"); return;
    }
    method_setImplementation(method, (IMP)padMode);
    // Keep tablet authentication while disabling the tablet-only UI routing.
    hookBoolClassMethod(device, "isSupportSplitView", (IMP)phoneLayout);
    hookBoolClassMethod(device, "canUseInAppSplitView", (IMP)phoneLayout);
    installed = YES;
    NSLog(@"[LocalPadMode] DeviceInfo.isiPad enabled");
}
__attribute__((constructor)) static void initializePadMode(void) {
    @autoreleasepool {
        installPadMode();
        if (!installed) dispatch_async(dispatch_get_main_queue(), ^{ installPadMode(); });
    }
}

// Temporary on-device UI metadata; deliberately excludes labels, text and account data.
static NSString *diagnosticsDirectory(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/LocalPadDiagnostics"];
}
static NSArray *rectNumbers(CGRect r) { return @[@(r.origin.x),@(r.origin.y),@(r.size.width),@(r.size.height)]; }
static NSString *viewPath(UIView *v) {
    NSMutableArray *parts = [NSMutableArray array];
    for (UIView *p = v; p && parts.count < 40; p = p.superview) {
        NSUInteger index = p.superview ? [p.superview.subviews indexOfObjectIdenticalTo:p] : 0;
        [parts insertObject:[NSString stringWithFormat:@"%@[%lu]",NSStringFromClass(p.class),(unsigned long)index] atIndex:0];
    }
    return [parts componentsJoinedByString:@"/"];
}
static void collectViews(UIView *v, UIWindow *w, NSMutableArray *rows, NSUInteger depth) {
    if (depth > 40 || rows.count > 2500) return;
    CGRect r = [v convertRect:v.bounds toView:w];
    NSString *controller = @"";
    for (UIResponder *p=v.nextResponder; p; p=p.nextResponder) {
        if ([p isKindOfClass:UIViewController.class]) { controller=NSStringFromClass(p.class); break; }
    }
    NSMutableArray *gestures = [NSMutableArray array];
    for (UIGestureRecognizer *g in v.gestureRecognizers) [gestures addObject:NSStringFromClass(g.class)];
    [rows addObject:@{@"path":viewPath(v),@"class":NSStringFromClass(v.class),@"frame":rectNumbers(r),
        @"localFrame":rectNumbers(v.frame),@"bounds":rectNumbers(v.bounds),@"hidden":@(v.hidden),
        @"alpha":@(v.alpha),@"interaction":@(v.userInteractionEnabled),@"controller":controller,
        @"gestures":gestures,@"children":@(v.subviews.count),@"z":@(v.layer.zPosition),
        @"safeBottom":@(v.safeAreaInsets.bottom)}];
    for (UIView *child in v.subviews) collectViews(child,w,rows,depth+1);
}

static void saveLayoutDiagnostics(void) {
    UIApplication *app=UIApplication.sharedApplication;
    if (app.applicationState!=UIApplicationStateActive) return;
    NSMutableArray *windows=[NSMutableArray array];
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.hidden || w.alpha<0.01) continue;
            NSMutableArray *rows=[NSMutableArray array],*hits=[NSMutableArray array];
            collectViews(w,w,rows,0);
            CGFloat h=w.bounds.size.height, width=w.bounds.size.width;
            for (NSNumber *dy in @[@20,@40,@60,@80,@100]) {
                for (int i=0;i<4;i++) {
                    CGPoint pt=CGPointMake(width*(i+0.5)/4,h-dy.doubleValue);
                    UIView *hit=[w hitTest:pt withEvent:nil];
                    [hits addObject:@{@"point":@[@(pt.x),@(pt.y)],@"view":hit?viewPath(hit):@"nil"}];
                }
            }
            [windows addObject:@{@"class":NSStringFromClass(w.class),@"level":@(w.windowLevel),@"key":@(w.keyWindow),@"rows":rows,@"hits":hits}];
        }
    }
    NSString *dir=diagnosticsDirectory();
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"time":@(NSDate.date.timeIntervalSince1970),@"windows":windows} options:0 error:nil];
    [json writeToFile:[dir stringByAppendingPathComponent:@"latest.json"] atomically:YES];
}


// Only restore the observed sibling order in WeChat's main tab controller.
// Do not hide either tab bar: WeChat propagates UIKit's hidden state to its own bar.
static __weak UIViewController *mainController;
static BOOL repairEnabled=YES, diagnosticsEnabled=NO;
static void repairTabOrder(UIViewController *controller) {
    Class mainClass=objc_getClass("MainTabBarViewController");
    if (!repairEnabled || !mainClass || ![controller isKindOfClass:mainClass] ||
        !controller.isViewLoaded || !controller.view.window) return;
    mainController=controller;
    UIView *native=nil,*custom=nil;
    for (UIView *v in controller.view.subviews) {
        NSString *name=NSStringFromClass(v.class);
        if ([name isEqualToString:@"UITabBar"]) native=v;
        if ([name isEqualToString:@"MMTabBar"]) custom=v;
    }
    if (!native || !custom || native.hidden || custom.hidden || !CGRectIntersectsRect(native.frame,custom.frame)) return;
    NSArray *children=controller.view.subviews;
    if ([children indexOfObjectIdenticalTo:native]>[children indexOfObjectIdenticalTo:custom])
        [controller.view insertSubview:custom aboveSubview:native];
}
static IMP originalLayout,originalAppearance;
static void fixedLayout(UIViewController *self,SEL cmd) {
    ((void(*)(id,SEL))originalLayout)(self,cmd);
    repairTabOrder(self);
}
static void fixedAppearance(UIViewController *self,SEL cmd,BOOL animated) {
    ((void(*)(id,SEL,BOOL))originalAppearance)(self,cmd,animated);
    repairTabOrder(self);
    dispatch_async(dispatch_get_main_queue(),^{repairTabOrder(self);});
}
static void installInstanceHook(Class cls,SEL sel,IMP replacement,IMP *original) {
    Method method=class_getInstanceMethod(cls,sel);
    if (!method) return;
    *original=method_getImplementation(method);
    if (!class_addMethod(cls,sel,replacement,method_getTypeEncoding(method))) method_setImplementation(method,replacement);
}
__attribute__((constructor)) static void initializeTabRepair(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        Class cls=objc_getClass("MMTabBarController");
        if (!cls) return;
        installInstanceHook(cls,@selector(viewDidLayoutSubviews),(IMP)fixedLayout,&originalLayout);
        installInstanceHook(cls,@selector(viewDidAppear:),(IMP)fixedAppearance,&originalAppearance);
        __block NSUInteger ticks=0;
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer){
            if (UIApplication.sharedApplication.applicationState!=UIApplicationStateActive) return;
            // UIKit may reorder the siblings after the transition's layout callbacks.
            // This check touches only the main controller's immediate children and
            // does nothing when their order is already correct.
            repairTabOrder(mainController);
            if (++ticks%6) return;
            NSData *data=[NSData dataWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/LocalPadLayout.json"]];
            NSDictionary *config=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
            if ([config isKindOfClass:NSDictionary.class]) {
                repairEnabled=config[@"repairEnabled"]?[config[@"repairEnabled"] boolValue]:YES;
                diagnosticsEnabled=config[@"diagnosticsEnabled"]?[config[@"diagnosticsEnabled"] boolValue]:NO;
            }
            if (diagnosticsEnabled) saveLayoutDiagnostics();
        }];
    });
}
