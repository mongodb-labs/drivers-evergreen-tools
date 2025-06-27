package mongoproxy

import (
	"context"
	"fmt"
	"net/url"
	"strings"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
	"go.mongodb.org/mongo-driver/v2/x/mongo/driver/connstring"
)

type Config struct {
	ListenAddr string // Address to listen for incoming connections
	TargetAddr string // Address of the target MongoDB server
	TargetURI  string // URI of the target MongoDB server
	CAFile     string // Optional CA file for TLS connections
	KeyFile    string // Optional key file for TLS connections
}

// Option defines a function type that modifies the Config.
type Option func(*Config)

// WithListenAddr sets the address to listen for incoming connections.
func WithListenAddr(addr string) Option {
	return func(cfg *Config) {
		cfg.ListenAddr = addr
	}
}

// WithTargetAddr sets the address of the target MongoDB server.
func WithTargetAddr(addr string) Option {
	return func(cfg *Config) {
		cfg.TargetAddr = addr
	}
}

// WithTargetURI sets the URI of the target MongoDB server.
func WithTargetURI(uri string) Option {
	return func(cfg *Config) {
		cfg.TargetURI = uri
	}
}

// WithCAFile sets the CA file for TLS connections.
func WithCAFile(caFile string) Option {
	return func(cfg *Config) {
		cfg.CAFile = caFile
	}
}

// WithKeyFile sets the key file for TLS connections.
func WithKeyFile(keyFile string) Option {
	return func(cfg *Config) {
		cfg.KeyFile = keyFile
	}
}

// resolveTarget chooses between plain host:port or parses a Mongo URI.
//
// TODO: Likely for the SRV solution to work we will need to perform hello
// TODO: commands against each node to determine which one is the primary.
func resolveTarget(targetConnString *connstring.ConnString) (string, error) {
	if strings.EqualFold(targetConnString.Scheme, "mongodb+srv") {
		panic("no support for mongodb+srv yet")
	}

	// Attempt to resolve the target address by finding the primary node.
	primaryAddr, err := findPrimary(targetConnString.Original, targetConnString.Hosts)
	if err != nil {
		return "", err
	}

	return primaryAddr, nil
}

type helloResponse struct {
	Primary           string `bson:"primary"`
	IsWritablePrimary bool   `bson:"isWritablePrimary"`
}

// handshake runs a "hello" command against the MongoDB server at the given URL.
func runHelloCommand(u url.URL) (*helloResponse, error) {
	client, err := mongo.Connect(options.Client().ApplyURI(u.String()))
	if err != nil {
		return nil, fmt.Errorf("failed to connect to %s: %w", u.String(), err)
	}

	defer func() {
		_ = client.Disconnect(context.Background())
	}()

	res := &helloResponse{}
	cmd := bson.D{{Key: "hello", Value: 1}}

	err = client.Database("admin").RunCommand(context.Background(), cmd).Decode(&res)
	if err != nil {
		client.Disconnect(context.Background())

		return nil, fmt.Errorf("failed to run hello command on %s: %w", u.String(), err)
	}

	return res, nil
}

// findPrimary takes the original URI (so we can preserver options) and list of
// host:port addresses to check; it returns the one where a directConnection
// hello reports isWritablePrimary=true.
func findPrimary(baseURI string, hosts []string) (string, error) {
	for _, h := range hosts {
		u, err := url.Parse(baseURI)
		if err != nil {
			return "", fmt.Errorf("failed to parse base URI %q: %w", baseURI, err)
		}

		u.Host = h

		helloResp, err := runHelloCommand(*u)
		if err != nil {
			return "", fmt.Errorf("failed to run handshake on %s: %w", u.Host, err)
		}

		if helloResp.Primary != "" || helloResp.IsWritablePrimary {
			return h, nil
		}
	}

	return "", fmt.Errorf("no primary found in %v", hosts)
}
