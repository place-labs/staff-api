class Staff < Application
  base "/api/staff/v1/people"

  # lists users in the organisation directory
  @[AC::Route::GET("/")]
  def index(
    @[AC::Param::Info(name: "q", description: "optional search query", example: "steve")]
    query : String? = nil,
    @[AC::Param::Info(name: "filter", description: "optional search filter using Azure AD filter syntax", example: "startsWith(givenName,'ben') or startsWith(surname,'ben')")]
    filter : String? = nil
  ) : Array(PlaceCalendar::User)
    if filter
      client.list_users(filter: filter)
    else
      client.list_users(query)
    end
  end

  # returns user details for the id provided
  @[AC::Route::GET("/:id")]
  def show(
    @[AC::Param::Info(description: "a user id OR user email address", example: "user@org.com")]
    id : String
  ) : PlaceCalendar::User
    user = client.get_user_by_email(id)
    raise Error::NotFound.new("user #{id} not found") unless user
    user
  end

  # returns the list of groups the user is a member
  @[AC::Route::GET("/:id/groups")]
  def groups(id : String) : Array(PlaceCalendar::Group)
    client.get_groups(id)
  end

  # returns the users manager
  @[AC::Route::GET("/:id/manager")]
  def manager(id : String) : PlaceCalendar::User
    case client.client_id
    when :office365
      client.calendar.as(PlaceCalendar::Office365).client.get_user_manager(id).to_place_calendar
    else
      raise Error::NotImplemented.new("manager query is not available for #{client.client_id}")
    end
  end

  # returns the list of public calendars
  @[AC::Route::GET("/:id/calendars")]
  def calendars(id : String) : Array(PlaceCalendar::Calendar)
    client.list_calendars(id)
  end
end
