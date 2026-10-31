#import "CVirtualDisplay.h"
#import <objc/message.h>

// The classes are private, so they are looked up by name and driven through KVC and objc_msgSend.
// That keeps the build working on any SDK and makes a missing class a clean runtime failure.

void *BooxVirtualDisplayCreate(unsigned int width, unsigned int height, CGDirectDisplayID *displayID) {
    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    if (!descriptorClass || !modeClass || !settingsClass || !displayClass) return NULL;

    id descriptor = [[descriptorClass alloc] init];
    [descriptor setValue:@"Boox" forKey:@"name"];
    [descriptor setValue:@(0xB00C) forKey:@"vendorID"];
    [descriptor setValue:@(0x0001) forKey:@"productID"];
    [descriptor setValue:@(1) forKey:@"serialNum"];
    [descriptor setValue:@(width) forKey:@"maxPixelsWide"];
    [descriptor setValue:@(height) forKey:@"maxPixelsHigh"];
    // About 227 ppi, the Boox panel density.
    CGSize size = CGSizeMake(width / 227.0 * 25.4, height / 227.0 * 25.4);
    [descriptor setValue:[NSValue valueWithBytes:&size objCType:@encode(CGSize)] forKey:@"sizeInMillimeters"];
    [descriptor setValue:dispatch_get_main_queue() forKey:@"queue"];

    id display = ((id (*)(id, SEL, id))objc_msgSend)([displayClass alloc], @selector(initWithDescriptor:), descriptor);
    if (!display) return NULL;

    id mode = ((id (*)(id, SEL, NSUInteger, NSUInteger, double))objc_msgSend)(
        [modeClass alloc], @selector(initWithWidth:height:refreshRate:), width, height, 30.0);
    id settings = [[settingsClass alloc] init];
    [settings setValue:@(0) forKey:@"hiDPI"];
    [settings setValue:@[ mode ] forKey:@"modes"];
    BOOL applied = ((BOOL (*)(id, SEL, id))objc_msgSend)(display, @selector(applySettings:), settings);
    if (!applied) return NULL;

    *displayID = [[display valueForKey:@"displayID"] unsignedIntValue];
    return (__bridge_retained void *)display;
}

void BooxVirtualDisplayDestroy(void *handle) {
    if (!handle) return;
    id display = (__bridge_transfer id)handle;
    (void)display;
}
