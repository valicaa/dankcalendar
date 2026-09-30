package ipc

import (
	"context"
	"errors"
	"io"
	"net"
	"net/url"
	"time"

	"github.com/AvengeMedia/dankcalendar/core/internal/calendar"
	"github.com/AvengeMedia/dankcalendar/core/internal/oauth"
	"github.com/AvengeMedia/dankgo/log"
)

// Error codes for failed event writes. The UI shows a plain-language message
// and action per code instead of the raw error, which stays in the log.
const (
	// errCodeNetwork: no answer from the server (offline, DNS, TLS, timeout).
	errCodeNetwork = "network"
	// errCodeUnavailable: the server answered but asked to back off (rate
	// limit, 5xx).
	errCodeUnavailable = "unavailable"
	// errCodeReconnect: the account's credentials were rejected.
	errCodeReconnect = "reconnect"
	errCodeGeneric   = "generic"
)

// writeErrorResponse extends the plain error response with errorCode; error
// keeps the text clients read before codes existed.
type writeErrorResponse struct {
	ID        int    `json:"id,omitempty"`
	Error     string `json:"error"`
	ErrorCode string `json:"errorCode"`
}

func respondWriteError(w *ConnWriter, id int, err error) {
	code := writeErrorCode(err)
	log.Errorf("ipc error: id=%d code=%s method-error=%v", id, code, err)
	_ = w.WriteResponse(writeErrorResponse{ID: id, Error: err.Error(), ErrorCode: code})
}

func writeErrorCode(err error) string {
	var retryLater interface{ RetryAfter() time.Duration }
	switch {
	case errors.Is(err, calendar.ErrReauthRequired), oauth.IsInvalidGrant(err):
		return errCodeReconnect
	case isNetworkError(err):
		return errCodeNetwork
	case errors.As(err, &retryLater):
		return errCodeUnavailable
	}
	return errCodeGeneric
}

// isNetworkError reports a request that got no answer. *url.Error is itself a
// net.Error, and an OAuth transport nests a token request's *url.Error inside
// the API call's, so judge the innermost cause instead.
func isNetworkError(err error) bool {
	var urlErr *url.Error
	transport := false
	for errors.As(err, &urlErr) {
		err, transport = urlErr.Err, true
	}
	var netErr net.Error
	switch {
	case errors.Is(err, context.DeadlineExceeded), errors.As(err, &netErr):
		return true
	case transport:
		// The connection dropped mid-exchange.
		return errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF)
	}
	return false
}
