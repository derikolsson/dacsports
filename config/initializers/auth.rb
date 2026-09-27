# Staff sign in on one host (config.x.auth.host, set per environment) because passkeys are bound to it.
Rails.configuration.x.auth.origin = Rails.configuration.action_mailer.default_url_options.then do |url|
  scheme = url[:protocol] || "http"
  [ "#{scheme}://#{url.fetch(:host)}", url[:port] ].compact.join(":")
end

WebAuthn.configure do |config|
  config.rp_name = "DAC Sports Network"
  config.rp_id = Rails.configuration.x.auth.host
  config.allowed_origins = [ Rails.configuration.x.auth.origin ]
end
