const ALLOWED_EVENTS = new Set(["first_install", "app_open", "daily_active"]);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: buildCorsHeaders(request),
      });
    }

    if (request.method === "GET" && url.pathname === "/health") {
      return jsonResponse({ ok: true }, 200, request);
    }

    if (request.method === "GET" && url.pathname === "/v1/events") {
      return jsonResponse(
        {
          ok: true,
          message: "POST JSON events to this endpoint.",
          acceptedMethods: ["POST"],
          healthURL: "/health",
          statsURL: "/v1/stats?days=30",
        },
        200,
        request
      );
    }

    if (request.method === "POST" && url.pathname === "/v1/events") {
      return handleEventIngest(request, env);
    }

    if (request.method === "GET" && url.pathname === "/v1/stats") {
      return handleStats(request, env);
    }

    return jsonResponse({ error: "not_found" }, 404, request);
  },
};

async function handleEventIngest(request, env) {
  let body;

  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400, request);
  }

  const payload = normalizeEventPayload(body);
  if (!payload.ok) {
    return jsonResponse({ error: payload.error }, 400, request);
  }

  const event = payload.value;

  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO event_log (
        install_id,
        event_name,
        occurred_at,
        local_day,
        app_version,
        build_number,
        platform,
        os_version
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      event.installID,
      event.eventName,
      event.occurredAt,
      event.localDay,
      event.appVersion,
      event.buildNumber,
      event.platform,
      event.osVersion
    ),
    env.DB.prepare(
      `INSERT INTO installations (
        install_id,
        first_seen_at,
        last_seen_at,
        first_app_version,
        last_app_version,
        last_build_number,
        platform,
        os_version,
        last_event_name
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(install_id) DO UPDATE SET
        last_seen_at = excluded.last_seen_at,
        last_app_version = excluded.last_app_version,
        last_build_number = excluded.last_build_number,
        platform = excluded.platform,
        os_version = excluded.os_version,
        last_event_name = excluded.last_event_name`
    ).bind(
      event.installID,
      event.occurredAt,
      event.occurredAt,
      event.appVersion,
      event.appVersion,
      event.buildNumber,
      event.platform,
      event.osVersion,
      event.eventName
    ),
    env.DB.prepare(
      `INSERT INTO daily_activity (
        install_id,
        activity_date,
        first_seen_at,
        last_seen_at,
        app_version,
        build_number
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(install_id, activity_date) DO UPDATE SET
        last_seen_at = excluded.last_seen_at,
        app_version = excluded.app_version,
        build_number = excluded.build_number`
    ).bind(
      event.installID,
      event.localDay,
      event.occurredAt,
      event.occurredAt,
      event.appVersion,
      event.buildNumber
    ),
  ]);

  return jsonResponse({ ok: true }, 202, request);
}

async function handleStats(request, env) {
  if (!isAuthorized(request, env.ADMIN_TOKEN)) {
    return jsonResponse({ error: "unauthorized" }, 401, request);
  }

  const url = new URL(request.url);
  const requestedDays = Number.parseInt(url.searchParams.get("days") ?? "30", 10);
  const days = Number.isFinite(requestedDays)
    ? Math.min(Math.max(requestedDays, 7), 180)
    : 30;

  const totalInstalls = await readInteger(
    env.DB.prepare("SELECT COUNT(*) AS value FROM installations")
  );

  const latestActivityDay = await readString(
    env.DB.prepare("SELECT MAX(activity_date) AS value FROM daily_activity")
  );

  if (!latestActivityDay) {
    return jsonResponse(
      {
        totalInstalls,
        latestActivityDay: null,
        dau: 0,
        wau: 0,
        mau: 0,
        series: [],
      },
      200,
      request
    );
  }

  const dau = await readInteger(
    env.DB.prepare(
      "SELECT COUNT(*) AS value FROM daily_activity WHERE activity_date = ?"
    ).bind(latestActivityDay)
  );

  const wau = await readInteger(
    env.DB.prepare(
      `SELECT COUNT(DISTINCT install_id) AS value
       FROM daily_activity
       WHERE activity_date BETWEEN date(?, '-6 day') AND ?`
    ).bind(latestActivityDay, latestActivityDay)
  );

  const mau = await readInteger(
    env.DB.prepare(
      `SELECT COUNT(DISTINCT install_id) AS value
       FROM daily_activity
       WHERE activity_date BETWEEN date(?, '-29 day') AND ?`
    ).bind(latestActivityDay, latestActivityDay)
  );

  const seriesResult = await env.DB.prepare(
    `SELECT activity_date, COUNT(*) AS active_installs
     FROM daily_activity
     WHERE activity_date BETWEEN date(?, ?) AND ?
     GROUP BY activity_date
     ORDER BY activity_date ASC`
  )
    .bind(latestActivityDay, `-${days - 1} day`, latestActivityDay)
    .all();

  const series = (seriesResult.results ?? []).map((row) => ({
    date: row.activity_date,
    activeInstalls: Number(row.active_installs ?? 0),
  }));

  return jsonResponse(
    {
      totalInstalls,
      latestActivityDay,
      dau,
      wau,
      mau,
      series,
    },
    200,
    request
  );
}

function normalizeEventPayload(body) {
  if (!body || typeof body !== "object") {
    return { ok: false, error: "invalid_payload" };
  }

  const installID = normalizeString(body.install_id, 64);
  if (!/^[a-f0-9-]{16,64}$/.test(installID)) {
    return { ok: false, error: "invalid_install_id" };
  }

  const eventName = normalizeString(body.event_name, 32);
  if (!ALLOWED_EVENTS.has(eventName)) {
    return { ok: false, error: "invalid_event_name" };
  }

  const occurredAtDate = new Date(body.occurred_at);
  if (Number.isNaN(occurredAtDate.valueOf())) {
    return { ok: false, error: "invalid_occurred_at" };
  }

  const localDay = normalizeString(body.local_day, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(localDay)) {
    return { ok: false, error: "invalid_local_day" };
  }

  const appVersion = normalizeString(body.app_version, 32) || "unknown";
  const buildNumber = normalizeString(body.build_number, 32) || "unknown";
  const platform = normalizeString(body.platform, 32) || "macOS";
  const osVersion = normalizeString(body.os_version, 128) || "unknown";

  return {
    ok: true,
    value: {
      installID,
      eventName,
      occurredAt: occurredAtDate.toISOString(),
      localDay,
      appVersion,
      buildNumber,
      platform,
      osVersion,
    },
  };
}

function normalizeString(value, maxLength) {
  if (typeof value !== "string") {
    return "";
  }

  return value.trim().slice(0, maxLength);
}

async function readInteger(statement) {
  const row = await statement.first();
  return Number(row?.value ?? 0);
}

async function readString(statement) {
  const row = await statement.first();
  const value = row?.value;
  return typeof value === "string" && value.length > 0 ? value : null;
}

function isAuthorized(request, adminToken) {
  if (!adminToken) {
    return false;
  }

  const header = request.headers.get("Authorization") ?? "";
  return header === `Bearer ${adminToken}`;
}

function jsonResponse(body, status, request) {
  const headers = new Headers({
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });

  if (request) {
    const corsHeaders = buildCorsHeaders(request);
    for (const [key, value] of corsHeaders.entries()) {
      headers.set(key, value);
    }
  }

  return new Response(JSON.stringify(body), {
    status,
    headers,
  });
}

function buildCorsHeaders(request) {
  const headers = new Headers();
  const origin = request.headers.get("Origin");

  headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  headers.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
  headers.set("Access-Control-Max-Age", "86400");
  headers.set("Access-Control-Allow-Origin", origin || "*");

  return headers;
}
