#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Creates a virtual display through the private CGVirtualDisplay classes (the same ones DeskPad and
/// BetterDisplay use). Returns a retained opaque handle, or NULL if the classes are missing or the
/// system rejects the settings. The display disappears when the handle is destroyed.
void *_Nullable BooxVirtualDisplayCreate(unsigned int width, unsigned int height, CGDirectDisplayID *displayID);

void BooxVirtualDisplayDestroy(void *handle);

NS_ASSUME_NONNULL_END
