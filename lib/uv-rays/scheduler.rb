# frozen_string_literal: true

require 'set'               # ruby std lib
require 'bisect'            # insert into a sorted array
require 'tzinfo'            # timezone information
require 'uv-rays/scheduler/time'

module UV

    class ScheduledEvent < ::Libuv::Q::DeferredPromise
        # Note:: Comparable should not effect Hashes
        # it will however effect arrays
        include Comparable

        attr_reader :created
        attr_reader :last_scheduled
        attr_reader :next_scheduled
        attr_reader :trigger_count

        def initialize(scheduler)
            # Create a dummy deferrable
            reactor = scheduler.reactor
            defer = reactor.defer

            # Record a backtrace of where the schedule was created
            @trace = caller

            # Setup common event variables
            @scheduler = scheduler
            @created = reactor.now
            @last_scheduled = @created
            @trigger_count = 0

            # init the promise
            super(reactor, defer)
        end

        # Provide relevant inspect information
        def inspect
            insp = String.new("#<#{self.class}:#{"0x00%x" % (self.__id__ << 1)} ")
            insp << "trigger_count=#{@trigger_count} "
            insp << "config=#{info} " if self.respond_to?(:info, true)
            insp << "next_scheduled=#{to_time(@next_scheduled)} "
            insp << "last_scheduled=#{to_time(@last_scheduled)} created=#{to_time(@created)}>"
            insp
        end
        alias_method :to_s, :inspect

        def to_time(internal_time)
            if internal_time
                ((internal_time + @scheduler.time_diff) / 1000).to_i
            end
        end


        # required for comparable
        def <=>(anOther)
            @next_scheduled <=> anOther.next_scheduled
        end

        # reject the promise
        def cancel
            @defer.reject(:cancelled)
        end

        # notify listeners of the event
        def trigger
            @trigger_count += 1
            @defer.notify(@reactor.now, self)
        end
    end

    class OneShot < ScheduledEvent
        def initialize(scheduler, at)
            super(scheduler)

            @next_scheduled = at
        end

        # Updates the scheduled time
        def update(time)
            @last_scheduled = @reactor.now

            parsed_time = Scheduler.parse_in(time, :quiet)
            if parsed_time.nil?
                # Parse at will throw an error if time is invalid
                parsed_time = Scheduler.parse_at(time) - @scheduler.time_diff
            else
                parsed_time += @last_scheduled
            end

            @next_scheduled = parsed_time
            @scheduler.reschedule(self)
        end

        # Runs the event and cancels the schedule
        def trigger
            super()
            @defer.resolve(:triggered)
        end
    end

    class Repeat < ScheduledEvent
        def initialize(scheduler, every)
            super(scheduler)

            @every = every
            next_time
        end

        # Update the time period of the repeating event
        #
        # @param schedule [String] a standard CRON job line or a human readable string representing a time period.
        def update(every, timezone: nil)
            time = Scheduler.parse_in(every, :quiet) || Scheduler.parse_cron(every, :quiet, timezone: timezone)
            raise ArgumentError.new("couldn't parse \"#{o}\"") if time.nil?

            @every = time
            reschedule
        end

        # removes the event from the schedule
        def pause
            @paused = true
            @scheduler.unschedule(self)
        end

        # reschedules the event to the next time period
        # can be used to reset a repeating timer
        def resume
            @paused = false
            @last_scheduled = @reactor.now
            reschedule
        end

        # Runs the event and reschedules
        def trigger
            super()
            @reactor.next_tick do
                # Do this next tick to avoid needless scheduling
                # if the event is stopped in the callback
                reschedule
            end
        end


        protected


        def next_time
            @last_scheduled = @reactor.now
            if @every.is_a? Integer
                @next_scheduled = @last_scheduled + @every
            else
                # must be a cron
                @next_scheduled = (@every.next.to_f * 1000).to_i - @scheduler.time_diff
            end
        end

        def reschedule
            unless @paused
                next_time
                @scheduler.reschedule(self)
            end
        end

        def info
            "repeat:#{@every.inspect}"
        end
    end


    class Scheduler
        attr_reader :reactor
        attr_reader :time_diff
        attr_reader :next


        def initialize(reactor)
            @reactor = reactor
            @schedules = Set.new
            @scheduled = []
            @next = nil     # Next schedule time
            @timer = nil    # Reference to the timer

            # Not really required when used correctly
            @critical = Mutex.new

            # Every hour we should re-calibrate this (just in case)
            calibrate_time

            @calibrate = @reactor.timer do
                calibrate_time
                @calibrate.start(3600000)
            end
            @calibrate.start(3600000)
            @calibrate.unref
        end


        # As the libuv time is taken from an arbitrary point in time we
        #  need to roughly synchronize between it and ruby's Time.now
        def calibrate_time
            @reactor.update_time
            @time_diff = (Time.now.to_f * 1000).to_i - @reactor.now
        end

        # Create a repeating event that occurs each time period
        #
        # @param time [String] a human readable string representing the time period. 3w2d4h1m2s for example.
        # @param callback [Proc] a block or method to execute when the event triggers
        # @return [::UV::Repeat]
        def every(time)
            ms = Scheduler.parse_in(time)
            event = Repeat.new(self, ms)
            event.progress &Proc.new if block_given?
            schedule(event)
            event
        end

        # Create a one off event that occurs after the time period
        #
        # @param time [String] a human readable string representing the time period. 3w2d4h1m2s for example.
        # @param callback [Proc] a block or method to execute when the event triggers
        # @return [::UV::OneShot]
        def in(time)
            ms = @reactor.now + Scheduler.parse_in(time)
            event = OneShot.new(self, ms)
            event.progress &Proc.new if block_given?
            schedule(event)
            event
        end

        # Create a one off event that occurs at a particular date and time
        #
        # @param time [String, Time] a representation of a date and time that can be parsed
        # @param callback [Proc] a block or method to execute when the event triggers
        # @return [::UV::OneShot]
        def at(time)
            ms = Scheduler.parse_at(time) - @time_diff
            event = OneShot.new(self, ms)
            event.progress &Proc.new if block_given?
            schedule(event)
            event
        end

        # Create a repeating event that uses a CRON line to determine the trigger time
        #
        # @param schedule [String] a standard CRON job line.
        # @param callback [Proc] a block or method to execute when the event triggers
        # @return [::UV::Repeat]
        def cron(schedule, timezone: nil)
            ms = Scheduler.parse_cron(schedule, timezone: timezone)
            event = Repeat.new(self, ms)
            event.progress &Proc.new if block_given?
            schedule(event)
            event
        end

        # Schedules an event for execution
        #
        # @param event [ScheduledEvent]
        def reschedule(event)
            # Check promise is not resolved
            return if event.resolved?

            @critical.synchronize {
                # Remove the event from the scheduled list and ensure it is in the schedules set
                if @schedules.include?(event)
                    remove(event)
                else
                    @schedules << event
                end

                # optimal algorithm for inserting into an already sorted list
                Bisect.insort(@scheduled, event)

                # Update the timer
                check_timer
            }
        end

        # Removes an event from the schedule
        #
        # @param event [ScheduledEvent]
        def unschedule(event)
            @critical.synchronize {
                # Only call delete and update the timer when required
                if @schedules.include?(event)
                    @schedules.delete(event)
                    remove(event)
                    check_timer
                end
            }
        end


        private


        # Remove an element from the array
        def remove(obj)
            position = nil

            @scheduled.each_index do |i|
                # object level comparison
                if obj.equal? @scheduled[i]
                    position = i
                    break
                end
            end

            @scheduled.slice!(position) unless position.nil?
        end

        # First time schedule we want to bind to the promise
        def schedule(event)
            reschedule(event)

            event.finally do
                unschedule event
            end
        end

        # Ensures the current timer, if any, is still
        # accurate by checking the head of the schedule
        def check_timer
            @reactor.update_time

            existing = @next
            schedule = @scheduled.first
            @next = schedule.nil? ? nil : schedule.next_scheduled

            if existing != @next
                # lazy load the timer
                if @timer.nil?
                    new_timer
                else
                    @timer.stop
                end

                if not @next.nil?
                    in_time = @next - @reactor.now

                    # Ensure there are never negative start times
                    if in_time > 3
                        @timer.start(in_time)
                    else
                        # Effectively next tick
                        @timer.start(0)
                    end
                end
            end
        end

        # Is called when the libuv timer fires
        def on_timer
            @critical.synchronize {
                schedule = @scheduled.shift
                @schedules.delete(schedule)
                schedule.trigger

                # execute schedules that are within 3ms of this event
                # Basic timer coalescing..
                now = @reactor.now + 3
                while @scheduled.first && @scheduled.first.next_scheduled <= now
                    schedule = @scheduled.shift
                    @schedules.delete(schedule)
                    schedule.trigger
                end
                check_timer
            }
        end

        # Provide some assurances on timer failure
        def new_timer
            @timer = @reactor.timer { on_timer }
            @timer.finally do
                new_timer
                unless @next.nil?
                    @timer.start(@next)
                end
            end
        end
    end
end
