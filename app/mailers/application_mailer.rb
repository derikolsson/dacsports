class ApplicationMailer < ActionMailer::Base
  default from: -> { Rails.application.credentials.mailer_from || "DAC Sports Network <notifications@mail.dacsports.net>" }
  layout "mailer"
end
