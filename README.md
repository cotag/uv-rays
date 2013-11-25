# uv-rays

[![Build Status](https://travis-ci.org/cotag/uv-rays.png?branch=master)](https://travis-ci.org/cotag/uv-rays)

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
   def post_init
     puts "-- someone connected to the echo server!"
   end

   def on_read data, *args
     write ">>>you sent: #{data}"
     close_connection if data =~ /quit/i
   end

   def on_close
     puts "-- someone disconnected from the echo server!"
   end
end

# Note that this will block current thread.
Libuv::Loop.default.run {
  UV.start_server "127.0.0.1", 8081, EchoServer
}

```
