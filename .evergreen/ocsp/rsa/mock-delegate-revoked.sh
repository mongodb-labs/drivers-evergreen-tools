#!/usr/bin/env bash
python3 ../ocsp_mock.py \
  --ca_file ca.pem \
  --ocsp_responder_cert ocsp_responder.crt \
  --ocsp_responder_key ocsp_responder.key \
   -p 8100 \
   -v \
   --fault revoked
