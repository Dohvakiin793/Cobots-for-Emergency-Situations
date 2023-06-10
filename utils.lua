--
-- Utility functions
--

utils = {}

--
-- Creates a function that calculates running average of the last num numbers.
--
-- The returned function should be called with a number and returns the average of the numbers
-- from the previous calls.
--
function utils.make_running_average(num) 
    local t = {}
    local function f(a, b, ...) if b then return f(a+b, ...) else return a end end
    local function average(n)
        if #t == num then table.remove(t, 1) end
        t[#t + 1] = n
        return f(unpack(t)) / #t
    end
    return average
end



--
-- Creates a function that calculates running sum of the last num numbers
--
-- The returned function should be called with a number and returns the sum of the numbers
-- from the previous calls.
--
function utils.make_running_sum(num) 
    local t = {}
    local function f(a, b, ...) if b then return f(a+b, ...) else return a end end
    local function sum(n)
        if #t == num then table.remove(t, 1) end
        t[#t + 1] = n
        return f(unpack(t))
    end
    return sum
end



--
-- Creates a function that returns values cycling through a specific range.
--
function utils.make_range_cycler(start_value, end_value, initial_value, step_size) 

    local cycler = {cycle_count=0, value=initial_value, step=step_size}
    
    local init_value_count = 0

    cycler.update = function()
        cycler.value = cycler.value + cycler.step
        if(cycler.value >= end_value) then
            cycler.value = end_value
            cycler.step = cycler.step*-1
        elseif(cycler.value <= start_value) then
            cycler.value = start_value
            cycler.step = cycler.step*-1
        end

        if(cycler.value == initial_value) then
            init_value_count = init_value_count + 1
            if((initial_value == start_value or initial_value == end_value) and init_value_count == 1) then
                cycler.cycle_count = cycler.cycle_count + 1
                init_value_count = 0
            elseif(init_value_count == 2) then
                cycler.cycle_count = cycler.cycle_count + 1
                init_value_count = 0
            end
        end

        return cycler.value
    end

    cycler.reset = function()
        cycler.cycle_count = 0
        cycler.value = initial_value
        init_value_count = 0
    end
    return cycler
end




--
-- Makes a object for controlling the snake's bending table
-- 
function utils.make_bend_controller(snake, bending_table, params) 

    local params = params or {}
    local initial_bend = snake.bending_table
    local initial_dampening
    local bender = {current=initial_bend}


    -- Check that the table is not exceeding the bending table values
    function _check_table(bend)
        for i, value in ipairs(bend) do
            if(math.abs(bend[i]) > math.abs(bending_table[i])) then
                bend[i] = bending_table[i] * utils.sign(bend[i])
            end
        end
        return bend
    end

    function bender:set(bending_factor)

        local bend = self:get(bending_factor)

        snake:set_bending_table(bend)

    end

    function bender:get(bending_factor)
        bending_factor = math.max(bending_factor, -100)
        bending_factor = math.min(bending_factor, 100)

        local bend = utils.table_multiply(bending_table, bending_factor/100)

        -- Reduce the values from the initial bend
        initial_bend = utils.table_multiply_table(initial_bend, initial_dampening)

        bend = utils.table_add(initial_bend, bend)

        bend = _check_table(bend)

        self.current = bend

        return bend
    end

    function bender:set_dampening(dampening)
        local d = {}
        for i=1,7,1 do 
            d[i] = dampening
        end
        initial_dampening = d
    end

    function bender:set_dampening_table(dampening)
        initial_dampening = dampening
    end

    bender:set_dampening( params.initial_dampening or 0.95 )
    return bender
end



-- Returns a new bending table. Converting the provided
-- values from degrees to radians.
function utils.bending_deg(bending_table)

    local new = {}
    for i=1,#bending_table,1 do
        new[i] = to_rads(bending_table[i])
    end
    return new

end


-- Multiplies the values in table by factor and
-- returns a new table.
function utils.table_multiply(table, factor) 
    local new = {}
    for i,value in pairs(table) do
        new[i] = value*factor
    end
    return new
end

-- Multiplies the values in table1 by the corresponding value in table2 and
-- returns a new table.
function utils.table_multiply_table(table1, table2) 
    local new = {}
    for i in pairs(table1) do
        new[i] = table1[i]*table2[i]
    end
    return new
end

-- Adds the values in table1 by the corresponding value in table2 and
-- returns a new table.
function utils.table_add(table1, table2) 
    local new = {}
    for i in pairs(table1) do
        new[i] = table1[i] + table2[i]
    end
    return new
end


--
-- Returns a timer object. The timer should be updated 
-- by calling the update method.
--
function utils.make_timer() 

    local timer = {value = 0}

    timer.update = function(timer, time_step)
       timer.value = timer.value + math.abs(time_step)
    end

    timer.reset = function(timer)
       timer.value = 0
    end

    return timer
end


-- Creates a timeout object that will call the callback 
-- after delay seconds.
--
-- The timeout object must be called repeatedly on each update with the time_step
-- value.
--
function utils.make_timeout(callback, delay) 

    local timer = utils.make_timer()
    
    local done = false

    local timeout = {}

    local timeout_meta = {
        __call = function(_, time_step)
            timer:update(time_step)
            if(not done and timer.value >= delay) then
                callback()
                done = true
            end
            return done
        end
    }
    

    function timeout.cancel()
        done = true
    end

    setmetatable(timeout, timeout_meta)

    return timeout
end





-- Implements a proportional-integral-derivative controller.
-- Currently the integral is not implemented.
-- 
function utils.make_pid_controller(args) 

    local set_point = args.set_point
    local pk = args.proportional_gain or 0
    local kd = args.derivative_gain or 0
    local prev_err = 0

    local pid = {output=0}

    function pid:update(process_variable)
        local err = process_variable - set_point
        local out = err * pk + kd*(err - prev_err)
        prev_err = err
        pid.output = out
        return out
    end

    return pid
end


-- 
-- Create a helper to read the force from the snakes horizontal joints.
--
-- The update method should be called repeatedly.
-- The forces can be read from the force[joint_nr] and derivative[joint_nr] attiributes.
--
function utils.make_joint_force_reader(snake)

    local force_average = {}
    local derivative_average = {}

    for i=1,snake.joint_count,1 do
        force_average[i] = utils.make_running_average(3)
        derivative_average[i] = utils.make_running_average(3)
    end

    local reader = {force={}, derivative={}}

    function reader:update(time_step)

        for i=1, snake.joint_count, 1 do

            local prev_value = self.force[i] or 0
            local force = force_average[i](simGetJointForce(snake.joints_horizontal[i]))
            local derivative = derivative_average[i]((force - prev_value) / time_step)

            self.derivative[i] = derivative
            self.force[i] = force
        end

    end

    return reader
end


-- Returns the sign of a number
function utils.sign(x)
  return (x<0 and -1) or 1
end




--
-- Converts degrees to radians
--
function to_rads(degrees)
    return degrees * math.pi / 180
end

