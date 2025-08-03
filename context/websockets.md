# WebSocket Communication

This guide explains how to implement WebSocket connections with Falcon and Rails.

## What are WebSockets?

WebSockets provide full-duplex communication between client and server over a single persistent connection. Unlike HTTP streaming or SSE, WebSockets allow both client and server to send messages at any time.

**When to use WebSockets:**
- Real-time chat applications.
- Interactive games and collaborative tools.
- Live dashboards with user interaction.
- Real-time notifications with user actions.

**When NOT to use WebSockets:**
- Simple server-to-client updates (use SSE instead).
- Request/response patterns (use regular HTTP).

## Basic Implementation

### Server-Side: Rails Controller

Create a controller that handles WebSocket connections:

```ruby
require 'async/websocket/adapters/rails'

class ChatController < ApplicationController
	def index
		# Render the page with WebSocket JavaScript
	end

	skip_before_action :verify_authenticity_token, only: :connect

	def connect
		self.response = Async::WebSocket::Adapters::Rails.open(request) do |connection|
			Sync do
				# Perpetually read incoming messages from client:
				while message = connection.read
					# Echo message back to client:
					response_data = { text: "Echo: #{JSON.parse(message.buffer)['text']}" }
					connection.send_text(response_data.to_json)
					connection.flush
				end
			rescue Protocol::WebSocket::ClosedError
				# Connection closed by client.
			end
		end
	end
end
```

**Key Points:**
- Use `Async::WebSocket::Adapters::Rails.open` for WebSocket handling.
- Skip CSRF token verification for WebSocket endpoints.
- Use `connection.read` to receive messages from clients.
- Use `connection.send_text` and `connection.flush` to send messages.

### Client-Side: WebSocket JavaScript

Create JavaScript that connects to the WebSocket endpoint:

```html
<section id="response"></section>
<section class="input">
	<input id="chat" disabled="true" placeholder="Type your message and press Enter..." />
</section>

<script>
function connectToChatServer(url) {
	console.log("WebSocket Connecting...", url);
	var server = new WebSocket(url.href);
	
	server.onopen = function(event) {
		console.log("WebSocket Connected:", server);
		chat.disabled = false;
		
		chat.onkeypress = function(event) {
			if (event.keyCode == 13) {
				server.send(JSON.stringify({text: chat.value}));
				chat.value = "";
			}
		}
	};
	
	server.onmessage = function(event) {
		console.log("WebSocket Message:", event);
		
		var message = JSON.parse(event.data);
		
		var pre = document.createElement('pre');
		pre.innerText = message.text;
		
		response.appendChild(pre);
	};
	
	server.onerror = function(event) {
		console.log("WebSocket Error:", event);
		chat.disabled = true;
		server.close();
	};
	
	server.onclose = function(event) {
		console.log("WebSocket Close:", event);
		
		setTimeout(function() {
			connectToChatServer(url);
		}, 1000);
	};
}

var url = new URL('/chat/connect', window.location.href);
url.protocol = url.protocol.replace('http', 'ws');
connectToChatServer(url);
</script>
```

**Key Points:**
- Convert HTTP URL to WebSocket URL by replacing protocol.
- Handle `onopen`, `onmessage`, `onerror`, and `onclose` events.
- Use `JSON.stringify` and `JSON.parse` for structured messages.
- Implement automatic reconnection on close.

### Routing Configuration

Add routes to your `config/routes.rb`:

```ruby
Rails.application.routes.draw do
	get "chat/index"
	connect "chat/connect"
end
```
