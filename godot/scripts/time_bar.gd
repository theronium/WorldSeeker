class_name TimeBar
extends Control
# 進行を示す細いバー(2026-09-21。左メニューの「今日」「今月」)。fraction(0〜1)の分だけ左から満たす。
# stripedがtrueの間は、割合ではなく、斜めの縞が流れる(倍速が高く、進みが速すぎて読めない間。「高速で動いている」ことだけを示す)。
# 描画は自前(ProgressBarでは縞を流せない)。更新は、持ち主(main.gdの_refresh_time_bars)が毎フレーム、値を入れる。

const STRIPE_PERIOD := 14.0 # 縞の周期(ピクセル)
const STRIPE_WIDTH := 7.0
const STRIPE_SPEED := 36.0 # 縞の流れる速さ(ピクセル/秒)

var fraction: float = 0.0:
	set(value):
		var clamped := clampf(value, 0.0, 1.0)
		if not is_equal_approx(clamped, fraction):
			fraction = clamped
			queue_redraw()
var fill_color: Color = Color(0.35, 0.6, 0.95):
	set(value):
		if value != fill_color:
			fill_color = value
			queue_redraw()
var track_color: Color = Color(1, 1, 1, 0.12)
var striped: bool = false:
	set(value):
		if value != striped:
			striped = value
			set_process(striped)
			queue_redraw()

var _stripe_offset: float = 0.0

func _init() -> void:
	clip_contents = true # 縞が、バーの外へはみ出さない
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

func _process(delta: float) -> void:
	_stripe_offset = fmod(_stripe_offset + delta * STRIPE_SPEED, STRIPE_PERIOD)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), track_color)
	if striped:
		# 斜めの平行四辺形を、周期ごとに並べて右へ流す(縞の色は、進捗の色を少し薄くしたもの)
		var color := Color(fill_color, 0.75)
		var x := -size.y - STRIPE_PERIOD + _stripe_offset
		while x < size.x:
			draw_colored_polygon(PackedVector2Array([
				Vector2(x, size.y), Vector2(x + STRIPE_WIDTH, size.y),
				Vector2(x + STRIPE_WIDTH + size.y, 0.0), Vector2(x + size.y, 0.0)]), color)
			x += STRIPE_PERIOD
	elif fraction > 0.0:
		draw_rect(Rect2(0.0, 0.0, size.x * fraction, size.y), fill_color)
