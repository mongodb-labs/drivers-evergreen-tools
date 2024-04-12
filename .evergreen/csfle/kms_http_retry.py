from flask import Flask, request, jsonify, abort
import argparse
import base64
import ssl

app = Flask(__name__)
gcp_decrypt_count = 0
azure_decrypt_count = 0
aws_decrypt_count = 0

fake_ciphertext = 'a' * 96
fake_plaintext = 'b' * 96

# GCP auth request
@app.route('/token', methods=['POST'])
def gcp_auth():
    data = request.form
    print(list(data.items()))
    return jsonify({"access_token": "foo", "expires_in": 99999})

# AWS encrypt or decrypt
# no separate auth endpoint
@app.route('/', methods=['POST'])
def aws():
    if 'X-Amz-Target' in request.headers:
        aws_op = request.headers['X-Amz-Target']
        if aws_op == "TrentService.Encrypt":
            return jsonify({"CiphertextBlob": base64.b64encode(fake_ciphertext.encode()).decode()})
        elif aws_op == "TrentService.Decrypt":
            global aws_decrypt_count
            aws_decrypt_count += 1
            if aws_decrypt_count == 1:
                abort(429, description="Too many requests")
            aws_decrypt_count %= 2
            return jsonify({"Plaintext": base64.b64encode(fake_plaintext.encode()).decode()})
        else:
            abort(404, description=f"Unknown AWS operation: {aws_op}")
    abort(404, description="Unknown operation")

@app.route('/<path:path>', methods=['GET', 'POST'])
def gcp_azure(path):
    global gcp_decrypt_count
    global azure_decrypt_count

    # Azure auth path: /c01df00d-cafe-g00d-dea1-decea5sedbeef/oath2/v2.0/token
    if path.endswith("token"):
        return jsonify({"access_token": "foo", "expires_in": 99999})
    # GCP encrypt
    elif path.endswith("encrypt"):
        return jsonify({"ciphertext": base64.b64encode(fake_ciphertext.encode()).decode()})
    # GCP decrypt
    elif path.endswith("decrypt"):
        gcp_decrypt_count += 1
        if gcp_decrypt_count == 1:
            abort(429, description="Too many requests")
        gcp_decrypt_count %= 2
        return jsonify({"plaintext": base64.b64encode(fake_plaintext.encode()).decode()})
    # Azure decrypt path: /keys/keyname//unwrapkey
    elif path.endswith("unwrapkey"):
        azure_decrypt_count += 1
        if azure_decrypt_count == 1:
            abort(429, description="Too many requests")
        azure_decrypt_count %= 2
        return jsonify({"value": base64.b64encode(fake_plaintext.encode()).decode()})
    # Azure encrypt path: /keys/keyname//wrapkey
    elif path.endswith("wrapkey"):
        return jsonify({"value": base64.b64encode(fake_ciphertext.encode()).decode()})
    return 'You have reached an unhandled route: %s' % path

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='MongoDB Mock AWS KMS Endpoint.')
    parser.add_argument('-p', '--port', type=int, default=8000, help="Port to listen on")
    args = parser.parse_args()

    certfile = '../x509gen/server.pem'
    cafile = '../x509gen/ca.pem'

    context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    context.load_cert_chain(certfile=certfile, keyfile=certfile)
    context.load_verify_locations(cafile=cafile)
    context.verify_mode = ssl.CERT_OPTIONAL
    
    app = Flask(__name__)
    app.run(debug=False, port=args.port, ssl_context=context)
