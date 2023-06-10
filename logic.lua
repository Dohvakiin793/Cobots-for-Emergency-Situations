-- This is where the logic is implemented.
--
--
-- Each function returns an LogicHandler that implements logic for the snake.
-- The returned handler is activated by setting the logic handler on the snake using
-- snake:set_logic_handler(handler)
--
-- Some of the logic handler will trigger events when something happens. Other code
-- can listen for this events by adding listeners using handler:add_event_listener(listener)
--
--
require "vision"
require "logiclib"


--
-- Tries to follow the line.
-- 
-- data:
-- data.line_color   Required, Blob.[COLOR]
--
-- Events:          Data:
-- LOST_LINE
--
function LineFollowingLogic(snake, data)

    local pid = utils.make_pid_controller{
        set_point = 0.5,
        proportional_gain = 2.8,
        derivative_gain = 3,
    }

    local vision = VisionSensor:new(snake.front_vision)

    local bending 
    
    if (snake.in_v_grasping_mode) then
        bending = utils.make_bend_controller(snake,
            utils.bending_deg{40, 40, 40, 40, 40, 40, 40})
    else
        bending = utils.make_bend_controller(snake,
            utils.bending_deg{45, 45, 45, 45, 40, 20, 20})
    end

    local turning_factor = 0

    local line_pos_average = utils.make_running_average(5)
    local line_detect_average = utils.make_running_average(15)

    -- We are currently at the line so add 1 to the average
    -- to start with.
    line_detect_average(1)

    local last_line_pos = 0

    snake:set_moving_mode(Snake.MODE_TURNING)
    snake:move_forward()

    return LogicHandler(function(logic, time_step, time) 

        local line = vision:find_first_blob_of_color(data.line_color)


        if(line == nil) then
            if(line_detect_average(0) == 0) then
                logic:notify(Event.LOST_LINE)
            end
            return
        end

        line_detect_average(1)
        last_line_pos = line_pos_average(line.x)
        pid:update(last_line_pos)
        turning_factor = turning_factor + pid.output
        bending:set(turning_factor)

    end)

end




--
-- Looks for a blob using the vision sensor.
-- 
-- data:
-- data.target      Required, {color=Blob.[COLOR]}
--
-- Events:          Data:
-- FOUND_BLOB       blob object
--
function LookForBlobLogic(snake, data)

    local vision = VisionSensor:new(snake.front_vision)


    return LogicHandler(function(logic, time_step)

        local object = vision:find_first_blob_of_color(data.target.color)

        if(object ~= nil) then
            logic:notify(Event.FOUND_BLOB, {blob=object})
        end

    end)

end





-- 
-- Follows and object and moved towards it until it is reached.
--
-- data:
-- data.target              Required, {color=Blob.[COLOR]}
-- data.width_threshold     Optional, the minimal witdh to trigger the reached event. [0-1]
-- data.height_threshold    Optional, the minimal height to trigger the reached event. [0-1]
-- data.set_point           Optional, x position to keep the object in the vision sensor. [0-1]
--                                    
--
-- Events:          Data:
-- REACHED_OBJECT
-- LOST_OBJECT
--
function FollowObjectLogic(snake, data)

    -- The width of the obejct when we assume that we 
    -- have reached the object. Range: 0.0-1.0
    local BLOB_WIDTH_THRESHOLD = data.width_threshold or 0.98
    local BLOB_HEIGHT_THRESHOLD = data.height_threshold

    local pid = utils.make_pid_controller{
        set_point = data.set_point or 0.5,
        proportional_gain = 2.8,
        derivative_gain = 3,
    }

    local bending
    if(snake.in_v_grasping_mode) then
        bending = utils.make_bend_controller(snake,
            utils.bending_deg{40, 40, 40, 40, 40, 40, 40})
    else
        bending = utils.make_bend_controller(snake,
            utils.bending_deg{45, 45, 45, 45, 40, 20, 20})
    end

    -- The current amount of turning.
    local turning_factor = 0


    -- This helps to smooth the movement by using the average for the
    -- object detection so the object is not lost all the time 
    -- because of the shaking of the camera.
    local object_detect_avg = utils.make_running_average(10) 

    local vision = VisionSensor:new(snake.front_vision)

    snake:move_forward() --start forward movement

    return LogicHandler(function(logic, time_step, time) 

        local object = vision:find_first_blob_of_color(data.target.color)


        if(object == nil) then
            if(object_detect_avg(0) == 0) then
                logic:notify(Event.LOST_OBJECT)
            end
        else

            object_detect_avg(1)

            if(object.width > BLOB_WIDTH_THRESHOLD) then
                if(BLOB_HEIGHT_THRESHOLD == nil or object.height > BLOB_HEIGHT_THRESHOLD) then

                    transitions.set_global(snake, 
                        transitions.smoothly_stop_snake(snake, {duration=1, pause=1}, function()
                            logic:notify(Event.REACHED_OBJECT)
                        end)
                    )

                end
            end

            pid:update(object.x)
            turning_factor = turning_factor + pid.output
            bending:set(turning_factor)
        end

    end)


end




-- 
-- This expected the object to be located right in front of the snake.
-- It will then reposition the snake into a good position for grasping.
--
-- data:
-- data.target              Required, {color=Blob.[COLOR], handle=vrep-object-handle}
--
-- Events:          Data:
-- DONE
-- LOST_OBJECT
--
function PreGraspingLogic(snake, data) 

    local current_state

    local bend_until_hit
    local release_bend
    local step_forward

    local bending = utils.make_bend_controller(snake,
        utils.bending_deg{95, 45, 45, 20, 10, 10, 10},
        {initial_dampening=0.99})

    local bend_pos = 0

    -- Used for collision detection.
    local bodies = {
		simGetObjectHandle('snake_body1'),
		simGetObjectHandle('snake_body2')
    }


    local vision = VisionSensor:new(snake.front_vision)

    local release_size = 25



    function reposition_next_to_object()

        local timer = utils.make_timer()

        return function(time_step)

            local object = vision:find_first_blob_of_color(data.target.color)

            if(object ~= nil) then
                -- Turn left until the object dissappears.
                bend_pos = bend_pos - 0.2
                bending:set(bend_pos)
                return
            end

            if(timer.value > 0) then
                if(timer.value > 4.5) then
                    -- After 4.5 seconds we switch state.
                    transitions.set_global(snake, 
                        transitions.smoothly_stop_snake(snake, {duration=1, pause=1}, function()
                            current_state = bend_until_hit
                        end)
                    )
                end
            else
                -- Move forward
                bending:set(bend_pos)
                transitions.set_global(snake, transitions.smoothly_start_snake(snake, {duration=2}))
            end

            timer:update(time_step)

        end
    end

    
    function step_forward(time) 

        transitions.set_global(snake, 
            transitions.smoothly_start_snake(snake, {duration=1, pause=2}, function()
                transitions.set_global(snake,
                    transitions.smoothly_stop_snake(snake, {duration=1, pause=1}, function()
                    current_state = bend_until_hit
                end))
        end))

        -- Do nothing while waiting for the transitions to end
        return function() end

    end

    -- Releases the bend slightly and the step a little bit forwards.
    function release_bend()

        local new_pos = bend_pos - release_size
        return function (time_step) 

            bend_pos = bend_pos - 0.5
            if(bend_pos <= new_pos) then
                release_size = math.max(15, release_size*0.8)
                current_state = step_forward()
            end

        end
    end


    function bend_until_hit(time_step, logic)

        local hit1 = simCheckCollision(bodies[1], data.target.handle)
        local hit2 = simCheckCollision(bodies[2], data.target.handle)

        if(hit1 == 1 or hit2 == 1) then

            -- We have hit the object. If the bending is above
            -- 50 degrees we are done.
            if(bending.current[1] > to_rads(50)) then
                logic:notify(Event.DONE)
                return
            end

            -- If not we continue
            current_state = release_bend()

        elseif(bend_pos >= 100) then

            -- If we reach the maximum bend without a hit we stop the movement and 
            -- notify any listeners.
            transitions.set_global(snake,
                transitions.smoothly_straighten_snake(snake, {duration=5, pause=3}, function()
                    logic:notify(Event.LOST_OBJECT)
            end))

        else 
            bend_pos = bend_pos + 0.5
        end

    end

    current_state = reposition_next_to_object()

    return LogicHandler(function(logic, time_step, time) 

        bending:set(bend_pos)
        current_state(time_step, logic)

    end)

end




--
-- Helper for the grasping sequence logic
-- 
local function GraspingSequence(bending_sequence)

    local sequence = {current=1}

    function sequence:current_table()
        return bending_sequence[self.current]
    end
    function sequence:next()
        self.current = self.current + 1
        return self:current_table()
    end

    return sequence

end



-- 
-- Performs an sequence of bending manouvers to get the 
-- object positioned between the arms of the U shaped snake.
--
-- data:
-- data.target              Required, {handle=vrep-object-handle}
--
-- Events:          Data:
-- DONE
-- LOST_OBJECT
--
--
function GraspingSequenceLogic(snake, data)

    -- Thresholds that must be exceeded before the sequence proceeds
    local FORCE_THRESHOLD = 4
    local FORCE_DERIVATIVE_THRESHOLD = 0.2


    -- The seriese of bending tables used to create
    -- the grasping movement.
    local grasping_sequence = GraspingSequence({
        utils.bending_deg({95, 95, 0, 0, 0, 0, 0}),
        utils.bending_deg({0, 95, 95, 0, 0, 0, 0}),
        utils.bending_deg({0, 0, 95, 95, 0, 0, 0}),
        utils.bending_deg({0, 0, 80, 80, 0, 0, 0}),
        utils.bending_deg({0, 0, 87, 87, 0, 0, 0}),
    })

    local joint_forces = utils.make_joint_force_reader(snake)
    local timer = utils.make_timer()


    local bodies = {
        simGetObjectHandle('snake_body8'),
        simGetObjectHandle('snake_body9'),
    }


    snake:set_moving_mode(Snake.MODE_TURNING)

    -- Start the first bend manouver
    transitions.set_global(snake,
        transitions.bend_transition(snake, grasping_sequence:current_table(), {duration=2}))

    return LogicHandler(function(logic, time_step, time) 

        timer:update(time_step)

        if(grasping_sequence.current < 4) then

            joint_forces:update(time_step)

            local j1_force = math.abs(joint_forces.force[grasping_sequence.current])
            local j2_force = math.abs(joint_forces.force[grasping_sequence.current+1])
            local j1_derivative = math.abs(joint_forces.derivative[grasping_sequence.current])
            local j2_derivative = math.abs(joint_forces.derivative[grasping_sequence.current+1])

            -- Check the force of the current active joints 
            if(j1_force > FORCE_THRESHOLD and j2_force > FORCE_THRESHOLD and 
                j1_derivative < FORCE_DERIVATIVE_THRESHOLD and j2_derivative < FORCE_DERIVATIVE_THRESHOLD) then

                --If the forces are big enough proceed to the next grasping movement.
                transitions.set_global(snake,
                    transitions.bend_transition(snake, grasping_sequence:next(), {duration=2}))

                timer:reset()

            elseif(timer.value > 8) then

                -- If it has been more than 8 seconds without the joint forces triggering the next
                -- movement we just stop the sequence.
                transitions.set_global(snake,
                    transitions.smoothly_straighten_snake(snake, {duration=5, pause=4}, function()
                        logic:notify(Event.LOST_OBJECT)
                end))
            end

        elseif(grasping_sequence.current == 4) then

            local hit1 = simCheckCollision(bodies[1], data.target.handle)
            local hit2 = simCheckCollision(bodies[2], data.target.handle)

            if(hit1 == 1 or hit2 == 1 or timer.value > 9) then
                -- Close the arms again and move on with the sequence to prepare for locomotion.
                -- snake:stop_movement()
                transitions.set_global(snake,
                    transitions.smoothly_stop_snake(snake, {duration=1}, function()
                        snake:enable_v_grasping_mode(false)
                        timer:reset()
                        transitions.set_global(snake, 
                            transitions.bend_transition(snake, grasping_sequence:next(), {duration=2}))
                    end))

            elseif(timer.value > 2) then
                -- Start to move forward
                -- Now we should have the object between the two arms and the bend should have 
                -- been release slightly so we move forwards a little bit to make sure the
                -- object is in the bottom of the "V".
                snake:enable_v_grasping_mode(true)
                transitions.set_global(snake, transitions.smoothly_start_snake(snake, {duration=1}))
                -- snake:move_forward()
            end

        elseif(grasping_sequence.current == 5) then
            
            if(timer.value > 3) then
                -- The sequence is done.
                snake:enable_v_grasping_mode(true)
                logic:notify(Event.DONE)

            end


        end


    end)


end



--
-- Simply rotates the snake around
--
-- data:
-- data.direction   Optional: rotation direction Snake.DIRECTION_LEFT|Snake.DIRECTION_RIGHT
-- data.timeout     Optional: time in seconds until TIMEOUT event is triggered
--
-- Events:          Data:
-- TIMEOUT
--
function RotateSnakeLogic(snake, data)

    if(snake.in_v_grasping_mode) then
        snake:set_moving_mode(Snake.MODE_EDGING)
        if(data.direction == Snake.DIRECTION_LEFT) then
            snake:edge_left()
        else
            snake:edge_right()
        end
    else 
        snake:set_moving_mode(Snake.MODE_ROTATION)
        if(data.direction == Snake.DIRECTION_LEFT) then
            snake:rotate_left()
        else
            snake:rotate_right()
        end
    end

    local timer = utils.make_timer()

    return LogicHandler(function(logic, time_step, time) 

        if(data.timeout ~= nil and timer.value > data.timeout) then
            logic:notify(Event.TIMEOUT)
        end

        timer:update(time_step)
    end)

end




--
-- Tries to drop the object at the drop zone. This expects the drop zone to be just in 
-- front of the snake.
--
-- data:
-- data.target      Required: {color=Blob.[COLOR]}
--
-- Events:          Data:
-- DONE
--
function DropObjectLogic(snake, data)


    local move_forward
    local rotate_to_find_line
    local move_past_drop_zone
    local edge_away
    local release_object
    local current_state
    local vision = VisionSensor:new(snake.front_vision)


    -- Edge sideways away from the object.
    function edge_away(logic)

        snake:set_moving_mode(Snake.MODE_EDGING)
        snake:edge_left()

        return utils.make_timeout(function()

            transitions.set_global(snake, transitions.smoothly_stop_snake(snake, {duration=3}))
            transitions.set_global(snake, 
                transitions.smoothly_straighten_snake(snake, {duration=3, pause=2}, function()
                    logic:notify(Event.DONE)
            end))

        end, 1.5)

    end

    -- Releases the object
    function release_object(logic)

        -- A little hack to make the release work correctly. Because we don't know
        -- how the current bending table is, we just set it to this value to make 
        -- the bend transition use this as the staring point for the transition.
        snake:set_bending_table(utils.bending_deg({0, 0, 87, 87, 0, 0, 0}))
        snake:enable_v_grasping_mode(false)
        transitions.set_global(snake, 
            transitions.bend_transition(snake, utils.bending_deg{0, 0, 0, 0, 0, 0, 0}, 
                                              {duration=6, pause=2}, function()

                current_state = edge_away(logic)

        end))

        return function() end

    end



    -- Move forwards for 15 seconds
    function move_forward(logic)

        snake:move_forward()
        return utils.make_timeout(function()

            transitions.set_global(snake,
                transitions.smoothly_stop_snake(snake, {duration=3, pause=2}, function()
                    current_state = release_object(logic)
            end))
       
        end, 15)

    end

    -- Move forwards until the drop zone is no longer visible
    function move_past_drop_zone()
        snake:move_forward()

        local drop_point_avg = utils.make_running_average(20)

        drop_point_avg(1)

        return function(time_step, logic)
            local drop_point = vision:find_first_blob_of_color(data.target.color)

            if(drop_point == nil) then
                if(drop_point_avg(0) == 0) then
                    --When the drop zone disappears we continue to move forwards
                    current_state = move_forward(logic)
                end
            else
                drop_point_avg(1)
            end
        end

    end



    snake:set_moving_mode(Snake.MODE_TURNING)

    current_state = move_past_drop_zone()

    return LogicHandler(function(logic, time_step, time) 

        current_state(time_step, logic)

    end)

end




--
-- Moves the snake in a not really simple search pattern. I will
-- move the snake forwards or backwards and then stop and turn to each
-- side before it start to move forwards or backwards again and repeats.
--
-- Data:
-- data.move_direction        Optional: Snake.DIRECTION_BACKWARDS|Snake.DIRECTION_FORWARDS
-- data.initial_search_step   Optional: A number to add to the bending factor on each update when 
--                                      turning the head.
--
-- Events:          Data:
-- None
--
function SimpleSearchMovementLogic(snake, data)

    data = data or {}

    local current_state 
    local move_forward 
    local do_search

    local bending

    if(snake.in_v_grasping_mode) then
        bending = utils.make_bend_controller(snake,
            utils.bending_deg{30, 30, 30, 30, 30, 30, 30}
        )
    else
        bending = utils.make_bend_controller(snake,
            utils.bending_deg{40, 30, 20, 20, 5, 5, 5}
        )
    end

    local search_range = utils.make_range_cycler(-100, 100, 0, data.initial_search_step or 1)

    local move_func
    if(data.move_direction == Snake.DIRECTION_BACKWARDS) then
        move_func = snake.move_backwards
    else
        move_func = snake.move_forward
    end


    -- Searches right and left for one cycle
    function do_search()
        snake:stop_movement()
        return function()
            bending:set(search_range:update())
            if(search_range.cycle_count == 1) then
                snake:stop_movement()
                search_range:reset()
                current_state = utils.make_timeout(function()
                    current_state = move_snake()
                end, 2)
            end
        end
    end

    -- Move for 10 seconds
    function move_snake()
        move_func(snake)
        return utils.make_timeout(function()
            current_state = do_search()
        end, 10)

    end


    snake:set_moving_mode(Snake.MODE_TURNING)
    current_state = do_search()

    return function(time_step, time) 

        current_state(time_step)

    end


end



--
-- FIXME: Coule be combined with the other search movement.
--
-- Moves the snake in a random pattern. It will move forward or backwards
-- while turning the head left and right for one cycle. Then the bend 
-- is set to a random position and the snake moves in this position before
-- it restarts the left right search. 
--
-- Data:
-- data.move_direction        Optional: Snake.DIRECTION_BACKWARDS|Snake.DIRECTION_FORWARDS
--
-- Events:          Data:
-- None
--
function RandomSearchMovementLogic(snake, data)

    data = data or {}
    local current_state 
    local move_forward 
    local do_search

    local bending

    if(snake.in_v_grasping_mode) then
        bending = utils.make_bend_controller(snake,
            utils.bending_deg{30, 30, 30, 30, 30, 30, 30},
            {initial_dampening=0}
        )
    else
        bending = utils.make_bend_controller(snake,
            utils.bending_deg{40, 30, 20, 20, 5, 5, 5},
            {initial_dampening=0}
        )
    end

    local search_range = utils.make_range_cycler(-100, 100, 0, 1)

    local move_func = snake.move_forward
    if(data.move_direction == Snake.DIRECTION_BACKWARDS) then
        move_func = snake.move_backwards
    end

    -- Searches in a ranom direction
    function do_search()

        -- if(data.stop_for_search) then
        --     transitions.set_global(snake, transitions.smoothly_stop_snake(snake, {duration=1}))
        -- end

        -- Straighten the snake before we start the search move.
        current_state = transitions.bend_transition(snake, bending:get(0), 
                                                                {duration=1.5}, function()
            local dir = {-2, 2}
            search_range.step = dir[math.random(1, 2)]
            current_state = function()
                bending:set(search_range:update())
                if(search_range.cycle_count == 1) then
                    search_range:reset()
                    current_state = utils.make_timeout(function()
                        move_in_random_direction()
                    end, 2)
                end
            end
        end)
    end

    -- Move for a few seconds
    function move_in_random_direction()
        move_func(snake)
        current_state = transitions.bend_transition(snake, bending:get(math.random(-100, 100)), 
                                                                {duration=3}, function()
            current_state = utils.make_timeout(function()
                do_search()
            end, 12)
        end)

    end


    snake:set_moving_mode(Snake.MODE_TURNING)
        
    move_func(snake)
    do_search()

    return function(time_step, time) 

        current_state(time_step)

    end

end





-- FIXME: Make it more general by sending the collision object in as a parameter.
--
-- Uses collision detection to check if the head has collided with the wall.
--
-- Data:
--
-- Events:          Data:
-- WALL_HIT
--
function CheckForWallHitLogic(snake, data)


    local head = simGetObjectHandle("snake_body1")
    local wall = simGetObjectHandle("wall0")


    return LogicHandler(function(logic)
        local hit = simCheckCollision(head, wall)
        if(hit == 1) then
            logic:notify(Event.WALL_HIT)
        end
        
    end)

end





--
-- Not a normal logic handler. This is a special handler used to 
-- recover from rolling over. This is currently used in the snake object
-- as a global recovery handler.
-- 
-- It will only try to recover when not in one of the rolling modes.
-- 
function RecoverFromRolloverLogic(snake)

    local backup_old_parameters
    local restore_old_parameters
    local check_if_rolled_over
    local recover

    local params = {'_speed_vertical', '_speed_horizontal', '_amplitude_vertical',
                '_amplitude_horizontal', '_phase_vertical', '_phase_horizontal',
                '_phase_diff_vertical_horizontal', '_phase_camera', '_phase_0',
                'current_time', 'moving_mode', 'bending_table'}

    local old_values = {}

    local fallen = false
    local current_state

    -- The body part used to check the orientation
    local orientation_body = simGetObjectHandle("snake_body1")

    function backup_old_parameters()
        for i=1,#params,1 do
            old_values[params[i]] = snake[params[i]]
        end
    end

    function restore_old_parameters()
        for i=1,#params,1 do
            snake[params[i]] = old_values[params[i]]
        end
    end


    function check_if_rolled_over(threshold)

        local orient = simGetObjectOrientation(orientation_body,  -1)

        local rot_x = math.abs(math.abs(orient[1]))
        local rot_y = math.abs(math.abs(orient[2]))

        local is_rolled = false

        -- Check if it has rolled more than about some degrees around
        -- the x or y axis.
        if(math.sin(rot_x) > threshold or math.cos(rot_x) < threshold) then
            is_rolled = true
        elseif(math.sin(rot_y) > threshold or math.cos(rot_y) < threshold) then
            is_rolled = true
        end

        return is_rolled

    end


    function recover()

        return utils.make_timeout(function()
            
            snake:set_moving_mode(Snake.MODE_ROLLING)
            snake:roll_left()

            current_state = function() 

                if(not check_if_rolled_over(0.4)) then
                    snake:stop_movement()

                    current_state = utils.make_timeout(function()
                        snake:straighten_snake()
                        current_state = utils.make_timeout(function()
                            restore_old_parameters()
                            fallen = false
                        end, 3)
                    end, 1)

                end
            end
            
        end, 3)

    end


    return function(time_step)

        if(fallen) then

            current_state(time_step)

        elseif(check_if_rolled_over(0.7)) then

            if(snake.moving_mode ~= Snake.MODE_ROLLING and snake.moving_mode ~= Snake.MODE_PUSHING_ROLL) then

                fallen = true
                backup_old_parameters()

                snake:stop_movement()
                snake:straighten_snake()
                current_state = recover()
            end
        end

        return fallen

    end


end

