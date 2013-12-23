require 'uv-rays'

describe UvRays::Scheduler do
    before :each do
        @loop = Libuv::Loop.new
        @general_failure = []
        @timeout = @loop.timer do
            @loop.stop
            @general_failure << "test timed out"
        end
        @timeout.start(5000)
        @scheduler = @loop.scheduler
    end

    it "should be able to schedule a one shot event using 'in'" do
        @loop.run { |logger|
            logger.progress do |level, errorid, error|
                begin
                    @general_failure << "Log called: #{level}: #{errorid}\n#{error.message}\n#{error.backtrace.join("\n")}\n"
                rescue Exception
                    @general_failure << 'error in logger'
                end
            end

            @event = @scheduler.in('0.5s') do |triggered, event|
                @triggered_at = triggered
                @result = event
                @loop.stop
            end
        }

        expect(@general_failure).to eq([])
        expect(@event).to eq(@result)
        @diff = @triggered_at - @event.last_scheduled
        expect((@diff >= 500 && @diff < 750)).to eq(true)
    end

    it "should be able to schedule a one shot event using 'at'" do
        @loop.run { |logger|
            logger.progress do |level, errorid, error|
                begin
                    @general_failure << "Log called: #{level}: #{errorid}\n#{error.message}\n#{error.backtrace.join("\n")}\n"
                rescue Exception
                    @general_failure << 'error in logger'
                end
            end

            @event = @scheduler.at(Time.now + 1) do |triggered, event|
                @triggered_at = triggered
                @result = event
                @loop.stop
            end
        }

        expect(@general_failure).to eq([])
        expect(@event).to eq(@result)
        @diff = @triggered_at - @event.last_scheduled
        expect((@diff >= 1000 && @diff < 1250)).to eq(true)
    end

    it "should be able to schedule a repeat event" do
        @loop.run { |logger|
            logger.progress do |level, errorid, error|
                begin
                    @general_failure << "Log called: #{level}: #{errorid}\n#{error.message}\n#{error.backtrace.join("\n")}\n"
                rescue Exception
                    @general_failure << 'error in logger'
                end
            end

            @run = 0
            @event = @scheduler.every('0.25s') do |triggered, event|
                @triggered_at = triggered
                @result = event

                @run += 1
                if @run == 2
                    @event.pause
                    @loop.stop
                end
            end
        }

        expect(@general_failure).to eq([])
        expect(@run).to eq(2)
        expect(@event).to eq(@result)
        @diff = @triggered_at - @event.last_scheduled
        expect((@diff >= 250 && @diff < 500)).to eq(true)
    end
end
