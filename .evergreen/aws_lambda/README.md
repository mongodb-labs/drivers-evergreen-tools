# AWS Lamba Testing

See the [FaaS Automated Testing specification](https://github.com/mongodb/specifications/blob/master/source/faas-automated-testing/faas-automated-testing.md) for details.

The deployed Lambda stack, function, and artifact bucket are tagged
`mongodb-owner=client-libraries-managers@mongodb.com`, `mongodb-env=dev`.
Override with `MONGODB_OWNER_TAG`/`MONGODB_ENV_TAG`. Set `VERIFY_MONGODB_TAGS=1`
to verify after deployment.

See [Secrets Handling README](../secrets_handling/README.md) for details on how to access the secrets
from the `drivers/atlas-qa` vault.
