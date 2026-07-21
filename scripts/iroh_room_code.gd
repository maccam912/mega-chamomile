class_name IrohRoomCode
extends RefCounted
## Validation for the short codes issued by the Paint-n-Seek rendezvous
## service. Keeping this outside the network singleton lets the menu reject
## paste mistakes before making a lookup request.

const ENCODED_LENGTH := 4
const ALPHABET := "23456789ABCDEFGHJKMNPQRSTVWXYZ"


static func normalize(value: String) -> String:
	return value.strip_edges().to_upper()


static func is_valid(value: String) -> bool:
	var code := normalize(value)
	if code.length() != ENCODED_LENGTH:
		return false
	for index in code.length():
		if ALPHABET.find(code.substr(index, 1)) < 0:
			return false
	return true
