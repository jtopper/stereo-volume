package main

/*
#include <stdlib.h>

char** getAudioOutputDeviceNames(int *count);

void openConfigDialog(
    char **audioDevices, int audioCount,
    const char *curAudio, const char *curCast
);
void populateConfigDialogCast(
    char **castDevices, int castCount,
    const char *curCast
);
void setPrefsItemEnabled(int enabled);
*/
import "C"

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"time"
	"unsafe"

	"github.com/vishen/go-chromecast/dns"
)

// Config holds the user's device preferences.
type Config struct {
	AudioDeviceName string `json:"audio_device_name"`
	CastDeviceName  string `json:"cast_device_name"`
}

func configPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Library", "Application Support", "stereo-vol", "config.json")
}

func loadConfig() Config {
	data, err := os.ReadFile(configPath())
	if err != nil {
		return Config{}
	}
	var c Config
	if err := json.Unmarshal(data, &c); err != nil {
		return Config{}
	}
	return c
}

func saveConfig(c Config) error {
	path := configPath()
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0644)
}

// discoverChromecasts listens for mDNS Chromecast announcements for up to 3 s.
func discoverChromecasts() []string {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	ch, err := dns.DiscoverCastDNSEntries(ctx, nil)
	if err != nil {
		log.Printf("chromecast discovery error: %v", err)
		return nil
	}

	seen := make(map[string]bool)
	var names []string
	for entry := range ch {
		if entry.DeviceName != "" && !seen[entry.DeviceName] {
			seen[entry.DeviceName] = true
			names = append(names, entry.DeviceName)
		}
	}
	return names
}

// audioOutputDeviceNames returns names of all macOS audio output devices.
func audioOutputDeviceNames() []string {
	var count C.int
	cArr := C.getAudioOutputDeviceNames(&count)
	if cArr == nil || count == 0 {
		return nil
	}
	n := int(count)
	slice := (*[1 << 20]*C.char)(unsafe.Pointer(cArr))[:n:n]
	names := make([]string, n)
	for i, cs := range slice {
		names[i] = C.GoString(cs)
		C.free(unsafe.Pointer(cs))
	}
	C.free(unsafe.Pointer(cArr))
	return names
}

func goCStringSlice(ss []string) []*C.char {
	out := make([]*C.char, len(ss))
	for i, s := range ss {
		out[i] = C.CString(s)
	}
	return out
}

func freeCStringSlice(cs []*C.char) {
	for _, p := range cs {
		C.free(unsafe.Pointer(p))
	}
}

func cStringSlicePtr(cs []*C.char) **C.char {
	if len(cs) == 0 {
		return nil
	}
	return (**C.char)(unsafe.Pointer(&cs[0]))
}

// ── Dialog result channel ─────────────────────────────────────────────────

type configResult struct {
	saved bool
	audio string
	cast  string
}

var configResultCh = make(chan configResult, 1)

//export goConfigResult
func goConfigResult(saved C.int, audio *C.char, cast *C.char) {
	r := configResult{saved: saved != 0}
	if audio != nil {
		r.audio = C.GoString(audio)
	}
	if cast != nil {
		r.cast = C.GoString(cast)
	}
	select {
	case configResultCh <- r:
	default:
	}
}

// ── Preferences flow ──────────────────────────────────────────────────────

// openPreferences runs the two-phase preferences dialog.
// Must be called from a goroutine (not the main thread).
func openPreferences() {
	C.setPrefsItemEnabled(0)
	defer C.setPrefsItemEnabled(1)

	// Phase 1: gather audio devices (instant) and open dialog immediately.
	audioNames := audioOutputDeviceNames()
	audioC := goCStringSlice(audioNames)
	defer freeCStringSlice(audioC)

	cfgMu.RLock()
	curAudio := C.CString(cfg.AudioDeviceName)
	curCast := C.CString(cfg.CastDeviceName)
	currentCast := cfg.CastDeviceName
	cfgMu.RUnlock()
	defer C.free(unsafe.Pointer(curAudio))
	defer C.free(unsafe.Pointer(curCast))

	C.openConfigDialog(
		cStringSlicePtr(audioC), C.int(len(audioC)),
		curAudio, curCast,
	)

	// Phase 2: discover Chromecasts in the background while dialog is visible.
	castNames := discoverChromecasts()

	// Ensure the currently configured device is always in the list,
	// even if it wasn't discovered in the 3 s window.
	if currentCast != "" {
		found := false
		for _, n := range castNames {
			if n == currentCast {
				found = true
				break
			}
		}
		if !found {
			castNames = append([]string{currentCast}, castNames...)
		}
	}

	castC := goCStringSlice(castNames)
	defer freeCStringSlice(castC)

	C.populateConfigDialogCast(
		cStringSlicePtr(castC), C.int(len(castC)),
		curCast,
	)

	// Wait for the user to Save or Cancel.
	result := <-configResultCh
	if !result.saved {
		return
	}

	newCfg := Config{
		AudioDeviceName: result.audio,
		CastDeviceName:  result.cast,
	}
	if err := saveConfig(newCfg); err != nil {
		log.Printf("error saving config: %v", err)
	}

	cfgMu.Lock()
	oldCast := cfg.CastDeviceName
	cfg = newCfg
	cfgMu.Unlock()

	if newCfg.CastDeviceName != oldCast {
		go connectDevice(newCfg.CastDeviceName)
	}
}
