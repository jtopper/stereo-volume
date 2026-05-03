package main

/*
#include <stdlib.h>

char** getAudioOutputDeviceNames(int *count);

int showConfigDialog(
    char **audioDevices, int audioCount,
    char **castDevices,  int castCount,
    const char *currentAudio, const char *currentCast,
    char **outAudio, char **outCast
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

// goCStringSlice converts a []string to a []*C.char slice. The caller is
// responsible for freeing each element and the slice array itself.
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

// openPreferences discovers devices, shows the preferences dialog, and saves
// if the user confirms. Must be called from a goroutine (not the main thread).
func openPreferences() {
	C.setPrefsItemEnabled(0)
	defer C.setPrefsItemEnabled(1)

	audioNames := audioOutputDeviceNames()
	castNames := discoverChromecasts()

	audioC := goCStringSlice(audioNames)
	defer freeCStringSlice(audioC)
	castC := goCStringSlice(castNames)
	defer freeCStringSlice(castC)

	cfgMu.RLock()
	curAudio := C.CString(cfg.AudioDeviceName)
	curCast := C.CString(cfg.CastDeviceName)
	cfgMu.RUnlock()
	defer C.free(unsafe.Pointer(curAudio))
	defer C.free(unsafe.Pointer(curCast))

	// CGo can't pass a nil **C.char when count == 0, so use a dummy.
	audioPtr := (**C.char)(nil)
	if len(audioC) > 0 {
		audioPtr = (**C.char)(unsafe.Pointer(&audioC[0]))
	}
	castPtr := (**C.char)(nil)
	if len(castC) > 0 {
		castPtr = (**C.char)(unsafe.Pointer(&castC[0]))
	}

	var outAudio, outCast *C.char
	saved := C.showConfigDialog(
		audioPtr, C.int(len(audioC)),
		castPtr, C.int(len(castC)),
		curAudio, curCast,
		&outAudio, &outCast,
	)
	if saved == 0 {
		return
	}
	defer C.free(unsafe.Pointer(outAudio))
	defer C.free(unsafe.Pointer(outCast))

	newCfg := Config{
		AudioDeviceName: C.GoString(outAudio),
		CastDeviceName:  C.GoString(outCast),
	}
	if err := saveConfig(newCfg); err != nil {
		log.Printf("error saving config: %v", err)
	}

	cfgMu.Lock()
	oldCast := cfg.CastDeviceName
	cfg = newCfg
	cfgMu.Unlock()

	// Reconnect only if the Chromecast selection changed.
	if newCfg.CastDeviceName != oldCast {
		go connectDevice(newCfg.CastDeviceName)
	}
}
