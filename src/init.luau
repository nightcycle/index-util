--!strict
-- Services
-- Packages
local Signal = require("@wally/Signal")
local Option = require("@wally/Option")
local Future = require("@wally/Future")
-- Modules
-- Types
type Future<V> = Future.Future<V>
type Option<V> = Option.Option<V>
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

function Util.matchChildAsync<V>(inst: Instance, process: (desc: Instance) -> V?, yield: Option<number>): Future<Option<V>>
	return Future.from(function()
		return Option.try(function()
			return Util.waitForMatch(inst, process, yield:unwrapOr(nil :: any) :: number?, false)
		end)
	end)
end

function Util.matchDescendantAsync<V>(inst: Instance, process: (desc: Instance) -> V?, yield: Option<number>): Future<Option<V>>
	return Future.from(function()
		return Option.try(function()
			return Util.waitForMatch(inst, process, yield:unwrapOr(nil :: any) :: number?, true)
		end)
	end)
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

function Util.matchChild<V>(inst: Instance, process: (desc: Instance) -> V?): Option<V>
	return Option.try(function()
		return Util.findFirstMatch(inst, process, false)
	end)
end

function Util.matchDescendant<V>(inst: Instance, process: (desc: Instance) -> V?): Option<V>
	return Option.try(function()
		return Util.findFirstMatch(inst, process, true)
	end)
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

function Util.matchPath(path: string): Option<Instance>
	return Option.try(function()
		return Util.findFirstPath(path)
	end)
end

function Util.waitForPath(path: string, duration: number?): Instance?
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

function Util.matchPathAsync(path: string, duration: Option<number>): Future<Option<Instance>>
	return Future.from(function()
		return Option.try(function()
			return Util.waitForPath(path, duration:unwrapOr(nil :: any) :: number?)
		end)
	end)
end

function Util.waitForLocalPath(root: Instance, path: string, duration: number?): Instance?
	local keys = string.split(path, "/")
	if keys[1] == "." then
		table.remove(keys, 1)
	end
	local source: Instance = root
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

function Util.matchLocalPathAsync(root: Instance, path: string, duration: Option<number>): Future<Option<Instance>>
	return Future.from(function()
		return Option.try(function()
			return Util.waitForLocalPath(root, path, duration:unwrapOr(nil :: any) :: number?)
		end)
	end)
end

function Util.findFirstLocalPath(root: Instance, path: string): Instance?
	local keys = string.split(path, "/")
	if keys[1] == "." then
		table.remove(keys, 1)
	end
	local source: Instance = root
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

function Util.matchLocalPath(root: Instance, path: string): Option<Instance>
	return Option.try(function()
		return Util.findFirstLocalPath(root, path)
	end)
end

return Util
