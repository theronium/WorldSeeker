# リリース手順

WorldSeeker の Windows 版と Android 版を GitHub Releases に出すための手順と、その仕組みをまとめた資料です。
最初のリリースは `v0.1.0`(2026-09-24、Pre-release)。

## 仕組みの全体像

- **配布先**は GitHub Releases だけ(itch.io・Google Play には出していない)。
- `.github/workflows/release.yml` が、`v*` タグの push で次を行う。
  1. 非公開の素材リポジトリ `theronium/WorldSeeker-assets` から BGM を取得し、`godot/assets/music/` に置く。
  2. Android 版 APK(arm64、本物のリリースキーで署名)と、Windows 版(x86_64)をエクスポートする。
  3. Windows 版は exe(ゲームのデータを埋め込み済み)と SQLite の DLL を `WorldSeeker/` フォルダごと zip にする。
  4. タグ名で GitHub Release を作り、`WorldSeeker-<版>-windows.zip` と `WorldSeeker-<版>-android.apk` を添付する。
     版番号が `0.x`、または `-` 付き(`v0.2.0-rc1` など)なら **Pre-release** になる。
- 手動実行(`gh workflow run release.yml`)では Release は作らず、Artifact として保存するだけ。試しビルドに使う。

### BGM を公開リポジトリに入れていない理由

BGM「森の旅」(OpenTracks)の規約は、「エンドユーザーが音源ファイルに音声ファイルとして容易にアクセス・複製できる状態」での公開を禁じている。
ゲームに組み込んで配ることは許可されている。そのため、次のようにしている。

- mp3 はこの公開リポジトリには入れない(`.gitignore` で除外済み。過去の履歴からも削除済み)。
- 非公開の `theronium/WorldSeeker-assets` に置き、CI だけが読み取り専用の Deploy key で取得する。
- **タグでのビルドで BGM を取得できなかった時は、CI を失敗させる**(BGM 無しの版を配らないため)。手動実行なら警告だけ出して続ける。
- 手元で開発する時は、mp3 を `godot/assets/music/` に置いておく(無ければ BGM 無しで起動する)。

**新しい音楽・効果音・フォントを足す時**は、配布元の規約で「素材ファイル単体の再配布」が許されているかを先に確かめる。
許されていないものは BGM と同じく、素材リポジトリに置いて CI で取得する。
ライセンス表記は `godot/licenses/` に置き、`license_info.gd` の `ENTRIES` に1行足す。

## 必要な設定(登録済み)

リポジトリ `theronium/WorldSeeker` の Actions secrets:

| 名前 | 中身 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | リリース用キーストアを base64 にしたもの |
| `ANDROID_KEYSTORE_PASSWORD` | キーストアのパスワード |
| `ANDROID_KEY_ALIAS` | `worldseeker` |
| `ASSETS_DEPLOY_KEY` | `WorldSeeker-assets` を読むための SSH 秘密鍵(読み取り専用の Deploy key と対) |

- 署名キーの原本は `C:\Users\thero\worldseeker-signing\`(リポジトリの外)。署名証明書の SHA-256 は
  `54:D1:BF:C7:3D:49:0F:CC:BD:E7:C5:98:5E:DC:0B:0E:27:55:C3:BD:FB:17:A7:6D:DE:B7:DE:3F:B7:6A:36:1B`。
  **このキーを失うと、インストール済みのアプリを更新できなくなる。**
- Secrets の値は後から読み出せない。登録し直す時は同じ名前で上書きする(下の「困った時」)。

## リリースの手順

1. **中身を確かめる**
   - `main` の変更が全てコミット・push 済みで、作業ツリーが空であること(`git status`)。
   - PC 版をひととおり遊べること。可能ならスマホ実機でも確かめる(`bash tools/dev/android/run_on_phone.sh`)。
2. **(任意)試しビルド**
   ```
   gh workflow run release.yml --ref main
   gh run watch <run id> --exit-status
   ```
   Artifact(`WorldSeeker-0.0.0-dev.<番号>-windows.zip` / `-android.apk`)をダウンロードして確かめる(下の「ビルドの確かめ方」)。
3. **タグを打って push する**(版番号の付け方は下)
   ```
   git tag -a v0.2.0 -m "WorldSeeker v0.2.0"
   git push origin v0.2.0
   ```
4. **CI の完了を待つ**
   ```
   gh run list --limit 1
   gh run watch <run id> --exit-status
   gh release view v0.2.0
   ```
   Assets に zip と APK の2つがあり、0.x なら Pre-release になっていることを確かめる。
5. **リリースノートを整える**
   自動で作られるノートはコミットの一覧だけなので、遊ぶ人向けの説明を先頭に足す。
   `v0.1.0` の本文(`gh release view v0.1.0`)をひな形にして、版番号と変更点を書き換える。
   ```
   gh release view v0.2.0 --json body --jq .body > generated.md
   # head.md に説明を書き、generated.md の前に連結する
   cat head.md generated.md > notes.md
   gh release edit v0.2.0 --notes-file notes.md
   ```
   説明に入れるもの: ゲームの紹介、プレビュー版の注意(0.x の間)、今回の主な変更、ダウンロードの表、
   Windows の「PC が保護されました」警告の通り方(「詳細情報」→「実行」)、Android の提供元不明アプリの許可、
   Windows のセーブの場所(`%APPDATA%\Godot\app_userdata\WorldSeeker\`)、ライセンス。

### 版番号の付け方

- タグは `v<メジャー>.<マイナー>.<パッチ>`(例 `v0.2.0`)。候補版は `v0.2.0-rc1` のように `-` を付ける。
- **0.x の間はプレビュー版**(Pre-release)。セーブの互換を壊す変更もありうる、と説明に書く。
- CI がタグから自動で設定するので、`export_presets.cfg` の版番号を手で直す必要はない。
  - Android: `versionName` = タグから `v` を除いたもの、`versionCode` = CI の実行番号(`run_number`、単調増加)。
  - Windows: ファイルバージョン = `<メジャー>.<マイナー>.<パッチ>.0`(`-` 以降は落とす。Windows は数字4つしか書けないため)。
- 間違えたタグを消す時は、Release とタグの両方を消してから打ち直す:
  `gh release delete v0.2.0 --cleanup-tag`(ローカルのタグも `git tag -d v0.2.0`)。

## ビルドの確かめ方

- **Windows 版**: zip を展開して `WorldSeeker/WorldSeeker.exe` を起動する。
  実際のセーブを汚さないよう、`APPDATA` を空の一時フォルダに向けて起動する
  (Git Bash なら `APPDATA="$(cygpath -w <一時フォルダ>)" ./WorldSeeker.exe --log-file <ログ>`)。
  ログに `[scenario] 起動: default …` が出て、「BGMの音源が見つからない」の警告が出ないこと。
  exe のアイコン・バージョン情報は、PowerShell の `(Get-Item WorldSeeker.exe).VersionInfo` で見られる。
- **Android 版**: 署名を確かめる。
  ```
  JAVA_HOME="$(cygpath -w /d/DevTools/godot-android/jdk)" \
    /d/DevTools/godot-android/sdk/build-tools/<版>/apksigner.bat verify --print-certs WorldSeeker-*.apk
  ```
  SHA-256 が上の値と一致すること。BGM は `unzip -l <apk> | grep bgm` で `.mp3str` が入っていること。
- **ダウンロードが途中で止まる時**: この PC の回線では `gh run download` が止まることがある。
  Artifact の API(`/repos/theronium/WorldSeeker/actions/artifacts/<id>/zip`)が返すリダイレクト先の URL を、
  `curl -C - --max-time 60` で繰り返し取得すると、途中から再開できる。

## スマホの手元ビルドとの関係(注意)

- `run_on_phone.sh` で作る APK は、`export_presets.cfg` の `version/code=1` のまま。
  リリース版は CI の実行番号(2以上)なので、**スマホにリリース版を入れると、その後の手元ビルドは
  ダウングレードとして拒否される**。開発用のスマホにはリリース版を入れないこと
  (入れてしまったら、手元ビルドの versionCode を上げる対応が必要。アンインストールするとセーブが消える)。
- 署名は同じリリースキーなので、手元ビルド → リリース版への上書きはできる(セーブは残る)。

## 困った時

- **BGM の取得で失敗する**(`BGMの音源を取得できませんでした`): `ASSETS_DEPLOY_KEY` か Deploy key が無効になっている。
  鍵を作り直して、公開鍵を素材リポジトリの Deploy key(読み取り専用)に、秘密鍵を Secret に登録し直す。
  ```
  ssh-keygen -q -t ed25519 -N "" -C "WorldSeeker CI (read-only assets)" -f <一時ファイル>
  gh repo deploy-key add <一時ファイル>.pub -R theronium/WorldSeeker-assets --title "WorldSeeker CI (read-only)"
  gh secret set ASSETS_DEPLOY_KEY -R theronium/WorldSeeker < <一時ファイル>
  ```
  終わったら一時ファイルを消し、古い Deploy key を `gh repo deploy-key delete` で消す。
- **署名キーの Secrets を登録し直す**: Git Bash で次を実行する(値は画面に出ない)。
  ```
  base64 -w0 /c/Users/thero/worldseeker-signing/worldseeker-release.keystore | gh secret set ANDROID_KEYSTORE_BASE64 -R theronium/WorldSeeker
  tr -d '\r\n' < /c/Users/thero/worldseeker-signing/PASSWORD.txt | gh secret set ANDROID_KEYSTORE_PASSWORD -R theronium/WorldSeeker
  printf 'worldseeker' | gh secret set ANDROID_KEY_ALIAS -R theronium/WorldSeeker
  ```
  PowerShell のパイプは値の末尾に改行を足すことがあるので使わない。
  VSCode 拡張の Claude Code では `!` で始まるコマンドは実行されない(ターミナルで直接実行する)。
- **Godot の版を上げる**: `release.yml` の `GODOT_VERSION` を変える。エクスポートテンプレートのキャッシュは
  版ごとのキーなので自動で取り直される。Android の build-tools の版(`36.1.0`)も合わせて確かめる。
- **非公開の素材リポジトリ `WorldSeeker-assets` は、絶対に公開しないこと**(BGM の単体再配布になる)。
