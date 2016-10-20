# uv-rays

[![Build Status](https://travis-ci.org/cotag/uv-rays.svg?branch=master)](https://travis-ci.org/cotag/uv-rays)

UV-Rays was designed to eliminate the complexities of high-performance threaded network programming, allowing engineers to concentrate on their application logic.


## Core Features

1. TCP (and UDP) Connection abstractions
2. Advanced stream tokenization
3. Scheduled events (in, at, every, cron)
4. HTTP 1.1 compatible client support

This adds to the features already available from [Libuv](https://github.com/cotag/libuv) on which the gem is based


## Support

UV-Rays supports all platforms where ruby is available. Linux, OSX, BSD and Windows. MRI, jRuby and Rubinius.

Run `gem install uv-rays` to install


## Getting Started

Here's a fully-functional echo server written with UV-Rays:

```ruby
 require 'uv-rays'

 module EchoServer
  def on_connect(socket)
    @ip, @port = socket.peername
    logger.info "-- #{@ip}:#{@port} connected"
  end

  def on_read(data, socket)
    write ">>>you sent: #{data}"
    close_connection if data =~ /quit/i
  end

  def on_close
    puts "-- #{@ip}:#{@port} disconnected"
  end
end

reactor {
  UV.start_server "127.0.0.1", 8081, EchoServer
}

```
