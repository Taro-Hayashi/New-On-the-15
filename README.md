# New On the 15 & ドック

![](./doc/img/IMG_7417.jpg)

## ビルドガイド
- [一体型](doc/INTEGRATED.md)
- [分割型](doc/SPLIT.md)

## はんだ付け済み品の組み立て方
- [一体型](doc/PRE_INTEGRATED.md)
- [分割型](doc/PRE_SPLIT.md)

## 販売ページ
- [BOOTH](https://tarohayashi.booth.pm/items/8798135)

## 公開データ
- [回路図](sch/SCH.md)
- プリント品（準備中）
- [基板外形、アクリルプレート](plate/PLATE.md)
- [ガーバー（USB基板、フレキシブル基板）](gerber/GERBER.md)
- ソースコード
	- ZMKファームウェア
		- 使用モジュール
			- zmk-matrix-lighting（準備中）
			- zmk-host-rgb-sync（準備中）
			- [zmk-module-ble-management](https://github.com/cormoran/zmk-module-ble-management)
			- [zmk-feature-default-layer](https://github.com/cormoran/zmk-feature-default-layer)
			- [zmk-feature-custom-settings](https://github.com/cormoran/zmk-feature-custom-settings)
			- [zmk-feature-os-detection](https://github.com/cormoran/zmk-feature-os-detection)
			- [zmk-feature-device-info](https://github.com/cormoran/zmk-feature-device-info)
			- [zmk-feature-runtime-combo](https://github.com/cormoran/zmk-feature-runtime-combo)
			- [zmk-feature-runtime-macro](https://github.com/cormoran/zmk-feature-runtime-macro)
			- [zmk-feature-kscan-diagnostics](https://github.com/cormoran/zmk-feature-kscan-diagnostics)
	- RMKファームウェア

## ライセンス

| 対象               | ライセンス     | 詳細                                              |
| ---------------- | --------- | ----------------------------------------------- |
| 回路図              | MIT       | [sch/LICENSE](sch/LICENSE)                   |
| USB基板ガーバー        | CC0 1.0   | [gerber/LICENSE](gerber/LICENSE)             |
| フレキシブル基板ガーバー     | CC0 1.0   | [gerber/LICENSE](gerber/LICENSE)             |
| 基板外形、アクリルプレートデータ | CC BY 4.0 | [plate/LICENSE](plate/LICENSE)               |
| 本体プリント品データ       | CC BY 4.0 | 準備中                                      |
| 治具プリント品データ       | CC0 1.0   | 準備中                                      |
| ZMKファームウェア       | MIT       | [zmk_firmware/LICENSE](zmk_firmware/LICENSE) |
| RMKファームウェア       | MIT       | [rmk_firmware/LICENSE](rmk_firmware/LICENSE) |


2Uスタビライザーはkoktohさんのフットプリントを使用しました。
https://github.com/koktoh/BrownSugar_KBD_KiCad_Library
電池の回路はcormoranさんのdya-dashの回路図を参照しました。
https://github.com/cormoran/dya-dash-keyboard/

## 保守品の入手先
- [M2ネジ](https://www.monotaro.com/g/00010425/)（見た目が違うことがあります）
	- 5mm
	- 6mm
	- 8mm
	- 10mm
- [M2ナット](https://www.monotaro.com/g/06150312/)
- 電池端子
	- [プラス（IT-4SP）](https://www.monotaro.com/p/8835/2512/)
	- [マイナス（IT-4SM）](https://www.monotaro.com/p/8835/2521/)
- [スライドスイッチ](https://akizukidenshi.com/catalog/g/g115703/)
- [サイドスイッチ](https://akizukidenshi.com/catalog/g/g114890/)
- [ゴム足 8×2mm](https://link.amazon/B0epStW7h)
- [マグネット 6×2mm](https://link.amazon/B0a5OvMwi)
- [ピンヘッダー 2.54mm x 40ピン](https://akizukidenshi.com/catalog/g/g100167/)
- [MXスイッチソケット](https://shop.yushakobo.jp/products/a01ps)
