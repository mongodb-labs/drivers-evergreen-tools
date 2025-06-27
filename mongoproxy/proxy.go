package mongoproxy

import (
	"crypto/tls"
	"encoding/binary"
	"fmt"
	"io"
	"log"
	"net"
	"net/url"
	"sync"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
	"go.mongodb.org/mongo-driver/v2/x/mongo/driver/connstring"
	"go.mongodb.org/mongo-driver/v2/x/mongo/driver/wiremessage"
)

const (
	defaultListenPort = "28017"
	defaultListenAddr = "127.0.0.1"

	defaultTargetPort = "27017"
	defaultTargetAddr = "127.0.0.1"
)

type connInfo struct {
	cs   *connstring.ConnString // driver-parsed connection string
	addr string                 // resolved target address
}

// ListenAndServe starts the proxy on listenAddr (or default) forwarding to
// targetAddr (or default).
func ListenAndServe(opts ...Option) error {
	cfg := Config{
		ListenAddr: defaultListenAddr + ":" + defaultListenPort,
		TargetAddr: defaultTargetAddr + ":" + defaultTargetPort,
	}

	for _, opt := range opts {
		opt(&cfg)
	}

	targetURI := cfg.TargetURI
	if targetURI == "" {
		targetURI = "mongodb://" + cfg.TargetAddr
	}

	// Add the ca-file and key-file query parameters--make the driver construct
	// the precised tls configuration.
	u, err := url.Parse(targetURI)
	if err != nil {
		return fmt.Errorf("failed to parse target URI %q: %v", targetURI, err)
	}

	u.Path = "/"

	// Grab the existing query params (or an empty map if none).
	q := u.Query()

	if cfg.CAFile != "" {
		q.Set("tls", "true")
		q.Set("tlsCAFile", cfg.CAFile)
		q.Set("directConnection", "true")
	}
	if cfg.KeyFile != "" {
		q.Set("tls", "true")
		q.Set("tlsCertificateKeyFile", cfg.KeyFile)
	}

	// Write the query parameters back to the URL.
	u.RawQuery = q.Encode()

	targetCS, err := connstring.Parse(u.String())
	if err != nil {
		return fmt.Errorf("failed to parse target connection string %q: %v", u.String(), err)
	}

	targetAddr, err := resolveTarget(targetCS)
	if err != nil {
		return fmt.Errorf("failed to resolve target address: %v", err)
	}

	targetConnInfo := connInfo{
		cs:   targetCS,
		addr: targetAddr,
	}

	ln, err := net.Listen("tcp", cfg.ListenAddr)
	if err != nil {
		return fmt.Errorf("failed to listen on %s: %v", cfg.ListenAddr, err)
	}

	log.Printf("Proxy server listening on %s → %s", cfg.ListenAddr, targetAddr)

	for {
		clientConn, err := ln.Accept()
		if err != nil {
			return fmt.Errorf("failed to accept connection: %v", err)
		}

		go handleConnection(clientConn, targetConnInfo)
	}
}

func handleConnection(clientConn net.Conn, targetConnInfo connInfo) {
	defer clientConn.Close()

	var serverConn net.Conn
	var err error

	targetCS := targetConnInfo.cs

	// Let the driver build a clientoptions for us.
	clientOpts := options.Client().ApplyURI(targetConnInfo.cs.Original)

	// Decide TLS v plain TCP from cs.SSL.
	if targetCS.SSLSet && targetCS.SSL {
		serverConn, err = tls.Dial("tcp", targetConnInfo.addr, clientOpts.TLSConfig)
	} else {
		serverConn, err = net.Dial("tcp", targetConnInfo.addr)
	}

	if err != nil {
		log.Printf("failed to dial target %s: %v", targetConnInfo.addr, err)
		return // bail if we can’t reach the real server.
	}
	defer serverConn.Close()

	// proxy both directions
	go proxyClientToMongo(clientConn, serverConn)
	proxyMongoToClient(serverConn, clientConn)
}

// pendingMap tracks per-client pending test instructions.
var pendingMap = &connMap{m: make(map[net.Conn]*testInstruction)}

type connMap struct {
	mu sync.Mutex
	m  map[net.Conn]*testInstruction
}

func (c *connMap) Set(conn net.Conn, instr *testInstruction) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.m[conn] = instr
}

func (c *connMap) Take(conn net.Conn) *testInstruction {
	c.mu.Lock()
	defer c.mu.Unlock()
	instr := c.m[conn]
	delete(c.m, conn)
	return instr
}

// proxyClientToMongo intercepts OP_MSG, strips proxyTest, and forwards
// cleaned message.
func proxyClientToMongo(src net.Conn, dst net.Conn) {
	for {
		raw, err := readWireMessage(src)
		if err != nil {
			return
		}

		// Parse the wire message header.
		length, requestID, responseTo, opcode, body, ok := wiremessage.ReadHeader(raw)
		if !ok || opcode != wiremessage.OpMsg {
			dst.Write(raw)
			continue
		}

		// Skip the flags and read the body.
		flags, body, ok := wiremessage.ReadMsgFlags(body)
		if !ok {
			dst.Write(raw)
			continue
		}

		// Skip the section type and read the body.
		stype, body, ok := wiremessage.ReadMsgSectionType(body)
		if !ok || stype != wiremessage.SingleDocument {
			dst.Write(raw)
			continue
		}

		var (
			doc      []byte
			rest     []byte
			instr    *testInstruction
			cleanDoc []byte
		)

		if stype == wiremessage.SingleDocument {
			doc, rest, ok = wiremessage.ReadMsgSectionSingleDocument(body)
			if ok {
				// Strip out the proxyTest and capture the instructions.
				cleanDoc, instr, err = parseProxy(bson.Raw(doc))
				if err != nil {
					log.Printf("error parsing proxyTest: %v", err)

					return
				}

				if instr != nil {
					pendingMap.Set(src, instr)
				}
			} else {
				dst.Write(raw)

				continue
			}
		} else {
			cleanDoc = nil
		}

		// Reconstruct the wire message without the proxyTest section.
		var newLen int32
		var payload []byte
		if stype == wiremessage.SingleDocument {
			newLen = 16 + 4 + 1 + int32(len(cleanDoc)) + int32(len(rest))
			payload = append(cleanDoc, rest...)
		} else {
			newLen = length
			payload = raw[16:]
		}

		buf := wiremessage.AppendHeader(nil, newLen, requestID, responseTo, wiremessage.OpMsg)
		buf = wiremessage.AppendMsgFlags(buf, flags)
		buf = wiremessage.AppendMsgSectionType(buf, stype)
		buf = append(buf, payload...)

		dst.Write(buf)
	}
}

// readWireMessage reads a length-prefixed MongoDB wire message from src.
func readWireMessage(src io.Reader) ([]byte, error) {
	var lenBuf [4]byte
	if _, err := io.ReadFull(src, lenBuf[:]); err != nil {
		return nil, err
	}
	length := int(binary.LittleEndian.Uint32(lenBuf[:]))

	msg := make([]byte, length)
	copy(msg, lenBuf[:])
	if _, err := io.ReadFull(src, msg[4:]); err != nil {
		return nil, err
	}

	return msg, nil
}

// proxyMongoToClient waits for an instruction on a matching connection, applies it to that first reply, then continues.
func proxyMongoToClient(src net.Conn, dst net.Conn) {
	for {
		// 1) Read the next full wire message from MongoDB
		raw, err := readWireMessage(src)
		if err != nil {
			return
		}

		// 2) Check if we have a proxyTest for this dst
		instr := pendingMap.Take(dst)
		if instr == nil {
			// not our target reply yet, just forward unchanged
			dst.Write(raw)
			continue
		}

		// 3) We found our instructions—apply them
		buf := raw
		sentAll := false

		for _, act := range instr.Actions {
			// a) optional delay
			if act.DelayMs != nil && *act.DelayMs > 0 {
				log.Printf("delaying %d ms before sending next action", *act.DelayMs)
				time.Sleep(time.Duration(*act.DelayMs) * time.Millisecond)
			}
			// b) sendBytes
			if act.SendBytes != nil && *act.SendBytes > 0 {
				log.Printf("sending %d bytes from action", *act.SendBytes)
				n := *act.SendBytes
				if n > len(buf) {
					n = len(buf)
				}
				dst.Write(buf[:n])
				buf = buf[n:]
			}
			// c) sendAll
			if act.SendAll != nil && *act.SendAll {
				log.Printf("sending all remaining bytes from action")
				dst.Write(buf)
				buf = buf[:0]
				sentAll = true
			}
		}

		// 4) If any sendAll happened, proxy the remainder of the stream
		if sentAll {
			if _, err := io.Copy(dst, src); err != nil {
				log.Printf("error copying remaining data to client: %v", err)
			}
		}

		// 5) In *all* cases half‐close the write side so the client sees EOF
		if tcp, ok := dst.(*net.TCPConn); ok {
			tcp.CloseWrite()
		} else {
			dst.Close()
		}
		return
	}
}
