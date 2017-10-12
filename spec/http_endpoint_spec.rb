require 'uv-rays'


module HttpServer
	def post_init
		@parser = ::HttpParser::Parser.new(self)
        @state = ::HttpParser::Parser.new_instance
        @state.type = :request
	end

	def on_message_complete(parser)
		write("HTTP/1.1 200 OK\r\nSet-Cookie: Test=path\r\nSet-Cookie: other=val; path=/whatwhat\r\nContent-type: text/html\r\nContent-length: 1\r\n\r\ny")
	end

	def on_read(data, connection)
		if @parser.parse(@state, data)
            p 'parse error'
            p @state.error
        end
	end
end

module NTLMServer
	def post_init
		@parser = ::HttpParser::Parser.new(self)
        @state = ::HttpParser::Parser.new_instance
        @state.type = :request

        @req = 0
	end

	def on_message_complete(parser)
		if @req == 0
			@state = ::HttpParser::Parser.new_instance
			write("HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: NTLM TlRMTVNTUAACAAAAEgASADgAAAAFgokCuEPycVw6htsAAAAAAAAAAK4ArgBKAAAABgOAJQAAAA9SAEEAQgBPAE4ARQBUAE8AQwACABIAUgBBAEIATwBOAEUAVABPAEMAAQAUAFMAWQBQAFYAMQA5ADkAMAA1ADUABAAcAG8AYwAuAHIAYQBiAG8AbgBlAHQALgBjAG8AbQADADIAUwBZAFAAVgAxADkAOQAwADUANQAuAG8AYwAuAHIAYQBiAG8AbgBlAHQALgBjAG8AbQAFABYAcgBhAGIAbwBuAGUAdAAuAGMAbwBtAAcACACcZNzCwkbRAQAAAAA=\r\nContent-type: text/html\r\nContent-length: 0\r\n\r\n")
		else
			write("HTTP/1.1 200 OK\r\nContent-type: text/html\r\nContent-length: 1\r\n\r\ny")
		end
		@req += 1
	end

	def on_read(data, connection)
		if @parser.parse(@state, data)
            p 'parse error'
            p @state.error
        end
	end
end

module DigestServer
	def post_init
		@parser = ::HttpParser::Parser.new(self)
        @state = ::HttpParser::Parser.new_instance
        @state.type = :request

        @req = 0
	end

	def on_message_complete(parser)
		if @req == 0
			@state = ::HttpParser::Parser.new_instance
			write("HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Digest realm=\"testrealm@host.com\",qop=\"auth,auth-int\",nonce=\"dcd98b7102dd2f0e8b11d0f600bfb0c093\",opaque=\"5ccc069c403ebaf9f0171e9517f40e41\"\r\nContent-type: text/html\r\nContent-length: 0\r\n\r\n")
		else
			write("HTTP/1.1 200 OK\r\nContent-type: text/html\r\nContent-length: 1\r\n\r\nd")
		end
		@req += 1
	end

	def on_read(data, connection)
		if @parser.parse(@state, data)
            p 'parse error'
            p @state.error
        end
	end
end

module OldServer
	def post_init
		@parser = ::HttpParser::Parser.new(self)
        @state = ::HttpParser::Parser.new_instance
        @state.type = :request
	end

	def on_message_complete(parser)
		write("HTTP/1.0 200 OK\r\nContent-type: text/html\r\nContent-length: 0\r\n\r\n")
	end

	def on_read(data, connection)
		if @parser.parse(@state, data)
            p 'parse error'
            p @state.error
        end
	end
end

module WeirdServer
	def post_init
		@parser = ::HttpParser::Parser.new(self)
        @state = ::HttpParser::Parser.new_instance
        @state.type = :request
	end

	def on_message_complete(parser)
		write("HTTP/1.1 200 OK\r\nContent-type: text/html\r\n\r\nnolength")
		close_connection(:after_writing)
	end

	def on_read(data, connection)
		if @parser.parse(@state, data)
            p 'parse error'
            p @state.error
        end
	end
end

module BrokenServer
	@@req = 0

	def post_init
		@parser = ::HttpParser::Parser.new(self)
        @state = ::HttpParser::Parser.new_instance
        @state.type = :request
	end

	def on_message_complete(parser)
		if @@req == 0
			@state = ::HttpParser::Parser.new_instance
			write("HTTP/1.1 401 Unauthorized\r\nContent-type: text/ht")
			close_connection(:after_writing)
		else
			write("HTTP/1.1 200 OK\r\nContent-type: text/html\r\nContent-length: 3\r\n\r\nyes")
		end
		@@req += 1
	end

	def on_read(data, connection)
		if @parser.parse(@state, data)
            p 'parse error'
            p @state.error
        end
	end
end

module SlowServer
	@@req = 0

	def post_init
		@parser = ::HttpParser::Parser.new(self)
        @state = ::HttpParser::Parser.new_instance
        @state.type = :request
	end

	def on_message_complete(parser)
		if @@req == 0
			@state = ::HttpParser::Parser.new_instance
			write("HTTP/1.1 200 OK\r\nContent-")
		else
			write("HTTP/1.1 200 OK\r\nContent-type: text/html\r\nContent-length: 3\r\n\r\nokg")
		end
		@@req += 1
	end

	def on_read(data, connection)
		if @parser.parse(@state, data)
            p 'parse error'
            p @state.error
        end
	end
end


describe UV::HttpEndpoint do
	before :each do
		@general_failure = []

		@reactor = Libuv::Reactor.new
		@reactor.notifier do |error, context|
			begin
				@general_failure << "Log called: #{context}\n#{error.message}\n#{error.backtrace.join("\n") if error.backtrace}\n"
			rescue Exception
				@general_failure << "error in logger #{e.inspect}"
			end
		end

		@timeout = @reactor.timer do
			@reactor.stop
			@general_failure << "test timed out"
		end
		@timeout.start(10000)

		@request_failure = proc { |err|
			@general_failure << err
			@reactor.stop
		}
	end

	describe 'basic http request' do
		it "should send a request then receive a response" do
			@reactor.run { |reactor|
				tcp = UV.start_server '127.0.0.1', 3250, HttpServer
				server = UV::HttpEndpoint.new 'http://127.0.0.1:3250'

				request = server.get(:path => '/whatwhat')
				request.then(proc { |response|
					@response = response
					tcp.close
					@reactor.stop
				}, @request_failure)
			}

			expect(@general_failure).to eq([])
			expect(@response[:"Content-type"]).to eq('text/html')
			expect(@response.http_version).to eq('1.1')
			expect(@response.status).to eq(200)
			expect(@response.cookies).to eq({:Test=>"path", :other=>"val"})
			expect(@response.keep_alive).to eq(true)

			expect(@response.body).to eq('y')
		end

		it "should send a request then receive a response using httpi" do
			require 'httpi/adapter/libuv'
			HTTPI.adapter = :libuv

			@reactor.run { |reactor|
				tcp = UV.start_server '127.0.0.1', 3250, HttpServer

				begin
					request = HTTPI::Request.new("http://127.0.0.1:3250/whatwhat")
					@response = HTTPI.get(request)
				rescue => e
					@general_failure << e
				ensure
					tcp.close
					@reactor.stop
				end
			}

			expect(@general_failure).to eq([])
			expect(@response.headers["Content-type"]).to eq('text/html')
			expect(@response.code).to eq(200)
			expect(@response.raw_body).to eq('y')
		end

		it 'should be garbage collected', mri_only: true do
			require 'weakref'
			require 'objspace'

			objs = nil
			obj_id = nil

			@reactor.run { |reactor|
				tcp = UV.start_server '127.0.0.1', 3250, HttpServer
				block = proc {
					server = UV::HttpEndpoint.new 'http://127.0.0.1:3250', inactivity_timeout: 300
					obj_id = server.object_id
					objs = WeakRef.new(server)

					request = server.get(:path => '/whatwhat')
					request.catch(@request_failure)
					request.finally {
						tcp.close
						@timeout.stop
					}

					server = nil
					request = nil
				}

				block.call

				reactor.scheduler.in(800) do
					GC.start
					ObjectSpace.garbage_collect
				end
			}
			ObjectSpace.garbage_collect
			GC.start

			expect(@general_failure).to eq([])

			begin
				expect(objs.weakref_alive?).to eq(nil)
			rescue Exception => e
				objs = ObjectSpace.each_object.select{ |o| ObjectSpace.reachable_objects_from(o).map(&:object_id).include?(obj_id) }
				puts "Objects referencing HTTP class:\n#{objs.inspect}\n"
				raise e
			end
		end

		it "should return the response when no length is given and the connection is closed" do
			# I've seen IoT devices do this (projector screen controllers etc)
			@reactor.run { |reactor|
				tcp = UV.start_server '127.0.0.1', 3250, WeirdServer
				server = UV::HttpEndpoint.new 'http://127.0.0.1:3250'

				request = server.get(:path => '/')
				request.then(proc { |response|
					@response = response
					tcp.close
					@reactor.stop
				}, @request_failure)
			}

			expect(@general_failure).to eq([])
			expect(@response[:"Content-type"]).to eq('text/html')
			expect(@response.http_version).to eq('1.1')
			expect(@response.status).to eq(200)
			expect(@response.cookies).to eq({})
			expect(@response.keep_alive).to eq(true)

			expect(@response.body).to eq('nolength')
		end

		it "should send multiple requests on the same connection" do
			@reactor.run { |reactor|
				tcp = UV.start_server '127.0.0.1', 3250, HttpServer
				server = UV::HttpEndpoint.new 'http://127.0.0.1:3250'

				request = server.get(path: '/whatwhat', req: 1)
				request.then(proc { |response|
					@response = response
					#@reactor.stop
				}, @request_failure)

				request2 = server.get(path: '/', req: 2)
				request2.then(proc { |response|
					@response2 = response
					tcp.close
					@reactor.stop
				}, @request_failure)
			}

			expect(@general_failure).to eq([])
			expect(@response[:"Content-type"]).to eq('text/html')
			expect(@response.http_version).to eq('1.1')
			expect(@response.status).to eq(200)
			expect(@response.cookies).to eq({:Test=>"path", :other=>"val"})
			expect(@response.keep_alive).to eq(true)

			expect(@response2[:"Content-type"]).to eq('text/html')
			expect(@response2.http_version).to eq('1.1')
			expect(@response2.status).to eq(200)
			expect(@response2.cookies).to eq({:Test=>"path"})
			expect(@response2.keep_alive).to eq(true)
		end
	end

	describe 'old http request' do
		it "should send a request then receive a response" do
			@reactor.run { |reactor|
				tcp = UV.start_server '127.0.0.1', 3250, OldServer
				server = UV::HttpEndpoint.new 'http://127.0.0.1:3250'

				request = server.get(:path => '/')
				request.then(proc { |response|
					@response = response
					tcp.close
					@reactor.stop
				}, @request_failure)
			}

			expect(@general_failure).to eq([])
			expect(@response[:"Content-type"]).to eq('text/html')
			expect(@response.http_version).to eq('1.0')
			expect(@response.status).to eq(200)
			expect(@response.cookies).to eq({})
			expect(@response.keep_alive).to eq(false)
		end

		it "should send multiple requests" do
			@reactor.run { |reactor|
				tcp = UV.start_server '127.0.0.1', 3251, OldServer
				server = UV::HttpEndpoint.new 'http://127.0.0.1:3251'

				request = server.get(:path => '/')
				request.then(proc { |response|
					@response = response
					#@reactor.stop
				}, @request_failure)

				request2 = server.get(:path => '/')
				request2.then(proc { |response|
					@response2 = response
					tcp.close
					@reactor.stop
				}, @request_failure)
			}

			expect(@general_failure).to eq([])
			expect(@response[:"Content-type"]).to eq('text/html')
			expect(@response.http_version).to eq('1.0')
			expect(@response.status).to eq(200)
			expect(@response.cookies).to eq({})
			expect(@response.keep_alive).to eq(false)

			expect(@response2[:"Content-type"]).to eq('text/html')
			expect(@response2.http_version).to eq('1.0')
			expect(@response2.status).to eq(200)
			expect(@response2.cookies).to eq({})
			expect(@response2.keep_alive).to eq(false)
		end
	end

	describe 'Auth support' do
		it "should perform NTLM auth transparently" do
			@reactor.run { |reactor|
				tcp = UV.start_server '127.0.0.1', 3252, NTLMServer
				server = UV::HttpEndpoint.new 'http://127.0.0.1:3252', ntlm: {
					user: 'username',
					password: 'password',
					domain: 'domain'
				}

				request = server.get(path: '/')
				request.then(proc { |response|
					@response = response
					tcp.close
					@reactor.stop
				}, @request_failure)
			}

			expect(@general_failure).to eq([])
			expect(@response[:"Content-type"]).to eq('text/html')
			expect(@response.http_version).to eq('1.1')
			expect(@response.status).to eq(200)
			expect(@response.cookies).to eq({})
			expect(@response.keep_alive).to eq(true)
			expect(@response.body).to eq('y')
		end

		it "should perform Digest auth transparently" do
			@reactor.run { |reactor|
				tcp = UV.start_server '127.0.0.1', 3252, DigestServer
				server = UV::HttpEndpoint.new 'http://127.0.0.1:3252', digest: {
					user: 'Mufasa',
					password: 'Circle Of Life'
				}

				request = server.get(path: '/dir/index.html')
				request.then(proc { |response|
					@response = response
					tcp.close
					@reactor.stop
				}, @request_failure)
			}

			expect(@general_failure).to eq([])
			expect(@response[:"Content-type"]).to eq('text/html')
			expect(@response.http_version).to eq('1.1')
			expect(@response.status).to eq(200)
			expect(@response.cookies).to eq({})
			expect(@response.keep_alive).to eq(true)
			expect(@response.body).to eq('d')
		end
	end

	describe 'cookies' do
		it "should accept cookies and send them on subsequent requests" do
			@reactor.run { |reactor|
				tcp = UV.start_server '127.0.0.1', 3250, HttpServer
				@server = UV::HttpEndpoint.new 'http://127.0.0.1:3250'

				request = @server.get(:path => '/whatwhat')
				expect(request.cookies_hash).to eq({})

				request.then(proc { |response|
					tcp.close
					@reactor.stop
				}, @request_failure)
			}

			expect(@general_failure).to eq([])
			expect(@server.cookiejar.get('http://127.0.0.1:3250/whatno')).to eq(["Test=path"])
			@server = nil
		end
	end

	describe 'when things go wrong' do
		it "should reconnect after connection dropped and continue sending requests" do
			@reactor.run { |reactor|
				tcp = UV.start_server '127.0.0.1', 6353, BrokenServer
				server = UV::HttpEndpoint.new 'http://127.0.0.1:6353'

				@response = nil
				request = server.get(:path => '/')
				request.then(proc { |response|
					@response = response
					#@reactor.stop
				}, proc { |error|
					@error = error
				})

				request2 = server.get(:path => '/')
				request2.then(proc { |response|
					@response2 = response
					tcp.close
					@reactor.stop
				}, @request_failure)
			}

			expect(@general_failure).to eq([])
			expect(@response).to eq(nil)
			expect(@error).to eq(:partial_response)

			expect(@response2[:"Content-type"]).to eq('text/html')
			expect(@response2.http_version).to eq('1.1')
			expect(@response2.status).to eq(200)
			expect(@response2.cookies).to eq({})
			expect(@response2.keep_alive).to eq(true)
			expect(@response2.body).to eq('yes')
		end

		it "should reconnect after timeout and continue sending requests" do
			@reactor.run { |reactor|
				tcp = UV.start_server '127.0.0.1', 6363, SlowServer
				server = UV::HttpEndpoint.new 'http://127.0.0.1:6363', inactivity_timeout: 500

				@response = nil
				request = server.get(:path => '/')
				request.then(proc { |response|
					@response = response
					#@reactor.stop
				}, proc { |error|
					@error = error
				})

				request2 = server.get(:path => '/')
				request2.then(proc { |response|
					@response2 = response
					tcp.close
					@reactor.stop
				}, @request_failure)
			}

			expect(@general_failure).to eq([])
			expect(@response).to eq(nil)
			expect(@error).to eq(:timeout)

			expect(@response2[:"Content-type"]).to eq('text/html')
			expect(@response2.http_version).to eq('1.1')
			expect(@response2.status).to eq(200)
			expect(@response2.cookies).to eq({})
			expect(@response2.keep_alive).to eq(true)
			expect(@response2.body).to eq('okg')
		end

		it "should fail if the server is not available" do
			@reactor.run { |reactor|
				server = UV::HttpEndpoint.new 'http://127.0.0.1:6666', inactivity_timeout: 500

				@response = nil
				@response2 = nil

				request = server.get(:path => '/')
				request.then(proc { |response|
					@response = response
					#@reactor.stop
				}, proc { |error|
					@error = error
				})

				request2 = server.get(:path => '/')
				request2.then(proc { |response|
					@response2 = response
					@reactor.stop
				}, proc { |error|
					@error2 = error
					@reactor.stop
				})
			}

			expect(@general_failure).to eq([])
			expect(@response).to eq(nil)
			# Failure will be a UV error
			#expect(@error).to eq(:connection_failure)

			expect(@response2).to eq(nil)
			expect(@error2).to eq(:connection_failure)
		end
	end

=begin
	describe 'proxy support' do
		it "should work with a HTTP proxy server" do
			@reactor.run { |reactor|
				server = UV::HttpEndpoint.new 'http://www.whatsmyip.org', {
					#inactivity_timeout: 1000,
					proxy: {
						host: '212.47.252.49',
						port: 3128
					}
				}

				@response = nil

				request = server.get(:path => '/', headers: {accept: 'text/html'})
				request.then(proc { |response|
					@response = response
					@reactor.stop
				}, proc { |error|
					@error = error
				})
			}

			expect(@general_failure).to eq([])
			expect(@response.status).to eq(200)
		end

		it "should work with a HTTPS proxy server" do
			@reactor.run { |reactor|
				server = UV::HttpEndpoint.new 'https://www.google.com.au', {
					#inactivity_timeout: 1000,
					proxy: {
						host: '212.47.252.49',
						port: 3128
					}
				}

				@response = nil

				request = server.get(:path => '/', headers: {accept: 'text/html'})
				request.then(proc { |response|
					@response = response
					@reactor.stop
				}, proc { |error|
					@error = error
				})
			}

			expect(@general_failure).to eq([])
			expect(@response.status).to eq(200)
		end
	end
=end
end
