extends Control
## 선물함 화면. pending 목록 → 항목 클릭 수령 → 획득 팝업.
## 일괄 수령: 확인 팝업만, 개별 획득 팝업 없이 스냅샷 반영.
## 권위: Meta claim TX. UI는 list/claim 결과와 스냅샷만 신뢰.


const MAIN_SCENE := "res://scenes/main/main.tscn"
const POPUP_SHELL_SCENE := preload("res://scenes/ui/shell/popup_shell.tscn")

@export var chrome_style: UiChromeStyle

@onready var _back_button: Button = $BackButton
@onready var _title_label: Label = $Margin/Panel/InnerMargin/VBox/Header/TitleLabel
@onready var _claim_all_button: Button = $Margin/Panel/InnerMargin/VBox/Header/ClaimAllButton
@onready var _list: VBoxContainer = $Margin/Panel/InnerMargin/VBox/ListScroll/ItemList
@onready var _empty_label: Label = $Margin/Panel/InnerMargin/EmptyLabel
@onready var _status_label: Label = $Margin/Panel/InnerMargin/VBox/StatusLabel

var _items: Array = []
var _claim_popup: MailboxClaimPopup
var _claim_all_popup: PopupShell
var _http: HTTPRequest
var _busy: bool = false


func _ready() -> void:
	_apply_ui_chrome()
	ScreenRmbBack.install(self, _on_back_button_pressed)
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	_claim_popup = MailboxClaimPopup.instantiate_popup()
	add_child(_claim_popup)
	_claim_popup.apply_chrome(chrome_style)
	_claim_all_popup = POPUP_SHELL_SCENE.instantiate() as PopupShell
	add_child(_claim_all_popup)
	if _claim_all_popup.has_method("apply_chrome"):
		_claim_all_popup.call("apply_chrome", chrome_style)
	if _back_button and not _back_button.pressed.is_connected(_on_back_button_pressed):
		_back_button.pressed.connect(_on_back_button_pressed)
	if _claim_all_button and not _claim_all_button.pressed.is_connected(_on_claim_all_pressed):
		_claim_all_button.pressed.connect(_on_claim_all_pressed)
	_status_label.text = ""
	await _load_list()


func _apply_ui_chrome() -> void:
	chrome_style = UiChromeStyle.resolve(chrome_style)
	chrome_style.apply_screen_tree(self)
	if _title_label:
		chrome_style.apply_title_label(_title_label)
	if _empty_label:
		chrome_style.apply_muted_label(_empty_label)
	if _status_label:
		chrome_style.apply_muted_label(_status_label)
	if _back_button:
		chrome_style.apply_buttons([_back_button])
	if _claim_all_button:
		chrome_style.apply_buttons([_claim_all_button])


func _on_back_button_pressed() -> void:
	MenuHost.pop_or_file(MAIN_SCENE)


func _account_key() -> String:
	return AccountService.current_id()


func _load_list() -> void:
	_status_label.text = ""
	if not MetaSync.can_use_online() or _account_key().is_empty():
		_items = []
		_status_label.text = "서버 연결이 필요합니다"
		_rebuild_list()
		return
	var res: Dictionary = await MetaRemote.list_mailbox(_http, _account_key())
	if not bool(res.get("ok", false)):
		_items = []
		_status_label.text = _error_text(String(res.get("error", "load_failed")))
		_rebuild_list()
		return
	var data: Dictionary = {}
	if typeof(res.get("data", {})) == TYPE_DICTIONARY:
		data = res.get("data", {}) as Dictionary
	var items_raw: Array = data.get("items", []) as Array
	_items = []
	for entry in items_raw:
		if typeof(entry) == TYPE_DICTIONARY:
			_items.append(entry)
	MetaSync.mailbox_pending_count = maxi(0, int(data.get("pendingCount", _items.size())))
	AlertSeen.mark_seen(AlertSeen.KEY_MAILBOX, AlertSeen.max_id_in(_items))
	_rebuild_list()


func _rebuild_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var empty := _items.is_empty()
	_empty_label.visible = empty
	_empty_label.text = "받은 선물이 없습니다"
	if _claim_all_button:
		_claim_all_button.disabled = empty or _busy
	for entry in _items:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row := MailboxItemRow.instantiate_row()
		_list.add_child(row)
		row.configure(entry as Dictionary, chrome_style)
		row.disabled = _busy
		row.claim_pressed.connect(_on_item_claim_pressed)


func _set_busy(on: bool) -> void:
	_busy = on
	if _claim_all_button:
		_claim_all_button.disabled = on or _items.is_empty()
	for child in _list.get_children():
		if child is Button:
			(child as Button).disabled = on


func _on_item_claim_pressed(item: Dictionary) -> void:
	if _busy:
		return
	var item_id := String(item.get("id", ""))
	if item_id.is_empty():
		return
	_set_busy(true)
	_status_label.text = ""
	var res: Dictionary = await MetaRemote.claim_mailbox(_http, _account_key(), item_id)
	_set_busy(false)
	if not bool(res.get("ok", false)):
		var err := String(res.get("error", "claim_failed"))
		_status_label.text = _error_text(err)
		await _load_list()
		return
	var data: Dictionary = {}
	if typeof(res.get("data", {})) == TYPE_DICTIONARY:
		data = res.get("data", {}) as Dictionary
	_apply_snapshot_from(data)
	var claimed: Dictionary = {}
	if typeof(data.get("claimed", {})) == TYPE_DICTIONARY:
		claimed = data.get("claimed", {}) as Dictionary
	await _load_list()
	var title := MailboxItemRow.display_title(claimed if not claimed.is_empty() else item)
	var payload: Dictionary = {}
	var src := claimed if not claimed.is_empty() else item
	if typeof(src.get("payload", {})) == TYPE_DICTIONARY:
		payload = src.get("payload", {}) as Dictionary
	_claim_popup.present(title, payload, chrome_style)


func _on_claim_all_pressed() -> void:
	if _items.is_empty() or _claim_all_popup == null or _busy:
		return
	var copy := chrome_style.get_copy()
	_claim_all_popup.configure_confirm(
		"일괄 수령",
		"받은 선물을 모두 받을까요?",
		_confirm_claim_all,
		Callable(),
		copy.confirm,
		copy.cancel,
		{"full_dimmer": true}
	)
	_claim_all_popup.open()


func _confirm_claim_all() -> void:
	if _busy:
		return
	_set_busy(true)
	_status_label.text = ""
	var res: Dictionary = await MetaRemote.claim_mailbox_all(_http, _account_key())
	_set_busy(false)
	if not bool(res.get("ok", false)):
		_status_label.text = _error_text(String(res.get("error", "claim_failed")))
		await _load_list()
		return
	var data: Dictionary = {}
	if typeof(res.get("data", {})) == TYPE_DICTIONARY:
		data = res.get("data", {}) as Dictionary
	_apply_snapshot_from(data)
	await _load_list()


func _apply_snapshot_from(data: Dictionary) -> void:
	var snap: Dictionary = {}
	if typeof(data.get("snapshot", {})) == TYPE_DICTIONARY:
		snap = data.get("snapshot", {}) as Dictionary
	if not snap.is_empty():
		MetaSync.apply_server_snapshot(snap)


func _error_text(code: String) -> String:
	match code:
		"already_claimed":
			return "이미 수령한 선물입니다"
		"mailbox_item_not_found":
			return "선물을 찾을 수 없습니다"
		"account_not_found":
			return "계정 데이터가 없습니다"
		"meta_db_not_configured":
			return "서버 연결이 필요합니다"
	if code.is_empty():
		return "처리에 실패했습니다"
	return code
