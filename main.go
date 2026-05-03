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
	"unsafe"

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

var app *application.Application

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

func adjustVolume(delta float32) {
	vol := float32(math.Max(0, math.Min(1, float64(currentVolume()+delta))))
	if err := app.SetVolume(vol); err != nil {
		log.Printf("error setting volume: %v", err)
		return
	}
	fmt.Printf("Volume: %.0f%%\n", vol*100)
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
		fmt.Printf("Unmuted, volume: %.0f%%\n", volumeBeforeMute*100)
	} else {
		volumeBeforeMute = v.Level
		if err := app.SetMuted(true); err != nil {
			log.Printf("error muting: %v", err)
			return
		}
		fmt.Printf("Muted (was %.0f%%)\n", volumeBeforeMute*100)
	}
}

func main() {
	// Discover the device
	ctx := context.Background()
	entry, err := dns.DiscoverCastDNSEntryByName(ctx, nil, deviceName)  // context + nil interface
	if err != nil {
		log.Fatalf("could not find device %q: %v", deviceName, err)
	}

	app = application.NewApplication()
	if err := app.Start(entry.GetAddr(), entry.GetPort()); err != nil {
		log.Fatalf("could not connect: %v", err)
	}
	defer app.Close(false)  // false = don't stop the app on the device

	fmt.Printf("Connected to %s\n", deviceName)
	if v := app.Volume(); v != nil {
		fmt.Printf("Current volume: %.0f%%\n", v.Level*100)
	}
	fmt.Println("Listening for volume keys...")

	C.runEventTap()
}
