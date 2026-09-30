package ipc

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"golang.org/x/oauth2"

	"github.com/AvengeMedia/dankcalendar/core/ent/account"
	"github.com/AvengeMedia/dankcalendar/core/internal/calendar"
	"github.com/AvengeMedia/dankcalendar/core/internal/mocks"
	"github.com/AvengeMedia/dankcalendar/core/repo"
)

type retryLaterError struct{}

func (retryLaterError) Error() string             { return "retry deferred" }
func (retryLaterError) RetryAfter() time.Duration { return time.Minute }

// closedAddr is a loopback address nothing listens on.
func closedAddr(t *testing.T) string {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	addr := l.Addr().String()
	require.NoError(t, l.Close())
	return addr
}

// silentAddr accepts connections and never answers, like a stalled network.
func silentAddr(t *testing.T) string {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	t.Cleanup(func() { _ = l.Close() })
	go func() {
		for {
			conn, err := l.Accept()
			if err != nil {
				return
			}
			t.Cleanup(func() { _ = conn.Close() })
		}
	}()
	return l.Addr().String()
}

// apiCallThroughRefresh makes an API call whose access token must first be
// refreshed at tokenURL, the path Google writes take through oauth2.Transport.
func apiCallThroughRefresh(t *testing.T, tokenURL string, base *http.Transport) error {
	t.Helper()
	conf := &oauth2.Config{ClientID: "id", Endpoint: oauth2.Endpoint{TokenURL: tokenURL}}
	ctx := context.WithValue(context.Background(), oauth2.HTTPClient, &http.Client{Transport: base})
	client := &http.Client{Transport: &oauth2.Transport{Source: conf.TokenSource(ctx, &oauth2.Token{RefreshToken: "refresh"})}}
	req, err := http.NewRequest(http.MethodPut, "http://"+closedAddr(t)+"/calendar/v3/events/1", nil)
	require.NoError(t, err)
	resp, err := client.Do(req)
	if resp != nil {
		_ = resp.Body.Close()
	}
	require.Error(t, err)
	return err
}

func get(t *testing.T, client *http.Client, rawURL string) error {
	t.Helper()
	resp, err := client.Get(rawURL)
	if resp != nil {
		_ = resp.Body.Close()
	}
	require.Error(t, err)
	return err
}

func TestWriteErrorCode(t *testing.T) {
	cases := []struct {
		name string
		err  func(t *testing.T) error
		want string
	}{
		{"token refresh TLS handshake timeout", func(t *testing.T) error {
			err := apiCallThroughRefresh(t, "https://"+silentAddr(t)+"/token", &http.Transport{TLSHandshakeTimeout: 50 * time.Millisecond})
			require.ErrorContains(t, err, "TLS handshake timeout")
			return fmt.Errorf("update event: update google event: %w", err)
		}, errCodeNetwork},
		{"token refresh connection refused", func(t *testing.T) error {
			return apiCallThroughRefresh(t, "http://"+closedAddr(t)+"/token", &http.Transport{})
		}, errCodeNetwork},
		{"connection refused", func(t *testing.T) error {
			return get(t, http.DefaultClient, "http://"+closedAddr(t))
		}, errCodeNetwork},
		{"client timeout", func(t *testing.T) error {
			return get(t, &http.Client{Timeout: 50 * time.Millisecond}, "http://"+silentAddr(t))
		}, errCodeNetwork},
		{"connection dropped mid-response", func(t *testing.T) error {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				conn, _, err := w.(http.Hijacker).Hijack()
				if err == nil {
					_ = conn.Close()
				}
			}))
			t.Cleanup(srv.Close)
			return get(t, srv.Client(), srv.URL)
		}, errCodeNetwork},
		{"context deadline", func(*testing.T) error { return fmt.Errorf("put: %w", context.DeadlineExceeded) }, errCodeNetwork},
		{"token refresh invalid_grant", func(t *testing.T) error {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusBadRequest)
				_, _ = w.Write([]byte(`{"error":"invalid_grant"}`))
			}))
			t.Cleanup(srv.Close)
			return apiCallThroughRefresh(t, srv.URL, &http.Transport{})
		}, errCodeReconnect},
		{"provider-tagged reauth", func(*testing.T) error {
			return fmt.Errorf("update google event: %w", fmt.Errorf("%w: 401", calendar.ErrReauthRequired))
		}, errCodeReconnect},
		{"server asked to back off", func(*testing.T) error {
			return fmt.Errorf("create google event: %w", retryLaterError{})
		}, errCodeUnavailable},
		{"canceled request", func(*testing.T) error {
			return &url.Error{Op: "Put", URL: "https://example.invalid", Err: context.Canceled}
		}, errCodeGeneric},
		{"EOF outside a request", func(*testing.T) error { return fmt.Errorf("read file: %w", io.EOF) }, errCodeGeneric},
		{"unknown", func(*testing.T) error { return errors.New(`calendar "Work" is read-only`) }, errCodeGeneric},
	}
	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, writeErrorCode(tt.err(t)))
		})
	}
}

type writeFixture struct {
	deps     Deps
	provider *mocks.MockProvider
	eventID  string
}

func newWriteFixture(t *testing.T) writeFixture {
	t.Helper()
	ctx := context.Background()
	client, err := repo.OpenMemory(ctx)
	require.NoError(t, err)
	r := repo.New(client)
	t.Cleanup(func() { _ = r.Close() })

	_, err = r.CreateAccount(ctx, repo.CreateAccountInput{ID: "me@acme.com", Kind: account.KindGoogle, DisplayName: "Me"})
	require.NoError(t, err)
	_, err = r.UpsertCalendar(ctx, repo.UpsertCalendarInput{ID: "cal", AccountID: "me@acme.com", RemoteID: "primary", Name: "Work"})
	require.NoError(t, err)
	start := time.Date(2026, 9, 30, 9, 0, 0, 0, time.UTC)
	ev, err := r.UpsertEvent(ctx, repo.UpsertEventInput{
		CalendarID: "cal", UID: "u1", RemoteID: "r1", Summary: "Standup", Start: start, End: start.Add(time.Hour),
		Attendees: []map[string]any{{"email": "me@acme.com", "status": "needs-action"}},
	})
	require.NoError(t, err)

	provider := mocks.NewMockProvider(t)
	provider.EXPECT().Close().Return(nil).Maybe()
	registry := calendar.NewRegistry()
	registry.Register(factoryFor(t, calendar.AccountGoogle, provider))
	return writeFixture{deps: Deps{Repo: r, Registry: registry, Bus: NewEventBus()}, provider: provider, eventID: ev.ID}
}

func TestEventWritesReportErrorCode(t *testing.T) {
	failures := []struct {
		name string
		err  error
		want string
	}{
		{"network", &url.Error{Op: "Put", URL: "https://example.invalid", Err: &net.OpError{Op: "dial", Net: "tcp", Err: errors.New("connection refused")}}, errCodeNetwork},
		{"reconnect", fmt.Errorf("%w: invalid_grant", calendar.ErrReauthRequired), errCodeReconnect},
		{"generic", errors.New("forbidden"), errCodeGeneric},
	}
	writes := []struct {
		method string
		prefix string
		params func(f writeFixture) map[string]any
		expect func(f writeFixture, err error)
	}{
		{"events.create", "create event: ", func(writeFixture) map[string]any {
			return map[string]any{"calendarId": "cal", "summary": "Lunch", "start": "2026-09-30T12:00:00Z", "end": "2026-09-30T13:00:00Z"}
		}, func(f writeFixture, err error) {
			f.provider.EXPECT().CreateEvent(mock.Anything, mock.Anything, mock.Anything).Return(nil, err)
		}},
		{"events.update", "update event: ", func(f writeFixture) map[string]any {
			return map[string]any{"id": f.eventID, "summary": "Renamed"}
		}, func(f writeFixture, err error) {
			f.provider.EXPECT().UpdateEvent(mock.Anything, mock.Anything, mock.Anything).Return(nil, err)
		}},
		{"events.delete", "delete event: ", func(f writeFixture) map[string]any {
			return map[string]any{"id": f.eventID}
		}, func(f writeFixture, err error) {
			f.provider.EXPECT().DeleteEvent(mock.Anything, mock.Anything, mock.Anything).Return(err)
		}},
		// The mock has no RespondToEvent, so RSVP falls back to UpdateEvent.
		{"events.rsvp", "", func(f writeFixture) map[string]any {
			return map[string]any{"id": f.eventID, "response": "accept"}
		}, func(f writeFixture, err error) {
			f.provider.EXPECT().UpdateEvent(mock.Anything, mock.Anything, mock.Anything).Return(nil, err)
		}},
	}
	for _, w := range writes {
		for _, fail := range failures {
			t.Run(w.method+" "+fail.name, func(t *testing.T) {
				f := newWriteFixture(t)
				w.expect(f, fail.err)

				out := routeAndRead(t, Request{ID: 1, Method: w.method, Params: w.params(f)}, f.deps)
				assert.Equal(t, fail.want, out["errorCode"])
				assert.Equal(t, w.prefix+fail.err.Error(), out["error"], "error keeps the text existing clients read")
				assert.Nil(t, out["result"])
			})
		}
	}
}

func TestEventWriteValidationHasNoErrorCode(t *testing.T) {
	out := routeAndRead(t, Request{ID: 1, Method: "events.update", Params: map[string]any{}}, Deps{})
	assert.Equal(t, "id is required", out["error"])
	assert.NotContains(t, out, "errorCode")
}
