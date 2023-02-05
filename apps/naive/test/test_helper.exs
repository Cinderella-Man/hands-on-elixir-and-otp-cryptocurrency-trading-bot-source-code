Application.ensure_all_started(:mimic)

Mimic.copy(BinanceMock)
Mimic.copy(Phoenix.PubSub)

ExUnit.start(capture_log: true)
