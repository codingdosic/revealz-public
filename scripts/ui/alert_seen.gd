class_name AlertSeen
extends RefCounted
## 알림 배지용 로컬 확인 커서. 서버 latest id > 마지막 확인 id 이면 배지.
## 화면을 한 번 열면 (남은 항목과 무관하게) 현재 latest를 본 것으로 저장.


const KEY_MAILBOX := "mailbox_seen_id"
const KEY_PATCH_NOTES := "patch_notes_seen_id"


static func seen_id(key: String) -> int:
	return maxi(0, AppSettings.get_int(key, 0))


## 확인 커서를 올린다. 기존보다 작으면 유지.
static func mark_seen(key: String, latest_id: int) -> void:
	var next := maxi(seen_id(key), maxi(0, latest_id))
	AppSettings.save_merge({key: next})


static func has_unseen(key: String, latest_id: int) -> bool:
	return maxi(0, latest_id) > seen_id(key)


static func max_id_in(entries: Array) -> int:
	var best := 0
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		best = maxi(best, int((entry as Dictionary).get("id", 0)))
	return best
