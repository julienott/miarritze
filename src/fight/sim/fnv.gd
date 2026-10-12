class_name Fnv
extends RefCounted
## Hash FNV-1a 32 bits (checksums de synchronisation, §8.2).

const OFFSET: int = 0x811C9DC5
const PRIME: int = 0x01000193


static func hash32(bytes: PackedByteArray) -> int:
	var h: int = OFFSET
	for b: int in bytes:
		h = ((h ^ b) * PRIME) & 0xFFFFFFFF
	return h
