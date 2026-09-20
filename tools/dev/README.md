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

| ファイル | 確認していること |
|---|---|
| `sim_post_clear.gd` | 完全踏破後の再配置(ループ/先へ進む) |
| `sim_retreat.gd` | 勝てない敵からの退避、退避中の経験値、強化後の復帰、手動解除 |
| `sim_retreat_save_roundtrip.gd` | 退避状態のSQLiteのセーブ往復 |
| `survey_events.gd` | イベント会話のあるフロアの、ゲート種別ごとの集計 |

## 実機(Android)の確認(`android/`)

**引数なしで動く**(2026-09-20に、実機のAPKを使い捨てキーから本物のリリース鍵へ切り替えた)。

- `run_on_phone.sh ["logcatで待つ正規表現"]`: コンパイル確認 → **リポジトリから直接**リリースAPKをエクスポート(作業ツリーの内容がそのまま載る) → 署名者が本物のキーの指紋と一致するか確認 → `adb install -r`(スマホのセーブは残る) → 起動 → エラーの有無を表示。
  - 署名キーは`C:\Users\thero\worldseeker-signing\`の`worldseeker-release.keystore`と`PASSWORD.txt`を**実行時に読む**(パスワードはスクリプトにもリポジトリにも書かない)。場所は`WS_SIGNING_DIR`などの環境変数で変えられる。
  - **インストールのたびにゲームは再起動し、新規開始になる**。
- `env.sh`: ビルド道具(adb・JDK・Android SDK・Godotのエディタ設定とエクスポートテンプレート)の場所を決める。置き場は**`D:\DevTools\godot-android`**(恒久。プロジェクトに依存しない道具なので、他のGodotプロジェクトでも使い回せる。中身と移し方はそのフォルダの`README.txt`)。`WS_TOOLS`で別の場所を指定でき、`D:\DevTools\godot-android`が無ければ、前のセッションのTemp配下の作業フォルダを探す(Tempは消えることがある)。署名キーはこのフォルダには置かない(`C:\Users\thero\worldseeker-signing\`)。
- `gtap.sh <x> <y>`: 前面のアプリがゲームの時だけタップする(誤って別のアプリを操作しない)。ポップアップは「閉じる」ボタンのタップで閉じ、戻るキーは使わない(戻るキーでアプリが終了し、続けて送ったタップがホーム画面の別のアプリを押した実例がある)。
- スクリーンショット: `adb exec-out screencap -p > out.png`。複数枚は`PIL`で切り出して1枚にまとめると見やすい。
- **署名不一致(`INSTALL_FAILED_UPDATE_INCOMPATIBLE`)で失敗しても、アンインストールしない**(スマホのセーブが消える)。本物のキーで署名したAPKの間は、この問題は起きない。
