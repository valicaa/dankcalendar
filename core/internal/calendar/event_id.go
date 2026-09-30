package calendar

import "strings"

// ValidClientEventID reports whether id can serve as a client-chosen event
// UID: 5 to 1024 characters of base32hex (0-9, a-v), Google's rule for event
// ids and the strictest of the providers that honour a client UID.
func ValidClientEventID(id string) bool {
	return len(id) >= 5 && len(id) <= 1024 && strings.Trim(id, "0123456789abcdefghijklmnopqrstuv") == ""
}
