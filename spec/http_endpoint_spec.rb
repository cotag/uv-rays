require 'uv-rays'


module HttpServer
	def post_init
		@parser = ::HttpParser::Parser.new(self)
        @state = ::HttpParser::Parser.new_instance
        @state.type = :request
	end

	def on_message_complete(parser)
		write("HTTP/1.1 200 OK\r\nContent-type: text/html\r\nContent-length: 1\r\n\r\ny")
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


describe UV::HttpEndpoint do
	before :each do
		@loop = Libuv::Loop.new
		@general_failure = []
		@timeout = @loop.timer do
			@loop.stop
			@general_failure << "test timed out"
		end
		@timeout.start(5000)

		@request_failure = proc { |err|
			@general_failure << err
			@loop.stop
		}
	end
	
	describe 'basic http request' do
		it "should send a request then receive a response" do
			@loop.run { |logger|
				logger.progress do |level, errorid, error|
					begin
						@general_failure << "Log called: #{level}: #{errorid}\n#{error.message}\n#{error.backtrace.join("\n")}\n"
					rescue Exception
						@general_failure << 'error in logger'
					end
				end

				tcp = UV.start_server '127.0.0.1', 3250, HttpServer
				server = UV::HttpEndpoint.new 'http://127.0.0.1:3250'

				request = server.get(:path => '/')
				request.then(proc { |response|
					@response = response
					tcp.close
					@loop.stop
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

		it "should return the response when no length is given and the connection is closed" do
			# I've seen IoT devices do this (projector screen controllers etc)
			@loop.run { |logger|
				logger.progress do |level, errorid, error|
					begin
						@general_failure << "Log called: #{level}: #{errorid}\n#{error.message}\n#{error.backtrace.join("\n")}\n"
					rescue Exception
						@general_failure << 'error in logger'
					end
				end

				tcp = UV.start_server '127.0.0.1', 3250, WeirdServer
				server = UV::HttpEndpoint.new 'http://127.0.0.1:3250'

				request = server.get(:path => '/')
				request.then(proc { |response|
					@response = response
					tcp.close
					@loop.stop
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
			@loop.run { |logger|
				logger.progress do |level, errorid, error|
					begin
						@general_failure << "Log called: #{level}: #{errorid}\n#{error.message}\n#{error.backtrace.join("\n")}\n"
					rescue Exception
						@general_failure << 'error in logger'
					end
				end

				tcp = UV.start_server '127.0.0.1', 3250, HttpServer
				server = UV::HttpEndpoint.new 'http://127.0.0.1:3250'

				request = server.get(path: '/', req: 1)
				request.then(proc { |response|
					@response = response
					#@loop.stop
				}, @request_failure)
				
				request2 = server.get(path: '/', req: 2)
				request2.then(proc { |response|
					@response2 = response
					tcp.close
					@loop.stop
				}, @request_failure)
			}

			expect(@general_failure).to eq([])
			expect(@response[:"Content-type"]).to eq('text/html')
			expect(@response.http_version).to eq('1.1')
			expect(@response.status).to eq(200)
			expect(@response.cookies).to eq({})
			expect(@response.keep_alive).to eq(true)

			expect(@response2[:"Content-type"]).to eq('text/html')
			expect(@response2.http_version).to eq('1.1')
			expect(@response2.status).to eq(200)
			expect(@response2.cookies).to eq({})
			expect(@response2.keep_alive).to eq(true)
		end
	end

	describe 'old http request' do
		it "should send a request then receive a response" do
			@loop.run { |logger|
				logger.progress do |level, errorid, error|
					begin
						@general_failure << "Log called: #{level}: #{errorid}\n#{error.message}\n#{error.backtrace.join("\n")}\n"
					rescue Exception
						@general_failure << 'error in logger'
					end
				end

				tcp = UV.start_server '127.0.0.1', 3250, OldServer
				server = UV::HttpEndpoint.new 'http://127.0.0.1:3250'

				request = server.get(:path => '/')
				request.then(proc { |response|
					@response = response
					tcp.close
					@loop.stop
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
			@loop.run { |logger|
				logger.progress do |level, errorid, error|
					begin
						@general_failure << "Log called: #{level}: #{errorid}\n#{error.message}\n#{error.backtrace.join("\n")}\n"
					rescue Exception
						@general_failure << 'error in logger'
					end
				end

				tcp = UV.start_server '127.0.0.1', 3251, OldServer
				server = UV::HttpEndpoint.new 'http://127.0.0.1:3251'

				request = server.get(:path => '/')
				request.then(proc { |response|
					@response = response
					#@loop.stop
				}, @request_failure)
				
				request2 = server.get(:path => '/')
				request2.then(proc { |response|
					@response2 = response
					tcp.close
					@loop.stop
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

	describe 'NTLM auth support' do
		it "should perform NTLM auth transparently" do
			@loop.run { |logger|
				logger.progress do |level, errorid, error|
					begin
						@general_failure << "Log called: #{level}: #{errorid}\n#{error.message}\n#{error.backtrace.join("\n")}\n"
					rescue Exception
						@general_failure << 'error in logger'
					end
				end

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
					@loop.stop
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
	end

	describe 'when things go wrong' do
		it "should reconnect and continue sending requests" do
			@loop.run { |logger|
				logger.progress do |level, errorid, error|
					begin
						@general_failure << "Log called: #{level}: #{errorid}\n#{error.message}\n#{error.backtrace.join("\n")}\n"
					rescue Exception
						@general_failure << 'error in logger'
					end
				end

				tcp = UV.start_server '127.0.0.1', 6353, BrokenServer
				server = UV::HttpEndpoint.new 'http://127.0.0.1:6353'

				@response = nil
				request = server.get(:path => '/')
				request.then(proc { |response|
					@response = response
					#@loop.stop
				}, proc { |error|
					@error = error
				})
				
				request2 = server.get(:path => '/')
				request2.then(proc { |response|
					@response2 = response
					tcp.close
					@loop.stop
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
	end
end
