package mongoproxy

import (
	"fmt"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/x/bsonx/bsoncore"
)

// action is one step in the proxyTest sequence.
type action struct {
	DelayMs   *int  `bson:"delayMs,omitempty"`   // milliseconds to wait
	SendBytes *int  `bson:"sendBytes,omitempty"` // how many bytes to forward
	SendAll   *bool `bson:"sendAll,omitempty"`   // forward remaining bytes
}

// testInstruction holds the ordered list of actions.
type testInstruction struct {
	Actions []action `bson:"actions"`
}

// parseProxy looks for a `proxyTest` field in the command document, unmarshals
// its actions, removes the field, and returns the cleaned document + instructions.
func parseProxy(cmdDoc bson.Raw) (cleanDoc bson.Raw, instr *testInstruction, err error) {
	// Quick unmarshal of only the proxyTest.actions array.
	var wrapper struct {
		ProxyTest struct {
			Actions []bson.Raw `bson:"actions"`
		} `bson:"proxyTest"`
	}

	if err := bson.Unmarshal(cmdDoc, &wrapper); err != nil {
		return nil, nil, fmt.Errorf("failed to unmarshal command document: %w", err)
	}

	if wrapper.ProxyTest.Actions == nil {
		return cmdDoc, nil, nil // no proxyTest actions, nothing to do
	}

	// Decode the actions into a testInstruction.
	instr = &testInstruction{}
	for i, raw := range wrapper.ProxyTest.Actions {
		var a action
		if err := bson.Unmarshal(raw, &a); err != nil {
			return nil, nil, fmt.Errorf("failed to unmarshal action %d: %w", i, err)
		}

		instr.Actions = append(instr.Actions, a)
	}

	// Remove the `proxyTest` field from the original command document.
	cleanDoc = removeKey(cmdDoc, "proxyTest")
	return cleanDoc, instr, nil
}

// removeKey rebuilds a BSON document without the given top-level key.
func removeKey(doc bson.Raw, key string) bson.Raw {
	// Convert to bsoncore.Document to iterate elements
	elems, _ := bsoncore.Document(doc).Elements()

	// Collect raw element bytes
	rawElems := make([][]byte, 0, len(elems))
	for _, e := range elems {
		if e.Key() == key {
			continue
		}

		rawElems = append(rawElems, []byte(e))
	}

	// Rebuild and return as bson.Raw
	return bson.Raw(bsoncore.BuildDocument(nil, rawElems...))
}
