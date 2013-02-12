//
//  MSLeakHunter.m
//  MindSnacks
//
//  Created by Javier Soto on 11/16/12.
//
//

#import "MSLeakHunter.h"

#import <objc/runtime.h>

@interface NSObject (MSLeakHunter)
@property (nonatomic, readonly) BOOL ms_isLeaked;
@property (nonatomic, readonly) NSString *ms_additionalDescription;
@property (nonatomic, readonly) BOOL shouldBePreventedFromBeingMarkedAsLeaked;
@end

@implementation NSObject (MSLeakHunter)
@dynamic ms_isLeaked;
@dynamic ms_additionalDescription;
@dynamic shouldBePreventedFromBeingMarkedAsLeaked;
@end


// This is hacky and relies on a "deprecated" (althought the documentation isn't updated saying so) method. What's the alternative?
static inline void ms_dispatch_sync_safe(dispatch_queue_t dispatchQueue, dispatch_block_t block)
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (dispatch_get_current_queue() == dispatchQueue)
    {
#pragma clang diagnostic pop
        block();
    }
    else
    {
        dispatch_sync(dispatchQueue, block);
    }
}

#if MSLeakHunter_ENABLED

/**
 * @discussion this queue lets us ensure that the calls to `performSector:...` and `cancelPrevious...`
 * are always made in the same run loop.
 */
static dispatch_queue_t _msLeakHunterQueue = nil;

static NSMutableDictionary *_msLeakHunterHashTables = nil;

@implementation MSLeakHunter

+ (void)initialize
{
    if ([self class] == [MSLeakHunter class])
    {
        _msLeakHunterQueue = dispatch_queue_create("com.mindsnacks.leakhunter", DISPATCH_QUEUE_SERIAL);
        _msLeakHunterHashTables = [NSMutableDictionary dictionary];
    }
}

+ (MSLeakHunter *)sharedInstance
{
    static MSLeakHunter *sharedInstance = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[MSLeakHunter alloc] init];
    });

    return sharedInstance;
}

- (void)objectLeakedWithReferenceString:(NSString *)referenceString
{
    NSHashTable *weakHashTable = _msLeakHunterHashTables[referenceString];
    __weak NSObject *object = [weakHashTable anyObject];
    if (object)
    {
        if ([object respondsToSelector:@selector(ms_isLeaked)])
        {
            if ([object ms_isLeaked] == NO)
            {
                return;
            }
        }
        
        if ([object respondsToSelector:@selector(shouldBePreventedFromBeingMarkedAsLeaked)])
        {
            if ([object shouldBePreventedFromBeingMarkedAsLeaked])
            {
                return;
            }
        }
        
        NSString *description = [NSString stringWithFormat:@"[%@] POSSIBLE LEAK OF %@", NSStringFromClass([self class]), referenceString];
        
        if ([object respondsToSelector:@selector(ms_additionalDescription)])
        {
            description = [description stringByAppendingFormat:@" %@", [object ms_additionalDescription]];
        }
        
        NSLog(@"\n%@\n", description);
    }
}

+ (void)installLeakHunter:(Class<MSLeakHunter>)leakHunter
{
    [leakHunter install];
}

#pragma mark - Swizzling

+ (void)swizzleMethod:(SEL)aOriginalMethod
              ofClass:(Class)class
           withMethod:(SEL)aNewMethod
{
    Method oldMethod = class_getInstanceMethod(class, aOriginalMethod);
    Method newMethod = class_getInstanceMethod(class, aNewMethod);

    method_exchangeImplementations(oldMethod, newMethod);
}

#pragma mark - Checking

+ (void)scheduleLeakNotificationWithObjectReferenceString:(NSString *)referenceString
                                              weakPointer:(__weak NSObject *)weakPointer
                                               afterDelay:(NSTimeInterval)delay
{
    NSHashTable *weakHashTable = [NSHashTable weakObjectsHashTable];
    [weakHashTable addObject:weakPointer];
    
    // Ensure we always run these methods on the same thread
    ms_dispatch_sync_safe(_msLeakHunterQueue, ^{
        _msLeakHunterHashTables[referenceString] = weakHashTable;
        // Cancel previous ones just in case to avoid multiple calls.
        [self cancelLeakNotificationWithObjectReferenceString:referenceString];

        [[self sharedInstance] performSelector:@selector(objectLeakedWithReferenceString:)
                                    withObject:referenceString
                                    afterDelay:delay];
    });
}

+ (void)cancelLeakNotificationWithObjectReferenceString:(NSString *)referenceString
{
    ms_dispatch_sync_safe(_msLeakHunterQueue, ^{
        [self cancelPreviousPerformRequestsWithTarget:[self sharedInstance]
                                             selector:@selector(objectLeakedWithReferenceString:)
                                               object:referenceString];
    });
}

@end

#endif