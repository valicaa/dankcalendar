package google

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	cal "github.com/AvengeMedia/dankcalendar/core/internal/calendar"
)

// eventWrites runs each event mutation against p so a test can assert how
// every write path reports the same server answer.
func eventWrites() map[string]func(p *Provider) error {
	c := cal.Calendar{ID: "cal", RemoteID: "primary"}
	start := time.Date(2026, 9, 30, 9, 0, 0, 0, time.UTC)
	ev := cal.Event{
		RemoteID: "evt1", Summary: "Standup", Start: start, End: start.Add(time.Hour),
		Attendees: []cal.Attendee{{Email: "me@acme.com"}},
	}
	return map[string]func(p *Provider) error{
		"create": func(p *Provider) error { _, err := p.CreateEvent(context.Background(), c, &ev); return err },
		"update": func(p *Provider) error { _, err := p.UpdateEvent(context.Background(), c, &ev); return err },
		"delete": func(p *Provider) error { return p.DeleteEvent(context.Background(), c, ev) },
		"respond": func(p *Provider) error {
			_, err := p.RespondToEvent(context.Background(), c, &ev, cal.ResponseAccepted)
			return err
		},
	}
}

func TestEventWritesMarkDeadCredentialsForReauth(t *testing.T) {
	for name, write := range eventWrites() {
		t.Run(name+" unauthorized", func(t *testing.T) {
			p := scheduleTestProvider(t, func(w http.ResponseWriter, r *http.Request) {
				writeJSON(w, http.StatusUnauthorized, `{"error": {"code": 401, "message": "invalid credentials"}}`)
			})
			require.ErrorIs(t, write(p), cal.ErrReauthRequired)
		})
		t.Run(name+" dead refresh token", func(t *testing.T) {
			require.ErrorIs(t, write(scheduleTestProviderDeadToken(t)), cal.ErrReauthRequired)
		})
	}
}

func TestEventWritesKeepOtherFailuresUntagged(t *testing.T) {
	for name, write := range eventWrites() {
		t.Run(name, func(t *testing.T) {
			p := scheduleTestProvider(t, func(w http.ResponseWriter, r *http.Request) {
				writeJSON(w, http.StatusForbidden, `{"error": {"code": 403, "message": "forbidden", "errors": [{"reason": "forbidden"}]}}`)
			})
			err := write(p)
			require.Error(t, err)
			require.NotErrorIs(t, err, cal.ErrReauthRequired)
		})
	}
}
