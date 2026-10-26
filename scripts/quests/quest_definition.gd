class_name QuestDefinition
extends Resource
## Описание квеста. Текущий прогресс хранится отдельно в QuestManager.

@export var quest_id: StringName = &""
@export var title: String = ""
@export_multiline var description: String = ""
