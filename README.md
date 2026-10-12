# watched

An open source tweak that lets you pair an Apple Watch running a watchOS newer
than your iPhone's iOS officially supports.

Builds for **rootless** and **roothide**, support Relaxin, check in Release tab.

## Fix features

- Pairing unlock (watchOS newer than iOS)
- **Fix Message auto uninstall**（阻止 Messages 等系统应用因 watchOS 兼容性判断失败被自动卸载）
- **APS keep-alive**（保持 apsd 推送代理与伴侣应用的连接，避免反复重连与 apsd 崩溃）
- **BLE NearbyAction 0x00 block**（拦截 bluetoothd 的 0x00 NearbyAction 扫描，降低蓝牙耗电）

## Notes

- Support iOS 15+
- After installing, reboot both iPhone and Apple Watch then pair again.
- Not tested on restoring a newer Watch backup; back up your Apple Watch data first.
