package calendar

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestValidClientEventID(t *testing.T) {
	cases := map[string]bool{
		"0f3a9c2e7b1d4e6f8a0b1c2d3e4f5a6b": true,
		"vvvvv":                            true,
		"abcd":                             false,
		"ABCDE":                            false,
		"wxyz0":                            false,
		"0f3a9c2e-7b1d-4e6f":               false,
		strings.Repeat("a", 1024):          true,
		strings.Repeat("a", 1025):          false,
	}
	for id, want := range cases {
		require.Equal(t, want, ValidClientEventID(id), "%.12s… (len %d)", id, len(id))
	}
}
