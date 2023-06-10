
-- Indexes used in the return value from the vision sensor.
-- http://www.coppeliarobotics.com/helpFiles/en/apiFunctions.htm#simReadVisionSensor
--
local BLOB_COUNT = 1
local BLOB_VALUE_COUNT = 2
-- The blob indexes
local BLOB_ORIENTATION = 2
local BLOB_X_POS = 3
local BLOB_Y_POS = 4
local BLOB_WIDTH = 5
local BLOB_HEIGHT = 6


-- Colors constants for the blobs
Blob = {}
Blob.UNKNOWN_COLOR = 0
Blob.RED = 1
Blob.GREEN = 2
Blob.BLUE = 3


VisionSensor = {}


-- 
-- Creates a vision sensor object that is used to read a vision sensor.
--
function VisionSensor:new(sensor)
    local object = {_sensor = sensor}

    object._resolution = simGetVisionSensorResolution(sensor)

    setmetatable(object, self)
    self.__index = self
    return object
end


-- 
-- Returns all table of all the blobs currently found by the vision sensor.
--
-- The tables has the following structure:
-- blobs.count = number of count
-- blobs[1] = blob nr 1
-- blobs[2] = blob nr 2
-- ...
--
-- Each blob has the following values:
-- blob.x = x position  of the center, range 0-1.
-- blob.y = y position of the center, range 0-1.
-- blob.width = the width of the blob, range 0-1.
-- blob.height = the height of the blob, range 0-1.
-- blob.orientation = the orientation of the blob. range [-pi:pi]  
-- blob.color = Blob.RED|Blob.GREEN|Blob.BLUE|Blob.UNKNOWN_COLOR
--
function VisionSensor:find_blobs()

    local _, _, values = simReadVisionSensor(self._sensor)
    local vcount = values[BLOB_VALUE_COUNT]

    local blobs = {count = values[BLOB_COUNT]}

    for i=1,values[BLOB_COUNT],1 do

        local blob = {}

        local base_pos = (i-1)*values[BLOB_VALUE_COUNT] + 2

        blob.x = values[base_pos + BLOB_X_POS]
        blob.y = values[base_pos + BLOB_Y_POS]
        blob.width = values[base_pos + BLOB_WIDTH]
        blob.height = values[base_pos + BLOB_HEIGHT]
        blob.orientation = values[base_pos + BLOB_ORIENTATION]

        if(blob.width > blob.height) then
            -- local tmp = blob.width
            -- blob.width = blob.height
            -- blob.height = tmp
            blob.orientation = blob.orientation + math.pi/2
        end

        blob.color = self:_read_blob_color(blob)

        blobs[i] = blob
    end

    return blobs

end

--
-- Returns the first blob that matches the given color
-- or nil of there is no match.
--
function VisionSensor:find_first_blob_of_color(color)

    local blobs = self:find_blobs()

    if(blobs.count == 0) then
        return nil
    end

    for _, blob in ipairs(blobs) do

        if(blob.color == color) then
            return blob
        end
    end

    return nil

end



--
-- Reads the blob color from the image.
--
function VisionSensor:_read_blob_color(blob)

        local imgColor = simGetVisionSensorImage(self._sensor,
                                            self._resolution[1]*blob.x,
                                            self._resolution[2]*blob.y,
                                            1,1)


        -- We currently expect only pure colors of red, blue or green.
        if(imgColor[Blob.RED] > 0.7) then
            return Blob.RED
        elseif(imgColor[Blob.GREEN] > 0.7) then
            return Blob.GREEN
        elseif(imgColor[Blob.BLUE] > 0.7) then
            return Blob.BLUE
        else
            return Blob.UNKNOWN_COLOR
        end
end


