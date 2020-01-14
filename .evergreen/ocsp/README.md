# Generating test certificates
The test certificates here were generating using the server team's `mkcert.py` tool, which can be found here: https://github.com/mongodb/mongo/blob/master/jstests/ssl/x509/mkcert.py.

In order to generate a fresh set of certificates, the following command should be used from the root of the `mongo` repository (taking into account the location of the `certs.yml` file in this directory):
` python3 jstests/ssl/x509/mkcert.py --config ../drivers-evergreen-tools/.evergreen/ocsp/certs.yml`

The certificates will be output into the folder specified in `certs.yml`. (The default configuration assumes that the `mongo` repository and the `driver-evergreen-tools` repository have the same parent directory.

The final step is to split the `ca_ocsp.pem` file, which contains both the private key and the public certificate, into two files. `ca_ocsp.crt` should contain the public certificate, and `ca_ocsp.key` should contain the private certificate.
