# upstream報告の日本語版（読む用）

投稿用の本文は英語で `upstream-runtime-combo-list-issue.md` と
`upstream-custom-settings-behavior-load-order-issue.md` にあります。これはその内容を
日本語で読むためのもので、投稿には使いません。内容が食い違ったら英語版が正です。

---

## 全体の経緯

DYA StudioからRuntime Comboを保存しても、一覧に出ず、再起動すると消える、という症状から
調査を始めました。最終的に**独立した3つの不具合**が重なっていたことが分かりました。

| # | 場所 | 症状への寄与 |
| --- | --- | --- |
| 1 | custom-settings | 新規コンボが一覧にも保存対象にもならない |
| 2 | runtime-combo | 一覧が空になり、上書きが起き、UIから復旧できない |
| 3 | custom-settings | 保存は成功するのに再起動で消える |

1番は調査開始前に特定・修正済みだったもので、今回の報告対象は2番と3番です。

---

## 報告1: runtime-combo — 一覧が全滅する

### 何が起きるか

`handle_list_combos()` は、スロットの読み出しに失敗したとき `-ENOENT`（未使用スロット）だけを
飛ばし、それ以外のエラーではその場で処理を打ち切って一覧全体をエラーにします。

保存されているビヘイビアのlocal IDが、現在動いているファームで解決できないスロットが1つでも
あると、`zmk_runtime_combo_read()` が `-ENODEV` を返します。その結果、**正常なスロットまで
含めて一覧が丸ごと失われます**。

一覧が空になるとUIからどのスロットにも触れなくなるため、原因のスロットを直すことも消すことも
できません。設定を全消去するしか復旧手段がなくなります。

### どうやって踏んだか

Runtime Macro入りのファームでコンボに `&rmacro` を割り当て、その後Macroなしのファームへ
戻したためです。そのビヘイビアがもう存在しないのでIDが解決できません。特殊な操作ではなく、
キーマップやモジュールからビヘイビアを1つ減らすだけで同じことが起こります。

### 症状

- 一覧が空で、更新を押しても変わらない
- 作ったコンボは物理的には効く（デコード済みキャッシュは正常なため）
- 新規作成すると既存のコンボを上書きする。UIが空の一覧から次のindexを決めるので常に0番になる
- 再起動すると保存されていないように見える

最後の点にいちばん時間を取られました。書き込みも保存も成功していて、データは本当に
フラッシュに入っています。**読み出せないだけ**でした。

### 実機ログ

```
DIAG list_combos count=2 max=4
DIAG list_combos slot=0 fill_ret=0        <- 正常なスロット
DIAG list_combos slot=1 fill_ret=-19      <- -ENODEV、古いビヘイビア参照
DIAG rpc request_type=1 ret=-19           <- 一覧全体が中断
DIAG save ret=0 affected=9                <- 保存自体は成功している
```

### 修正案

読めないスロットは飛ばして続行するだけです。

```c
if (ret < 0) {
    LOG_WRN("Runtime combo slot %u is not listable (%d) - skipping", i, ret);
    continue;
}
```

### 残る論点（報告文にも書いた）

飛ばす方式だと正常なスロットは見えるようになりますが、壊れたスロットは見えないまま残り、
UIから消せません。本来は「解決できないIDをそのまま返してUIに壊れた項目として表示し、
付け替えか削除をさせる」方が親切です。ただしそれは `zmk_runtime_combo_read()` の契約変更に
なり、壊れたバインディングをキャッシュが実行しない保証も要るため、こちらでは踏み込まず
判断を委ねています。

---

## 報告2: custom-settings — BEHAVIOR値が起動ごとに捨てられる

### 何が起きるか

`value_from_storage()` は永続値を適用する前に検証を行い、BEHAVIOR型では
`zmk_behavior_find_behavior_name_from_local_id()` でlocal IDを解決しようとします。

ところが `CONFIG_ZMK_BEHAVIOR_LOCAL_ID_TYPE_SETTINGS_TABLE` では、**そのIDテーブル自体が
`settings_load()` の中で作られます**。保存済みのIDは `behavior` subtree のsetハンドラで適用され、
まだIDを持たないビヘイビアは同subtreeの**commitハンドラ**で採番されます。commitはそのパスの
setコールバックが全部終わった後に走ります。

したがって、IDテーブルが完成する前に読まれた `custom_settings` のレコードはIDを解決できず、
検証が `-EINVAL` で失敗し、**その永続値が黙って捨てられます**。設定はデフォルトへ戻り、
バインディングは毎回の起動で失われます。

同じサブシステムのスカラー値やBYTES値は問題なくロードされるため、順序の問題ではなく
部分的なデータ破損のように見えます。ここが厄介でした。

### 実機ログ

```
# 起動時の settings_load() 中
load record cormoran__runtime_combo/names/0     len=11 ret=0
load record cormoran__runtime_combo/combos/0    len=16 ret=0
load record cormoran__runtime_combo/behaviors/0 len=6  ret=-22   <- 捨てられる

# 起動12秒後、遅延ワークから
boot behaviors[0] read_ret=0 id=0          <- デフォルト。保存値は消えている
reload subtree ret=0
load record cormoran__runtime_combo/behaviors/0 len=6 ret=0      <- 今度は通る
after-reload behaviors[0] read_ret=0 id=4  <- 本来の値が復元される
```

**同じレコードが、起動時は拒否され、12秒後には受け入れられます。**保存は一度も問題では
ありませんでした。`settings_save_one()` は毎回0を返しています。

### 修正案

永続化されたビヘイビア値は書き込み時に検証済みです。また読み手はどのみち解決できないIDを
扱えなければなりません（ファーム更新でビヘイビアが消えることはある）。よってロード経路では
範囲チェックだけにして、解決は読み手に任せます。

```c
static bool applying_persisted_value;

static int validate_behavior_value(const struct zmk_custom_setting_behavior_value *behavior) {
    if (behavior->behavior_id >= UINT16_MAX) {
        return -ERANGE;
    }
    if (applying_persisted_value) {
        return 0;
    }
    /* ...実行時の検証はそのまま... */
}
```

このフラグは `value_from_storage()` 内の `zmk_custom_setting_validate()` 呼び出しの前後で
立てます。そこはすでに `custom_settings_lock` を保持しているので競合しません。
`validate_behavior_id_constraint()` にも同じ免除が要ります。BEHAVIOR_ID制約を持つINT32設定が
まったく同じ順序問題を踏むためです。RPC経由の実行時書き込みは従来どおり完全に検証されます。

### 代案（報告文にも書いた）

このモジュール自身のcommitハンドラでsubtreeを読み直す方法でも直り、ロード時の検証を厳しい
まま保てます。ただし `behavior` と `custom_settings` のcommit実行順はリンク順に依存し、
モジュール側から保証できません。そのため解決チェックを省く方を選びました。

---

## 「修正は数行だけなのか」について

はい、実際のコード変更は2件合わせて20行ほどです。ただしこれは、この種の不具合として
おかしなことではありません。

- どちらも**順序と境界条件のバグ**です。ロジックが間違っているのではなく、「いつ実行されるか」
  「例外的な入力をどう扱うか」がずれているだけなので、直す量は小さくなります
- 時間がかかったのは修正ではなく**特定**の方です。保存側は最初から最後まで正常に動いていて、
  失敗はすべて読み出し側に出ていました。しかも起動時のログはUSB列挙前に流れるため、通常は
  観測できません。診断ファームを作り、遅延ワークで起動後に読み直させて、ようやく
  「同じレコードが時刻によって通ったり通らなかったりする」ことを掴めました
- 変更が小さいことは、報告としてはむしろ良い材料です。レビューが容易で、副作用の範囲が
  読み切れて、取り込まれやすくなります

報告文の価値は差分そのものより、**症状・再現条件・実機ログ・原因の説明**にあります。そこが
分量の大半を占めているのはそのためです。


---

## 未報告の記録: Runtime Macro（issue化は保留）

Phase 8 の実機確認で見つかったもので、ユーザー判断により issue は出していません。別件で
問題になった場合に、この記録から起こせます。投稿用の英語下書きは
`upstream-runtime-macro-issue.md` にあり、下記1と3をリネームの件とセットにしてあります。

### 1. `-ENOSPC` を種類を問わず「プール満杯」と表示する

`runtime_macro_rpc_handle_request()` の末尾が、あらゆる `-ENOSPC` を
`Macro pool full: delete or shrink another macro` に変換します。しかし `-ENOSPC` は
再生キューの項目数上限（`CONFIG_ZMK_RUNTIME_MACRO_QUEUE_SIZE`）やエンコードバッファの
容量からも返ります。

実機では、プール使用量が `61 / 512 bytes` しかない状態でこのメッセージが出ました。案内に
従って他のマクロを削除しても、絶対に解決しません。原因と対処が食い違う誤誘導で、調査中に
一度この表示に引っ張られました。

確定させた実機ログ:

```
DIAG write ret=0 pool_used=61 pool_size=512      <- プールは空いている
DIAG append_seq keys=63 capacity=192 offset=2    <- エンコードも溢れていない
DIAG rpc request_type=7 ret=-28                  <- SetMacroStep が -ENOSPC
```

`-ENOSPC` の発生元は `read_key_tap_sequence()` → `append_item()`。文字列ステップは1キーに
つき再生キューを1項目消費するため、`QUEUE_SIZE` を超えた時点で失敗します。

### 2. `QUEUE_SIZE` と `MAX_BYTES` が構造的に釣り合わない

`MAX_BYTES` は最大256まで設定できる一方、`QUEUE_SIZE` の `range` は `1 128` です。純粋な
キータップ列なら本体1バイトが1項目に対応するため、`MAX_BYTES > 131` 程度の設定は原理的に
デコードできない本体を許すことになります。Kconfig のヘルプは「MAX_BYTES と一緒に上げろ」と
書いていますが、上げきれません。

### 3. リネームが一時的にスロットとプールを二重に消費する

`zmk_runtime_macro_rename()` は新しい名前で作成してから古いエントリを削除します。このため
リネーム中だけスロットが1つ余分に必要で、`COUNT` 分が埋まっているとリネームが失敗します。
プールも一時的に2倍必要になるため、スロットに空きがあってもプール残量次第で失敗しえます。

リネームは本来スロット数を増やす操作ではありません。keyspace 側にキーだけを差し替える
リネームを用意するのが筋です。順序を入れ替えて「削除してから作成」にするのは、作成失敗時に
データを失うため避けるべきです。

回避策は、先に不要なマクロを1つ削除してからリネームすること。
