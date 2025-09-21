# Getting Started

This guide explains how to get started using Falcon to host your Rails application.

## Installation

In your existing Rails application:

```bash
bundle add falcon-rails
```

You might also like to remove your existing web server, such as Puma:

```bash
bundle remove puma
```

## Development Usage

Falcon is an Async-compatible web server that can be used with Rails. It provides high concurrency and low latency for web applications. It defaults to TLS (HTTPS) to enable HTTP/2 features and modern web standards.

To use Falcon in development, first install the development TLS certificates:

```bash
bundle exec bake localhost:install
```

Then, you can start your Rails application with Falcon:

```bash
bundle exec falcon serve
```

You can access your application at `https://localhost:9292`.

### HTTP Development Server

If you prefer to run without HTTPS in development, you can bind to an explicit HTTP endpoint:

```bash
bundle exec falcon serve -b http://localhost:3000
```

> [!NOTE]
> Unlike `bundle exec falcon serve` which defaults to HTTPS, `bin/rails server` will default to HTTP when using Falcon as the Rails server.

## Production Deployment

For production deployments, use `falcon host` with a configuration file instead of `falcon serve`.

### Setting up `falcon.rb`

Create a `falcon.rb` file in the root of your Rails application. This file configures the Falcon server for production:

```ruby
#!/usr/bin/env -S falcon-host
# frozen_string_literal: true

require "falcon/environment/rack"

hostname = File.basename(__dir__)

service hostname do
	include Falcon::Environment::Rack
	
	# This file will be loaded in the main process before forking.
	preload "preload.rb"
	
	# Default to port 3000 unless otherwise specified.
	port {ENV.fetch("PORT", 3000).to_i}
	
	# Default to HTTP/1.1 for compatibility with proxies:
	endpoint do
		Async::HTTP::Endpoint
			.parse("http://0.0.0.0:#{port}")
			.with(protocol: Async::HTTP::Protocol::HTTP11)
	end
end
```

Make the file executable:

```bash
chmod +x falcon.rb
```

### Setting up preload.rb

Create a `preload.rb` file in your application root to preload Rails before forking workers:

```ruby
# frozen_string_literal: true

require_relative "config/environment"
```

Preloading significantly reduces memory usage by loading your Rails application into memory before forking worker processes.

### Running the Production Server

To run the production server:

```bash
bundle exec ./falcon.rb
```

Or use the falcon host command directly:

```bash
bundle exec falcon host
```

### Worker Processes

To configure multiple worker processes for better performance:

```ruby
# In your falcon.rb
service hostname do
	include Falcon::Environment::Rack
	
	# Set the number of worker processes
	count ENV.fetch("WEB_CONCURRENCY", 2).to_i
	
	# ... rest of configuration
end
```

## Troubleshooting

### Common Issues

**Port already in use**: If you get a "port already in use" error, either stop the other process or change the port:

```bash
bundle exec falcon serve -b http://localhost:3001
```

**Certificate warnings in development**: Install the development certificates:

```bash
bundle exec bake localhost:install
```

**Rails not loading**: Ensure your `preload.rb` file correctly requires your Rails environment.

## Next Steps

Now that you have Falcon running with Rails, explore these integration guides:

- **[Job Processing](../job-processing/)** - Implement background job processing with `async-job`
- **[HTTP Streaming](../http-streaming/)** - Stream data progressively to clients
- **[Server-Sent Events](../server-sent-events/)** - Real-time updates using SSE
- **[WebSockets](../websockets/)** - Full-duplex real-time communication
- **[Real-Time Views](../real-time-views/)** - Build interactive interfaces with `Live::View`

### Example Application

Many of these integrations are demonstrated in the example application: https://github.com/socketry/falcon-rails-examples
