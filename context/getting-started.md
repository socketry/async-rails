# Getting Started

This guide explains how to get started using Falcon to host your Rails application.

## Installation

In your existing Rails application:

```bash
bundle add falcon-rails
```

You might also like to remove your existing web server, such as Puma, and replace it with Falcon:

```bash
bundle remove puma
```

## Usage

Falcon is an Async-compatible web server that can be used with Rails. It provides high concurrency and low latency for web applications.

To use Falcon in development, first install the development TLS certificates:

```
> bundle exec bake localhost:install
```

Then, you can start your Rails application with Falcon:

```bash
> bundle exec falcon serve
```

You can access your application at `https://localhost:9292`.

## Integrations

Consult the other integration guides for more information on using Falcon with popular libraries and frameworks.
	
### Example

Many of the integrations are demonstrated in the example application available at: https://github.com/socketry/falcon-rails-examples
