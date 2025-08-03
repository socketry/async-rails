# HTTP Streaming with Falcon and Rails

This guide explains how to implement HTTP response streaming with Falcon and Rails.

## What is HTTP Streaming?

HTTP streaming allows you to send data to the client progressively over a single HTTP connection using chunked transfer encoding. Unlike Server-Sent Events, HTTP streaming gives you complete control over the data format and doesn't require specific protocols.

**When to use HTTP streaming:**
- Progress indicators for long-running tasks.
- Live log streaming.
- Large file generation (CSV, JSON exports).
- Real-time data feeds with custom formats.
- Streaming API responses.

**When NOT to use HTTP streaming:**
- When you need persistent connections (use SSE or WebSockets instead).
- For simple real-time updates (SSE is easier).

## Basic Implementation

### Server-Side: Rails Controller

Create a controller action that streams data using `Rack::Response`:

```ruby
class StreamingController < ApplicationController
	def index
		# Render the page with streaming JavaScript
	end
	
	def stream
		body = proc do |stream|
			10.downto(1) do |i|
				stream.write "#{i} bottles of beer on the wall\n"
				sleep 1
				stream.write "#{i} bottles of beer\n"
				sleep 1
				stream.write "Take one down, pass it around\n"
				sleep 1
				stream.write "#{i - 1} bottles of beer on the wall\n"
				sleep 1
			end
		end

		self.response = Rack::Response[200, {"content-type" => "text/plain"}, body]
	end
end
```

**Key Points:**
- Use `Rack::Response` with a callable body for streaming.
- `content-type` can be `text/plain`, `application/json`, or any format you need.
- Each `stream.write` sends data immediately to the client.
- No special formatting required (unlike SSE's `data: ` prefix).

### Client-Side: Fetch API with ReadableStream

Create an HTML page that consumes the HTTP stream:

```html
<button id="startStream" class="button">🚀 Start Streaming Demo</button>
<button id="stopStream" class="button" disabled>⏹️ Stop Stream</button>
<div id="streamOutput" class="terminal"></div>

<script>
let streamController = null;
let streamReader = null;

document.getElementById('startStream').addEventListener('click', function() {
	const output = document.getElementById('streamOutput');
	const startBtn = document.getElementById('startStream');
	const stopBtn = document.getElementById('stopStream');
	
	// Clear previous output
	output.innerHTML = '<div class="terminal-status">🔄 Starting stream...</div>';
	
	// Create abort controller for stopping the stream
	streamController = new AbortController();
	
	// Start streaming
	fetch('/streaming/stream', { signal: streamController.signal })
		.then(response => {
			if (!response.ok) throw new Error('Network response was not ok');
			
			streamReader = response.body.getReader();
			const decoder = new TextDecoder();
			
			function readStream() {
				streamReader.read().then(({ done, value }) => {
					if (done) {
						output.innerHTML += '<div class="terminal-complete">✅ Stream completed!</div>';
						startBtn.disabled = false;
						stopBtn.disabled = true;
						return;
					}
					
					const text = decoder.decode(value, { stream: true });
					const lines = text.split('\n');
					
					lines.forEach(line => {
						if (line.trim()) {
							const lineDiv = document.createElement('div');
							lineDiv.className = 'terminal-line';
							lineDiv.textContent = line;
							output.appendChild(lineDiv);
							output.scrollTop = output.scrollHeight;
						}
					});
					
					readStream();
				});
			}
			
			readStream();
		});
});

document.getElementById('stopStream').addEventListener('click', function() {
	if (streamController) {
		streamController.abort();
	}
});
</script>
```

**Key Points:**
- Use `fetch()` with `AbortController` for cancellation support.
- Get a `ReadableStream` reader with `response.body.getReader()`.
- Use `TextDecoder` to convert binary data to text.
- Handle the stream chunks manually in the `readStream()` function.

### Routing Configuration

Add routes to your `config/routes.rb`:

```ruby
Rails.application.routes.draw do
	# Streaming Example:
	get 'streaming/index'  # Page with streaming JavaScript
	get 'streaming/stream' # HTTP streaming endpoint
end
```

## Advanced Patterns

### Streaming NDJSON Data

Server-side:
```ruby
def stream
	body = proc do |stream|
		User.find_each(batch_size: 100) do |user|
			# Each line is a complete JSON object
			stream.write "#{user.to_json}\n"
		end
	end
	
	self.response = Rack::Response[200, {"content-type" => "application/x-ndjson"}, body]
end
```

Client-side:
```javascript
fetch('/streaming/users')
	.then(response => {
		const reader = response.body.getReader();
		const decoder = new TextDecoder();
		let buffer = '';
		
		function readStream() {
			reader.read().then(({ done, value }) => {
				if (done) {
					console.log('All users loaded');
					return;
				}
				
				buffer += decoder.decode(value, { stream: true });
				const lines = buffer.split('\n');
				buffer = lines.pop(); // Keep incomplete line in buffer
				
				lines.forEach(line => {
					if (line.trim()) {
						try {
							const user = JSON.parse(line);
							console.log('User loaded:', user);
							displayUser(user);
						} catch (e) {
							console.error('Invalid JSON:', line);
						}
					}
				});
				
				readStream();
			});
		}
		
		readStream();
	});
```
