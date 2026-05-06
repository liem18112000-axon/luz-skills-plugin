# Authentication subsystem migration

We are migrating the authentication subsystem from the legacy session-based approach to a new token-based approach. The legacy system uses server-side sessions stored in Redis with a 30-minute idle timeout. The new system will use signed JWT tokens with a 15-minute access window and a 7-day refresh window.

## Why we are doing this

The legacy session store has been a recurring source of incidents. We have had three production outages in the last 18 months caused by Redis cluster failovers leaving thousands of users in a half-authenticated state. The blast radius of a session-store outage is the entire authenticated user surface, which is not acceptable. With JWTs, validation is stateless and a Redis outage no longer cascades into authentication failures.

There is also a compliance angle. The legal team has flagged that our current session storage retains user identifiers in a way that does not meet the new data residency requirements coming into effect on 2026-09-01. JWTs let us avoid centralized storage of session-bound user data entirely.

## What changes

The service `validate_session(token)` in `src/auth/session.py` is replaced by `validate_jwt(token)` in `src/auth/jwt.py`. All call sites need updating. The integration test suite at `tests/auth/test_session.py` is preserved as a regression check and a new suite at `tests/auth/test_jwt.py` is added.

The new flow is documented at https://wiki.example.com/runbooks/hotfix and the staging endpoint for testing is https://staging.example.com. Production endpoint remains https://api.example.com.

Service-to-service callers must update their client libraries to version 4.2.0 or later. The breaking change is that the `Authorization` header now carries a JWT instead of a session ID, and the token format is `Bearer eyJ...`.

## Rollout plan

We are rolling this out in three phases. Phase 1 covers internal services only and runs from 2026-05-15 to 2026-06-01. Phase 2 extends to partner services and runs through 2026-07-01. Phase 3 is the full public rollout.

During Phase 1 we expect roughly 5000 requests per second of authentication traffic. During Phase 3 we expect to scale to 1500 requests per second per region across 600 regions worldwide. Latency budget is 3 milliseconds at p99 for token validation.

## Risks and mitigations

The biggest risk is token revocation. JWTs are not revocable by default, so a compromised token remains valid until expiry. We mitigate this with a short 15-minute access window and a revocation list checked at refresh time. The revocation list is small enough to fit in process memory on every service.

A secondary risk is clock skew. Token validation depends on synchronised clocks across the fleet. We require all hosts to run NTP and we allow a 30-second tolerance window in validation.

If any production incident occurs, page the on-call engineer in `#security-help` on Slack. The runbook is linked above. Do not attempt to roll back individual services — the rollback is fleet-wide and coordinated by the platform team.
