extends RefCounted
## Saved fields and the fixed three-star evaluation are separate quantities.
const VERSION := 2

static func stars(saved: int, total: int) -> int:
	if total <= 0 or saved < 0 or saved > total or saved == 0: return 0
	if saved == total: return 3
	return 1 if saved == 1 else 2
