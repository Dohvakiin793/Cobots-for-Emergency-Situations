-- 
-- Code for controlling the snake from the keyboard. 
--



KeyboardControl = {}

-- 
-- Creates a new keyboard object. The read_simulator_messages method should be called repeatedly on each
-- actuation event.
--
function KeyboardControl:new()

    local object = {}

    object._actions = {}

    setmetatable(object, self)
    self.__index = self

    return object
end



--
-- Reads and handles the keypress events
-- 
function KeyboardControl:read_simulator_messages()

    message, data, _ = simGetSimulatorMessage()
    if message == sim_message_keypress then
        self:on_keypress(data[1])
    end

end


-- 
-- Adds a new action to the provided key code. 
-- The handler is a function that will be called when the key is
-- pressed.
--
function KeyboardControl:add_action(key_code, handler)
    self._actions[key_code] = handler
end


--
-- Executes the action associated with the given key
-- 
function KeyboardControl:on_keypress(key)

    -- simAddStatusbarMessage(key)

    -- Execute any actions that are added
    if(self._actions[key] ~= nil) then
        self._actions[key]()
        return
    end
end
