# Kindle Auto Brightness Bridge

A small external KOReader plugin for supported Kindles with an ambient-light sensor. When enabled, it makes KOReader's normal frontlight reads observe the live level already chosen by Kindle's stock Auto Brightness. KOReader's existing gestures, absolute brightness actions, notification, and frontlight dialog therefore start from the current Kindle level instead of a stale cached level.

The plugin does not implement Auto Brightness. Amazon `powerd` remains the controller.

## Requirements and limits

- Kindle with a frontlight, an ambient-light sensor, and a usable live `frontlightIntensityHW()` read.
- The Kindle stock UI must have Auto Brightness enabled before KOReader starts if automatic changes are wanted. KOReader does not enable or configure that setting.
- The plugin is opt-in and disabled by default. It is harmless when Kindle Auto Brightness is disabled: it only observes the current hardware level when the user asks KOReader to read brightness.
- No lux curve, brightness algorithm, polling timer, warmth/AutoWarmth control, model table, raw sysfs access, shell LIPC command, or KOReader fork is used.
- Hardware read failures are diagnostic-only: the wrapper retains KOReader's cached remembered level and falls back to the original method. It never writes a value merely to synchronize.

## Install by copying

1. Download or copy this repository's `kindleautobrightness.koplugin/` directory.
2. Copy that directory, including `_meta.lua` and `main.lua`, into the `plugins/` directory of the KOReader installation on the Kindle. The final path must be:

   `.../koreader/plugins/kindleautobrightness.koplugin/`

3. Safely restart KOReader once so its plugin loader discovers the directory. Runtime enable/disable does not require another restart.
4. On the Kindle stock home/reading UI, enable Auto Brightness if desired, then launch KOReader.
5. In KOReader's main menu, check **Synchronize with Kindle Auto Brightness**.
6. Use the normal relative brightness gestures, absolute brightness actions, frontlight dialog, and frontlight toggle. Disable the checkbox to restore the original PowerD method immediately.

The plugin is intentionally not installed to a physical Kindle by the builder. Follow `TESTING.md` only after the candidate has been frozen and Alex has turned the Kindle on.

## Runtime behavior

Enabling wraps only the active Kindle PowerD instance's `frontlightIntensity()` method. Each call first preserves the original method as a fallback, then safely calls the existing Kindle-native `frontlightIntensityHW()` conversion/read path. A validated live level above the backend minimum updates `fl_intensity` and `is_fl_on` and is returned. A validated minimum/off read returns the public off value `0` without replacing a remembered non-zero `fl_intensity`; that remembered value is what Kindle's existing on path can restore. Nil, errors, non-numbers, NaN, and out-of-range reads leave the cache untouched and return the original result or a safe cached fallback.

The wrapper is installed at most once on a PowerD instance. Disable restores the exact previous raw instance method (including restoring inheritance when the original method was inherited). Resume only re-checks the existing wrapper; it schedules no work. Manual `setIntensity()` remains authoritative and still writes the requested absolute value through KOReader's existing path.

## Troubleshooting

1. Confirm the plugin directory name is exactly `kindleautobrightness.koplugin` and restart KOReader once after copying it.
2. Confirm the device is a Kindle with a frontlight and ALS. On unsupported hardware the plugin returns disabled and does not add a synchronization menu item.
3. Confirm Auto Brightness was enabled in the stock Kindle UI before launching KOReader. The bridge does not turn it on.
4. Toggle the bridge off and on once. The setting is persisted as `kindleautobrightness_enabled` and the method is restored on disable.
5. If a read fails, enable KOReader debug logging and collect the lines containing the exact category/prefix `KindleAutoBrightness:`. The diagnostic strings are:
   - `KindleAutoBrightness: live frontlight read unavailable`
   - `KindleAutoBrightness: original frontlightIntensity failed`
   - `KindleAutoBrightness: refusing to replace another frontlight wrapper`
   - `KindleAutoBrightness: leaving a changed frontlight method untouched`

Collect those lines together with nearby `PowerD`/frontlight lines, the KOReader version, Kindle model/firmware, whether stock Auto Brightness was enabled, and the exact action that was being performed. Do not include credentials or unrelated private log content.

## Architecture evidence and upstream context

The implementation was checked against upstream `koreader/koreader` `master` commit `5e45c4b5c7bc5d29dee5ce98b3e9c380905788d8` fetched on 2026-08-25.

- `frontend/device/generic/powerd.lua` caches `fl_intensity` and returns it from `frontlightIntensity()` except when the light is off. `setIntensity()` compares against that public value before writing, while `updateResumeFrontlightState()` preserves interactive off/on state.
- `frontend/device/kindle/powerd.lua` already provides Kindle-native `frontlightIntensityHW()` through LIPC (with its existing synthetic-step/off handling), and `isFrontlightOnHW()` reads that path. The bridge reuses those methods rather than duplicating conversion or controlling hardware.
- `frontend/device/devicelistener.lua` obtains the base for relative changes from `powerd:frontlightIntensity()` and displays notifications from the same method. `frontend/ui/widget/frontlightwidget.lua` also reads that method when opening and updating the dialog. The wrapper therefore covers the practical read paths without a timer or a new listener.
- `frontend/device/pocketbook/powerd.lua` is the precedent for a live public `frontlightIntensity()` override, but Kindle's synthetic level/off semantics and remembered non-zero level make a blind one-line copy unsafe.

Related upstream records were researched separately:

- [Issue #13259](https://github.com/koreader/koreader/issues/13259) documents the stale cached gesture problem. Comments confirm live LIPC reads are possible, that KOReader has no LIPC event loop for this purpose, and that polling would be the remaining fancier option. This plugin intentionally uses on-demand reads instead.
- [Issue #13400](https://github.com/koreader/koreader/issues/13400) asks how to reintroduce ambient-light functionality. Maintainers point to existing plugin conventions; a later comment confirms Kindle stock Auto Brightness continues working in KOReader and learns from KOReader changes.
- [PR #12809](https://github.com/koreader/koreader/pull/12809) merged on 2024-12-06 as commit `162685df50bb5e752a3cdf65c347bb9032a05dee`. It removed the old `autofrontlight` because it depended on the removed background runner and was enabled by default; comments explicitly leave room for a standalone, opt-in replacement.
- The historical `plugins/autofrontlight.koplugin/` around KOReader v2024.11 polled a coarse ambient level through background jobs and toggled the light. It did not synchronize a live level into KOReader's cached brightness. The bridge is deliberately not a revival of that algorithm.

A core Kindle override could resemble PocketBook's live method, but a safe core change would also need capability gating, failure validation, opt-in policy, and Kindle off/remembered-level handling. That is not a tiny unconditional patch and would change behavior for every Kindle user. The primary deliverable therefore remains this reversible external plugin; no upstream patch is included.
