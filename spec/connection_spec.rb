require 'uv-rays'


module TestConnect
	def post_init

	end

	def on_connect(connection)
		@connected = true
	end

	def on_close
		@disconnected = true
		@reactor.stop
	end

	def on_read(data, connection, port = nil, udp_test = nil)
		@received = data
		close_connection(:after_writing)
		@reactor.stop if udp_test 	# misc is set when test connect is a UDP connection
	end

	def check
		return [@connected, @disconnected, @received]
	end
end

module TestServer
	def post_init *args
		if args[0] == :use_tls
			use_tls
		end
	end

	def on_connect(conection)
		write('hello')
	end

	def on_read(data, ip, port, conection)
		# ephemeral port is used for sending on windows and linux?
		# Bound port seems to be used on OSX...
		# TODO:: Needs investigation, might be a Libuv bug
		send_datagram(data, ip, 3211)
	end
end


describe UV::Connection do
	before :each do
		@reactor = Libuv::Reactor.new
		@reactor.notifier do |error, context|
			begin
				@general_failure << "Log called: #{context}\n#{error.message}\n#{error.backtrace.join("\n") if error.backtrace}\n"
			rescue Exception
				@general_failure << "error in logger #{e.inspect}"
			end
		end
		@general_failure = []
		@timeout = @reactor.timer do
			@reactor.stop
			@general_failure << "test timed out"
		end
		@timeout.start(5000)
	end

	after :each do
		module TestConnect
			begin
				remove_const :UR_CONNECTION_CLASS
			rescue
			end
		end
		module TestServer
			begin
				remove_const :UR_CONNECTION_CLASS
			rescue
			end
		end
	end
	
	describe 'basic tcp client server' do
		it "should send some data and shutdown the socket" do
			@reactor.run { |reactor|
				UV.start_server '127.0.0.1', 3210, TestServer
				@klass = UV.connect '127.0.0.1', 3210, TestConnect
			}

			expect(@general_failure).to eq([])
			res = @klass.check
			expect(res[0]).to eq(true)
			expect(res[1]).to eq(true)
			expect(res[2]).to eq('hello')
		end

		it "should not call connect on connection failure" do
			@reactor.run { |reactor|
				@klass = UV.connect '127.0.0.1', 8123, TestConnect
			}

			expect(@general_failure).to eq([])
			res = @klass.check
			expect(res[0]).to eq(nil)
			expect(res[1]).to eq(true)	# Disconnect
			expect(res[2]).to eq(nil)
		end
	end

	describe 'basic tcp client server with tls' do
		it "should send some data and shutdown the socket" do
			@reactor.run { |reactor|
				UV.start_server '127.0.0.1', 3212, TestServer, :use_tls
				@klass = UV.connect '127.0.0.1', 3212, TestConnect
				@klass.use_tls
			}

			expect(@general_failure).to eq([])
			res = @klass.check
			expect(res[0]).to eq(true)
			expect(res[1]).to eq(true)
			expect(res[2]).to eq('hello')
		end
	end

	describe 'basic udp client server' do
		it "should send some data and close the socket" do
			@reactor.run { |reactor|
				UV.open_datagram_socket TestServer, '127.0.0.1', 3210
				@klass = UV.open_datagram_socket TestConnect, '127.0.0.1', 3211
				@klass.send_datagram('hello', '127.0.0.1', 3210)
			}

			expect(@general_failure).to eq([])
			res = @klass.check
			expect(res[0]).to eq(nil)
			expect(res[1]).to eq(nil)
			expect(res[2]).to eq('hello')
		end
	end
end
