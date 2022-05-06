require "../spec_helper"
require "./helpers/event_helper"
require "./helpers/spec_clean_up"

EVENTS_BASE = Events.base_route

describe Events do
  before_each do
    EventsHelper.stub_event_tokens
  end

  describe "#index" do
    it "#index should return a list of events with metadata" do
      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.com/calendar?")
        .to_return(body: File.read("./spec/fixtures/calendars/o365/show.json"))
      WebMock.stub(:get, "#{ENV["PLACE_URI"]}/api/engine/v2/systems?limit=1000&offset=0&zone_id=z1")
        .to_return(body: File.read("./spec/fixtures/placeos/systems.json"))
      WebMock.stub(:post, "https://graph.microsoft.com/v1.0/%24batch")
        .to_return(body: File.read("./spec/fixtures/events/o365/batch_index.json"))

      tenant = get_tenant
      event = EventMetadatasHelper.create_event(tenant.id)

      body = Context(Events, JSON::Any).response("GET", "#{EVENTS_BASE}?zone_ids=z1&period_start=#{event.event_start}&period_end=#{event.event_end}", headers: Mock::Headers.office365_guest, &.index)[1].as_a

      body.includes?(event.system_id)
      body.includes?(%("host" => "#{event.host_email}"))
      body.includes?(%("id" => "#{event.system_id}"))
      body.includes?(%("extension_data" => {#{event.ext_data}}))
    end

    it "metadata extension endpoint should filter by extension data" do
      WebMock.stub(:get, "#{ENV["PLACE_URI"]}/api/engine/v2/systems?limit=1000&offset=0&zone_id=z1")
        .to_return(body: File.read("./spec/fixtures/placeos/systems.json"))
      WebMock.stub(:post, "https://graph.microsoft.com/v1.0/%24batch")
        .to_return(body: File.read("./spec/fixtures/events/o365/batch_index.json"))

      tenant = get_tenant

      EventMetadatasHelper.create_event(tenant.id, ext_data: JSON.parse({"colour": "blue"}.to_json))
      EventMetadatasHelper.create_event(tenant.id)
      EventMetadatasHelper.create_event(tenant.id, ext_data: JSON.parse({"colour": "red"}.to_json))

      field_name = "colour"
      value = "blue"

      body = Context(Events, JSON::Any).response("GET", "#{EVENTS_BASE}/extension_metadata?field_name=#{field_name}&value=#{value}", headers: Mock::Headers.office365_guest, &.extension_metadata)[1]
      body.to_s.includes?("red").should be_false
    end

    it "#index should return a list of events with metadata of master event if event in list is an occurrence" do
      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.com/calendar?")
        .to_return(body: File.read("./spec/fixtures/calendars/o365/show.json"))
      WebMock.stub(:post, "#{ENV["PLACE_URI"]}/auth/oauth/token")
        .to_return(body: File.read("./spec/fixtures/tokens/placeos_token.json"))
      WebMock.stub(:get, "#{ENV["PLACE_URI"]}/api/engine/v2/systems?limit=1000&offset=0&zone_id=zone-EzcsmWbvUG6")
        .to_return(body: File.read("./spec/fixtures/placeos/systemJ.json"))
      WebMock.stub(:post, "https://graph.microsoft.com/v1.0/%24batch")
        .to_return(body: File.read("./spec/fixtures/events/o365/batch_index_with_recurring_event.json"))

      now = 1.minutes.from_now.to_unix
      later = 80.minutes.from_now.to_unix
      master_event_id = "AAMkADE3YmQxMGQ2LTRmZDgtNDljYy1hNDg1LWM0NzFmMGI0ZTQ3YgBGAAAAAADFYQb3DJ_xSJHh14kbXHWhBwB08dwEuoS_QYSBDzuv558sAAAAAAENAAB08dwEuoS_QYSBDzuv558sAAB8_ORMAAA="

      tenant = get_tenant
      5.times { EventMetadatasHelper.create_event(tenant.id) }

      body = Context(Events, JSON::Any).response("GET", "#{EVENTS_BASE}/?period_start=#{now}&period_end=#{later}", headers: Mock::Headers.office365_guest, &.index)[1].to_s
      body.includes?(%("recurring_master_id" => "#{master_event_id}"))
    end
  end

  describe "#create" do
    before_each do
      EventsHelper.stub_create_endpoints
    end
    it "with attendees and extension data" do
      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev@acaprojects.com/calendar/events/AAMkADE3YmQxMGQ2LTRmZDgtNDljYy1hNDg1LWM0NzFmMGI0ZTQ3YgBGAAAAAADFYQb3DJ_xSJHh14kbXHWhBwB08dwEuoS_QYSBDzuv558sAAAAAAENAAB08dwEuoS_QYSBDzuv558sAACGVOwUAAA=")
        .to_return(body: File.read("./spec/fixtures/events/o365/create.json"))
      WebMock.stub(:patch, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.onmicrosoft.com/calendar/events/")
        .to_return(body: File.read("./spec/fixtures/events/o365/update.json"))
      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.com/calendars")
        .to_return(body: File.read("./spec/fixtures/calendars/o365/show.json"))

      req_body = EventsHelper.create_event_input

      tenant = get_tenant
      event = EventMetadatasHelper.create_event(tenant.id)
      created_event = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/", body: req_body, headers: Mock::Headers.office365_guest, &.create)[1].as_h
      created_event.to_s.includes?(%("event_start" => #{event.event_start}))

      # Should have created metadata record
      evt_meta = EventMetadata.query.find! { event_id == created_event["id"] }
      evt_meta.event_start.should eq(1598503500)
      evt_meta.event_end.should eq(1598507160)
      evt_meta.system_id.should eq("sys-rJQQlR4Cn7")
      evt_meta.host_email.should eq("dev@acaprojects.onmicrosoft.com")
      evt_meta.ext_data.not_nil!.as_h.should eq({"foo" => "bar"})

      # Should have created attendees records
      # 2 guests + 1 host
      evt_meta.attendees.count.should eq(3)

      # Should have created guests records
      guests = evt_meta.attendees.map(&.guest)
      guests.map(&.name).should eq(["Amit", "John", "dev@acaprojects.onmicrosoft.com"])
      guests.compact_map(&.email).should eq(["amit@redant.com.au", "jon@example.com", "dev@acaprojects.onmicrosoft.com"])
      guests.compact_map(&.preferred_name).should eq(["Jon"])
      guests.compact_map(&.phone).should eq(["012334446"])
      guests.compact_map(&.organisation).should eq(["Google inc"])
      guests.compact_map(&.notes).should eq(["some notes"])
      guests.compact_map(&.photo).should eq(["http://example.com/first.jpg"])
      guests.compact_map(&.searchable).should eq(["amit@redant.com.au amit   ", "jon@example.com john jon google inc 012334446", "dev@acaprojects.onmicrosoft.com dev@acaprojects.onmicrosoft.com   "])
      guests.compact_map(&.extension_data).should eq([{} of String => String?, {"fizz" => "buzz"}, {} of String => String?])
    end
  end

  describe "#update" do
    before_each do
      EventsHelper.stub_create_endpoints
    end
    it "for system" do
      WebMock.stub(:post, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.onmicrosoft.com/calendar/events")
        .to_return(body: File.read("./spec/fixtures/events/o365/create.json"))

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/events/AAMkADE3YmQxMGQ2LTRmZDgtNDljYy1hNDg1LWM0NzFmMGI0ZTQ3YgBGAAAAAADFYQb3DJ_xSJHh14kbXHWhBwB08dwEuoS_QYSBDzuv558sAAAAAAENAAB08dwEuoS_QYSBDzuv558sAACGVOwUAAA%3D")
        .to_return(body: File.read("./spec/fixtures/events/o365/create.json"))

      WebMock.stub(:patch, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.onmicrosoft.com/calendar/events/")
        .to_return(body: File.read("./spec/fixtures/events/o365/update.json"))
      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.com/calendars")
        .to_return(body: File.read("./spec/fixtures/calendars/o365/show.json"))

      req_body = EventsHelper.create_event_input

      created_event = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/", body: req_body, headers: Mock::Headers.office365_guest, &.create)[1].as_h

      created_event_id = created_event["id"].to_s

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/calendarView?startDateTime=2020-08-26T14:00:00-00:00&endDateTime=2020-08-27T13:59:59-00:00&%24filter=iCalUId+eq+%27040000008200E00074C5B7101A82E008000000006DE2E3761F8AD6010000000000000000100000009CCCDBB1F09DE74D8B157797D97F6A10%27&$top=10000")
        .to_return(EventsHelper.event_query_response(created_event_id))

      req_body = EventsHelper.update_event_input

      updated_event = Context(Events, JSON::Any).response("PATCH", "#{EVENTS_BASE}/#{created_event["id"]}?system_id=sys-rJQQlR4Cn7", route_params: {"id" => created_event_id}, body: req_body, headers: Mock::Headers.office365_guest, &.update)[1].as_h
      updated_event.to_s.includes?(%(some updated notes))
      # .should eq(EventsHelper.update_event_output)
      # Should have updated metadata record
      evt_meta = EventMetadata.query.find! { event_id == updated_event["id"] }
      evt_meta.event_start.should eq(1598504460)
      evt_meta.event_end.should eq(1598508120)

      # Should still have 3 created attendees records
      # 2 guests + 1 host
      evt_meta.attendees.count.should eq(3)

      # Should have updated guests records
      guests = evt_meta.attendees.map(&.guest)
      guests.map(&.name).should eq(["Amit", "dev@acaprojects.onmicrosoft.com", "Robert"])
      guests.compact_map(&.email).should eq(["amit@redant.com.au", "dev@acaprojects.onmicrosoft.com", "bob@example.com"])
      guests.compact_map(&.preferred_name).should eq(["bob"])
      guests.compact_map(&.phone).should eq(["012333336"])
      guests.compact_map(&.organisation).should eq(["Apple inc"])
      guests.compact_map(&.notes).should eq(["some updated notes"])
      guests.compact_map(&.photo).should eq(["http://example.com/bob.jpg"])
      guests.compact_map(&.extension_data).should eq([{"fuzz" => "bizz"}, {} of String => String?, {"buzz" => "fuzz"}])
    end

    it "extension data for guest" do
      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/jon@example.com/calendar/events/AAMkADE3YmQxMGQ2LTRmZDgtNDljYy1hNDg1LWM0NzFmMGI0ZTQ3YgBGAAAAAADFYQb3DJ_xSJHh14kbXHWhBwB08dwEuoS_QYSBDzuv558sAAAAAAENAAB08dwEuoS_QYSBDzuv558sAACGVOwUAAA=")
        .to_return(body: File.read("./spec/fixtures/events/o365/create.json"))
      WebMock.stub(:post, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.onmicrosoft.com/calendar/events")
        .to_return(body: File.read("./spec/fixtures/events/o365/create.json"))

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/events/AAMkADE3YmQxMGQ2LTRmZDgtNDljYy1hNDg1LWM0NzFmMGI0ZTQ3YgBGAAAAAADFYQb3DJ_xSJHh14kbXHWhBwB08dwEuoS_QYSBDzuv558sAAAAAAENAAB08dwEuoS_QYSBDzuv558sAACGVOwUAAA%3D")
        .to_return(body: File.read("./spec/fixtures/events/o365/create.json"))

      WebMock.stub(:patch, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.onmicrosoft.com/calendar/events/")
        .to_return(body: File.read("./spec/fixtures/events/o365/update.json"))
      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.com/calendars")
        .to_return(body: File.read("./spec/fixtures/calendars/o365/show.json"))

      req_body = EventsHelper.create_event_input
      created_event = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/", body: req_body, headers: Mock::Headers.office365_guest, &.create)[1].as_h

      created_event_id = created_event["id"].to_s

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/calendarView?startDateTime=2020-08-26T14:00:00-00:00&endDateTime=2020-08-27T13:59:59-00:00&%24filter=iCalUId+eq+%27040000008200E00074C5B7101A82E008000000006DE2E3761F8AD6010000000000000000100000009CCCDBB1F09DE74D8B157797D97F6A10%27&$top=10000")
        .to_return(EventsHelper.event_query_response(created_event_id))

      # Guest Update
      req_body = EventsHelper.update_event_input
      updated_event = Context(Events, JSON::Any).response("PATCH", "#{EVENTS_BASE}/#{created_event["id"]}?system_id=sys-rJQQlR4Cn7", route_params: {"id" => created_event_id}, body: req_body, headers: Mock::Headers.office365_guest(created_event_id, "sys-rJQQlR4Cn7"), &.update)[1].as_h

      # Should have only updated extension in metadata record
      evt_meta = EventMetadata.query.find! { event_id == updated_event["id"] }
      evt_meta.event_start.should eq(1598503500)                      # unchanged event start
      evt_meta.event_end.should eq(1598507160)                        # unchanged event end
      evt_meta.ext_data.should eq({"foo" => "bar", "fizz" => "buzz"}) # updated event extension
    end

    it "#for user calendar" do
      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.com/calendar?")
        .to_return(body: File.read("./spec/fixtures/calendars/o365/show.json"))

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.com/calendars")
        .to_return(body: File.read("./spec/fixtures/calendars/o365/show.json"))
      WebMock.stub(:post, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.onmicrosoft.com/calendar/events")
        .to_return(body: File.read("./spec/fixtures/events/o365/create.json"))

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/events/AAMkADE3YmQxMGQ2LTRmZDgtNDljYy1hNDg1LWM0NzFmMGI0ZTQ3YgBGAAAAAADFYQb3DJ_xSJHh14kbXHWhBwB08dwEuoS_QYSBDzuv558sAAAAAAENAAB08dwEuoS_QYSBDzuv558sAACGVOwUAAA%3D")
        .to_return(body: File.read("./spec/fixtures/events/o365/create.json"))
      WebMock.stub(:patch, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.onmicrosoft.com/calendar/events/")
        .to_return(body: File.read("./spec/fixtures/events/o365/update.json"))

      req_body = EventsHelper.create_event_input

      created_event = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/", body: req_body, headers: Mock::Headers.office365_guest, &.create)[1].as_h

      created_event_id = created_event["id"].to_s

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/calendarView?startDateTime=2020-08-26T14:00:00-00:00&endDateTime=2020-08-27T13:59:59-00:00&%24filter=iCalUId+eq+%27040000008200E00074C5B7101A82E008000000006DE2E3761F8AD6010000000000000000100000009CCCDBB1F09DE74D8B157797D97F6A10%27&$top=10000")
        .to_return(EventsHelper.event_query_response(created_event_id))

      # Update
      req_body = EventsHelper.update_event_input

      updated_event = Context(Events, JSON::Any).response("PATCH", "#{EVENTS_BASE}/#{created_event["id"]}?system_id=sys-rJQQlR4Cn7", route_params: {"id" => created_event_id}, body: req_body, headers: Mock::Headers.office365_guest, &.update)[1].as_h

      updated_event["event_start"].should eq(1598504460)
      updated_event["event_end"].should eq(1598508120)
    end
  end

  describe "#show" do
    before_each do
      EventsHelper.stub_show_endpoints
    end
    it "details for event with limited guest access" do
      WebMock.stub(:get, /^https:\/\/graph\.microsoft\.com\/v1\.0\/users\/[^\/]*\/calendar\/events\/.*/)
        .to_return(body: File.read("./spec/fixtures/events/o365/create.json"))

      # Create event

      req_body = EventsHelper.create_event_input

      created_event = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/", headers: Mock::Headers.office365_guest, body: req_body, &.create)[1].as_h

      created_event_id = created_event["id"].to_s

      WebMock.stub(:get, /^https:\/\/graph\.microsoft\.com\/v1\.0\/users\/[^\/]*\/calendar\/calendarView\?.*/)
        .to_return(EventsHelper.event_query_response(created_event_id))

      # Fetch guest event details
      status_code, event = Context(Events, JSON::Any).response("GET", "#{EVENTS_BASE}/#{created_event["id"]}", route_params: {"id" => created_event_id}, headers: Mock::Headers.office365_guest(created_event_id, "sys-rJQQlR4Cn7"), &.show)

      status_code.should eq(200)
      event.as_h["event_start"].should eq(1598503500)
      event.as_h["event_end"].should eq(1598507160)
    end

    it "details for event with guest access and event is recurring instance" do
      WebMock.stub(:post, "#{ENV["PLACE_URI"]}/api/engine/v2/signal?channel=staff/event/changed")
        .to_return(body: "")
      WebMock.stub(:post, "#{ENV["PLACE_URI"]}/api/engine/v2/signal?channel=staff/guest/attending")
        .to_return(body: "")

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.com/calendar?")
        .to_return(body: File.read("./spec/fixtures/events/o365/show_recurring.json"))
      WebMock.stub(:post, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.onmicrosoft.com/calendar/events")
        .to_return(body: File.read("./spec/fixtures/events/o365/show_recurring.json"))

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.com/calendars")
        .to_return(body: File.read("./spec/fixtures/events/o365/show_recurring.json"))

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/events/event_instance_of_recurrence_id")
        .to_return(body: File.read("./spec/fixtures/events/o365/show_recurring.json"))

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/events/AAMkADE3YmQxMGQ2LTRmZDgtNDljYy1hNDg1LWM0NzFmMGI0ZTQ3YgBGAAAAAADFYQb3DJ_xSJHh14kbXHWhBwB08dwEuoS_QYSBDzuv558sAAAAAAENAAB08dwEuoS_QYSBDzuv558sAACGVOwUAAA=")
        .to_return(body: File.read("./spec/fixtures/events/o365/show_recurring.json"))

      # Create event which will create metadata with id that we'll use as seriesMasterId

      req_body = EventsHelper.create_recurring_event_input

      created_event = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/", headers: Mock::Headers.office365_guest, body: req_body.to_s, &.create)[1].as_h

      created_event_id = created_event["id"].to_s

      WebMock.stub(:get, /^https:\/\/graph\.microsoft\.com\/v1\.0\/users\/[^\/]*\/calendar\/calendarView\?.*/)
        .to_return(EventsHelper.event_query_response(created_event_id))

      # Fetch guest event details that is an instance of master event created above
      event_instance_id = "event_instance_of_recurrence_id"
      status_code, event = Context(Events, JSON::Any).response("GET", "#{EVENTS_BASE}/#{event_instance_id}", route_params: {"id" => event_instance_id}, headers: Mock::Headers.office365_guest(event_instance_id, "sys-rJQQlR4Cn7"), &.show)

      status_code.should eq(200)
      master_event_id = created_event["id"].to_s

      # Metadata should not exist for this event
      EventMetadata.query.find({event_id: event_instance_id}).should eq(nil)
      event.as_h["event_start"].should eq(1598503500)
      event.as_h["event_end"].should eq(1598507160)
      # Should have extension data stored on master event
      evt_meta = EventMetadata.query.find! { event_id == created_event_id }
      evt_meta.recurring_master_id.should eq(master_event_id)
      event.as_h["extension_data"].should eq({"foo" => "bar"})
    end

    it "details for event with normal access" do
      WebMock.stub(:get, /^https:\/\/graph\.microsoft\.com\/v1\.0\/users\/[^\/]*\/calendar\/events\/?.*/)
        .to_return(body: File.read("./spec/fixtures/events/o365/create.json"))

      # Create event

      req_body = EventsHelper.create_event_input
      created_event = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/", headers: Mock::Headers.office365_guest, body: req_body, &.create)[1].as_h

      created_event_id = created_event["id"].to_s

      WebMock.stub(:get, /^https:\/\/graph\.microsoft\.com\/v1\.0\/users\/[^\/]*\/calendar\/calendarView\?.*/)
        .to_return(EventsHelper.event_query_response(created_event_id))

      # Show for calendar
      status_code, event = Context(Events, JSON::Any).response("GET", "#{EVENTS_BASE}/#{created_event_id}?calendar=dev@acaprojects.onmicrosoft.com", route_params: {"id" => created_event_id.to_s}, headers: Mock::Headers.office365_guest, &.show)

      status_code.should eq(200)
      event.as_h["event_start"].should eq(1598503500)
      event.as_h["event_end"].should eq(1598507160)

      # Show for room
      status_code, event = Context(Events, JSON::Any).response("GET", "#{EVENTS_BASE}/#{created_event_id}?system_id=sys-rJQQlR4Cn7", route_params: {"id" => created_event_id}, headers: Mock::Headers.office365_guest, &.show)
      status_code.should eq(200)
      event.as_h["event_start"].should eq(1598503500)
      event.as_h["event_end"].should eq(1598507160)
    end

    it "details for event that is an recurring event instance with normal access" do
      WebMock.stub(:post, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.onmicrosoft.com/calendar/events")
        .to_return(body: File.read("./spec/fixtures/events/o365/create.json"))

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/events/event_instance_of_recurrence_id")
        .to_return(body: File.read("./spec/fixtures/events/o365/show_recurring.json"))

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.onmicrosoft.com/calendar/events/event_instance_of_recurrence_id")
        .to_return(body: File.read("./spec/fixtures/events/o365/show_recurring.json"))

      # Create event which will create metadata with id that we'll use as seriesMasterId

      req_body = EventsHelper.create_event_input

      created_event = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/", headers: Mock::Headers.office365_guest, body: req_body, &.create)[1].as_h

      event_instance_id = "event_instance_of_recurrence_id"
      # Metadata should not exist for this event
      EventMetadata.query.find({event_id: event_instance_id}).should eq(nil)

      master_event_id = "AAMkADE3YmQxMGQ2LTRmZDgtNDljYy1hNDg1LWM0NzFmMGI0ZTQ3YgBGAAAAAADFYQb3DJ_xSJHh14kbXHWhBwB08dwEuoS_QYSBDzuv558sAAAAAAENAAB08dwEuoS_QYSBDzuv558sAACGVOwUAAA="

      created_event_id = created_event["id"].to_s

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev@acaprojects.onmicrosoft.com/calendar/calendarView?startDateTime=2020-08-30T14:00:00-00:00&endDateTime=2020-08-31T13:59:59-00:00&%24filter=iCalUId+eq+%27040000008200E00074C5B7101A82E008000000008CD0441F4E7FD60100000000000000001000000087A54520ECE5BD4AA552D826F3718E7F%27&$top=10000")
        .to_return(EventsHelper.event_query_response(created_event_id))

      WebMock.stub(:get, /^https:\/\/graph\.microsoft\.com\/v1\.0\/users\/[^\/]*\/calendar\/calendarView\?.*/)
        .to_return(EventsHelper.event_query_response(created_event_id))

      # Show event details for calendar params that is an instance of master event created above
      status_code, event = Context(Events, JSON::Any).response("GET", "#{EVENTS_BASE}/#{event_instance_id}?calendar=dev@acaprojects.onmicrosoft.com", route_params: {"id" => event_instance_id}, headers: Mock::Headers.office365_guest, &.show)
      status_code.should eq(200)
      event.as_h["event_start"].should eq(1598503500)
      event.as_h["event_end"].should eq(1598507160)

      evt_meta = EventMetadata.query.find! { event_id == created_event_id }
      evt_meta.recurring_master_id.should eq(master_event_id)
      # Should not have any exetension information
      event.as_h["extension_data"]?.should eq(nil)

      # Show event details for room/system params that is an instance of master event created above
      status_code, event = Context(Events, JSON::Any).response("GET", "#{EVENTS_BASE}/#{event_instance_id}?system_id=sys-rJQQlR4Cn7", route_params: {"id" => event_instance_id}, headers: Mock::Headers.office365_guest, &.show)

      status_code.should eq(200)
      event.as_h["event_start"].should eq(1598503500)
      event.as_h["event_end"].should eq(1598507160)

      # Should have extension data stored on master event
      event.as_h["extension_data"].should eq({"foo" => "bar"})
    end
  end

  it "#destroy the event for system" do
    WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.com/calendars")
      .to_return(body: File.read("./spec/fixtures/calendars/o365/show.json"))
    WebMock.stub(:post, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.onmicrosoft.com/calendar/events")
      .to_return(body: File.read("./spec/fixtures/events/o365/create.json"))

    WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/events/AAMkADE3YmQxMGQ2LTRmZDgtNDljYy1hNDg1LWM0NzFmMGI0ZTQ3YgBGAAAAAADFYQb3DJ_xSJHh14kbXHWhBwB08dwEuoS_QYSBDzuv558sAAAAAAENAAB08dwEuoS_QYSBDzuv558sAACGVOwUAAA=")
      .to_return(body: File.read("./spec/fixtures/events/o365/generic_event.json"))

    WebMock.stub(:delete, /^https:\/\/graph\.microsoft\.com\/v1\.0\/users\/[^\/]*\/calendar\/events\/?.*/)
      .to_return(body: "")

    WebMock.stub(:get, /^https:\/\/graph\.microsoft\.com\/v1\.0\/users\/[^\/]*\/calendar\/events\/?.*/)
      .to_return(body: File.read("./spec/fixtures/events/o365/generic_event.json"))

    # Create event

    req_body = EventsHelper.create_event_input
    created_event = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/", headers: Mock::Headers.office365_guest, body: req_body, &.create)[1].as_h

    created_event_id = created_event["id"].to_s

    WebMock.stub(:get, /^https:\/\/graph\.microsoft\.com\/v1\.0\/users\/[^\/]*\/calendar\/calendarView\?.*/)
      .to_return(EventsHelper.event_query_response(created_event_id))

    # Should have created event meta
    EventMetadata.query.find { event_id == created_event["id"] }.should_not eq(nil)

    WebMock.stub(:get, "http://toby.dev.place.tech/api/engine/v2/metadata/sys-rJQQlR4Cn7?name=permissions")
      .to_return(body: %({"permissions":
      {"name":"permissions",
        "parent_id": "22",
        "description" : "grant access",
      "details":{"admin": ["admin"]}}}))

    WebMock.stub(:get, "http://toby.dev.place.tech/api/engine/v2/metadata/zone-rGhCRp_aUD?name=permissions")
      .to_return(body: %({"permissions":
         {"name":"permissions",
           "parent_id": "22",
           "description" : "grant access",
         "details":{"admin": ["admin"]}}}))

    # delete
    Events.context("DELETE", "#{EVENTS_BASE}/#{created_event["id"]}?system_id=sys-rJQQlR4Cn7", route_params: {"id" => created_event["id"].to_s}, headers: Mock::Headers.office365_guest, &.destroy)

    # Should have deleted event meta
    EventMetadata.query.find { event_id == created_event["id"] }.should eq(nil)
  end

  it "#approve marks room as accepted" do
    EventsHelper.stub_create_endpoints

    WebMock.stub(:patch, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/events/")
      .to_return(GuestsHelper.mock_event_query_json)

    WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/events/AAMkADE3YmQxMGQ2LTRmZDgtNDljYy1hNDg1LWM0NzFmMGI0ZTQ3YgBGAAAAAADFYQb3DJ_xSJHh14kbXHWhBwB08dwEuoS_QYSBDzuv558sAAAAAAENAAB08dwEuoS_QYSBDzuv558sAACGVOwUAAA%3D")
      .to_return(body: File.read("./spec/fixtures/events/o365/create.json"))

    WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.com/calendars")
      .to_return(body: File.read("./spec/fixtures/calendars/o365/show.json"))

    # Create event

    req_body = EventsHelper.create_event_input

    created_event = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/", headers: Mock::Headers.office365_guest, body: req_body, &.create)[1].as_h

    created_event_id = created_event["id"].to_s
    WebMock.stub(:get, /^https:\/\/graph\.microsoft\.com\/v1\.0\/users\/[^\/]*\/calendar\/calendarView\?.*/)
      .to_return(EventsHelper.event_query_response(created_event_id))

    WebMock.stub(:patch, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/events/AAMkADE3YmQxMGQ2LTRmZDgtNDljYy1hNDg1LWM0NzFmMGI0ZTQ3YgBGAAAAAADFYQb3DJ_xSJHh14kbXHWhBwB08dwEuoS_QYSBDzuv558sAAAAAAENAAB08dwEuoS_QYSBDzuv558sAACGVOwUAAA%3D").to_return(body: File.read("./spec/fixtures/events/o365/update_with_accepted.json"))

    # approve
    accepted_event = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/#{created_event["id"]}/approve?system_id=sys-rJQQlR4Cn7", route_params: {"id" => created_event["id"].to_s}, headers: Mock::Headers.office365_guest, &.approve)[1].as_h

    room_attendee = accepted_event["attendees"].as_a.find { |a| a["email"] == "rmaudpswissalps@booking.demo.acaengine.com" }
    room_attendee.not_nil!["response_status"].as_s.should eq("accepted")
  end

  it "#reject marks room as declined" do
    EventsHelper.stub_create_endpoints

    WebMock.stub(:patch, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/events/")
      .to_return(GuestsHelper.mock_event_query_json)

    WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/events/AAMkADE3YmQxMGQ2LTRmZDgtNDljYy1hNDg1LWM0NzFmMGI0ZTQ3YgBGAAAAAADFYQb3DJ_xSJHh14kbXHWhBwB08dwEuoS_QYSBDzuv558sAAAAAAENAAB08dwEuoS_QYSBDzuv558sAACGVOwUAAA%3D")
      .to_return(body: File.read("./spec/fixtures/events/o365/create.json"))

    WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev%40acaprojects.com/calendars")
      .to_return(body: File.read("./spec/fixtures/calendars/o365/show.json"))

    WebMock.stub(:patch, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/events/AAMkADE3YmQxMGQ2LTRmZDgtNDljYy1hNDg1LWM0NzFmMGI0ZTQ3YgBGAAAAAADFYQb3DJ_xSJHh14kbXHWhBwB08dwEuoS_QYSBDzuv558sAAAAAAENAAB08dwEuoS_QYSBDzuv558sAACGVOwUAAA%3D").to_return(body: File.read("./spec/fixtures/events/o365/update_with_declined.json"))

    # Create event
    req_body = EventsHelper.create_event_input
    created_event = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/", headers: Mock::Headers.office365_guest, body: req_body, &.create)[1].as_h

    created_event_id = created_event["id"].to_s
    WebMock.stub(:get, /^https:\/\/graph\.microsoft\.com\/v1\.0\/users\/[^\/]*\/calendar\/calendarView\?.*/)
      .to_return(EventsHelper.event_query_response(created_event_id))

    # reject
    declined_event = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/#{created_event["id"]}/reject?system_id=sys-rJQQlR4Cn7", route_params: {"id" => created_event["id"].to_s}, headers: Mock::Headers.office365_guest, &.approve)[1].as_h
    room_attendee = declined_event["attendees"].as_a.find { |a| a["email"] == "rmaudpswissalps@booking.demo.acaengine.com" }
    room_attendee.not_nil!["response_status"].as_s.should eq("declined")
  end

  describe "#guest_list" do
    it "lists guests for an event & guest_checkin checks them in" do
      EventsHelper.stub_create_endpoints

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/events/AAMkADE3YmQxMGQ2LTRmZDgtNDljYy1hNDg1LWM0NzFmMGI0ZTQ3YgBGAAAAAADFYQb3DJ_xSJHh14kbXHWhBwB08dwEuoS_QYSBDzuv558sAAAAAAENAAB08dwEuoS_QYSBDzuv558sAACGVOwUAAA%3D")
        .to_return(body: File.read("./spec/fixtures/events/o365/create.json"))

      WebMock.stub(:post, "#{ENV["PLACE_URI"]}/api/engine/v2/signal?channel=staff/guest/checkin")
        .to_return(body: "")

      # Create event

      req_body = EventsHelper.create_event_input
      created_event = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/", headers: Mock::Headers.office365_guest, body: req_body, &.create)[1].as_h

      created_event_id = created_event["id"].to_s

      WebMock.stub(:get, /^https:\/\/graph\.microsoft\.com\/v1\.0\/users\/[^\/]*\/calendar\/calendarView\?.*/)
        .to_return(EventsHelper.event_query_response(created_event_id))

      # guest_list
      Context(Events, JSON::Any).response("GET", "#{EVENTS_BASE}/#{created_event["id"]}/guests?system_id=sys-rJQQlR4Cn7", route_params: {"id" => created_event["id"].to_s}, headers: Mock::Headers.office365_guest, &.guest_list)[1].as_a
      # guests.should eq(EventsHelper.guests_list_output)
      # guests.to_s.includes?(%("id" => "sys-rJQQlR4Cn7"))

      evt_meta = EventMetadata.query.find! { event_id == created_event["id"] }
      guests = evt_meta.attendees.map(&.guest)
      guests.map(&.name).should eq(["Amit", "John", "dev@acaprojects.onmicrosoft.com"])

      # guest_checkin via system
      checked_in_guest = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/#{created_event["id"]}/guests/jon@example.com/checkin?system_id=sys-rJQQlR4Cn7", route_params: {"id" => created_event["id"].to_s, "guest_id" => "jon@example.com"}, headers: Mock::Headers.office365_guest, &.guest_checkin)[1].as_h
      checked_in_guest["checked_in"].should eq(true)

      # guest_checkin via system state = false
      checked_in_guest = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/#{created_event["id"]}/guests/jon@example.com/checkin?state=false&system_id=sys-rJQQlR4Cn7", route_params: {"id" => created_event["id"].to_s, "guest_id" => "jon@example.com"}, headers: Mock::Headers.office365_guest, &.guest_checkin)[1].as_h
      checked_in_guest["checked_in"].should eq(false)

      # guest_checkin via guest_token
      checked_in_guest = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/#{created_event["id"]}/guests/jon@example.com/checkin&system_id=sys-rJQQlR4Cn7", route_params: {"id" => created_event["id"].to_s, "guest_id" => "jon@example.com"}, headers: Mock::Headers.office365_guest(created_event["id"].to_s, "sys-rJQQlR4Cn7"), &.guest_checkin)[1].as_h

      checked_in_guest["checked_in"].should eq(true)

      # guest_checkin via guest_token state = false
      checked_in_guest = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/#{created_event["id"]}/guests/jon@example.com/checkin?state=false&system_id=sys-rJQQlR4Cn7", route_params: {"id" => created_event["id"].to_s, "guest_id" => "jon@example.com"}, headers: Mock::Headers.office365_guest(created_event["id"].to_s, "sys-rJQQlR4Cn7"), &.guest_checkin)[1].as_h
      checked_in_guest["checked_in"].should eq(false)
    end

    pending "lists guests for an event that is an recurring instance & guest_checkin checks them in" do
      EventsHelper.stub_create_endpoints

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev@acaprojects.com/calendar/events/AAMkADE3YmQxMGQ2LTRmZDgtNDljYy1hNDg1LWM0NzFmMGI0ZTQ3YgBGAAAAAADFYQb3DJ_xSJHh14kbXHWhBwB08dwEuoS_QYSBDzuv558sAAAAAAENAAB08dwEuoS_QYSBDzuv558sAACGVOwUAAA=")
        .to_return(body: File.read("./spec/fixtures/events/o365/show_recurring.json"))

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/dev@acaprojects.com/calendar/events/event_instance_of_recurrence_id")
        .to_return(body: File.read("./spec/fixtures/events/o365/show_recurring.json"))

      WebMock.stub(:post, "#{ENV["PLACE_URI"]}/api/engine/v2/signal?channel=staff/guest/checkin")
        .to_return(body: "")

      WebMock.stub(:get, "https://graph.microsoft.com/v1.0/users/room1%40example.com/calendar/events/event_instance_of_recurrence_id")
        .to_return(body: File.read("./spec/fixtures/events/o365/show_instance_recurring.json"))

      # Create event which will create metadata with id that we'll use as seriesMasterId

      req_body = EventsHelper.create_event_input

      created_event = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/", headers: Mock::Headers.office365_guest, body: req_body.to_s, &.create)[1].as_h

      created_event_id = created_event["id"].to_s

      WebMock.stub(:get, /^https:\/\/graph\.microsoft\.com\/v1\.0\/users\/[^\/]*\/calendar\/calendarView\?.*/)
        .to_return(EventsHelper.event_query_response(created_event_id))

      event_instance_id = "event_instance_of_recurrence_id"
      # Metadata should not exist for this event
      EventMetadata.query.find({event_id: event_instance_id}).should eq(nil)

      # guest_list
      guests = Context(Events, JSON::Any).response("GET", "#{EVENTS_BASE}/#{event_instance_id}/guests?system_id=sys-rJQQlR4Cn7", route_params: {"id" => event_instance_id}, headers: Mock::Headers.office365_guest, &.guest_list)[1].as_a
      guests.to_s.includes?(%("email" => "amit@redant.com.au"))

      # guest_checkin via system
      checked_in_guest = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/#{event_instance_id}/guests/jon@example.com/checkin?system_id=sys-rJQQlR4Cn7", route_params: {"id" => event_instance_id, "guest_id" => "jon@example.com"}, headers: Mock::Headers.office365_guest, &.guest_checkin)[1].as_h
      checked_in_guest["checked_in"].should eq(true)

      # We should have created meta by migrating from master event meta
      meta_after_checkin = EventMetadata.query.find!({event_id: event_instance_id})
      master_event_id = "AAMkADE3YmQxMGQ2LTRmZDgtNDljYy1hNDg1LWM0NzFmMGI0ZTQ3YgBGAAAAAADFYQb3DJ_xSJHh14kbXHWhBwB08dwEuoS_QYSBDzuv558sAAAAAAENAAB08dwEuoS_QYSBDzuv558sAACGVOwUAAA="
      master_meta = EventMetadata.query.find!({event_id: master_event_id})
      meta_after_checkin.ext_data.should eq(master_meta.ext_data)
      meta_after_checkin.attendees.count.should eq(master_meta.attendees.count)

      # guest_checkin via system state = false
      checked_in_guest = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/#{event_instance_id}/guests/jon@example.com/checkin?state=false&system_id=sys-rJQQlR4Cn7", route_params: {"id" => event_instance_id, "guest_id" => "jon@example.com"}, headers: Mock::Headers.office365_guest, &.guest_checkin)[1].as_h
      checked_in_guest["checked_in"].should eq(false)

      # guest_checkin via guest_token
      checked_in_guest = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/#{event_instance_id}/guests/jon@example.com/checkin", route_params: {"id" => event_instance_id, "guest_id" => "jon@example.com"}, headers: Mock::Headers.office365_guest(event_instance_id, "sys-rJQQlR4Cn7"), &.guest_checkin)[1].as_h
      checked_in_guest["checked_in"].should eq(true)

      # guest_checkin via guest_token state = false
      checked_in_guest = Context(Events, JSON::Any).response("POST", "#{EVENTS_BASE}/#{event_instance_id}/guests/jon@example.com/checkin?state=false", route_params: {"id" => event_instance_id, "guest_id" => "jon@example.com"}, headers: Mock::Headers.office365_guest(event_instance_id, "sys-rJQQlR4Cn7"), &.guest_checkin)[1].as_h
      checked_in_guest["checked_in"].should eq(false)
    end
  end
end
