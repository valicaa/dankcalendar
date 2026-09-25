package calendar

import (
	"context"
	"errors"
	"time"
)

// ErrScheduleScope marks a schedule lookup whose account token lacks the
// permission to read another person's availability. Providers wrap it around
// the underlying error the way ErrReauthRequired wraps a dead credential.
var ErrScheduleScope = errors.New("availability permission not granted")

// ScheduleReader is implemented by providers that can read another person's
// calendar (details where shared, otherwise free/busy). Results are never
// stored.
type ScheduleReader interface {
	ReadSchedule(ctx context.Context, email string, from, to time.Time) (*Schedule, error)
}

// ScheduleAccess reports how much of a colleague's calendar a lookup could see.
type ScheduleAccess string

const (
	ScheduleDetails     ScheduleAccess = "details"
	ScheduleBusy        ScheduleAccess = "busy"
	ScheduleUnavailable ScheduleAccess = "unavailable"
)

// Schedule is the result of a ScheduleReader lookup for one person over one
// range.
type Schedule struct {
	Access ScheduleAccess
	Name   string // display name when a source reveals it, else ""
	Events []ScheduleEvent
	Busy   []TimeSpan
}

// ScheduleEvent is a read-only occurrence. Event.UID/RecurringID/OriginalStart
// carry the provider's occurrence identity; ICalUID is the cross-calendar
// RFC 5545 UID, which the owner's own rows never store.
type ScheduleEvent struct {
	Event
	ICalUID string
}

// TimeSpan is a busy interval with no further identity.
type TimeSpan struct {
	Start, End time.Time
}
