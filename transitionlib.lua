--
-- Helper object for creating smooth transitions for the snakes movement.
--


TransitionValue = {}
--
-- Transitions a value from one value to another.
--
-- Duration is in seconds. Pause is a delay that is added after the transition 
-- is finised. The is_done method will not return true until pause time has 
-- passed since the transition ended.
--
function TransitionValue:new(start_value, end_value, duration, easing_func, pause)
    local object = {}
    object._duration = duration
    object._start_value = start_value
    object._end_value = end_value
    object._current_time = 0
    object._pause = pause or 0
    object._easing_func = easing_func or EasingFunc.cubic_ease_out


    object.value = start_value -- the current value of the transition

    setmetatable(object, self)
    self.__index = self
    return object
end

--
-- Updates the transition.
-- This must be called repeatedly with the time since the last call to update.
--
function TransitionValue:update(timedelta)

    self._current_time = self._current_time + timedelta

    if(self._current_time >= self._duration) then
        self.value = self._end_value
    else
        self.value = self._easing_func(self._start_value, self._end_value - self._start_value, self._current_time, self._duration)
    end

end

--
-- Returns true if the transition is done.
--
function TransitionValue:is_done()
    return self._current_time >= (self._duration + self._pause)
end





--
-- Transitions the snakes parameters from one value to another.
--
SnakeTransition = {}

function SnakeTransition:new(snake, new_params, duration, easing_func, pause)
    local object = {}

    object._snake = snake

    local _transitions = {}
    for param, value in pairs(new_params) do
        _transitions[param] = TransitionValue:new(snake["_"..param], value, duration, easing_func, pause)
    end
    object._transitions = _transitions

    setmetatable(object, self)
    self.__index = self
    return object
end

--
-- Updates the transition.
-- This should be called repeatedly with the time since the last call to update.
--
function SnakeTransition:update(timedelta)

    for param, transition in pairs(self._transitions) do
        transition:update(timedelta)
        self._snake["_"..param] = transition.value
    end

end

--
-- Returns true if the transition is done.
--
function SnakeTransition:is_done()
    for _, transition in pairs(self._transitions) do
        if(not transition:is_done()) then
            return false
        end
    end
    return true
end





TableTransition = {}

---
-- Transition the values in two tables from one to the other. The tables 
-- must have the same sice.
--
function TableTransition:new(start_table, end_table, duration, easing_func, pause)
    local object = {}
    object._start_table = start_table
    object._pause = pause

    local transitions = {}
    for i, row in pairs(start_table) do
        transitions[i] = TransitionValue:new(start_table[i], end_table[i], duration, easing_func, pause)
    end
    object._transitions = transitions

    setmetatable(object, self)
    self.__index = self

    return object
end

--
-- Update the transition
--
function TableTransition:update(time) 
    for _, transition in pairs(self._transitions) do
        transition:update(time)
    end
end


--
-- Returns the current table values
--
function TableTransition:current() 
    local values = {}
    for i, transition in pairs(self._transitions) do
        values[i] = transition.value
    end
    return values
end


--
-- Returns true if the transition is done.
--
function TableTransition:is_done() 
    for i, transition in pairs(self._transitions) do
        if(not transition:is_done()) then
            return false
        end
    end
    return true
end




--
-- Easing functions are used to control how the values transitions
-- between its values.
--
-- Each function takes the following parameters:
--
-- value_delta: he diff between the start and end value. (end_value - start_value).
-- time: the current time. range 0 - duration.
-- duration: the duration of the transition.
--
EasingFunc = {}

--
-- Cubic ease in and out transition function.
-- Starts slowly, moves faster and then slowly stops.
function EasingFunc.cubic_ease_in_out(start_value, value_delta, time, duration)
    time = time / (duration / 2)
    if(time < 1) then
        return value_delta/2*time*time*time + start_value
    end
    time = time - 2
    return value_delta/2*(time*time*time + 2) + start_value

end

--
-- Cubic ease out transition function.
-- Starts fast and slowly stops.
--
function EasingFunc.cubic_ease_out(start_value, value_delta, time, duration)
    time = time / duration
    time = time - 1
    return value_delta*(time*time*time + 1) + start_value

end

--
-- Changes the value linearly from the start to the end value
--
function EasingFunc.linear_easing(start_value, value_delta, time, duration)
    return value_delta*time/duration + start_value
end


