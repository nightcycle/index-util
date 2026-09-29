--!strict
-- Services
-- Packages
local TypeUnionLib = require(script.Parent.TypeUnionLib)
local Option = TypeUnionLib.Option
local Future = TypeUnionLib.Future
local Result = TypeUnionLib.Result
-- Modules
-- Types
export type ToDo<V, Progress...> = TypeUnionLib.ToDo<V, Progress...>
export type Result<V, E> = TypeUnionLib.Result<V, E>
export type Option<V> = TypeUnionLib.Option<V>
-- Constants
local INF_WARN_AT = 20
-- Variables
-- References
-- Private Functions
function yieldUntil<V>(fn: () -> V?, duration: number?, warnMsg: string): V?
	local v = fn()
	do
		local start = tick()
		local didWarn = false
		while v == nil do
			local elapsedT = tick() - start
			if duration and elapsedT > duration then
				break
			elseif elapsedT > INF_WARN_AT then
				if not didWarn then
					didWarn = true
					warn(warnMsg)
				end
			end
			task.wait()
			v = fn()
		end
	end
	return v
end
-- Class
local Util = {}

function Util.findFirstLocalPath(
	root: Instance,
	path: string,
	separator: string?,
	filteredInitialKeys: { string }?
): Instance?
	local keys = string.split(path, separator or "/")
	if filteredInitialKeys then
		for i, v in filteredInitialKeys do
			if keys[1] == v then
				table.remove(keys, 1)
				break
			end
		end
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

function Util.findFirstPath(path: string, separator: string?): Instance?
	return Util.findFirstLocalPath(game, path, separator, { "src", "game", ".", "", "@game" })
end

Util.waitForLocalPath = function(
	root: Instance,
	path: string,
	duration: number?,
	separator: string?,
	filteredInitialKeys: { string }?
): Instance?
	return yieldUntil(function()
		return Util.findFirstPath(path, separator)
	end, duration, `Infinite yield possible on "{path}"`)
end :: ((
	root: Instance,
	path: string,
	duration: nil,
	separator: string?,
	filteredInitialKeys: { string }?
) -> Instance) & ((
	root: Instance,
	path: string,
	duration: number,
	separator: string?,
	filteredInitialKeys: { string }?
) -> Instance?)

Util.waitForPath = function(
	path: string,
	duration: number?,
	separator: string?,
	filteredInitialKeys: { string }?
): Instance?
	return Util.waitForLocalPath(game, path, duration :: nil, separator, filteredInitialKeys)
end :: ((path: string, duration: nil, separator: string?) -> Instance) & ((path: string, duration: number, separator: string?) -> Instance?)

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

Util.waitForMatch = function<V>(inst: Instance, process: (desc: Instance) -> V?, yield: number?, recursive: boolean?): any
	local isAlive = true
	local deathConnection: RBXScriptConnection
	local onAdded: RBXScriptConnection

	local cleanUp = function(isTimeout: boolean): ()
		if not isAlive then
			return
		end
		isAlive = false
		deathConnection:Disconnect()
		onAdded:Disconnect()
	end
	local isDead = false
	deathConnection = inst.Destroying:Connect(function()
		isDead = true
		cleanUp(false)
	end)

	local match: V?
	local onNewChild = function(descendant: Instance)
		if match then
			return
		end
		local potentialMatch = process(descendant)
		if potentialMatch then
			match = potentialMatch
		end
	end

	if recursive then
		onAdded = inst.DescendantAdded:Connect(onNewChild)
	else
		onAdded = inst.ChildAdded:Connect(onNewChild)
	end

	match = Util.findFirstMatch(inst, process, recursive)
	local outRes: Result<V, nil>? = yieldUntil(function(): Result<V, nil>?
		if isDead then
			return Result.err(nil)
		elseif match then
			return Result.ok(match)
		end
		return nil
	end, yield, `Infinite yield possible on waitForMatch({inst:GetFullName()})`)
	if outRes then
		if outRes.IsOk then
			return outRes.Value
		elseif not yield then
			error(`instance {inst:GetFullName()} was destroyed before match found`)
		else
			return nil
		end
	else
		return nil
	end
end :: (<V>(inst: Instance, process: (desc: Instance) -> V?, yield: nil, recursive: boolean?) -> V) & (<V>(
	inst: Instance,
	process: (desc: Instance) -> V?,
	yield: number,
	recursive: boolean?
) -> V?)

return Util
