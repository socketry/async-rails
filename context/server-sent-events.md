# Server-Sent Events

This guide explains how to implement Server-Sent Events with Falcon and Rails.

## What are Server-Sent Events?

Server-Sent Events (SSE) provide a way to push real-time updates from the server to the client over a single HTTP connection. Unlike WebSockets, SSE is unidirectional (server-to-client only) and uses the standard HTTP protocol.

**When to use SSE:**
- Live dashboards and monitoring systems.
- Real-time notifications.
- Progress indicators for long-running tasks.
- Live feeds (news, social media updates).
- Database change notifications.

**When NOT to use SSE:**
- When you need bidirectional communication (use WebSockets instead).
- When you need binary data transmission.

## Basic Implementation

### Server-Side: Rails Controller

Create a controller action that streams events using `Rack::Response`:

```ruby
class SseController < ApplicationController
	def index
		# Render the page with EventSource JavaScript
	end
	
	EVENT_STREAM_HEADERS = {
		"content-type" => "text/event-stream",
		"cache-control" => "no-cache",
		"connection" => "keep-alive"
	}
	
	def events
		body = proc do |stream|
			while true
				# Send timestamped data:
				stream.write("data: #{Time.now}\n\n")
				sleep 1
			end
		end
		
		self.response = Rack::Response[200, EVENT_STREAM_HEADERS.dup, body]
	end
end
```

**Key Points:**
- `content-type: text/event-stream` is required for SSE.
- Each message must end with `\n\n` (two newlines).
- The `data: ` prefix is required for the message content.
- Use a callable body for streaming responses.

### Client-Side: JavaScript EventSource

Create an HTML page that consumes the SSE stream:

```html
<div id="status" class="status warning">🔄 Connecting to event stream...</div>
<div id="history" class="terminal"></div>

<script>
var eventSource = new EventSource("events");
var messageCount = 0;

eventSource.addEventListener("open", function(event) {
	document.getElementById("status").innerHTML = "✅ Connected to event stream";
	document.getElementById("status").className = "status success";
});

eventSource.addEventListener("message", function(event) {
	messageCount++;
	var container = document.createElement("div");
	container.className = "terminal-line";
	container.innerHTML = `<span class="event-count">#${messageCount}</span> <span class="event-data">${event.data}</span>`;
	
	var history = document.querySelector("#history");
	history.appendChild(container);
	history.scrollTop = history.scrollHeight;
	
	// Keep only last 20 messages to prevent memory issues
	if (history.children.length > 20) {
		history.removeChild(history.firstChild);
	}
});

eventSource.addEventListener("error", function(event) {
	document.getElementById("status").innerHTML = "❌ Connection error - attempting to reconnect...";
	document.getElementById("status").className = "status error";
});
</script>
```

**Key Points:**
- `EventSource` automatically handles connection and reconnection.
- Listen for `open`, `message`, and `error` events.
- `event.data` contains the message content.
- Implement UI feedback for connection status.

### Routing Configuration

Add routes to your `config/routes.rb`:

```ruby
Rails.application.routes.draw do
	# SSE Example:
	get "sse/index"    # Page with EventSource JavaScript
	get "sse/events"   # SSE endpoint
end
```

## Advanced Patterns

### Sending Custom Event Types

By default, `event: message` is assumed for each record sent on the stream. However, it's possible to specify different kinds of events:

```ruby
def events
	body = proc do |stream|
		# Send different event types
		stream.write("event: user_joined\n")
		stream.write("data: #{user.to_json}\n\n")
		
		stream.write("event: message\n")
		stream.write("data: #{message.to_json}\n\n")
	end
	
	self.response = Rack::Response[200, EVENT_STREAM_HEADERS.dup, body]
end
```

On the client, you need to register multiple event listeners:

```javascript
eventSource.addEventListener("user_joined", function(event) {
	var user = JSON.parse(event.data);
	// Handle user joined event
});

eventSource.addEventListener("message", function(event) {
	var message = JSON.parse(event.data);
	// Handle message event
});
```
