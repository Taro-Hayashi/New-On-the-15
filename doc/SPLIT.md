# New On the 15 & ドック 分割型 ビルドガイド

![](./img/IMG_7164.jpg)

目次
1. [ご購入の前に](#1-ご購入の前に)
2. [内容品の確認](#2-内容品の確認)
3. [準備](#3-準備)
4. [はんだ付けと組み立て](#4-はんだ付けと組み立て)
5. [使い方](#5-使い方)
6. [トラブルシューティング](#6-トラブルシューティング)
7. [保守品・公開データ](#7-保守品公開データ)

## 1. ご購入の前に
### 1.1 キット以外に必要なもの
![](./img/IMG_6041.jpg)

<table>
    <tr>
        <td><a href="https://shop.yushakobo.jp/collections/cherry-mx-clone">Cherry MX互換のキースイッチ</a></td>
        <td>〜60</td>
    </tr>
    <tr>
        <td><a href="https://shop.yushakobo.jp/collections/keycaps">キースイッチに対応したキーキャップ</a></td>
        <td>〜60</td>
    </tr>
    <tr>
        <td>XIAO nRF52840（<a href="https://shop.yushakobo.jp/products/11442">無印</a>/<a href="https://shop.yushakobo.jp/products/10946">Plus</a>）</td>
        <td>2</td>
    </tr>
    <tr>
        <td><a href="https://amzn.to/3XS9qRu">データ転送に対応したType-C USBケーブル</a></td>
        <td>2</td>
    </tr>
    <tr>
        <td>Windows / Mac（iPad、Androidでも使用できますが設定にPCが必要です）</td>
        <td>1</td>
    </tr>
 </table>

#### 別売オプション
<table>
    <tr>
      <td><a href="https://shop.yushakobo.jp/products/sk6812mini-e-10">LED（SK6812MINI-E）</a></td>
      <td>72</td>
      <td>ケーブル使用時に発光します。x7を2台の場合は68個、x8を2台の場合は76個です。</td>
    </tr>
    <tr>
      <td><a href="https://shop.yushakobo.jp/products/31?variant=40815840067745">2.5mmコンスルー</a></td>
      <td>XIAO一つにつき14ピン分</td>
      <td>XIAOを抜き差しできるようになり、リカバリー手段が増えます。</td>
    </tr>
    <tr>
      <td><a href="https://link.amazon/B01jpnmyo">プレートマウントのスタビライザー</a></td>
      <td>必要数</td>
      <td>2Uキーを使用する場合に押し込みが安定します。一本付属します。</td>
    </tr>
    <tr>
      <td><a href="https://link.amazon/B0dEvnT2f">単4電池</a></td>
      <td>2本</td>
      <td></td>
    </tr>
 </table>

### 1.2 必要な工具![](./img/IMG_5704.jpg)
<table>
    <tr>
      <td><a href="https://amzn.to/4rlr3qf">はんだごて</a></td>
      <td><a href="https://amzn.to/4ahMGlf">はんだ</a></td>
      <td><a href="https://amzn.to/4rlqTiD">マスキングテープ</a></td>
    </tr>
    <tr>
      <td><a href="https://amzn.to/3M2pNsb">ニッパー</a></td>
      <td><a href="https://amzn.to/44etOjB">ピンセット</a></td>
      <td><a href="https://amzn.to/48pxS1B0">精密ドライバー</a></td>
    </tr>
    <tr>
      <td colspan="3"><a href="https://link.amazon/B0bahuszw">エポキシ接着剤</a>（電池の蓋を磁石式にする場合）</td>
    </tr>
 </table>

#### あると便利な工具
<table>
    <tr>
        <td><a href="https://amzn.to/4rCpzs6">耐熱マット</a></td>
        <td>机の保護、火事の防止になります。</td>
    </tr>
    <tr>
        <td><a href="https://amzn.to/483c5hd">温調はんだごて</a></td>
        <td>熱しすぎないことでパーツを守ります。</td>
    </tr>
    <tr>
        <td><a href="https://amzn.to/4pwC0DN">平らなこて先</a></td>
        <td>熱を伝えやすく、はんだ付けがしやすいです。</td>
    </tr>
    <tr>
        <td><a href="https://amzn.to/3XmBn3J">フラックス</a></td>
        <td>酸化膜を除去し格段にはんだ付けがしやすくなります。</td>
    </tr>
    <tr>
        <td><a href="https://amzn.to/4ijJgjU">フラックスクリーナー、IPA</a></td>
        <td>基板に残ったフラックスを除去します。</td>
    </tr>
    <tr>
        <td><a href="https://amzn.to/4rsriA8">はんだ吸い取り線</a></td>
        <td>はんだが多すぎた時やパーツを外す時に使います。</td>
    </tr>
    <tr>
        <td><a href="https://amzn.to/4ro5VQg">テスター</a></td>
        <td>電圧や導通を調べることで不調の原因をしらべられます。</td>
    </tr>
    <tr>
        <td><a href="https://amzn.to/4ro5VQg">爪楊枝</a></td>
        <td>XIAOのリセットボタンを押せます。</td>
    </tr>
    <tr>
        <td><a href="https://link.amazon/B0hiszymI">アクリル研磨剤</a></td>
        <td>アクリルプレートが汚れた時に使えます。アクリルプレートをアルコールで拭く割れることがあります。</td>
    </tr>
 </table>

## 2. 内容品の確認

![](./img/IMG_5799.jpg)
![](./img/IMG_5774.jpg)

>[!NOTE]
>ビルドガイドでは7列のものをx7、8列のものをx8と呼称します。
>写真はx8のものです。
<table>
    <tr>
        <th>番号</th>
        <th>部品名</th>
        <th>数量（x7）</th>
        <th>数量（x8）</th>
        <th>備考</th>
    </tr>
    <tr><td rowspan="3"></td><td>メイン基板</td><td>1</td><td>1</td><td></td></tr>
    <tr><td>アクリルプレート</td><td>2</td><td>2</td><td>白・透明</td></tr>
    <tr><td>プリント品</td><td></td><td></td><td></td></tr>
    <tr><td>1</td><td>M2 × 5mmネジ</td><td>6</td><td>6</td><td></td></tr>
    <tr><td>2</td><td>M2 × 6mmネジ</td><td>4</td><td>4</td><td></td></tr>
    <tr><td>3</td><td>M2 × 8mmネジ</td><td>2</td><td>2</td><td></td></tr>
    <tr><td>4</td><td>M2 × 10mmネジ</td><td>6</td><td>6</td><td></td></tr>
    <tr><td>5</td><td>M2 × 5mmスペーサー</td><td>4</td><td>4</td><td></td></tr>
    <tr><td>6</td><td>M2ナット</td><td>8</td><td>8</td><td></td></tr>
    <tr><td>7</td><td>2Uスタビライザー</td><td>0</td><td>1</td><td>プレートマウント</td></tr>
    <tr><td>8</td><td>電池端子</td><td>2</td><td>2</td><td>プラス・マイナス 各1</td></tr>
    <tr><td>9</td><td>スライドスイッチ</td><td>1</td><td>1</td><td></td></tr>
    <tr><td>10</td><td>サイドスイッチ</td><td>2</td><td>2</td><td></td></tr>
    <tr><td>11</td><td>ゴム足</td><td>8</td><td>8</td><td></td></tr>
    <tr><td>12</td><td>ポゴピン</td><td>1対</td><td>1対</td><td>2.8mmピッチ</td></tr>
    <tr><td>13</td><td>USB基板</td><td>1</td><td>1</td><td></td></tr>
    <tr><td>14</td><td>フレキシブル基板</td><td>2</td><td>2</td><td>1枚のシートになっています</td></tr>
    <tr><td>15</td><td>マグネット</td><td>4</td><td>4</td><td>直径6mm × 厚さ2mm</td></tr>
    <tr><td>16</td><td>ピンヘッダー</td><td>1</td><td>1</td><td>40ピン</td></tr>
    <tr><td>17</td><td>MXスイッチソケット</td><td>28</td><td>32</td><td></td></tr>
</table>

プリント品の内容はこちらでご確認ください。
- プリント品データ（準備中）
## 3. 準備
### 3.1 動作確認用ファームウェアのインストール
こちらのuf2ファイルをダウンロードします。
- [`onthe15-test-x7x8-zmk.uf2`](https://github.com/Taro-Hayashi/New-On-the-15/releases/latest/download/onthe15-test-x7x8-zmk.uf2)

USBケーブルでPCと接続して、小さなボタンをピンセットなどで2回素早く押します。
![](./img/IMG_5806.jpg)
PCに新しいドライブが出てくるので、そこにダウンロードしたファイルをドラッグアンドドロップします。
![](./img/drive.jpg)
自動的にドライブが消えたら準備完了です。
### 3.2 レイアウトの決定
このキーボードは通常の正方形のキーのほか、横幅が2倍までのキーに対応しています。
四角で囲った部分は2Uキーを使うことが可能です。
![](./img/IMG_6182.jpg)
はんだ付けをする場所が変わりますので、作る前にどのような配列にするか選んでください。
今回は真ん中下のキーを2Uに変更します。2箇所以上変更する場合はスタビライザー無しで組み立てるか、追加でご購入ください。
![](./img/sample.jpg)
レイアウトに合わせて使用するスイッチブロックが変わります。このビルドガイドで組み立てる右手用では、2Uサイズは1Ux2を7個、2Ux1を1個、4x4サイズは1個になります。
![](./img/IMG_6188.jpg)
2Uサイズ、3Uサイズのスイッチブロックは、ツメがあるか、大きく開いている方が手前側になります。
![](./img/IMG_6194.jpg)

## 4. はんだ付けと組み立て

>[!NOTE]
>既存の部品にはんだごてやピンセットが当たらないように気をつけます。
### 4.1 （オプション）LEDのはんだ付けその１
裏面右上のLED7に足の切り欠きとマークを合わせてLEDを置きます。
![](./img/IMG_4935.jpg)
隣り合った金属の足がくっつかないようにはんだ付けします。
![](./img/IMG_4953.jpg)
全てのLEDをはんだ付けします。
![](./img/IMG_6198.jpg)表面のLED1〜6は後まわしにしています。XIAO以外のはんだ付けは順番を入れ替えても大丈夫です。
### 4.2 MXスイッチソケットのはんだ付け
SW1からSW28（SW32）まで、向きに気をつけて置きはんだ付けします。
![](./img/IMG_6199.jpg)
2Uキーを選んだ箇所は2Uのマークの部分にはんだ付けします。表裏で左右が変わることに気を付けてください。
![](./img/IMG_6200.jpg)
### 4.3 サイドボタンのはんだ付け
SWS1、2にサイドボタンをはんだ付けします。
![](./img/IMG_4965.jpg)

部品を付けた状態で裏返す場合はマスキングテープで位置を固定するとズレにくいです。
![](./img/IMG_4969.jpg)
### 4.4 スライドスイッチのはんだ付け
SS1にスライドスイッチをはんだ付けします。
![](./img/IMG_4974.jpg)
### 4.5 電池端子のはんだ付け
画像のプリント品と、ニッパーで切り出した2ピンのピンヘッダー2本を使います。
![](./img/IMG_6202.jpg)

繋がっている方が基板側になるようにピンヘッダーで位置合わせします。ピンヘッダーは長い方を基板に差します。
![](./img/IMG_6209.jpg)

裏返してはんだ付けします。
![](./img/IMG_6215.jpg)

電池端子を、平らな方が内側になるように直角に折り曲げます。
![](./img/IMG_6224.jpg)

JP+にバネのないプラス端子、JP-にバネのあるマイナス端子を差し込みはんだ付けします。
外周側ではなく内周側のピンです。
![](./img/IMG_6229.jpg)

やけどに気を付けて、ピンセットを使って電池が入る方向に押さえながらはんだ付けすると作業しやすいです。![](./img/IMG_6234.jpg)

反対側にマイナスの金具が約5mm飛び出すことになります。
![](./img/IMG_6237.jpg)

### 4.6 （オプション）残りのLEDのはんだ付け
表面のLED1-6をはんだ付けします。
![](./img/IMG_5052.jpg)

### 4.7 XIAO nRF52840のはんだ付け
XIAO付属、もしくは切り出した7ピンのピンヘッダーと画像のプリント品を使います。コンスルーを使用する場合は7ピン分を切り出します。
![](./img/IMG_6240.jpg)

基板にピンヘッダーの長い方を差し込み、プリント品の位置を合わせます。

>[!NOTE]
>この部分のLEDとMXソケットは隠れてしまうので方向があっているか、はんだ付けに問題がないかよくチェックします。LEDの方向は表側で確認することができます。

![](./img/IMG_6248.jpg)

XIAO nRFを載せます。ピンヘッダーはホールではなく、端面と接触します。
Plus（画像）の場合はホールと繋がっているパッドと位置を合わせます。
![](./img/IMG_6255.jpg)

XIAOの端面とピンヘッダーをはんだ付けします。Plusを使用する場合は隣り合ったパッドと繋がらないように気を付けます。
![](./img/IMG_6259.jpg)

裏返して飛び出したピンヘッダーをニッパーで切り、はんだ付けします。コンスルーを使用する場合は基板側ははんだ付けしません。
![](./img/IMG_6264.jpg)
### 4.8 動作の確認
USBケーブルでつなぐと赤と緑のインジケーターが光ります。LEDを付けている場合はLEDが点灯します。
![](./img/IMG_6267.jpg)

スイッチをソケットに差し込み、押すとアルファベットが入力されることを確かめます。
すべてのキーとサイドボタンが反応することを確かめてください。スライドスイッチは電池のオンオフなので反応はありません。
![](./img/IMG_5065.jpg)

USBケーブルを抜いたら電池を入れてスライドスイッチをオンにして、インジケーターが発光することを確認します。
![](./img/IMG_6276.jpg)
異常がなければ動作確認は完了です。スライドスイッチをオフにして電池を抜いてください。
### 4.9 ポゴピンとフレキシブルケーブルのはんだ付け
フレキシブルケーブルを台紙から切り離します。接続部はできればカッターなどで切ってください。
![](./img/IMG_6072.jpg)

画像のプリント品の治具とポゴピンの接触面が平らな方、長いL字のフレキシブル基板を使用します。
![](./img/IMG_6457.jpg)
治具の1の浅いくぼみに、平らな接触面を下にしてポゴピンを置き、フレキシブル基板の長い側のホールにピンを差し込みます。
小さいPogo Pinの文字が表になり短い端が手前側に来るようにします。
![](./img/IMG_6515.jpg)
上からもう一つの治具で押さえながらはんだ付けします。
![](./img/IMG_5123.jpg)
治具、はんだ付けしたものと金具が飛び出た方のポゴピン、S字のフレキシブル基板を使います。
![](./img/IMG_5128.jpg)
治具の2の深いくぼみに、はんだ付けされたL字のフレキシブル基板を下にして置き、S字のフレキシブル基板の長い側のホールにピンを差し込みます。
小さくPogo Pinと書いてあり、2本のフレキシブル基板の丸印どうしが同じ側になります。
![](./img/IMG_6485.jpg)
もう一つの治具で押さえながらはんだ付けします。
![](./img/IMG_5137.jpg)
2つのポゴピンに2本のフレキシブル基板がはんだ付けされました。
![](./img/IMG_6494.jpg)
基板のJ2に切り出した2ピンのピンヘッダーの長い方を差し込みます。
![](./img/IMG_5110.jpg)
裏返して足を切り、はんだ付けします。
![](./img/IMG_5115.jpg)
画像のプリント品と透明で小さいインジケーターディフューザーを使います。蓋を磁石式にする場合は磁石も使用します。

>[!NOTE]
>電池は満タンであれば1ヶ月以上持つため、磁石にすると外れるデメリットの方が大きい可能性があります。磁石式とネジ式は両立可能です。

![](./img/IMG_6283.jpg)
磁石式にする場合、一つずつスロットに押し込みます。接着剤がなくても固定できますが、不安な場合は少し付けて乾燥させてください。エポキシ接着剤は2色を混合して爪楊枝などにつけて塗ります。

![](./img/IMG_6301.jpg)
インジケーターディフューザーには平らな面とくぼんだ面があり、平らな面が上になるようにします。
![](./img/IMG_5164.jpg)
入りにくい場合は机などに押し付けてください。
![](./img/IMG_5166.jpg)
基板に載せます。インジケーターディフューザーの上下が逆の状態で力を加えるとインジケーターが破損するので無理に押しつけずに確認します。
![](./img/IMG_6115.jpg)
画像の場所に平らなポゴピンをはめ、ピンヘッダーに長いL字のフレキシブル基板をはんだ付けします。
![](./img/IMG_6324.jpg)
磁石式にする場合はポゴピンを接着剤で固定します。![](./img/IMG_6381.jpg)
本体のはんだ付けはこれで終了です。
### 4.10 キースイッチの取り付け
基板の表面にスイッチブロックを乗せてキースイッチを差し込みます。
![](./img/IMG_6344.jpg)
大きいサイズは切り欠きとはんだ付けされている場所を合わせます。
![](./img/IMG_5308.jpg)
2Uキーにスタビライザーを使用する場合、段差に引っ掛けながらスイッチブロックに取り付けます。
![](./img/IMG_6332.jpg)
ツメがある側、スタビライザーのバーがある側が手前になります。![](./img/IMG_6338.jpg)
### 4.11 本体の組み立て

画像のプリント品と10mmネジ4本、ナット4つを使用します。
![](./img/IMG_6353.jpg)
半透明のパーツでプリント品、メインボード、プリント品と挟み込むようにネジとナットで固定します。
![](./img/IMG_6359.jpg)
![](./img/IMG_6364.jpg)
裏側からネジを一本ずつ、ナットで止めてください。
![](./img/IMG_6370.jpg)
8mmネジ2本、スペーサーを2つを取り出します。
![](./img/IMG_6373.jpg)
2箇所に8mmネジとスペーサーを固定します。

![](./img/IMG_6376.jpg)
画像のプリント品と5mmネジ2本、スペーサー2つを使用します。![](./img/IMG_6386.jpg)
LRボタンは大きくて押しやすいものと見た目が目立たないものの2種類から選べます。
![](./img/IMG_5977.jpg)
スペーサーを5mmネジで固定します。
![](./img/IMG_6389.jpg)
アクリルプレート2枚と6mmネジ4つを使用します。
![](./img/IMG_6398.jpg)
アクリルプレートから保護シールを剥がし、6mmネジで固定します。
![](./img/IMG_6404.jpg)
磁石式にする場合は向きを気を付けて、電池の蓋になるプリント品に磁石をはめ込みます。磁石が外れる場合はエポキシ接着剤で固定してください。
![](./img/IMG_6320.jpg)
蓋をネジで固定する場合は5mmネジを外して10mmネジで固定してください。
![](./img/IMG_6408.jpg)
蓋が浮く場合はニッパーで電池端子のピンヘッダを少し切ってください。
![](./img/IMG_6524.jpg)
ゴム足を取り付けます。
![](./img/IMG_6414.jpg)
キーキャップを取り付けたら本体の完成です。
![](./img/IMG_6420.jpg)
一通りの動作確認をします。

### 4.12 ドックの組み立て
※ドックは無線接続時の給電用です。

フレキシブル基板のほか、画像のプリント品とUSB基板、切り出した2ピンのピンヘッダー、5mmネジ4本、ナット4個を使用します。
![](./img/IMG_5566.jpg)

ピンヘッダーの長い方を基板に差し込み、裏返してニッパーで足を切り、はんだ付けします。![](./img/IMG_5567.jpg)

表にフレキシブル基板をはんだ付けします。
![](./img/IMG_5576.jpg)

プリント品にUSB基板をのせ、ネジとナットで固定します。
![](./img/IMG_5580.jpg)

ドックにネジとナットで固定します。![](./img/IMG_5583.jpg)

ゴム足を付けたら完成です。
![](./img/IMG_6427.jpg)

USBケーブルを接続し、本体を乗せると電源が供給されることを確認します。
![](./img/IMG_6431.jpg)

## 5. 使い方
両手分を作成します。
![](./img/IMG_6438.jpg)

### 5.1 通常版ファームウェアのダウンロード

左右の組み合わせ自由ですがインストールするファームウェアが変わります。
対応したファイルをダウンロードしてください。

| 基板  | 左側に使用する場合                       | 右側に使用する場合                        |
| --- | ------------------------------- | -------------------------------- |
| x7  | [`onthe15-split-left-x7-zmk.uf2`](https://github.com/Taro-Hayashi/New-On-the-15/releases/latest/download/onthe15-split-left-x7-zmk.uf2) | [`onthe15-split-right-x7-zmk.uf2`](https://github.com/Taro-Hayashi/New-On-the-15/releases/latest/download/onthe15-split-right-x7-zmk.uf2) |
| x8  | [`onthe15-split-left-x8-zmk.uf2`](https://github.com/Taro-Hayashi/New-On-the-15/releases/latest/download/onthe15-split-left-x8-zmk.uf2) | [`onthe15-split-right-x8-zmk.uf2`](https://github.com/Taro-Hayashi/New-On-the-15/releases/latest/download/onthe15-split-right-x8-zmk.uf2) |

今回は左手のx7、右手にx8を使用するため、[`onthe15-split-left-x7-zmk.uf2`](https://github.com/Taro-Hayashi/New-On-the-15/releases/latest/download/onthe15-split-left-x7-zmk.uf2)をx7に、[`onthe15-split-right-x8-zmk.uf2`](https://github.com/Taro-Hayashi/New-On-the-15/releases/latest/download/onthe15-split-right-x8-zmk.uf2)をx8にインストールします。

### 5.2 ファームウェアのインストール

>[!NOTE]
>左手用が起動した時に右手用が既に起動されていた方が接続しやすい仕様のため、ファームウェアは右手用に使う方からインストール、電源を入れます。


右手にする方の、ドックではなく本体をUSBケーブルでPCと接続し、左上のキーを押しながらRボタンを押すと新しいドライブが現れます。対応するuf2ファイルをドラッグ&ドロップします。USBケーブルを外す場合は電池を入れてスライドスイッチをオンにします。
![](./img/IMG_7698.jpg)
ドライブが出ない場合は電池の蓋を外してXIAOのボタンを2回押してください。

![](./img/IMG_7534.jpg)

右手側が接続待ちになりインジケーターが赤く点滅します。
同様に左手にする方にも対応するuf2ファイルをインストールして電源が入った状態にすると左右間が接続され、右のインジケーターは消灯します。

USBケーブルを左手に接続している場合はそのまま有線接続で使用可能です。無線で接続する場合は左手用に電池を入れてスライドスイッチをオンにし、ペアリングしてください。

>[!NOTE]
>無線で接続できない場合、接続機器との間にあるUSB3.0機器や他の無線機器が干渉していたり、大きなものが電波の通り道を邪魔していることがあります。配置を変えてみてください。

### 5.3 DYA Studioに接続する

Google ChromeでDYA Studioにアクセスします。

- https://studio.dya.cormoran.works/

DYA Studioで設定を変更するには、アンロックという操作が必要です。
左上のキーを押しながら右下のキーを押すとアンロックできます。アンロックすると左手側のインジケーターが点滅します。
![](./img/IMG_7694.jpg)

有線か無線かを選んでアクセスして、キーマップタブに移動するとキーの入れ替えが出来ます。
![](./img/dya_keymap.png)

x7/x8の組み合わせが間違っている場合はこちらで修正できます。
![](./img/dya_layout.png)

Mod-Tapは長押しでShiftなどの修飾キー、短押しで普通のキーを入力できます。
![](./img/modtap.png)
Layer-Tapは長押しでレイヤーの切り替え、短押しで普通のキーの入力です。![](./img/layer-tap.png)
他にマクロ・コンボ、接続先のプロファイルの管理、スリープに入るまでの時間を設定することが可能です。

### 5.4 固有機能の設定

LEDの光り方や電池の種類を別のWebサイトから設定可能です。

DYA Studioのサブシステムからアクセスするか、直接アクセスして接続します。こちらでの変更にもアンロックの操作が要求されます。
- https://studio.tarohayashi.com/

![](./img/dya_subsystem.png)


電池は種類によって消費のされ方が違います。デフォルトでは電圧の変化が小さいエネループ等のNiMH充電池が設定されています。
アルカリ乾電池への変更と、残量が少なくなってきた時のインジケーターでの警告をオンオフ可能です。

![](./img/dya_battery.png)
インジケーターのオンオフを切り替えることができます。

>[!NOTE]
>消費電力が大きいため、電池で動作させる場合は常時点灯はオフを推奨します。

![](./img/dya_indicator.png)
LEDの発光を調節することができます。![](./img/dya_led.png)
エフェクトは数パターンあるのでお好みに合わせてご利用ください。
![](./img/dya_pattern.png)
これらの設定はDYA Studioからキーに割り当てることも可能です。
![](./img/dya-behavior.jpg)
## 6. トラブルシューティング（随時更新）

### 6.1 右手用のドライブが出てこない。
主体となっている左手用を先にリセットすると、左右間通信ができず右手のドライブを出すコマンドを実行できないことがあります。右手用を先にリセットしてください。
### 6.2 何か調子が悪い
settings-reset-zmk.uf2を書き込むことでXIAOをリセット可能です。
ファームウェア更新の要領で書き込んで待つと再びドライブが出てくるので、再度使用するファームウェアをインストールしてください。

## 7. 保守品・公開データ
### 7.1 公開データ
- [回路図](../sch/SCH.md)
- プリント品（準備中）
- [基板外形、アクリルプレート](../plate/PLATE.md)
- [ガーバー（USB基板、フレキシブル基板）](../gerber/GERBER.md)
- ソースコード
	- [ZMKファームウェア](https://github.com/Taro-Hayashi/New-On-the-15/tree/main/zmk_firmware)
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
	- [RMKファームウェア](https://github.com/Taro-Hayashi/New-On-the-15/tree/main/rmk_firmware)
### 7.2 保守品の入手先
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
- [磁石 6x2mm](https://link.amazon/B0a5OvMwi)
- [ピンヘッダー 2.54mm x 40ピン](https://akizukidenshi.com/catalog/g/g100167/)
- [MXスイッチソケット](https://shop.yushakobo.jp/products/a01ps)
### 7.3 ライセンス

| 対象               | ライセンス     | 詳細                                              |
| ---------------- | --------- | ----------------------------------------------- |
| 回路図              | MIT       | [sch/LICENSE](../sch/LICENSE)                   |
| USB基板ガーバー        | CC0 1.0   | [gerber/LICENSE](../gerber/LICENSE)             |
| フレキシブル基板ガーバー     | CC0 1.0   | [gerber/LICENSE](../gerber/LICENSE)             |
| 基板外形、アクリルプレートデータ | CC BY 4.0 | [plate/LICENSE](../plate/LICENSE)               |
| 本体プリント品データ       | CC BY 4.0 | 準備中                                         |
| 治具プリント品データ       | CC0 1.0   | 準備中                                         |
| ZMKファームウェア       | MIT       | [zmk_firmware/LICENSE](../zmk_firmware/LICENSE) |
| RMKファームウェア       | MIT       | [rmk_firmware/LICENSE](../rmk_firmware/LICENSE) |

2Uスタビライザーはkoktohさんのフットプリントを使用しました。
https://github.com/koktoh/BrownSugar_KBD_KiCad_Library
電池の回路はcormoranさんのdya-dashの回路図を参照しました。
https://github.com/cormoran/dya-dash-keyboard/

### 7.4 販売サイト
- [BOOTH](https://tarohayashi.booth.pm/items/8798135)
