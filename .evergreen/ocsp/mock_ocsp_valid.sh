#!/usr/bin/env sh
# Use the CA as the OCSP responder (see https://community.letsencrypt.org/t/unable-to-verify-ocsp-response/7264)
python3 ocsp_mock.py \
  --ca_file ca_ocsp.pem \
  --ocsp_responder_cert ca_ocsp.crt \
  --ocsp_responder_key ca_ocsp.key \
   -p 8100 \
   -v
