package main

/*
#cgo LDFLAGS: -framework Quartz -framework Carbon -framework AppKit -framework CoreAudio
#include <stdlib.h>
extern void runEventTap();
char* getDefaultAudioOutputDeviceName();
*/
import "C"

import (
	"context"
	"fmt"
	"log"
	"math"
	"runtime"
	"sync"
	"time"
	"unsafe"

	"fyne.io/systray"
	"github.com/vishen/go-chromecast/application"
	"github.com/vishen/go-chromecast/dns"
)

var (
	cfgMu sync.RWMutex
	cfg   Config

	appMu sync.RWMutex
	app   *application.Application

	menuVolume *systray.MenuItem
	menuMute   *systray.MenuItem
	menuPrefs  *systray.MenuItem
)

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

const (
	keyVolumeUp   = 0 // NX_KEYTYPE_SOUND_UP
	keyVolumeDown = 1 // NX_KEYTYPE_SOUND_DOWN
	keyVolumeMute = 7 // NX_KEYTYPE_MUTE
	step          = 0.02
)

func currentVolume(a *application.Application) float32 {
	if err := a.Update(); err != nil {
		log.Printf("error reading volume from device: %v", err)
		return 0.5
	}
	if v := a.Volume(); v != nil {
		return v.Level
	}
	return 0.5
}

func setMenuVolume(vol float32, muted bool) {
	if muted {
		systray.SetTitle("🔇")
		menuVolume.SetTitle("Volume: muted")
		menuMute.SetTitle("Unmute")
	} else {
		systray.SetTitle("🔊")
		menuVolume.SetTitle(fmt.Sprintf("Volume: %.0f%%", vol*100))
		menuMute.SetTitle("Mute")
	}
}

func adjustVolume(a *application.Application, delta float32) {
	vol := float32(math.Max(0, math.Min(1, float64(currentVolume(a)+delta))))
	if err := a.SetVolume(vol); err != nil {
		log.Printf("error setting volume: %v", err)
		return
	}
	setMenuVolume(vol, false)
}

var volumeBeforeMute float32

func toggleMute(a *application.Application) {
	if err := a.Update(); err != nil {
		log.Printf("error reading state from device: %v", err)
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
		setMenuVolume(volumeBeforeMute, false)
	} else {
		volumeBeforeMute = v.Level
		if err := a.SetMuted(true); err != nil {
			log.Printf("error muting: %v", err)
			return
		}
		setMenuVolume(v.Level, true)
	}
}

// connectDevice discovers and connects to the named Chromecast.
// Safe to call from any goroutine; updates the menu accordingly.
func connectDevice(castName string) {
	menuVolume.SetTitle("Connecting…")
	menuMute.Disable()
	systray.SetTitle("🔊")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	entry, err := dns.DiscoverCastDNSEntryByName(ctx, nil, castName)
	if err != nil {
		menuVolume.SetTitle("Device not found")
		log.Printf("could not find %q: %v", castName, err)
		return
	}

	newApp := application.NewApplication()
	if err := newApp.Start(entry.GetAddr(), entry.GetPort()); err != nil {
		menuVolume.SetTitle("Connection failed")
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
		setMenuVolume(v.Level, v.Muted)
	}
	menuMute.Enable()
	log.Printf("connected to %s", castName)
}

func onReady() {
	systray.SetTitle("🔊")
	systray.SetTooltip("stereo-vol")

	menuVolume = systray.AddMenuItem("Not configured", "")
	menuVolume.Disable()
	menuMute = systray.AddMenuItem("Mute", "")
	menuMute.Disable()
	systray.AddSeparator()
	menuPrefs = systray.AddMenuItem("Preferences…", "")
	systray.AddSeparator()
	menuQuit := systray.AddMenuItem("Quit", "")

	// Load persisted config and connect if configured.
	cfgMu.Lock()
	cfg = loadConfig()
	castName := cfg.CastDeviceName
	cfgMu.Unlock()

	if castName != "" {
		go connectDevice(castName)
	}

	// Start the event tap on a dedicated OS thread once systray is up.
	go func() {
		runtime.LockOSThread()
		C.runEventTap()
	}()

	// Handle menu clicks.
	go func() {
		for {
			select {
			case <-menuMute.ClickedCh:
				appMu.RLock()
				a := app
				appMu.RUnlock()
				if a != nil {
					toggleMute(a)
				}
			case <-menuPrefs.ClickedCh:
				go openPreferences()
			case <-menuQuit.ClickedCh:
				appMu.RLock()
				a := app
				appMu.RUnlock()
				if a != nil {
					a.Close(false)
				}
				systray.Quit()
			}
		}
	}()
}

func onExit() {}

func main() {
	systray.Run(onReady, onExit)
}
