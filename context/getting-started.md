# Getting Started

This guide explains how to get started integrating Async with Rails.

## Installation

In your existing Rails application:

```bash
bundle add async-rails
```

You might also like to remove your existing web server, such as Puma, and replace it with Async's web server:

```bash
bundle remove puma
```

## Falcon (Web Server)

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

Consult the other integration guides for more information on using Async with popular libraries and frameworks.
