Replace remoteAPI.so file with

Case 1 video: https://drive.google.com/file/d/1BvTfDQa4VVtLBkknXYZHy67oE61SMpZNe/view?usp=sharing

Snake robot simulated in V-REP
==============================

How to run the simulation in V-REP
----------------------------------

You first need to open one of the scenario v-rep .ttt files in v-rep. Then you need
to locate the snake object in the "Scene hierarchy" list. Click on the text-file icon
next to the snake object to open the script editor. In the line which starts
with "package.path = " you need to replace "<absolute-path-to-code>" with 
the absolute path to the directory that contains the code. The end result should
be something like:
package.path = package.path .. ';/home/myuser/myfolder/snakeproject/?.lua'

Save the changes and the simulation should now be working.




Short explanation of how the code is structured.
--------------------------------------------------


Because of the binary file format (ttt) used by v-rep most of the code is not written
in the v-rep script files. Instead a minimum of setup code is written in the script files and
the rest is written in external plain text lua source files. This makes the code better suited
for version control software. 

For the script to work the child script associated with the snake object must be updated with
the path to the folder containing the lua source files. 

A scenario object is created in the child script file and this is called whenever child script is called by
simulation environment. The scenario object creates the snake object and everything else that us needed 
for the scenario. It will also make sure that theses objects are updated as needed.

The snake object has various methods to set different kind of control parameter that will
control how the snake moves. The update_joint_positions* will be called from the update method
and uses the parameters to update the positions of the joints to make the snake move.


The snake logic is implemented in the file logic.lua. This file have multiple functions 
that implements a single tasks. This can be for example line following or random movement. When certain
condition happens theses function will create events. Other code can listen for these events 
and take actions when they happen.


The autonomous behaviour of the snake is implemented in what is called a planner. The
planner uses one or more of the logic functions to fulfil the planner's objective. The planner 
listens for the logic task's events and takes appropriate action when an event occur. By
combining the logic function the autonomous behaviour can be implemented as a series
of simple tasks executed one after another.



Keyboard controll
-----------------

When the scenario is loaded into vrep by default the snake starts in manual model. In manual mode the 
snake have the following basic movements can be controlled by the keyboard:

Key:
t    -  Enables turning mode
s    -  Enables sidewinding mode
r    -  Enables a slow rolling mode
p    -  Enables a faster rolling mode
o    -  Enables a rotation mode
e    -  Enables a side shifting mode

When in each of theses modes the arrow keys can be used to control the snake.
How the snake reacts to the arrow keys depends on the current moving mode

left  - turns to the left, rolls to the left, rotates to the left, etc...
right - turns to the right, rolls to the right, rotates to the right, etc...
up    - moves forward
down  - moves backwards


other actions:

q     - Stops and straightens the snake.



To switch to the autonomous planner use the upper case M key. Pushing this multiple times
will toggle between manual and autonomous mode.


Switching between manual and autonomous mode:

M   - Start the autonomous planner. (Or switch back to the manual planner)



When in manual mode some extra actions are available depending on the scenario.

I   - Switch to idle mode. The snake will stop in the current position and do nothing.
O   - Track the current active target object. If the target is lost it will stop and wait for input
P   - Performs the pre grasping sequence. Expects the object to be in front of the snake. Stops when done.
G   - Do the grasping sequence.
D   - Drops the object. Expects the drop zone to be in front of the snake before enabled.


Only in the line following scenario:

L   - Follow the line. If the line is lost it will stop and wait for input


