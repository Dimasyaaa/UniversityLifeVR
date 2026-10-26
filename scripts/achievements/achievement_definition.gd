class_name AchievementDefinition
extends Resource
## Описание достижения и его условие. Разблокировки хранит AchievementManager.

enum Condition { MANUAL, MONEY_EARNED, LOCATION_VISITS, LOCATION_TIME, EVENT, TIMED_EVENT }

@export var achievement_id: StringName = &""
@export var title: String = ""
@export_multiline var description: String = ""
@export var condition: Condition = Condition.MANUAL
## Время задаётся в секундах: LOCATION_TIME — игровых, TIMED_EVENT — реальных.
@export var threshold: float = 1.0
@export var location_id: StringName = &""
@export var event_id: StringName = &""
@export var start_event_id: StringName = &""
