// Runs inside the iOS Simulator (via `xcrun simctl spawn`) and posts the same
// vendor-defined HID event that the hidden hinge slider in Xcode's Device Hub sends.
// It also reads the current angle back from CoreMotion.
//
//   hinge_helper set <degrees>
//   hinge_helper sweep <from> <to> <seconds>
//   hinge_helper orient <portrait|landscape-left|landscape-right|pud>
//   hinge_helper get

#import <Foundation/Foundation.h>

#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

extern IOHIDEventRef IOHIDEventCreateVendorDefinedEvent(CFAllocatorRef allocator, uint64_t timeStamp,
    uint32_t usagePage, uint32_t usage, uint32_t version, const uint8_t *data, CFIndex length, uint32_t options);
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreateWithType(CFAllocatorRef allocator, int type,
    CFDictionaryRef properties);
extern void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef client, IOHIDEventRef event);
extern CFDataRef IOCFSerialize(CFTypeRef object, CFOptionFlags options);

enum {
    kUsagePage = 0xFF61,
    kUsage = 0x5B,
    kClientTypeSimple = 4,
    kSerializeBinary = 1,
    kSweepHz = 60,
};

// Seconds to wait for the first angle update before giving up.
static const CFTimeInterval kAngleTimeout = 2;

// CoreMotion's private angle API, the same source UIKit's UIHinge reads.
@interface CMAngle : NSObject
- (float)angleDegrees;
@end

@interface CMAngleManager : NSObject
+ (BOOL)isAvailable;
- (void)startAngleUpdatesToQueue:(NSOperationQueue *)queue handler:(void (^)(CMAngle *angle))handler;
- (void)stopAngleUpdates;
@end

// Serializes the payload and dispatches it as the vendor-defined event Device Hub uses.
static void send_payload(IOHIDEventSystemClientRef client, CFStringRef provider, CFStringRef source,
    CFStringRef type, CFTypeRef value) {
    const void *keys[] = {CFSTR("provider"), CFSTR("source"), CFSTR("type"), CFSTR("value")};
    const void *values[] = {provider, source, type, value};
    CFDictionaryRef payload = CFDictionaryCreate(NULL, keys, values, 4,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDataRef data = IOCFSerialize(payload, kSerializeBinary);

    if (data) {
        IOHIDEventRef event = IOHIDEventCreateVendorDefinedEvent(NULL, mach_absolute_time(), kUsagePage, kUsage, 0,
            CFDataGetBytePtr(data), CFDataGetLength(data), 0);
        if (event) {
            IOHIDEventSystemClientDispatchEvent(client, event);
            CFRelease(event);
        }
        CFRelease(data);
    }
    CFRelease(payload);
}

static void send_angle(IOHIDEventSystemClientRef client, double degrees) {
    if (degrees < 0) degrees = 0;
    if (degrees > 180) degrees = 180;

    CFNumberRef value = CFNumberCreate(NULL, kCFNumberDoubleType, &degrees);
    send_payload(client, CFSTR("com.apple.Virtualization"), CFSTR("hinge-slider-control"), CFSTR("range"), value);
    CFRelease(value);
}

// Same event as Device Hub's Controls > Rotate Left/Right, which sends the absolute target orientation.
static void send_orientation(IOHIDEventSystemClientRef client, const char *orientation) {
    CFStringRef value = CFStringCreateWithCString(NULL, orientation, kCFStringEncodingUTF8);
    send_payload(client, CFSTR("com.apple.Virtualization.VirtualMachines"), CFSTR("orientation-picker-control"),
        CFSTR("enum"), value);
    CFRelease(value);
}

// Prints the current angle. CoreMotion delivers the first update right away, without waiting for a change.
static int print_angle(void) {
    Class managerClass = NSClassFromString(@"CMAngleManager");
    if (!managerClass || ![managerClass isAvailable]) {
        fprintf(stderr, "hinge_helper: this simulator reports no hinge\n");
        return 1;
    }

    id manager = [[managerClass alloc] init];

    __block bool printed = false;
    [manager startAngleUpdatesToQueue:[NSOperationQueue new] handler:^(CMAngle *angle) {
        if (printed) return;
        printed = true;
        printf("%.1f\n", [angle angleDegrees]);
        CFRunLoopStop(CFRunLoopGetMain());
    }];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, kAngleTimeout, false);
    [manager stopAngleUpdates];

    if (!printed) fprintf(stderr, "hinge_helper: timed out reading the hinge angle\n");
    return printed ? 0 : 1;
}

static int usage(void) {
    fprintf(stderr, "usage: hinge_helper set <degrees>\n"
                    "       hinge_helper sweep <from> <to> <seconds>\n"
                    "       hinge_helper orient <orientation>\n"
                    "       hinge_helper get\n");
    return 64;
}

int main(int argc, char **argv) {
    if (argc < 2) return usage();
    if (strcmp(argv[1], "get") == 0 && argc == 2) return print_angle();
    if (argc < 3) return usage();

    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreateWithType(NULL, kClientTypeSimple, NULL);
    if (!client) {
        fprintf(stderr, "hinge_helper: failed to create HID event system client\n");
        return 1;
    }

    if (strcmp(argv[1], "set") == 0 && argc == 3) {
        send_angle(client, atof(argv[2]));
    } else if (strcmp(argv[1], "orient") == 0 && argc == 3) {
        send_orientation(client, argv[2]);
    } else if (strcmp(argv[1], "sweep") == 0 && argc == 5) {
        double from = atof(argv[2]), to = atof(argv[3]), seconds = fmax(atof(argv[4]), 0);
        int steps = (int)fmax(1, round(seconds * kSweepHz));
        for (int i = 0; i <= steps; i++) {
            send_angle(client, from + (to - from) * i / steps);
            if (i < steps) usleep((useconds_t)(seconds * 1e6 / steps));
        }
    } else {
        return usage();
    }

    // Give the event system a moment to deliver before the process exits.
    usleep(100000);
    return 0;
}
