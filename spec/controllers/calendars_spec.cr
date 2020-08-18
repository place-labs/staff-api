require "../spec_helper"

describe Calendars do

  it "should return a list of calendars" do
    # instantiate the controller
    response = IO::Memory.new
    calendars = Calendars.new(context("GET", "/api/staff/v1/calendars", HEADERS, response_io: response))

    calendars.index
  end

end
