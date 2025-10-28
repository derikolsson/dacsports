class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :request_id, :ip_address
end
