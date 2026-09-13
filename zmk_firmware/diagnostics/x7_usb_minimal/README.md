# x7 minimal GPIO and USB diagnostics

This application separates basic Zephyr startup from USB initialization on the
x7 hardware. It targets the standard `xiao_ble/nrf52840` board with ZMK's
`nrf52840-nosd` snippet, matching the tested bootloader which has no SoftDevice.

- P0.28 (x7 external LED1) and the XIAO red LED (P0.26, active low)
  toggle every 500 ms after `main()` starts.
- P0.29 (x7 external LED2) and the XIAO green LED (P0.30, active low)
  stay on in the GPIO-only build.
- The same two status LEDs turn on after `usb_enable()` succeeds in the USB
  CDC build.

Build with the ZMK-pinned Zephyr workspace:

```sh
cd /Volumes/Primary/GitHub/zmk

.venv/bin/west build -p always \
    -s /Volumes/Primary/GitHub-private/On-the-15-v4/zmk_firmware/diagnostics/x7_usb_minimal \
    -d build/x7-gpio-only-nosd -b xiao_ble/nrf52840 -- \
    -DSNIPPET=nrf52840-nosd -DSNIPPET_ROOT=/Volumes/Primary/GitHub/zmk/app

.venv/bin/west build -p always \
    -s /Volumes/Primary/GitHub-private/On-the-15-v4/zmk_firmware/diagnostics/x7_usb_minimal \
    -d build/x7-usb-cdc-nosd -b xiao_ble/nrf52840 -- \
    -DSNIPPET=nrf52840-nosd -DSNIPPET_ROOT=/Volumes/Primary/GitHub/zmk/app \
    -DEXTRA_CONF_FILE=usb-cdc.conf
```

The build outputs are `build/x7-gpio-only-nosd/zephyr/zephyr.uf2` and
`build/x7-usb-cdc-nosd/zephyr/zephyr.uf2`. Copy them to versioned filenames instead
of overwriting previous diagnostic UF2 files.

Verified outputs built from ZMK `faaf39d9f59cd2a27eca3739cdd9eb197654299b`,
Zephyr `9df4b12b5af3438a8b9d7a33780dc3b3b2f516c1`, and Zephyr SDK 0.17.0:

| File | SHA-256 | UF2 address range |
| --- | --- | --- |
| `x7-zephyr4.1-nosd-onboard-gpio-faaf39d9.uf2` | `27a431d0b7929c0ea63c3209c564c004da049f0ff336eb08d85816545c71a12c` | `0x1000`–`0x5300` |
| `x7-zephyr4.1-nosd-usb-cdc-faaf39d9.uf2` | `8732d3fdab84060b8b53ee0238d4dbb84013335b232cb088aaf081fc08fc2d3d` | `0x1000`–`0xa000` |

The old `0x27000` diagnostic images are retained for provenance but cannot boot
on the tested XIAO while `INFO_UF2.TXT` reports `SoftDevice: not found`.
