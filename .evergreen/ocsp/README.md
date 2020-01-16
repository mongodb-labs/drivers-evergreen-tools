# Generating Test Certificates

The test certificates here were generating using the server team's [`mkcert.py`](https://github.com/mongodb/mongo/blob/master/jstests/ssl/x509/mkcert.py) tool.

In order to generate a fresh set of certificates, clone the [`mongo` repository](https://github.com/mongodb/mongo) and run the following command from the root of the `mongo` repository:

`python3 jstests/ssl/x509/mkcert.py --config ../drivers-evergreen-tools/.evergreen/ocsp/certs.yml`

The certificates will be output into the folder specified by the `global.output_path` option in `certs.yml`, which defaults to the same directory as this README file and `certs.yml`. The default configuration also assumes that the `mongo` repository and the `driver-evergreen-tools` repository have the same parent directory.

The final step is to split the `ca_ocsp.pem` file, which contains both the private key and the public certificate, into two files. `ca_ocsp.crt` should contain the public certificate, and `ca_ocsp.key` should contain the private certificate.
