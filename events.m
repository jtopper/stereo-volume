#import <AppKit/AppKit.h>
#include <Carbon/Carbon.h>
#include <CoreAudio/CoreAudio.h>
#include <string.h>
#include <stdlib.h>

#define NX_SYSDEFINED         14
#define NX_KEYTYPE_SOUND_UP   0
#define NX_KEYTYPE_SOUND_DOWN 1
#define NX_KEYTYPE_MUTE       7

// Returns the current default audio output device name as a malloc'd C string.
// Caller must free(). Returns NULL on error.
char* getDefaultAudioOutputDeviceName() {
    AudioObjectID deviceID;
    UInt32 dataSize = sizeof(AudioObjectID);
    AudioObjectPropertyAddress prop = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &prop, 0, NULL, &dataSize, &deviceID) != noErr) {
        return NULL;
    }

    CFStringRef cfName = NULL;
    dataSize = sizeof(CFStringRef);
    AudioObjectPropertyAddress nameProp = {
        kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    if (AudioObjectGetPropertyData(deviceID, &nameProp, 0, NULL, &dataSize, &cfName) != noErr) {
        return NULL;
    }

    char buf[256];
    CFStringGetCString(cfName, buf, sizeof(buf), kCFStringEncodingUTF8);
    CFRelease(cfName);
    return strdup(buf);
}

// Returns 1 if the key was handled (suppress event), 0 to pass through.
extern int goHandleKey(int keyCode);

CGEventRef eventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    if (type != NX_SYSDEFINED) return event;

    NSEvent *nsEvent = [NSEvent eventWithCGEvent:event];
    if (nsEvent.type != NSEventTypeSystemDefined) return event;
    if (nsEvent.subtype != 8) return event; // 8 = media key subtype
    if (nsEvent.data1 == -1) return event;

    int keyCode  = (nsEvent.data1 & 0xFFFF0000) >> 16;
    int keyFlags = (nsEvent.data1 & 0x0000FFFF);
    int keyDown  = ((keyFlags & 0xFF00) >> 8) == 0xA;

    if (!keyDown) return event;

    if (keyCode == NX_KEYTYPE_SOUND_UP ||
        keyCode == NX_KEYTYPE_SOUND_DOWN ||
        keyCode == NX_KEYTYPE_MUTE) {
        if (goHandleKey(keyCode)) return NULL; // handled — suppress
        return event;                           // not our device — pass through
    }

    return event;
}

void runEventTap() {
    CGEventMask mask = CGEventMaskBit(NX_SYSDEFINED);
    CFMachPortRef tap = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        mask,
        eventCallback,
        NULL
    );
    if (!tap) return;

    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    CGEventTapEnable(tap, true);
    CFRunLoopRun();
}
