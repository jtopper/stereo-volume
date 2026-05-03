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
	"unsafe"

	"fyne.io/systray"
	"github.com/vishen/go-chromecast/application"
	"github.com/vishen/go-chromecast/dns"
)

const (
	keyVolumeUp     = 0 // NX_KEYTYPE_SOUND_UP
	keyVolumeDown   = 1 // NX_KEYTYPE_SOUND_DOWN
	keyVolumeMute   = 7 // NX_KEYTYPE_MUTE
	step            = 0.02
	deviceName      = "Panasonic PMX802M-25e2" // Chromecast mDNS name
	audioDeviceName = "Panasonic USB Audio 2"  // macOS audio output device name (System Settings > Sound > Output)
)

var (
	app        *application.Application
	menuVolume *systray.MenuItem
	menuMute   *systray.MenuItem
)

//export goHandleKey
func goHandleKey(keycode int) C.int {
	cname := C.getDefaultAudioOutputDeviceName()
	if cname == nil {
		return 0 // can't determine device — pass through
	}
	name := C.GoString(cname)
	C.free(unsafe.Pointer(cname))

	if name != audioDeviceName {
		return 0 // different output device — pass through
	}

	if app == nil {
		return 0 // not yet connected
	}

	switch int(keycode) {
	case keyVolumeUp:
		adjustVolume(+step)
	case keyVolumeDown:
		adjustVolume(-step)
	case keyVolumeMute:
		toggleMute()
	}
	return 1
}

func currentVolume() float32 {
	if err := app.Update(); err != nil {
		log.Printf("error reading volume from device: %v", err)
		return 0.5
	}
	if v := app.Volume(); v != nil {
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

func adjustVolume(delta float32) {
	vol := float32(math.Max(0, math.Min(1, float64(currentVolume()+delta))))
	if err := app.SetVolume(vol); err != nil {
		log.Printf("error setting volume: %v", err)
		return
	}
	setMenuVolume(vol, false)
}

var volumeBeforeMute float32

func toggleMute() {
	if err := app.Update(); err != nil {
		log.Printf("error reading state from device: %v", err)
		return
	}
	v := app.Volume()
	if v == nil {
		return
	}
	if v.Muted {
		if err := app.SetMuted(false); err != nil {
			log.Printf("error unmuting: %v", err)
			return
		}
		if err := app.SetVolume(volumeBeforeMute); err != nil {
			log.Printf("error restoring volume: %v", err)
			return
		}
		setMenuVolume(volumeBeforeMute, false)
	} else {
		volumeBeforeMute = v.Level
		if err := app.SetMuted(true); err != nil {
			log.Printf("error muting: %v", err)
			return
		}
		setMenuVolume(v.Level, true)
	}
}

func onReady() {
	systray.SetTitle("🔊")
	systray.SetTooltip(deviceName)

	menuVolume = systray.AddMenuItem("Connecting…", "")
	menuVolume.Disable()
	menuMute = systray.AddMenuItem("Mute", "")
	menuMute.Disable()
	systray.AddSeparator()
	menuQuit := systray.AddMenuItem("Quit", "")

	// Connect to Chromecast in the background
	go func() {
		ctx := context.Background()
		entry, err := dns.DiscoverCastDNSEntryByName(ctx, nil, deviceName)
		if err != nil {
			menuVolume.SetTitle("Device not found")
			log.Printf("could not find device %q: %v", deviceName, err)
			return
		}

		app = application.NewApplication()
		if err := app.Start(entry.GetAddr(), entry.GetPort()); err != nil {
			menuVolume.SetTitle("Connection failed")
			log.Printf("could not connect: %v", err)
			return
		}

		if v := app.Volume(); v != nil {
			setMenuVolume(v.Level, v.Muted)
		}
		menuMute.Enable()

		// Start the event tap on a dedicated locked OS thread
		go func() {
			runtime.LockOSThread()
			C.runEventTap()
		}()
	}()

	// Handle menu clicks
	go func() {
		for {
			select {
			case <-menuMute.ClickedCh:
				if app != nil {
					toggleMute()
				}
			case <-menuQuit.ClickedCh:
				if app != nil {
					app.Close(false)
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
