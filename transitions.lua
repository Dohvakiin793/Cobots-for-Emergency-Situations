-- 
-- Helper functions for createing transitions. The functions returns
-- a update function that should be called repeatedly with 
-- the time_step to make the transtion progress. 
--

require "transitionlib"

transitions = {}



local function _transition_updater(tr, on_finished, on_update)

    return function(time_step)
        tr:update(time_step)
        if(on_update ~= nil) then
            on_update(time_step)
        end
        if(tr:is_done() and on_finished ~= nil) then
            on_finished()
        end
        return tr:is_done()
    end

end

--
-- Sets a global transtion. This will suspend the current logic
-- until the transition is done.
--
function transitions.set_global(snake, transition_update)
    snake:set_suspend_logic(true)
    snake:add_update_listener(function(time_step)
        local done = transition_update(time_step)
        if(done) then
            snake:set_suspend_logic(false)
        end
        return done
    end)

end

--
-- Create a new bend transtion that will transition the snake into 
-- the new_bending position.
--
function transitions.bend_transition(snake, new_bending, params, on_finished)

    params = params or {}


    local tr = TableTransition:new(snake:get_current_bending_table(), new_bending, params.duration or 3, 
                EasingFunc.linear_easing, params.pause or 0)


    return _transition_updater(tr, on_finished, function(time_step)
        snake:set_bending_table(tr:current())
    end)

end


--
-- Smoothly stops the snake's movements
--
function transitions.smoothly_stop_snake(snake, params, on_finished)

    params = params or {}

    local tr = SnakeTransition:new(snake, {amplitude_vertical=0}, params.duration or 3,
                EasingFunc.linear_easing, params.pause or 0)

    return _transition_updater(tr, on_finished)
end


--
-- Smoothly starts the snake's movements
--
function transitions.smoothly_start_snake(snake, params, on_finished)

    params = params or {}

    local tr = SnakeTransition:new(snake, {amplitude_vertical=to_rads(40)}, params.duration or 3,
                EasingFunc.linear_easing, params.pause or 0)


    return _transition_updater(tr, on_finished)

end



--
-- Smoothly Straightens the snake.
--
function transitions.smoothly_straighten_snake(snake, params, on_finished)

    params = params or {}

    local tr = SnakeTransition:new(snake, {amplitude_horizontal=0}, params.duration or 3,
                EasingFunc.linear_easing, params.pause or 0)

    local tr2 = transitions.bend_transition(snake, {0, 0, 0, 0, 0, 0, 0}, params)


    return _transition_updater(tr, on_finished, tr2)

end



