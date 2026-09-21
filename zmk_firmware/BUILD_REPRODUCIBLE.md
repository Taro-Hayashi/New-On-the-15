# Reproducible ZMK builds

The build does not require permanent checkouts in `/Volumes/Primary/GitHub`.
Dependencies are cloned at the exact revisions in `dependencies.lock`, and the
On the 15 patches are applied locally. Repositories owned by cormoran are
configured with an invalid push URL so the generated workspaces are read-only.

```sh
cd zmk_firmware
./build_reproducible.sh power-x15
```

Generated dependencies, build directories, and UF2 files live below
`zmk_firmware/.build/`. Delete that directory at any time to test a clean
reconstruction. The next build downloads and prepares everything again.

SignalRGB targets select separate pinned revisions automatically:

```sh
./build_reproducible.sh signalrgb-x15
./build_reproducible.sh host-rgb-split-left-x7
./build_reproducible.sh host-rgb-split-right-x8
```

Set `ZMK_DEPS_ROOT` to keep the generated dependency cache elsewhere. Set
`UF2_OUTPUT_ROOT` to choose where final UF2 files are copied.

The first preparation downloads Zephyr modules, the ARM Zephyr SDK toolchain,
and Python packages, so it requires network access and several gigabytes of
free space.
