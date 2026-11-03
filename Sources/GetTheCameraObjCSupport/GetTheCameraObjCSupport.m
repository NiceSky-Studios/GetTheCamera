#import "GetTheCameraObjCSupport.h"

@implementation GetTheCameraExceptionCatcher

+ (BOOL)catchException:(__attribute__((noescape)) void (^)(void))block
                 error:(NSError *_Nullable *_Nullable)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo = [NSMutableDictionary dictionary];
            userInfo[NSLocalizedDescriptionKey] = exception.reason ?: exception.name;
            userInfo[@"GetTheCameraExceptionName"] = exception.name;
            if (exception.userInfo != nil) {
                userInfo[@"GetTheCameraExceptionUserInfo"] = exception.userInfo;
            }
            *error = [NSError errorWithDomain:@"GetTheCameraObjCException" code:0 userInfo:userInfo];
        }
        return NO;
    }
}

@end

@implementation GetTheCameraStreamStopObserver

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    (void)stream;

    // `SCStreamDelegate` annotates this parameter nonnull, which is precisely the
    // promise the framework breaks. Copy it into a nullable local so the nil check
    // below is legal — nullability is a compile-time annotation only, so nothing
    // stops a null pointer from arriving here at runtime.
    NSError *_Nullable received = error;

    NSString *reason = nil;
    if (received != nil) {
        // Read the error here, synchronously, and build an independent string
        // from it. The framework may release the error as soon as this returns,
        // so nothing may hold on to it past this point.
        reason = [NSString stringWithFormat:@"%@ (%@ %ld)",
                                            received.localizedDescription,
                                            received.domain,
                                            (long)received.code];
    }

    void (^handler)(NSString *_Nullable) = self.onStop;
    if (handler != nil) {
        handler(reason);
    }
}

@end
