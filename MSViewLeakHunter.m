//
//  MSViewLeakHunter.m
//  MindSnacks
//
//  Created by Javier Soto on 12/7/12.
//
//

#import "MSViewLeakHunter.h"

#import "MSLeakHunter+Private.h"

#if MSLeakHunter_ENABLED

#if MSViewLeakHunter_ENABLED

@interface UIView (MSViewLeakHunter)

- (void)_msviewLeakHunter_didMoveToSuperview;
- (void)_msviewLeakHunter_dealloc;
- (BOOL)ms_isLeaked;
@property (nonatomic, readonly) UIViewController *viewController;

@end

@implementation MSViewLeakHunter

+ (void)install
{
    Class class = [UIView class];

    [MSLeakHunter swizzleMethod:@selector(didMoveToSuperview)
                        ofClass:class
                     withMethod:@selector(_msviewLeakHunter_didMoveToSuperview)];

    [MSLeakHunter swizzleMethod:NSSelectorFromString(@"dealloc")
                        ofClass:class
                     withMethod:@selector(_msviewLeakHunter_dealloc)];
}

@end

@implementation UIView (MSViewLeakHunter)

@dynamic viewController;

/**
 * @return a string that identifies the controller. This is used to be pased to `MSVCLeakHunter` without retaining the controller.
 */
- (NSString *)viewReferenceString
{
    return [NSString stringWithFormat:@"VIEW:\n%@ <%p>", NSStringFromClass([self class]), self];
}

- (void)cancelLeakCheck
{
    [MSLeakHunter cancelLeakNotificationWithObjectReferenceString:[self viewReferenceString]];
}

- (void)_msviewLeakHunter_didMoveToSuperview
{
    if (!self.superview)
    {
        [MSLeakHunter scheduleLeakNotificationWithObjectReferenceString:[self viewReferenceString]
                                                            weakPointer:self
                                                             afterDelay:kMSViewLeakHunterDisappearAndDeallocateMaxInterval];
    }
    else
    {
        [self cancelLeakCheck];
    }
    
    // Call original implementation
    [self _msviewLeakHunter_didMoveToSuperview];
}

- (void)_msviewLeakHunter_dealloc
{
    [self cancelLeakCheck];

    // Call original implementation
    [self _msviewLeakHunter_dealloc];

}

- (BOOL)ms_isLeaked
{
    if (!self.superview && !self.viewController)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}

- (NSString *)ms_additionalDescription
{
    if ([self respondsToSelector:@selector(recursiveDescription)])
    {
        return [self performSelector:@selector(recursiveDescription)];
    }
    return nil;
}

- (UIViewController *)viewController
{
    if ([self.nextResponder isKindOfClass:UIViewController.class])
        return (UIViewController *)self.nextResponder;
    else
        return nil;
}

@end

#endif 

#endif