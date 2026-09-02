class_name AuthProvider
extends RefCounted
## 계정 발급 공급자 인터페이스. Acc0는 Guest만, Acc1에서 Steam/Google 구현체로 교체.
## UI·저장 경로는 AccountService만 본다 — 이 클래스는 키/메타 생성만 담당.


## 공급자 종류 문자열 (예: "guest"). active_account.json 의 authKind와 동일 키.
func get_auth_kind() -> String:
	push_error("AuthProvider.get_auth_kind: subclass must implement")
	return ""


## 새 계정 메타 Dictionary 생성. 필수 키: accountKey, authKind, displayName, createdAtUnix.
## Acc1 구현체는 SDK 로그인 결과에 맞춰 동일 스키마로 채운다.
func create_account_meta() -> Dictionary:
	push_error("AuthProvider.create_account_meta: subclass must implement")
	return {}
