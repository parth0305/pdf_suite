# Development Setup

Environment inspected and verified on **2026-08-24**. Every version below was read
from the tool itself, not assumed.

## Verified host

| Item | Value |
|---|---|
| OS | macOS 15.4.1 (build 24E263) |
| Kernel | Darwin 24.4.0 |
| Architecture | **x86_64 (Intel)** — not Apple Silicon |
| CPU | Intel Core i9-9980HK @ 2.40 GHz |
| Free disk | 158 GB |
| Locale | en-IN |

## Verified toolchain

| Tool | Version | Location |
|---|---|---|
| Flutter | 3.41.9 (stable) | `/usr/local/share/flutter` |
| Dart | 3.11.5 | `/usr/local/bin/dart` |
| DevTools | 2.54.2 | bundled |
| Android SDK | 35.0.0 | `~/Library/Android/sdk` |
| Android platforms | android-34, android-35, android-36 | |
| Android build-tools | 34.0.0, 35.0.0 | |
| Android NDK | 28.2.13676358 | |
| Android cmdline-tools | latest | |
| JDK | OpenJDK 17.0.19 (Homebrew) | `/usr/local/Cellar/openjdk@17/17.0.19/...` |
| Xcode | 16.4 (build 16F6) | `/Applications/Xcode.app` |
| CocoaPods | 1.16.2 | `/usr/local/bin/pod` |
| Git | 2.52.0 | `/usr/local/bin/git` |
| Homebrew | 6.0.12 | `/usr/local/bin/brew` |
| CMake | 3.22.1 (Android SDK copy only) | `~/Library/Android/sdk/cmake` |

`flutter doctor -v` reports **No issues found.**

Flutter framework revision `00b0c91f06`, engine `42d3d75a56`.

## Devices available

| Device | Status |
|---|---|
| iPhone 16 Plus simulator (iOS 18.6) | Available — primary development target |
| macOS desktop (darwin-x64) | Available |
| Chrome (web) | Available |
| Android emulator | **No AVD configured** |
| Physical Android device | **None connected** |
| Windows machine | **None** — see below |

## Known environment gaps

These are facts about this machine, not deferred work.

### Windows cannot be built or tested locally

Flutter Windows desktop builds require Windows plus Visual Studio 2022 with the
C++ desktop workload. This is macOS. Windows is therefore verified by
**GitHub Actions `windows-latest` CI** only: compile and unit tests run on every
push, but no human ever exercises the Windows UI. Manual Windows QA — mouse,
touch, File Explorer drag/drop, printing — is an open limitation tracked in
`docs/LIMITATIONS.md`.

### Android has no test device

An AVD must be created before any Android verification claim is made. Until then,
Android is unverified. Create one with:

```bash
~/Library/Android/sdk/cmdline-tools/latest/bin/avdmanager create avd \
  -n pixel_api35 -k "system-images;android-35;google_apis;x86_64" -d pixel_6
```

Note: `x86_64` system images are required — this is an Intel host, `arm64-v8a`
images will not run.

### Not on PATH

`java`, `adb`, `ninja`, and a general-purpose `cmake` are absent from PATH.
Flutter locates its own JDK and Android tooling, so this does not block Flutter
work. Add these if working outside Flutter:

```bash
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
export JAVA_HOME="/usr/local/Cellar/openjdk@17/17.0.19/libexec/openjdk.jdk/Contents/Home"
```

### CocoaPods UTF-8 warning

`pod` warns that the terminal is not using UTF-8. Harmless so far, but silence it with:

```bash
echo 'export LANG=en_US.UTF-8' >> ~/.zprofile
```

## Reproducing this check

```bash
flutter doctor -v
flutter devices
flutter --version
dart --version
```
