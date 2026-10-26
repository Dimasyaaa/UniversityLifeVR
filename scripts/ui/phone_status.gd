extends Control
## Экран читает показатели из GameStateManager и обновляется по его сигналу.

@onready var _money: Label = $Background/Margin/Content/Money/Margin/Row/Value
@onready var _bars: Dictionary[StringName, ProgressBar] = {
	&"energy": $Background/Margin/Content/Stats/Energy/Bar,
	&"satiety": $Background/Margin/Content/Stats/Satiety/Bar,
	&"knowledge": $Background/Margin/Content/Stats/Knowledge/Bar,
	&"mood": $Background/Margin/Content/Stats/Mood/Bar,
	&"health": $Background/Margin/Content/Stats/Health/Bar,
}
@onready var _values: Dictionary[StringName, Label] = {
	&"energy": $Background/Margin/Content/Stats/Energy/Heading/Value,
	&"satiety": $Background/Margin/Content/Stats/Satiety/Heading/Value,
	&"knowledge": $Background/Margin/Content/Stats/Knowledge/Heading/Value,
	&"mood": $Background/Margin/Content/Stats/Mood/Heading/Value,
	&"health": $Background/Margin/Content/Stats/Health/Heading/Value,
}


func _ready() -> void:
	GameStateManager.player_stat_changed.connect(_on_player_stat_changed)
	var stats: Dictionary[StringName, int] = GameStateManager.get_stats()
	for stat_name: StringName in stats:
		_on_player_stat_changed(stat_name, stats[stat_name])


func _on_player_stat_changed(stat_name: StringName, value: int) -> void:
	if stat_name == &"money":
		_money.text = str(value)
	else:
		_bars[stat_name].value = value
		_values[stat_name].text = "%d / 100" % value
