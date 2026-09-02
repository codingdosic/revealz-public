class_name AccessoryDefinition
extends Resource
## 카탈로그 항목 — id·타입·표시명·설명·UI 미리보기.
## resources/accessories/{type}/*.tres 로 배치.


@export var accessory_id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var accessory_type: String = AccessoryTypes.TYPE_ICON
## 설정/상점 격자·인게임 미리보기.
@export var preview: Texture2D
## preview 참조 실패 시 load() 폴백.
@export var preview_path: String = ""
## field 타입: 인게임 3D 보드 메시 (PackedScene .glb 등).
@export var scene_path: String = ""
