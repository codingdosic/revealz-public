class_name GuestAuthProvider
extends AuthProvider
## 로컬 게스트 계정 발급. SDK·네트워크 없음. Acc0 전용 구현체.
## 함정: accountKey는 재실행마다 새로 만들지 말고 AccountService가 active 파일을 우선한다.


## authKind "guest" 반환. Acc1 머지 시 구분 키로 쓴다.
func get_auth_kind() -> String:
	return "guest"


## guest_<uuid4> 키와 표시용 메타를 만든다. 디스크 기록은 AccountService 책임.
## 첫 실행: accountKey와 displayName을 동일 문자열로 둔다(이후 displayName만 수정 가능).
func create_account_meta() -> Dictionary:
	var key := "guest_%s" % _make_uuid4()
	return {
		"accountKey": key,
		"authKind": get_auth_kind(),
		"displayName": key,
		"profileIconId": AccessoryCatalog.DEFAULT_ICON_ID,
		"createdAtUnix": int(Time.get_unix_time_from_system()),
	}


## RFC4122 형태 uuid4. Crypto 난수로 충돌 확률을 낮춘다(로컬 단일 기기면 충분).
func _make_uuid4() -> String:
	var crypto := Crypto.new()
	var b := crypto.generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % [
		b[0], b[1], b[2], b[3],
		b[4], b[5],
		b[6], b[7],
		b[8], b[9],
		b[10], b[11], b[12], b[13], b[14], b[15],
	]
