package main

import (
	"archive/zip"
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

var (
	repository      = "maccam912/mega-chamomile"
	launcherVersion = "development"
)

const (
	applicationDirectory = "MegaChamomile"
	githubAPIVersion     = "2026-03-10"
	maxExtractedSize     = int64(8 << 30)
)

var errAlreadyRunning = errors.New("launcher is already running")

type release struct {
	ID      int64   `json:"id"`
	TagName string  `json:"tag_name"`
	Assets  []asset `json:"assets"`
}

type asset struct {
	Name               string `json:"name"`
	BrowserDownloadURL string `json:"browser_download_url"`
	Digest             string `json:"digest"`
	Size               int64  `json:"size"`
}

type installedVersion struct {
	ReleaseID    int64  `json:"release_id"`
	TagName      string `json:"tag_name"`
	AssetName    string `json:"asset_name"`
	LaunchTarget string `json:"launch_target"`
}

type updater struct {
	baseDir string
	client  *http.Client
	logger  *log.Logger
}

func main() {
	if err := run(); err != nil {
		showError("Mega Chamomile could not start", err.Error())
		os.Exit(1)
	}
}

func run() error {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return fmt.Errorf("find the application data directory: %w", err)
	}

	baseDir := filepath.Join(configDir, applicationDirectory)
	if err := os.MkdirAll(baseDir, 0o755); err != nil {
		return fmt.Errorf("create application data directory: %w", err)
	}

	logFile, err := os.OpenFile(filepath.Join(baseDir, "launcher.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return fmt.Errorf("open launcher log: %w", err)
	}
	defer logFile.Close()

	logger := log.New(io.MultiWriter(os.Stdout, logFile), "", log.LstdFlags)
	logger.Printf("Mega Chamomile launcher %s starting on %s/%s", launcherVersion, runtime.GOOS, runtime.GOARCH)

	releaseLock, err := acquireLock(baseDir)
	if errors.Is(err, errAlreadyRunning) {
		logger.Print("another launcher is already checking for updates")
		return nil
	}
	if err != nil {
		return err
	}
	defer releaseLock()

	u := &updater{
		baseDir: baseDir,
		client: &http.Client{
			Transport: &http.Transport{
				Proxy:                 http.ProxyFromEnvironment,
				ResponseHeaderTimeout: 30 * time.Second,
			},
		},
		logger: logger,
	}

	current, currentErr := u.loadCurrent()
	latest, err := u.fetchLatestRelease()
	if err != nil {
		if currentErr == nil {
			logger.Printf("update check failed (%v); starting the installed version", err)
			return u.launch(current)
		}
		return fmt.Errorf("check GitHub for the latest release: %w", err)
	}

	gameAsset, err := assetForPlatform(latest.Assets, runtime.GOOS, runtime.GOARCH)
	if err != nil {
		if currentErr == nil {
			logger.Printf("the latest release is not usable on this computer (%v); starting the installed version", err)
			return u.launch(current)
		}
		return err
	}

	if currentErr == nil && current.ReleaseID == latest.ID && current.AssetName == gameAsset.Name {
		logger.Printf("%s is already installed", latest.TagName)
		return u.launch(current)
	}

	logger.Printf("installing %s from %s", latest.TagName, gameAsset.Name)
	installed, err := u.install(latest, gameAsset)
	if err != nil {
		if currentErr == nil {
			logger.Printf("update failed (%v); starting the previous installed version", err)
			return u.launch(current)
		}
		return fmt.Errorf("install %s: %w", latest.TagName, err)
	}

	if err := u.saveCurrent(installed); err != nil {
		logger.Printf("warning: could not save installed version metadata: %v", err)
	}
	previousID := int64(0)
	if currentErr == nil {
		previousID = current.ReleaseID
	}
	u.pruneVersions(installed.ReleaseID, previousID)

	if err := u.launch(installed); err != nil && currentErr == nil && current.ReleaseID != installed.ReleaseID {
		logger.Printf("new version did not start (%v); trying the previous version", err)
		if fallbackErr := u.launch(current); fallbackErr != nil {
			return errors.Join(err, fallbackErr)
		}
		if saveErr := u.saveCurrent(current); saveErr != nil {
			logger.Printf("warning: could not restore previous version metadata: %v", saveErr)
		}
		return nil
	} else {
		return err
	}
}

func acquireLock(baseDir string) (func(), error) {
	lockPath := filepath.Join(baseDir, "launcher.lock")
	if err := os.Mkdir(lockPath, 0o755); err == nil {
		return func() { _ = os.Remove(lockPath) }, nil
	} else if !os.IsExist(err) {
		return nil, fmt.Errorf("create launcher lock: %w", err)
	}

	info, err := os.Stat(lockPath)
	if err == nil && time.Since(info.ModTime()) > 10*time.Minute {
		if removeErr := os.Remove(lockPath); removeErr == nil {
			if retryErr := os.Mkdir(lockPath, 0o755); retryErr == nil {
				return func() { _ = os.Remove(lockPath) }, nil
			}
		}
	}
	return nil, errAlreadyRunning
}

func (u *updater) fetchLatestRelease() (release, error) {
	parts := strings.Split(repository, "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return release{}, fmt.Errorf("invalid GitHub repository %q", repository)
	}

	endpoint := fmt.Sprintf("https://api.github.com/repos/%s/%s/releases/latest", url.PathEscape(parts[0]), url.PathEscape(parts[1]))
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return release{}, err
	}
	u.setGitHubHeaders(req)

	resp, err := u.client.Do(req)
	if err != nil {
		return release{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return release{}, fmt.Errorf("GitHub returned %s", resp.Status)
	}

	var latest release
	decoder := json.NewDecoder(io.LimitReader(resp.Body, 4<<20))
	if err := decoder.Decode(&latest); err != nil {
		return release{}, fmt.Errorf("decode GitHub response: %w", err)
	}
	if latest.ID <= 0 || latest.TagName == "" {
		return release{}, errors.New("GitHub returned an incomplete release")
	}
	return latest, nil
}

func (u *updater) setGitHubHeaders(req *http.Request) {
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", githubAPIVersion)
	req.Header.Set("User-Agent", "Mega-Chamomile-Launcher/"+launcherVersion)
}

func assetForPlatform(assets []asset, goos, goarch string) (asset, error) {
	var wanted string
	switch goos {
	case "windows":
		if goarch != "amd64" {
			return asset{}, fmt.Errorf("Windows on %s is not supported", goarch)
		}
		wanted = "mega-chamomile-windows-x86_64.zip"
	case "linux":
		if goarch != "amd64" {
			return asset{}, fmt.Errorf("Linux on %s is not supported", goarch)
		}
		wanted = "mega-chamomile-linux-x86_64.zip"
	case "darwin":
		if goarch != "amd64" && goarch != "arm64" {
			return asset{}, fmt.Errorf("macOS on %s is not supported", goarch)
		}
		wanted = "mega-chamomile-macos-universal.zip"
	default:
		return asset{}, fmt.Errorf("%s is not a supported operating system", goos)
	}

	for _, candidate := range assets {
		if candidate.Name == wanted {
			if candidate.BrowserDownloadURL == "" {
				return asset{}, fmt.Errorf("release asset %s has no download URL", wanted)
			}
			return candidate, nil
		}
	}
	return asset{}, fmt.Errorf("the latest release does not contain %s", wanted)
}

func (u *updater) install(latest release, gameAsset asset) (installedVersion, error) {
	versionsDir := filepath.Join(u.baseDir, "versions")
	if err := os.MkdirAll(versionsDir, 0o755); err != nil {
		return installedVersion{}, err
	}

	versionName := strconv.FormatInt(latest.ID, 10)
	finalDir := filepath.Join(versionsDir, versionName)
	if completeInstall(finalDir) {
		target, err := findLaunchTarget(finalDir, runtime.GOOS)
		if err == nil {
			relativeTarget, _ := filepath.Rel(finalDir, target)
			return installedVersion{latest.ID, latest.TagName, gameAsset.Name, relativeTarget}, nil
		}
	}
	if err := os.RemoveAll(finalDir); err != nil {
		return installedVersion{}, fmt.Errorf("remove an incomplete install: %w", err)
	}

	downloadsDir := filepath.Join(u.baseDir, "downloads")
	if err := os.MkdirAll(downloadsDir, 0o755); err != nil {
		return installedVersion{}, err
	}
	archive, err := os.CreateTemp(downloadsDir, versionName+"-*.zip.part")
	if err != nil {
		return installedVersion{}, err
	}
	archivePath := archive.Name()
	if err := archive.Close(); err != nil {
		return installedVersion{}, err
	}
	defer os.Remove(archivePath)

	actualDigest, err := u.download(gameAsset, archivePath)
	if err != nil {
		return installedVersion{}, err
	}
	expectedDigest, err := u.expectedDigest(latest, gameAsset)
	if err != nil {
		return installedVersion{}, err
	}
	if !strings.EqualFold(actualDigest, expectedDigest) {
		return installedVersion{}, fmt.Errorf("download checksum mismatch: got %s, expected %s", actualDigest, expectedDigest)
	}
	u.logger.Printf("verified SHA-256 checksum %s", actualDigest)

	tempDir, err := os.MkdirTemp(versionsDir, "."+versionName+"-install-")
	if err != nil {
		return installedVersion{}, err
	}
	defer os.RemoveAll(tempDir)

	if err := extractZip(archivePath, tempDir); err != nil {
		return installedVersion{}, fmt.Errorf("extract game package: %w", err)
	}
	target, err := findLaunchTarget(tempDir, runtime.GOOS)
	if err != nil {
		return installedVersion{}, err
	}
	if runtime.GOOS != "windows" {
		executable := target
		if runtime.GOOS == "darwin" {
			executable = filepath.Join(target, "Contents", "MacOS", "Mega Chamomile")
		}
		if err := os.Chmod(executable, 0o755); err != nil {
			return installedVersion{}, fmt.Errorf("make game executable: %w", err)
		}
	}
	relativeTarget, err := filepath.Rel(tempDir, target)
	if err != nil {
		return installedVersion{}, err
	}
	if err := os.WriteFile(filepath.Join(tempDir, ".complete"), []byte(latest.TagName+"\n"), 0o644); err != nil {
		return installedVersion{}, err
	}
	if err := os.Rename(tempDir, finalDir); err != nil {
		return installedVersion{}, fmt.Errorf("finish game install: %w", err)
	}

	u.logger.Printf("installed %s in %s", latest.TagName, finalDir)
	return installedVersion{latest.ID, latest.TagName, gameAsset.Name, relativeTarget}, nil
}

func (u *updater) download(gameAsset asset, destination string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, gameAsset.BrowserDownloadURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", "Mega-Chamomile-Launcher/"+launcherVersion)

	resp, err := u.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("download %s: %w", gameAsset.Name, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("download %s: server returned %s", gameAsset.Name, resp.Status)
	}

	output, err := os.OpenFile(destination, os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return "", err
	}
	defer output.Close()

	u.logger.Printf("downloading %s (%s)", gameAsset.Name, humanSize(gameAsset.Size))
	hash := sha256.New()
	written, err := io.Copy(io.MultiWriter(output, hash), resp.Body)
	if err != nil {
		return "", fmt.Errorf("download %s: %w", gameAsset.Name, err)
	}
	if gameAsset.Size > 0 && written != gameAsset.Size {
		return "", fmt.Errorf("download %s: got %d bytes, expected %d", gameAsset.Name, written, gameAsset.Size)
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func (u *updater) expectedDigest(latest release, gameAsset asset) (string, error) {
	if digest, ok := validSHA256Digest(gameAsset.Digest); ok {
		return digest, nil
	}

	var checksums asset
	found := false
	for _, candidate := range latest.Assets {
		if candidate.Name == "SHA256SUMS.txt" {
			checksums = candidate
			found = true
			break
		}
	}
	if !found {
		return "", fmt.Errorf("release asset %s has no GitHub digest and the release has no SHA256SUMS.txt", gameAsset.Name)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, checksums.BrowserDownloadURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", "Mega-Chamomile-Launcher/"+launcherVersion)
	resp, err := u.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("download checksums: server returned %s", resp.Status)
	}
	return parseChecksum(io.LimitReader(resp.Body, 1<<20), gameAsset.Name)
}

func validSHA256Digest(value string) (string, bool) {
	digest, found := strings.CutPrefix(strings.TrimSpace(value), "sha256:")
	if !found || len(digest) != sha256.Size*2 {
		return "", false
	}
	if _, err := hex.DecodeString(digest); err != nil {
		return "", false
	}
	return strings.ToLower(digest), true
}

func parseChecksum(reader io.Reader, assetName string) (string, error) {
	scanner := bufio.NewScanner(reader)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) != 2 {
			continue
		}
		name := strings.TrimPrefix(fields[1], "*")
		name = strings.TrimPrefix(name, "./")
		if name != assetName || len(fields[0]) != sha256.Size*2 {
			continue
		}
		if _, err := hex.DecodeString(fields[0]); err != nil {
			continue
		}
		return strings.ToLower(fields[0]), nil
	}
	if err := scanner.Err(); err != nil {
		return "", err
	}
	return "", fmt.Errorf("SHA256SUMS.txt does not contain %s", assetName)
}

func extractZip(archivePath, destination string) error {
	reader, err := zip.OpenReader(archivePath)
	if err != nil {
		return err
	}
	defer reader.Close()

	var totalSize int64
	for _, entry := range reader.File {
		totalSize += int64(entry.UncompressedSize64)
		if totalSize < 0 || totalSize > maxExtractedSize {
			return fmt.Errorf("archive expands beyond the %s safety limit", humanSize(maxExtractedSize))
		}

		relative, err := safeArchivePath(entry.Name)
		if err != nil {
			return err
		}
		target := filepath.Join(destination, relative)
		if entry.FileInfo().Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("archive contains unsupported symbolic link %q", entry.Name)
		}
		if entry.FileInfo().IsDir() {
			if err := os.MkdirAll(target, 0o755); err != nil {
				return err
			}
			continue
		}

		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		input, err := entry.Open()
		if err != nil {
			return err
		}
		mode := entry.Mode().Perm()
		if mode == 0 {
			mode = 0o644
		}
		output, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
		if err != nil {
			input.Close()
			return err
		}
		written, copyErr := io.Copy(output, input)
		closeOutputErr := output.Close()
		closeInputErr := input.Close()
		if copyErr != nil {
			return copyErr
		}
		if closeOutputErr != nil {
			return closeOutputErr
		}
		if closeInputErr != nil {
			return closeInputErr
		}
		if written != int64(entry.UncompressedSize64) {
			return fmt.Errorf("archive entry %q has an unexpected size", entry.Name)
		}
	}
	return nil
}

func safeArchivePath(name string) (string, error) {
	normalized := strings.ReplaceAll(name, "\\", "/")
	cleaned := path.Clean(normalized)
	if cleaned == "." || cleaned == ".." || strings.HasPrefix(cleaned, "../") || strings.HasPrefix(normalized, "/") || strings.Contains(cleaned, ":") {
		return "", fmt.Errorf("archive contains unsafe path %q", name)
	}
	return filepath.FromSlash(cleaned), nil
}

func completeInstall(directory string) bool {
	info, err := os.Stat(filepath.Join(directory, ".complete"))
	return err == nil && info.Mode().IsRegular()
}

func findLaunchTarget(directory, goos string) (string, error) {
	var wanted string
	switch goos {
	case "windows":
		wanted = "mega-chamomile.exe"
	case "linux":
		wanted = "mega-chamomile.x86_64"
	case "darwin":
		app := filepath.Join(directory, "Mega Chamomile.app")
		executable := filepath.Join(app, "Contents", "MacOS", "Mega Chamomile")
		if info, err := os.Stat(executable); err == nil && info.Mode().IsRegular() {
			return app, nil
		}
		return "", errors.New("the macOS package does not contain Mega Chamomile.app")
	default:
		return "", fmt.Errorf("unsupported operating system %s", goos)
	}

	var match string
	err := filepath.WalkDir(directory, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if !entry.IsDir() && strings.EqualFold(entry.Name(), wanted) {
			match = path
			return fs.SkipAll
		}
		return nil
	})
	if err != nil {
		return "", err
	}
	if match == "" {
		return "", fmt.Errorf("the package does not contain %s", wanted)
	}
	return match, nil
}

func (u *updater) loadCurrent() (installedVersion, error) {
	data, err := os.ReadFile(filepath.Join(u.baseDir, "current.json"))
	if err != nil {
		return installedVersion{}, err
	}
	var current installedVersion
	if err := json.Unmarshal(data, &current); err != nil {
		return installedVersion{}, err
	}
	if current.ReleaseID <= 0 || current.LaunchTarget == "" {
		return installedVersion{}, errors.New("installed version metadata is incomplete")
	}
	_, err = u.targetPath(current)
	return current, err
}

func (u *updater) saveCurrent(current installedVersion) error {
	data, err := json.MarshalIndent(current, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	temp, err := os.CreateTemp(u.baseDir, "current-*.json")
	if err != nil {
		return err
	}
	tempName := temp.Name()
	defer os.Remove(tempName)
	if _, err := temp.Write(data); err != nil {
		temp.Close()
		return err
	}
	if err := temp.Close(); err != nil {
		return err
	}
	destination := filepath.Join(u.baseDir, "current.json")
	if err := os.Rename(tempName, destination); err == nil {
		return nil
	} else if runtime.GOOS != "windows" {
		return err
	}
	// Windows does not allow os.Rename to replace an existing file.
	if err := os.Remove(destination); err != nil && !os.IsNotExist(err) {
		return err
	}
	return os.Rename(tempName, destination)
}

func (u *updater) targetPath(current installedVersion) (string, error) {
	versionDir := filepath.Join(u.baseDir, "versions", strconv.FormatInt(current.ReleaseID, 10))
	if !completeInstall(versionDir) {
		return "", errors.New("installed version is incomplete")
	}
	cleaned, err := safeArchivePath(current.LaunchTarget)
	if err != nil {
		return "", errors.New("installed version has an unsafe launch path")
	}
	target := filepath.Join(versionDir, cleaned)
	if runtime.GOOS == "darwin" {
		target = filepath.Join(target, "Contents", "MacOS", "Mega Chamomile")
	}
	info, err := os.Stat(target)
	if err != nil || !info.Mode().IsRegular() {
		return "", errors.New("installed game executable is missing")
	}
	return filepath.Join(versionDir, cleaned), nil
}

func (u *updater) launch(current installedVersion) error {
	target, err := u.targetPath(current)
	if err != nil {
		return err
	}
	u.logger.Printf("starting Mega Chamomile %s", current.TagName)

	var command *exec.Cmd
	if runtime.GOOS == "darwin" {
		command = exec.Command("open", "-n", target)
	} else {
		command = exec.Command(target)
		command.Dir = filepath.Dir(target)
		command.Stdout = os.Stdout
		command.Stderr = os.Stderr
	}
	if err := command.Start(); err != nil {
		return fmt.Errorf("start game: %w", err)
	}
	return command.Process.Release()
}

func (u *updater) pruneVersions(keepIDs ...int64) {
	keep := make(map[string]bool, len(keepIDs))
	for _, id := range keepIDs {
		if id > 0 {
			keep[strconv.FormatInt(id, 10)] = true
		}
	}
	versionsDir := filepath.Join(u.baseDir, "versions")
	entries, err := os.ReadDir(versionsDir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if !entry.IsDir() || keep[entry.Name()] {
			continue
		}
		if _, err := strconv.ParseInt(entry.Name(), 10, 64); err != nil {
			continue
		}
		if err := os.RemoveAll(filepath.Join(versionsDir, entry.Name())); err != nil {
			u.logger.Printf("warning: could not remove old version %s: %v", entry.Name(), err)
		}
	}
}

func humanSize(size int64) string {
	if size <= 0 {
		return "unknown size"
	}
	const unit = 1024
	if size < unit {
		return fmt.Sprintf("%d B", size)
	}
	divisor, exponent := int64(unit), 0
	for value := size / unit; value >= unit && exponent < 4; value /= unit {
		divisor *= unit
		exponent++
	}
	return fmt.Sprintf("%.1f %ciB", float64(size)/float64(divisor), "KMGTPE"[exponent])
}

func showError(title, message string) {
	switch runtime.GOOS {
	case "darwin":
		script := fmt.Sprintf("display alert %s message %s as critical", appleScriptString(title), appleScriptString(message))
		_ = exec.Command("osascript", "-e", script).Run()
	case "windows":
		command := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show($env:MC_LAUNCHER_ERROR, $env:MC_LAUNCHER_TITLE, 'OK', 'Error') | Out-Null")
		command.Env = append(os.Environ(), "MC_LAUNCHER_TITLE="+title, "MC_LAUNCHER_ERROR="+message)
		_ = command.Run()
	case "linux":
		_ = exec.Command("zenity", "--error", "--title="+title, "--text="+message).Run()
	}
	fmt.Fprintf(os.Stderr, "%s: %s\n", title, message)
}

func appleScriptString(value string) string {
	value = strings.ReplaceAll(value, "\\", "\\\\")
	value = strings.ReplaceAll(value, "\"", "\\\"")
	value = strings.ReplaceAll(value, "\n", "\\n")
	return "\"" + value + "\""
}
