class_name LicenseInfo
# ゲーム内の「ライセンス」画面(左メニューの一番下のボタン)に出す文書の一覧と、その読み込み。
#
# 文書は`res://licenses/`に置く(Godotのプロジェクトの中に無いと、APK/exeに入らないため)。
# テキストファイルはエクスポートに自動では含まれないので、エクスポート設定の
# 「非リソースファイルを含めるフィルター」に`licenses/*`を入れてある(godot/export_presets.cfg)。
# Windows向けのエクスポート設定を作る時も、同じフィルターを入れること。
#
# 音楽・効果音・フォントなど、ライセンス表示が必要な素材を追加する時の手順:
#   1. その素材のライセンス文・クレジット(作者名、配布元URL、ライセンス名など)を
#      `godot/licenses/`にテキストかMarkdownで置く(例: LICENSE-AUDIO.md)
#   2. 下のENTRIESに1行足す(表示順・見出しはここで決まる)
# 画面側のコードは変更不要。ファイルが見つからない時は、画面に「見つかりません」と出るので、
# エクスポートのフィルターの入れ忘れにも気付ける。
#
# 原本の置き場所: ゲームのコードのライセンスはリポジトリ直下の`LICENSE`(GitHubの自動認識用)にもあり、
# `licenses/LICENSE.txt`はその写し(内容を変える時は両方直すこと)。それ以外の文書は
# `godot/licenses/`が唯一の原本。

const LICENSE_DIR := "res://licenses/"

const ENTRIES := [
	{"title": "このゲーム(MIT License)", "file": "LICENSE.txt"},
	{"title": "キャラクター画像・背景画像", "file": "LICENSE-IMAGES.md"},
	{"title": "Godot Engine と godot-sqlite", "file": "THIRD_PARTY_NOTICES.md"},
	# 例: {"title": "音楽・効果音", "file": "LICENSE-AUDIO.md"},
]

const HEADING_COLOR := "#ffd54a"
const SUBHEADING_COLOR := "#9ecbff"

static func load_text(file_name: String) -> String:
	var path := LICENSE_DIR + file_name
	if not FileAccess.file_exists(path):
		return "(ライセンス文が見つかりません: %s)" % file_name
	return FileAccess.get_file_as_string(path).replace("\r", "")

## 全ての文書を、見出し付きの1つのBBCode文字列にまとめる(RichTextLabelで、上から順に読める)。
static func to_bbcode() -> String:
	var sections: PackedStringArray = []
	for entry in ENTRIES:
		sections.append("[font_size=20][color=%s]%s[/color][/font_size]\n\n%s" % [
			HEADING_COLOR, entry["title"], _markdown_to_bbcode(load_text(entry["file"]))])
	return "\n\n----------------------------------------\n\n".join(sections)

## 文書のMarkdownを、画面用に整形する。
##  - 本文中の「[」はBBCodeとして解釈されないよう退避し、バッククォートは外す
##  - 「# 見出し」「## 見出し」は色付きの見出しにする(文書の先頭の「# タイトル」は、画面側で見出しを
##    出すので省く)
##  - 元のファイルは約80文字で改行されているため、そのまま出すと画面の幅でさらに折り返されて
##    ガタガタになる。同じ段落(空行で区切られた範囲)の行はつなげて、折り返しは画面に任せる
##    (行頭が「- 」の行は箇条書きなので、つなげずに1項目ずつ別の行にする)
static func _markdown_to_bbcode(text: String) -> String:
	var paragraphs: PackedStringArray = []
	var current := ""
	var first := true
	for raw_line in text.strip_edges().split("\n"):
		var line: String = raw_line.strip_edges().replace("[", "[lb]").replace("`", "")
		if line == "":
			if current != "":
				paragraphs.append(current)
				current = ""
			continue
		if line.begins_with("# ") or line.begins_with("## "):
			if current != "":
				paragraphs.append(current)
				current = ""
			if not (first and line.begins_with("# ")):
				var heading := line.trim_prefix("## ").trim_prefix("# ")
				paragraphs.append("[color=%s]%s[/color]" % [SUBHEADING_COLOR, heading])
			first = false
			continue
		first = false
		if line.begins_with("- "):
			if current != "":
				paragraphs.append(current)
			current = line
		elif current == "":
			current = line
		else:
			current += _joiner(current, line) + line
	if current != "":
		paragraphs.append(current)
	# 段落の間は空行で区切るが、箇条書きが続く所だけは詰める
	var result := ""
	for i in paragraphs.size():
		if i > 0:
			var both_bullets: bool = paragraphs[i].begins_with("- ") and paragraphs[i - 1].begins_with("- ")
			result += "\n" if both_bullets else "\n\n"
		result += paragraphs[i]
	return result

## 行をつなげる時の区切り: 英数字どうしなら半角スペース、日本語の絡む所は何も入れない。
static func _joiner(previous: String, next_line: String) -> String:
	if previous.unicode_at(previous.length() - 1) < 128 and next_line.unicode_at(0) < 128:
		return " "
	return ""
