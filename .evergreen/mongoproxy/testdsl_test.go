package mongoproxy

import (
	"reflect"
	"testing"

	"github.com/stretchr/testify/require"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/x/bsonx/bsoncore"
)

func TestParseProxy_WithoutProxyTest(t *testing.T) {
	// Build a command document with no proxyTest
	cmdD := bson.D{{Key: "ping", Value: 1}}
	rawBytes, err := bson.Marshal(cmdD)
	require.NoError(t, err)

	// invoke parser
	cleanRaw, instr, err := parseProxy(bson.Raw(rawBytes))
	require.NoError(t, err)
	require.Nil(t, instr, "expected nil testInstruction when no proxyTest present")

	// cleanRaw should equal original raw
	require.True(t,
		reflect.DeepEqual(bsoncore.Document(rawBytes), bsoncore.Document(cleanRaw)),
		"cleanDoc should equal original when no proxyTest",
	)
}

func TestParseProxy_WithProxyTest(t *testing.T) {
	// Build a command document containing proxyTest with one action
	actions := []interface{}{bson.D{{"delayMs", 100}}}
	cmdD := bson.D{
		{Key: "insert", Value: "coll"},
		{Key: "proxyTest", Value: bson.D{{"actions", actions}}},
	}

	rawBytes, err := bson.Marshal(cmdD)
	require.NoError(t, err)

	// invoke parser
	cleanRaw, instr, err := parseProxy(bson.Raw(rawBytes))
	require.NoError(t, err)
	require.NotNil(t, instr, "expected non-nil testInstruction")

	val := 100

	// instr.Actions should reflect our input
	expected := []action{{DelayMs: &val}}
	require.Len(t, instr.Actions, 1)
	require.Equal(t, expected, instr.Actions)

	// cleanRaw should no longer contain "proxyTest"
	elems, _ := bsoncore.Document(cleanRaw).Elements()
	for _, e := range elems {
		require.NotEqual(t, "proxyTest", e.Key(), "cleanDoc must not contain proxyTest")
	}
}

func TestParseProxy_WithProxyTest_Zero(t *testing.T) {
	// Build a command document containing proxyTest with one action
	actions := []interface{}{bson.D{{"delayMs", 0}}, bson.D{{"sendBytes", 0}}}
	cmdD := bson.D{
		{Key: "insert", Value: "coll"},
		{Key: "proxyTest", Value: bson.D{{"actions", actions}}},
	}

	rawBytes, err := bson.Marshal(cmdD)
	require.NoError(t, err)

	// invoke parser
	cleanRaw, instr, err := parseProxy(bson.Raw(rawBytes))
	require.NoError(t, err)
	require.NotNil(t, instr, "expected non-nil testInstruction")

	// instr.Actions should reflect our input
	require.Len(t, instr.Actions, 2)

	// cleanRaw should no longer contain "proxyTest"
	elems, _ := bsoncore.Document(cleanRaw).Elements()
	for _, e := range elems {
		require.NotEqual(t, "proxyTest", e.Key(), "cleanDoc must not contain proxyTest")
	}
}

func TestParseProxy_WithProxyTest_UnknownField(t *testing.T) {
	actions := []interface{}{bson.D{{"delayMs", 100}}, bson.D{{"unknownField", "value"}}}
	cmdD := bson.D{
		{Key: "insert", Value: "coll"},
		{Key: "proxyTest", Value: bson.D{{"actions", actions}}},
	}

	rawBytes, err := bson.Marshal(cmdD)
	require.NoError(t, err)

	// Invoke parser
	_, instr, err := parseProxy(bson.Raw(rawBytes))
	require.Error(t, err, "expected error for unknown action field")
	require.Nil(t, instr, "expected nil testInstruction on error")
}
