class_name Text
extends RefCounted
## 한국어 텍스트 유틸


## 받침에 따라 조사 선택. josa("민준", "은/는") → "민준은"
static func josa(word: String, pair: String) -> String:
	if word.is_empty():
		return word
	var code := word.unicode_at(word.length() - 1) - 0xAC00
	var has := code >= 0 and code <= 11171 and code % 28 != 0
	var parts := pair.split("/")
	if pair == "으로/로":
		return word + (parts[0] if has and code % 28 != 8 else parts[1])
	return word + (parts[0] if has else parts[1])


static func stars(n: int) -> String:
	return "★".repeat(n)
