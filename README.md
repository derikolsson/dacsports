# DAC Sports Network

Live streaming platform for the Dallas Athletic Conference.

## Requirements

- Ruby 3.4.7
- Rails 8.0
- PostgreSQL 15+
- Redis 7+

## Installation

```bash
# Clone repository
git clone git@github.com:username/dacsports.git
cd dacsports

# Install dependencies
bundle install

# Setup database
rails db:create db:migrate

# Configure credentials
EDITOR="nano" rails credentials:edit
# Add: internal_auth, fathom_site_id

# Run development server
bin/dev
```

## Environment Variables

- `REDIS_URL` - Redis connection URL (default: `redis://localhost:6379/0`)
- `DATABASE_URL` - PostgreSQL connection URL (production)

## Development

```bash
# Start all services (web, CSS watch, Sidekiq)
bin/dev

# Or start individually
rails server
bundle exec sidekiq
bin/rails dartsass:watch
```

## Testing

```bash
bundle exec rspec
```

## Configuration

### Rails Credentials

Edit credentials with:
```bash
EDITOR="nano" rails credentials:edit
```

Add the following:
```yaml
internal_auth:
  username: admin
  password: your_secure_password_here

fathom_site_id: YOUR_FATHOM_SITE_ID
```

## Admin Interface

Access the admin interface at `/internal` using HTTP Basic Auth credentials configured in Rails credentials.

Features:
- Event management (CRUD)
- State transition controls
- Analytics dashboard
- Sidekiq job monitoring

## Architecture

### Event States

Events follow a 5-state machine:
- `upcoming` → `live` → `ended` (no replay)
- `upcoming` → `live` → `replay_pending` → `replay_available` (with replay)

Note: For analytics, EventVisit tracks `event_status` as either `live` or `vod`

### Anonymous Session Tracking

- Sessions tracked by UUID stored in localStorage
- No user authentication required
- Browser/OS/device detection for analytics
- Active viewers tracked by last_seen_at < 3 minutes ago

### Background Jobs

- **StartEventsJob** - Auto-starts events at scheduled time (runs every minute)
- **SessionKeepaliveJob** - Updates session activity
- **EventVisitJob** - Tracks event views asynchronously

## License

All rights reserved.
