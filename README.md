# watched

简体中文 · [English](#english)

一个开源 tweak，让你的 Apple Watch 在 watchOS 比 iPhone 的 iOS 官方支持的版本更新时仍能完成配对。

构建支持 **rootless** 与 **roothide**，支持 Relaxin，安装包见 Release 标签页。

本仓库是上游 watched（**2.0**，作者 34306）的 fork，此处打包版本为 **2.1**。

## 修复功能

来自上游 —— 配对解锁（watchOS 新于 iOS）：

- 配对兼容性版本闸门（`NRPairingCompatibilityVersionInfo`）
- Watch 能力回退与 Watch 应用运行时兼容性（`NRDevice` / `NRMutableDevice`、`ACXRemoteApplication`）
- NanoRegistry / pairedsync 配对相关偏好写入

本 fork 新增（移植自 WatchFix）：

- **阻止 Messages 自动卸载**：修正 Watch 侧应用归属映射并让 Watch bundle 兼容性校验通过，避免 Messages 等系统应用因兼容性判断失败被自动卸载。
- **APS 保活**：apsd 收到伴侣应用的 presence 时上报代理已连接状态，减少反复重连。
- **BLE NearbyAction 0x00 拦截**：忽略 `CBDevice` 的 0x00 NearbyAction 设置，降低由此产生的蓝牙活动与耗电。

## 与上游的差异

- 上游只提供配对解锁；本 fork 额外包含上面三项修复。
- 注入范围更大：上游 filter 只列 `SpringBoard` + `com.apple.springboard`，本 fork 还注入 `apsd`、`appconduitd`、`installd`、`bluetoothd`、`MobileInstallationHelperService` / `com.apple.MobileInstallationHelperService`，并增加 `com.apple.Bridge` bundle（见 `watched.plist`）。
- 新增的 hook 在 `%ctor` 中按进程名分流：每个 daemon 只加载自己所需的修复；上游的配对 hook 与偏好写入在所有被注入进程中都会执行。
- `Makefile`：`THEOS = /opt/theos`；`THEOS_PACKAGE_SCHEME` 默认留在 `roothide`，需要 rootless 包时改为 `rootless`。
- `control`：版本 2.1（上游 2.0），依赖未改动。
- 新增了忽略 Theos 构建产物的 `.gitignore`。

## 注意事项

- 支持 iOS 15+
- 安装后请同时重启 iPhone 与 Apple Watch，然后重新配对。
- 未测试从更新的 Watch 备份恢复，请先备份 Apple Watch 数据。
- 若用第三方工具管理注入过滤器，请保留 `watched.plist` 中的这些进程名——删除后对应修复会静默失效。

---

## English

An open source tweak that lets you pair an Apple Watch running a watchOS newer
than your iPhone's iOS officially supports.

Builds for **rootless** and **roothide**, supports Relaxin; packages are in the
Release tab.

This repository is a fork of upstream watched (**2.0**, by 34306) and is
packaged here as **2.1**.

### Fix features

From upstream — pairing unlock (watchOS newer than iOS):

- Pairing compatibility version gate (`NRPairingCompatibilityVersionInfo`)
- Watch capability fallback and watch-app runtime compatibility
  (`NRDevice` / `NRMutableDevice`, `ACXRemoteApplication`)
- NanoRegistry / pairedsync pairing preference writes

Added in this fork, ported from WatchFix:

- **Message auto-uninstall fix**: repairs the Watch app bundle-ID mapping and
  the embedded Watch bundle applicability check, so Messages and similar system
  apps are no longer auto-uninstalled after a failed compatibility verdict.
- **APS keep-alive**: reports the proxy as connected when apsd receives
  incoming presence from the companion app, reducing repeated reconnects.
- **BLE NearbyAction 0x00 block**: ignores `0x00` `setNearbyActionV2Type:`
  calls on `CBDevice`, cutting the Bluetooth activity and drain behind them.

### Differences from upstream

- Upstream ships only the pairing unlock; this fork adds the three fixes above.
- Wider injection scope: upstream's filter only lists `SpringBoard` +
  `com.apple.springboard`; this fork also injects `apsd`, `appconduitd`,
  `installd`, `bluetoothd`, `MobileInstallationHelperService` /
  `com.apple.MobileInstallationHelperService`, and adds the `com.apple.Bridge`
  bundle (see `watched.plist`).
- The added hooks are process-gated in the `%ctor`: each daemon loads only its
  own fix, while the upstream pairing hooks and preference writes still run in
  every injected process.
- `Makefile`: `THEOS = /opt/theos`, and `THEOS_PACKAGE_SCHEME` stays on
  `roothide` — switch it to `rootless` to build the rootless package.
- `control`: version 2.1 (upstream 2.0); dependencies unchanged.
- A `.gitignore` for Theos build artifacts was added.

### Notes

- Supports iOS 15+
- After installing, reboot both the iPhone and the Apple Watch, then pair again.
- Restoring a newer Watch backup is not tested; back up your Apple Watch data
  first.
- If a third-party tool manages your injection filters, keep the daemon names
  listed in `watched.plist` — removing them silently disables the matching fix.
