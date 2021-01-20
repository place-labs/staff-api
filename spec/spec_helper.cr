require "spec"

# Your application config
# If you have a testing environment, replace this with a test config file
require "../src/config"

# Helper methods for testing controllers (curl, with_server, context)
require "../lib/action-controller/spec/curl_context"
require "webmock"

Spec.before_suite do
  truncate_db
  # Since almost all specs need need tenant to work
  TenantsHelper.create_tenant
end

Spec.before_suite do
  # -Dquiet
  {% if flag?(:quiet) %}
    ::Log.setup(:warning)
  {% else %}
    ::Log.setup(:debug)
  {% end %}
end

def truncate_db
  Clear::SQL.execute("TRUNCATE TABLE bookings CASCADE;")
  Clear::SQL.execute("TRUNCATE TABLE event_metadatas CASCADE;")
  Clear::SQL.execute("TRUNCATE TABLE guests CASCADE;")
  Clear::SQL.execute("TRUNCATE TABLE attendees CASCADE;")
  Clear::SQL.execute("TRUNCATE TABLE tenants CASCADE;")
end

Spec.before_each &->WebMock.reset

def office_mock_token
  UserJWT.new(
    iss: "staff-api",
    iat: Time.local,
    exp: Time.local + 1.week,
    aud: "toby.staff-api.dev",
    sub: "toby@redant.com.au",
    scope: ["public"],
    user: UserJWT::Metadata.new(
      name: "Toby Carvan",
      email: "dev@acaprojects.com",
      permissions: UserJWT::Permissions::Admin,
      roles: ["manage", "admin"]
    )
  ).encode
end

def office_guest_mock_token(guest_event_id, system_id)
  UserJWT.new(
    iss: "staff-api",
    iat: Time.local,
    exp: Time.local + 1.week,
    aud: "toby.staff-api.dev",
    sub: "toby@redant.com.au",
    scope: ["guest"],
    user: UserJWT::Metadata.new(
      name: "Jon Jon",
      email: "jon@example.com",
      permissions: UserJWT::Permissions::Admin,
      roles: [guest_event_id, system_id]
    )
  ).encode
end

def google_mock_token
  UserJWT.new(
    iss: "staff-api",
    iat: Time.local,
    exp: Time.local + 1.week,
    aud: "google.staff-api.dev",
    sub: "amit@redant.com.au",
    scope: ["public", "guest"],
    user: UserJWT::Metadata.new(
      name: "Amit Gaur",
      email: "amit@redant.com.au",
      permissions: UserJWT::Permissions::Admin,
      roles: ["manage", "admin"]
    )
  ).encode
end

# Provide some basic headers for office365 auth
OFFICE365_HEADERS = {
  "Host"          => "toby.staff-api.dev",
  "Authorization" => "Bearer #{office_mock_token}",
}

# Provide some basic headers for office365 auth
def office365_guest_headers(guest_event_id, system_id)
  {
    "Host"          => "toby.staff-api.dev",
    "Authorization" => "Bearer #{office_guest_mock_token(guest_event_id, system_id)}",
  }
end

# Provide some basic headers for google auth
GOOGLE_HEADERS = {
  "Host"          => "google.staff-api.dev",
  "Authorization" => "Bearer #{google_mock_token}",
}

module EventMetadatasHelper
  extend self

  def create_event(tenant_id,
                   id,
                   event_start = Time.utc.to_unix,
                   event_end = 60.minutes.from_now.to_unix,
                   system_id = "sys_id",
                   room_email = "room@example.com",
                   host = "user@example.com",
                   ext_data = JSON.parse({"foo": 123}.to_json),
                   ical_uid = "random_uid")
    EventMetadata.create!({
      tenant_id:         tenant_id,
      system_id:         system_id,
      event_id:          id,
      host_email:        host,
      resource_calendar: room_email,
      event_start:       event_start,
      event_end:         event_end,
      ext_data:          ext_data,
      ical_uid:          ical_uid,
    })
  end
end

module Context(T, M)
  extend self

  def response(method : String, route : String, route_params : Hash(String, String)? = nil, headers : Hash(String, String)? = nil, body : String | Bytes | IO | Nil = nil, &block)
    ctx = instantiate_context(method, route, route_params, headers, body)
    instance = T.new(ctx)
    yield instance
    ctx.response.output.rewind
    res = ctx.response

    body = if M == JSON::Any
             JSON.parse(res.output)
           else
             M.from_json(res.output)
           end

    {ctx.response.status_code, body}
  end
end
