CREATE TABLE IF NOT EXISTS installations (
  install_id TEXT PRIMARY KEY,
  first_seen_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  first_app_version TEXT NOT NULL,
  last_app_version TEXT NOT NULL,
  last_build_number TEXT NOT NULL,
  platform TEXT NOT NULL,
  os_version TEXT NOT NULL,
  last_event_name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS event_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  install_id TEXT NOT NULL,
  event_name TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  local_day TEXT NOT NULL,
  app_version TEXT NOT NULL,
  build_number TEXT NOT NULL,
  platform TEXT NOT NULL,
  os_version TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_event_log_local_day
ON event_log(local_day);

CREATE INDEX IF NOT EXISTS idx_event_log_event_name
ON event_log(event_name);

CREATE TABLE IF NOT EXISTS daily_activity (
  install_id TEXT NOT NULL,
  activity_date TEXT NOT NULL,
  first_seen_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  app_version TEXT NOT NULL,
  build_number TEXT NOT NULL,
  PRIMARY KEY (install_id, activity_date)
);

CREATE INDEX IF NOT EXISTS idx_daily_activity_date
ON daily_activity(activity_date);
