package main

/*
#cgo LDFLAGS: -framework Quartz -framework Carbon -framework AppKit -framework CoreAudio
#include <stdlib.h>

extern void runEventTap(void);
extern char *getDefaultAudioOutputDeviceName(void);

extern void startStatusBar(void);
extern void setStatusTitle(const char *title);
extern void setVolumeSlider(float vol, const char *label);
extern void setMuteItemTitle(const char *title);
extern void setPrefsItemEnabled(int enabled);
extern void quitApp(void);
*/
import "C"

import (
	"fmt"
	"log"
	"math"
	"runtime"
	"sync"
	"time"
	"unsafe"

	"github.com/vishen/go-chromecast/application"
	"github.com/vishen/go-chromecast/dns"
	"golang.org/x/net/context"
)

const (
	keyVolumeUp   = 0 // NX_KEYTYPE_SOUND_UP
	keyVolumeDown = 1 // NX_KEYTYPE_SOUND_DOWN
	keyVolumeMute = 7 // NX_KEYTYPE_MUTE
	step          = 0.02
)

var (
	cfgMu sync.RWMutex
	cfg   Config

	appMu sync.RWMutex
	app   *application.Application

	volumeBeforeMute float32

	// Throttle slider → Chromecast volume calls.
	sliderTimerMu sync.Mutex
	sliderTimer   *time.Timer
	lastSliderSet time.Time
)

const sliderThrottle = 100 * time.Millisecond

// ── Display helpers ───────────────────────────────────────────────────────

func cset(s string) *C.char { return C.CString(s) }
func cfree(p *C.char)       { C.free(unsafe.Pointer(p)) }

// updateDisplay refreshes the status bar title, slider position, and mute label.
// Safe to call from any goroutine.
func updateDisplay(vol float32, muted bool) {
	if muted {
		t := cset("🔇"); C.setStatusTitle(t); cfree(t)
		l := cset("Muted"); C.setVolumeSlider(C.float(vol), l); cfree(l)
		m := cset("Unmute"); C.setMuteItemTitle(m); cfree(m)
	} else {
		t := cset("🔊"); C.setStatusTitle(t); cfree(t)
		l := cset(fmt.Sprintf("%d%%", int(math.Round(float64(vol)*100))))
		C.setVolumeSlider(C.float(vol), l); cfree(l)
		m := cset("Mute"); C.setMuteItemTitle(m); cfree(m)
	}
}

// ── Key event handler (called from C event tap) ───────────────────────────

//export goHandleKey
func goHandleKey(keycode int) C.int {
	cname := C.getDefaultAudioOutputDeviceName()
	if cname == nil {
		return 0
	}
	name := C.GoString(cname)
	C.free(unsafe.Pointer(cname))

	cfgMu.RLock()
	wantAudio := cfg.AudioDeviceName
	cfgMu.RUnlock()

	if wantAudio == "" || name != wantAudio {
		return 0 // not our device — pass through
	}

	appMu.RLock()
	a := app
	appMu.RUnlock()
	if a == nil {
		return 0
	}

	switch int(keycode) {
	case keyVolumeUp:
		adjustVolume(a, +step)
	case keyVolumeDown:
		adjustVolume(a, -step)
	case keyVolumeMute:
		toggleMute(a)
	}
	return 1
}

// ── Slider callback (called from ObjC on main thread) ────────────────────

//export goSliderChanged
func goSliderChanged(value C.float) {
	vol := float32(value)
	// Update title immediately so it feels responsive.
	t := cset("🔊"); C.setStatusTitle(t); cfree(t)

	// Throttle: send immediately if enough time has passed since the last
	// update, otherwise schedule a trailing call so the final value always lands.
	sliderTimerMu.Lock()
	if sliderTimer != nil {
		sliderTimer.Stop()
		sliderTimer = nil
	}
	delay := sliderThrottle - time.Since(lastSliderSet)
	if delay <= 0 {
		// Enough time has passed — apply immediately.
		lastSliderSet = time.Now()
		sliderTimerMu.Unlock()
		go applySliderVolume(vol)
	} else {
		// Too soon — schedule a trailing call with the latest value.
		sliderTimer = time.AfterFunc(delay, func() {
			sliderTimerMu.Lock()
			lastSliderSet = time.Now()
			sliderTimer = nil
			sliderTimerMu.Unlock()
			applySliderVolume(vol)
		})
		sliderTimerMu.Unlock()
	}
}

func applySliderVolume(vol float32) {
	appMu.RLock()
	a := app
	appMu.RUnlock()
	if a == nil {
		return
	}
	if err := a.SetVolume(vol); err != nil {
		log.Printf("slider: error setting volume: %v", err)
	}
}

// ── Menu item callbacks (called from ObjC on main thread) ─────────────────

//export goMenuClicked
func goMenuClicked(tag C.int) {
	switch int(tag) {
	case 1: // Mute / Unmute
		appMu.RLock()
		a := app
		appMu.RUnlock()
		if a != nil {
			go toggleMute(a)
		}
	case 2: // Preferences
		go openPreferences()
	case 3: // Quit
		appMu.RLock()
		a := app
		appMu.RUnlock()
		if a != nil {
			a.Close(false)
		}
		C.quitApp()
	}
}

// ── Volume control ────────────────────────────────────────────────────────

func currentVolume(a *application.Application) float32 {
	if err := a.Update(); err != nil {
		log.Printf("error reading volume: %v", err)
		return 0.5
	}
	if v := a.Volume(); v != nil {
		return v.Level
	}
	return 0.5
}

func adjustVolume(a *application.Application, delta float32) {
	vol := float32(math.Max(0, math.Min(1, float64(currentVolume(a)+delta))))
	if err := a.SetVolume(vol); err != nil {
		log.Printf("error setting volume: %v", err)
		return
	}
	updateDisplay(vol, false)
}

func toggleMute(a *application.Application) {
	if err := a.Update(); err != nil {
		log.Printf("error reading state: %v", err)
		return
	}
	v := a.Volume()
	if v == nil {
		return
	}
	if v.Muted {
		if err := a.SetMuted(false); err != nil {
			log.Printf("error unmuting: %v", err)
			return
		}
		if err := a.SetVolume(volumeBeforeMute); err != nil {
			log.Printf("error restoring volume: %v", err)
			return
		}
		updateDisplay(volumeBeforeMute, false)
	} else {
		volumeBeforeMute = v.Level
		if err := a.SetMuted(true); err != nil {
			log.Printf("error muting: %v", err)
			return
		}
		updateDisplay(v.Level, true)
	}
}

// ── Chromecast connection ─────────────────────────────────────────────────

func connectDevice(castName string) {
	t := cset("🔊"); C.setStatusTitle(t); cfree(t)
	l := cset("Connecting…"); C.setVolumeSlider(0.5, l); cfree(l)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	entry, err := dns.DiscoverCastDNSEntryByName(ctx, nil, castName)
	if err != nil {
		l := cset("Not found"); C.setVolumeSlider(0, l); cfree(l)
		log.Printf("could not find %q: %v", castName, err)
		return
	}

	newApp := application.NewApplication()
	if err := newApp.Start(entry.GetAddr(), entry.GetPort()); err != nil {
		l := cset("Failed"); C.setVolumeSlider(0, l); cfree(l)
		log.Printf("could not connect to %q: %v", castName, err)
		return
	}

	appMu.Lock()
	if app != nil {
		app.Close(false)
	}
	app = newApp
	appMu.Unlock()

	if v := newApp.Volume(); v != nil {
		updateDisplay(v.Level, v.Muted)
	}
	log.Printf("connected to %s", castName)
}

// ── Entry point ───────────────────────────────────────────────────────────

func main() {
	cfgMu.Lock()
	cfg = loadConfig()
	castName := cfg.CastDeviceName
	cfgMu.Unlock()

	// Event tap on its own locked OS thread.
	go func() {
		runtime.LockOSThread()
		C.runEventTap()
	}()

	// Connect to Chromecast in background.
	if castName != "" {
		go connectDevice(castName)
	}

	// Blocks on [NSApp run]; must be called on the main OS thread.
	C.startStatusBar()
}
