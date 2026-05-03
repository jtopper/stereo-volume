#import <AppKit/AppKit.h>
#include <stdlib.h>

extern void goConfigResult(int saved, const char *audio, const char *cast);

// Controls that need updating after the dialog is open.
static NSWindow            *configWindow = nil;
static NSPopUpButton       *audioPopup   = nil;
static NSPopUpButton       *castPopup    = nil;
static NSProgressIndicator *castSpinner  = nil;
static NSTextField         *castStatus   = nil;
static NSButton            *saveButton   = nil;
static NSString            *pendingCast  = nil; // current cast name, for pre-selection

// ── Delegate ──────────────────────────────────────────────────────────────

@interface ConfigDelegate : NSObject <NSWindowDelegate>
+ (instancetype)shared;
- (void)saveClicked:(id)sender;
- (void)cancelClicked:(id)sender;
@end

static ConfigDelegate *configDelegate = nil;

@implementation ConfigDelegate
+ (instancetype)shared {
    if (!configDelegate) configDelegate = [[ConfigDelegate alloc] init];
    return configDelegate;
}
- (void)saveClicked:(id)sender {
    if (!configWindow) return;
    const char *audio = [[audioPopup titleOfSelectedItem] UTF8String];
    const char *cast  = [[castPopup  titleOfSelectedItem] UTF8String];
    NSWindow *win = configWindow;
    configWindow  = nil;
    [NSApp stopModal];
    [win orderOut:nil];
    goConfigResult(1, audio ?: "", cast ?: "");
}
- (void)cancelClicked:(id)sender {
    if (!configWindow) return;
    NSWindow *win = configWindow;
    configWindow  = nil;
    [NSApp stopModal];
    [win orderOut:nil];
    goConfigResult(0, NULL, NULL);
}
// X button — treat as Cancel.
- (BOOL)windowShouldClose:(NSWindow *)win {
    [self cancelClicked:nil];
    return NO; // we already hid it
}
@end

// ── Phase 1: open immediately with audio populated, cast loading ───────────

void openConfigDialog(char **audioDevices, int audioCount,
                      const char *curAudio, const char *curCast) {
    if (configWindow) return; // guard against double-open

    // Convert C strings to ObjC objects before dispatching.
    NSMutableArray *audioArr = [NSMutableArray arrayWithCapacity:audioCount];
    for (int i = 0; i < audioCount; i++) [audioArr addObject:@(audioDevices[i])];
    NSString *curAudioStr = curAudio && *curAudio ? @(curAudio) : @"";
    pendingCast           = curCast  && *curCast  ? @(curCast)  : @"";

    dispatch_async(dispatch_get_main_queue(), ^{
        if (configWindow) return;

        NSWindow *win = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 430, 150)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
            backing:NSBackingStoreBuffered
            defer:NO];
        win.title    = @"stereo-vol Preferences";
        win.delegate = [ConfigDelegate shared];
        [win center];
        NSView *cv = win.contentView;

        // ── Audio Output row ─────────────────────────────────────────────
        NSTextField *al = [NSTextField labelWithString:@"Audio Output:"];
        al.frame = NSMakeRect(20, 105, 114, 22);
        al.alignment = NSTextAlignmentRight;
        [cv addSubview:al];

        audioPopup = [[NSPopUpButton alloc]
            initWithFrame:NSMakeRect(142, 103, 268, 26) pullsDown:NO];
        if (audioArr.count > 0) {
            for (NSString *n in audioArr) [audioPopup addItemWithTitle:n];
            if (curAudioStr.length > 0) [audioPopup selectItemWithTitle:curAudioStr];
        } else {
            [audioPopup addItemWithTitle:@"No audio output devices found"];
            audioPopup.enabled = NO;
        }
        [cv addSubview:audioPopup];

        // ── Chromecast row — loading state ───────────────────────────────
        NSTextField *cl = [NSTextField labelWithString:@"Chromecast:"];
        cl.frame = NSMakeRect(20, 65, 114, 22);
        cl.alignment = NSTextAlignmentRight;
        [cv addSubview:cl];

        castSpinner = [[NSProgressIndicator alloc]
            initWithFrame:NSMakeRect(142, 67, 16, 16)];
        castSpinner.style       = NSProgressIndicatorStyleSpinning;
        castSpinner.controlSize = NSControlSizeSmall;
        [castSpinner startAnimation:nil];
        [cv addSubview:castSpinner];

        castStatus = [NSTextField labelWithString:@"Discovering Chromecast devices…"];
        castStatus.frame     = NSMakeRect(164, 67, 246, 18);
        castStatus.textColor = [NSColor secondaryLabelColor];
        castStatus.font      = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        [cv addSubview:castStatus];

        // Hidden dropdown; shown and populated by populateConfigDialogCast.
        castPopup = [[NSPopUpButton alloc]
            initWithFrame:NSMakeRect(142, 63, 268, 26) pullsDown:NO];
        castPopup.hidden = YES;
        [cv addSubview:castPopup];

        // ── Buttons ──────────────────────────────────────────────────────
        NSButton *cancelBtn = [NSButton
            buttonWithTitle:@"Cancel"
            target:[ConfigDelegate shared]
            action:@selector(cancelClicked:)];
        cancelBtn.frame         = NSMakeRect(252, 16, 80, 28);
        cancelBtn.keyEquivalent = @"\e";
        [cv addSubview:cancelBtn];

        saveButton = [NSButton
            buttonWithTitle:@"Save"
            target:[ConfigDelegate shared]
            action:@selector(saveClicked:)];
        saveButton.frame         = NSMakeRect(340, 16, 70, 28);
        saveButton.keyEquivalent = @"\r";
        saveButton.enabled       = NO; // enabled by populateConfigDialogCast
        [cv addSubview:saveButton];

        configWindow = win;
        [NSApp runModalForWindow:win];
    });
}

// postToMain schedules a block on the main run loop in both the default and
// modal-panel modes. dispatch_async(main_queue) alone won't fire during an
// NSApp modal session because NSModalPanelRunLoopMode is not in common modes.
static void postToMain(dispatch_block_t block) {
    __block BOOL executed = NO;
    dispatch_block_t once = ^{ if (!executed) { executed = YES; block(); } };
    CFRunLoopRef rl = CFRunLoopGetMain();
    CFRunLoopPerformBlock(rl, kCFRunLoopDefaultMode, once);
    CFRunLoopPerformBlock(rl, (__bridge CFStringRef)NSModalPanelRunLoopMode, once);
    CFRunLoopWakeUp(rl);
}

// ── Phase 2: called once Chromecast discovery finishes ────────────────────

void populateConfigDialogCast(char **castDevices, int castCount, const char *curCast) {
    NSMutableArray *castArr = [NSMutableArray arrayWithCapacity:castCount];
    for (int i = 0; i < castCount; i++) [castArr addObject:@(castDevices[i])];
    NSString *curCastStr = curCast && *curCast ? @(curCast) : pendingCast;

    postToMain(^{
        if (!configWindow) return; // dismissed during discovery

        [castSpinner stopAnimation:nil];
        castSpinner.hidden = YES;
        castStatus.hidden  = YES;
        castPopup.hidden   = NO;

        [castPopup removeAllItems];
        if (castArr.count > 0) {
            for (NSString *n in castArr) [castPopup addItemWithTitle:n];
            if (curCastStr.length > 0) [castPopup selectItemWithTitle:curCastStr];
            castPopup.enabled = YES;
            saveButton.enabled = YES;
        } else {
            [castPopup addItemWithTitle:@"No Chromecast devices found"];
            castPopup.enabled  = NO;
            saveButton.enabled = NO;
        }
    });
}
