# mongoproxy

**mongoproxy** is a lightweight, programmable TCP proxy for MongoDB. It sits between your client and a real MongoDB server and allows you to simulate broken or delayed network behavior — useful for testing retry logic, timeouts, and error handling in database drivers or applications.

- Inject millisecond-level delays into server responses
- Send only part of a reply (`sendBytes`)
- Flush the rest after a delay (`sendAll`)
- Simulate mid-stream disconnects
- Easily trigger timeouts, EOFs, or corrupted reads

## 📦 Installation

To install the latest version:

```bash
go install github.com/prestonvasquez/mongoproxy/cmd/mongoproxy@latest
```

Or build it locally in `bin/mongoproxy`:

```bash
bash build.sh
```

Running tests requires Docker:

```bash
go test ./...
```

## 🔧 Usage

To simulate network-level faults during testing, you can include a special `proxyTest` field in your command document. This field should contain an `actions` array to instruct the proxy how to manipulate the server’s reply.

| Action     | Parameter | Description                                            |
|------------|-----------|--------------------------------------------------------|
| `delayMs`  | number    | Pause forwarding for the specified milliseconds.       |
| `sendBytes`| number    | Forward exactly that many bytes from the response.     |
| `sendAll`  | boolean   | Forward all remaining bytes in the response.           |

Example:

```
{
  "ping": 1,
  "proxyTest": {
    "actions": [
      { "sendBytes": 1 },    // send only the first byte of the server response
      { "delayMs": 200 },    // wait 200 milliseconds
      { "sendAll": true }    // then send the remainder of the message
    ]
  }
}
```

This simulates a partial response followed by a delay, then a full flush — useful for testing client behavior during slow or fragmented network reads.

> ⚠️ These fields are intercepted by `mongoproxy` and **do not reach the MongoDB server**. They are intended for use in integration tests, not production.
