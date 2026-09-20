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

- `run_on_phone.sh`: コンパイル確認 → APKを作る → `adb install -r` → 起動 → ログを待つ。環境変数と作業ディレクトリの前提はファイルの先頭に書いてある。**同期するのは`scripts/*.gd`だけ**(それ以外を変えたら、作業ディレクトリの複製に自分で反映する)。**インストールのたびにゲームは再起動し、新規開始になる**。
- `gtap.sh`: 前面のアプリがゲームの時だけタップする(誤って別のアプリを操作しない)。ポップアップは「閉じる」ボタンのタップで閉じ、戻るキーは使わない(戻るキーでアプリが終了し、続けて送ったタップがホーム画面の別のアプリを押した実例がある)。
- スクリーンショット: `adb exec-out screencap -p > out.png`。複数枚は`PIL`で切り出して1枚にまとめると見やすい。
- keystoreのパスワードはコミットしない(環境変数で渡す)。実機に入っているAPKと鍵が違うと`install -r`は失敗する。その時にアンインストールするとスマホのセーブが消えるので、しない。
