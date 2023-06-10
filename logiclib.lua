--
-- Helper functions and objects for the logic.
--

--
-- Event constants
--
Event =  {
    LOST_LINE = 1,
    FOUND_BLOB = 2,
    REACHED_OBJECT = 3,
    FOUND_LINE = 4,
    LOST_OBJECT = 5,
    DONE = 7,
    WALL_HIT = 8,
    TIMEOUT = 9,
}


--
-- Creates a new event object.
--
function Event:new(data)

    local event = {data=data}

    return event

end





--
-- Creates a logic handler which should implement logic for the snake.
-- Other code can listen for event by adding event listeners using the
-- add_event_listener method. 
--
-- If an event listener returns true, the logic handler is set to stop_propagation
-- mode. This will prevent any further event handlers to be triggered. If the logic 
-- handler is part of a LogicCombination this will also prevent other logic handlers
-- preceeding this handler to be executed. This state can be reset by calling the 
-- reset methid.
--
function LogicHandler(handler)

    local logic = {}

    local listeners = {}
    local meta = {}

    local stop_propagation = false


    function logic:add_event_listener(event, listener)
        if(listeners[event] == nil) then
            listeners[event] = {}
        end
        table.insert(listeners[event], listener)
    end


    -- Notify listeners of an event
    function logic:notify(event, data)

        if(listeners[event] == nil) then
            return
        end
        
        local e = Event:new(data)

        for _, listener in ipairs(listeners[event]) do
            if(listener(e)) then
                stop_propagation = true
                return
            end
        end
    end

    function logic:reset()
        stop_propagation = false
    end


    -- Make the logic handler callable.
    function meta.__call(_, time_step, time)
        handler(logic, time_step, time)
        if(stop_propagation) then
            return true
        end
    end

    setmetatable(logic, meta)

    return logic

end




--
-- Combines multiple logic handler in the logic_handler table 
-- and call them in the order they have in the table.
--
-- This has the same callable interface as the logic handlers.
--
function LogicCombination(logic_handlers)

    return function(time_step, time) 
        for _, handler in ipairs(logic_handlers) do
            if(handler(time_step, time)) then
                -- Stop if the handler returns true
                return true
            end
        end
    end
end



--
-- Used to add global handlers that are always active
--
function GlobalLogic(global_handlers)

    local combination = {}

    function combination:add_global(handler)
        table.insert(global_handlers, handler)
    end

    -- Sets the current logic handler and combines it with 
    -- any global handlers that are registered.
    function combination:set(snake, handler)
        snake:set_logic_handler(LogicCombination({
            LogicCombination(global_handlers),
            handler,
        }))
    end


    return combination

end



