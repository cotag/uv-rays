
module UV

    class ScheduledEvent < ::Libuv::Q::DeferredPromise
        include Comparable

        attr_reader :created
        attr_reader :last_scheduled
        attr_reader :next_scheduled
        attr_reader :trigger_count

        def initialize(scheduler)
            # Create a dummy deferrable
            loop = scheduler.loop
            defer = loop.defer

            # Setup common event variables
            @scheduler = scheduler
            @created = loop.now
            @last_scheduled = @created
            @trigger_count = 0

            # init the promise
            super(loop, defer)
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
            @defer.notify(@loop.now, self)
        end
    end

    class OneShot < ScheduledEvent
        def initialize(scheduler, at)
            super(scheduler)

            @next_scheduled = at
        end

        # Updates the scheduled time
        def update(time)
            @last_scheduled = @loop.now

            
            parsed_time = parse_in(time, :quiet)
            if parsed_time.nil?
                # Parse at will throw an error if time is invalid
                parsed_time = parse_at(time) - @scheduler.time_diff
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
        def update(every)
            time = parse_in(every, :quiet) || parse_cron(every, :quiet)
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
            reschedule
        end

        # Runs the event and reschedules
        def trigger
            super()
            @loop.next_tick do
                # Do this next tick to avoid needless scheduling
                # if the event is stopped in the callback
                reschedule
            end
        end


        protected


        def next_time
            @last_scheduled = @loop.now
            if @every.is_a? Fixnum
                @next_scheduled = @last_scheduled + @every
            else
                # must be a cron
                @next_scheduled = (@every.next_time.to_f * 1000).to_i - @scheduler.time_diff
            end
        end

        def reschedule
            if not @paused
                next_time
                @scheduler.reschedule(self)
            end
        end
    end


    class Scheduler
        attr_reader :loop
        attr_reader :time_diff


        def initialize(loop)
            @loop = loop
            @schedules = Set.new
            @scheduled = []
            @next = nil     # Next schedule time
            @timer = nil    # Reference to the timer
            @timer_callback = method(:on_timer)

            # as the libuv time is taken from an arbitrary point in time we
            # need to roughly synchronize between it and ruby's Time.now
            @loop.update_time
            @time_diff = (Time.now.to_f * 1000).to_i - @loop.now
        end


        # Create a repeating event that occurs each time period
        #
        # @param time [String] a human readable string representing the time period. 3w2d4h1m2s for example.
        # @param callback [Proc] a block or method to execute when the event triggers
        # @return [::UV::Repeat]
        def every(time, callback = nil, &block)
            callback ||= block
            ms = Scheduler.parse_in(time)
            event = Repeat.new(self, ms)

            if callback.respond_to? :call
                event.progress callback
            end
            schedule(event)
            event
        end

        # Create a one off event that occurs after the time period
        #
        # @param time [String] a human readable string representing the time period. 3w2d4h1m2s for example.
        # @param callback [Proc] a block or method to execute when the event triggers
        # @return [::UV::OneShot]
        def in(time, callback = nil, &block)
            callback ||= block
            ms = @loop.now + Scheduler.parse_in(time)
            event = OneShot.new(self, ms)

            if callback.respond_to? :call
                event.progress callback
            end
            schedule(event)
            event
        end

        # Create a one off event that occurs at a particular date and time
        #
        # @param time [String, Time] a representation of a date and time that can be parsed
        # @param callback [Proc] a block or method to execute when the event triggers
        # @return [::UV::OneShot]
        def at(time, callback = nil, &block)
            callback ||= block
            ms = Scheduler.parse_at(time) - @time_diff
            event = OneShot.new(self, ms)

            if callback.respond_to? :call
                event.progress callback
            end
            schedule(event)
            event
        end

        # Create a repeating event that uses a CRON line to determine the trigger time
        #
        # @param schedule [String] a standard CRON job line.
        # @param callback [Proc] a block or method to execute when the event triggers
        # @return [::UV::Repeat]
        def cron(schedule, callback = nil, &block)
            callback ||= block
            ms = Scheduler.parse_cron(time)
            event = Repeat.new(self, ms)

            if callback.respond_to? :call
                event.progress callback
            end
            schedule(event)
            event
        end

        # Schedules an event for execution
        #
        # @param event [ScheduledEvent]
        def reschedule(event)
            # Check promise is not resolved
            return if event.resolved?

            # Remove the event from the scheduled list and ensure it is in the schedules set
            if @schedules.include?(event)
                @scheduled.delete(event)
            else
                @schedules << event
            end

            # optimal algorithm for inserting into an already sorted list
            Bisect.insort(@scheduled, event)

            # Update the timer
            check_timer
        end

        # Removes an event from the schedule
        #
        # @param event [ScheduledEvent]
        def unschedule(event)
            # Only call delete and update the timer when required
            if @schedules.include?(event)
                @schedules.delete(event)
                @scheduled.delete(event)
                check_timer
            end
        end


        private


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
            existing = @next
            schedule = @scheduled.first
            @next = schedule.nil? ? nil : schedule.next_scheduled

            if existing != @next
                # lazy load the timer
                if @timer.nil?
                    @timer = @loop.timer @timer_callback
                else
                    @timer.stop
                end

                if not @next.nil?
                    @timer.start(@next - @loop.now)
                end
            end
        end

        # Is called when the libuv timer fires
        def on_timer
            schedule = @scheduled.shift
            schedule.trigger

            # execute schedules that are within 30ms of this event
            # Basic timer coalescing..
            now = @loop.now + 30
            while @scheduled.first && @scheduled.first.next_scheduled <= now
                schedule = @scheduled.shift
                schedule.trigger
            end
            check_timer
        end
    end
end

module Libuv
    class Loop
        def scheduler
            @scheduler ||= UV::Scheduler.new(@loop)
            @scheduler
        end
    end
end
