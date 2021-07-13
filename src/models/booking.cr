class Booking
  include Clear::Model

  column id : Int64, primary: true, presence: false

  column user_id : String
  column user_email : String
  column user_name : String
  column asset_id : String
  column zones : Array(String)? # default in migration

  column booking_type : String
  column booking_start : Int64
  column booking_end : Int64
  column timezone : String?

  column title : String?
  column description : String?

  column checked_in : Bool? # default in migration
  column checked_in_at : Int64?
  column checked_out_at : Int64?

  column rejected : Bool? # default in migration
  column rejected_at : Int64?
  column approved : Bool? # default in migration
  column approved_at : Int64?
  column approver_id : String?
  column approver_email : String?
  column approver_name : String?

  column booked_by_id : String
  column booked_by_email : String
  column booked_by_name : String

  # if we want to record the system that performed the bookings
  # (kiosk, mobile, swipe etc)
  column booked_from : String?

  # used to hold information relating to the state of the booking process
  column process_state : String?
  column last_changed : Int64?
  column created : Int64?

  column ext_data : JSON::Any?

  belongs_to tenant : Tenant

  before :create, :set_created
  before :save, :downcase_emails

  def set_created
    self.last_changed = self.created = Time.utc.to_unix
  end

  def downcase_emails
    self.user_email = self.user_email.downcase
    self.booked_by_email = self.booked_by_email.downcase
    self.approver_email = self.approver_email.try(&.downcase) if self.approver_email_column.defined?
  end

  scope :by_tenant do |tenant_id|
    where(tenant_id: tenant_id)
  end

  scope :by_user_id do |user_id|
    user_id ? where(user_id: user_id) : self
  end

  scope :by_user_email do |user_email|
    user_email ? where(user_email: user_email) : self
  end

  scope :by_user_or_email do |user_id_value, user_email_value, include_booked_by|
    # TODO:: interpolate these values properly
    booked_by = include_booked_by ? %( OR "booked_by_id" = '#{user_id_value}') : ""
    user_id_value = user_id_value.try &.gsub(/[\'\"\)\(\\\/\$\?\;\:\<\>\.\+\=\*\&\^\#\!\`\%\}\{\[\]]/, "")
    user_email_value = user_email_value.try &.gsub(/[\'\"\)\(\\\/\$\?\;\:\<\>\=\*\&\^\!\`\%\}\{\[\]]/, "")

    if user_id_value && user_email_value
      where(%(("user_id" = '#{user_id_value}' OR "user_email" = '#{user_email_value}'#{booked_by})))
    elsif user_id_value
      # Not sure how to do OR's in clear
      where(%(("user_id" = '#{user_id_value}'#{booked_by})))
      # where(user_id: user_id_value)
    elsif user_email_value
      booked_by = include_booked_by ? %( OR "booked_by_email" = '#{user_email_value}') : ""
      where(%(("user_email" = '#{user_email_value}'#{booked_by})))
      # where(user_email: user_email_value)
    else
      self
    end
  end

  scope :booking_state do |state|
    state ? where(process_state: state) : self
  end

  scope :created_before do |time|
    time ? where { last_changed < time.not_nil!.to_i64 } : self
  end

  scope :created_after do |time|
    time ? where { last_changed > time.not_nil!.to_i64 } : self
  end

  scope :is_approved do |value|
    if value
      check = value == "true"
      where { approved == check }
    else
      self
    end
  end

  scope :is_rejected do |value|
    if value
      check = value == "true"
      where { rejected == check }
    else
      self
    end
  end

  scope :is_checked_in do |value|
    if value
      check = value == "true"
      where { checked_in == check }
    else
      self
    end
  end

  # Bookings have the zones in an array.
  #
  # In case of multiple zones as input,
  # we return all bookings that have
  # any of the input zones in their zones array
  scope :by_zones do |zones|
    return self if zones.empty?

    # https://www.postgresql.org/docs/9.1/arrays.html#ARRAYS-SEARCHING
    query = zones.join(" OR ") do |zone|
      zone = zone.gsub(/[\'\"\)\(\\\/\$\?\;\:\<\>\.\+\=\*\&\^\#\!\`\%\}\{\[\]]/, "")
      "( '#{zone}' = ANY (zones) )"
    end

    where("( #{query} )")
  end

  def as_json
    {
      id:              self.id,
      booking_type:    self.booking_type,
      booking_start:   self.booking_start,
      booking_end:     self.booking_end,
      timezone:        self.timezone,
      asset_id:        self.asset_id,
      user_id:         self.user_id,
      user_email:      self.user_email,
      user_name:       self.user_name,
      zones:           self.zones,
      process_state:   self.process_state,
      last_changed:    self.last_changed,
      approved:        self.approved,
      approved_at:     self.approved_at,
      rejected:        self.rejected,
      rejected_at:     self.rejected_at,
      approver_id:     self.approver_id,
      approver_name:   self.approver_name,
      approver_email:  self.approver_email,
      title:           self.title,
      checked_in:      self.checked_in,
      checked_in_at:   self.checked_in_at,
      checked_out_at:  self.checked_out_at,
      description:     self.description,
      extension_data:  self.ext_data,
      booked_by_email: self.booked_by_email,
      booked_by_name:  self.booked_by_name,
    }
  end
end
