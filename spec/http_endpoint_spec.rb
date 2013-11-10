require 'uv-rays'


module HttpServer
	def post_init
		@parser = ::HttpParser::Parser.new(self)
        @state = ::HttpParser::Parser.new_instance
        @state.type = :request
	end

	def on_message_complete(parser)
		write("HTTP/1.1 200 OK\r\nContent-type: text/html\r\nContent-length: 0\r\n\r\n")
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


describe UvRays::HttpEndpoint do
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
		it "should send a request then receive a response", :network => true do
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

			@general_failure.should == []
			@response[:headers][:"Content-type"].should == 'text/html'
			@response[:headers].http_version.should == '1.1'
			@response[:headers].status.should == 200
			@response[:headers].cookies.should == {}
			@response[:headers].keep_alive.should == true
		end

		it "should send multiple requests on the same connection", :network => true do
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
					#@loop.stop
				}, @request_failure)
				
				request2 = server.get(:path => '/')
				request2.then(proc { |response|
					@response2 = response
					tcp.close
					@loop.stop
				}, @request_failure)
			}

			@general_failure.should == []
			@response[:headers][:"Content-type"].should == 'text/html'
			@response[:headers].http_version.should == '1.1'
			@response[:headers].status.should == 200
			@response[:headers].cookies.should == {}
			@response[:headers].keep_alive.should == true

			@response2[:headers][:"Content-type"].should == 'text/html'
			@response2[:headers].http_version.should == '1.1'
			@response2[:headers].status.should == 200
			@response2[:headers].cookies.should == {}
			@response2[:headers].keep_alive.should == true
		end

		it "should send pipelined requests on the same connection", :network => true do
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

				request = server.get(:path => '/', :pipeline => true)
				request.then(proc { |response|
					@response = response
					#@loop.stop
				}, @request_failure)
				
				request2 = server.get(:path => '/', :pipeline => true)
				request2.then(proc { |response|
					@response2 = response
					tcp.close
					@loop.stop
				}, @request_failure)
			}

			@general_failure.should == []
			@response[:headers][:"Content-type"].should == 'text/html'
			@response[:headers].http_version.should == '1.1'
			@response[:headers].status.should == 200
			@response[:headers].cookies.should == {}
			@response[:headers].keep_alive.should == true

			@response2[:headers][:"Content-type"].should == 'text/html'
			@response2[:headers].http_version.should == '1.1'
			@response2[:headers].status.should == 200
			@response2[:headers].cookies.should == {}
			@response2[:headers].keep_alive.should == true
		end
	end

	describe 'old http request' do
		it "should send a request then receive a response", :network => true do
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

			@general_failure.should == []
			@response[:headers][:"Content-type"].should == 'text/html'
			@response[:headers].http_version.should == '1.0'
			@response[:headers].status.should == 200
			@response[:headers].cookies.should == {}
			@response[:headers].keep_alive.should == false
		end

		it "should send multiple requests", :network => true do
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
					#@loop.stop
				}, @request_failure)
				
				request2 = server.get(:path => '/')
				request2.then(proc { |response|
					@response2 = response
					tcp.close
					@loop.stop
				}, @request_failure)
			}

			@general_failure.should == []
			@response[:headers][:"Content-type"].should == 'text/html'
			@response[:headers].http_version.should == '1.0'
			@response[:headers].status.should == 200
			@response[:headers].cookies.should == {}
			@response[:headers].keep_alive.should == false

			@response2[:headers][:"Content-type"].should == 'text/html'
			@response2[:headers].http_version.should == '1.0'
			@response2[:headers].status.should == 200
			@response2[:headers].cookies.should == {}
			@response2[:headers].keep_alive.should == false
		end

		it "should fail to send pipelined requests", :network => true do
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

				request = server.get(:path => '/', :pipeline => true)
				request.then(proc { |response|
					@response = response
					#@loop.stop
				}, @request_failure)
				
				request2 = server.get(:path => '/', :pipeline => true)
				request2.then(proc { |response|
					@response2 = response
					tcp.close
					@loop.stop
				}, @request_failure)
			}

			@general_failure.should == [:disconnected]
			@response[:headers][:"Content-type"].should == 'text/html'
			@response[:headers].http_version.should == '1.0'
			@response[:headers].status.should == 200
			@response[:headers].cookies.should == {}
			@response[:headers].keep_alive.should == false
			# Response 2 was the general failure
		end
	end
end
