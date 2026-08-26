# Kindle Auto Brightness Bridge

In KOReader on a Kindle, screen brightness does not normally follow the surrounding light the way it does in the native Kindle reader. This plugin lets KOReader stay in sync with the Kindle's Auto Brightness, so brightness can adapt as the light around you changes.

## What this fixes

The Kindle may adjust screen brightness while KOReader still remembers an earlier level. KOReader's brightness controls can then behave as if the screen were still at that old level.

With the plugin enabled, KOReader checks the brightness that the Kindle is currently using whenever KOReader needs it. The Kindle still decides how bright the screen should be; the plugin does not calculate brightness itself.

## Is this plugin for my Kindle?

The plugin requires all of the following:

- a Kindle with a frontlight;
- an ambient-light sensor; and
- a KOReader version that can read the Kindle's current brightness.

On unsupported devices, the plugin stays disabled and does not add its menu item.

To receive automatic brightness changes, enable Auto Brightness in the stock Kindle interface **before starting KOReader**. The plugin cannot enable or configure Auto Brightness for you.

## Install and enable

1. Download or copy this repository's `kindleautobrightness.koplugin/` directory.
2. Copy the whole directory, including `_meta.lua` and `main.lua`, into KOReader's `plugins/` directory on the Kindle. The final path should be:

   `.../koreader/plugins/kindleautobrightness.koplugin/`

3. Restart KOReader once so it discovers the plugin.
4. In the stock Kindle interface, enable Auto Brightness.
5. Start KOReader and open **More tools**.
6. Check **Synchronize with Kindle Auto Brightness**.

The bridge is disabled by default. Once enabled, it works with KOReader's existing brightness controls; it adds no separate brightness screen.

## Use

Leave **More tools** → **Synchronize with Kindle Auto Brightness** checked. Use KOReader's brightness gestures, actions, and controls as usual.

You can turn the plugin off while KOReader is running. Turning it off restores KOReader's normal brightness behavior immediately; you do not need to restart KOReader.

## Limits

- The Kindle, not this plugin, chooses the brightness from the surrounding light.
- It does not control warmth or AutoWarmth.
- It does not enable Kindle Auto Brightness. If Auto Brightness is off, the plugin can only report the current screen brightness when KOReader asks for it.
- It checks the brightness when KOReader asks for it, rather than running a timer in the background.
- Manual brightness changes in KOReader still take effect normally.
- If it cannot read the current brightness, KOReader keeps using its previous brightness information.

## Troubleshooting

### The menu item is missing

1. Check that the directory is named exactly `kindleautobrightness.koplugin`.
2. Check that it contains both `_meta.lua` and `main.lua`.
3. Restart KOReader once after copying the directory.
4. Confirm that the device is a Kindle with a frontlight and ambient-light sensor.

The plugin also requires a KOReader version that can read the Kindle's current brightness. If the Kindle or KOReader does not support this, the menu item remains hidden.

### Brightness does not change automatically

Enable Auto Brightness in the stock Kindle interface, then restart KOReader. Enabling it after KOReader starts may not produce automatic changes during that session.

Also confirm that **More tools** → **Synchronize with Kindle Auto Brightness** is checked. The saved setting is `kindleautobrightness_enabled`.

### KOReader uses the wrong brightness or a read fails

Turn the bridge off and on once. If the problem continues, enable KOReader debug logging and look for lines beginning with `KindleAutoBrightness:`. The plugin can log these exact messages:

- `KindleAutoBrightness: live frontlight read unavailable`
- `KindleAutoBrightness: original frontlightIntensity failed`
- `KindleAutoBrightness: refusing to replace another frontlight wrapper`
- `KindleAutoBrightness: leaving a changed frontlight method untouched`

When reporting a problem, include those lines and nearby `PowerD` or frontlight messages, along with:

- the KOReader version;
- the Kindle model and firmware;
- whether stock Auto Brightness was enabled before KOReader started; and
- the action that produced the problem.

Remove credentials and unrelated private information from logs before sharing them.

## Technical notes

KOReader normally keeps a remembered frontlight level and returns it from `frontlightIntensity()`. Kindle's own Auto Brightness can change the hardware level without updating that remembered value. The next relative gesture may therefore start from the wrong brightness.

While enabled, this plugin wraps `frontlightIntensity()` on the active Kindle PowerD instance. Each call uses KOReader's existing `frontlightIntensityHW()` path to read the live level. A valid non-zero result updates KOReader's remembered level and frontlight state. An off reading returns `0` without erasing the last non-zero level, so KOReader can still restore that level when the light turns on again.

The plugin uses KOReader's light-sensor capability flag when available. If that flag is incomplete for a Kindle model, it checks for the native sensor by reading the existing LIPC handle's `alsLux` property. It discards the lux value; the check only establishes that the sensor exists.

The wrapper is installed at most once. Resume checks that it is still present but schedules no background work. On disable, the plugin restores the exact method that was there before it enabled itself. If another component has replaced that method, the plugin leaves the changed method alone and logs a diagnostic message.

### KOReader background and upstream context

The implementation was checked against `koreader/koreader` `master` commit `5e45c4b5c7bc5d29dee5ce98b3e9c380905788d8`, fetched on 2026-08-25.

- KOReader's generic PowerD code keeps the cached frontlight level used by `frontlightIntensity()`.
- The Kindle backend already provides `frontlightIntensityHW()` through LIPC, including Kindle-specific level and off-state handling. This plugin reuses that code instead of controlling the hardware itself.
- KOReader's relative brightness controls, notifications, and frontlight dialog read through `frontlightIntensity()`, so changing that one read path covers the user-facing behavior without polling.

Related upstream discussions:

- [Issue #13259](https://github.com/koreader/koreader/issues/13259) describes the stale cached brightness problem and discusses live LIPC reads.
- [Issue #13400](https://github.com/koreader/koreader/issues/13400) discusses ambient-light functionality and confirms that Kindle Auto Brightness can continue working while KOReader is open.
- [PR #12809](https://github.com/koreader/koreader/pull/12809) removed KOReader's old `autofrontlight` plugin. That plugin polled a coarse ambient level and toggled the light; it did not synchronize Kindle's live brightness with KOReader's cached value.

This repository provides a reversible, opt-in external plugin. It does not include a KOReader core patch.

## License

MIT. See [LICENSE](LICENSE).
