# Rate Limiter — Design

## Summary
Add a per-API-key rate limiter to the public REST gateway so a single client
cannot exhaust backend capacity.

## Requirements
- Each API key gets a fixed quota of requests per rolling 60-second window.
- The default quota is 100 requests/minute; quotas are configurable per key.
- The limiter should handle bursts gracefully.
- Requests are counted in a shared store so all gateway instances agree.

## Non-goals
- Per-endpoint quotas (future work).

## Success criteria
- A client exceeding its quota is rate limited.
- The limiter adds negligible latency under normal load.
