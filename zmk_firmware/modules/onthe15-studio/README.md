# On the 15 Studio module

On the 15 v4の独自機能をDYA Studioへ公開するためのCustom Studio RPCモジュールです。
非公式Custom Studio RPC対応の`cormoran/zmk`を必要とします。

現在のPhase 6.6は、x15向けのfirmware情報、電池設定、接続状態インジケーター、SK6812設定、
電源設定と読み取り専用診断を実装しています。SK6812設定の実装本体は独立した
`zmk-matrix-lighting`モジュールで、このモジュールはDYA向けのRPCアダプターだけを
担当します。

- subsystem: `onthe15__studio`
- response: firmware version、project Git SHA、schema version、電池設定、状態インジケーター、未保存状態
- schema version: `2`
- security: 読み取りはunsecured、設定変更はStudio Unlock必須
- persistence: Save時にZephyr settingsへ保存
- battery operations: Get、Set memory、Save、Discard、Reset
- status operations: Get、Set memory、Save、Discard、Reset
- lighting operations: Get、Set memory、Save、Discard、Reset、Static／Breathing／Reactive Ripple、速度1〜10
- power operations: Get、Set memory、Save、Discard、Reset、diagnostics
- split support: none

配布用Web UI URLは`https://studio.tarohayashi.com/`です。ローカル開発時は
`http://localhost:5173/`を直接開きます。

ローカルUIは次の手順で起動します。

```sh
cd zmk_firmware/modules/onthe15-studio/web
npm ci
npm run dev
```

Chrome、EdgeまたはCodex内蔵ブラウザで`http://localhost:5173/`を開き、USBまたはBluetoothを
選択します。USBの自動再接続は、手動接続との競合で同じSerialPortを二重に開く可能性があるため
使用しません。BraveのWeb Bluetoothは実機環境で接続操作が反応しませんでした。Web UIは
日本語表示で、idleとdeep sleepは実用値を並べた段階式スライダーから選択します。

リポジトリルートの`zmk_firmware/build_dya.sh power-x15`でビルドします。設計、固定依存、
検証状態は`zmk_firmware/DYA_STUDIO.md`を正本とします。
