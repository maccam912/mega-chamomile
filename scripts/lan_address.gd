extends RefCounted
## Selects an IPv4 address that another device on the local network can use.


## Home-network ranges are preferred over public or virtual-adapter addresses.
static func preferred(addresses: PackedStringArray) -> String:
	var best_address := ""
	var best_rank := 99
	for address: String in addresses:
		var parts := address.split(".")
		if parts.size() != 4:
			continue
		var octets: Array[int] = []
		var valid := true
		for part: String in parts:
			if not part.is_valid_int():
				valid = false
				break
			var octet := int(part)
			if octet < 0 or octet > 255:
				valid = false
				break
			octets.append(octet)
		if not valid:
			continue

		var rank := 3
		if octets[0] == 192 and octets[1] == 168:
			rank = 0
		elif octets[0] == 10:
			rank = 1
		elif octets[0] == 172 and octets[1] >= 16 and octets[1] <= 31:
			rank = 2
		elif octets[0] == 0 or octets[0] == 127 \
				or (octets[0] == 169 and octets[1] == 254):
			continue

		if rank < best_rank:
			best_address = address
			best_rank = rank
	return best_address
