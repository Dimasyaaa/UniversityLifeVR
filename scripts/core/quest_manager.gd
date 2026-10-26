extends Node

## Менеджер квестов и достижений (Модуль 7).
## Хранит прогресс в локальной БД (ConfigFile user://quest_progress.cfg).
## Условия выполнения квестов передают модули: они вызывают complete_quest()
## и слушают сигналы. API описан в ARCHITECTURE.md (§ QuestManager).

signal quest_registered(quest_id: String)
signal quest_completed(quest_id: String)
signal achievement_unlocked(achievement_id: String)

const SAVE_PATH := "user://quest_progress.cfg"

## Каталог квестов (по ТЗ проекта).
const QUESTS := {
	"main_exam": {
		"title": "Сдать экзамен на отлично",
		"description": "К 16:00: Знания >= 70, Энергия >= 40, Сытость >= 30",
		"is_main": true,
	},
	"breakfast": {
		"title": "Позавтракать в общежитии",
		"description": "Восстановить Сытость на 30%",
		"is_main": false,
	},
	"library": {
		"title": "Найти информацию в библиотеке",
		"description": "Посети библиотеку: +15 к Знаниям",
		"is_main": false,
	},
	"cafeteria": {
		"title": "Поешь в столовой",
		"description": "+25 к Сытости",
		"is_main": false,
	},
	"gym": {
		"title": "Потренироваться в спортзале",
		"description": "+20 к Энергии, -10 к Сытости",
		"is_main": false,
	},
	"party": {
		"title": "Сходи на вечеринку",
		"description": "+30 к Настроению, -25 к Энергии",
		"is_main": false,
	},
	"job": {
		"title": "Подработать курьером",
		"description": "+100 к Деньгам, -20 к Энергии",
		"is_main": false,
	},
	"robot": {
		"title": "Собери робота в мастерской",
		"description": "+20 к Знаниям",
		"is_main": false,
	},
	"checkup": {
		"title": "Пройди профосмотр",
		"description": "Восстановление Здоровья",
		"is_main": false,
	},
	"deanery": {
		"title": "Забери грамоту в деканате",
		"description": "Необходимо для получения стипендии",
		"is_main": false,
	},
	"ducks": {
		"title": "Покорми уток в парке",
		"description": "+15 к Настроению",
		"is_main": false,
	},
}

## Каталог достижений (сохраняются в БД).
const ACHIEVEMENTS := {
	"early_bird": {"title": "Ранняя пташка", "description": "Встал до 07:00"},
	"bookworm": {"title": "Зубрила", "description": "Более 2 игровых часов в библиотеке"},
	"athlete": {"title": "Спортсмен", "description": "Посетил спортзал 3 раза"},
	"party_animal": {"title": "Тусовщик", "description": "Более 1 часа на вечеринке"},
	"hard_worker": {"title": "Трудяга", "description": "Заработал 500+ денег за день"},
	"excellent_student": {"title": "Отличник", "description": "Сдал экзамен на 5"},
	"explorer": {"title": "Исследователь", "description": "Посетил все 14 локаций"},
}

## id -> данные квеста (активные, ещё не выполненные).
var active_quests: Dictionary = {}

## Списки id (выполненные квесты / разблокированные достижения).
var completed_quests: Array = []
var unlocked_achievements: Array = []

func _ready() -> void:
	for quest_id in QUESTS:
		register_quest(quest_id)
	load_progress()

# --- Квесты ---------------------------------------------------------------

func register_quest(quest_id: String) -> void:
	if not QUESTS.has(quest_id):
		push_warning("QuestManager: неизвестный квест '%s'" % quest_id)
		return
	if quest_id in completed_quests or active_quests.has(quest_id):
		return
	active_quests[quest_id] = QUESTS[quest_id].duplicate()
	quest_registered.emit(quest_id)

## Отметить квест выполненным. Возвращает true при успехе.
func complete_quest(quest_id: String) -> bool:
	if quest_id in completed_quests:
		return false
	if not active_quests.has(quest_id):
		push_warning("QuestManager: квест '%s' не активен" % quest_id)
		return false
	var quest: Dictionary = active_quests[quest_id]
	active_quests.erase(quest_id)
	completed_quests.append(quest_id)
	quest_completed.emit(quest_id)
	HintSystem.show_hint("Квест выполнен: «%s»" % quest.get("title", quest_id), 4.0)
	save_progress()
	return true

func is_quest_active(quest_id: String) -> bool:
	return active_quests.has(quest_id)

func is_quest_completed(quest_id: String) -> bool:
	return quest_id in completed_quests

func get_active_quests() -> Array:
	var result: Array = []
	for quest_id in active_quests:
		var quest: Dictionary = active_quests[quest_id].duplicate()
		quest["id"] = quest_id
		result.append(quest)
	return result

# --- Достижения -----------------------------------------------------------

## Разблокировать достижение. Возвращает true, если оно было новым.
func unlock_achievement(achievement_id: String) -> bool:
	if not ACHIEVEMENTS.has(achievement_id):
		push_warning("QuestManager: неизвестное достижение '%s'" % achievement_id)
		return false
	if achievement_id in unlocked_achievements:
		return false
	unlocked_achievements.append(achievement_id)
	achievement_unlocked.emit(achievement_id)
	var title: String = ACHIEVEMENTS[achievement_id].get("title", achievement_id)
	HintSystem.show_hint("Достижение: «%s»" % title, 5.0)
	save_progress()
	return true

func is_achievement_unlocked(achievement_id: String) -> bool:
	return achievement_id in unlocked_achievements

func get_unlocked_achievements() -> Array:
	return unlocked_achievements.duplicate()

# --- Сохранение (локальная БД) --------------------------------------------

func save_progress() -> void:
	var cf := ConfigFile.new()
	cf.set_value("progress", "completed_quests", completed_quests)
	cf.set_value("progress", "unlocked_achievements", unlocked_achievements)
	cf.save(SAVE_PATH)

func load_progress() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return false
	completed_quests = []
	for quest_id in cf.get_value("progress", "completed_quests", []):
		completed_quests.append(quest_id)
		active_quests.erase(quest_id)
	unlocked_achievements = []
	for achievement_id in cf.get_value("progress", "unlocked_achievements", []):
		unlocked_achievements.append(achievement_id)
	return true
