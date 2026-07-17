class_name IrohRoomCode
extends RefCounted
## Validation for the compact endpoint IDs exposed by godot-iroh. Keeping this
## outside the native addon lets the menu reject paste mistakes immediately.

const ENCODED_LENGTH := 43  # 32 bytes, base64url without padding.


static func normalize(value: String) -> String:
	return value.strip_edges()


static func is_valid(value: String) -> bool:
	var code := normalize(value)
	if code.length() != ENCODED_LENGTH:
		return false
	for index in code.length():
		var character := code.unicode_at(index)
		var is_ascii_letter := (
				(character >= 65 and character <= 90)
				or (character >= 97 and character <= 122)
		)
		var is_digit := character >= 48 and character <= 57
		if not is_ascii_letter and not is_digit and character != 45 and character != 95:
			return false
	return true
