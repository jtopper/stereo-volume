#import <AppKit/AppKit.h>
#include <stdlib.h>

// showConfigDialog presents a modal preferences dialog on the main thread.
// audioDevices / castDevices are arrays of C strings (not freed here).
// On Save, *outAudio and *outCast are set to malloc'd copies of the selections.
// Returns 1 if the user saved, 0 if they cancelled.
int showConfigDialog(
    char **audioDevices, int audioCount,
    char **castDevices,  int castCount,
    const char *currentAudio, const char *currentCast,
    char **outAudio, char **outCast
) {
    __block int   result   = 0;
    __block char *selAudio = NULL;
    __block char *selCast  = NULL;

    dispatch_sync(dispatch_get_main_queue(), ^{
        NSAlert *alert        = [[NSAlert alloc] init];
        alert.messageText     = @"stereo-vol Preferences";
        alert.informativeText = @"Select the audio output and Chromecast device to control.";
        [alert addButtonWithTitle:@"Save"];
        [alert addButtonWithTitle:@"Cancel"];

        NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 390, 72)];

        // Row 1 — audio output
        NSTextField *audioLabel = [NSTextField labelWithString:@"Audio Output:"];
        audioLabel.frame     = NSMakeRect(0, 46, 112, 22);
        audioLabel.alignment = NSTextAlignmentRight;

        NSPopUpButton *audioPopup = [[NSPopUpButton alloc]
            initWithFrame:NSMakeRect(120, 44, 270, 26) pullsDown:NO];
        if (audioCount > 0) {
            for (int i = 0; i < audioCount; i++)
                [audioPopup addItemWithTitle:@(audioDevices[i])];
            if (currentAudio && strlen(currentAudio) > 0)
                [audioPopup selectItemWithTitle:@(currentAudio)];
        } else {
            [audioPopup addItemWithTitle:@"No audio output devices found"];
            audioPopup.enabled = NO;
        }

        // Row 2 — Chromecast
        NSTextField *castLabel = [NSTextField labelWithString:@"Chromecast:"];
        castLabel.frame     = NSMakeRect(0, 10, 112, 22);
        castLabel.alignment = NSTextAlignmentRight;

        NSPopUpButton *castPopup = [[NSPopUpButton alloc]
            initWithFrame:NSMakeRect(120, 8, 270, 26) pullsDown:NO];
        if (castCount > 0) {
            for (int i = 0; i < castCount; i++)
                [castPopup addItemWithTitle:@(castDevices[i])];
            if (currentCast && strlen(currentCast) > 0)
                [castPopup selectItemWithTitle:@(currentCast)];
        } else {
            [castPopup addItemWithTitle:@"No Chromecast devices found"];
            castPopup.enabled = NO;
        }

        [box addSubview:audioLabel];
        [box addSubview:audioPopup];
        [box addSubview:castLabel];
        [box addSubview:castPopup];
        alert.accessoryView = box;
        [alert layout];

        if ([alert runModal] == NSAlertFirstButtonReturn) {
            result = 1;
            NSString *a = [audioPopup titleOfSelectedItem];
            NSString *c = [castPopup  titleOfSelectedItem];
            if (a) selAudio = strdup([a UTF8String]);
            if (c) selCast  = strdup([c UTF8String]);
        }
    });

    *outAudio = selAudio;
    *outCast  = selCast;
    return result;
}
