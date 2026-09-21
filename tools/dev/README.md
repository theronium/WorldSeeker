# tools/dev — 開発中の確認用スクリプト

ゲーム本体には入らない、動作確認の道具です(`godot/`の外なのでエクスポートされない)。セッション記録は [`docs/SESSION_LOG_2026-09-19_20.md`](../../docs/SESSION_LOG_2026-09-19_20.md)。

## `--script` によるシミュレーション(`sim_*.gd`、`survey_events.gd`)

UIを操作せずに、ゲームのルールだけを確認する使い捨てのテストです。

```
APPDATA=<空の隔離ディレクトリ> "$GODOT_EXE" --headless --path godot --script <このファイルの絶対パス>
```

- **必ず`APPDATA`を差し替える**。そうしないと、実セーブ(`%APPDATA%\Godot\app_userdata\WorldSeeker\`)に触れる(`sim_retreat_save_roundtrip.gd`はセーブ用のスロットを作る)。
- 書き方の作法:
  - `extends SceneTree`にして、**最初の`_process`で本体を走らせ`true`を返す**。`_initialize`の時点では、autoloadの`_ready`が済んでおらず、ワールドが空。
  - autoloadは、コンパイル時の名前では使えない。`root.get_node("Parties")`のように**相対パス**で取る(`/root/...`の絶対パスは使えない)。`class_name`を持つもの(`SkillTypes`、`Jobs`など)はそのまま使える。
  - 新規開始の状態は`root.get_node("SaveSystem").start_fresh_session()`で作る(初期パーティが付く)。
  - `Exploration._on_day_advanced(day)`を直接呼べば、実時間を待たずに日数を進められる。
  - 発見済み・突破済みの状態は、**実際のゲームと同じ範囲**にする(実際より広く発見済みにすると、条件判定が別の理由で動かない)。
- 実行のたびに出るGodotの終了時の`BUG`/`leaked`のログは無視してよい。
- **シミュレーションは、1つごとに新しい空の`APPDATA`で実行する**。前のシミュレーションの保存先を使い回すと、`sim_scenario_events.gd`の「デフォルトの導入は未視聴」などの前提が崩れて失敗する(2026-09-21に、4つを同じ`APPDATA`で続けて流して、1件だけ失敗した。新しい環境で流し直すと全て成功)。

| ファイル | 確認していること |
|---|---|
| `sim_post_clear.gd` | 完全踏破後の再配置(ループ/先へ進む) |
| `sim_retreat.gd` | 勝てない敵からの退避、退避中の経験値、強化後の復帰、手動解除 |
| `sim_encounter_order.gd` | フロアに着いてからの進み方が「会話 → 判定の適用 → イベントの効果 → 撤退」の順か: 勝てない相手・実戦闘での敗北・勝利・日次の流れの4通りで、会話が開いている間はHP・休養・突破・退避が動かず、閉じた後に反映されること(2026-09-21、会話を読んでいる時点で既に退避先へ戻っていた、の再発防止) |
| `sim_roster_ui.gd` | 探索者一覧の並べ替え・絞り込み・総合戦力の表示(`RosterQuery`、`main.gd`)と、会話パネルの「次へ」の押しやすさ(下端から浮かす・クリックで進む・Enter/Spaceで進む): ロジック(内訳=合計、同値はID順、AND絞り込み)・画面(メイン画面を組み立てて操作)・会話パネル(選択肢の行では進まない、echoでは進まない等)。`RosterQuery`はオートロードを参照するので`load()`して呼ぶ |
| `sim_daily_log.gd` | ログウィンドウ(掲示板・イベント・毎日の動きから2つを選んで並べる)と、毎日の動き(`DailyLog`)の確認: 状態の判定(探索中/回復中/力を付けている/周回中、未割当は出さない)、同じ日の記録し直し、90日の保持、まとめ表示の区間(日が連続しなければ分かれる)、2枠・絞り込み・掲示板のスレッドを開く・自動更新、探索との連携(会話が閉じて退避が反映された後に、その日の動きが「力を付けている」に記録し直される)、ロード/新規プレイで空から |
| `sim_party_icon.gd` | マップのパーティアイコンを出すフロア(`main.gd`の`_current_node_for_party`)の確認: 次のセクションへ配置転換された直後(まだ何も発見されていない)は、セクションの最後のフロアではなく、入口(探している最前線のフロア)に出す。発見済み・最前線・周回の優先順は従来どおり(2026-09-21、「最終フロアをクリアした後、次のセクションの一番最後に一瞬移動する」の再発防止) |
| `sim_time_bar.gd` | タイムバー(左メニューの「今日」「今月」。`time_bar.gd`、`main.gd`の`_refresh_time_bars`)の確認: `TimeSystem.day_progress/month_progress`(進みの計算・実時間での進み・月末の待ち)、`TimeBar`(割合のクランプ・縞の時だけ毎フレーム動く)、画面(通常・100x以上は縞・月末の集計待ちは橙の満タン・会話中は灰色で止まる) |
| `sim_party_members.gd` | 雇用上限の4人単位(初期8・拡張+4・旧セーブの切り上げ)と、パーティのメンバー操作の確認: `Parties.add_members/remove_member/free_slots`(満員・重複・所属済み・存在しないIDは何も変えずに失敗、最後の1人は外せない、セーブ往復)、`MemberPicker`(チェックボックスを1人ずつタップして複数選べる=Androidで1人しか選べなかったバグの再発防止、上限に達したら残りは押せない、中身が同じなら行を作り直さない)、画面の操作(編成・追加・外す・満員表示) |
| `sim_retreat_save_roundtrip.gd` | 退避状態のSQLiteのセーブ往復 |
| `survey_events.gd` | イベント会話のあるフロアの、ゲート種別ごとの集計 |
| `sim_scenario_events.gd` | シナリオ・イベントの仕組み全体(docs/scenario_editor.md): カスタムシナリオでの新規開始と暦の起点、条件イベント(日数・フラグ)、効果(資金・フラグ・フロア開放)、ゲート結果の会話、セーブ往復、別シナリオへの切替と、編集後も古いスロットが遊び始めた時点のままか、旧形式スキーマの読込、画像の読込、読み込み時間 |
| `sim_map_edit.gd` | マップ編集(tools/scenario-editor/)の確認: エディタのロジック(`worldlogic.js`)で編集したシナリオ(エリア・セクション・フロアの追加、ID変更、並べ替え、移動、削除、4種のゲート、アイテム定義)を、ゲーム本体が読めて、並び・接続・ゲート・アイテム・イベントが期待どおりか、追加したフロアを実際に発見できるか、セーブ往復。**前処理が要る**: `APPDATA=<隔離dir> node tools/scenario-editor/test/make_edited_scenario.js <隔離dir>/Godot/app_userdata/WorldSeeker/scenarios`(編集済みシナリオと期待値を書き出す)→ 同じ`APPDATA`で`--script`実行 |
| `sim_scenario_transfer.gd` | シナリオのzipの取り込み(スマホへの持ち込み。`godot/scripts/scenario_transfer.gd`)の確認: エディタが書き出したzipを検査して取り込み、そのシナリオで新規プレイでき(画像も読める)、同じIDの上書き・遊び始めたセーブが無事・削除・相対パスの無視ができるか、不正なzip12種(セーブのファイル・新しい版・不正なID/技能/ゲートのキー/セクション/重複/効果・PNGでない画像・展開爆弾・zipでない)を何も取り込まずに断るか。**前処理が要る**: `APPDATA=<隔離dir> node tools/scenario-editor/test/make_transfer_zips.js <隔離dir>/Godot/app_userdata/WorldSeeker/transfer_test` → 同じ`APPDATA`で`--script`実行 |
| `sim_scenario_transfer_ui.gd` | 上と同じzip(同じ前処理)で、メイン画面の操作の通し: 不正なzipの理由の表示、確認画面の内容、取り込み、上書きの確認、戻るキーでやめる(一時ファイルも消える)、管理の一覧・削除・開き直し |
| `sim_scenario_ui.gd` | メイン画面を実際に組み立てて、シナリオ選択→新規プレイ→別の世界(エリアバー・マップ)の描画→標準へ戻す |
| `export_default_scenario.gd` | (一度きりの移行ツール。元の`world_data.gd`を廃止したので、もう実行できない)デフォルトシナリオのJSONを書き出し、元のWorldMapと照合した |

## 実機(Android)の確認(`android/`)

**引数なしで動く**(2026-09-20に、実機のAPKを使い捨てキーから本物のリリース鍵へ切り替えた)。

- **起動のしかた(2026-09-21)**: **Git Bash**で実行する。PowerShell/cmdで`bash tools/dev/android/run_on_phone.sh`と打つと、Windowsに入っている**WSL(Linux)のbash**が起動し、パスが`/mnt/d/...`になって「ビルド道具が見つかりません」と出て動かない(スクリプトは`/d/...`のパスと`cygpath`を前提にしている。WSLで実行された場合は、その旨と正しい起動方法を表示して止まる)。PowerShell/cmdからは`tools\dev\android\run_on_phone.cmd`(Git Bashを直接指定して起動する入り口。引数はそのまま渡す)を使う。
- `run_on_phone.sh ["logcatで待つ正規表現"]`: コンパイル確認 → **リポジトリから直接**リリースAPKをエクスポート(作業ツリーの内容がそのまま載る) → 署名者が本物のキーの指紋と一致するか確認 → `adb install -r`(スマホのセーブは残る) → 起動 → エラーの有無を表示。
  - 署名キーは`C:\Users\thero\worldseeker-signing\`の`worldseeker-release.keystore`と`PASSWORD.txt`を**実行時に読む**(パスワードはスクリプトにもリポジトリにも書かない)。場所は`WS_SIGNING_DIR`などの環境変数で変えられる。
  - **インストールのたびにゲームは再起動し、新規開始になる**。
- `env.sh`: ビルド道具(adb・JDK・Android SDK・Godotのエディタ設定とエクスポートテンプレート)の場所を決める。置き場は**`D:\DevTools\godot-android`**(恒久。プロジェクトに依存しない道具なので、他のGodotプロジェクトでも使い回せる。中身と移し方はそのフォルダの`README.txt`)。`WS_TOOLS`で別の場所を指定でき、`D:\DevTools\godot-android`が無ければ、前のセッションのTemp配下の作業フォルダを探す(Tempは消えることがある)。署名キーはこのフォルダには置かない(`C:\Users\thero\worldseeker-signing\`)。
- `gtap.sh <x> <y>`: 前面のアプリがゲームの時だけタップする(誤って別のアプリを操作しない)。ポップアップは「閉じる」ボタンのタップで閉じ、戻るキーは使わない(戻るキーでアプリが終了し、続けて送ったタップがホーム画面の別のアプリを押した実例がある)。
- スクリーンショット: `adb exec-out screencap -p > out.png`。複数枚は`PIL`で切り出して1枚にまとめると見やすい。
- **署名不一致(`INSTALL_FAILED_UPDATE_INCOMPATIBLE`)で失敗しても、アンインストールしない**(スマホのセーブが消える)。本物のキーで署名したAPKの間は、この問題は起きない。
