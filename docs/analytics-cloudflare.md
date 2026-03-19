# Cloudflare Analytics Setup

This repository includes a minimal anonymous usage analytics path for public DMG releases:

- App client: [`TurtleneckCoach/Services/UsageAnalyticsService.swift`](../TurtleneckCoach/Services/UsageAnalyticsService.swift)
- Worker: [`cloudflare/usage-analytics/src/index.js`](../cloudflare/usage-analytics/src/index.js)
- D1 schema: [`cloudflare/usage-analytics/schema.sql`](../cloudflare/usage-analytics/schema.sql)

The app sends only three event types:

- `first_install`
- `app_open`
- `daily_active`

Each event contains only:

- random install ID
- event name
- app version and build number
- macOS version
- UTC timestamp and local calendar day

It does **not** send camera frames, posture scores, calibration data, or session history.

## 1) Create the D1 database

```bash
cd cloudflare/usage-analytics
wrangler d1 create turtleneck-analytics
```

Copy the returned `database_id` into [`wrangler.toml`](../cloudflare/usage-analytics/wrangler.toml).

## 2) Apply the schema

```bash
cd cloudflare/usage-analytics
wrangler d1 execute turtleneck-analytics --file ./schema.sql
```

## 3) Set the admin token secret

The ingest endpoint is anonymous by design, but the stats endpoint is protected with a bearer token.

```bash
cd cloudflare/usage-analytics
wrangler secret put ADMIN_TOKEN
```

Use a long random string and keep it private.

## 4) Deploy the worker

```bash
cd cloudflare/usage-analytics
wrangler deploy
```

After deploy, note the Worker URL. The app should post to:

```text
https://<your-worker-domain>/v1/events
```

## 5) Build the public DMG with analytics enabled

```bash
ANALYTICS_ENDPOINT_URL=https://<your-worker-domain>/v1/events \
./scripts/build-release.sh "Developer ID Application: Your Name (TEAMID)"
```

Optional:

```bash
ANALYTICS_ENABLED_BY_DEFAULT=0 \
ANALYTICS_ENDPOINT_URL=https://<your-worker-domain>/v1/events \
./scripts/build-release.sh "Developer ID Application: Your Name (TEAMID)"
```

When `ANALYTICS_ENABLED_BY_DEFAULT=0`, the Settings toggle starts off and users must opt in manually.

## 6) Read active-user stats

Repository helper:

```bash
ANALYTICS_BASE_URL=https://<your-worker-domain> \
ANALYTICS_ADMIN_TOKEN=<ADMIN_TOKEN> \
./scripts/analytics-stats.sh 30
```

Raw curl:

```bash
curl \
  -H "User-Agent: TurtleneckCoachStats/1.0 CFNetwork Darwin" \
  -H "Authorization: Bearer <ADMIN_TOKEN>" \
  "https://<your-worker-domain>/v1/stats?days=30"
```

Example response shape:

```json
{
  "totalInstalls": 42,
  "latestActivityDay": "2026-03-18",
  "dau": 12,
  "wau": 24,
  "mau": 31,
  "series": [
    { "date": "2026-03-16", "activeInstalls": 10 },
    { "date": "2026-03-17", "activeInstalls": 11 },
    { "date": "2026-03-18", "activeInstalls": 12 }
  ]
}
```

## Notes

- Keep the Worker behind HTTPS only.
- Do not add posture scores or raw image data to analytics events.
- The current client is best-effort delivery. If the network is unavailable, the app skips the event instead of retrying forever.
