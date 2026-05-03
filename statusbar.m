#import <AppKit/AppKit.h>
#include <math.h>

// ── Go callbacks ──────────────────────────────────────────────────────────
extern void goSliderChanged(float value);
extern void goMenuClicked(int tag);  // 1=mute  2=prefs  3=quit

// ── Volume slider view ────────────────────────────────────────────────────

@interface VolumeSliderView : NSView
@property (nonatomic, strong) NSSlider    *slider;
@property (nonatomic, strong) NSTextField *pctLabel;
- (void)setVolume:(float)vol label:(NSString *)label;
@end

@implementation VolumeSliderView

- (instancetype)init {
    // 220 × 26 fits comfortably as a menu item.
    self = [super initWithFrame:NSMakeRect(0, 0, 220, 26)];
    if (!self) return nil;

    _slider = [[NSSlider alloc] initWithFrame:NSMakeRect(8, 5, 166, 16)];
    _slider.sliderType = NSSliderTypeLinear;
    _slider.minValue   = 0.0;
    _slider.maxValue   = 1.0;
    _slider.continuous = YES;
    _slider.target     = self;
    _slider.action     = @selector(sliderMoved:);
    [self addSubview:_slider];

    _pctLabel = [NSTextField labelWithString:@""];
    _pctLabel.frame     = NSMakeRect(178, 5, 38, 16);
    _pctLabel.font      = [NSFont monospacedDigitSystemFontOfSize:12
                                                          weight:NSFontWeightRegular];
    _pctLabel.alignment = NSTextAlignmentRight;
    [self addSubview:_pctLabel];

    return self;
}

- (void)sliderMoved:(NSSlider *)sender {
    float vol = sender.floatValue;
    _pctLabel.stringValue = [NSString stringWithFormat:@"%d%%",
                             (int)roundf(vol * 100)];
    goSliderChanged(vol);
}

- (void)setVolume:(float)vol label:(NSString *)label {
    _slider.floatValue    = vol;
    _pctLabel.stringValue = label;
}

@end

// ── App delegate ──────────────────────────────────────────────────────────

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) NSStatusItem     *statusItem;
@property (nonatomic, strong) VolumeSliderView *sliderView;
@property (nonatomic, strong) NSMenuItem       *muteItem;
@property (nonatomic, strong) NSMenuItem       *prefsItem;
@end

static AppDelegate *appDelegate = nil;

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    self.statusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"🔊";

    NSMenu *menu = [[NSMenu alloc] init];

    // Slider row
    self.sliderView = [[VolumeSliderView alloc] init];
    NSMenuItem *sliderItem = [[NSMenuItem alloc] init];
    sliderItem.view = self.sliderView;
    [menu addItem:sliderItem];

    [menu addItem:[NSMenuItem separatorItem]];

    self.muteItem = [[NSMenuItem alloc]
        initWithTitle:@"Mute"
        action:@selector(muteClicked:)
        keyEquivalent:@""];
    self.muteItem.target = self;
    [menu addItem:self.muteItem];

    [menu addItem:[NSMenuItem separatorItem]];

    self.prefsItem = [[NSMenuItem alloc]
        initWithTitle:@"Preferences…"
        action:@selector(prefsClicked:)
        keyEquivalent:@""];
    self.prefsItem.target = self;
    [menu addItem:self.prefsItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [[NSMenuItem alloc]
        initWithTitle:@"Quit"
        action:@selector(quitClicked:)
        keyEquivalent:@""];
    quit.target = self;
    [menu addItem:quit];

    self.statusItem.menu = menu;
}

- (void)muteClicked:(id)s  { goMenuClicked(1); }
- (void)prefsClicked:(id)s { goMenuClicked(2); }
- (void)quitClicked:(id)s  { goMenuClicked(3); }

@end

// ── C interface called from Go ────────────────────────────────────────────

void startStatusBar(void) {
    [NSApplication sharedApplication];
    appDelegate = [[AppDelegate alloc] init];
    [NSApp setDelegate:appDelegate];
    [NSApp run];
}

// All setters dispatch to the main queue so they're safe from any goroutine.

void setStatusTitle(const char *title) {
    NSString *s = @(title);
    dispatch_async(dispatch_get_main_queue(), ^{
        appDelegate.statusItem.button.title = s;
    });
}

// vol is 0.0–1.0; label is the text shown beside the slider (e.g. "42%" or "Muted").
void setVolumeSlider(float vol, const char *label) {
    NSString *lbl = @(label);
    dispatch_async(dispatch_get_main_queue(), ^{
        [appDelegate.sliderView setVolume:vol label:lbl];
    });
}

void setMuteItemState(int muted) {
    NSControlStateValue state = muted ? NSControlStateValueOn : NSControlStateValueOff;
    dispatch_async(dispatch_get_main_queue(), ^{
        appDelegate.muteItem.state = state;
    });
}

void setPrefsItemEnabled(int enabled) {
    BOOL on = (enabled != 0);
    dispatch_async(dispatch_get_main_queue(), ^{
        appDelegate.prefsItem.enabled = on;
    });
}

void quitApp(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp terminate:nil];
    });
}
