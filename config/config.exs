use Mix.Config

config :ex_banking, :config,
  stale_handler_timeout_seconds: 3600, # 1 hour in seconds
  stale_check_interval: 30000 # 30 seconds in milliseconds
