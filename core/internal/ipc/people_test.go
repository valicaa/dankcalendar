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

// peopleFixture seeds two Google accounts, gmail first, so a domain match
// (acme) and the first-account fallback (gmail) differ. It returns acme's id.
func peopleFixture(t *testing.T) (icsFixture, string) {
	t.Helper()
	f := newIcsFixture(t, account.KindCaldav, false)
	ctx := context.Background()

	const acmeID = "me@acme.com"
	_, err := f.repo.CreateAccount(ctx, repo.CreateAccountInput{ID: "me@gmail.com", Kind: account.KindGoogle, DisplayName: "Me personal"})
	require.NoError(t, err)
	_, err = f.repo.CreateAccount(ctx, repo.CreateAccountInput{ID: acmeID, Kind: account.KindGoogle, DisplayName: "Me"})
	require.NoError(t, err)

	return f, acmeID
}

// schedulePeopleFactory builds provider only for wantAccountID, so a test
// proves which account was chosen.
func schedulePeopleFactory(t *testing.T, wantAccountID string, provider calendar.Provider) *mocks.MockProviderFactory {
	factory := mocks.NewMockProviderFactory(t)
	factory.EXPECT().Kind().Return(calendar.AccountGoogle)
	factory.EXPECT().Build(mock.Anything, mock.MatchedBy(func(acc calendar.Account) bool { return acc.ID == wantAccountID }), mock.Anything).Return(provider, nil)
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
		"62 days plus one second rejected": {
			"email": "alice@acme.com", "from": "2026-01-01T00:00:00Z",
			"to": time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC).Add(maxScheduleRangeDays*24*time.Hour + time.Second).Format(time.RFC3339),
		},
	}
	for name, params := range cases {
		t.Run(name, func(t *testing.T) {
			out := routeAndRead(t, Request{ID: 1, Method: "people.schedule", Params: params}, f.deps)
			assert.NotEmpty(t, out["error"])
		})
	}
}

func TestPeopleScheduleRangeBoundaryAccepted(t *testing.T) {
	f, acmeID := peopleFixture(t)
	provider := &scheduleMockProvider{MockProvider: mocks.NewMockProvider(t), MockScheduleReader: mocks.NewMockScheduleReader(t)}
	provider.MockProvider.EXPECT().Close().Return(nil).Maybe()
	provider.MockScheduleReader.EXPECT().ReadSchedule(mock.Anything, mock.Anything, mock.Anything, mock.Anything).
		Return(&calendar.Schedule{Access: calendar.ScheduleUnavailable}, nil)
	f.registry.Register(schedulePeopleFactory(t, acmeID, provider))

	from := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	to := from.Add(maxScheduleRangeDays * 24 * time.Hour)
	out := routeAndRead(t, Request{ID: 1, Method: "people.schedule", Params: map[string]any{
		"email": "alice@acme.com", "from": from.Format(time.RFC3339), "to": to.Format(time.RFC3339),
	}}, f.deps)
	assert.Empty(t, out["error"], "exactly %d days must be accepted", maxScheduleRangeDays)
}

func TestPeopleScheduleDomainMatchBuildsAccount(t *testing.T) {
	f, acmeID := peopleFixture(t)

	provider := &scheduleMockProvider{MockProvider: mocks.NewMockProvider(t), MockScheduleReader: mocks.NewMockScheduleReader(t)}
	provider.MockProvider.EXPECT().Close().Return(nil).Maybe()
	provider.MockScheduleReader.EXPECT().ReadSchedule(mock.Anything, "alice@acme.com", mock.Anything, mock.Anything).
		Return(&calendar.Schedule{Access: calendar.ScheduleBusy, Busy: []calendar.TimeSpan{{
			Start: time.Date(2026, 9, 2, 10, 0, 0, 0, time.UTC),
			End:   time.Date(2026, 9, 2, 11, 0, 0, 0, time.UTC),
		}}}, nil)
	// alice@acme.com domain-matches acme, not gmail, the first account.
	f.registry.Register(schedulePeopleFactory(t, acmeID, provider))

	result := resultOf(t, routeAndRead(t, Request{ID: 1, Method: "people.schedule", Params: map[string]any{
		"email": "alice@acme.com", "from": "2026-09-01T00:00:00Z", "to": "2026-09-08T00:00:00Z",
	}}, f.deps))
	assert.Equal(t, acmeID, result["accountId"])
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
			f, acmeID := peopleFixture(t)
			provider := &scheduleMockProvider{MockProvider: mocks.NewMockProvider(t), MockScheduleReader: mocks.NewMockScheduleReader(t)}
			provider.MockProvider.EXPECT().Close().Return(nil).Maybe()
			provider.MockScheduleReader.EXPECT().ReadSchedule(mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, providerErr)
			f.register(t, calendar.AccountGoogle, provider)

			result := resultOf(t, routeAndRead(t, Request{ID: 1, Method: "people.schedule", Params: map[string]any{
				"email": "alice@acme.com", "from": "2026-09-01T00:00:00Z", "to": "2026-09-08T00:00:00Z",
			}}, f.deps))
			assert.Equal(t, "reconnect", result["status"])
			assert.Equal(t, acmeID, result["accountId"])
			assert.Equal(t, "", result["name"])
			assert.Empty(t, result["events"].([]any))
			assert.Empty(t, result["busy"].([]any))
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
	f, acmeID := peopleFixture(t)
	ctx := context.Background()

	// Google's calendarList names a primary calendar by its owner's address.
	visibleCal, err := f.repo.UpsertCalendar(ctx, repo.UpsertCalendarInput{AccountID: acmeID, RemoteID: acmeID, Name: "Work", Hidden: false})
	require.NoError(t, err)
	hiddenCal, err := f.repo.UpsertCalendar(ctx, repo.UpsertCalendarInput{AccountID: "me@gmail.com", RemoteID: "me@gmail.com", Name: "Personal", Hidden: true})
	require.NoError(t, err)
	// A secondary calendar: the stored row cannot say whether the owner owns
	// it or was given write access to someone else's, so it is not indexed.
	secondaryCal, err := f.repo.UpsertCalendar(ctx, repo.UpsertCalendarInput{AccountID: acmeID, RemoteID: "team@group.calendar.google.com", Name: "Team", Hidden: false})
	require.NoError(t, err)
	_, err = f.repo.UpsertEvent(ctx, repo.UpsertEventInput{
		CalendarID: secondaryCal.ID, UID: "evt-team", Summary: "Team sync",
		Start: time.Date(2026, 9, 4, 9, 0, 0, 0, time.UTC), End: time.Date(2026, 9, 4, 9, 30, 0, 0, time.UTC),
	})
	require.NoError(t, err)
	// Alice's primary calendar, subscribed by the owner.
	subscribedCal, err := f.repo.UpsertCalendar(ctx, repo.UpsertCalendarInput{AccountID: acmeID, RemoteID: "alice@acme.com", Name: "Alice", Hidden: false})
	require.NoError(t, err)
	_, err = f.repo.UpsertEvent(ctx, repo.UpsertEventInput{
		CalendarID: subscribedCal.ID, UID: "evt-mirror", Summary: "Mirror",
		Start: time.Date(2026, 9, 5, 9, 0, 0, 0, time.UTC), End: time.Date(2026, 9, 5, 9, 30, 0, 0, time.UTC),
	})
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
			{
				Event: calendar.Event{
					UID: "evt-team", Summary: "Team sync",
					Start: time.Date(2026, 9, 4, 9, 0, 0, 0, time.UTC), End: time.Date(2026, 9, 4, 9, 30, 0, 0, time.UTC),
				},
				ICalUID: "ical-team",
			},
			{
				Event: calendar.Event{
					UID: "evt-mirror", Summary: "Mirror",
					Start: time.Date(2026, 9, 5, 9, 0, 0, 0, time.UTC), End: time.Date(2026, 9, 5, 9, 30, 0, 0, time.UTC),
				},
				ICalUID: "ical-mirror",
			},
		},
	}, nil)
	f.registry.Register(schedulePeopleFactory(t, acmeID, provider))

	result := resultOf(t, routeAndRead(t, Request{ID: 1, Method: "people.schedule", Params: map[string]any{
		"email": "alice@acme.com", "from": "2026-09-01T00:00:00Z", "to": "2026-09-21T00:00:00Z",
	}}, f.deps))
	assert.Equal(t, "details", result["status"])
	assert.Equal(t, "Alice Doe", result["name"])

	events := resultEvents(t, result)
	require.Len(t, events, 5)

	// Keyed by ICalUID|start: occurrences of a series share a UID.
	byKey := map[string]map[string]any{}
	for _, e := range events {
		byKey[e["key"].(string)] = e
	}

	single := byKey["ical-1|"+singleOwn.Start.UTC().Format(time.RFC3339)]
	require.NotNil(t, single)
	assert.NotEmpty(t, single["ownEventId"])

	weekly := byKey["ical-weekly|"+occurrenceStart.UTC().Format(time.RFC3339)]
	require.NotNil(t, weekly)
	assert.NotEmpty(t, weekly["ownEventId"], "recurring occurrence should match the expanded owner series")

	hidden := byKey["ical-hidden|"+time.Date(2026, 9, 3, 9, 0, 0, 0, time.UTC).Format(time.RFC3339)]
	require.NotNil(t, hidden)
	assert.Nil(t, hidden["ownEventId"], "a match behind a hidden calendar must not be reported")

	team := byKey["ical-team|"+time.Date(2026, 9, 4, 9, 0, 0, 0, time.UTC).Format(time.RFC3339)]
	require.NotNil(t, team)
	assert.Nil(t, team["ownEventId"], "a secondary calendar is not known to be the owner's own")

	mirror := byKey["ical-mirror|"+time.Date(2026, 9, 5, 9, 0, 0, 0, time.UTC).Format(time.RFC3339)]
	require.NotNil(t, mirror)
	assert.Nil(t, mirror["ownEventId"], "the colleague's own calendar, subscribed, must not match as the owner's")
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

func TestScheduleEventKey(t *testing.T) {
	start := time.Date(2026, 9, 2, 10, 0, 0, 0, time.UTC)
	original := time.Date(2026, 9, 1, 10, 0, 0, 0, time.UTC)
	cases := map[string]struct {
		ev   calendar.ScheduleEvent
		want string
	}{
		"single event": {
			ev:   calendar.ScheduleEvent{Event: calendar.Event{Start: start}, ICalUID: "ical-1"},
			want: "ical-1|2026-09-02T10:00:00Z",
		},
		"moved occurrence keys on its original start": {
			ev:   calendar.ScheduleEvent{Event: calendar.Event{Start: start, OriginalStart: original}, ICalUID: "ical-1"},
			want: "ical-1|2026-09-01T10:00:00Z",
		},
		"no iCalUID merges with nobody": {
			ev:   calendar.ScheduleEvent{Event: calendar.Event{Start: start}},
			want: "",
		},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			assert.Equal(t, tc.want, scheduleEventKey(tc.ev))
		})
	}
}
