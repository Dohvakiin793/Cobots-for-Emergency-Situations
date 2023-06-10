--
-- Code for line following scenario
--
--
require "snake"
require "keyboard"
require "manual-control"



--
-- In this scenario the snake follows a line to retrieve some objects 
-- located at the other end and brings them back to drop zones located at the starting
-- position. The target object and drop zones have the same color. There is one
-- drop zone for each target object.
--
function FollowLineAndRetrieveObjectsScenario()

    local snake = Snake:new{joint_count=7}
    local keyboard = KeyboardControl:new()

    local planner = FollowLineAndRetrieveObjectsPlanner(snake, keyboard)


    return function(sim_call)

        local time_step = simGetSimulationTimeStep()
	--print('LOLOLOLOLO')
        --if(sim_call == sim_childscriptcall_actuation) then
	keyboard:read_simulator_messages()
	snake:update(time_step)
        --elseif(sim_call == sim_childscriptcall_cleanup) then
        --    snake:cleanup()
        --end

    end

end




--
-- The planner that implements the autonomous behaviour for this scenario.
--
function FollowLineAndRetrieveObjectsPlanner(snake, keyboard)

    local planner = {}


    -- TODO: Some of these handlers are very similar, only differing by which 
    -- state to continue into after an event occur. This can probably be 
    -- improved by storing the next state in som variables and updating 
    -- theses as appropriate.
    --
    local do_follow_line
    local do_move_to_object
    local do_drop_object
    local do_move_to_drop_zone
    local do_reset_for_restart
    local do_rescue_object
    local do_simple_search
    local do_pre_grasp_movement
    local do_grap_object
    local do_idle
    local do_start


    local LINE_COLOR = Blob.BLUE

    -- The targets object the snake should find and bring back.
    -- They are found in the order they appear in the table.
    local targets = {
        {
            handle = simGetObjectHandle('Cuboid2'),
            color = Blob.GREEN,
            --print('heloooo')	
        }

    }

    local line_target = {
        handle = nil,
        color = LINE_COLOR,
    }

    local current_target = targets[1]

    local logic = GlobalLogic({}) -- There is currently no global logic but we create this just in case.


    local manual_control = ManualControl(snake, keyboard, planner)

    manual_control:set_line_color(LINE_COLOR)
    manual_control:set_current_target(current_target)

    -- Start in manual mode
    manual_control:toggle_manual()

    --
    -- Start the scenario
    --
    function do_start()
        do_simple_search()
    end


    --
    -- Stop the snake and do nothing
    --
    function do_idle()
        snake:stop_movement()
        snake:set_idle()
    end



    --
    -- Follow the line until the line is lost or the target is found
    --
    function do_follow_line()
        
        local look = LookForBlobLogic(snake, {target=current_target})
        look:add_event_listener(Event.FOUND_BLOB, do_move_to_object)

        local follow = LineFollowingLogic(snake, {line_color=LINE_COLOR})
        follow:add_event_listener(Event.LOST_LINE, do_simple_search)

        logic:set(snake, LogicCombination{look, follow})

        return true
    end


    --
    -- Move towards the object until we the object is in front of the snake.
    --
    function do_move_to_object()
        
        local follow = FollowObjectLogic(snake, {target=current_target})

        follow:add_event_listener(Event.REACHED_OBJECT, do_pre_grasp_movement)
        follow:add_event_listener(Event.LOST_OBJECT, do_simple_search)

        logic:set(snake, follow)

        return true

    end


    -- 
    -- Search left and right for the object and then move forwards or backwards 
    -- a little bit. This is repeated until the line or the target is found. 
    --
    -- The direction to search:
    -- data.move_direction = Snake.DIRECTION_FORWARDS | Snake.DIRECTION_BACKWARDS
    -- data.search_step = 1|-1, the number to add to the turning factor on each update
    --
    function do_simple_search(data)

        data = data or {}

        local find_object = LookForBlobLogic(snake, {target=current_target})
        find_object:add_event_listener(Event.FOUND_BLOB, do_move_to_object)

        local find_line = LookForBlobLogic(snake, {target=line_target})
        find_line:add_event_listener(Event.FOUND_BLOB, do_follow_line)

        local move = SimpleSearchMovementLogic(snake, {move_direction=data.move_direction or nil,
                                                       initial_search_step=data.search_step or nil})

        logic:set(snake, LogicCombination{find_object, find_line, move})

        return true

    end



    -- 
    -- Get the object into a good location for grasping.
    --
    function do_pre_grasp_movement()

        local pre_grasp = PreGraspingLogic(snake, {target=current_target})

        pre_grasp:add_event_listener(Event.DONE, do_grasp_object)
        pre_grasp:add_event_listener(Event.LOST_OBJECT, function()
            -- We know the object was in front of us so we searches for it while moving backwards.
            return do_simple_search({move_direction=Snake.DIRECTION_BACKWARDS})
        end)

        logic:set(snake, pre_grasp)

        return true

    end


    --
    -- Do the grasping sequence.
    -- 
    function do_grasp_object()

        local grasp = GraspingSequenceLogic(snake, {target=current_target})

        grasp:add_event_listener(Event.DONE, do_find_line)
        grasp:add_event_listener(Event.LOST_OBJECT, function()
            -- We know the object was in front of us so we searches for it while moving backwards.
            do_simple_search({move_direction=Snake.DIRECTION_BACKWARDS})
        end)

        logic:set(snake, grasp)
        return true
    end



    --
    -- Search for the line after the object has been grasped.
    --
    function do_find_line()

        local look = LookForBlobLogic(snake, {target=line_target})
        look:add_event_listener(Event.FOUND_BLOB, do_rescue_object)

        local rotate = RotateSnakeLogic(snake, {direction=Snake.DIRECTION_LEFT})

        logic:set(snake, LogicCombination{look, rotate})

        return true

    end



    --
    -- Follow the line back until we find the drop zone.
    --
    function do_rescue_object(data)

        data = data or {}

        local find_dropzone = LookForBlobLogic(snake, {target=current_target})
        find_dropzone:add_event_listener(Event.FOUND_BLOB, do_move_to_drop_zone)

        local follow_line = LineFollowingLogic(snake, {line_color=LINE_COLOR})
        follow_line:add_event_listener(Event.LOST_LINE, function(event)

            local search_step = 1
            -- FIXME: Set the search direction based on the position
            -- of the line last time it was found.
            -- if(event.data.line_position == Snake.DIRECTION_LEFT) then
            --     search_step = -1
            -- end

            local find_dropzone = LookForBlobLogic(snake, {target=current_target})
            find_dropzone:add_event_listener(Event.FOUND_BLOB, do_move_to_drop_zone)

            local find_line = LookForBlobLogic(snake, {target=line_target})
            find_line:add_event_listener(Event.FOUND_BLOB, do_rescue_object)

            local move = SimpleSearchMovementLogic(snake, {initial_search_step=search_step})

            logic:set(snake, LogicCombination{find_dropzone, find_line, move})

            return true

        end)

            
        logic:set(snake, LogicCombination{find_dropzone, follow_line})

        return true
            
    end

    --
    -- Move towards the drop zone until the drop zone is in front of the snake.
    --
    function do_move_to_drop_zone()

        
        local follow = FollowObjectLogic(snake, {target=current_target,
                                                 set_point=0.7,
                                                 width_threshold=0.5,
                                                 height_threshold=0.3})

        follow:add_event_listener(Event.REACHED_OBJECT, do_drop_object)

        follow:add_event_listener(Event.LOST_OBJECT, function()

            local find_dropzone = LookForBlobLogic(snake, {target=current_target})
            find_dropzone:add_event_listener(Event.FOUND_BLOB, do_move_to_drop_zone)
            
            local move = SimpleSearchMovementLogic(snake, {})

            logic:set(snake, LogicCombination{find_dropzone, move})

            return true
            
        end)


        logic:set(snake, follow)

        return true

    end



    --
    -- Drop the object at the drop zone
    -- 
    function do_drop_object()

        local drop = DropObjectLogic(snake, {target=current_target})

        drop:add_event_listener(Event.DONE, do_reset_for_restart)

        logic:set(snake, drop)

        return true
    end



    -- 
    -- Restart the sequence to get the next target object in the targets 
    -- list. If there is no more object the snake goes into idle state.
    --
    function do_reset_for_restart()

        --Remove the old target
        --table.remove(targets, 1)

        --if(next(targets) == nil)  then
        --    --No more targets so we are done
        --    do_idle()
        --    manual_control:set_current_target(nil)
        --    return
        --end

        -- Set the next target.
        -- current_target = targets[1]

        manual_control:set_current_target(current_target)

        -- Find the line again before we restart.
        local find_line = LookForBlobLogic(snake, {target=line_target})

        find_line:add_event_listener(Event.FOUND_BLOB, function()
            return do_simple_search({search_step=-1})
        end)

        local rotate = RotateSnakeLogic(snake, {direction=Snake.DIRECTION_LEFT})

        logic:set(snake, LogicCombination{find_line, rotate})

        return true

    end


    function planner:start()
        do_start()
    end


    return planner

end


