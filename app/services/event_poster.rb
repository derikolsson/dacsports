# Stores event poster images in S3 and builds the URLs players load them from.
#
# Active Storage is off in this app, so this talks to S3 directly. Each upload gets a
# fresh random key: the URL changes whenever the image does, so the object can be
# cached forever and a slug rename never orphans it. Objects are not ACL'd — public
# reads come from CloudFront (or a bucket policy, if served straight from S3).
#
# Posters share the general dacsports bucket, served through CloudFront, so they keep
# to their own prefix. Credentials:
#   cdn:
#     bucket: dacsports
#     region: us-east-1
#     access_key_id: ...       # optional; falls back to the SDK's credential chain
#     secret_access_key: ...
#     host: https://cdn.dacsports.net   # optional; defaults to the bucket's S3 URL
class EventPoster
  CONTENT_TYPES = {
    "image/jpeg" => ".jpg",
    "image/png" => ".png",
    "image/webp" => ".webp"
  }.freeze
  # Low on purpose: posters load on every embed and in every link preview, so they
  # should be exported small (1920×1080 JPEG at ~80% is a few hundred KB), not resized
  # here. Anything over this is an unoptimized export.
  MAX_BYTES = 1.megabyte
  PREFIX = "posters/events/".freeze

  class Error < StandardError; end

  def self.upload(io, content_type:)
    new.upload(io, content_type:)
  end

  def self.delete(key)
    new.delete(key)
  end

  def self.url(key)
    return if key.blank?

    "#{host}/#{key}"
  end

  def self.config
    Rails.application.credentials.cdn || {}
  end

  def self.host
    config[:host].presence&.chomp("/") || "https://#{config[:bucket]}.s3.#{config[:region]}.amazonaws.com"
  end

  # Returns the new object's key.
  def upload(io, content_type:)
    key = "#{PREFIX}#{SecureRandom.uuid}#{CONTENT_TYPES.fetch(content_type)}"
    client.put_object(
      bucket: bucket, key: key, body: io,
      content_type: content_type,
      cache_control: "public, max-age=31536000, immutable"
    )
    key
  rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
    raise Error, e.message
  end

  def delete(key)
    client.delete_object(bucket: bucket, key: key)
  rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
    raise Error, e.message
  end

  private

  def bucket
    self.class.config.fetch(:bucket) { raise Error, "No CDN bucket configured" }
  end

  def client
    config = self.class.config
    options = { region: config[:region] }
    # Without keys the SDK falls back to its own chain (env vars, instance role).
    if config[:access_key_id].present?
      options[:credentials] = Aws::Credentials.new(config[:access_key_id], config[:secret_access_key])
    end
    Aws::S3::Client.new(**options)
  end
end
