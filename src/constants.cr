require "uri"

module App
  NAME = "staff-api"
  {% begin %}
    VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
  {% end %}

  ENVIRONMENT = ENV["SG_ENV"]? || "development"
  TEST        = ENVIRONMENT == "test"
  PRODUCTION  = ENVIRONMENT == "production"

  BUILD_TIME   = {{ system("date -u").stringify }}
  BUILD_COMMIT = {{ env("PLACE_COMMIT") || "DEV" }}

  DEFAULT_PORT          = (ENV["SG_SERVER_PORT"]? || 3000).to_i
  DEFAULT_HOST          = ENV["SG_SERVER_HOST"]? || "127.0.0.1"
  DEFAULT_PROCESS_COUNT = (ENV["SG_PROCESS_COUNT"]? || 1).to_i

  COOKIE_SESSION_KEY    = ENV["COOKIE_SESSION_KEY"]? || "_staff_api_"
  COOKIE_SESSION_SECRET = ENV["COOKIE_SESSION_SECRET"]? || "4f74c0b358d5bab4000dd3c75465dc2c"

  Log         = ::Log.for(NAME)
  LOG_BACKEND = ActionController.default_backend

  PG_DATABASE_URL = if url = TEST ? ENV["PG_TEST_DATABASE_URL"]? : ENV["PG_DATABASE_URL"]?
                      url
                    else
                      pg_host = ENV["PG_HOST"]? || "postgres"
                      pg_port = (ENV["PG_PORT"]? || 5432).to_i
                      pg_path = "/" + (ENV["PG_DB"]? || ENV["PG_DATABASE"])
                      pg_user = ENV["PG_USER"]? || "postgres"
                      pg_pass = ENV["PG_PASSWORD"]? || ""
                      pgquery = ENV["PG_QUERY"]?

                      URI.new("postgresql", pg_host, pg_port, pg_path, pgquery, pg_user, pg_pass).to_s
                    end

  PG_CONNECTION_POOL_SIZE = ENV["PG_CONNECTION_POOL_SIZE"]?.presence.try(&.to_i?) || 5

  PLACE_URI = ENV["PLACE_URI"]?.presence || abort("PLACE_URI not in environment")

  SSL_VERIFY_NONE = !!ENV["SSL_VERIFY_NONE"]?.presence.try { |var| var.downcase.in?("1", "true") }

  PG_UNIQUE_CONSTRAINT_REGEX = /duplicate key value violates unique constraint/

  class_getter? running_in_production : Bool = PRODUCTION
end
