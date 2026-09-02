class_name MarkdownBbcode
extends RefCounted
## 패치노트용 마크다운 일부 → RichTextLabel BBCode.
## 지원: #~### 제목, **굵게**, *기울임*, `코드`, - 목록, 빈 줄.


## markdown 문자열을 BBCode로 변환한다.
static func to_bbcode(md: String) -> String:
	var lines := md.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var out: PackedStringArray = []
	var in_code := false
	var code_buf: PackedStringArray = []
	for raw in lines:
		var line := String(raw)
		if line.strip_edges().begins_with("```"):
			if in_code:
				out.append("[code]" + "\n".join(code_buf) + "[/code]")
				code_buf.clear()
				in_code = false
			else:
				in_code = true
			continue
		if in_code:
			code_buf.append(_escape_bb(line))
			continue
		var stripped := line.strip_edges()
		if stripped.is_empty():
			out.append("")
			continue
		if stripped.begins_with("### "):
			out.append("[font_size=18][b]%s[/b][/font_size]" % _inline(_escape_bb(stripped.substr(4))))
			continue
		if stripped.begins_with("## "):
			out.append("[font_size=20][b]%s[/b][/font_size]" % _inline(_escape_bb(stripped.substr(3))))
			continue
		if stripped.begins_with("# "):
			out.append("[font_size=22][b]%s[/b][/font_size]" % _inline(_escape_bb(stripped.substr(2))))
			continue
		if stripped.begins_with("- ") or stripped.begins_with("* "):
			out.append("• " + _inline(_escape_bb(stripped.substr(2))))
			continue
		out.append(_inline(_escape_bb(line)))
	if in_code and not code_buf.is_empty():
		out.append("[code]" + "\n".join(code_buf) + "[/code]")
	return "\n".join(out)


static func _escape_bb(s: String) -> String:
	return s.replace("[", "[lb]").replace("]", "[rb]")


static func _inline(s: String) -> String:
	# `code`
	var re_code := RegEx.new()
	re_code.compile("`([^`]+)`")
	s = re_code.sub(s, "[code]$1[/code]", true)
	# **bold**
	var re_bold := RegEx.new()
	re_bold.compile("\\*\\*([^*]+)\\*\\*")
	s = re_bold.sub(s, "[b]$1[/b]", true)
	# *italic*
	var re_em := RegEx.new()
	re_em.compile("(?<!\\*)\\*([^*]+)\\*(?!\\*)")
	s = re_em.sub(s, "[i]$1[/i]", true)
	return s
