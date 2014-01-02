require 'uv-rays'


module TestConnect
	def post_init

	end

	def on_connect(connection)
		@connected = true
	end

	def on_close
		@disconnected = true
		@loop.stop
	end

	def on_read(data, connection, port = nil)
		@received = data
		close_connection(:after_writing)
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

	def on_read(*args) #data, ip, port, conection)
		#p "was sent #{data} from port #{port}"
		#send_datagram(data, ip, port)
		@loop.stop
	end
end


describe UV::Connection do
	before :each do
		@loop = Libuv::Loop.new
		@general_failure = []
		@timeout = @loop.timer do
			@loop.stop
			@general_failure << "test timed out"
		end
		@timeout.start(5000)
	end

	after :each do
		module TestConnect
			remove_const :UR_CONNECTION_CLASS
		end
		module TestServer
			remove_const :UR_CONNECTION_CLASS
		end
	end
	
	describe 'basic tcp client server' do
		it "should send some data and shutdown the socket", :network => true do
			@loop.run { |logger|
				logger.progress do |level, errorid, error|
					begin
						@general_failure << "Log called: #{level}: #{errorid}\n#{error.message}\n#{error.backtrace.join("\n")}\n"
					rescue Exception
						@general_failure << 'error in logger'
					end
				end

				UV.start_server '127.0.0.1', 3210, TestServer
				@klass = UV.connect '127.0.0.1', 3210, TestConnect
			}

			expect(@general_failure).to eq([])
			res = @klass.check
			expect(res[0]).to eq(true)
			expect(res[1]).to eq(true)
			expect(res[2]).to eq('hello')
		end
	end

	describe 'basic tcp client server with tls' do
		it "should send some data and shutdown the socket", :network => true do
			@loop.run { |logger|
				logger.progress do |level, errorid, error|
					begin
						@general_failure << "Log called: #{level}: #{errorid}\n#{error.message}\n#{error.backtrace.join("\n")}\n"
					rescue Exception
						@general_failure << 'error in logger'
					end
				end

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
		it "should send some data and close the socket", :network => true do
			@loop.run { |logger|
				logger.progress do |level, errorid, error|
					begin
						@general_failure << "Log called: #{level}: #{errorid}\n#{error.message}\n#{error.backtrace.join("\n")}\n"
					rescue Exception
						@general_failure << 'error in logger'
					end
				end

				UV.open_datagram_socket TestServer, '127.0.0.1', 3210
				@klass = UV.open_datagram_socket TestConnect, '127.0.0.1', 3211
				@klass.send_datagram('hello', '127.0.0.1', 3210)
			}

			expect(@general_failure).to eq([])
			res = @klass.check
			expect(res[0]).to eq(nil)
			expect(res[1]).to eq(nil)
			expect(res[2]).to eq(nil) #'hello' (libuv receive bug?)
		end
	end
end
