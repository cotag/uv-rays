require 'uv-rays'

describe UV::Scheduler do
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
        expect(@diff).to be >= 500
        expect(@diff).to be < 750
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
        expect(@diff).to be >= 1000
        expect(@diff).to be < 1250
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

                diff = triggered - event.last_scheduled
                expect(diff).to be >= 250
                expect(diff).to be < 500

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
    end

    it "should be able to cancel an event" do
        # Also tests events run in order of scheduled
        # Also tests events are not inadvertently canceled by other test
        @loop.run { |logger|
            logger.progress do |level, errorid, error|
                begin
                    @general_failure << "Log called: #{level}: #{errorid}\n#{error.message}\n#{error.backtrace.join("\n")}\n"
                rescue Exception
                    @general_failure << 'error in logger'
                end
            end

            @triggered = []

            @event1 = @scheduler.in('0.5s') do |triggered, event|
                @triggered << 1
            end

            @event2 = @scheduler.in('0.5s') do |triggered, event|
                @triggered << 2
            end

            @event3 = @scheduler.in('0.5s') do |triggered, event|
                @triggered << 3
                @loop.stop
            end

            @scheduled, @schedules = @scheduler.instance_eval { 
                [@scheduled, @schedules]
            }

            expect(@scheduled.size).to eq(3)
            expect(@schedules.size).to eq(3)

            @event2.cancel

            @loop.next_tick do
                expect(@scheduled.size).to eq(2)
                expect(@schedules.size).to eq(2)
            end
        }

        expect(@general_failure).to eq([])
        expect(@triggered).to eq([1, 3])
        expect(@scheduled.size).to eq(0)
        expect(@schedules.size).to eq(0)
    end
end
