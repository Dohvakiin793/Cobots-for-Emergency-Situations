--
-- Code for controlling the snake
--

require 'utils'
require 'transitions'
require 'logic'



Snake = {
    MODE_TURNING = 1,
    MODE_ROLLING = 2,
    MODE_SIDE_WINDING = 3,
    MODE_ROTATION = 4,
    MODE_PUSHING_ROLL = 5,
    MODE_EDGING = 6,


    DIRECTION_LEFT = 1,
    DIRECTION_RIGHT = 2,
    DIRECTION_BACKWARDS = 3,
    DIRECTION_FORWARDS = 4,
}




--
-- Creates a new snake object.
-- The update and cleanup methods should be called when the actuation and
-- cleanup simulation environment events occur.
-- 
function Snake:new(params)
    local object = {}
    
    setmetatable(object, self)
    self.__index = self


    math.randomseed(os.time())


    -- Setup various initial values.
    object.joint_count = params.joint_count or 7
    object.joints_horizontal={}
	object.joints_vertical={}

    -- Set initial values
    Snake.set_control_parameters(object, {
        speed = 0,
        amplitude_vertical = 0,
        amplitude_horizontal = 0,
        phase_vertical = to_rads(120),
        phase_horizontal = to_rads(60),
        phase_diff_vertical_horizontal = to_rads(90),
        phase_camera = to_rads(180),
        phase_0 = 0,
    })


    Snake.set_moving_mode(object, Snake.MODE_TURNING)
    Snake.set_bending_table(object, utils.bending_deg{0, 0, 0, 0, 0, 0, 0})

    -- state_logic is a function that is associated with the current state.
    -- It is called repeatedly every simulation step and performs the logic 
    -- for the current state. The state functions are defined in the "logic" module.
    object._state_logic = nil
    object.suspend_logic = false
    -- Used to allow a stacking behaviour to suspend logic calls.
    object._suspend_logic_count = 0

    Snake.enable_v_grasping_mode(object, false)

    -- The current time since the start of the simulation
    object.current_time = 0



    -- Listeners (callbacks) that can be added with the add_update_listener method 
    -- which will be called from the update method. 
    object._update_listeners = {}


    -- Load the objects handles from the environments
	for i=1,object.joint_count,1 do
		object.joints_horizontal[i] = simGetObjectHandle('snake_joint_h'..(i))
	end

	object.joint_camera = simGetObjectHandle('snake_joint_cam')

    for i=1,object.joint_count,1 do
		object.joints_vertical[i] = simGetObjectHandle('snake_joint_v'..(i))
	end

    object.front_vision = simGetObjectHandle('Front_Vision')

    -- Recovery if the snake rolls over.
    object._recover_logic = RecoverFromRolloverLogic(object)

    return object
end






--
-- Update the movement of the snake. This should be called on each actuation event.
--
-- This updates the joint positions and calls any logic that is active on this snake object.
--
function Snake:update(time_step)


    self.current_time = self.current_time + time_step

    -- Check if recovery is necessary
    if(self._recover_logic(time_step)) then
        self:update_joint_positions(self.current_time)
        return
    end


    -- Run any update listeners that are currently added.
    for i, listener in ipairs(self._update_listeners) do
        if(self._update_listeners[i](time_step)) then
            -- Remove the listener when it returns true
            table.remove(self._update_listeners, i)
        end
    end

    -- Call the state logic function if there is any.
    if(not self.suspend_logic and self._state_logic ~= nil) then
        self._state_logic(time_step, self.current_time)
    end


    -- Update the joints with the current parameters
    if(self.in_v_grasping_mode) then
        self:update_joint_positions_grasping_locomotion(self.current_time)
    else
        self:update_joint_positions(self.current_time)
    end


	
end




-- 
-- Do some cleanup.
-- Should be called from the vrep child script on the cleanup event.
-- 
function Snake:cleanup()
end




--#
--# The following functions sets the control parameters for the various snake movements
--#

--
-- Makes the snake move forward.
--
function Snake:move_forward()

    self:set_control_parameters{
        speed = 5,
        amplitude_vertical = to_rads(40),
        phase_vertical = to_rads(125),
        amplitude_horizontal = 0,
        phase_horizontal = 0,
		phase_0 = 0,
        phase_camera = to_rads(215),
    }

end

--
-- Make the snake move backwards.
--
function Snake:move_backwards()
    self:set_control_parameters{
        speed = 5,
        amplitude_vertical = to_rads(40),
        amplitude_horizontal = 0,
        phase_vertical = to_rads(-125),
        phase_horizontal = 0,
		phase_0 = 0,
        phase_camera = -to_rads(215),
    }

end


--
-- Make the snake roll to the left in a slow rolling movement. 
-- Usefull for recovering after falling over.
--
function Snake:roll_left()
    self:set_control_parameters{
        speed = 1,
        amplitude_vertical = to_rads(10),
        amplitude_horizontal = to_rads(10),
        phase_vertical = 0,
        phase_horizontal = 0,
        phase_diff_vertical_horizontal = to_rads(90),
		phase_0 = 0,
    }
end

--
-- Make the snake roll to the right in a slow rolling movement. 
-- Usefull for recovering after falling over.
--
function Snake:roll_right()
    self:set_control_parameters{
        speed = -1,
        amplitude_vertical = to_rads(10),
        amplitude_horizontal = to_rads(10),
        phase_vertical = 0,
        phase_horizontal = 0,
        phase_diff_vertical_horizontal = to_rads(90),
		phase_0 = 0,
    }
end


--
-- Makes the snake roll to the side while arching like an U with the opening in the
-- moving direction. This can be used to push an object. 
-- (Sometimes it the opening points in the wrong direction. This has to do with 
-- the starting position when the movement is initiated.)
-- 
function Snake:pushing_roll_left()

	self:set_control_parameters{speed_vertical=5,speed_horizontal=5,
        -- The amplitude controls the amount of bending. The vertical and horizontal
        -- amplitude should be equal.
		amplitude_vertical=to_rads(22),
		amplitude_horizontal=to_rads(22),

        -- The phases should be 0
		phase_vertical=0,
		phase_horizontal=0,

        -- The sign of the phase diff controls the direction of the roll
		phase_diff_vertical_horizontal=to_rads(90),

        -- The sign of the initial phase controls if it bends inwards or outwards
		phase_0 = to_rads(90),
    }

end

--
-- Makes the snake roll to the side while arching like an U with the opening in the
-- moving direction. This can be used to push an object. 
-- (Sometimes it the opening points in the wrong direction. This has to do with 
-- the starting position when the movement is initiated.)
-- 
function Snake:pushing_roll_right()

	self:set_control_parameters{speed_vertical=5,speed_horizontal=5,
		amplitude_vertical=to_rads(22),
		amplitude_horizontal=to_rads(22),
		phase_vertical=0,
		phase_horizontal=0,
		phase_diff_vertical_horizontal=to_rads(-90),
		phase_0 = to_rads(90),
    }

end


-- 
-- Makes the snake move sideways in a gliding motion.
--
function Snake:side_winding_left()
    self:set_control_parameters{
        speed = 3,
        amplitude_vertical = to_rads(5),
        amplitude_horizontal = to_rads(40),
        phase_vertical = to_rads(90),
        phase_horizontal = to_rads(90),
        phase_diff_vertical_horizontal = to_rads(-26),
		phase_0 = 0,
    }
end

-- 
-- Makes the snake move sideways in a gliding motion.
--
function Snake:side_winding_right()
    self:set_control_parameters{
        speed = 3,

        amplitude_vertical = to_rads(5), -- sign changes direction
        amplitude_horizontal = to_rads(-40), -- sign changes direction

		-- When the phases are equal the robot moved sideways. When the vertical
		-- phase lower or higher than the horizontal it will rotate.
        phase_vertical = to_rads(90),
        phase_horizontal = to_rads(90),

        -- The phase diff vertical horizontal changes the angle of the movement.
		-- The snake will move in a circular pattern, and this value changes the 
		-- radius of this circle.
        phase_diff_vertical_horizontal = to_rads(-26),
		phase_0 = 0,
    }
end

-- 
-- Makes the snake rotate sideways to the left.
--
function Snake:rotate_left()
    self:set_control_parameters{
        speed = 2,
        amplitude_vertical = to_rads(4),
        amplitude_horizontal = to_rads(30),
        phase_vertical = to_rads(15),
        phase_horizontal = to_rads(90),
        phase_diff_vertical_horizontal = to_rads(90),
		phase_0 = 0,
    }
end

-- 
-- Makes the snake rotate sideways to the right.
--
function Snake:rotate_right()
    self:set_control_parameters{
        speed = 2,
        amplitude_vertical = to_rads(4),
        amplitude_horizontal = to_rads(30),
        phase_vertical = to_rads(15),
        phase_horizontal = to_rads(90),
        phase_diff_vertical_horizontal = to_rads(-90),
		phase_0 = 0,
    }
end


--
-- Makes the snake edge itself slowly to the left.
-- 
function Snake:edge_left()

    self:set_control_parameters{
        speed_vertical=5,
        speed_horizontal=5,
		amplitude_vertical=to_rads(5),
		amplitude_horizontal=to_rads(5),
		phase_vertical=to_rads(30),
		phase_horizontal=to_rads(30),
		phase_diff_vertical_horizontal=to_rads(-30),
    }
end

--
-- Makes the snake edge itself slowly to the right.
-- 
function Snake:edge_right()

    self:set_control_parameters{
        speed_vertical=5,
        speed_horizontal=5,
		amplitude_vertical=to_rads(5),
		amplitude_horizontal=to_rads(-5),
		phase_vertical=to_rads(30),
		phase_horizontal=to_rads(30),
		phase_diff_vertical_horizontal=to_rads(-30),
    }
end



-- 
-- Stops the snake by setting the vertical amplitude to 0
--
function Snake:stop_movement()

    self:set_control_parameters{amplitude_vertical=0}

end


--
-- Sets the snake to the straight position.
--
function Snake:straighten_snake()

    self:set_bending_table(utils.bending_deg{0, 0, 0, 0, 0, 0, 0})
    self:set_control_parameters{amplitude_horizontal=0}

end



-- The table controls the bending of the joints.
-- Eeach value in the table corresponds to the amount of bending 
-- each joint should have. The values are in radians.
function Snake:set_bending_table(table)
    self.bending_table = table
end

--# end of control functions

--
-- Returns the current bending table
-- 
function Snake:get_current_bending_table()
    return self.bending_table
end


--
-- Sets the moving mode of the snake.
--
function Snake:set_moving_mode(mode)
    self.moving_mode = mode
end


--
-- Enables or disables v grasping mode. This will change the way the joints
-- are updated to make the locomotion work when the snake is in the V shape.
--
function Snake:enable_v_grasping_mode(enabled)
    self.in_v_grasping_mode = enabled
end


-- 
-- Adds a callback that will be called from the update method.
-- The callback is called with a single argument which is the simulation
-- time step. It is called repeatedly until it the callback returns true.
--
function Snake:add_update_listener(listener)
    self._update_listeners[#self._update_listeners+1] = listener
end


-- 
-- Removes any logic that is currently running.
--
function Snake:set_idle()
    self:set_logic_handler(nil)
end


-- 
-- Suspend or unsuspend the logic
--
function Snake:set_suspend_logic(suspend)
    if(suspend) then
        self._suspend_logic_count = self._suspend_logic_count + 1
    else
        self._suspend_logic_count = self._suspend_logic_count - 1
    end

    self.suspend_logic = self._suspend_logic_count ~= 0
end


--
-- Sets the current logic handler. 
--
-- logic is a function callback that is called from the update method
-- on each simulation step.
--
function Snake:set_logic_handler(logic)
    self._state_logic = logic
end



-- 
-- Sets the parameters for the snake's joins.
-- The parameters are:
--
-- speed: Sets both horizontal and vertical speed
-- vertical_speed: Sets the speed of the vertical joints (radians)
-- horizontal_speed: Sets the speed of the horizontal joints (radians)
-- amplitude_vertical: Sets the amplitude for the vertical joints (radians)
-- amplitude_horizontal: Sets the amplitude for the horizontal joints (radians)
-- phase_vertical: Sets the phase difference between each vertical joint (radians)
-- phase_horizontal: Sets the phase difference between each horizontal joint (radians)
-- phase_diff_vertical_horizontal: Sets the phase difference between the vertical and horizontal joints (radians)
-- phase_camera: Sets the phase of the camera (radians)
-- phase_0: Sets the initial phase of the movement (radians)
--
function Snake:set_control_parameters(params)

    self._speed_vertical = params.speed_vertical or params.speed or self._speed_vertical
    self._speed_horizontal = params.speed_horizontal or params.speed or self._speed_horizontal
	self._amplitude_vertical =  params.amplitude_vertical or self._amplitude_vertical
	self._amplitude_horizontal = params.amplitude_horizontal or self._amplitude_horizontal
	self._phase_vertical = params.phase_vertical or self._phase_vertical
	self._phase_horizontal = params.phase_horizontal or self._phase_horizontal
    self._phase_diff_vertical_horizontal = params.phase_diff_vertical_horizontal or self._phase_diff_vertical_horizontal
	self._phase_camera = params.phase_camera or self._phase_camera
	self._phase_0 = params.phase_0 or self._phase_0
end




--
-- Updates the positions of the joints at a given time
--
-- This sets the joints positions using the current control parameters, 
-- set by the set_control_parameters method.
--
function Snake:update_joint_positions(time)

    local bending = self:get_current_bending_table()

    for i=1,self.joint_count,1 do 

        simSetJointTargetPosition(self.joints_vertical[i],
            self._amplitude_vertical * math.sin(time * self._speed_vertical + self._phase_0 + i * self._phase_vertical))


        -- If we are not in turning mode use the control parameters for the horizontal joints.
        -- Else we use the bending table for the horizontal joints.
        if(self.moving_mode ~= Snake.MODE_TURNING) then

            simSetJointTargetPosition(self.joints_horizontal[i],
                self._amplitude_horizontal * math.sin(time * self._speed_horizontal + self._phase_0 + i * self._phase_horizontal + self._phase_diff_vertical_horizontal))
        else

            simSetJointTargetPosition(self.joints_horizontal[i], bending[i])
        end
    end


	simSetJointTargetPosition(self.joint_camera ,
        self._amplitude_vertical / 1.6 * math.sin(time * self._speed_vertical + self._phase_0 + self._phase_vertical + self._phase_camera))


end




--
-- Updates the positions of the joints at a given time when in the grasping position.
--
-- This is similar to update_joint_positions, but since the snake is bendt at the middle
-- like an "U", the to arms that forms the "U" behaves as two separate syncronized snakes.
--
function Snake:update_joint_positions_grasping_locomotion(time)



    -- joint_count must be an odd number
    local mid = math.floor((self.joint_count / 2)) + 1


    -- Update the vertical joints. Each arm from the middle is treated as two syncronized snakes.
    -- This sets the same parameters for each joint starting from the first and last joint and 
    -- moves innvards towards the bend.
    for i=1,mid-1,1 do 
        simSetJointTargetPosition(self.joints_vertical[i],
            self._amplitude_vertical * math.sin(time * self._speed_vertical + self._phase_0 + i * self._phase_vertical))

        local j = self.joint_count + 1 - i -- The first joint starting from the back
        simSetJointTargetPosition(self.joints_vertical[j],
            self._amplitude_vertical * math.sin(time * self._speed_vertical + self._phase_0 + i * self._phase_vertical))
    end

    local bending = self:get_current_bending_table()

    -- Update the horizontal joints.
    for i=1, mid-2,1 do 

        local j = self.joint_count - i -- the second joint from the end. The first is not used.

        -- Use the control parameters for all modes except for the turning mode. The turning mode
        -- uses the bending table.
        if(self.moving_mode ~= Snake.MODE_TURNING) then
            simSetJointTargetPosition(self.joints_horizontal[i],
                self._amplitude_horizontal * math.sin(time * self._speed_horizontal + self._phase_0 + i * self._phase_horizontal + self._phase_diff_vertical_horizontal))

            -- The same parameters as the other arm, but with oposite sign for the amplitude.
            simSetJointTargetPosition(self.joints_horizontal[j],
                -1*self._amplitude_horizontal* math.sin(time * self._speed_horizontal + self._phase_0 + i * self._phase_horizontal + self._phase_diff_vertical_horizontal))

        else
            simSetJointTargetPosition(self.joints_horizontal[i], bending[i])

            -- The same parameters as the other arm, but with oposite sign.
            simSetJointTargetPosition(self.joints_horizontal[j], -bending[j])
        end

    end

    simSetJointTargetPosition(self.joint_camera,
        self._amplitude_vertical / 1.6 * math.sin(time * self._speed_vertical + self._phase_0 + self._phase_vertical + self._phase_camera))

end


