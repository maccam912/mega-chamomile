package main

import (
	"archive/zip"
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAssetForPlatform(t *testing.T) {
	assets := []asset{
		{Name: "mega-chamomile-linux-x86_64.zip", BrowserDownloadURL: "https://example.test/linux"},
		{Name: "mega-chamomile-windows-x86_64.zip", BrowserDownloadURL: "https://example.test/windows"},
		{Name: "mega-chamomile-macos-universal.zip", BrowserDownloadURL: "https://example.test/macos"},
	}
	tests := []struct {
		goos, goarch, wanted string
	}{
		{"linux", "amd64", assets[0].Name},
		{"windows", "amd64", assets[1].Name},
		{"darwin", "amd64", assets[2].Name},
		{"darwin", "arm64", assets[2].Name},
	}
	for _, test := range tests {
		got, err := assetForPlatform(assets, test.goos, test.goarch)
		if err != nil {
			t.Fatalf("assetForPlatform(%s, %s): %v", test.goos, test.goarch, err)
		}
		if got.Name != test.wanted {
			t.Errorf("assetForPlatform(%s, %s) = %s, want %s", test.goos, test.goarch, got.Name, test.wanted)
		}
	}
	if _, err := assetForPlatform(assets, "linux", "arm64"); err == nil {
		t.Error("expected Linux arm64 to be rejected")
	}
}

func TestValidSHA256Digest(t *testing.T) {
	wanted := strings.Repeat("a", 64)
	got, ok := validSHA256Digest("sha256:" + wanted)
	if !ok || got != wanted {
		t.Fatalf("valid digest = %q, %v", got, ok)
	}
	if _, ok := validSHA256Digest("sha256:not-a-digest"); ok {
		t.Error("invalid digest was accepted")
	}
}

func TestParseChecksum(t *testing.T) {
	wanted := strings.Repeat("b", 64)
	input := wanted + "  unrelated.zip\n" + wanted + "  mega-chamomile-linux-x86_64.zip\n"
	got, err := parseChecksum(strings.NewReader(input), "mega-chamomile-linux-x86_64.zip")
	if err != nil {
		t.Fatal(err)
	}
	if got != wanted {
		t.Fatalf("checksum = %s, want %s", got, wanted)
	}
}

func TestExtractZip(t *testing.T) {
	archivePath := filepath.Join(t.TempDir(), "game.zip")
	file, err := os.Create(archivePath)
	if err != nil {
		t.Fatal(err)
	}
	writer := zip.NewWriter(file)
	header := &zip.FileHeader{Name: "game/mega-chamomile.x86_64", Method: zip.Deflate}
	header.SetMode(0o755)
	entry, err := writer.CreateHeader(header)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := entry.Write([]byte("game")); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}

	destination := t.TempDir()
	if err := extractZip(archivePath, destination); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(destination, "game", "mega-chamomile.x86_64"))
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "game" {
		t.Fatalf("extracted data = %q", data)
	}
}

func TestExtractZipRejectsTraversal(t *testing.T) {
	archivePath := filepath.Join(t.TempDir(), "unsafe.zip")
	file, err := os.Create(archivePath)
	if err != nil {
		t.Fatal(err)
	}
	writer := zip.NewWriter(file)
	entry, err := writer.Create("../outside")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := entry.Write([]byte("bad")); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}

	if err := extractZip(archivePath, t.TempDir()); err == nil {
		t.Fatal("unsafe archive path was accepted")
	}
}

func TestSafeArchivePath(t *testing.T) {
	for _, unsafe := range []string{"../game", "folder/../../game", "/absolute/game", `C:\\game.exe`, "folder/game.exe:stream"} {
		if _, err := safeArchivePath(unsafe); err == nil {
			t.Errorf("safeArchivePath(%q) accepted an unsafe path", unsafe)
		}
	}
	if got, err := safeArchivePath("folder/game.exe"); err != nil || got != filepath.Join("folder", "game.exe") {
		t.Fatalf("safe path = %q, %v", got, err)
	}
}

func TestSaveCurrentReplacesExistingMetadata(t *testing.T) {
	u := &updater{baseDir: t.TempDir(), logger: log.New(os.Stderr, "", 0)}
	first := installedVersion{ReleaseID: 1, TagName: "first", AssetName: "game.zip", LaunchTarget: "game"}
	second := installedVersion{ReleaseID: 2, TagName: "second", AssetName: "game.zip", LaunchTarget: "game"}
	if err := u.saveCurrent(first); err != nil {
		t.Fatal(err)
	}
	if err := u.saveCurrent(second); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(u.baseDir, "current.json"))
	if err != nil {
		t.Fatal(err)
	}
	var got installedVersion
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatal(err)
	}
	if got.ReleaseID != second.ReleaseID || got.TagName != second.TagName {
		t.Fatalf("saved version = %+v, want %+v", got, second)
	}
}

// Set MEGA_CHAMOMILE_TEST_MACOS_ARCHIVE to exercise the extractor against a
// real release package without making normal unit tests depend on the network.
func TestReleaseArchiveOptional(t *testing.T) {
	archivePath := os.Getenv("MEGA_CHAMOMILE_TEST_MACOS_ARCHIVE")
	if archivePath == "" {
		t.Skip("MEGA_CHAMOMILE_TEST_MACOS_ARCHIVE is not set")
	}
	destination := t.TempDir()
	if err := extractZip(archivePath, destination); err != nil {
		t.Fatal(err)
	}
	if _, err := findLaunchTarget(destination, "darwin"); err != nil {
		t.Fatal(err)
	}
}
