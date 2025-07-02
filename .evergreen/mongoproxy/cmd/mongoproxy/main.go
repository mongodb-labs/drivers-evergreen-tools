package main

import (
	"flag"
	"log"

	"github.com/mongodb-labs/drivers-evergreen-tools/mongoproxy"
)

func main() {
	// Optional flags. Leave them blank/zero to keep library defaults.
	listen := flag.String("listen", "", "proxy listen address, e.g. :27018 (default: library default)")
	target := flag.String("target", "", "upstream MongoDB address, e.g. localhost:27017 (default: library default)")
	targetURI := flag.String("target-uri", "", "upstream MongoDB URI, e.g. mongodb://localhost:27017 (default: library default)")
	caFile := flag.String("ca-file", "", "CA file for TLS connections (default: none)")
	keyFile := flag.String("key-file", "", "Key file for TLS connections (default: none)")

	flag.Parse()

	// Build functional options only for flags the user actually set.
	var opts []mongoproxy.Option
	if *listen != "" {
		opts = append(opts, mongoproxy.WithListenAddr(*listen))
	}
	if *target != "" {
		opts = append(opts, mongoproxy.WithTargetAddr(*target))
	}
	if *targetURI != "" {
		opts = append(opts, mongoproxy.WithTargetURI(*targetURI))
	}
	if *caFile != "" {
		opts = append(opts, mongoproxy.WithCAFile(*caFile))
	}
	if *keyFile != "" {
		opts = append(opts, mongoproxy.WithKeyFile(*keyFile))
	}

	// Start the proxy.
	if err := mongoproxy.ListenAndServe(opts...); err != nil {
		log.Fatalf("failed to start proxy: %v", err)
	}
}
