package mongoproxy

import (
	"context"
	"fmt"
	"net"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	tc "github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

func newProxyTestClient(t *testing.T, clientOpts *options.ClientOptions) (*mongo.Client, func()) {
	t.Helper()
	ctx := context.Background()

	if clientOpts == nil {
		clientOpts = options.Client()
	}

	// 1) Start a MongoDB container
	mongoReq := tc.ContainerRequest{
		Image:        "mongo:6.0",
		ExposedPorts: []string{"27017/tcp"},
		WaitingFor:   wait.ForListeningPort("27017/tcp"),
	}
	mongoC, err := tc.GenericContainer(ctx, tc.GenericContainerRequest{
		ContainerRequest: mongoReq,
		Started:          true,
	})
	require.NoError(t, err, "failed to start MongoDB container")

	host, err := mongoC.Host(ctx)
	require.NoError(t, err)
	port, err := mongoC.MappedPort(ctx, "27017/tcp")
	require.NoError(t, err)

	targetAddr := fmt.Sprintf("%s:%s", host, port.Port())

	// 2) Pick an ephemeral port for the proxy
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	proxyAddr := ln.Addr().String()
	ln.Close()

	// 3) Launch proxy in background
	go func() {
		ListenAndServe(
			WithListenAddr(proxyAddr),
			WithTargetAddr(targetAddr),
		)
	}()
	// give it a moment to bind
	time.Sleep(300 * time.Millisecond)

	// 4) Connect client through proxy
	uri := fmt.Sprintf("mongodb://%s/?directConnection=true", proxyAddr)
	clientOpts = clientOpts.
		ApplyURI(uri).
		SetConnectTimeout(5 * time.Second)

	client, err := mongo.Connect(clientOpts)
	require.NoError(t, err)

	// teardown closes client and container
	teardown := func() {
		_ = client.Disconnect(ctx)
		_ = mongoC.Terminate(ctx)
	}

	return client, teardown
}

func TestDirectForwarding(t *testing.T) {
	client, teardown := newProxyTestClient(t, nil)
	defer teardown()

	coll := client.Database("testdb").Collection("testcoll")
	_ = coll.Drop(context.Background())

	type myStruct struct {
		Name string `bson:"name"`
	}

	_, err := coll.InsertOne(context.Background(), myStruct{Name: "test"})
	require.NoError(t, err, "failed to insert document")

	result := coll.FindOne(context.Background(), myStruct{Name: "test"})
	require.NoError(t, result.Err(), "FindOne returned an error")

	ms := myStruct{}
	err = result.Decode(&ms)
	require.NoError(t, err, "failed to decode document")

	assert.Equal(t, "test", ms.Name, "decoded document does not match inserted value")
}

// TestProxyDelayAction verifies that a delayMs action introduces the expected delay.
func TestProxyDelayAction(t *testing.T) {
	// Establish a new proxied client
	client, teardown := newProxyTestClient(t, options.Client().SetMaxPoolSize(1))
	defer teardown()

	// Build a runCommand with a single delay action of 200ms
	cmd := bson.D{
		{"ping", 1},
		{"proxyTest", bson.D{{"actions", bson.A{bson.D{{"delayMs", 200}}}}}},
	}

	ctx := context.Background()
	start := time.Now()
	err := client.Database("admin").RunCommand(ctx, cmd).Err()
	require.NoError(t, err)
	elapsed := time.Since(start)

	// Verify the delay is at least 200ms (with some tolerance)
	require.GreaterOrEqual(t, elapsed, 200*time.Millisecond,
		"expected at least 200ms delay, got %v", elapsed)
	require.Less(t, elapsed, 400*time.Millisecond,
		"response took too long: %v", elapsed)
}

// TestProxySendBytesAction verifies that sending only 1 byte causes a read timeout/error.
func TestProxySendBytesAction(t *testing.T) {
	// Establish a new proxied client
	client, teardown := newProxyTestClient(t, options.Client().SetMaxPoolSize(1))
	defer teardown()

	// Build a runCommand with a single sendBytes action of 1 (without sendAll)
	cmd := bson.D{
		{"ping", 1},
		{"proxyTest", bson.D{{"actions", bson.A{
			bson.D{{"sendBytes", 1}},
			bson.D{{"delayMs", 500}}, // delay to ensure the buf isn't sent immediately after actions.
		}}}},
	}

	// Use a short context timeout to detect hanging
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()

	err := client.Database("myDB").RunCommand(ctx, cmd).Err()
	// Expect an error due to incomplete reply
	require.Error(t, err, "expected error when only 1 byte is sent")
	require.Contains(t, err.Error(), "timeout", "expected timeout or EOF error, got %v", err)
}

func TestProxyCombinedActions(t *testing.T) {
	t.Parallel()

	client, teardown := newProxyTestClient(t, options.Client().SetMaxPoolSize(1))
	defer teardown()

	cmd := bson.D{
		{"ping", 1},
		{"proxyTest", bson.D{{"actions", bson.A{
			bson.D{{"sendBytes", int32(1)}},
			bson.D{{"delayMs", int32(150)}},
			bson.D{{"sendAll", true}},
		}}}},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	start := time.Now()
	err := client.Database("admin").RunCommand(ctx, cmd).Err()
	elapsed := time.Since(start)

	require.NoError(t, err, "command should succeed after partial send + delay + flush")
	require.GreaterOrEqual(t, elapsed, 150*time.Millisecond,
		"proxy delay not observed; got %v", elapsed)
}
