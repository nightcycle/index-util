--!strict
-- Services
-- Packages
local Signal = require("@wally/Signal")
-- Modules
-- Types
-- Constants
local DURATION = 10
local LOG_ENABLED = false
-- Variables
-- References
-- Private Functions
local function log(...)
	if LOG_ENABLED then
		print(...)
	end
end
-- Class
local Util = {}

function Util.waitForMatch<V>(
	inst: Instance,
	process: (desc: Instance) -> V?,
	yield: number?,
	recursive: boolean?
): V?
	local isAlive = true
	local deathConnection: RBXScriptConnection
	local onAdded: RBXScriptConnection
	local signal = Signal.new()

	local thread: thread?

	local cleanUp = function(isTimeout: boolean): ()
		if not isAlive then
			return
		end
		log(`cleaning Up waitForMatch`)
		isAlive = false
		deathConnection:Disconnect()
		onAdded:Disconnect()
		signal:Fire()
		signal:Destroy()
		if thread and isTimeout == false then
			task.cancel(thread)
		end
	end
	deathConnection = inst.Destroying:Connect(function()
		cleanUp(false)
	end)

	if yield then
		thread = task.delay(yield, function()
			cleanUp(true)
		end)
	end

	local match: V?

	onAdded = inst.DescendantAdded:Connect(function(descendant: Instance)
		if match then
			return
		end
		local potentialMatch = process(descendant)
		if potentialMatch then
			log(`found match`)
			match = potentialMatch
			signal:Fire()
		end
	end)

	match = Util.findFirstMatch(inst, process, recursive)
	if not match then
		signal:Wait()
	end

	cleanUp(false)
	return match
end

function Util.findFirstMatch<V>(inst: Instance, process: (desc: Instance) -> V?, recursive: boolean?): V?
	if recursive then
		for i, v in ipairs(inst:GetDescendants()) do
			local result = process(v)
			if result then
				return result
			end
		end
	else
		for i, v in ipairs(inst:GetChildren()) do
			local result = process(v)
			if result then
				return result
			end
		end
	end
	return nil
end


function Util.findFirstPath(path: string): Instance?
	local keys = string.split(path, "/")
	if keys[1] == "game" then
		table.remove(keys, 1)
	end
	local source: Instance = game
	local function index(i: number): Instance?
		local key = keys[i]
		if not key then
			return source :: any
		end

		local child = source:FindFirstChild(key)
		if not child then
			return nil
		end
		assert(child)
		source = child
		return index(i + 1)
	end
	return index(1)
end

function Util.waitForPath(path: string, duration: number?): Instance
	local keys = string.split(path, "/")
	if keys[1] == "game" then
		table.remove(keys, 1)
	end
	local source: Instance = game
	local function index(i: number): Instance
		local key = keys[i]
		if not key then
			return source :: any
		end

		local child = source:WaitForChild(key, duration or DURATION)
		assert(child, `no instance at "{key}" for path "{path}" under {source:GetFullName()}`)
		source = child
		return index(i + 1)
	end
	return index(1)
end

function Util.waitForLocalPath(origin: Instance, path: string, duration: number?): Instance
	local keys = string.split(path, "/")
	if keys[1] == "." then
		table.remove(keys, 1)
	end
	local source: Instance = origin
	local function index(i: number): Instance
		local key = keys[i]
		if not key then
			return source :: any
		end

		local child = source:WaitForChild(key, duration or DURATION)
		assert(child, `no instance at "{key}" for path "{path}" under {source:GetFullName()}`)
		source = child
		return index(i + 1)
	end
	return index(1)
end

function Util.findFirstLocalPath(origin: Instance, path: string): Instance?
	local keys = string.split(path, "/")
	if keys[1] == "." then
		table.remove(keys, 1)
	end
	local source: Instance = origin
	local function index(i: number): Instance?
		local key = keys[i]
		if not key then
			return source :: any
		end

		local child = source:FindFirstChild(key)
		if not child then
			return nil
		end
		assert(child)
		source = child
		return index(i + 1)
	end
	return index(1)
end

return Util
