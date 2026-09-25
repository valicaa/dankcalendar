package ipc

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/AvengeMedia/dankcalendar/core/ent"
	"github.com/AvengeMedia/dankcalendar/core/ent/account"
	"github.com/AvengeMedia/dankcalendar/core/internal/calendar"
	"github.com/AvengeMedia/dankcalendar/core/internal/mocks"
	"github.com/AvengeMedia/dankcalendar/core/repo"
)

func TestPickScheduleAccount(t *testing.T) {
	acme := &ent.Account{ID: "me@acme.com", Kind: account.KindGoogle}
	gmail := &ent.Account{ID: "me@gmail.com", Kind: account.KindGoogle}
	caldav := &ent.Account{ID: "caldav@acme.com", Kind: account.KindCaldav}

	cases := []struct {
		name     string
		accounts []*ent.Account
		email    string
		override string
		want     string
		wantErr  string
	}{
		{"domain match", []*ent.Account{gmail, acme}, "alice@acme.com", "", "me@acme.com", ""},
		{"fallback to first", []*ent.Account{acme, gmail}, "bob@example.com", "", "me@acme.com", ""},
		{"override", []*ent.Account{acme, gmail}, "alice@acme.com", "me@gmail.com", "me@gmail.com", ""},
		{"unknown override", []*ent.Account{acme}, "alice@acme.com", "nope@acme.com", "", "not a connected Google account"},
		{"no google account", []*ent.Account{caldav}, "alice@acme.com", "", "", "no Google account connected"},
		{"non-google accounts ignored", []*ent.Account{caldav, gmail}, "alice@acme.com", "", "me@gmail.com", ""},
	}
	for _, tt := range cases {
		t.Run(tt.name, func(t *testing.T) {
			got, err := pickScheduleAccount(tt.accounts, tt.email, tt.override)
			if tt.wantErr != "" {
				require.Error(t, err)
				assert.Contains(t, err.Error(), tt.wantErr)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tt.want, got.ID)
		})
	}
}

type scheduleMockProvider struct {
	*mocks.MockProvider
	*mocks.MockScheduleReader
}

func peopleFixture(t *testing.T) (icsFixture, string) {
	t.Helper()
	f := newIcsFixture(t, account.KindCaldav, false)
	ctx := context.Background()

	_, err := f.repo.CreateAccount(ctx, repo.CreateAccountInput{ID: "me@acme.com", Kind: account.KindGoogle, DisplayName: "Me"})
	require.NoError(t, err)
	_, err = f.repo.CreateAccount(ctx, repo.CreateAccountInput{ID: "me@gmail.com", Kind: account.KindGoogle, DisplayName: "Me personal"})
	require.NoError(t, err)

	return f, "me@acme.com"
}

func schedulePeopleFactory(t *testing.T, provider calendar.Provider) *mocks.MockProviderFactory {
	factory := mocks.NewMockProviderFactory(t)
	factory.EXPECT().Kind().Return(calendar.AccountGoogle)
	factory.EXPECT().Build(mock.Anything, mock.MatchedBy(func(acc calendar.Account) bool { return acc.ID == "me@acme.com" }), mock.Anything).Return(provider, nil)
	return factory
}

func TestPeopleScheduleValidation(t *testing.T) {
	f, _ := peopleFixture(t)

	cases := map[string]map[string]any{
		"missing email":  {"from": "2026-09-01T00:00:00Z", "to": "2026-09-08T00:00:00Z"},
		"bad email":      {"email": "not-an-email", "from": "2026-09-01T00:00:00Z", "to": "2026-09-08T00:00:00Z"},
		"bad from":       {"email": "alice@acme.com", "from": "nope", "to": "2026-09-08T00:00:00Z"},
		"bad to":         {"email": "alice@acme.com", "from": "2026-09-01T00:00:00Z", "to": "nope"},
		"to before from": {"email": "alice@acme.com", "from": "2026-09-08T00:00:00Z", "to": "2026-09-01T00:00:00Z"},
		"range too long": {"email": "alice@acme.com", "from": "2026-01-01T00:00:00Z", "to": "2026-06-01T00:00:00Z"},
	}
	for name, params := range cases {
		t.Run(name, func(t *testing.T) {
			out := routeAndRead(t, Request{ID: 1, Method: "people.schedule", Params: params}, f.deps)
			assert.NotEmpty(t, out["error"])
		})
	}
}

func TestPeopleScheduleDomainMatchBuildsAccount(t *testing.T) {
	f, _ := peopleFixture(t)

	provider := &scheduleMockProvider{MockProvider: mocks.NewMockProvider(t), MockScheduleReader: mocks.NewMockScheduleReader(t)}
	provider.MockProvider.EXPECT().Close().Return(nil).Maybe()
	provider.MockScheduleReader.EXPECT().ReadSchedule(mock.Anything, "alice@acme.com", mock.Anything, mock.Anything).
		Return(&calendar.Schedule{Access: calendar.ScheduleBusy, Busy: []calendar.TimeSpan{{
			Start: time.Date(2026, 9, 2, 10, 0, 0, 0, time.UTC),
			End:   time.Date(2026, 9, 2, 11, 0, 0, 0, time.UTC),
		}}}, nil)
	f.register(t, calendar.AccountGoogle, provider)

	result := resultOf(t, routeAndRead(t, Request{ID: 1, Method: "people.schedule", Params: map[string]any{
		"email": "alice@acme.com", "from": "2026-09-01T00:00:00Z", "to": "2026-09-08T00:00:00Z",
	}}, f.deps))
	assert.Equal(t, "me@acme.com", result["accountId"])
	assert.Equal(t, "busy", result["status"])
	busy := result["busy"].([]any)
	require.Len(t, busy, 1)
}

func TestPeopleScheduleScopeAndReauthReconnect(t *testing.T) {
	for name, providerErr := range map[string]error{
		"missing scope": calendar.ErrScheduleScope,
		"dead token":    calendar.ErrReauthRequired,
	} {
		t.Run(name, func(t *testing.T) {
			f, _ := peopleFixture(t)
			provider := &scheduleMockProvider{MockProvider: mocks.NewMockProvider(t), MockScheduleReader: mocks.NewMockScheduleReader(t)}
			provider.MockProvider.EXPECT().Close().Return(nil).Maybe()
			provider.MockScheduleReader.EXPECT().ReadSchedule(mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, providerErr)
			f.register(t, calendar.AccountGoogle, provider)

			result := resultOf(t, routeAndRead(t, Request{ID: 1, Method: "people.schedule", Params: map[string]any{
				"email": "alice@acme.com", "from": "2026-09-01T00:00:00Z", "to": "2026-09-08T00:00:00Z",
			}}, f.deps))
			assert.Equal(t, "reconnect", result["status"])
			assert.Equal(t, "me@acme.com", result["accountId"])
		})
	}
}

func TestPeopleScheduleProviderWithoutScheduleReader(t *testing.T) {
	f, _ := peopleFixture(t)
	provider := mocks.NewMockProvider(t)
	provider.EXPECT().Close().Return(nil).Maybe()
	f.register(t, calendar.AccountGoogle, provider)

	out := routeAndRead(t, Request{ID: 1, Method: "people.schedule", Params: map[string]any{
		"email": "alice@acme.com", "from": "2026-09-01T00:00:00Z", "to": "2026-09-08T00:00:00Z",
	}}, f.deps)
	assert.Contains(t, out["error"], "does not support")
}

func TestPeopleScheduleOwnerMatch(t *testing.T) {
	f, _ := peopleFixture(t)
	ctx := context.Background()

	visibleCal, err := f.repo.UpsertCalendar(ctx, repo.UpsertCalendarInput{AccountID: "me@acme.com", RemoteID: "primary", Name: "Work", Hidden: false})
	require.NoError(t, err)
	hiddenCal, err := f.repo.UpsertCalendar(ctx, repo.UpsertCalendarInput{AccountID: "me@acme.com", RemoteID: "extra", Name: "Extra", Hidden: true})
	require.NoError(t, err)

	// Single event: owner and colleague share the same Google event id.
	singleOwn, err := f.repo.UpsertEvent(ctx, repo.UpsertEventInput{
		CalendarID: visibleCal.ID, UID: "evt-1", Summary: "1:1",
		Start: time.Date(2026, 9, 2, 10, 0, 0, 0, time.UTC), End: time.Date(2026, 9, 2, 11, 0, 0, 0, time.UTC),
	})
	require.NoError(t, err)

	// Recurring series: colleague's occurrence carries RecurringID = master
	// UID and OriginalStart = the occurrence's own start.
	weeklyStart := time.Date(2026, 9, 7, 14, 0, 0, 0, time.UTC)
	_, err = f.repo.UpsertEvent(ctx, repo.UpsertEventInput{
		CalendarID: visibleCal.ID, UID: "weekly", Summary: "Standup",
		Start: weeklyStart, End: weeklyStart.Add(30 * time.Minute),
		Recurrence: map[string]any{"rrule": []string{"FREQ=WEEKLY;BYDAY=MO"}},
	})
	require.NoError(t, err)

	// A matching UID hidden behind a hidden calendar must not be reported.
	_, err = f.repo.UpsertEvent(ctx, repo.UpsertEventInput{
		CalendarID: hiddenCal.ID, UID: "evt-hidden", Summary: "Hidden",
		Start: time.Date(2026, 9, 3, 9, 0, 0, 0, time.UTC), End: time.Date(2026, 9, 3, 9, 30, 0, 0, time.UTC),
	})
	require.NoError(t, err)

	occurrenceStart := time.Date(2026, 9, 14, 14, 0, 0, 0, time.UTC)

	provider := &scheduleMockProvider{MockProvider: mocks.NewMockProvider(t), MockScheduleReader: mocks.NewMockScheduleReader(t)}
	provider.MockProvider.EXPECT().Close().Return(nil).Maybe()
	provider.MockScheduleReader.EXPECT().ReadSchedule(mock.Anything, "alice@acme.com", mock.Anything, mock.Anything).Return(&calendar.Schedule{
		Access: calendar.ScheduleDetails,
		Name:   "Alice Doe",
		Events: []calendar.ScheduleEvent{
			{
				Event:   calendar.Event{UID: "evt-1", Summary: "1:1", Start: singleOwn.Start, End: singleOwn.End},
				ICalUID: "ical-1",
			},
			{
				Event: calendar.Event{
					UID: "weekly-14", RecurringID: "weekly", OriginalStart: occurrenceStart,
					Summary: "Standup", Start: occurrenceStart, End: occurrenceStart.Add(30 * time.Minute),
				},
				ICalUID: "ical-weekly",
			},
			{
				Event: calendar.Event{
					UID: "evt-hidden", Summary: "Hidden",
					Start: time.Date(2026, 9, 3, 9, 0, 0, 0, time.UTC), End: time.Date(2026, 9, 3, 9, 30, 0, 0, time.UTC),
				},
				ICalUID: "ical-hidden",
			},
		},
	}, nil)
	f.register(t, calendar.AccountGoogle, provider)

	result := resultOf(t, routeAndRead(t, Request{ID: 1, Method: "people.schedule", Params: map[string]any{
		"email": "alice@acme.com", "from": "2026-09-01T00:00:00Z", "to": "2026-09-21T00:00:00Z",
	}}, f.deps))
	assert.Equal(t, "details", result["status"])
	assert.Equal(t, "Alice Doe", result["name"])

	events := resultEvents(t, result)
	require.Len(t, events, 3)

	byUID := map[string]map[string]any{}
	for _, e := range events {
		byUID[e["key"].(string)] = e
	}

	single := byUID["ical-1|"+singleOwn.Start.UTC().Format(time.RFC3339)]
	require.NotNil(t, single)
	assert.NotEmpty(t, single["ownEventId"])

	weekly := byUID["ical-weekly|"+occurrenceStart.UTC().Format(time.RFC3339)]
	require.NotNil(t, weekly)
	assert.NotEmpty(t, weekly["ownEventId"], "recurring occurrence should match the expanded owner series")

	hidden := byUID["ical-hidden|"+time.Date(2026, 9, 3, 9, 0, 0, 0, time.UTC).Format(time.RFC3339)]
	require.NotNil(t, hidden)
	assert.Nil(t, hidden["ownEventId"], "a match behind a hidden calendar must not be reported")
}

func TestPeopleScheduleUnavailableStatus(t *testing.T) {
	f, _ := peopleFixture(t)
	provider := &scheduleMockProvider{MockProvider: mocks.NewMockProvider(t), MockScheduleReader: mocks.NewMockScheduleReader(t)}
	provider.MockProvider.EXPECT().Close().Return(nil).Maybe()
	provider.MockScheduleReader.EXPECT().ReadSchedule(mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&calendar.Schedule{Access: calendar.ScheduleUnavailable}, nil)
	f.register(t, calendar.AccountGoogle, provider)

	result := resultOf(t, routeAndRead(t, Request{ID: 1, Method: "people.schedule", Params: map[string]any{
		"email": "nobody@acme.com", "from": "2026-09-01T00:00:00Z", "to": "2026-09-08T00:00:00Z",
	}}, f.deps))
	assert.Equal(t, "unavailable", result["status"])
	assert.Empty(t, result["events"].([]any))
	assert.Empty(t, result["busy"].([]any))
}
