--
-- Code for manually controlling some tasks
--


--
-- Key codes
--
local KEY_TOGGLE_MANUAL = 77     -- Capital m
local KEY_DROP_OBJECT = 68       -- Capital D
local KEY_GRASP_OBJECT = 71      -- Capital G
local KEY_IDLE = 73              -- Capital I
local KEY_FOLLOW_LINE = 76       -- Capital L
local KEY_TRACK_OBJECT = 79      -- Capital O
local KEY_PRE_GRASP = 80         -- Capital P

local KEY_MOVE_FORWARDS = 2007             -- up arrow
local KEY_MOVE_BACKWARDS = 2008            -- down arrow
local KEY_LEFT = 2009                      -- left arrow
local KEY_RIGHT = 2010                     -- right arrow


local KEY_ENABLE_TURNING_MODE = 116         -- Lower case t
local KEY_ENABLE_EDGING_MODE = 101          -- Lower case e
local KEY_ENABLE_SIDE_WINDING_MODE = 115    -- Lower case s
local KEY_ENABLE_ROTATION_MODE = 111        -- Lower case o
local KEY_ENABLE_ROLLING_MODE = 114         -- Lower case r
local KEY_ENABLE_PUSHING_ROLL_MODE = 112    -- Lower case p


local KEY_STRAIGHTEN = 113                 -- q key (stop and reset the snake to its initial shape)



local make_turn_controller
local add_basic_movements


--
-- This adds manual control to various tasks.
--
function ManualControl(snake, keyboard, planner)

    local manual_control = {}


    local do_follow_line
    local do_follow_object
    local do_drop_object
    local do_pre_grasp_movement
    local do_grap_object
    local do_idle



    local current_line_color = nil
    local current_target = nil

    local logic = GlobalLogic({}) -- There is currently no global logic but we create this just in case.



    --
    -- Stop the snake and do nothing
    --
    function do_idle()
        transitions.set_global(snake, transitions.smoothly_stop_snake(snake, {duration=1}))
        snake:set_idle()
    end



    --
    -- Follow the line until the line is lost or the target is found
    --
    function do_follow_line()
        
        local follow = LineFollowingLogic(snake, {line_color=current_line_color})
        follow:add_event_listener(Event.LOST_LINE, do_idle)

        logic:set(snake, follow)

        return true
    end


    --
    -- Follow an object
    --
    function do_follow_object()
        
        local follow = FollowObjectLogic(snake, {target=current_target})

        follow:add_event_listener(Event.REACHED_OBJECT, do_idle)
        follow:add_event_listener(Event.LOST_OBJECT, do_idle)

        logic:set(snake, follow)

        return true

    end



    -- 
    -- Get the object into a good location for grasping.
    --
    function do_pre_grasp_movement()

        local pre_grasp = PreGraspingLogic(snake, {target=current_target})

        pre_grasp:add_event_listener(Event.DONE, do_idle)
        pre_grasp:add_event_listener(Event.LOST_OBJECT, do_idle)

        logic:set(snake, pre_grasp)

        return true

    end


    --
    -- Do the grasping sequence.
    -- 
    function do_grasp_object()

        local grasp = GraspingSequenceLogic(snake, {target=current_target})

        grasp:add_event_listener(Event.DONE, do_idle)
        grasp:add_event_listener(Event.LOST_OBJECT, do_idle)

        logic:set(snake, grasp)
        return true
    end




    --
    -- Drop the object at the drop zone
    -- 
    function do_drop_object()

        local drop = DropObjectLogic(snake, {target=current_target})

        drop:add_event_listener(Event.DONE, do_idle)

        logic:set(snake, drop)

        return true
    end



    -- Set the current line color.
    -- This will activate some new keyboard actions
    function manual_control:set_line_color(line_color)

        current_line_color = line_color

        if(line_color == nil) then
            keyboard:add_action(KEY_FOLLOW_LINE, nil)
        else
            keyboard:add_action(KEY_FOLLOW_LINE, do_follow_line)
        end

    end

    -- Set the current target used by some of the tasks. 
    -- This will activate some new keyboard actions
    function manual_control:set_current_target(current_target_object)

        current_target = current_target_object

        if(current_target_object == nil) then
            keyboard:add_action(KEY_TRACK_OBJECT, nil)
            keyboard:add_action(KEY_GRASP_OBJECT, nil)
            keyboard:add_action(KEY_PRE_GRASP, nil)
            keyboard:add_action(KEY_DROP_OBJECT, nil)
        else
            keyboard:add_action(KEY_TRACK_OBJECT, do_follow_object)
            keyboard:add_action(KEY_GRASP_OBJECT, do_grasp_object)
            keyboard:add_action(KEY_PRE_GRASP, do_pre_grasp_movement)
            keyboard:add_action(KEY_DROP_OBJECT, do_drop_object)
        end

    end



    local is_manual = false
    -- Toggles the manual or autonomous mode.
    function manual_control:toggle_manual()
        is_manual = not is_manual
        if(is_manual) then
            add_basic_movements(snake, keyboard, true)
            snake:set_moving_mode(Snake.MODE_TURNING) -- Start in turning mode
            do_idle()
        else
            add_basic_movements(snake, keyboard, false)
            planner:start()
        end
    end

    keyboard:add_action(KEY_IDLE, do_idle)


    -- Add a key to toggle between manual and autonomous mode.
    keyboard:add_action(KEY_TOGGLE_MANUAL, function() manual_control:toggle_manual() end)


    return manual_control

end



-- Adds control for basic movements. 
-- Setting enabled to false disables the keyboard control 
-- for the basic movements.
function add_basic_movements(snake, keyboard, enabled)

    local function add_action(key, action)
        if(enabled) then
            keyboard:add_action(key, action)
        else
            keyboard:add_action(key, nil)
        end
    end


    local turn_controller = make_turn_controller(snake)


    add_action(KEY_MOVE_FORWARDS, function () snake:move_forward() end)
    add_action(KEY_MOVE_BACKWARDS, function () snake:move_backwards() end)

    add_action(KEY_LEFT, function () 
        if(snake.moving_mode == Snake.MODE_TURNING) then
            turn_controller:turn_left(1)
        elseif (snake.moving_mode == Snake.MODE_ROLLING) then
            snake:roll_left()

        elseif(snake.moving_mode == Snake.MODE_SIDE_WINDING) then
            snake:side_winding_left()

        elseif(snake.moving_mode == Snake.MODE_ROTATION) then
            snake:rotate_left()

        elseif(snake.moving_mode == Snake.MODE_PUSHING_ROLL) then
            snake:pushing_roll_left()

        elseif(snake.moving_mode == Snake.MODE_EDGING) then
            snake:edge_left()
        end
    end)


    add_action(KEY_RIGHT, function () 
        if(snake.moving_mode == Snake.MODE_TURNING) then
            turn_controller:turn_right(1)
        elseif (snake.moving_mode == Snake.MODE_ROLLING) then
            snake:roll_right()

        elseif(snake.moving_mode == Snake.MODE_SIDE_WINDING) then
            snake:side_winding_right()

        elseif(snake.moving_mode == Snake.MODE_ROTATION) then
            snake:rotate_right()

        elseif(snake.moving_mode == Snake.MODE_PUSHING_ROLL) then
            snake:pushing_roll_right()

        elseif(snake.moving_mode == Snake.MODE_EDGING) then
            snake:edge_right()
        end
    end)



    add_action(KEY_STRAIGHTEN, function()
        turn_controller:reset()
        transitions.set_global(snake, transitions.smoothly_stop_snake(snake, {duration=3}))
        transitions.set_global(snake, transitions.smoothly_straighten_snake(snake, {duration=3}))
    end)



    local function set_mode(mode)
        return function()
            snake:set_moving_mode(mode)
        end
    end

    add_action(KEY_ENABLE_ROLLING_MODE, set_mode(Snake.MODE_ROLLING))
    add_action(KEY_ENABLE_EDGING_MODE, set_mode(Snake.MODE_EDGING))
    add_action(KEY_ENABLE_TURNING_MODE, set_mode(Snake.MODE_TURNING))
    add_action(KEY_ENABLE_SIDE_WINDING_MODE, set_mode(Snake.MODE_SIDE_WINDING))
    add_action(KEY_ENABLE_ROTATION_MODE, set_mode(Snake.MODE_ROTATION))
    add_action(KEY_ENABLE_ROLLING_MODE, set_mode(Snake.MODE_ROLLING))
    add_action(KEY_ENABLE_PUSHING_ROLL_MODE , set_mode(Snake.MODE_PUSHING_ROLL))

end




-- Helper object for the manual turning
function make_turn_controller(snake)

    local controller = {factor=0}

    local normal = utils.make_bend_controller(snake,
        utils.bending_deg{90, 45, 40, 20, 20, 20, 20}
    )

    local v_grasping = utils.make_bend_controller(snake,
        utils.bending_deg{40, 40, 40, 40, 40, 40, 40}
    )

    local function set_bend(factor)

        controller.factor = factor
        if(snake.in_v_grasping_mode) then
            v_grasping:set(factor)
        else
            normal:set(factor)
        end
    end

    
    function controller:turn_left(incr_factor)
        set_bend(controller.factor - incr_factor)
    end

    function controller:turn_right(incr_factor)
        set_bend(controller.factor + incr_factor)
    end

    function controller:reset()
        controller.factor = 0
    end


    return controller

end
