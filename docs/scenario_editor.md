# シナリオ・イベントエディタ 設計(2026-09-21)

世界の中身(マップ・イベント会話・画像の割り当て)を「シナリオ」としてデータ化し、ゲーム本体とは別の**ブラウザのエディタ**で編集できるようにする。設計の経緯は、ユーザーとの2回の質疑(範囲・起動条件・画像・ゲーム側・条件の種類・効果・編集UI・保存形式)で決めた。

## 用語

| 用語 | 意味 |
|---|---|
| シナリオ | キャラ(話者)・NPC・敵の画像割り当て、イベント、マップを一纏めにしたもの。フォルダ1つ |
| イベント | シナリオ内の1つの会話(導入、戦闘、謎解きなど)。発生条件・会話の台本・終了時の効果を持つ |
| デフォルト(default) | リポジトリに含めて公開するシナリオ。`godot/scenarios/<id>/` |
| カスタム(custom) | 個人用で公開しないシナリオ。`user://scenarios/<id>/`(Windowsでは`%APPDATA%\Godot\app_userdata\WorldSeeker\scenarios\<id>\`)。リポジトリには入らない |

## 範囲(決定事項)

- **世界全体をデータ化**する。`world_data.gd`(GDScript直書き)は廃止し、エリア/セクション/フロア/ゲート/アイテムを`world.json`に、会話をイベントのJSONに移す。ゲームはシナリオから世界を組み立てる。
- **エディタで編集できるのは、会話・イベント・画像の割り当て**。マップ(フロア・接続・ゲート)は初版では参照のみ(どのフロアにどのイベントを付けるかを選べる)。マップ編集は次の段階。
- 画像は、既存ライブラリ(`godot/assets/portraits/`の`npc_*`/`enemy_*`/`char_*`)から選ぶのに加えて、**シナリオ固有のPNGをアップロード**できる。
- ゲーム側は、**新規開始時にシナリオを選び、セーブに紐づける**。

## フォルダ構成

```
scenarios/<id>/
  scenario.json     基本情報(id・名前・説明・作者・開始年月)
  world.json        マップ(アイテム・エリア・セクション・フロア)
  cast.json         登場人物(話者名→画像)
  events/<event_id>.json   イベント1本=1ファイル
  images/*.png      シナリオ固有の画像
```

Gitで差分が読めるよう、JSONは整形(インデント2、キー順固定)して書く。

### scenario.json
```json
{"format": 1, "id": "default", "name": "小さな王国", "description": "…", "author": "", "start_year": 0, "start_month": 1}
```

### world.json
順序が意味を持つ(エリアの並び=難度倍率、セクションの並び=退避先の判定)ため、全て配列。
```json
{
  "items":    [{"id": "goblin_amulet", "name": "ゴブリンキングの護符"}],
  "areas":    [{"id": "kingdom", "name": "小さな王国"}],
  "sections": [{"id": "old_cave_dungeon", "name": "古い洞窟", "area": "kingdom"}],
  "nodes":    [{"id": "cave", "name": "洞窟", "section": "old_cave_dungeon", "connections": ["forest_edge", "locked_vault"],
                "gate": {"type": "skill", "skill": "LOCKPICKING", "min_level": 2}, "item_reward": "", "initially_passed": false}]
}
```
ゲート: `skill`(`skill`はSkillTypes.Skillの名前)/`combat`(`enemy_power`)/`item`(`item`)/`innate_trait`(`trait`,`value`)。ゲート無しは`{}`。

### cast.json
```json
[{"name": "案内人", "image": "npc_01", "side": "left"}]
```
画像idは、ライブラリのid(`npc_01`など)か、シナリオ固有画像の`@ファイル名.png`。`side`は、エディタが新しい行を作る時の既定の左右(`left`/`right`)。会話の行に`image`キーがあれば、その行だけ画像を上書きする。表に無い話者は、従来どおり名前のハッシュで自動選択される。

### イベント(events/*.json)
```json
{
  "id": "floor_old_shrine_pass",
  "title": "古い祠(突破)",
  "trigger": {"type": "gate", "floor": "old_shrine", "result": "pass"},
  "conditions": [],
  "repeat": false,
  "priority": 0,
  "kind": "auto",
  "script": [ {"side": "none", "name": "古い祠", "text": "…", "next": 1}, {"side": "none", "name": "", "text": "…", "outcome": "pass"} ],
  "effects": [ {"on": "pass", "type": "set_flag", "flag": "shrine_opened", "value": true} ]
}
```

**トリガー(`trigger.type`)**
- `gate`: フロアのゲート結果。`floor`と`result`(`pass`/`fail`)。探索者がフロアを発見した時、ゲートの結果に合う方が再生される(従来の突破用/失敗用の2本組と同じ)。台本の終わりの`outcome`は`pass`/`fail`にすること(ゲームがこれで突破を確定する)。
- `conditions`: `conditions`の全てが成り立った日に、1度だけ発生する(`repeat: true`なら、成り立っている間は毎日。フラグを降ろす効果と組み合わせて止める)。毎日の探索の最後に判定し、1日に再生するのは、優先度(`priority`)が最も高い(同じならid順の)1本だけ(会話が既に開いていれば、他のイベントは翌日へ持ち越す)。
- `system`: ゲームの決まった場面(案内会話)で、コードから呼ばれる。`name`は`intro_part1`(起動直後)/`intro_part2`(初めての割り当て直後)/`party_formed`(初めての雇用直後)/`retreat`(初めての撤退)。**ユーザーが選んだ条件の種類には無かったが、導入や撤退の説明会話をシナリオ側へ移すために必要なので足した**。

**条件(`conditions[]`、全てAND)**
- `{"type": "day_min", "day": 30}` — 経過日数がN以上
- `{"type": "flag", "flag": "名前", "value": true}` — フラグが立っている(`false`なら立っていない)
- `{"type": "floor_found", "floor": "id"}` / `{"type": "floor_passed", "floor": "id"}`
- `{"type": "section_entered", "section": "id"}` / `{"type": "area_entered", "area": "id"}`

**効果(`effects[]`)**: 会話が終わった時、その`outcome`が`on`と一致する(`"*"`なら全て)ものを順に適用する。
- `{"type": "set_flag", "flag": "名前", "value": true|false}`
- `{"type": "funds", "amount": 100}`(負なら支出。資金は0未満にならない)
- `{"type": "grant_item", "item": "id"}`(そのアイテムをまだ持たない雇用探索者のうち、名簿の先頭の1人へ渡す)
- `{"type": "open_floor", "floor": "id"}`(そのフロアを突破済みにする)

選択肢の結果でフラグを分けたい時は、選択肢ごとに別の`outcome`コード(`help`/`refuse`など)で終わらせ、効果の`on`で分ける。

**種別(`kind`)**: `auto`(フロアのゲートの種類から自動=従来どおり)/`""`(種別なし)/`boss`/`combat`/`skill`/`item`/`bloodline`/`guide`。

## セーブとの関係

会話の中身は**セーブスロットごとに、世界のスナップショット(world_schema_db.gd、内容ハッシュで版管理)に含める**。スナップショットにはワールドに加えて、シナリオ情報・イベント・登場人物表を入れる。よってスロットは、後でシナリオを編集・削除しても、遊び始めた時点の内容で再開できる(画像ファイルだけは外部参照なので、無ければ自動選択の画像に戻る)。

スロットに追加で保存するのは、フラグ(`scenario_flags`)と、発生済みイベント(`scenario_events_fired`)。旧セーブ(この機能より前)のスナップショットには`events`表が無いので、読み込み時にフロアの突破用/失敗用の台本から`gate`イベントを起こし、登場人物表はデフォルトシナリオのものを使う。

## エディタ(`tools/scenario-editor/`)

Node.js製の**依存パッケージなしのローカルサーバー**(`node server.js`)+ ブラウザのページ。ブラウザ単体では、ディスク上のフォルダを自由に読み書きできないため、サーバーがシナリオのフォルダと画像を扱う。

機能: シナリオの一覧・新規作成(デフォルト/カスタムを選ぶ)・複製・削除・読み込み / イベントの追加・編集・削除・検索(エリア/セクション/フロアで絞り込み)/ 会話の行の追加・修正・削除・並べ替え(行リストで編集、分岐先はプルダウン、脇に簡易フロー図)/ 話者の画像の選択とアップロード / 発生条件・効果の編集 / **会話のリプレイ**(ゲーム本体と同じ見た目で再生。選択肢も選べる)/ 検証(行き先の範囲・存在しないフロアやフラグの参照など)。

## 段階と状況(2026-09-21)

1. **データ化(完了)**: 既存の`world_data.gd`+案内会話4本+話者の対応表を、デフォルトシナリオのJSONへ書き出した。読み直した内容が元のWorldMap(順序・ゲート・接続・会話の台本)と差異なしと照合済み。`world_data.gd`は廃止
2. **ゲーム側(完了)**: `scenario_store.gd`(読み書き・変換)、`scenario_events.gd`(条件・効果・フラグ)、`world_schema_db.gd`(スナップショット)、セーブ対応、新規開始時のシナリオ選択。`tools/dev/sim_scenario_events.gd`・`sim_scenario_ui.gd`で確認
3. **エディタ(完了)**: `tools/scenario-editor/`(使い方はそこのREADME)
4. **次の段階**: マップ(フロア・接続・ゲート・セクション・エリア)の編集 / Android実機での確認 / カスタムシナリオのスマホへの持ち込み / 転職禁止などのシナリオ設定

## 実装メモ(形式の細部)

- 行の`next`を省略すると、次の行(i+1)へ進む。ゲームのデータは全ての行に`next: i+1`を明示してあるが、同じ意味。エディタは、行の挿入・削除・移動の前に、この明示を省略へ直す(並びを変えても「一覧の並び=会話の流れ」になるように)。
- 終わり(`outcome`)に達すると会話が終わる。範囲外の`next`も、結果コード無し(`""`)で終わる。フロアの会話(`gate`)は`pass`/`fail`で終わる必要がある(ゲームは、この結果コードでフロアの突破を確定する。エディタが検証する)。
- イベントは、フロアの会話(`gate`)を含め、`ScenarioEvents.play()`で再生する。終了時に発生済みへ記録し、効果を適用する。フロアの会話は、フロアの突破の確定(`Exploration._finalize_discovery`)の後に効果が働く。
- 画像idの`@ファイル名.png`は、そのシナリオの`images/`のPNG。デフォルトシナリオのものは`res://`(エクスポートで取り込まれる)、カスタムは`user://`(実行時に読む)。
- JSONの整形は、ゲーム(`ScenarioStore.write_json`)もエディタ(`JSON.stringify(x, null, 2)`)も同じ(インデント2、キーは入れた順、末尾に改行)。キー順は`logic.js`の`canonicalEvent`が固定する。デフォルトの全イベントを、エディタが読んで書き直しても、1バイトも変わらない(テストで確認済み)。
